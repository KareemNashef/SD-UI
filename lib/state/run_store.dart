// ==================== Run Store ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/diagnostics.dart';
import 'package:sd_companion/core/store.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';

/// The generation currently in flight, if any.
///
/// The old code spread this across four unrelated globals
/// (`globalIsGenerating`, `globalProgressData`, plus a separate ComfyUI
/// progress notifier and a Forge polling service) and left the UI to work
/// out which one was authoritative. Worse, the "stuck on STARTING" bug came
/// straight from that split: the flag said generating, the progress object
/// never advanced, and nothing owned the contradiction.
///
/// One store owns the whole lifecycle, and the spec that started it is kept
/// alongside so the UI can show what is being generated and offer a retry
/// without reconstructing anything.
@immutable
class RunState {
  final RunProgress progress;

  /// The spec that started this run. Null when idle.
  final GenerationSpec? spec;

  /// When the run started, for elapsed-time display.
  final DateTime? startedAt;

  final AppError? error;

  const RunState({
    this.progress = RunProgress.idle,
    this.spec,
    this.startedAt,
    this.error,
  });

  bool get isActive => progress.isActive;
  RunPhase get phase => progress.phase;

  Duration? get elapsed =>
      startedAt == null ? null : DateTime.now().difference(startedAt!);

  RunState copyWith({
    RunProgress? progress,
    GenerationSpec? spec,
    DateTime? startedAt,
    AppError? error,
    bool clearError = false,
    bool clearSpec = false,
  }) =>
      RunState(
        progress: progress ?? this.progress,
        spec: clearSpec ? null : (spec ?? this.spec),
        startedAt: startedAt ?? this.startedAt,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  bool operator ==(Object other) =>
      other is RunState &&
      other.progress == progress &&
      identical(other.spec, spec) &&
      other.startedAt == startedAt &&
      other.error == error;

  @override
  int get hashCode => Object.hash(progress, spec, startedAt, error);
}

class RunStore extends Store<RunState> {
  RunStore() : super(const RunState());

  bool get isActive => state.isActive;

  /// Marks non-generation work as in flight - upscaling, principally.
  ///
  /// An upscale is a run in every way that matters here: it occupies the
  /// engine, it reports progress, it produces an image, and nothing else
  /// may start while it is going. It simply has no [GenerationSpec], so
  /// [begin] cannot describe it. [label] rides on `RunProgress.stage`, which
  /// the UI already prefers over the phase name - so the bar reads
  /// "UPSCALING" rather than "GENERATING" with no special-casing on screen.
  void beginTask(String label) => emit(RunState(
        progress: RunProgress(phase: RunPhase.queued, stage: label),
        startedAt: DateTime.now(),
      ));

  /// Marks a run as accepted and waiting on the engine.
  void begin(GenerationSpec spec) => emit(RunState(
        progress: const RunProgress(phase: RunPhase.queued),
        spec: spec,
        startedAt: DateTime.now(),
      ));

  /// Feeds an engine progress event in. Late events for a run that already
  /// finished are dropped, so a slow WebSocket frame can't resurrect a
  /// completed run - which is what made the old overlay stick.
  ///
  /// The drop is traced rather than silent: this guard is correct, but when
  /// something upstream wrongly ends the run early it turns into "progress
  /// never updates again", and a silent drop made that invisible.
  void report(RunProgress progress) {
    if (!state.isActive && progress.isActive) {
      trace(
        'run',
        'DROPPED ${progress.phase.name} frame - store is not active '
            '(store phase=${state.phase.name}). Something ended the run early.',
      );
      return;
    }
    trace('run', 'report ${progress.phase.name} '
        'frac=${progress.fraction?.toStringAsFixed(3) ?? "null"}');
    emit(state.copyWith(progress: progress));
  }

  void succeed() => emit(state.copyWith(
        progress: state.progress.copyWith(phase: RunPhase.completed, fraction: 1.0),
      ));

  void fail(AppError error) => emit(state.copyWith(
        progress: state.progress.copyWith(
          phase: RunPhase.failed,
          failureMessage: error.message,
        ),
        error: error,
      ));

  void cancel() => emit(state.copyWith(
        progress: state.progress.copyWith(phase: RunPhase.cancelled),
      ));

  /// Returns to idle, clearing the finished run.
  void reset() => emit(const RunState());
}
