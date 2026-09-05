// For the whole of a generation the shelf used to be decorative. The stage
// showed the preview and nothing else could reach it, so a picture made a
// minute ago was unreachable until the run finished - which is exactly when
// you most want to look at it, to decide whether this run is going the same
// way.
//
// Watching the run is now a selection like any other: the run has its own
// card, it holds the stage until you tap something else, and tapping it
// again comes back.

import 'dart:async';
import 'dart:convert';
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
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/stage/front_page.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUB'
    'AScY42YAAAAASUVORK5CYII=';
const _dataUrl = 'data:image/png;base64,$_pngBase64';

/// Generates only when told to, so the run can be held open while the shelf
/// is driven.
class _HeldEngine implements ImageEngine {
  _HeldEngine(this.endpoint);

  @override
  final EngineEndpoint endpoint;
  @override
  EngineKind get kind => endpoint.kind;
  @override
  EngineCapabilities get capabilities => EngineCapabilities.of(kind);

  final _progress = StreamController<RunProgress>.broadcast();
  @override
  Stream<RunProgress> get progress => _progress.stream;

  final release = Completer<void>();

  void emit(RunProgress p) => _progress.add(p);

  @override
  Future<bool> ping() async => true;

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async {
    await release.future;
    return Ok([
      GeneratedImage.fromRun(url: _dataUrl, engine: kind, prompt: spec.prompt),
    ]);
  }

  @override
  Future<Result<void>> cancel() async => const Ok(null);
  @override
  Future<Result<Uint8List>> fetchImageBytes(String url) async =>
      Ok(Uint8List(0));
  @override
  Future<void> dispose() async {}
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {int maxTicks = 60}) async {
  for (var i = 0; i < maxTicks && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _card(String id) =>
    find.byWidgetPredicate((w) => w is Print && w.id == id);

/// What the stage says it is showing. Read off the sheet rather than
/// searched for as text - "GENERATING" also appears in the status line and
/// the progress caption, which are not the thing under test.
String _stage(WidgetTester tester) =>
    tester.widget<MountedSheet>(find.byType(MountedSheet)).caption;

void main() {
  testWidgets('an earlier result can be looked at mid-run, and the run '
      'card gets the stage back', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final engine = _HeldEngine(EngineEndpoint.defaultFor(EngineKind.forge));
    final runtime = ApertureRuntime.forTesting(
      engines: EngineRegistry(engineFactory: (_) => engine),
    );
    addTearDown(runtime.dispose);
    runtime.engine.markConnected();
    runtime.session.setPrompt('a lighthouse');

    // Something already on the shelf to go back to.
    final earlier = GeneratedImage.fromRun(
        url: _dataUrl, engine: EngineKind.forge, prompt: 'an earlier one');
    runtime.library.add([earlier]);

    await tester.pumpWidget(
      RuntimeScope(
          runtime: runtime, child: const MaterialApp(home: FrontPage())),
    );
    await _pumpUntil(tester, () => find.text('Generate').evaluate().isNotEmpty);

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(runtime.run.state.isActive, isTrue);

    engine.emit(RunProgress(
      phase: RunPhase.running,
      fraction: 0.4,
      preview: base64Decode(_pngBase64),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // Generating starts on the stage, as it always did.
    expect(_stage(tester), 'GENERATING');
    expect(_card(kRunPrintId), findsOneWidget,
        reason: 'the run needs a card of its own to come back to');

    // Step off it onto the earlier picture.
    await tester.tap(_card(earlier.id));
    await tester.pumpAndSettle();
    expect(_stage(tester), 'RESULT',
        reason: 'the run must not drag the stage back to itself');
    expect(runtime.run.state.isActive, isTrue,
        reason: 'and looking away must not disturb the run');

    // And back onto the run.
    await tester.tap(_card(kRunPrintId));
    await tester.pumpAndSettle();
    expect(_stage(tester), 'GENERATING');

    // Progress keeps arriving on the card that was left behind.
    engine.emit(RunProgress(
      phase: RunPhase.running,
      fraction: 0.8,
      preview: base64Decode(_pngBase64),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_stage(tester), 'GENERATING');

    await tester.runAsync(() async {
      engine.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    // Finishing hands the stage to what was just made.
    expect(runtime.run.state.isActive, isFalse);
    expect(_stage(tester), 'RESULT');

    await tester.pump(const Duration(seconds: 5)); // drain notice timers
  });
}
