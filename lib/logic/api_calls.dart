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
        String imageUrl = '';
        try {
          final civitaiRes = await http.get(
            Uri.parse(
              'https://civitai.com/api/v1/model-versions/by-hash/$hash',
            ),
          );
          if (civitaiRes.statusCode == 200) {
            final civitaiData = jsonDecode(civitaiRes.body);
            if (civitaiData['images'] != null &&
                civitaiData['images'].isNotEmpty) {
              imageUrl = civitaiData['images'][0]['url'] ?? '';
            }
          }
        } catch (_) {}

        globalCheckpointDataMap[modelName] = CheckpointData(
          title: model['title'],
          imageURL: imageUrl,
          samplingSteps: 20,
          samplingMethod: 'DPM++ 2M',
          cfgScale: 3.5,
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

  try {
    final checkpointData = globalCheckpointDataMap[globalCurrentCheckpointName];
    if (checkpointData == null) {
      debugPrint('Checkpoint data not found for $globalCurrentCheckpointName');
      return;
    }

    await http.post(
      Uri.parse(serverUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"sd_model_checkpoint": checkpointData.title}),
    );
  } catch (e) {
    debugPrint('Failed to set checkpoint: $e');
  }
}
