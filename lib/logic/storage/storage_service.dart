// ==================== Storage Service ==================== //

// Flutter imports
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Local imports - Logic
import 'package:sd_companion/logic/models/checkpoint_data.dart';
import 'package:sd_companion/logic/globals.dart';

// Storage Service Implementation

class StorageService {
  // ===== Class Methods ===== //

  // ===== Server Settings ===== //

  static Future<void> saveServerSettings(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverIP', ip);
    await prefs.setString('serverPort', port);
  }

  static Future<void> loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    globalServerIP.value = prefs.getString('serverIP') ?? '';
    globalServerPort.value = prefs.getString('serverPort') ?? '';
  }

  // ===== Checkpoint Storage ===== //

  static Future<void> saveCheckpointDataMap() async {
    final prefs = await SharedPreferences.getInstance();

    final json = jsonEncode(
      globalCheckpointDataMap.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    );
    await prefs.setString('checkpointDataMap', json);
    await prefs.setString('currentCheckpointName', globalCurrentCheckpointName);
  }

  static Future<void> loadCheckpointDataMap() async {
    final prefs = await SharedPreferences.getInstance();

    final json = prefs.getString('checkpointDataMap');
    if (json != null) {
      final Map<String, dynamic> decoded = jsonDecode(json);
      globalCheckpointDataMap = decoded.map(
        (key, value) => MapEntry(
          key,
          CheckpointData.fromJson(value as Map<String, dynamic>),
        ),
      );
    }
    globalCurrentCheckpointName =
        prefs.getString('currentCheckpointName') ?? '';

    // Initial sync of local globals after loading all data
    syncActiveCheckpointSettings();
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

  static Future<void> saveGenerationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maskBlur', globalMaskBlur);
    await prefs.setString('maskFill', globalMaskFill);
    await prefs.setInt('batchSize', globalBatchSize);
    await prefs.setString('negativePrompt', globalNegativePrompt);
  }

  static Future<void> loadGenerationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    globalMaskBlur = prefs.getInt('maskBlur') ?? 8;
    globalMaskFill = prefs.getString('maskFill') ?? 'fill';
    globalBatchSize = prefs.getInt('batchSize') ?? 2;
    globalNegativePrompt = prefs.getString('negativePrompt') ?? '';
  }

  // ===== Inpaint History Storage ===== //

  static Future<void> saveInpaintHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('inpaintHistory', globalInpaintHistory.toList());
    await prefs.setStringList(
      'favoritePrompts',
      globalFavoritePrompts.toList(),
    );
  }

  static Future<void> loadInpaintHistory() async {
    final prefs = await SharedPreferences.getInstance();
    globalInpaintHistory = Set<String>.from(
      prefs.getStringList('inpaintHistory') ?? <dynamic>{},
    );
    globalFavoritePrompts = Set<String>.from(
      prefs.getStringList('favoritePrompts') ?? <dynamic>{},
    );
  }
}
