// One button, two tools. Enhance rewrites what you have; hold it and it
// becomes Write, which makes one when you have nothing - which is exactly
// the case Enhance cannot help with. (Write, not "Generate": the button
// that starts a run already owns that word.)
//
// The toggle is capability-gated, so an engine that can only rewrite must
// not be left with a button whose long-press does nothing.

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
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/stage/front_page.dart';

class _WordyEngine implements ImageEngine, PromptRewriteCapable, PromptGenerateCapable {
  _WordyEngine(this.endpoint);

  @override
  final EngineEndpoint endpoint;
  @override
  EngineKind get kind => endpoint.kind;

  @override
  EngineCapabilities get capabilities => EngineCapabilities.of(kind);

  final _progress = StreamController<RunProgress>.broadcast();
  @override
  Stream<RunProgress> get progress => _progress.stream;

  int generateCalls = 0;
  int rewriteCalls = 0;
  int? lastIntensity;

  @override
  Future<Result<String>> generatePrompt({required int intensity}) async {
    generateCalls++;
    lastIntensity = intensity;
    return const Ok('a lighthouse in a storm');
  }

  @override
  Future<Result<String>> rewritePrompt(String prompt) async {
    rewriteCalls++;
    return Ok('$prompt, but better');
  }

  @override
  Future<bool> ping() async => true;
  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async =>
      const Ok([]);
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

void main() {
  testWidgets('holding Enhance turns it into Write, and back',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final engine = _WordyEngine(EngineEndpoint.defaultFor(EngineKind.comfy));
    final runtime = ApertureRuntime.forTesting(
      engines: EngineRegistry(engineFactory: (_) => engine),
    );
    addTearDown(runtime.dispose);
    // The row reads the *store's* capabilities, which follow the active
    // engine kind - writing prompts is ComfyUI's, so the store has to be on
    // it for the second tool to exist at all.
    runtime.engine.setActive(EngineKind.comfy);
    runtime.engine.markConnected();
    runtime.session.setPrompt('a cottage');

    await tester.pumpWidget(
      RuntimeScope(
          runtime: runtime, child: const MaterialApp(home: FrontPage())),
    );
    await _pumpUntil(tester, () => find.text('Enhance').evaluate().isNotEmpty);
    expect(find.text('Write'), findsNothing);
    expect(find.text('INTENSITY'), findsNothing,
        reason: 'a dial for a button that is not on screen is furniture');

    await tester.longPress(find.text('Enhance'));
    await tester.pumpAndSettle();
    expect(find.text('Write'), findsOneWidget);
    expect(find.text('Enhance'), findsNothing,
        reason: 'it is the same button, not a second one');
    expect(find.text('INTENSITY'), findsOneWidget,
        reason: 'the one input this tool takes, shown once it is armed');

    // The dial is the whole interface: one number, 1 to 10, which the
    // bundled system prompt reads as how far to go.
    await tester.tap(find.descendant(
        of: find.byType(DeskTape), matching: find.byIcon(Icons.add_rounded)));
    await tester.pumpAndSettle();

    // Tapping now writes a prompt rather than rewriting the one there.
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    expect(engine.generateCalls, 1);
    expect(engine.rewriteCalls, 0);
    expect(engine.lastIntensity, 6, reason: 'five by default, nudged once');
    expect(runtime.session.state.prompt, 'a lighthouse in a storm');

    // The replaced prompt is recoverable, like every other wholesale swap.
    expect(runtime.promptBook.state.history, contains('a cottage'));
    expect(find.byIcon(Icons.undo_rounded), findsOneWidget);

    await tester.longPress(find.text('Write'));
    await tester.pumpAndSettle();
    expect(find.text('Enhance'), findsOneWidget);
    expect(find.text('INTENSITY'), findsNothing,
        reason: 'and it goes away with the tool it belongs to');

    await tester.tap(find.text('Enhance'));
    await tester.pumpAndSettle();
    expect(engine.rewriteCalls, 1);
    expect(engine.generateCalls, 1, reason: 'the toggle really did go back');

    await tester.pump(const Duration(seconds: 5)); // drain notice timers
  });

  testWidgets('an engine that cannot write prompts keeps a plain Enhance',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Forge rewrites through OpenRouter but has nothing that writes from
    // nothing, so there is no second tool to hold for.
    final runtime = ApertureRuntime.forTesting(
      engines: EngineRegistry(
        engineFactory: (endpoint) => _RewriteOnlyEngine(endpoint),
      ),
    );
    addTearDown(runtime.dispose);
    runtime.engine.markConnected();

    await tester.pumpWidget(
      RuntimeScope(
          runtime: runtime, child: const MaterialApp(home: FrontPage())),
    );
    await _pumpUntil(tester, () => find.text('Enhance').evaluate().isNotEmpty);

    await tester.longPress(find.text('Enhance'));
    await tester.pumpAndSettle();
    expect(find.text('Enhance'), findsOneWidget);
    expect(find.text('Write'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });
}

/// Forge: rewrites through OpenRouter, cannot write from nothing. The
/// runtime defaults to it, so the second test needs no setup at all.
class _RewriteOnlyEngine extends _WordyEngine {
  _RewriteOnlyEngine(super.endpoint);
}
