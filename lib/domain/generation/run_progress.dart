// ==================== Run Progress ==================== //


import 'package:flutter/foundation.dart';

/// Where a generation has got to.
///
/// Forge polls a REST endpoint and ComfyUI streams WebSocket events, but the
/// UI should never know which. Both engines report into this one shape, and
/// the fields each cannot provide are simply null.
@immutable
class RunProgress {
  final RunPhase phase;

  /// 0.0-1.0 when the engine can say. Null means "working, unknown how far" -
  /// which the UI must render as indeterminate rather than as 0%.
  final double? fraction;

  final int? stepCurrent;
  final int? stepTotal;

  /// ComfyUI: how many jobs are ahead of this one.
  final int? queuePosition;

  /// ComfyUI: which graph node is executing right now.
  final String? currentNode;

  /// Human-readable stage, when the engine reports one - Forge's upscaler
  /// says "Phase 2: DiT Upscaling", Forge's sampler says it is swapping
  /// checkpoints. Free text, shown verbatim; null means "use [phase]".
  final String? stage;

  /// Latest preview frame, when the engine streams them.
  final Uint8List? preview;

  /// Set when [phase] is [RunPhase.failed].
  final String? failureMessage;

  const RunProgress({
    this.phase = RunPhase.idle,
    this.fraction,
    this.stepCurrent,
    this.stepTotal,
    this.queuePosition,
    this.currentNode,
    this.stage,
    this.preview,
    this.failureMessage,
  });

  static const idle = RunProgress();

  bool get isActive => phase == RunPhase.queued || phase == RunPhase.running;
  bool get isFinished =>
      phase == RunPhase.completed ||
      phase == RunPhase.failed ||
      phase == RunPhase.cancelled;

  /// Progress as a percentage, or null when indeterminate.
  int? get percent => fraction == null ? null : (fraction! * 100).round();

  RunProgress copyWith({
    RunPhase? phase,
    double? fraction,
    int? stepCurrent,
    int? stepTotal,
    int? queuePosition,
    String? currentNode,
    String? stage,
    Uint8List? preview,
    String? failureMessage,
  }) {
    return RunProgress(
      phase: phase ?? this.phase,
      fraction: fraction ?? this.fraction,
      stepCurrent: stepCurrent ?? this.stepCurrent,
      stepTotal: stepTotal ?? this.stepTotal,
      queuePosition: queuePosition ?? this.queuePosition,
      currentNode: currentNode ?? this.currentNode,
      stage: stage ?? this.stage,
      preview: preview ?? this.preview,
      failureMessage: failureMessage ?? this.failureMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RunProgress &&
      other.phase == phase &&
      other.fraction == fraction &&
      other.stepCurrent == stepCurrent &&
      other.stepTotal == stepTotal &&
      other.queuePosition == queuePosition &&
      other.currentNode == currentNode &&
      other.stage == stage &&
      identical(other.preview, preview) &&
      other.failureMessage == failureMessage;

  @override
  int get hashCode => Object.hash(phase, fraction, stepCurrent, stepTotal,
      queuePosition, currentNode, stage, preview, failureMessage);
}

enum RunPhase {
  idle,
  queued,
  running,
  completed,
  failed,
  cancelled;

  /// Short status text for the UI. Kept here so Forge and ComfyUI can never
  /// drift into describing the same phase differently.
  String get label => switch (this) {
        RunPhase.idle => 'Ready',
        RunPhase.queued => 'Queued',
        RunPhase.running => 'Generating',
        RunPhase.completed => 'Done',
        RunPhase.failed => 'Failed',
        RunPhase.cancelled => 'Cancelled',
      };
}
