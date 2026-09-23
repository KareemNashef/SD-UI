// The prompt writer, and what the prompt box becomes while it runs.
//
// The three things you can do to a prompt live behind one `...` button now:
// they were a row of their own, permanently on screen, for actions taken
// once or twice a session on a page where the canvas had three hundred
// points to work with. The writer's dial rides on its own row in that card
// as ten pips, so it costs no height at all.
//
// While it runs, the box stops being a field and becomes the writing: the
// words arrive about eight times a second and are shown as they land,
// because a local model has no step count to make a bar out of.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
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
import 'package:sd_companion/domain/generation/thinking_update.dart';
import 'package:sd_companion/runtime/aperture_runtime.dart';
import 'package:sd_companion/runtime/engine_registry.dart';
import 'package:sd_companion/runtime/runtime_scope.dart';
import 'package:sd_companion/ui/stage/front_page.dart';
import 'package:sd_companion/ui/stage/prompt_tools.dart';
import 'package:sd_companion/ui/stage/thinking_surface.dart';

class _WriterEngine
    implements ImageEngine, PromptGenerateCapable, ThinkingFeedCapable {
  _WriterEngine(this.endpoint);

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
  final ValueNotifier<ThinkingUpdate> thinking =
      ValueNotifier(ThinkingUpdate.idle);

  /// Held open so the surface can be driven mid-run.
  Completer<void>? hold;
  int? lastIntensity;

  @override
  Future<Result<String>> generatePrompt({required int intensity}) async {
    lastIntensity = intensity;
    if (hold != null) await hold!.future;
    return const Ok('a lighthouse in a storm');
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

/// Forge: no prompt writer at all, which is now the only distinction left.
class _PlainEngine extends _WriterEngine {
  _PlainEngine(super.endpoint);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {int maxTicks = 60}) async {
  for (var i = 0; i < maxTicks && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

late ApertureRuntime runtime;

Future<_WriterEngine> _pumpFrontPage(
  WidgetTester tester, {
  required EngineKind kind,
  _WriterEngine Function(EngineEndpoint)? build,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  late _WriterEngine engine;
  runtime = ApertureRuntime.forTesting(
    engines: EngineRegistry(engineFactory: (endpoint) {
      engine = (build ?? _WriterEngine.new)(endpoint);
      return engine;
    }),
  );
  addTearDown(runtime.dispose);
  // The row reads the *store's* capabilities, which follow the active
  // engine kind - writing prompts is ComfyUI's.
  runtime.engine.setActive(kind);
  runtime.engine.markConnected();

  await tester.pumpWidget(
    RuntimeScope(runtime: runtime, child: const MaterialApp(home: FrontPage())),
  );
  await _pumpUntil(tester, () => find.byType(PromptTools).evaluate().isNotEmpty);
  return engine;
}

/// Opens the tools card. Nothing in it is on screen until it is asked for,
/// which is the whole point of it.
Future<void> _openTools(WidgetTester tester) async {
  await tester.tap(find.byType(PromptTools));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the tools are behind one button until they are wanted',
      (tester) async {
    await _pumpFrontPage(tester, kind: EngineKind.comfy);

    expect(find.text('Write'), findsNothing);
    expect(find.text('Prompts'), findsNothing);
    expect(find.text('Enhance'), findsNothing,
        reason: 'the enhancer is gone entirely');

    await _openTools(tester);
    expect(find.text('Prompts'), findsOneWidget);
    expect(find.text('Write'), findsOneWidget);
    expect(find.text('Describe'), findsOneWidget);
    expect(find.byType(WriteAction), findsOneWidget,
        reason: 'the dial rides on Write rather than taking a row');

    await tester.pump(const Duration(seconds: 5)); // drain notice timers
  });

  testWidgets('an engine that cannot write prompts shows neither',
      (tester) async {
    await _pumpFrontPage(tester,
        kind: EngineKind.forge, build: _PlainEngine.new);
    await _openTools(tester);

    expect(find.text('Prompts'), findsOneWidget, reason: 'always available');
    expect(find.text('Write'), findsNothing);
    expect(find.byType(WriteAction), findsNothing);
    expect(find.text('Enhance'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the dial is what reaches the engine', (tester) async {
    final engine = await _pumpFrontPage(tester, kind: EngineKind.comfy);
    await _openTools(tester);

    // The pips are their own target: the label writes, the strip sets the
    // level, so neither gesture has to wait to find out what the other one
    // was going to be. Eight and a half tenths along is level 9.
    final strip = tester.getRect(find.byKey(WriteAction.stripKey));
    await tester.tapAt(
        Offset(strip.left + strip.width * 0.85, strip.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();

    expect(engine.lastIntensity, 9,
        reason: 'the pip under the finger is the level');
    // And it is a taste, not a per-press decision, so it outlives the app.
    expect(runtime.settings.loadPromptIntensity(), 9);
    expect(find.text('a lighthouse in a storm'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the dial is held and dragged, and never writes by accident',
      (tester) async {
    final engine = await _pumpFrontPage(tester, kind: EngineKind.comfy);
    await _openTools(tester);

    // A tenth of the strip is nineteen points wide and four tall. Aiming a
    // finger at one of those, on a card that also carries a button, meant
    // the misses landed on *Write* - which starts a generation you then sit
    // through. So the strip claims the gesture the moment it is touched,
    // and holding it tracks the finger along the pips.
    final strip = tester.getRect(find.byKey(WriteAction.stripKey));
    expect(strip.height, greaterThanOrEqualTo(24),
        reason: 'four points of pip is not a target; the strip around them is');

    final finger = await tester.startGesture(
        Offset(strip.left + strip.width * 0.85, strip.center.dy));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text('INTENSITY'), findsOneWidget,
        reason: 'a hold on a four-point pip has to say it has been taken');

    await finger.moveTo(Offset(strip.left + strip.width * 0.25, strip.center.dy));
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();

    expect(runtime.settings.loadPromptIntensity(), 3,
        reason: 'the pip under the finger when it lifted');
    expect(engine.lastIntensity, isNull,
        reason: 'setting the dial is not asking for a prompt');
    expect(find.text('Write'), findsOneWidget, reason: 'and the card stays');

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the box becomes the writing, and shows the words as they land',
      (tester) async {
    final engine = await _pumpFrontPage(tester, kind: EngineKind.comfy);
    engine.hold = Completer<void>();

    expect(find.byType(ThinkingSurface), findsNothing);

    await _openTools(tester);
    await tester.tap(find.text('Write'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The field is gone; the surface has taken its place.
    expect(find.byType(ThinkingSurface), findsOneWidget);
    expect(find.text('WAKING THE MODEL'), findsOneWidget,
        reason: 'a cold local model is several seconds of nothing, and '
            'saying so beats an empty box');

    // A cold start reports a real percentage; nothing else does.
    engine.thinking.value =
        const ThinkingUpdate(phase: 'loading', progress: 0.47);
    await tester.pump();
    expect(find.text('LOADING THE MODEL 47%'), findsOneWidget);

    engine.thinking.value = const ThinkingUpdate(
        phase: 'thinking', thinking: 'weighing the storm against the light');
    await tester.pump();
    expect(find.text('THINKING'), findsOneWidget);
    expect(find.textContaining('weighing the storm'), findsOneWidget,
        reason: 'the words are the progress');

    // Once the answer starts, that is what is worth showing, not the
    // reasoning behind it.
    engine.thinking.value = const ThinkingUpdate(
        phase: 'generating',
        thinking: 'weighing the storm against the light',
        text: 'a lighthouse');
    await tester.pump();
    expect(find.text('WRITING'), findsOneWidget);
    expect(find.textContaining('a lighthouse'), findsOneWidget);
    expect(find.textContaining('weighing the storm'), findsNothing);

    engine.hold!.complete();
    await tester.pumpAndSettle();

    // And it hands the box back, with the prompt in it.
    expect(find.byType(ThinkingSurface), findsNothing);
    expect(find.text('a lighthouse in a storm'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });
}
