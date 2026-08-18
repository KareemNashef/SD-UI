// Covers the two pieces the whole app now hangs off: the registry that
// keeps one engine per endpoint, and `ApertureRuntime.submit()`, which is
// the single place a run is orchestrated. The old code open-coded that
// sequence inside a button's onPressed, which is why a thrown error left the
// UI stuck "generating" - so the failure path is tested here explicitly.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/core/app_error.dart';
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

/// An engine that answers from memory, so a run can be exercised with no
/// server, no sockets and no timing.
class FakeEngine implements ImageEngine {
  @override
  final EngineEndpoint endpoint;

  /// When set, [generate] fails with this instead of producing images.
  AppError? failWith;

  /// Progress frames pushed before the result is returned.
  List<RunProgress> emit = const [];

  int generateCalls = 0;
  bool disposed = false;
  GenerationSpec? lastSpec;

  final _progress = StreamController<RunProgress>.broadcast();

  FakeEngine(this.endpoint);

  @override
  EngineKind get kind => endpoint.kind;

  @override
  EngineCapabilities get capabilities => EngineCapabilities.of(kind);

  @override
  Stream<RunProgress> get progress => _progress.stream;

  @override
  Future<bool> ping() async => true;

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async {
    generateCalls++;
    lastSpec = spec;
    for (final frame in emit) {
      _progress.add(frame);
      await Future<void>.delayed(Duration.zero);
    }
    final error = failWith;
    if (error != null) return Err(error);
    return Ok([
      GeneratedImage.fromRun(
        url: 'data:image/png;base64,AAAA',
        engine: kind,
        prompt: spec.prompt,
      ),
    ]);
  }

  @override
  Future<Result<void>> cancel() async => const Ok(null);

  @override
  Future<Result<Uint8List>> fetchImageBytes(String url) async =>
      Ok(Uint8List(0));

  @override
  Future<void> dispose() async {
    disposed = true;
    await _progress.close();
  }
}

void main() {
  late FakeEngine engine;

  ApertureRuntime build() {
    final registry = EngineRegistry(engineFactory: (endpoint) {
      engine = FakeEngine(endpoint);
      return engine;
    });
    return ApertureRuntime.forTesting(engines: registry);
  }

  group('EngineRegistry', () {
    test('returns the same engine for the same endpoint', () {
      final registry = EngineRegistry(engineFactory: FakeEngine.new);
      final a = registry.of(EngineEndpoint.defaultFor(EngineKind.comfy));
      final b = registry.of(EngineEndpoint.defaultFor(EngineKind.comfy));
      expect(identical(a, b), isTrue);
    });

    test('keeps Forge and Comfy engines side by side', () {
      // The old BackendManager held one activeBackend, so switching engines
      // tore the other one down. Both must survive here.
      final registry = EngineRegistry(engineFactory: FakeEngine.new);
      final forge = registry.of(EngineEndpoint.defaultFor(EngineKind.forge));
      final comfy = registry.of(EngineEndpoint.defaultFor(EngineKind.comfy));
      expect(identical(forge, comfy), isFalse);
      expect((forge as FakeEngine).disposed, isFalse);
    });

    test('two ComfyUI servers get separate engines and workflow services', () {
      final registry = EngineRegistry(engineFactory: FakeEngine.new);
      const a = EngineEndpoint(
          kind: EngineKind.comfy, host: '10.0.0.2', port: '8188');
      const b = EngineEndpoint(
          kind: EngineKind.comfy, host: '10.0.0.3', port: '8188');
      expect(identical(registry.of(a), registry.of(b)), isFalse);
      expect(identical(registry.workflowsFor(a), registry.workflowsFor(b)),
          isFalse);
    });

    test('invalidate disposes the engine so the next lookup rebuilds it', () async {
      final registry = EngineRegistry(engineFactory: FakeEngine.new);
      final endpoint = EngineEndpoint.defaultFor(EngineKind.comfy);
      final first = registry.of(endpoint) as FakeEngine;
      await registry.invalidate(endpoint);
      expect(first.disposed, isTrue);
      expect(identical(registry.of(endpoint), first), isFalse);
    });
  });

  group('ApertureRuntime.submit', () {
    test('a successful run fills the library and records the prompt', () async {
      final rt = build();
      rt.session.setPrompt('a lighthouse at dusk');

      final result = await rt.submit();

      expect(result.valueOrNull, hasLength(1));
      expect(rt.library.state.count, 1);
      expect(rt.run.state.phase, RunPhase.completed);
      expect(rt.promptBook.state.history.first, 'a lighthouse at dusk');
    });

    test('the spec carries the session settings, not ambient state', () async {
      final rt = build();
      rt.session.setPrompt('a lighthouse at dusk');
      rt.session.tuneSampling((p) => p.copyWith(steps: 33, cfgScale: 2.5));

      await rt.submit();

      // This is the whole point of GenerationSpec: what the engine received
      // must be exactly what the user set, with nothing read from globals.
      expect(engine.lastSpec!.prompt, contains('a lighthouse at dusk'));
      expect(engine.lastSpec!.sampling.steps, 33);
      expect(engine.lastSpec!.sampling.cfgScale, 2.5);
    });

    test('a failed run ends the run instead of leaving it active', () async {
      final rt = build();
      rt.session.setPrompt('boom');
      // Build the engine first so the failure can be armed before submitting.
      rt.engines.of(rt.engine.state.endpoint);
      engine.failWith = const ServerError('server exploded');

      final result = await rt.submit();

      expect(result.errorOrNull, isA<ServerError>());
      expect(rt.run.state.phase, RunPhase.failed);
      expect(rt.run.state.isActive, isFalse);
      expect(rt.run.state.progress.failureMessage, 'server exploded');
      expect(rt.library.state.count, 0);
    });

    test('engine progress is mirrored into the run store', () async {
      final rt = build();
      rt.engines.of(rt.engine.state.endpoint);
      engine.emit = const [
        RunProgress(phase: RunPhase.running, fraction: 0.5, stepCurrent: 10),
      ];

      await rt.submit();

      expect(engine.generateCalls, 1);
      // The run finished, so the final phase wins - but the intermediate
      // frame must have arrived, which the step count proves.
      expect(rt.run.state.progress.stepCurrent, 10);
      expect(rt.run.state.phase, RunPhase.completed);
    });

    test('a second submit while one is running is rejected', () async {
      final rt = build();
      rt.session.setPrompt('first');
      final first = rt.submit();
      final second = await rt.submit();

      expect(second.errorOrNull, isA<ValidationError>());
      await first;
      expect(rt.library.state.count, 1); // only the first run produced an image
    });
  });
}
