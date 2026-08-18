// ==================== Sampling Params ==================== //

import 'package:flutter/foundation.dart';

/// How the image should be sampled.
///
/// These were nine loose mutable globals (`globalCurrentSamplingSteps`,
/// `globalCurrentCfgScale`, ...) that the Forge engine reached out and read
/// at generation time. Grouping them into one immutable value means a run
/// captures exactly the settings it used, they can be diffed, stored
/// per-checkpoint, and passed to an engine that has no ambient state.
@immutable
class SamplingParams {
  final int steps;
  final double cfgScale;
  final double denoise;
  final String sampler;
  final String scheduler;
  final int width;
  final int height;
  final int batchSize;

  /// Inpainting only: how far to feather the mask edge, in pixels.
  final int maskBlur;

  /// Inpainting only: what to seed the masked region with.
  final MaskFill maskFill;

  /// Null means "let the engine pick a fresh one for every run".
  final int? seed;

  const SamplingParams({
    this.steps = 20,
    this.cfgScale = 7.0,
    this.denoise = 0.95,
    this.sampler = 'Euler a',
    this.scheduler = 'Automatic',
    this.width = 512,
    this.height = 512,
    this.batchSize = 1,
    this.maskBlur = 8,
    this.maskFill = MaskFill.fill,
    this.seed,
  });

  bool get isSeedRandom => seed == null;

  SamplingParams copyWith({
    int? steps,
    double? cfgScale,
    double? denoise,
    String? sampler,
    String? scheduler,
    int? width,
    int? height,
    int? batchSize,
    int? maskBlur,
    MaskFill? maskFill,
    int? seed,
    bool clearSeed = false,
  }) {
    return SamplingParams(
      steps: steps ?? this.steps,
      cfgScale: cfgScale ?? this.cfgScale,
      denoise: denoise ?? this.denoise,
      sampler: sampler ?? this.sampler,
      scheduler: scheduler ?? this.scheduler,
      width: width ?? this.width,
      height: height ?? this.height,
      batchSize: batchSize ?? this.batchSize,
      maskBlur: maskBlur ?? this.maskBlur,
      maskFill: maskFill ?? this.maskFill,
      seed: clearSeed ? null : (seed ?? this.seed),
    );
  }

  Map<String, dynamic> toJson() => {
        'steps': steps,
        'cfgScale': cfgScale,
        'denoise': denoise,
        'sampler': sampler,
        'scheduler': scheduler,
        'width': width,
        'height': height,
        'batchSize': batchSize,
        'maskBlur': maskBlur,
        'maskFill': maskFill.name,
        'seed': seed,
      };

  factory SamplingParams.fromJson(Map<String, dynamic> json) => SamplingParams(
        steps: (json['steps'] as num?)?.toInt() ?? 20,
        cfgScale: (json['cfgScale'] as num?)?.toDouble() ?? 7.0,
        denoise: (json['denoise'] as num?)?.toDouble() ?? 0.95,
        sampler: json['sampler'] as String? ?? 'Euler a',
        scheduler: json['scheduler'] as String? ?? 'Automatic',
        width: (json['width'] as num?)?.toInt() ?? 512,
        height: (json['height'] as num?)?.toInt() ?? 512,
        batchSize: (json['batchSize'] as num?)?.toInt() ?? 1,
        maskBlur: (json['maskBlur'] as num?)?.toInt() ?? 8,
        maskFill: MaskFill.fromName(json['maskFill'] as String?),
        seed: (json['seed'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is SamplingParams &&
      other.steps == steps &&
      other.cfgScale == cfgScale &&
      other.denoise == denoise &&
      other.sampler == sampler &&
      other.scheduler == scheduler &&
      other.width == width &&
      other.height == height &&
      other.batchSize == batchSize &&
      other.maskBlur == maskBlur &&
      other.maskFill == maskFill &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(steps, cfgScale, denoise, sampler, scheduler,
      width, height, batchSize, maskBlur, maskFill, seed);
}

/// What to put in the masked region before sampling starts.
enum MaskFill {
  fill,
  original,
  latentNoise,
  latentNothing;

  String get label => switch (this) {
        MaskFill.fill => 'Fill',
        MaskFill.original => 'Original',
        MaskFill.latentNoise => 'Latent noise',
        MaskFill.latentNothing => 'Latent nothing',
      };

  /// A1111's `inpainting_fill` is a positional integer.
  int get a1111Value => switch (this) {
        MaskFill.fill => 0,
        MaskFill.original => 1,
        MaskFill.latentNoise => 2,
        MaskFill.latentNothing => 3,
      };

  static MaskFill fromName(String? name) => switch (name) {
        'original' => MaskFill.original,
        'latentNoise' => MaskFill.latentNoise,
        'latentNothing' => MaskFill.latentNothing,
        _ => MaskFill.fill,
      };
}
