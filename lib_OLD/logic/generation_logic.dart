// ==================== Generation Logic ==================== //

// Flutter imports
import 'dart:typed_data';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/models/generation_models.dart';

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

  /// Backend-neutral entry point: builds a [GenerationRequest] from the
  /// shared canvas state and delegates to the active backend. Forge reads
  /// its sampler/cfg/steps/etc from globals internally; ComfyUI reads its
  /// active workflow/favorites internally. Neither branch lives here.
  static Future<GenerationOutcome> generate({
    required String prompt,
    required Uint8List imageBytes,
    required Uint8List? maskBytes,
    required String loraPromptAdditions,
    List<String>? stitchImages,
    Map<String, Uint8List>? namedImages,
  }) async {
    final request = GenerationRequest(
      prompt: prompt,
      imageBytes: imageBytes,
      maskBytes: maskBytes,
      loraPromptAdditions: loraPromptAdditions,
      stitchImagesBase64: stitchImages,
      namedImages: namedImages ?? const {},
    );
    return globalBackend.generate(request);
  }
}
