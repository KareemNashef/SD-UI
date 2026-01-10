import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/backend/checkpoint_utils.dart';
import 'package:sd_companion/logic/models/lora_data.dart';

class A1111Backend {
  // Helper to construct base URL
  String get _baseUrl =>
      'http://${globalServerIP.value}:${globalServerPort.value}';

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
    final serverUrl = '$_baseUrl/sdapi/v1/options';
    final progressUrl = '$_baseUrl/sdapi/v1/progress';

    try {
      final checkpointData = globalCheckpointDataMap[name];
      if (checkpointData == null) {
        debugPrint('Checkpoint data not found for $name');
        return;
      }

      // Send the checkpoint change request
      await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"sd_model_checkpoint": checkpointData.title}),
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
      globalLoraDataMap.clear();

      for (final lora in data) {
        final String name = lora['name'] ?? '';
        if (name.isEmpty) continue;

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
              trainedWords =
                  Set<String>.from(metadata['trainedWords'].cast<String>());
            }
          }
        } catch (e) {
          debugPrint('Could not fetch or parse metadata for $name: $e');
        }

        // 4. Construct thumbnail URL
        final String thumbnailUrl = '$_baseUrl/file=models/Lora/$name.preview.png';

        globalLoraDataMap[name] = LoraData(
          name: name,
          displayName: displayName,
          trainedWords: trainedWords,
          thumbnailUrl: thumbnailUrl,
          baseModel: baseModel,
        );
      }
    } catch (e) {
      debugPrint('Failed to load lora data from server: $e');
    }
  }

  Future<Map<String, dynamic>> fetchProgress() async {
    final url = Uri.parse('$_baseUrl/sdapi/v1/progress');
    final response = await http.get(url).timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch progress: ${response.statusCode}');
    }
  }

  Future<List<String>> generateImg2Img({
    required String prompt,
    required Uint8List imageBytes,
    required Uint8List? maskBytes,
    required String loraPromptAdditions,
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
  }) async {
    final base64Image = base64Encode(imageBytes);
    final base64Mask = maskBytes != null ? base64Encode(maskBytes) : null;

    final body = {
      "prompt": prompt + loraPromptAdditions,
      "negative_prompt": negativePrompt,
      "sampler_name": samplerName,
      "scheduler": "Automatic",
      "width": width,
      "height": height,
      "n_iter": batchSize,
      "steps": steps,
      "cfg_scale": cfgScale,
      "denoising_strength": denoiseStrength,
      "init_images": [base64Image],
      "mask": base64Mask,
      "save_images": true,
      "send_images": true,
      "mask_blur": maskBlur,
      "inpainting_fill": inpaintingFill,
      "inpaint_full_res_padding": 32,
      "inpaint_full_res": true,
      "inpainting_mask_invert": 0,
      "mask_round": true,
    };

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
