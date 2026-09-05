import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/data/engines/comfy/workflow_auto_detector.dart';

ComfyWorkflowDocument _loadDoc(String name) {
  final file = File('test/fixtures/$name');
  return ComfyWorkflowDocument(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
}

late StaticComfyNodeSchemaProvider _schemaProvider;
late WorkflowAutoDetector _detector;

dynamic _valueOf(List<DetectedWidget> widgets, String name) =>
    widgets.firstWhere((w) => w.input.name == name).currentValue;

bool _has(List<DetectedWidget> widgets, String name) =>
    widgets.any((w) => w.input.name == name);

void main() {
  setUpAll(() {
    final objectInfo = jsonDecode(File('test/fixtures/comfy_object_info.json').readAsStringSync())
        as Map<String, dynamic>;
    _schemaProvider = StaticComfyNodeSchemaProvider(objectInfo);
    _detector = WorkflowAutoDetector(_schemaProvider);
  });

  group('krea2_identity_edit_workflow (image edit, custom nodes)', () {
    test('detects prompt, image, model/clip/vae, sampler settings', () async {
      final doc = _loadDoc('krea2_identity_edit_workflow.json');
      final result = await _detector.detect(doc);

      expect(result.positivePrompt?.node.id, 84);
      expect(result.positivePrompt?.currentValue, 'Change her outfit to a red raincoat.');
      // Negative node (85) has its own real prompt widget too - both distinct.
      expect(result.negativePrompt?.node.id, 85);
      expect(result.negativePrompt?.currentValue, '');

      expect(result.primaryImage?.node.id, 72);
      // Node 90 is bypassed (mode 4) - must not show up as a second image slot.
      expect(result.additionalImages, isEmpty);

      // The loader is trimmed to its file, but everything the model is
      // patched through on the way to the sampler contributes its dials -
      // otherwise a Krea2 edit node's ref_boost, which is the whole point of
      // that workflow, would be unreachable from the app.
      expect(_valueOf(result.modelSettings, 'unet_name'), 'krea2_turbo_fp8_scaled.safetensors');
      expect(_has(result.modelSettings, 'weight_dtype'), isFalse,
          reason: 'loader plumbing stays hidden');
      expect(_valueOf(result.modelSettings, 'ref_boost'), 4);
      expect(_valueOf(result.modelSettings, 'ref_boost_a'), 1);
      expect(_valueOf(result.modelSettings, 'fit_mode'), 'fit');
      expect(result.modelSettings, hasLength(4));
      // Loader first, then each patch in the order the model flows through.
      expect(result.modelSettings.map((w) => w.node.id).toList(),
          [55, 79, 79, 79]);

      // The LoRA is a list entry, not a model setting - it is added and
      // removed rather than tuned, so it must not appear in both places.
      expect(_has(result.modelSettings, 'lora_name'), isFalse);
      expect(result.loras, hasLength(1));
      expect(result.loras.single.nodeId, 71);
      expect(result.loras.single.fileName,
          'Krea2/krea2_identity_edit_v1_2.safetensors');
      expect(result.loras.single.strengthValue, 1);
      expect(result.modelChain, [55, 71, 79, 53],
          reason: 'loader, LoRA, patch, sampler - the order the model flows');
      expect(result.loraLoaderType, 'LoraLoaderModelOnly');
      expect(result.clipSettings, hasLength(2));
      expect(_valueOf(result.clipSettings, 'clip_name'), 'qwen3vl_4b_fp8_scaled.safetensors');
      expect(_has(result.clipSettings, 'type'), isTrue);
      expect(result.vaeSettings, hasLength(1));
      expect(_valueOf(result.vaeSettings, 'vae_name'), 'qwen_image_vae.safetensors');

      expect(_valueOf(result.samplerSettings, 'steps'), 10);
      expect(_valueOf(result.samplerSettings, 'cfg'), 1);
      expect(_valueOf(result.samplerSettings, 'sampler_name'), 'euler');

      // seed carries its control_after_generate companion ("randomize").
      final seed = result.samplerSettings.firstWhere((w) => w.input.name == 'seed');
      expect(seed.isRandomized, isTrue);
      expect(seed.currentValue, 1088049369132323);

      // latent_image comes from EmptySD3LatentImage, whose width/height are
      // linked to a ResolutionSelector - those get unwrapped into the
      // selector's own controls instead of a dead "linked" row, once each
      // (not duplicated for both width and height). batch_size stays as-is.
      expect(_has(result.latentSettings, 'width'), isFalse);
      expect(_has(result.latentSettings, 'height'), isFalse);
      expect(_valueOf(result.latentSettings, 'aspect_ratio'), '1:1 (Square)');
      expect(_valueOf(result.latentSettings, 'megapixels'), 1);
      expect(_valueOf(result.latentSettings, 'multiple'), 8);
      final batch = result.latentSettings.firstWhere((w) => w.input.name == 'batch_size');
      expect(batch.isLinked, isFalse);
      expect(batch.currentValue, 1);
    });
  });

  group('qwen-img2img (custom Nunchaku loader, GGUF-free, real img2img)', () {
    test('detects everything through CFGNorm/ModelSamplingAuraFlow patch chain', () async {
      final doc = _loadDoc('qwen-img2img.json');
      final result = await _detector.detect(doc);

      expect(result.positivePrompt?.node.id, 76);
      expect(result.positivePrompt?.currentValue, 'Change her hair to blue');
      expect(result.negativePrompt?.node.id, 77);
      expect(result.negativePrompt?.currentValue, '');

      expect(result.primaryImage?.node.id, 78);

      // Model chain: KSampler <- CFGNorm <- ModelSamplingAuraFlow <- NunchakuQwenImageDiTLoader.
      // The loader is trimmed to just the model file - not
      // cpu_offload/num_blocks_on_gpu/etc - while the two patch nodes in
      // between contribute their own dials.
      expect(_valueOf(result.modelSettings, 'model_name'),
          'qwen\\svdq-int4_r32-qwen-image-edit-lightningv1.0-8steps.safetensors');
      expect(_has(result.modelSettings, 'cpu_offload'), isFalse);
      expect(result.loras, isEmpty, reason: 'this graph has no LoRA at all');
      expect(_valueOf(result.modelSettings, 'shift'), 3);
      expect(_valueOf(result.modelSettings, 'strength'), 1);
      expect(_valueOf(result.modelSettings, 'pre_cfg'), false);
      expect(result.modelSettings, hasLength(4));

      expect(_valueOf(result.clipSettings, 'clip_name'), 'TE-Qwen.safetensors');
      expect(_valueOf(result.vaeSettings, 'vae_name'), 'qwen_image_vae.safetensors');

      expect(_valueOf(result.samplerSettings, 'steps'), 8);
      expect(_valueOf(result.samplerSettings, 'cfg'), 1);

      // latent_image comes from VAEEncode(88), which has no width/height -
      // dimensions are driven by the (pre-scaled) input image instead.
      expect(result.latentSettings, isEmpty);
    });
  });

  group('krea-edit-multi-lora (three LoRAs stacked in the model chain)', () {
    test('lists them in flow order, out of the model settings', () async {
      final result = await _detector.detect(_loadDoc('krea-edit-multi-lora.json'));

      // UNETLoader(26) -> Lora(6) -> Lora(30) -> Lora(31) -> Krea2(9) -> KSampler(2)
      expect(result.modelChain, [26, 6, 30, 31, 9, 2]);
      expect(result.loras.map((l) => l.nodeId).toList(), [6, 30, 31]);
      expect(result.loras.map((l) => l.strengthValue).toList(), [1, 1, 0.8],
          reason: 'each LoRA keeps its own strength');
      expect(result.loras.last.fileName, 'k_bitinglips.safetensors');

      // The three loaders contribute nothing to the model settings; only the
      // file and the Krea2 patch dials belong there.
      expect(result.modelSettings.map((w) => w.input.name).toList(),
          ['unet_name', 'ref_boost', 'ref_boost_a', 'fit_mode']);
    });
  });

  group('krea-img2img (Resolution Selector feeding an unused empty latent)', () {
    test('unwraps the linked width/height into the selector\'s own controls', () async {
      final doc = _loadDoc('krea-img2img.json');
      final result = await _detector.detect(doc);

      expect(result.positivePrompt?.node.id, 84);
      expect(result.negativePrompt?.node.id, 85);
      expect(result.primaryImage?.node.id, 72);

      expect(_has(result.latentSettings, 'width'), isFalse);
      expect(_has(result.latentSettings, 'height'), isFalse);
      expect(_valueOf(result.latentSettings, 'aspect_ratio'), '2:3 (Portrait Photo)');
      expect(_valueOf(result.latentSettings, 'megapixels'), 0.9);
      expect(_valueOf(result.latentSettings, 'multiple'), 8);
      // batch_size on EmptySD3LatentImage is unlinked and stays as its own entry.
      final batch = result.latentSettings.firstWhere((w) => w.input.name == 'batch_size');
      expect(batch.isLinked, isFalse);
    });
  });

  group('z-image-txt2img and krea-txt2img (zeroed negative, pure txt2img)', () {
    for (final fixture in ['z-image-txt2img.json', 'krea-txt2img.json']) {
      test('$fixture: negative collapses to unavailable, latent widgets detected', () async {
        final doc = _loadDoc(fixture);
        final result = await _detector.detect(doc);

        expect(result.positivePrompt, isNotNull);
        expect(result.positivePrompt!.currentValue, isA<String>());
        expect((result.positivePrompt!.currentValue as String).isNotEmpty, isTrue);

        // Both positive and the (zeroed) negative trace back to the SAME
        // CLIPTextEncode node via ConditioningZeroOut - there is no distinct
        // negative prompt to expose.
        expect(result.negativePrompt, isNull);

        // No LoadImage node at all in either workflow.
        expect(result.images, isEmpty);
        expect(result.maskSupported, isFalse);

        // latent_image comes straight from EmptySD3LatentImage.
        expect(_valueOf(result.latentSettings, 'width'), 768);
        expect(_valueOf(result.latentSettings, 'height'), 768);
        expect(_valueOf(result.latentSettings, 'batch_size'), 1);

        expect(result.modelSettings, isNotEmpty);
        expect(result.clipSettings, isNotEmpty);
        expect(result.vaeSettings, isNotEmpty);
      });
    }
  });

  group('illustrious-inpainting (checkpoint loader, real inpaint crop/stitch)', () {
    test('detects distinct positive/negative, mask support, no latent widgets', () async {
      final doc = _loadDoc('illustrious-inpainting.json');
      final result = await _detector.detect(doc);

      // Sampler's positive/negative are wired through InpaintModelConditioning,
      // which must be treated as a passthrough back to the real CLIPTextEncode
      // nodes, not mistaken for the prompt source itself.
      expect(result.positivePrompt?.node.id, 6);
      expect(result.positivePrompt?.currentValue, contains('black mesh shirt'));
      expect(result.negativePrompt?.node.id, 7);
      expect(result.negativePrompt?.currentValue, contains('worst quality'));

      // CheckpointLoaderSimple supplies MODEL+CLIP+VAE from one node.
      expect(_valueOf(result.modelSettings, 'ckpt_name'), contains('babesIllustriousBy'));
      expect(_valueOf(result.clipSettings, 'ckpt_name'), contains('babesIllustriousBy'));
      expect(_valueOf(result.vaeSettings, 'ckpt_name'), contains('babesIllustriousBy'));

      expect(_valueOf(result.samplerSettings, 'denoise'), 0.85);

      expect(result.primaryImage?.node.id, 20);
      expect(result.maskSupported, isTrue);
      expect(result.maskSourceNode?.id, 20);

      // latent_image comes from InpaintModelConditioning, which has no
      // width/height widgets (only a noise_mask toggle) - fine either way,
      // the key assertion is that it's NOT sourced from an empty-latent node.
      expect(_has(result.latentSettings, 'width'), isFalse);
    });
  });
}
