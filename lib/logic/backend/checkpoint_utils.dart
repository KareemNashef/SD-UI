import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

/// Common logic to sync model metadata (like Civitai previews) and update global variables.
/// This is intended to be shared across different backends.
Future<void> updateCheckpointMetadata({
  required List<Map<String, dynamic>> models,
  bool force = false,
}) async {
  // Extract all model names from the server list
  final serverModelNames = models.map((m) => m['model_name'] as String).toSet();

  // 1. Cleanup: Remove any checkpoints in our global map that are no longer on the server
  globalCheckpointDataMap.removeWhere(
    (key, _) => !serverModelNames.contains(key),
  );

  // 2. Processing: Iterate through server models and update metadata
  for (final model in models) {
    final modelName = model['model_name'] as String;
    String title = model['title'] ?? modelName;

    // Only proceed if it's a new model OR we are forcing a refresh
    if (force || !globalCheckpointDataMap.containsKey(modelName)) {
      String imageUrl = '';
      String baseModel = '';
      const placeholder = 'assets/placeholders/checkpoint.png';

      // --- New Logic ---
      try {
        final imageUrlString =
            'http://${globalServerIP.value}:${globalServerPort.value}/file=models/Stable-diffusion/$modelName.preview.png';
        // check if image exists
        final imageRes = await http.head(Uri.parse(imageUrlString));
        if (imageRes.statusCode == 200) {
          imageUrl = imageUrlString;
        }
      } catch (_) {
        // Fallback if the image is not available
      }

      try {
        final civitaiInfoUrl =
            'http://${globalServerIP.value}:${globalServerPort.value}/file=models/Stable-diffusion/$modelName.civitai.info';
        final civitaiInfoRes = await http
            .get(Uri.parse(civitaiInfoUrl))
            .timeout(const Duration(seconds: 3));

        if (civitaiInfoRes.statusCode == 200) {
          final data = jsonDecode(civitaiInfoRes.body);
          baseModel = data['baseModel'] ?? '';
        }
      } catch (_) {
        // Fallback if civitai info is not available
      }

      // Default fallbacks
      if (imageUrl.isEmpty) imageUrl = placeholder;
      if (baseModel.isEmpty) baseModel = 'SD 1.5';

      // Preserve existing user settings (steps, cfg, etc.) if they exist
      final existingData = globalCheckpointDataMap[modelName];

      globalCheckpointDataMap[modelName] = CheckpointData(
        title: title,
        imageURL: imageUrl,
        samplingSteps: existingData?.samplingSteps ?? 20,
        samplingMethod: existingData?.samplingMethod ?? 'DPM++ 2M',
        cfgScale: existingData?.cfgScale ?? 3.5,
        resolutionHeight: existingData?.resolutionHeight ?? 512,
        resolutionWidth: existingData?.resolutionWidth ?? 512,
        baseModel: baseModel,
      );
    }
  }

  // 3. Persist changes
  await StorageService.saveCheckpointDataMap();

  // 4. Sync local globals (active selection metadata)
  syncActiveCheckpointSettings();
}
