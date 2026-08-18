// ==================== Generated Image ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/domain/engine/engine_kind.dart';

/// One produced image, plus enough context to inspect or reuse it later.
///
/// The engine-specific fields that used to sit loose on this class
/// (`comfyFilename`, `comfySubfolder`, `outputNodeId`, ...) are grouped into
/// [ComfyOrigin] so it is obvious at a glance which fields only ever apply
/// to one engine, and so adding a third engine doesn't widen this class.
@immutable
class GeneratedImage {
  final String id;

  /// `data:` URL or `http(s)` URL. What the UI displays.
  final String url;

  final EngineKind engine;

  /// How this image came to exist.
  final ImageOrigin origin;

  /// The prompt that produced it, when it came from a run.
  final String? prompt;
  final String? negativePrompt;

  /// Set only for images produced by ComfyUI.
  final ComfyOrigin? comfy;

  final DateTime createdAt;

  GeneratedImage({
    required this.id,
    required this.url,
    required this.engine,
    this.origin = ImageOrigin.generated,
    this.prompt,
    this.negativePrompt,
    this.comfy,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Result of a fresh generation.
  factory GeneratedImage.fromRun({
    required String url,
    required EngineKind engine,
    String? prompt,
    String? negativePrompt,
    ComfyOrigin? comfy,
  }) =>
      GeneratedImage(
        id: _newId(url),
        url: url,
        engine: engine,
        prompt: prompt,
        negativePrompt: negativePrompt,
        comfy: comfy,
      );

  /// Produced locally by a tool (crop, resize, upscale, stitch) rather than
  /// by a generation run.
  factory GeneratedImage.fromTool(String url, EngineKind engine) =>
      GeneratedImage(
        id: _newId(url),
        url: url,
        engine: engine,
        origin: ImageOrigin.tool,
      );

  /// Pulled back from the server's own output folder.
  factory GeneratedImage.fromServerLibrary({
    required String url,
    required EngineKind engine,
    ComfyOrigin? comfy,
    DateTime? createdAt,
  }) =>
      GeneratedImage(
        id: _newId(url),
        url: url,
        engine: engine,
        origin: ImageOrigin.serverLibrary,
        comfy: comfy,
        createdAt: createdAt,
      );

  static String _newId(String url) =>
      '${DateTime.now().microsecondsSinceEpoch}_${url.hashCode}';

  bool get isDataUrl => url.startsWith('data:image/');

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'engine': engine.storageKey,
        'origin': origin.name,
        'prompt': prompt,
        'negativePrompt': negativePrompt,
        'comfy': comfy?.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory GeneratedImage.fromJson(Map<String, dynamic> json) => GeneratedImage(
        id: json['id'] as String,
        url: json['url'] as String,
        engine: EngineKind.fromStorageKey(json['engine'] as String?),
        origin: ImageOrigin.fromName(json['origin'] as String?),
        prompt: json['prompt'] as String?,
        negativePrompt: json['negativePrompt'] as String?,
        comfy: json['comfy'] == null
            ? null
            : ComfyOrigin.fromJson((json['comfy'] as Map).cast<String, dynamic>()),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  @override
  bool operator ==(Object other) => other is GeneratedImage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum ImageOrigin {
  generated,
  tool,
  serverLibrary;

  static ImageOrigin fromName(String? name) => switch (name) {
        'tool' => ImageOrigin.tool,
        'serverLibrary' => ImageOrigin.serverLibrary,
        _ => ImageOrigin.generated,
      };
}

/// ComfyUI-specific provenance. Enough to re-fetch the file from the server
/// and to trace which graph node emitted it.
@immutable
class ComfyOrigin {
  final String? promptId;
  final String? workflowId;
  final String? nodeId;
  final String? filename;
  final String? subfolder;

  /// ComfyUI's own bucket: `output`, `temp` or `input`.
  final String type;

  const ComfyOrigin({
    this.promptId,
    this.workflowId,
    this.nodeId,
    this.filename,
    this.subfolder,
    this.type = 'output',
  });

  Map<String, dynamic> toJson() => {
        'promptId': promptId,
        'workflowId': workflowId,
        'nodeId': nodeId,
        'filename': filename,
        'subfolder': subfolder,
        'type': type,
      };

  factory ComfyOrigin.fromJson(Map<String, dynamic> json) => ComfyOrigin(
        promptId: json['promptId'] as String?,
        workflowId: json['workflowId'] as String?,
        nodeId: json['nodeId'] as String?,
        filename: json['filename'] as String?,
        subfolder: json['subfolder'] as String?,
        type: json['type'] as String? ?? 'output',
      );
}
