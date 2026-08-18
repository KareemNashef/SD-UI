// ==================== Image Backend Interface ==================== //

import 'package:sd_companion/logic/backend/backend_capabilities.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/models/generation_models.dart';

/// Backend-neutral contract for a generation server. [ForgeBackend] and
/// [ComfyBackend] both implement this; the rest of the app should depend on
/// this interface (via the active-backend accessor) rather than on a
/// concrete backend type, except where a screen is intentionally
/// backend-specific (gated by [capabilities]).
abstract class ImageBackend {
  BackendKind get kind;
  BackendCapabilities get capabilities;
  ServerProfile get profile;

  /// Bounded, read-only reachability probe. Must not throw; returns false on
  /// any failure (timeout, connection refused, non-2xx).
  Future<bool> checkStatus();

  /// Runs a generation using the shared canvas/image data in [request] plus
  /// whatever backend-specific state (Forge globals, active Comfy workflow)
  /// the implementation reads on its own.
  Future<GenerationOutcome> generate(GenerationRequest request);

  /// Cancels the in-flight generation, if any. Safe to call when idle.
  Future<void> interruptGeneration();

  /// Current progress snapshot. Implementations that stream progress (Comfy
  /// WebSocket) return their last received snapshot here; implementations
  /// that poll (Forge) perform the poll inline.
  Future<GenerationProgress> fetchProgress();

  /// Releases any live resources (WebSocket connections, timers) held for
  /// progress tracking. Called on backend switch and app disposal.
  void disposeProgress();
}
