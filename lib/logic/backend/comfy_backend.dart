// ==================== Comfy Backend ==================== //
//
// ComfyUI implementation of ImageBackend: health check, image upload,
// editor-graph -> API-graph conversion + queueing, history polling / output
// extraction, and interrupt. Live WebSocket progress (ComfyProgressService)
// plugs into fetchProgress()/generate() when connected; when it isn't, this
// falls back to bounded /history polling so generation still completes.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:sd_companion/logic/backend/backend_capabilities.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/image_backend.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/comfy/comfy_graph_converter.dart';
import 'package:sd_companion/logic/comfy/comfy_node_schema.dart';
import 'package:sd_companion/logic/comfy/comfy_object_info_client.dart';
import 'package:sd_companion/logic/comfy/comfy_progress_service.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/models/generation_models.dart';

class ComfyBackend implements ImageBackend {
  final http.Client _client = http.Client();
  final ComfyProgressService progressService = ComfyProgressService();

  @override
  BackendKind get kind => BackendKind.comfy;

  @override
  BackendCapabilities get capabilities => BackendCapabilities.comfy;

  @override
  ServerProfile get profile => ServerProfile(
    kind: BackendKind.comfy,
    host: globalComfyServerIP.value,
    port: globalComfyServerPort.value,
  );

