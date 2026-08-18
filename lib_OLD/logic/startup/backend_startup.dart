// ==================== Backend Startup ==================== //
//
// Branches what gets loaded/synced based on the active backend, so Comfy
// never triggers Forge model/LoRA calls and vice versa. Called once at app
// startup and again every time the user switches backends from Settings.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/backend_manager.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

Future<void> loadActiveBackendProfile() async {
  final kind = globalActiveBackendKind.value;
  try {
    if (kind == BackendKind.forge) {
      await StorageService.loadCheckpointDataMap();
      await StorageService.loadLoraDataMap();
      await checkServerStatus();
      if (globalServerStatus.value) {
        await syncCheckpointDataFromServer();
        await loadLoraDataFromServer();
      }
    } else {
      await checkServerStatus();
      if (globalServerStatus.value) {
        await ComfyWorkflowService.instance.loadForProfile(
          BackendManager.instance.comfyProfile,
        );
        // Best-effort: live preview is a bonus, never blocks startup.
        unawaited(
          globalComfyBackend.progressService.connect(
            BackendManager.instance.comfyProfile,
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('Warning while loading $kind profile: $e');
  }
}
