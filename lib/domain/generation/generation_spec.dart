// ==================== Generation Spec ==================== //


import 'package:flutter/foundation.dart';

import 'package:sd_companion/domain/catalog/checkpoint.dart';
import 'package:sd_companion/domain/generation/sampling_params.dart';

/// A complete, self-contained description of one generation.
///
/// This is the fix for the worst structural problem in the old code. The
/// previous `GenerationRequest` *looked* like it carried the request, but
/// `ForgeBackend.generate()` ignored most of it and reached out into fifteen
/// mutable globals for the prompt, sampler, size, steps, CFG, denoise, mask
/// settings and batch size. That made the engine impossible to test without
/// first arranging global state, and made it impossible to tell from a call
/// site what a run would actually do.
///
/// A spec is everything the engine needs. Engines read nothing else.
/// Consequences worth keeping:
///
///  * an engine can be unit-tested by handing it a literal;
///  * a run can record the exact spec it used, so results are reproducible;
///  * queuing several different runs is trivial, because nothing is ambient.
@immutable
class GenerationSpec {
  /// What the user typed. Already includes any LoRA tags appended for Forge.
  final String prompt;

  final String negativePrompt;

  /// Source image for img2img/inpainting. Null for txt2img.
  final Uint8List? sourceImage;

  /// Mask for inpainting: white marks the region to regenerate.
  final Uint8List? mask;

  final SamplingParams sampling;

  /// The model to generate with. Forge must select it server-side before
  /// each run; ComfyUI ignores it, because its graph names its own loader.
  /// It lives here rather than being read from a store at generation time
  /// so that a spec records the model it actually used - without it, the
  /// "reproducible" promise above is only three-quarters true.
  final Checkpoint? checkpoint;

  /// Forge only: extra images composited by the stitch script, base64.
  final List<String> stitchImages;

  /// ComfyUI only: extra named image slots, keyed by graph node id.
  final Map<String, Uint8List> namedImages;

  const GenerationSpec({
    required this.prompt,
    this.negativePrompt = '',
    this.sourceImage,
    this.mask,
    this.sampling = const SamplingParams(),
    this.checkpoint,
    this.stitchImages = const [],
    this.namedImages = const {},
  });

  bool get hasSourceImage => sourceImage != null && sourceImage!.isNotEmpty;
  bool get hasMask => mask != null && mask!.isNotEmpty;

  /// What kind of run this is, derived from what was supplied rather than
  /// tracked as a separate mode flag that could disagree with the payload.
  GenerationMode get mode {
    if (!hasSourceImage) return GenerationMode.textToImage;
    if (hasMask) return GenerationMode.inpaint;
    return GenerationMode.imageToImage;
  }

  GenerationSpec copyWith({
    String? prompt,
    String? negativePrompt,
    Uint8List? sourceImage,
    Uint8List? mask,
    SamplingParams? sampling,
    Checkpoint? checkpoint,
    List<String>? stitchImages,
    Map<String, Uint8List>? namedImages,
    bool clearSourceImage = false,
    bool clearMask = false,
  }) {
    return GenerationSpec(
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      sourceImage: clearSourceImage ? null : (sourceImage ?? this.sourceImage),
      mask: clearMask ? null : (mask ?? this.mask),
      sampling: sampling ?? this.sampling,
      checkpoint: checkpoint ?? this.checkpoint,
      stitchImages: stitchImages ?? this.stitchImages,
      namedImages: namedImages ?? this.namedImages,
    );
  }

  /// Log/debug summary that deliberately omits image bytes.
  @override
  String toString() =>
      'GenerationSpec(${mode.name}, "${prompt.length > 40 ? '${prompt.substring(0, 40)}…' : prompt}", '
      '${sampling.width}x${sampling.height}, steps ${sampling.steps})';
}

enum GenerationMode {
  textToImage,
  imageToImage,
  inpaint;

  String get label => switch (this) {
        GenerationMode.textToImage => 'Text to image',
        GenerationMode.imageToImage => 'Image to image',
        GenerationMode.inpaint => 'Inpaint',
      };
}
