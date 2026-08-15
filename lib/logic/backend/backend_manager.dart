// ==================== Backend Manager ==================== //
//
// Single place that knows which backend is active and how to reach it.
// Server address globals stay split per backend (globalServerIP/Port for
// Forge, globalComfyServerIP/Port for Comfy) so switching backends never
// clobbers the other one's last-used address; this class derives
// ServerProfile from whichever pair is relevant.

import 'package:flutter/foundation.dart';

import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/comfy_backend.dart';
import 'package:sd_companion/logic/backend/forge_backend.dart';
import 'package:sd_companion/logic/backend/image_backend.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/globals.dart';

class BackendManager {
  BackendManager._();
  static final BackendManager instance = BackendManager._();

  final ForgeBackend forge = ForgeBackend();
  final ComfyBackend comfy = ComfyBackend();

  ImageBackend get active =>
      globalActiveBackendKind.value == BackendKind.forge ? forge : comfy;

  ImageBackend forKind(BackendKind kind) =>
      kind == BackendKind.forge ? forge : comfy;

  ServerProfile get forgeProfile => ServerProfile(
    kind: BackendKind.forge,
    host: globalServerIP.value,
    port: globalServerPort.value,
  );

  ServerProfile get comfyProfile => ServerProfile(
    kind: BackendKind.comfy,
    host: globalComfyServerIP.value,
    port: globalComfyServerPort.value,
  );

  ServerProfile get activeProfile =>
      globalActiveBackendKind.value == BackendKind.forge
      ? forgeProfile
      : comfyProfile;

  ServerProfile profileFor(BackendKind kind) =>
      kind == BackendKind.forge ? forgeProfile : comfyProfile;

  /// Switches the active backend, releasing any live progress resources
  /// (e.g. Comfy's WebSocket) held by the previously active backend.
  Future<void> switchTo(BackendKind kind) async {
    if (globalActiveBackendKind.value == kind) return;
    active.disposeProgress();
    globalActiveBackendKind.value = kind;
    debugPrint('Switched active backend to ${kind.displayName}');
  }
}
