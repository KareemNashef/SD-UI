// A live preview frame outlives the run that produced it: `succeed()` keeps
// the last progress object and `RunProgress.copyWith` carries `preview`
// forward. The stage checked for a preview before anything else, so a
// finished run left the last frame pinned on screen and tapping a result did
// nothing - the classic "it works, then it's stuck" report.

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

/// A 1x1 PNG, so `Image.memory` has something real to decode.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4, 0x89,
  0, 0, 0, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0, 1, 0, 0, 5, 0, 1,
  0x0D, 0x0A, 0x2D, 0xB4, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]);

class _PreviewEngine implements ImageEngine {
  _PreviewEngine(this.endpoint);

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

  @override
  Future<bool> ping() async => true;

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async {
    // A preview frame mid-run, exactly as ComfyUI streams them.
    _progress.add(RunProgress(
      phase: RunPhase.running,
      fraction: 0.5,
      preview: _png,
    ));
    await hold.future;
    return Ok([
      GeneratedImage.fromRun(
        url: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1'
            'HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        engine: kind,
        prompt: spec.prompt,
      ),
    ]);
  }

  @override
  Future<Result<void>> cancel() async => const Ok(null);
  @override
  Future<Result<Uint8List>> fetchImageBytes(String url) async => Ok(_png);
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('the stage stops showing the preview once the run finishes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final engine = _PreviewEngine(EngineEndpoint.defaultFor(EngineKind.forge));
    final runtime = ApertureRuntime.forTesting(
      engines: EngineRegistry(engineFactory: (_) => engine),
    );
    addTearDown(runtime.dispose);

    runtime.engine.markConnected();
    runtime.session.setPrompt('a cat');

    await tester.pumpWidget(
      RuntimeScope(runtime: runtime, child: const MaterialApp(home: FrontPage())),
    );
    for (var i = 0; i < 10 && find.text('Generate').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 'GENERATING' also appears on the progress bar and the status line
    // while a run is live, so this counts any of them.
    expect(find.text('GENERATING'), findsWidgets,
        reason: 'a live preview should own the stage while running');

    await tester.runAsync(() async {
      engine.hold.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // The preview bytes are still sitting in RunState - that is precisely
    // the trap. What must not happen is the stage continuing to show them.
    expect(runtime.run.state.progress.preview, isNotNull,
        reason: 'guarding the test itself: the stale frame is still in state');
    expect(runtime.run.isActive, isFalse);

    expect(find.text('GENERATING'), findsNothing,
        reason: 'the finished run must release the stage');
    expect(find.text('RESULT'), findsOneWidget,
        reason: 'the produced image should now be what is displayed');

    await tester.pump(const Duration(seconds: 5));
  });
}
