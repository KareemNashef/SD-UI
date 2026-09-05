// Upscaling shares the run lifecycle with generation, but has no
// GenerationSpec to describe it. These pin the parts the UI depends on:
// that the bar appears, that it is labelled for the work being done, and
// that nothing else can start underneath it.

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/state/run_store.dart';

void main() {
  late RunStore run;
  setUp(() => run = RunStore());
  tearDown(() => run.dispose());

  test('beginTask makes the run active so the progress bar appears', () {
    expect(run.isActive, isFalse);
    run.beginTask('Upscaling');
    expect(run.isActive, isTrue);
    expect(run.state.phase, RunPhase.queued);
  });

  test('the label rides on stage, which the UI prefers over the phase name', () {
    run.beginTask('Upscaling');
    expect(run.state.progress.stage, 'Upscaling',
        reason: 'the bar must read UPSCALING, not GENERATING');
  });

  test('a task carries no spec, so nothing mistakes it for a generation', () {
    run.beginTask('Upscaling');
    expect(run.state.spec, isNull);
  });

  test('progress frames advance a task exactly as they do a run', () {
    run.beginTask('Upscaling');
    run.report(const RunProgress(
        phase: RunPhase.running, stage: 'Upscaling', fraction: 0.5));
    expect(run.state.progress.fraction, 0.5);
    expect(run.isActive, isTrue);
  });

  test('succeeding ends the task and pins it to complete', () {
    run.beginTask('Upscaling');
    run.succeed();
    expect(run.isActive, isFalse);
    expect(run.state.progress.fraction, 1.0);
  });

  test('failing ends the task and keeps the reason', () {
    run.beginTask('Upscaling');
    run.fail(const ServerError('upscaler exploded'));
    expect(run.isActive, isFalse);
    expect(run.state.error, isA<ServerError>());
    expect(run.state.progress.failureMessage, contains('exploded'));
  });

  test('a fresh task clears the previous one entirely', () {
    run.beginTask('Upscaling');
    run.report(const RunProgress(phase: RunPhase.running, fraction: 0.8));
    run.succeed();

    run.beginTask('Upscaling');
    expect(run.state.progress.fraction, isNull,
        reason: 'a new task must not inherit the last one\'s progress');
    expect(run.state.error, isNull);
  });
}
