// ==================== Image Metadata ==================== //

import 'package:flutter/foundation.dart';

/// Which tool wrote the metadata found in an image.
enum MetadataSource {
  /// A1111 / Forge: one `parameters` text chunk holding a human-readable
  /// prompt block.
  automatic1111,

  /// ComfyUI: `prompt` (the API graph) and usually `workflow` (the editor
  /// graph), both raw JSON.
  comfyui,

  /// Text chunks exist but match no known convention.
  unknown,

  /// No text chunks at all - a re-encoded or stripped file.
  none,
}

/// What a generated image says about how it was made.
///
/// Both A1111 and ComfyUI embed this in the PNG itself, so reading it back
/// needs no server and works on images the app never generated - including
/// ones saved from somewhere else entirely.
@immutable
class ImageMetadata {
  final MetadataSource source;

  /// Human-readable fields, in display order. Values are already formatted.
  final Map<String, String> fields;

  final String? prompt;
  final String? negativePrompt;

  /// Every raw text chunk, keyed by its PNG keyword. Kept so a workflow can
  /// be recovered verbatim even when this class doesn't understand it.
  final Map<String, String> raw;

  const ImageMetadata({
    required this.source,
    this.fields = const {},
    this.prompt,
    this.negativePrompt,
    this.raw = const {},
  });

  static const empty = ImageMetadata(source: MetadataSource.none);

  bool get isEmpty => source == MetadataSource.none;
  bool get hasPrompt => prompt != null && prompt!.trim().isNotEmpty;

  /// The ComfyUI graph as it was submitted, when present.
  String? get comfyPrompt => raw['prompt'];

  /// The ComfyUI editor graph, which is what re-imports cleanly.
  String? get comfyWorkflow => raw['workflow'];

  String get sourceLabel => switch (source) {
        MetadataSource.automatic1111 => 'Forge / A1111',
        MetadataSource.comfyui => 'ComfyUI',
        MetadataSource.unknown => 'Unrecognised',
        MetadataSource.none => 'No metadata',
      };
}
