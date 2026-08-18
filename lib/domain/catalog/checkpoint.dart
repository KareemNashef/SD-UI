// ==================== Checkpoint ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/domain/generation/sampling_params.dart';

/// A model installed on a Forge server, plus the settings the user prefers
/// when using it.
///
/// The old `CheckpointData` mixed identity (name, preview image) with nine
/// loose sampling fields. Folding those into [defaults] means "the settings
/// this checkpoint likes" is one value that can be applied to a session in a
/// single assignment, instead of seven separate global writes that could
/// half-apply.
@immutable
class Checkpoint {
  final String name;

  /// A1111's own identifier, e.g. `model.safetensors [a1b2c3]`. This is what
  /// `sd_model_checkpoint` must be set to; the bare [name] is rejected by
  /// some Forge builds. Falls back to [name] when the server didn't say.
  final String? title;

  /// Preview image URL, if the user attached one.
  final String? previewUrl;

  /// SDXL, SD1.5, Flux, ... Used to group the picker and to decide whether
  /// a LoRA selection should survive a switch.
  final String? baseModel;

  /// Sampling settings remembered for this checkpoint.
  final SamplingParams defaults;

  /// Extra VAE / text-encoder files Forge should load alongside it.
  final List<String> modules;

  /// Whether inpainting on this model should mask or use the full image.
  final bool inpaintMasked;

  const Checkpoint({
    required this.name,
    this.title,
    this.previewUrl,
    this.baseModel,
    this.defaults = const SamplingParams(),
    this.modules = const [],
    this.inpaintMasked = true,
  });

  String get selector => title ?? name;

  Checkpoint copyWith({
    String? title,
    String? previewUrl,
    String? baseModel,
    SamplingParams? defaults,
    List<String>? modules,
    bool? inpaintMasked,
  }) =>
      Checkpoint(
        name: name,
        title: title ?? this.title,
        previewUrl: previewUrl ?? this.previewUrl,
        baseModel: baseModel ?? this.baseModel,
        defaults: defaults ?? this.defaults,
        modules: modules ?? this.modules,
        inpaintMasked: inpaintMasked ?? this.inpaintMasked,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'previewUrl': previewUrl,
        'baseModel': baseModel,
        'defaults': defaults.toJson(),
        'modules': modules,
        'inpaintMasked': inpaintMasked,
      };

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        name: json['name'] as String,
        title: json['title'] as String?,
        previewUrl: json['previewUrl'] as String?,
        baseModel: json['baseModel'] as String?,
        defaults: json['defaults'] == null
            ? const SamplingParams()
            : SamplingParams.fromJson(
                (json['defaults'] as Map).cast<String, dynamic>()),
        modules: (json['modules'] as List?)?.cast<String>() ?? const [],
        inpaintMasked: json['inpaintMasked'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) => other is Checkpoint && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
