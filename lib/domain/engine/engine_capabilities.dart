// ==================== Engine Capabilities ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/domain/engine/engine_kind.dart';

/// What the active engine can actually do.
///
/// The UI gates on these flags and never on [EngineKind] directly, so adding
/// a third engine is a matter of declaring its capabilities rather than
/// hunting down every `if (isComfy)` in the widget tree.
@immutable
class EngineCapabilities {
  /// Browse and switch installed checkpoints.
  final bool checkpoints;

  /// Import and run node-graph workflows.
  final bool workflows;

  /// A dedicated LoRA inventory with per-LoRA weights and trigger tags.
  final bool loras;

  /// Rewrite the prompt through a remote LLM.
  final bool promptRewrite;

  /// Caption an image into a prompt.
  final bool imageToText;

  /// Read generation parameters back out of a PNG.
  final bool imageMetadata;

  /// Accept a source image (img2img).
  final bool imageInput;

  /// Accept a mask (inpainting).
  final bool masks;

  /// Stream partial frames while generating.
  final bool livePreview;

  /// Upscale an existing image.
  final bool upscale;

  /// Composite extra images into the generation.
  final bool stitching;

  /// Batch-compare checkpoints or samplers.
  final bool testLab;

  /// Cancel a run in flight.
  final bool interrupt;

  /// Browse the images already on the server.
  final bool serverLibrary;

  const EngineCapabilities({
    required this.checkpoints,
    required this.workflows,
    required this.loras,
    required this.promptRewrite,
    required this.imageToText,
    required this.imageMetadata,
    required this.imageInput,
    required this.masks,
    required this.livePreview,
    required this.upscale,
    required this.stitching,
    required this.testLab,
    required this.interrupt,
    required this.serverLibrary,
  });

  static const forge = EngineCapabilities(
    checkpoints: true,
    workflows: false,
    loras: true,
    promptRewrite: true, // OpenRouter
    imageToText: false,
    imageMetadata: true,
    imageInput: true,
    masks: true,
    livePreview: false,
    upscale: true, // dedicated SeedVR2 endpoint
    stitching: true,
    testLab: true,
    interrupt: true,
    // No core REST endpoint exists for browsing Forge's output directory.
    serverLibrary: false,
  );

  static const comfy = EngineCapabilities(
    checkpoints: false,
    workflows: true,
    loras: false,
    promptRewrite: true, // bundled QwenVL workflow
    imageToText: true, // bundled QwenVL workflow
    imageMetadata: false,
    imageInput: true,
    masks: true,
    livePreview: true, // binary PREVIEW_IMAGE frames over the socket
    upscale: true, // bundled SeedVR2 workflow
    stitching: false,
    testLab: false,
    interrupt: true,
    serverLibrary: true, // via the ComfyUI-Gallery addon
  );

  static EngineCapabilities of(EngineKind kind) => switch (kind) {
        EngineKind.forge => forge,
        EngineKind.comfy => comfy,
      };
}