  @override
  Future<bool> checkStatus() async {
    try {
      final response = await _client
          .get(profile.httpUri('/system_stats'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> interruptGeneration() async {
    try {
      await _client.post(profile.httpUri('/interrupt'));
    } catch (e) {
      throw BackendException(
        'Failed to interrupt generation: $e',
        kind: BackendErrorKind.connection,
      );
    }
  }

  @override
  Future<GenerationProgress> fetchProgress() async =>
      progressService.current ?? GenerationProgress.idleFor(BackendKind.comfy);

  @override
  void disposeProgress() => progressService.dispose();

  // ===== Generation ===== //

  @override
  Future<GenerationOutcome> generate(GenerationRequest request) async {
    final workflowService = ComfyWorkflowService.instance;
    final record = workflowService.activeRecord;
    if (record == null) {
      throw const BackendException(
        'No ComfyUI workflow selected. Import and select a workflow first.',
        kind: BackendErrorKind.validation,
      );
    }

    final detected = workflowService.activeDetected.value;
    if (detected == null) {
      throw BackendException(
        workflowService.activeError.value ?? 'This workflow could not be analyzed',
        kind: BackendErrorKind.validation,
      );
    }
    final positive = detected.positivePrompt;
    if (positive == null) {
      throw const BackendException(
        'Could not find an editable prompt widget in this workflow',
        kind: BackendErrorKind.validation,
      );
    }

    final overrides = <String, dynamic>{
      '${positive.node.id}:${positive.input.name}': request.prompt,
    };

    final negative = detected.negativePrompt;
    if (negative != null) {
      overrides['${negative.node.id}:${negative.input.name}'] = globalNegativePrompt;
    }

    final primaryImage = detected.primaryImage;
    if (primaryImage != null) {
      final uploadBytes = detected.maskSupported && request.maskBytes != null
          ? _embedMaskAsAlpha(request.imageBytes, request.maskBytes!)
          : request.imageBytes;
      final uploaded = await _uploadImage(uploadBytes, primaryImage.node.id);
      overrides['${primaryImage.node.id}:${primaryImage.input.name}'] = uploaded;
    }

    for (final extraImage in detected.additionalImages) {
      final extra = request.namedImages['${extraImage.node.id}'];
      if (extra != null) {
        final uploaded = await _uploadImage(extra, extraImage.node.id);
        overrides['${extraImage.node.id}:${extraImage.input.name}'] = uploaded;
      }
    }

    // ComfyUI caches node outputs by their resolved input values, not by
    // request - it has no idea a "regenerate" happened and will silently
    // return the previous run's cached image if nothing actually changed.
    // The stored seed value never changes on its own (the "randomize" flag
    // is purely metadata this app tracks; only the real ComfyUI frontend's
    // JS re-rolls it, and only *after* a run completes, for next time), so
    // a same-image-same-prompt regenerate with Random seed would otherwise
    // resubmit an identical graph forever. Roll a fresh seed in as an
    // override (not persisted to the saved workflow) whenever the widget is
    // flagged randomize, so every such generation is actually novel.
    for (final widget in detected.samplerSettings) {
      if (widget.controlAfterGenerateSlotIndex == null || !widget.isRandomized) continue;
      overrides['${widget.node.id}:${widget.input.name}'] = _randomSeedValue();
    }

    final schemaProvider = HttpComfyNodeSchemaProvider(profile);
    final converter = ComfyGraphConverter(schemaProvider);
    final ComfyGraphConversionResult conversion;
    try {
      conversion = await converter.convert(record.current, overrides: overrides);
    } on ComfyWorkflowParseException catch (e) {
      throw BackendException(e.message, kind: BackendErrorKind.validation);
    }

    final clientId = progressService.ensureClientId();
    // Force a fresh socket before queueing so the connection is verified
    // alive when ComfyUI starts sending "executing"/"progress" events and
    // KSampler preview frames - reusing a socket that merely *looks*
    // connected (e.g. silently dropped while backgrounded) would otherwise
    // leave the progress overlay stuck with no updates for the whole run.
    // Best-effort: a failed connection never blocks generation, since
    // _awaitHistory below still drives completion via HTTP polling
    // regardless.
    await progressService.connect(profile, force: true);
    final promptId = await _queuePrompt(conversion.apiGraph, clientId);

    progressService.beginTracking(promptId);
    try {
      final history = await _awaitHistory(promptId);
      final images = _extractOutputImages(
        history: history,
        promptId: promptId,
        workflowId: record.id,
        promptSnapshot: request.prompt,
        negativeSnapshot: globalNegativePrompt,
      );
      if (images.isEmpty) {
        throw const BackendException(
          'ComfyUI finished but returned no image outputs',
          kind: BackendErrorKind.server,
        );
      }
      return GenerationOutcome(images: images);
    } finally {
      progressService.endTracking();
    }
  }

  // ===== SeedVR2 Upscale ===== //
  //
  // Unlike the main txt2img/img2img/inpainting flow, this doesn't run a
  // user-imported workflow - it's a small, fixed IMAGE->IMAGE pipeline
  // (LoadImage -> SeedVR2TilingUpscaler -> SaveImage) bundled with the app,
  // matching the same UI the Forge upscale modal already offers. It reuses
  // all the same queueing/history/progress machinery as generate() rather
  // than duplicating it.

  static const _kUpscaleWorkflowAsset = 'assets/comfy/seedvr2_upscale.json';
  ComfyWorkflowDocument? _upscaleWorkflowTemplate;

  Future<ComfyWorkflowDocument> _loadUpscaleWorkflow() async {
    // Cache the parsed template, but always hand back a clone - the graph
    // converter overrides values on a per-call basis and must never mutate
    // shared state between concurrent/repeated upscale calls.
    _upscaleWorkflowTemplate ??= ComfyWorkflowDocument.parse(
      await rootBundle.loadString(_kUpscaleWorkflowAsset),
    );
    return _upscaleWorkflowTemplate!.clone();
  }

  /// Runs the bundled SeedVR2 workflow against [imageBytes], targeting
  /// [resolution] pixels on the image's longest side. Returns a ComfyUI
  /// `/view` URL for the upscaled output - safe to hand straight to
  /// `GeneratedImage.local`, which displays network URLs the same way it
  /// displays data URLs.
  Future<String> upscaleSeedVR2({
    required Uint8List imageBytes,
    required int resolution,
    Function(Map<String, dynamic> progressData)? onProgress,
  }) async {
    final doc = await _loadUpscaleWorkflow();

    ComfyEditorNode? loadImageNode;
    ComfyEditorNode? upscalerNode;
    for (final node in doc.nodes) {
      if (node.type == 'LoadImage') loadImageNode = node;
      if (node.type == 'SeedVR2TilingUpscaler') upscalerNode = node;
    }
    if (loadImageNode == null || upscalerNode == null) {
      throw const BackendException(
        'Bundled SeedVR2 upscale workflow is missing required nodes',
        kind: BackendErrorKind.validation,
      );
    }

    final schemaProvider = HttpComfyNodeSchemaProvider(profile);
    final upscalerSchema = await schemaProvider.schemaFor(upscalerNode.type);
    if (!upscalerSchema.known || upscalerSchema.inputByName('new_resolution') == null) {
      throw const BackendException(
        'SeedVR2TilingUpscaler node is not available on this ComfyUI server. '
        'Install moonwhaler/comfyui-seedvr2-tilingupscaler and its models.',
        kind: BackendErrorKind.unsupported,
      );
    }

    final clientId = progressService.ensureClientId();
    await progressService.connect(profile, force: true);

    final uploadedFilename = await _uploadImage(imageBytes, loadImageNode.id);
    final overrides = <String, dynamic>{
      '${loadImageNode.id}:image': uploadedFilename,
      '${upscalerNode.id}:new_resolution': resolution,
    };

    final converter = ComfyGraphConverter(schemaProvider);
    final ComfyGraphConversionResult conversion;
    try {
      conversion = await converter.convert(doc, overrides: overrides);
    } on ComfyWorkflowParseException catch (e) {
      throw BackendException(e.message, kind: BackendErrorKind.validation);
    }

    final promptId = await _queuePrompt(conversion.apiGraph, clientId);
    progressService.beginTracking(promptId);

    void Function()? unsubscribe;
    if (onProgress != null) {
      void listener() {
        final p = progressService.notifier.value;
        onProgress({'progress': p.fraction, 'status': _describeUpscaleProgress(p)});
      }

      progressService.notifier.addListener(listener);
      unsubscribe = () => progressService.notifier.removeListener(listener);
    }

    try {
      final history = await _awaitHistory(promptId);
      final images = _extractOutputImages(
        history: history,
        promptId: promptId,
        workflowId: 'seedvr2_upscale',
        promptSnapshot: '',
        negativeSnapshot: '',
      );
      if (images.isEmpty) {
        throw const BackendException(
          'SeedVR2 upscale finished but returned no image output',
          kind: BackendErrorKind.server,
        );
      }
      return images.first.imageUrl;
    } finally {
      unsubscribe?.call();
      progressService.endTracking();
    }
  }

  String _describeUpscaleProgress(GenerationProgress p) => switch (p.state) {
    GenerationState.queued => 'Queued',
    GenerationState.running => 'Upscaling',
    GenerationState.completed => 'Finishing',
    _ => 'Processing',
  };

  // ===== Prompt Enhance / Image-to-Prompt ===== //
  //
  // Two more small bundled utility workflows, same shape as the upscale one
  // above: fixed IMAGE/STRING->STRING pipelines built on the QwenVL-GGUF
  // custom nodes (1038lab/ComfyUI-QwenVL), driven purely by widget-name
  // overrides resolved against the live server's own schema rather than
  // any positional assumption - the SeedVR2 workflow already showed what
  // goes wrong when that's assumed instead of verified. Both terminate in
  // a core `PreviewAny` node, whose ComfyUI-side implementation reports its
  // stringified value at `outputs[nodeId]['text'][0]` in `/history` (it has
  // no image output to extract, unlike the rest of this backend).

  static const _kPromptEnhanceWorkflowAsset = 'assets/comfy/prompt_enhance.json';
  static const _kImg2PromptWorkflowAsset = 'assets/comfy/img2prompt.json';
  ComfyWorkflowDocument? _promptEnhanceTemplate;
  ComfyWorkflowDocument? _img2PromptTemplate;

  Future<ComfyWorkflowDocument> _loadPromptEnhanceWorkflow() async {
    _promptEnhanceTemplate ??= ComfyWorkflowDocument.parse(
      await rootBundle.loadString(_kPromptEnhanceWorkflowAsset),
    );
    return _promptEnhanceTemplate!.clone();
  }

  Future<ComfyWorkflowDocument> _loadImg2PromptWorkflow() async {
    _img2PromptTemplate ??= ComfyWorkflowDocument.parse(
      await rootBundle.loadString(_kImg2PromptWorkflowAsset),
    );
    return _img2PromptTemplate!.clone();
  }

  /// Rewrites [prompt] through the bundled QwenVL prompt-enhancer workflow.
  Future<String> enhancePrompt(String prompt) async {
    final doc = await _loadPromptEnhanceWorkflow();

    ComfyEditorNode? enhancerNode;
    for (final node in doc.nodes) {
      if (node.type == 'AILab_QwenVL_GGUF_PromptEnhancer') enhancerNode = node;
    }
    if (enhancerNode == null) {
      throw const BackendException(
        'Bundled prompt-enhance workflow is missing its enhancer node',
        kind: BackendErrorKind.validation,
      );
    }

    final schemaProvider = HttpComfyNodeSchemaProvider(profile);
    final schema = await schemaProvider.schemaFor(enhancerNode.type);
    if (!schema.known || schema.inputByName('prompt_text') == null) {
      throw const BackendException(
        'AILab_QwenVL_GGUF_PromptEnhancer node is not available on this ComfyUI server. '
        'Install 1038lab/ComfyUI-QwenVL and its GGUF models.',
        kind: BackendErrorKind.unsupported,
      );
    }

    return _runTextWorkflow(doc, schemaProvider, {
      '${enhancerNode.id}:prompt_text': prompt,
    });
  }

  /// Captions [imageBytes] through the bundled QwenVL image-to-prompt
  /// workflow.
  Future<String> describeImage(Uint8List imageBytes) async {
    final doc = await _loadImg2PromptWorkflow();

    ComfyEditorNode? loadImageNode;
    ComfyEditorNode? captionNode;
    for (final node in doc.nodes) {
      if (node.type == 'LoadImage') loadImageNode = node;
      if (node.type == 'AILab_QwenVL_GGUF_Advanced') captionNode = node;
    }
    if (loadImageNode == null || captionNode == null) {
      throw const BackendException(
        'Bundled img2prompt workflow is missing required nodes',
        kind: BackendErrorKind.validation,
      );
    }

    final schemaProvider = HttpComfyNodeSchemaProvider(profile);
    final schema = await schemaProvider.schemaFor(captionNode.type);
    if (!schema.known) {
      throw const BackendException(
        'AILab_QwenVL_GGUF_Advanced node is not available on this ComfyUI server. '
        'Install 1038lab/ComfyUI-QwenVL and its GGUF models.',
        kind: BackendErrorKind.unsupported,
      );
    }

    final uploadedFilename = await _uploadImage(imageBytes, loadImageNode.id);
    return _runTextWorkflow(doc, schemaProvider, {
      '${loadImageNode.id}:image': uploadedFilename,
    });
  }

  /// Shared queue/history plumbing for the two text-output workflows above.
  Future<String> _runTextWorkflow(
    ComfyWorkflowDocument doc,
    ComfyNodeSchemaProvider schemaProvider,
    Map<String, dynamic> overrides,
  ) async {
    final clientId = progressService.ensureClientId();
    await progressService.connect(profile, force: true);

    final converter = ComfyGraphConverter(schemaProvider);
    final ComfyGraphConversionResult conversion;
    try {
      conversion = await converter.convert(doc, overrides: overrides);
    } on ComfyWorkflowParseException catch (e) {
      throw BackendException(e.message, kind: BackendErrorKind.validation);
    }

    final promptId = await _queuePrompt(conversion.apiGraph, clientId);
    progressService.beginTracking(promptId);
    try {
      final history = await _awaitHistory(promptId);
      final text = _extractOutputText(history);
      if (text == null || text.trim().isEmpty) {
        throw const BackendException(
          'ComfyUI finished but returned no text output',
          kind: BackendErrorKind.server,
        );
      }
      return text.trim();
    } finally {
      progressService.endTracking();
    }
  }

  String? _extractOutputText(Map<String, dynamic> history) {
    final outputs = (history['outputs'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final nodeOutputs in outputs.values) {
      final textList = (nodeOutputs as Map<String, dynamic>?)?['text'] as List?;
      if (textList != null && textList.isNotEmpty) {
        return textList.first?.toString();
      }
    }
    return null;
  }

  /// A fresh seed for a "randomize" widget. ComfyUI reports seed's range as
  /// up to 2^64-1, but that doesn't fit safely in Dart's 64-bit signed int
  /// and Random.nextInt is capped at 2^32 anyway - a 32-bit seed space is
  /// still effectively unlimited entropy for the sole purpose here (making
  /// sure the submitted graph differs from the last run).
  int _randomSeedValue() => Random().nextInt(0xFFFFFFFF);

  /// ComfyUI's `LoadImage` derives its MASK output from the uploaded PNG's
  /// alpha channel (`mask = 1 - alpha/255`), the same convention its own
  /// mask editor uses ("clipspace-painted-masked" files). The app's canvas
  /// produces a black/white mask (white = paint here, matching Forge's
  /// convention) - this embeds it as inverted alpha so a plain LoadImage
  /// node picks it up without any dedicated mask-upload endpoint.
  Uint8List _embedMaskAsAlpha(Uint8List imageBytes, Uint8List maskBytes) {
    final source = img.decodeImage(imageBytes);
    final maskImage = img.decodeImage(maskBytes);
    if (source == null || maskImage == null) {
      throw const BackendException(
        'Could not decode the image or mask for upload',
        kind: BackendErrorKind.validation,
      );
    }
    final mask = (maskImage.width == source.width && maskImage.height == source.height)
        ? maskImage
        : img.copyResize(maskImage, width: source.width, height: source.height);

    final withAlpha = source.numChannels == 4 ? source : source.convert(numChannels: 4);
    for (var y = 0; y < withAlpha.height; y++) {
      for (var x = 0; x < withAlpha.width; x++) {
        final maskLuminance = mask.getPixel(x, y).luminance;
        final alpha = (255 - maskLuminance).clamp(0, 255).toInt();
        final p = withAlpha.getPixel(x, y);
        withAlpha.setPixelRgba(x, y, p.r, p.g, p.b, alpha);
      }
    }
    return Uint8List.fromList(img.encodePng(withAlpha));
  }

  Future<String> _uploadImage(Uint8List bytes, int nodeId) async {
    final uri = profile.httpUri('/upload/image');
    final request = http.MultipartRequest('POST', uri)
      ..fields['overwrite'] = 'true'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'sd_companion_$nodeId.png',
        ),
      );
    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw BackendException(
        'Failed to upload image: $e',
        kind: BackendErrorKind.connection,
      );
    }
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw BackendException(
        'Failed to upload image: HTTP ${response.statusCode}',
        kind: BackendErrorKind.server,
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['name'] as String;
  }

  Future<String> _queuePrompt(Map<String, dynamic> apiGraph, String clientId) async {
    final response = await _client.post(
      profile.httpUri('/prompt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': apiGraph, 'client_id': clientId}),
    );

    if (response.statusCode != 200) {
      String message = 'ComfyUI rejected the prompt: HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final nodeErrors = decoded['node_errors'] as Map<String, dynamic>?;
        if (nodeErrors != null && nodeErrors.isNotEmpty) {
          final parts = nodeErrors.entries.map((entry) {
            final errors = (entry.value as Map<String, dynamic>)['errors'] as List?;
            final firstMessage = errors != null && errors.isNotEmpty
                ? (errors.first as Map<String, dynamic>)['message']
                : null;
            return 'node ${entry.key}: $firstMessage';
          });
          message = 'ComfyUI validation failed - ${parts.join('; ')}';
        } else if (decoded['error'] != null) {
          message = 'ComfyUI rejected the prompt: ${decoded['error']['message']}';
        }
      } catch (_) {}
      throw BackendException(message, kind: BackendErrorKind.validation);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final promptId = decoded['prompt_id'] as String?;
    if (promptId == null) {
      throw const BackendException(
        'ComfyUI accepted the prompt but returned no prompt_id',
        kind: BackendErrorKind.server,
      );
    }
    return promptId;
  }

  /// Polls `/history/{promptId}` until ComfyUI reports completion, an error,
  /// or the bounded timeout elapses. This is the fallback path used when the
  /// WebSocket isn't connected; when it is, ComfyProgressService's own
  /// "executed"/status events short-circuit sooner via the same endpoint.
  Future<Map<String, dynamic>> _awaitHistory(
    String promptId, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _client
          .get(profile.httpUri('/history/$promptId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final entry = decoded[promptId] as Map<String, dynamic>?;
        if (entry != null) {
          final status = entry['status'] as Map<String, dynamic>?;
          final statusStr = status?['status_str'] as String?;
          if (statusStr == 'error') {
            final messages = (status?['messages'] as List?) ?? const [];
            throw BackendException(
              'ComfyUI reported an execution error: ${messages.isNotEmpty ? messages.last : 'unknown error'}',
              kind: BackendErrorKind.nodeExecution,
            );
          }
          final completed = status?['completed'] as bool? ?? entry['outputs'] != null;
          if (completed) return entry;
        }
      }
      progressService.nudgeRunningIfQueued();
      await Future.delayed(const Duration(milliseconds: 700));
    }
    throw const BackendException(
      'Timed out waiting for ComfyUI to finish generating',
      kind: BackendErrorKind.timeout,
    );
  }

  List<GeneratedImage> _extractOutputImages({
    required Map<String, dynamic> history,
    required String promptId,
    required String workflowId,
    required String promptSnapshot,
    required String negativeSnapshot,
  }) {
    final outputs = (history['outputs'] as Map?)?.cast<String, dynamic>() ?? {};
    final images = <GeneratedImage>[];

    for (final entry in outputs.entries) {
      final nodeOutputs = entry.value as Map<String, dynamic>?;
      final imageList = nodeOutputs?['images'] as List?;
      if (imageList == null) continue;
      for (final imageEntry in imageList) {
        final map = imageEntry as Map<String, dynamic>;
        final filename = map['filename'] as String?;
        if (filename == null) continue;
        final subfolder = map['subfolder'] as String? ?? '';
        final type = map['type'] as String? ?? 'output';
        final url = profile
            .httpUri('/view', {
              'filename': filename,
              'subfolder': subfolder,
              'type': type,
            })
            .toString();
        images.add(GeneratedImage(
          id: '${promptId}_${entry.key}_${images.length}',
          imageUrl: url,
          backend: BackendKind.comfy,
          promptId: promptId,
          workflowId: workflowId,
          outputNodeId: entry.key,
          comfyFilename: filename,
          comfySubfolder: subfolder,
          comfyType: type,
          promptSnapshot: promptSnapshot,
          negativePromptSnapshot: negativeSnapshot,
        ));
      }
    }
    return images;
  }
}
