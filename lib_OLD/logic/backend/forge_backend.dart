// ==================== Forge Backend ==================== //
//
// Forge Neo / A1111-compatible implementation of ImageBackend. This is the
// pre-existing A1111Backend, renamed and adapted to the backend-neutral
// interface; all HTTP behavior is unchanged.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:sd_companion/logic/backend/backend_capabilities.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/checkpoint_utils.dart';
import 'package:sd_companion/logic/backend/image_backend.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';
import 'package:sd_companion/logic/models/generation_models.dart';
import 'package:sd_companion/logic/models/lora_data.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

class ForgeBackend implements ImageBackend {
  // ===== ImageBackend ===== //

  @override
  BackendKind get kind => BackendKind.forge;

  @override
  BackendCapabilities get capabilities => BackendCapabilities.forge;

  @override
  ServerProfile get profile => ServerProfile(
    kind: BackendKind.forge,
    host: globalServerIP.value,
    port: globalServerPort.value,
  );

  // Helper to construct base URL
  String get _baseUrl =>
      'http://${globalServerIP.value}:${globalServerPort.value}';

  @override
  Future<bool> checkStatus() async {
    final url = Uri.parse('$_baseUrl/sdapi/v1/sd-models');
    try {
      final response = await http
          .get(url)
          .timeout(const Duration(milliseconds: 500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<GenerationOutcome> generate(GenerationRequest request) async {
    final urls = await generateImg2Img(
      prompt: request.prompt,
      imageBytes: request.imageBytes,
      maskBytes: request.maskBytes,
      loraPromptAdditions: request.loraPromptAdditions,
      positivePrompt: globalPositivePrompt,
      negativePrompt: globalNegativePrompt,
      samplerName: globalCurrentSamplingMethod,
      width: globalCurrentResolutionWidth,
      height: globalCurrentResolutionHeight,
      batchSize: globalBatchSize,
      steps: globalCurrentSamplingSteps,
      cfgScale: globalCurrentCfgScale,
      denoiseStrength: globalDenoiseStrength,
      maskBlur: globalMaskBlur,
      inpaintingFill: _inpaintingFillValue(globalMaskFill),
      stitchImages: request.stitchImagesBase64,
    );
    return GenerationOutcome(
      images: urls
          .map((url) => GeneratedImage.forge(url, prompt: request.prompt))
          .toList(),
    );
  }

  int _inpaintingFillValue(String maskFill) {
    switch (maskFill.toLowerCase()) {
      case 'fill':
        return 0;
      case 'original':
        return 1;
      case 'latent noise':
        return 2;
      case 'latent nothing':
        return 3;
      default:
        return 0;
    }
  }

  @override
  Future<void> interruptGeneration() async {
    final url = Uri.parse('$_baseUrl/sdapi/v1/interrupt');
    final response = await http.post(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to interrupt generation: ${response.statusCode}');
    }
  }

  @override
  Future<GenerationProgress> fetchProgress() async {
    final data = await fetchRawProgress();
    final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
    final state = data['state'] as Map<String, dynamic>? ?? {};
    final jobDescription = (state['job'] as String? ?? '').toLowerCase();
    final isSwitching =
        jobDescription.contains('loading') ||
        jobDescription.contains('checkpoint') ||
        jobDescription.contains('weights');
    final currentImage = data['current_image'] as String?;

    return GenerationProgress(
      backend: BackendKind.forge,
      state: progress > 0
          ? GenerationState.running
          : GenerationState.queued,
      stepCurrent: state['sampling_step'] as int?,
      stepTotal: state['sampling_steps'] as int?,
      fraction: progress,
      etaSeconds: (data['eta_relative'] as num?)?.toDouble(),
      jobCurrent: (state['job_no'] as int?)?.let((n) => n + 1),
      jobTotal: state['job_count'] as int?,
      isSwitchingCheckpoint: isSwitching,
      previewBytes: currentImage != null ? base64Decode(currentImage) : null,
    );
  }

  @override
  void disposeProgress() {
    // Forge progress is polled on demand by ProgressService; nothing to
    // release here.
  }

  // ===== Forge-specific methods (accessed via globalForgeBackend) ===== //

  Future<String> optimizePrompt(
    String prompt,
    String? checkpoint, {
    String? openRouterModel,
  }) async {
    final url = Uri.parse('$_baseUrl/ollama_optimizer/optimize');
    final Map<String, dynamic> body = {
      "prompt": prompt,
      if (checkpoint != null) "model": checkpoint,
      if (openRouterModel != null) "openrouter_model": openRouterModel,
    };
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return responseData['optimizedPrompt'] as String;
    } else {
      throw Exception('Failed to optimize prompt: HTTP ${response.statusCode}');
    }
  }

  Future<void> syncCheckpoints({bool force = false}) async {
    // Force the server to refresh the list of checkpoints
    final refreshURL = '$_baseUrl/sdapi/v1/refresh-checkpoints';
    try {
      await http
          .post(Uri.parse(refreshURL))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}

    final serverUrl = '$_baseUrl/sdapi/v1/sd-models';
    try {
      final res = await http.get(Uri.parse(serverUrl));
      if (res.statusCode != 200) throw Exception('Failed to get models');

      final List rawModels = jsonDecode(res.body);

      // Map A1111 specific keys to the common format required by the utility
      final List<Map<String, dynamic>> processedModels = rawModels.map((m) {
        final model = m as Map<String, dynamic>;
        return {
          'model_name': model['model_name'] as String,
          'title': model['title'] as String,
          'hash': model['hash'] as String?,
        };
      }).toList();

      // Use the shared utility for metadata processing and global state updates
      await updateCheckpointMetadata(models: processedModels, force: force);
    } catch (e) {
      debugPrint('Error syncing checkpoints: $e');
    }
  }

  Future<void> setCheckpoint(String name) async {
    final progressUrl = '$_baseUrl/sdapi/v1/progress';
    final txt2imgUrl = '$_baseUrl/sdapi/v1/txt2img';

    try {
      await applyCheckpointConfiguration(name);

      // Send a quick 1x1 pixel text2image request to force the server to switch checkpoints immediately
      await http.post(
        Uri.parse(txt2imgUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "prompt": "",
          "steps": 1,
          "width": 10,
          "height": 10,
          "sampler_name": "Euler a",
          "cfg_scale": 1.0,
          "save_images": false,
        }),
      );

      // Poll the progress endpoint until the model is loaded
      while (true) {
        await Future.delayed(const Duration(milliseconds: 500));

        final response = await http.get(Uri.parse(progressUrl));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // When progress is 0 and state is empty, the model change is complete
          if (data['progress'] == 0 &&
              (data['state']['job'] == null || data['state']['job'].isEmpty)) {
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to set checkpoint: $e');
    }
  }

  /// Returns the VAE and text-encoder files reported by Forge Neo.
  Future<List<String>> fetchForgeModules() async {
    final response = await http.get(Uri.parse('$_baseUrl/sdapi/v1/sd-modules'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to load VAE and text encoders: HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final modules = data
        .whereType<Map<String, dynamic>>()
        .map((item) => item['model_name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    modules.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return modules;
  }

  /// Applies the complete checkpoint configuration through Forge Neo's
  /// options API. Module filenames are accepted directly by Forge.
  Future<void> applyCheckpointConfiguration(String name) async {
    final checkpointData = globalCheckpointDataMap[name];
    if (checkpointData == null) {
      throw StateError('Checkpoint data not found for $name');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/sdapi/v1/options'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sd_model_checkpoint': checkpointData.title,
        'forge_additional_modules': checkpointData.forgeAdditionalModules,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to apply checkpoint configuration: '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<void> loadLoras() async {
    try {
      // 1. Refresh loras
      final refreshResponse = await http.post(
        Uri.parse('$_baseUrl/sdapi/v1/refresh-loras'),
      );

      if (refreshResponse.statusCode != 200) {
        debugPrint('Failed to refresh loras');
        return;
      }

      // 2. Load loras
      final loraResponse = await http.get(
        Uri.parse('$_baseUrl/sdapi/v1/loras'),
      );

      if (loraResponse.statusCode != 200) return;

      final data = jsonDecode(loraResponse.body) as List<dynamic>;

      final serverLoraNames = data
          .map((l) => (l['name'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toSet();
      globalLoraDataMap.removeWhere(
        (key, value) => !serverLoraNames.contains(key),
      );

      for (final lora in data) {
        final String name = lora['name'] ?? '';
        if (name.isEmpty) continue;

        if (globalLoraDataMap.containsKey(name)) {
          continue;
        }

        // 3. Fetch metadata from civitai.info
        String displayName = name;
        Set<String> trainedWords = {};
        String baseModel = 'Unknown';

        try {
          final metadataResponse = await http.get(
            Uri.parse('$_baseUrl/file=models/Lora/$name.civitai.info'),
          );
          if (metadataResponse.statusCode == 200) {
            final metadata = jsonDecode(metadataResponse.body);
            displayName = metadata['model']?['name'] ?? displayName;
            baseModel = metadata['baseModel'] ?? 'Unknown';

            if (metadata['trainedWords'] is List) {
              trainedWords = Set<String>.from(
                metadata['trainedWords'].cast<String>(),
              );
            }
          }
        } catch (e) {
          debugPrint('Could not fetch or parse metadata for $name: $e');
        }

        // 4. Construct thumbnail URL
        final String thumbnailUrl =
            '$_baseUrl/file=models/Lora/$name.preview.png';
        debugPrint('Thumbnail URL: $thumbnailUrl');

        globalLoraDataMap[name] = LoraData(
          name: name,
          displayName: displayName,
          trainedWords: trainedWords,
          thumbnailUrl: thumbnailUrl,
          baseModel: baseModel,
        );
      }

      StorageService.saveLoraDataMap();
    } catch (e) {
      debugPrint('Failed to load lora data from server: $e');
    }
  }

  Future<Map<String, dynamic>> fetchRawProgress() async {
    final url = Uri.parse('$_baseUrl/sdapi/v1/progress');
    final response = await http.get(url).timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch progress: ${response.statusCode}');
    }
  }

  // Added new method strictly for SeedVR2 polling
  Future<Map<String, dynamic>> fetchSeedVR2Progress() async {
    final url = Uri.parse('$_baseUrl/seedvr2/progress');
    final response = await http.get(url).timeout(const Duration(seconds: 2));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to fetch SeedVR2 progress: ${response.statusCode}',
      );
    }
  }

  // =================================================================
  // SeedVR2 Upscaling
  // =================================================================
  Future<String> upscaleSeedVR2({
    required Uint8List imageBytes,
    required int resolution,
    Function(Map<String, dynamic> progressData)? onProgress,
  }) async {
    final base64Image = base64Encode(imageBytes);

    final body = {"image": base64Image, "resolution": resolution};

    final url = Uri.parse('$_baseUrl/seedvr2/upscale');
    bool isDone = false;

    // 1. Start the upscale request (this blocks the python server until finished)
    final upscaleFuture = http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .whenComplete(() => isDone = true);

    // 2. Poll our new SeedVR2 progress endpoint instead of A1111's default progress
    if (onProgress != null) {
      while (!isDone) {
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // Poll every half-second
        if (isDone) break;

        try {
          final progressData = await fetchSeedVR2Progress();
          // progressData will contain: {"progress": 0.25, "status": "Phase 2: DiT Upscaling", "is_running": true}
          onProgress(progressData);
        } catch (e) {
          debugPrint('Failed to poll SeedVR2 upscale progress: $e');
        }
      }
    }

    // 3. Await the final image
    final response = await upscaleFuture;

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final String upscaledImage = responseData['image'];

      if (upscaledImage.startsWith('data:image/')) {
        return upscaledImage;
      }
      return 'data:image/png;base64,$upscaledImage';
    } else {
      throw Exception(
        'Upscaling failed: HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<List<String>> generateImg2Img({
    required String prompt,
    required Uint8List imageBytes,
    required Uint8List? maskBytes,
    required String loraPromptAdditions,
    required String positivePrompt,
    required String negativePrompt,
    required String samplerName,
    required int width,
    required int height,
    required int batchSize,
    required int steps,
    required double cfgScale,
    required double denoiseStrength,
    required int maskBlur,
    required int
    inpaintingFill, // This param is int, but older logic used string lookup. A1111 expects int.
    List<String>? stitchImages,
  }) async {
    final checkpointData = globalCheckpointDataMap[globalCurrentCheckpointName];
    if (checkpointData == null) {
      throw StateError('Select a checkpoint before generating an image');
    }

    // Re-apply the saved VAE/text encoders before each generation so the
    // request remains correct after a server restart or a configuration edit.
    await applyCheckpointConfiguration(globalCurrentCheckpointName);

    final fullImage = checkpointData.img2imgMode == Img2ImgMode.fullImage;

    int finalWidth = width;
    int finalHeight = height;
    Uint8List requestImageBytes = imageBytes;

    if (fullImage) {
      final source = img.decodeImage(imageBytes);
      if (source == null) {
        throw const FormatException('Unsupported input image');
      }

      finalWidth = _alignFullImageDimension(source.width);
      finalHeight = _alignFullImageDimension(source.height);
      if (finalWidth != source.width || finalHeight != source.height) {
        final resized = img.copyResize(
          source,
          width: finalWidth,
          height: finalHeight,
          interpolation: img.Interpolation.cubic,
        );
        requestImageBytes = Uint8List.fromList(img.encodePng(resized));
      }
    }

    final base64Image = base64Encode(requestImageBytes);
    final base64Mask = !fullImage && maskBytes != null
        ? base64Encode(maskBytes)
        : null;

    String scheduler = globalCurrentScheduler;

    final body = <String, dynamic>{
      "prompt":
          (positivePrompt.isNotEmpty ? '$positivePrompt, ' : '') +
          prompt +
          loraPromptAdditions,
      "negative_prompt": negativePrompt,
      "sampler_name": samplerName,
      "scheduler": scheduler,
      "width": finalWidth,
      "height": finalHeight,
      "n_iter": batchSize,
      "steps": steps,
      "cfg_scale": cfgScale,
      "denoising_strength": denoiseStrength,
      "init_images": [base64Image],
      "resize_mode": 0,
      "save_images": true,
      "send_images": true,
      if (!fullImage) ...{
        "mask": base64Mask,
        "mask_blur": maskBlur,
        "inpainting_fill": inpaintingFill,
        "inpaint_full_res_padding": 32,
        "inpaint_full_res": true,
        "inpainting_mask_invert": 0,
        "mask_round": true,
      },
    };

    // Inject imagestitch integrated script when additional stitch images are provided
    if (stitchImages != null && stitchImages.isNotEmpty) {
      body["alwayson_scripts"] = {
        "imagestitch integrated": {
          "args": [true, stitchImages],
        },
      };
    }

    final url = Uri.parse('$_baseUrl/sdapi/v1/img2img');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final images = responseData['images'] as List<dynamic>?;

      if (images != null && images.isNotEmpty) {
        final List<String> resultImages = [];
        // Skip the first image (grid) if more than 1 image is returned
        final int start = images.length > 1 ? 1 : 0;
        for (int i = start; i < images.length; i++) {
          resultImages.add('data:image/png;base64,${images[i]}');
        }
        return resultImages;
      } else {
        throw Exception('No images generated');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  int _alignFullImageDimension(int value) {
    const alignment = 16;
    final lower = value - (value % alignment);
    final upper = lower + alignment;
    if (lower < alignment) return alignment;
    return value - lower < upper - value ? lower : upper;
  }

  Future<Map<String, dynamic>> getPngInfo(String base64Image) async {
    final url = Uri.parse('$_baseUrl/sdapi/v1/png-info');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image': base64Image}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch PNG info: ${response.statusCode}');
    }
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
