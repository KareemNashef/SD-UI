// ==================== Image Engine ==================== //

import 'dart:typed_data';

import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';

/// The contract every generation engine implements.
///
/// Two things changed from the old `ImageBackend`, and both matter:
///
/// 1. **Everything returns [Result].** The old contract threw a mixture of
///    `Exception`, `StateError` and `BackendException`, so callers guessed.
///    Now failure is in the signature and cannot be forgotten.
///
/// 2. **[generate] takes a complete [GenerationSpec].** The old one took a
///    partial request and quietly read the rest from mutable globals, which
///    made engines untestable and runs unreproducible. An engine now reads
///    nothing but its arguments and its own endpoint.
///
/// Progress is a [Stream] rather than a poll-this-getter, because that is
/// what both transports naturally are: ComfyUI pushes WebSocket events, and
/// Forge's polling loop can just as easily push into a stream. The UI
/// subscribes once and stops caring which engine is behind it.
abstract class ImageEngine {
  EngineKind get kind;
  EngineCapabilities get capabilities;
  EngineEndpoint get endpoint;

  /// Bounded, read-only reachability probe. Must never throw.
  Future<bool> ping();

  /// Runs a generation. The returned images are ready to display.
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec);

  /// Progress for the run currently in flight. Emits [RunProgress.idle]
  /// when nothing is running. Never closes for the engine's lifetime.
  Stream<RunProgress> get progress;

  /// Cancels the run in flight. Safe to call when idle.
  Future<Result<void>> cancel();

  /// Fetches the bytes behind one of this engine's image URLs.
  Future<Result<Uint8List>> fetchImageBytes(String url);

  /// Releases sockets, timers and polling loops.
  Future<void> dispose();
}

/// Optional capability mixins.
///
/// Rather than widening [ImageEngine] with methods that only one engine can
/// answer - which is what pushed the old contract toward a god-interface -
/// engine-specific abilities live in their own interfaces. Call sites use
/// `engine is PromptRewriteCapable` alongside the declared capability flag.

/// Rewrites a prompt through an LLM. Forge uses OpenRouter; ComfyUI runs a
/// bundled QwenVL workflow. Same contract, very different plumbing.
abstract interface class PromptRewriteCapable {
  Future<Result<String>> rewritePrompt(String prompt);
}

/// Captions an image into a prompt.
abstract interface class ImageToTextCapable {
  Future<Result<String>> describeImage(Uint8List image);
}

/// Upscales an image to a target resolution on its longest side.
abstract interface class UpscaleCapable {
  Future<Result<String>> upscale({
    required Uint8List image,
    required int targetResolution,
    void Function(RunProgress progress)? onProgress,
  });
}
