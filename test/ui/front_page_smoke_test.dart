// Verifies the fix for the reported bug: generate flickering back to the
// default layout instead of holding the "generating" state, and the
// progress bar reading as stuck at one value. Both are consistent with
// Flutter's classic unkeyed-conditional-sibling reconciliation glitch (the
// print shelf swapping widget type, and the progress row being inserted,
// both unkeyed, in the same Column) - this drives multiple progress frames
// through a real widget pump and checks the UI actually tracks each one.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/engine/image_engine.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/engine_registry.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/ui/stage/front_page.dart';

class _SteppedEngine implements ImageEngine {
  _SteppedEngine(this.endpoint);

  @override
  final EngineEndpoint endpoint;
  @override
  EngineKind get kind => endpoint.kind;
  @override
  EngineCapabilities get capabilities => EngineCapabilities.of(kind);

  final _progress = StreamController<RunProgress>.broadcast();
  @override
  Stream<RunProgress> get progress => _progress.stream;

  final hold = Completer<void>();

  void emit(RunProgress p) => _progress.add(p);

  @override
  Future<bool> ping() async => true;

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async {
    await hold.future;
    return Ok([
      GeneratedImage.fromRun(url: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', engine: kind, prompt: spec.prompt),
    ]);
  }

  @override
  Future<Result<void>> cancel() async => const Ok(null);
  @override
  Future<Result<Uint8List>> fetchImageBytes(String url) async => Ok(Uint8List(0));
  @override
  Future<void> dispose() async {}
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, {int maxTicks = 60}) async {
  for (var i = 0; i < maxTicks && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('progress advances through multiple frames and the layout survives it', (
    tester,
  ) async {
    final engine = _SteppedEngine(EngineEndpoint.defaultFor(EngineKind.forge));
    final runtime = ApertureRuntime.forTesting(
      engines: EngineRegistry(engineFactory: (_) => engine),
    );
    addTearDown(runtime.dispose);

    runtime.engine.markConnected();
    runtime.session.setPrompt('a cat');

    await tester.pumpWidget(
      RuntimeScope(runtime: runtime, child: const MaterialApp(home: FrontPage())),
    );
    await _pumpUntil(tester, () => find.text('Generate').evaluate().isNotEmpty);
    expect(find.text('Generate'), findsOneWidget);

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Started from an empty library, so this tick is the exact moment the
    // shelf swaps from the "nothing printed" message to a real PrintShelf
    // *and* the progress row gets inserted above the composer, both in the
    // same unkeyed Column - the reported "flash and revert to default".
    expect(runtime.run.state.isActive, isTrue);
    expect(find.text('Stop'), findsOneWidget, reason: 'the layout did not hold the run-active state');
    expect(find.text('Generate'), findsNothing);

    // Drive three distinct progress frames through, checking each one is
    // actually reflected rather than the readout sticking on the first.
    for (final f in [0.2, 0.5, 0.8]) {
      engine.emit(RunProgress(phase: RunPhase.running, fraction: f));
      await tester.pump(const Duration(milliseconds: 50));
      expect(runtime.run.state.progress.fraction, f,
          reason: 'progress fraction did not update - the "stuck at one bar" report');
      expect(find.text('Stop'), findsOneWidget);
    }

    // Completing here goes through a real StreamSubscription.cancel(),
    // which flutter_test's fake clock does not reliably drain via pump() -
    // proven separately against the runtime in isolation, where the same
    // sequence resolves in ~3ms. runAsync bridges out to the real event
    // loop so this assertion isn't fighting the test harness instead of the
    // app.
    await tester.runAsync(() async {
      engine.hold.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    expect(runtime.run.state.isActive, isFalse);
    expect(runtime.library.state.count, 1);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);

    // Drain the sticky-note dismiss timer the initial (unrelated, expected
    // to fail in this offline test) auto-connect attempt scheduled, so the
    // binding doesn't flag it as a leaked timer on teardown.
    await tester.pump(const Duration(seconds: 5));
  });
}
