// ==================== Comfy Workflow Type ==================== //
//
// User-declared at import time. Auto-detection finds *what settings exist*
// in a workflow; this says *how the inpaint page should present it* -
// structural detection alone can't reliably tell "this graph has a mask
// input" apart from "the user wants to treat this as plain img2img and
// ignore it", so it stays an explicit choice rather than being inferred.

enum ComfyWorkflowType { textToImage, imageToImage, inpainting }

extension ComfyWorkflowTypeLabel on ComfyWorkflowType {
  String get displayName => switch (this) {
    ComfyWorkflowType.textToImage => 'Text to Image',
    ComfyWorkflowType.imageToImage => 'Image to Image',
    ComfyWorkflowType.inpainting => 'Inpainting',
  };

  String get description => switch (this) {
    ComfyWorkflowType.textToImage =>
      'No input image. Prompt only.',
    ComfyWorkflowType.imageToImage =>
      'Takes an input image, no mask.',
    ComfyWorkflowType.inpainting =>
      'Takes an input image and a painted mask.',
  };

  bool get needsInputImage => this != ComfyWorkflowType.textToImage;
  bool get needsMask => this == ComfyWorkflowType.inpainting;

  String get storageKey => switch (this) {
    ComfyWorkflowType.textToImage => 'textToImage',
    ComfyWorkflowType.imageToImage => 'imageToImage',
    ComfyWorkflowType.inpainting => 'inpainting',
  };

  static ComfyWorkflowType fromStorageKey(String? key) => switch (key) {
    'imageToImage' => ComfyWorkflowType.imageToImage,
    'inpainting' => ComfyWorkflowType.inpainting,
    _ => ComfyWorkflowType.textToImage,
  };
}
