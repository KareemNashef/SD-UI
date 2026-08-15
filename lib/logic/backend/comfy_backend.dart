// ==================== Comfy Backend ==================== //
//
// ComfyUI implementation of ImageBackend: health check, image upload,
// editor-graph -> API-graph conversion + queueing, history polling / output
// extraction, and interrupt. Live WebSocket progress (ComfyProgressService)
// plugs into fetchProgress()/generate() when connected; when it isn't, this
// falls back to bounded /history polling so generation still completes.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:sd_companion/logic/backend/backend_capabilities.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/image_backend.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/comfy/comfy_graph_converter.dart';
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
