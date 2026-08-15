// ==================== Generation Models ==================== //
//
// Backend-neutral models shared by Forge and ComfyUI: the request handed to
// ImageBackend.generate(), the result returned from it, the progress model
// streamed while it runs, and the persisted result metadata.

import 'dart:typed_data';

import 'package:sd_companion/logic/backend/backend_kind.dart';

// ===== Generation Request/Outcome ===== //

/// Everything a backend needs from the shared canvas to run a generation.
/// Backend-specific knobs (Forge sampler/cfg/steps, Comfy favorite values)
/// are read by each backend from its own state, not carried here.
class GenerationRequest {
  final String prompt;
  final Uint8List imageBytes;
  final Uint8List? maskBytes;
  final String loraPromptAdditions;
  final List<String>? stitchImagesBase64; // Forge image-stitch script only
  final Map<String, Uint8List> namedImages; // additional Comfy image slots

  const GenerationRequest({
    required this.prompt,
    required this.imageBytes,
    this.maskBytes,
    this.loraPromptAdditions = '',
    this.stitchImagesBase64,
    this.namedImages = const {},
  });
}

class GenerationOutcome {
  final List<GeneratedImage> images;
  final String? warning;

  const GenerationOutcome({required this.images, this.warning});
}

// ===== Progress ===== //

enum GenerationState { idle, queued, running, completed, failed, cancelled }

/// Backend-neutral progress snapshot. Forge fills it from `/sdapi/v1/progress`
/// polling; ComfyUI fills it from WebSocket events (falling back to history
/// polling). UI should render off this model, not raw backend JSON.
class GenerationProgress {
  final BackendKind backend;
  final GenerationState state;
  final String? jobId; // Comfy prompt_id / Forge has none
  final String? currentNodeId; // Comfy only
  final String? currentNodeTitle; // Comfy only
  final int? stepCurrent;
  final int? stepTotal;
  final double? fraction; // 0.0-1.0 when known
  final int? queuePosition;
  final Uint8List? previewBytes;
  final String? errorMessage;
  final bool isSwitchingCheckpoint; // Forge model-load detection
  final double? etaSeconds; // Forge only
  final int? jobCurrent; // Forge batch position (1-based)
  final int? jobTotal; // Forge batch size

  const GenerationProgress({
    required this.backend,
    required this.state,
    this.jobId,
    this.currentNodeId,
    this.currentNodeTitle,
    this.stepCurrent,
    this.stepTotal,
    this.fraction,
    this.queuePosition,
    this.previewBytes,
    this.errorMessage,
    this.isSwitchingCheckpoint = false,
    this.etaSeconds,
    this.jobCurrent,
    this.jobTotal,
  });

  static GenerationProgress idleFor(BackendKind backend) =>
      GenerationProgress(backend: backend, state: GenerationState.idle);

  bool get isActive =>
      state == GenerationState.queued || state == GenerationState.running;
}

// ===== Results ===== //

/// A generated image plus enough context to reuse or inspect it later,
/// regardless of which backend produced it.
class GeneratedImage {
  final String id;
  final String imageUrl; // data: URL or http(s) URL, used for display today
  final BackendKind backend;
  final String? promptId; // Comfy prompt/job id
  final String? workflowId; // Comfy workflow id used to generate this image
  final String? outputNodeId;
  final String? outputNodeType;
  final String? comfyFilename;
  final String? comfySubfolder;
  final String? comfyType;
  final Map<String, dynamic>? favoriteValuesSnapshot;
  final String? promptSnapshot;
  final String? negativePromptSnapshot;
  final DateTime createdAt;

  GeneratedImage({
    required this.id,
    required this.imageUrl,
    required this.backend,
    this.promptId,
    this.workflowId,
    this.outputNodeId,
    this.outputNodeType,
    this.comfyFilename,
    this.comfySubfolder,
    this.comfyType,
    this.favoriteValuesSnapshot,
    this.promptSnapshot,
    this.negativePromptSnapshot,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory GeneratedImage.forge(String imageUrl, {String? prompt}) =>
      GeneratedImage(
        id: '${DateTime.now().microsecondsSinceEpoch}_${imageUrl.hashCode}',
        imageUrl: imageUrl,
        backend: BackendKind.forge,
        promptSnapshot: prompt,
      );

  /// For images produced locally in-app (crop/resize/stitch/upscale
  /// outputs) rather than by a fresh backend generation.
  factory GeneratedImage.local(String imageUrl, BackendKind backend) =>
      GeneratedImage(
        id: '${DateTime.now().microsecondsSinceEpoch}_${imageUrl.hashCode}',
        imageUrl: imageUrl,
        backend: backend,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'imageUrl': imageUrl,
    'backend': backend.storageKey,
    'promptId': promptId,
    'workflowId': workflowId,
    'outputNodeId': outputNodeId,
    'outputNodeType': outputNodeType,
    'comfyFilename': comfyFilename,
    'comfySubfolder': comfySubfolder,
    'comfyType': comfyType,
    'favoriteValuesSnapshot': favoriteValuesSnapshot,
    'promptSnapshot': promptSnapshot,
    'negativePromptSnapshot': negativePromptSnapshot,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GeneratedImage.fromJson(Map<String, dynamic> json) =>
      GeneratedImage(
        id: json['id'] as String,
        imageUrl: json['imageUrl'] as String,
        backend: BackendKindLabel.fromStorageKey(json['backend'] as String?),
        promptId: json['promptId'] as String?,
        workflowId: json['workflowId'] as String?,
        outputNodeId: json['outputNodeId'] as String?,
        outputNodeType: json['outputNodeType'] as String?,
        comfyFilename: json['comfyFilename'] as String?,
        comfySubfolder: json['comfySubfolder'] as String?,
        comfyType: json['comfyType'] as String?,
        favoriteValuesSnapshot:
            (json['favoriteValuesSnapshot'] as Map?)?.cast<String, dynamic>(),
        promptSnapshot: json['promptSnapshot'] as String?,
        negativePromptSnapshot: json['negativePromptSnapshot'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

// ===== Errors ===== //

/// Typed backend error so the UI can show a useful message instead of raw
/// JSON/stack traces.
class BackendException implements Exception {
  final String message;
  final BackendErrorKind kind;
  final Object? cause;

  const BackendException(
    this.message, {
    this.kind = BackendErrorKind.unknown,
    this.cause,
  });

  @override
  String toString() => message;
}

enum BackendErrorKind {
  connection,
  timeout,
  validation,
  nodeExecution,
  server,
  unsupported,
  unknown,
}
