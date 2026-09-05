// ==================== Comfy Engine ==================== //
//
// ComfyUI implementation of [ImageEngine]: health check, image upload,
// editor-graph -> API-graph conversion + queueing, history polling / output
// extraction, and interrupt.
//
// Three things changed when this moved off the old `ImageBackend`:
//
//  * it reads no globals - the endpoint and the workflow service are
//    constructor arguments, so two engines against two servers can coexist
//    and a test can drive one with no ambient setup;
//  * failures come back as `Err(AppError)` instead of a thrown
//    `BackendException`, so callers cannot forget them;
//  * progress is a broadcast [Stream] rather than a getter to poll.
//
// Live WebSocket progress (ComfyProgressService) drives the stream when
// connected; when it isn't, generation still completes via bounded
// /history polling.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/diagnostics.dart';
import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/data/engines/comfy/comfy_graph_converter.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_object_info_client.dart';
import 'package:sd_companion/data/engines/comfy/comfy_progress_service.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/engine/image_engine.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';

class ComfyEngine
    implements
        ImageEngine,
        PromptRewriteCapable,
        PromptGenerateCapable,
        ImageToTextCapable,
        UpscaleCapable {
  @override
  final EngineEndpoint endpoint;

  final ComfyWorkflowService workflows;
  final ComfyProgressService progressService;

  final http.Client _client;
  final bool _ownsClient;

  ComfyEngine({
    required this.endpoint,
    required this.workflows,
    ComfyProgressService? progressService,
    http.Client? client,
  })  : progressService = progressService ?? ComfyProgressService(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  @override
  EngineKind get kind => EngineKind.comfy;

  @override
  EngineCapabilities get capabilities => EngineCapabilities.comfy;

  // ===== Progress ===== //

  // The service exposes a ValueNotifier; the contract wants a stream that
  // never closes. Bridging here (rather than making the service a stream)
  // keeps the existing listener-based upscale progress hook working.
  StreamController<RunProgress>? _progressController;

  @override
  Stream<RunProgress> get progress {
    final existing = _progressController;
    if (existing != null) return existing.stream;

    late final StreamController<RunProgress> controller;
    void forward() => controller.add(progressService.current);
    controller = StreamController<RunProgress>.broadcast(
      onListen: () => progressService.notifier.addListener(forward),
      onCancel: () => progressService.notifier.removeListener(forward),
    );
    _progressController = controller;
    return controller.stream;
  }

  // ===== Lifecycle ===== //

  @override
  Future<bool> ping() async {
    try {
      final response = await _client
          .get(endpoint.http('/system_stats'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Result<void>> cancel() => guard(() async {
        await _client.post(endpoint.http('/interrupt'));
      });

  @override
  Future<Result<Uint8List>> fetchImageBytes(String url) => guard(() async {
        final response =
            await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw ServerError('Could not fetch image: HTTP ${response.statusCode}');
        }
        return response.bodyBytes;
      });

  @override
  Future<void> dispose() async {
    await _progressController?.close();
    _progressController = null;
    progressService.dispose();
    if (_ownsClient) _client.close();
  }

  // ===== Generation ===== //

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) =>
      guard(() => _generate(spec));

  Future<List<GeneratedImage>> _generate(GenerationSpec spec) async {
    final record = workflows.activeRecord;
    if (record == null) {
      throw const ValidationError(
        'No ComfyUI workflow selected. Import and select a workflow first.',
      );
    }

    final detected = workflows.activeDetected.value;
    if (detected == null) {
      throw ValidationError(
        workflows.activeError.value ?? 'This workflow could not be analyzed',
      );
    }
    final positive = detected.positivePrompt;
    if (positive == null) {
      throw const ValidationError(
        'Could not find an editable prompt widget in this workflow',
      );
    }

    final overrides = <String, dynamic>{
      '${positive.node.id}:${positive.input.name}': spec.prompt,
    };

    final negative = detected.negativePrompt;
    if (negative != null) {
      overrides['${negative.node.id}:${negative.input.name}'] =
          spec.negativePrompt;
    }

    final primaryImage = detected.primaryImage;
    if (primaryImage != null && spec.hasSourceImage) {
      final uploadBytes = detected.maskSupported && spec.hasMask
          ? _embedMaskAsAlpha(spec.sourceImage!, spec.mask!)
          : spec.sourceImage!;
      final uploaded = await _uploadImage(uploadBytes, primaryImage.node.id);
      overrides['${primaryImage.node.id}:${primaryImage.input.name}'] = uploaded;
    }

    for (final extraImage in detected.additionalImages) {
      final extra = spec.namedImages['${extraImage.node.id}'];
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
      if (widget.controlAfterGenerateSlotIndex == null || !widget.isRandomized) {
        continue;
      }
      overrides['${widget.node.id}:${widget.input.name}'] = _randomSeedValue();
    }

    final schemaProvider = HttpComfyNodeSchemaProvider(endpoint);
    final conversion = await _convert(
      record.current,
      schemaProvider,
      overrides,
    );

    final clientId = progressService.ensureClientId();
    // Force a fresh socket before queueing so the connection is verified
    // alive when ComfyUI starts sending "executing"/"progress" events and
    // KSampler preview frames - reusing a socket that merely *looks*
    // connected (e.g. silently dropped while backgrounded) would otherwise
    // leave the progress overlay stuck with no updates for the whole run.
    // Best-effort: a failed connection never blocks generation, since
    // _awaitHistory below still drives completion via HTTP polling
    // regardless.
    await progressService.connect(endpoint, force: true);
    final promptId = await _queuePrompt(conversion.apiGraph, clientId);

    // Previews are unicast to the client_id on the /prompt request. If the
    // socket ever registered a different id, the server sends them into a
    // black hole and it looks exactly like previews being switched off - so
    // the pairing is logged on every run.
    trace('preview',
        'queued promptId=$promptId with clientId=$clientId '
        '(socket uses ${progressService.ensureClientId()})');

    progressService.beginTracking(promptId);
    try {
      final history = await _awaitHistory(promptId);
      final images = _extractOutputImages(
        history: history,
        promptId: promptId,
        prompt: spec.prompt,
        negativePrompt: spec.negativePrompt,
        workflowId: record.id,
      );
      if (images.isEmpty) {
        throw const ServerError('ComfyUI finished but returned no image outputs');
      }
      return images;
    } finally {
      progressService.endTracking();
    }
  }

  // ===== SeedVR2 Upscale ===== //
  //
  // Unlike the main txt2img/img2img/inpainting flow, this doesn't run a
  // user-imported workflow - it's a small, fixed IMAGE->IMAGE pipeline
  // (LoadImage -> SeedVR2TilingUpscaler -> SaveImage) bundled with the app.
  // It reuses all the same queueing/history/progress machinery as generate()
  // rather than duplicating it.

  static const _kUpscaleWorkflowAsset = 'assets/comfy/seedvr2_upscale.json';
  ComfyWorkflowDocument? _upscaleWorkflowTemplate;

  Future<ComfyWorkflowDocument> _loadBundled(
    String asset,
    ComfyWorkflowDocument? cached,
    void Function(ComfyWorkflowDocument) store,
  ) async {
    // Cache the parsed template, but always hand back a clone - the graph
    // converter overrides values on a per-call basis and must never mutate
    // shared state between concurrent/repeated calls.
    if (cached == null) {
      cached = ComfyWorkflowDocument.parse(await rootBundle.loadString(asset));
      store(cached);
    }
    return cached.clone();
  }

  @override
  Future<Result<String>> upscale({
    required Uint8List image,
    required int targetResolution,
    void Function(RunProgress progress)? onProgress,
  }) =>
      guard(() => _upscale(image, targetResolution, onProgress));

  Future<String> _upscale(
    Uint8List imageBytes,
    int resolution,
    void Function(RunProgress)? onProgress,
  ) async {
    final doc = await _loadBundled(
      _kUpscaleWorkflowAsset,
      _upscaleWorkflowTemplate,
      (d) => _upscaleWorkflowTemplate = d,
    );

    final loadImageNode = _findNode(doc, 'LoadImage');
    final upscalerNode = _findNode(doc, 'SeedVR2TilingUpscaler');
    if (loadImageNode == null || upscalerNode == null) {
      throw const ValidationError(
        'Bundled SeedVR2 upscale workflow is missing required nodes',
      );
    }

    final schemaProvider = HttpComfyNodeSchemaProvider(endpoint);
    final upscalerSchema = await schemaProvider.schemaFor(upscalerNode.type);
    if (!upscalerSchema.known ||
        upscalerSchema.inputByName('new_resolution') == null) {
      throw const CapabilityError(
        'SeedVR2TilingUpscaler node is not available on this ComfyUI server. '
        'Install moonwhaler/comfyui-seedvr2-tilingupscaler and its models.',
      );
    }

    final clientId = progressService.ensureClientId();
    await progressService.connect(endpoint, force: true);

    final uploadedFilename = await _uploadImage(imageBytes, loadImageNode.id);
    final conversion = await _convert(doc, schemaProvider, {
      '${loadImageNode.id}:image': uploadedFilename,
      '${upscalerNode.id}:new_resolution': resolution,
    });

    final promptId = await _queuePrompt(conversion.apiGraph, clientId);
    progressService.beginTracking(promptId);

    void Function()? unsubscribe;
    if (onProgress != null) {
      void listener() => onProgress(progressService.current);
      progressService.notifier.addListener(listener);
      unsubscribe = () => progressService.notifier.removeListener(listener);
    }

    try {
      final history = await _awaitHistory(promptId);
      final images = _extractOutputImages(
        history: history,
        promptId: promptId,
        workflowId: 'seedvr2_upscale',
        tool: true,
      );
      if (images.isEmpty) {
        throw const ServerError(
          'SeedVR2 upscale finished but returned no image output',
        );
      }
      return images.first.url;
    } finally {
      unsubscribe?.call();
      progressService.endTracking();
    }
  }

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
  // no image output to extract, unlike the rest of this engine).

  static const _kPromptEnhanceWorkflowAsset = 'assets/comfy/prompt_enhance.json';
  static const _kImg2PromptWorkflowAsset = 'assets/comfy/img2prompt.json';
  static const _kPromptGenerateWorkflowAsset =
      'assets/comfy/prompt_generate.json';
  ComfyWorkflowDocument? _promptEnhanceTemplate;
  ComfyWorkflowDocument? _img2PromptTemplate;
  ComfyWorkflowDocument? _promptGenerateTemplate;

  @override
  Future<Result<String>> rewritePrompt(String prompt) => guard(() async {
        final doc = await _loadBundled(
          _kPromptEnhanceWorkflowAsset,
          _promptEnhanceTemplate,
          (d) => _promptEnhanceTemplate = d,
        );

        final enhancerNode = _findNode(doc, 'AILab_QwenVL_GGUF_PromptEnhancer');
        if (enhancerNode == null) {
          throw const ValidationError(
            'Bundled prompt-enhance workflow is missing its enhancer node',
          );
        }

        final schemaProvider = HttpComfyNodeSchemaProvider(endpoint);
        final schema = await schemaProvider.schemaFor(enhancerNode.type);
        if (!schema.known || schema.inputByName('prompt_text') == null) {
          throw const CapabilityError(
            'AILab_QwenVL_GGUF_PromptEnhancer node is not available on this '
            'ComfyUI server. Install 1038lab/ComfyUI-QwenVL and its GGUF models.',
          );
        }

        return _runTextWorkflow(doc, schemaProvider, {
          '${enhancerNode.id}:prompt_text': prompt,
        });
      });

  @override
  Future<Result<String>> generatePrompt({required int intensity}) =>
      guard(() async {
        final doc = await _loadBundled(
          _kPromptGenerateWorkflowAsset,
          _promptGenerateTemplate,
          (d) => _promptGenerateTemplate = d,
        );

        final generatorNode = _findNode(doc, 'PromptGenerator');
        if (generatorNode == null) {
          throw const ValidationError(
            'Bundled prompt-generate workflow is missing its generator node',
          );
        }

        final schemaProvider = HttpComfyNodeSchemaProvider(endpoint);
        final schema = await schemaProvider.schemaFor(generatorNode.type);
        if (!schema.known) {
          throw const CapabilityError(
            'PromptGenerator node is not available on this ComfyUI server. '
            'Install the prompt-manager custom nodes and an LLM model.',
          );
        }

        // The whole point of this button is a *different* prompt each press,
        // and ComfyUI caches node outputs by their resolved inputs - so the
        // workflow's stored seed would hand back the same sentence forever.
        // Same reasoning as the sampler seed in `generate`.
        final overrides = <String, dynamic>{};
        if (schema.inputByName('seed') != null) {
          overrides['${generatorNode.id}:seed'] = _randomSeedValue();
        }
        // The node's user prompt, which the bundled system prompt reads as
        // an intensity from 1 to 10 and nothing else. A string, because that
        // is the widget's declared type - sending an int would be rejected.
        if (schema.inputByName('prompt') != null) {
          overrides['${generatorNode.id}:prompt'] =
              '${intensity.clamp(1, 10)}';
        }
        return _runTextWorkflow(doc, schemaProvider, overrides);
      });

  @override
  Future<Result<String>> describeImage(Uint8List image) => guard(() async {
        final doc = await _loadBundled(
          _kImg2PromptWorkflowAsset,
          _img2PromptTemplate,
          (d) => _img2PromptTemplate = d,
        );

        final loadImageNode = _findNode(doc, 'LoadImage');
        final captionNode = _findNode(doc, 'AILab_QwenVL_GGUF_Advanced');
        if (loadImageNode == null || captionNode == null) {
          throw const ValidationError(
            'Bundled img2prompt workflow is missing required nodes',
          );
        }

        final schemaProvider = HttpComfyNodeSchemaProvider(endpoint);
        final schema = await schemaProvider.schemaFor(captionNode.type);
        if (!schema.known) {
          throw const CapabilityError(
            'AILab_QwenVL_GGUF_Advanced node is not available on this ComfyUI '
            'server. Install 1038lab/ComfyUI-QwenVL and its GGUF models.',
          );
        }

        final uploadedFilename = await _uploadImage(image, loadImageNode.id);
        return _runTextWorkflow(doc, schemaProvider, {
          '${loadImageNode.id}:image': uploadedFilename,
        });
      });

  /// Shared queue/history plumbing for the two text-output workflows above.
  Future<String> _runTextWorkflow(
    ComfyWorkflowDocument doc,
    ComfyNodeSchemaProvider schemaProvider,
    Map<String, dynamic> overrides,
  ) async {
    final clientId = progressService.ensureClientId();
    await progressService.connect(endpoint, force: true);

    final conversion = await _convert(doc, schemaProvider, overrides);
    final promptId = await _queuePrompt(conversion.apiGraph, clientId);
    progressService.beginTracking(promptId);
    try {
      final history = await _awaitHistory(promptId);
      final text = _extractOutputText(history);
      if (text == null || text.trim().isEmpty) {
        throw const ServerError('ComfyUI finished but returned no text output');
      }
      return text.trim();
    } finally {
      progressService.endTracking();
    }
  }

  // ===== Shared plumbing ===== //

  ComfyEditorNode? _findNode(ComfyWorkflowDocument doc, String type) {
    for (final node in doc.nodes) {
      if (node.type == type) return node;
    }
    return null;
  }

  /// Graph conversion, with the parser's own exception translated into the
  /// app's error taxonomy so callers only ever see [AppError].
  Future<ComfyGraphConversionResult> _convert(
    ComfyWorkflowDocument doc,
    ComfyNodeSchemaProvider schemaProvider,
    Map<String, dynamic> overrides,
  ) async {
    try {
      return await ComfyGraphConverter(schemaProvider)
          .convert(doc, overrides: overrides);
    } on ComfyWorkflowParseException catch (e) {
      throw ValidationError(e.message);
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
      throw const ValidationError('Could not decode the image or mask for upload');
    }
    final mask =
        (maskImage.width == source.width && maskImage.height == source.height)
            ? maskImage
            : img.copyResize(maskImage,
                width: source.width, height: source.height);

    final withAlpha =
        source.numChannels == 4 ? source : source.convert(numChannels: 4);
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
    final request = http.MultipartRequest('POST', endpoint.http('/upload/image'))
      ..fields['overwrite'] = 'true'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'aperture_$nodeId.png',
        ),
      );
    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw UnreachableError('Failed to upload image: $e', cause: e);
    }
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw ServerError(
        'Failed to upload image: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['name'] as String;
  }

  Future<String> _queuePrompt(
    Map<String, dynamic> apiGraph,
    String clientId,
  ) async {
    final response = await _client.post(
      endpoint.http('/prompt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': apiGraph, 'client_id': clientId}),
    );

    if (response.statusCode != 200) {
      throw ValidationError(_describeQueueFailure(response));
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final promptId = decoded['prompt_id'] as String?;
    if (promptId == null) {
      throw const ServerError(
        'ComfyUI accepted the prompt but returned no prompt_id',
      );
    }
    return promptId;
  }

  /// ComfyUI reports validation failures as a per-node error map. Surfacing
  /// the first message per node is what makes a rejected graph debuggable
  /// from the phone instead of just "HTTP 400".
  String _describeQueueFailure(http.Response response) {
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
        return 'ComfyUI validation failed - ${parts.join('; ')}';
      }
      if (decoded['error'] != null) {
        return 'ComfyUI rejected the prompt: ${decoded['error']['message']}';
      }
    } catch (_) {}
    return 'ComfyUI rejected the prompt: HTTP ${response.statusCode}';
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
          .get(endpoint.http('/history/$promptId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final entry = decoded[promptId] as Map<String, dynamic>?;
        if (entry != null) {
          final status = entry['status'] as Map<String, dynamic>?;
          if (status?['status_str'] == 'error') {
            final messages = (status?['messages'] as List?) ?? const [];
            throw ExecutionError(
              'ComfyUI reported an execution error: '
              '${messages.isNotEmpty ? messages.last : 'unknown error'}',
            );
          }
          final completed = status?['completed'] as bool? ?? entry['outputs'] != null;
          if (completed) return entry;
        }
      }
      progressService.nudgeRunningIfQueued();
      await Future.delayed(const Duration(milliseconds: 700));
    }
    throw const TimeoutError('Timed out waiting for ComfyUI to finish generating');
  }

  List<GeneratedImage> _extractOutputImages({
    required Map<String, dynamic> history,
    required String promptId,
    required String workflowId,
    String? prompt,
    String? negativePrompt,
    bool tool = false,
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
        final url = endpoint
            .http('/view', {
              'filename': filename,
              'subfolder': subfolder,
              'type': type,
            })
            .toString();
        final origin = ComfyOrigin(
          promptId: promptId,
          workflowId: workflowId,
          nodeId: entry.key,
          filename: filename,
          subfolder: subfolder,
          type: type,
        );
        images.add(
          tool
              ? GeneratedImage(
                  id: '${promptId}_${entry.key}_${images.length}',
                  url: url,
                  engine: EngineKind.comfy,
                  origin: ImageOrigin.tool,
                  comfy: origin,
                )
              : GeneratedImage.fromRun(
                  url: url,
                  engine: EngineKind.comfy,
                  prompt: prompt,
                  negativePrompt: negativePrompt,
                  comfy: origin,
                ),
        );
      }
    }
    return images;
  }
}
