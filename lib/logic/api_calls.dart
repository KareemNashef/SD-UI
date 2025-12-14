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
      if (force || !globalCheckpointDataMap.containsKey(modelName)) {
        final hash = model['hash'];

        // Get preview image from Civitai

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
        const placeholder = 'https://cdn-media.sforum.vn/storage/app/media/Van%20Pham/civitai-ai-thumbnail.jpg'; // replace

        try {
          final civitaiRes = await http.get(
            Uri.parse(
              'https://civitai.com/api/v1/model-versions/by-hash/$hash',
            ),
          );
          if (civitaiRes.statusCode == 200) {
            final data = jsonDecode(civitaiRes.body);
            final images = data['images'];
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

        globalCheckpointDataMap[modelName] = CheckpointData(
          title: model['title'],
          imageURL: imageUrl,
          samplingSteps: 20,
          samplingMethod: 'DPM++ 2M',
          cfgScale: 3.5,
          resolutionHeight: 512,
          resolutionWidth: 512,
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
