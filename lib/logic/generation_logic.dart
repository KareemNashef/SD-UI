// ==================== Generation Logic ==================== //

// Flutter imports
import 'dart:typed_data';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Generation Logic Implementation

class GenerationLogic {
  // ===== Class Methods ===== //

  static String buildLoraPromptAddition(
    Map<String, double> selectedLoras,
    Map<String, Set<String>> selectedLoraTags,
  ) {
    if (selectedLoras.isEmpty) return '';
    List<String> loraStrings = [];

    selectedLoras.forEach((loraName, strength) {
      if (strength > 0) {
        final loraData = globalLoraDataMap[loraName];
        if (loraData != null) {
          loraStrings.add(
            '<lora:${loraData.name}:${strength.toStringAsFixed(2)}>',
          );
          final selectedTags = selectedLoraTags[loraName];
          if (selectedTags != null && selectedTags.isNotEmpty) {
            loraStrings.addAll(selectedTags);
          }
        }
      }
    });

    return loraStrings.isEmpty ? '' : ' ${loraStrings.join(' ')}';
  }

  static Future<List<String>> generateImg2Img({
    required String prompt,
    required Uint8List imageBytes,
    required Uint8List? maskBytes,
    required String loraPromptAdditions,
  }) async {
    // Delegate to the current backend
    return await globalBackend.generateImg2Img(
      prompt: prompt,
      imageBytes: imageBytes,
      maskBytes: maskBytes,
      loraPromptAdditions: loraPromptAdditions,
      negativePrompt: globalNegativePrompt,
      samplerName: globalCurrentSamplingMethod,
      width: globalCurrentResolutionWidth.toInt(),
      height: globalCurrentResolutionHeight.toInt(),
      batchSize: globalBatchSize,
      steps: globalCurrentSamplingSteps.toInt(),
      cfgScale: globalCurrentCfgScale,
      denoiseStrength: globalDenoiseStrength,
      maskBlur: globalMaskBlur,
      inpaintingFill: _getInpaintingFillValue(globalMaskFill),
    );
  }

  static int _getInpaintingFillValue(String maskFill) {
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
}
