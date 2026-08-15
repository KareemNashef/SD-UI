// ==================== Storage Service ==================== //

// Flutter imports
import 'dart:convert';
import 'package:sd_companion/logic/models/lora_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Local imports - Logic
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';
import 'package:sd_companion/logic/globals.dart';

// Storage Service Implementation

/// Bump when the on-disk shape of any StorageService-owned key changes in a
/// way that requires a migration step. Nothing currently reads this beyond
/// recording it, but it exists so a future breaking change has somewhere to
/// branch from instead of guessing at what's on disk.
const int storageSchemaVersion = 2;

class StorageService {
  // ===== Class Methods ===== //

  static Future<void> ensureSchemaVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('storageSchemaVersion', storageSchemaVersion);
  }

  // ===== Backend Selection ===== //

  static Future<void> saveActiveBackendKind(BackendKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeBackendKind', kind.storageKey);
  }

  static Future<void> loadActiveBackendKind() async {
    final prefs = await SharedPreferences.getInstance();
    globalActiveBackendKind.value =
        BackendKindLabel.fromStorageKey(prefs.getString('activeBackendKind'));
  }

  // ===== Server Settings ===== //

  /// Forge Neo's last-used address. Key names are unchanged from the
  /// pre-ComfyUI app on purpose: existing installs keep working with no
  /// migration step, since this key always meant "Forge's address".
  static Future<void> saveServerSettings(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverIP', ip);
    await prefs.setString('serverPort', port);
  }

  static Future<void> loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    globalServerIP.value = prefs.getString('serverIP') ?? '127.0.0.1';
    globalServerPort.value = prefs.getString('serverPort') ?? '7860';
  }

  static Future<void> saveComfyServerSettings(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('comfyServerIP', ip);
    await prefs.setString('comfyServerPort', port);
  }

  static Future<void> loadComfyServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    globalComfyServerIP.value = prefs.getString('comfyServerIP') ?? '127.0.0.1';
    globalComfyServerPort.value = prefs.getString('comfyServerPort') ?? '8188';
  }

  // ===== Checkpoint Storage ===== //

  static Future<void> saveCheckpointDataMap() async {
    final prefs = await SharedPreferences.getInstance();

    final json = jsonEncode(globalCheckpointDataMap.map((key, value) => MapEntry(key, value.toJson())));
    await prefs.setString('checkpointDataMap', json);
    await prefs.setString('currentCheckpointName', globalCurrentCheckpointName);
  }

  static Future<void> loadCheckpointDataMap() async {
    final prefs = await SharedPreferences.getInstance();

    final json = prefs.getString('checkpointDataMap');
    if (json != null) {
      final Map<String, dynamic> decoded = jsonDecode(json);
      globalCheckpointDataMap = decoded.map((key, value) => MapEntry(key, CheckpointData.fromJson(value as Map<String, dynamic>)));
    }
    globalCurrentCheckpointName = prefs.getString('currentCheckpointName') ?? '';

    // Initial sync of local globals after loading all data
    syncActiveCheckpointSettings();
  }

  // ===== Lora Storage ===== //

  static Future<void> saveLoraDataMap() async {
    final prefs = await SharedPreferences.getInstance();

    final json = jsonEncode(globalLoraDataMap.map((key, value) => MapEntry(key, value.toJson())));
    await prefs.setString('loraDataMap', json);
  }

  static Future<void> loadLoraDataMap() async {
    final prefs = await SharedPreferences.getInstance();

    final json = prefs.getString('loraDataMap');
    if (json != null) {
      final Map<String, dynamic> decoded = jsonDecode(json);
      globalLoraDataMap = decoded.map((key, value) => MapEntry(key, LoraData.fromJson(value as Map<String, dynamic>)));
    }
  }

  // ===== Generation Settings Storage ===== //

  static Future<void> saveMaskBlur() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maskBlur', globalMaskBlur);
  }

  static Future<void> saveMaskFill() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('maskFill', globalMaskFill);
  }

  static Future<void> saveBatchSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('batchSize', globalBatchSize);
  }

  static Future<void> saveNegativePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('negativePrompt', globalNegativePrompt);
  }

  static Future<void> savePositivePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('positivePrompt', globalPositivePrompt);
  }

  static Future<void> saveRouterModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('routerModel', globalRouterModel.value);
  }

  static Future<void> loadGenerationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    globalMaskBlur = prefs.getInt('maskBlur') ?? 8;
    globalMaskFill = prefs.getString('maskFill') ?? 'fill';
    globalBatchSize = prefs.getInt('batchSize') ?? 2;
    globalNegativePrompt = prefs.getString('negativePrompt') ?? '';
    globalPositivePrompt = prefs.getString('positivePrompt') ?? '';
    globalRouterModel.value = prefs.getString('routerModel') ?? 'arcee-ai/trinity-large-preview:free';
  }

  // ===== Inpaint History Storage ===== //

  static Future<void> saveInpaintHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('inpaintHistory', globalInpaintHistory.toList());
    await prefs.setStringList('favoritePrompts', globalFavoritePrompts.toList());
  }

  static Future<void> loadInpaintHistory() async {
    final prefs = await SharedPreferences.getInstance();
    globalInpaintHistory = Set<String>.from(prefs.getStringList('inpaintHistory') ?? <dynamic>{});
    globalFavoritePrompts = Set<String>.from(prefs.getStringList('favoritePrompts') ?? <dynamic>{});
  }
}
