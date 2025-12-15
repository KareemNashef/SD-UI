import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:sd_companion/logic/globals.dart';

class GenerationLogic {
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
            '<lora:${loraData.alias}:${strength.toStringAsFixed(2)}>',
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
    final url = Uri.parse(
      'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/img2img',
    );

    final headers = {'Content-Type': 'application/json'};
    final base64Image = base64Encode(imageBytes);
    final base64Mask = maskBytes != null ? base64Encode(maskBytes) : null;

    final body = jsonEncode({
      "prompt": prompt + loraPromptAdditions,
      "negative_prompt": globalNegativePrompt,
      "sampler_name": globalCurrentSamplingMethod,
      "scheduler": "Automatic",
      "width": globalCurrentResolutionWidth.toInt(),
      "height": globalCurrentResolutionHeight.toInt(),
      "n_iter": globalBatchSize,
      "steps": globalCurrentSamplingSteps.toInt(),
      "cfg_scale": globalCurrentCfgScale,
      "denoising_strength": globalDenoiseStrength,
      "init_images": [base64Image],
      "mask": base64Mask,
      "save_images": true,
      "send_images": true,
      "mask_blur": globalMaskBlur,
      "inpainting_fill": _getInpaintingFillValue(globalMaskFill),
      "inpaint_full_res_padding": 32,
      "inpaint_full_res": true,
      "inpainting_mask_invert": 0,
      "mask_round": true,
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final images = responseData['images'] as List<dynamic>?;

      if (images != null && images.isNotEmpty) {
        final List<String> resultImages = [];
        // Skip the first image if grid is enabled (standard SD behavior check logic if needed)
        // For now, using your logic:
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
