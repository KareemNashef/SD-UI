// ==================== Backend Capabilities ==================== //

import 'package:sd_companion/logic/backend/backend_kind.dart';

/// Feature flags describing what a backend supports. UI reads these instead
/// of branching on [BackendKind] directly, so adding a backend never means
/// hunting down every `if (isComfy)` call site.
class BackendCapabilities {
  final bool checkpoints; // checkpoint browser / switching
  final bool workflows; // ComfyUI workflow import/selection
  final bool loras; // dedicated LoRA inventory + modal
  final bool promptOptimizer; // Forge ollama_optimizer endpoint
  final bool metadata; // Forge PNG info endpoint
  final bool imageUpload; // primary input image
  final bool masks; // inpaint mask drawing/injection
  final bool livePreview; // streamed intermediate preview frames
  final bool upscale; // SeedVR2 upscale endpoint
  final bool stitching; // A1111 image-stitch alwayson script
  final bool testing; // checkpoint/sampler test lab
  final bool interrupt; // cancel an in-flight generation
  final bool serverLibrary; // browse the server's generated-image history
  final bool promptEnhance; // bundled Comfy LLM prompt-rewrite workflow
  final bool imageToText; // bundled Comfy LLM image-captioning workflow

  const BackendCapabilities({
    required this.checkpoints,
    required this.workflows,
    required this.loras,
    required this.promptOptimizer,
    required this.metadata,
    required this.imageUpload,
    required this.masks,
    required this.livePreview,
    required this.upscale,
    required this.stitching,
    required this.testing,
    required this.interrupt,
    required this.serverLibrary,
    required this.promptEnhance,
    required this.imageToText,
  });

  static const forge = BackendCapabilities(
    checkpoints: true,
    workflows: false,
    loras: true,
    promptOptimizer: true,
    metadata: true,
    imageUpload: true,
    masks: true,
    livePreview: false,
    upscale: true,
    stitching: true,
    testing: true,
    interrupt: true,
    // Forge/A1111 has no core REST endpoint for browsing its output
    // directory - unlike Comfy's /history, there's nothing safe to build
    // this against yet.
    serverLibrary: false,
    promptEnhance: false,
    imageToText: false,
  );

  static const comfy = BackendCapabilities(
    checkpoints: false,
    workflows: true,
    loras: false,
    promptOptimizer: false,
    metadata: false,
    imageUpload: true,
    masks: true,
    livePreview: true,
    // Backed by a bundled SeedVR2 ComfyUI workflow (assets/comfy/
    // seedvr2_upscale.json), not a server-side endpoint like Forge's - see
    // ComfyBackend.upscaleSeedVR2.
    upscale: true,
    stitching: false,
    testing: false,
    interrupt: true,
    serverLibrary: true,
    // Backed by bundled QwenVL-GGUF workflows (assets/comfy/
    // prompt_enhance.json, assets/comfy/img2prompt.json) - see
    // ComfyBackend.enhancePrompt / ComfyBackend.describeImage.
    promptEnhance: true,
    imageToText: true,
  );

  static BackendCapabilities forKind(BackendKind kind) => switch (kind) {
    BackendKind.forge => forge,
    BackendKind.comfy => comfy,
  };
}
