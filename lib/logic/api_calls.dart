// ==================== API Calls ==================== //

// Flutter imports
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Check if the server is online
Future<void> checkServerStatus() async {
  final url = Uri.parse(
    'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/sd-models',
  );
  try {
    final response = await http
        .get(url)
        .timeout(const Duration(milliseconds: 500));
    globalServerStatus.value = response.statusCode == 200;
  } catch (_) {
    globalServerStatus.value = false;
  }
}

// Get checkpoint data from the server
Future<void> syncCheckpointDataFromServer({bool force = false}) async {
  // Force the server to refresh the list of checkpoints
  final refreshURL =
      'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/refresh-checkpoints';

  // Post request to refresh the list of checkpoints
  await http.post(Uri.parse(refreshURL));

  final serverUrl =
      'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/sd-models';
  try {
    final res = await http.get(Uri.parse(serverUrl));
    if (res.statusCode != 200) throw Exception('Failed to get models');
    final List models = jsonDecode(res.body);

    final serverModelNames = models
        .map((m) => m['model_name'] as String)
        .toSet();

    // Remove any checkpoints not present on the server
    globalCheckpointDataMap.removeWhere(
      (key, _) => !serverModelNames.contains(key),
    );

    for (final model in models) {
      final modelName = model['model_name'];

      // Only proceed if it's a new model OR we are forcing a refresh
      if (force || !globalCheckpointDataMap.containsKey(modelName)) {
        final hash = model['hash'];

        // --- Get preview image from Civitai Logic ---
        bool isImage(Map img) {
          final type = img['type']?.toString().toLowerCase();
          if (type != null) return type == 'image';

          final mime = img['mimeType']?.toString().toLowerCase();
          if (mime != null) return mime.startsWith('image/');

          final url = img['url']?.toString().toLowerCase() ?? '';
          return url.endsWith('.png') ||
              url.endsWith('.jpg') ||
              url.endsWith('.jpeg') ||
              url.endsWith('.webp');
        }

        String imageUrl = '';
        String baseModel = '';

        const placeholder =
            'https://cdn-media.sforum.vn/storage/app/media/Van%20Pham/civitai-ai-thumbnail.jpg';

        try {
          final civitaiRes = await http.get(
            Uri.parse(
              'https://civitai.com/api/v1/model-versions/by-hash/$hash',
            ),
          );
          if (civitaiRes.statusCode == 200) {
            final data = jsonDecode(civitaiRes.body);
            
            final images = data['images'];
            baseModel = data['baseModel'];
            if (images is List) {
              for (final img in images) {
                if (img is Map &&
                    isImage(img) &&
                    (img['url']?.toString().isNotEmpty ?? false)) {
                  imageUrl = img['url'];
                  break;
                }
              }
            }
          }
        } catch (_) {}

        if (imageUrl.isEmpty) imageUrl = placeholder;
        if (baseModel.isEmpty) baseModel = 'SD 1.5';

        // ---------------------------------------------

        // Capture existing data if available to preserve settings
        final existingData = globalCheckpointDataMap[modelName];

        globalCheckpointDataMap[modelName] = CheckpointData(
          title: model['title'],
          imageURL: imageUrl, // Always update the image
          // If existing data is found, keep the old values, otherwise use defaults
          samplingSteps: existingData?.samplingSteps ?? 20,
          samplingMethod: existingData?.samplingMethod ?? 'DPM++ 2M',
          cfgScale: existingData?.cfgScale ?? 3.5,
          resolutionHeight: existingData?.resolutionHeight ?? 512,
          resolutionWidth: existingData?.resolutionWidth ?? 512,
          baseModel: baseModel,
        );
      }
    }

    


    await saveCheckpointDataMap();
  } catch (e) {
    debugPrint('Error syncing checkpoints: $e');
  }
}

// Change the checkpoint
Future<void> setCheckpoint() async {
  final serverUrl =
      'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/options';
  final progressUrl =
      'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/progress';

  try {
    final checkpointData = globalCheckpointDataMap[globalCurrentCheckpointName];
    if (checkpointData == null) {
      debugPrint('Checkpoint data not found for $globalCurrentCheckpointName');
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

// Load lora data from the server
Future<void> loadLoraDataFromServer() async {
  final baseUrl = 'http://${globalServerIP.value}:${globalServerPort.value}';

  try {
    // 1. Refresh loras
    final refreshResponse = await http.post(
      Uri.parse('$baseUrl/sdapi/v1/refresh-loras'),
    );

    if (refreshResponse.statusCode != 200) {
      debugPrint('Failed to refresh loras');
      return;
    }

    // 2. Load loras
    final loraResponse = await http.get(Uri.parse('$baseUrl/sdapi/v1/loras'));

    if (loraResponse.statusCode != 200) return;

    final data = jsonDecode(loraResponse.body) as List<dynamic>;
    globalLoraDataMap.clear();

    for (final lora in data) {
      final String name = lora['name'] ?? '';
      final String alias = lora['alias'] ?? name;
      final Set<String> tags = {};

      if (lora['metadata']?['ss_tag_frequency'] is Map) {
        final Map tagFreqData = lora['metadata']['ss_tag_frequency'];
        for (final group in tagFreqData.values) {
          if (group is Map) {
            tags.addAll(group.keys.cast<String>());
          }
        }
      }

      globalLoraDataMap[name] = LoraData(title: name, alias: alias, tags: tags);
    }
  } catch (e) {
    debugPrint('Failed to load lora data from server: $e');
  }
}
