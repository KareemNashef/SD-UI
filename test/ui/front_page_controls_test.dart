// Undo on the prompt. Clearing, enhancing, describing and lifting a prompt
// from the book or from Civitai all replace the whole text at once, and
// before this there was no way back from any of them.
//
// (The sibling change - holding compare no longer paints the mask over the
// input - is not pinned here: it needs a real source `File` on the stage,
// and `Image.file`'s decode does not resolve under the fake-async pump, so
// the test hangs rather than failing.)

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

/// A 1x1 PNG - enough for Image.memory/Image.file to decode without any
/// real asset or network.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUB'
    'AScY42YAAAAASUVORK5CYII=';

class _InstantEngine implements ImageEngine {
  _InstantEngine(this.endpoint);

  @override
  final EngineEndpoint endpoint;
  @override
  EngineKind get kind => endpoint.kind;
  @override
  EngineCapabilities get capabilities => EngineCapabilities.of(kind);

  final _progress = StreamController<RunProgress>.broadcast();
  @override
  Stream<RunProgress> get progress => _progress.stream;

  @override
  Future<bool> ping() async => true;

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async => Ok([
        GeneratedImage.fromRun(
          url: 'data:image/png;base64,$_pngBase64',
          engine: kind,
          prompt: spec.prompt,
        ),
      ]);

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

ApertureRuntime _runtime() => ApertureRuntime.forTesting(
      engines: EngineRegistry(
        engineFactory: (_) => _InstantEngine(
          EngineEndpoint.defaultFor(EngineKind.forge),
        ),
      ),
    );

void main() {
  testWidgets('the prompt can be put back after being replaced',
      (tester) async {
    final runtime = _runtime();
    addTearDown(runtime.dispose);
    runtime.engine.markConnected();
    runtime.session.setPrompt('a cathedral at dusk');

    await tester.pumpWidget(
      RuntimeScope(runtime: runtime, child: const MaterialApp(home: FrontPage())),
    );
    await _pumpUntil(tester, () => find.text('Generate').evaluate().isNotEmpty);

    // Nothing has been replaced yet, so there is nothing to go back to.
    expect(find.byIcon(Icons.undo_rounded), findsNothing);
    expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(runtime.session.state.prompt, isEmpty);
    // The clear button goes with the text; undo takes its place.
    expect(find.byIcon(Icons.backspace_outlined), findsNothing);
    expect(find.byIcon(Icons.undo_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    expect(runtime.session.state.prompt, 'a cathedral at dusk');

    // Undo swaps rather than pops, so an accidental undo is itself
    // undoable - pressing it again returns to the cleared prompt instead of
    // leaving the button dead.
    expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    expect(runtime.session.state.prompt, isEmpty);

    await tester.pump(const Duration(seconds: 5)); // drain notice timers
  });
}
