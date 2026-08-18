// ==================== Preferences ==================== //

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/result.dart';

/// Typed wrapper over SharedPreferences.
///
/// The old `StorageService` was entirely static, held its own
/// `SharedPreferences` handle, and scattered raw string keys through its
/// methods - so nothing could be substituted in a test, and a typo in a key
/// silently produced a default value instead of an error.
///
/// This is an ordinary object, so a test can hand the repositories an
/// in-memory instance. All keys live in [PrefKeys], and JSON round-tripping
/// is handled once here rather than at every call site.
class Preferences {
  final SharedPreferences _prefs;

  Preferences(this._prefs);

  static Future<Preferences> open() async =>
      Preferences(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  List<String>? getStringList(String key) => _prefs.getStringList(key);
  Future<void> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  bool contains(String key) => _prefs.containsKey(key);

  /// Reads and decodes a JSON object. Returns null - never throws - when the
  /// value is absent or corrupt, so one bad write can't brick startup. The
  /// corrupt entry is dropped so it stops failing on every future launch.
  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      _prefs.remove(key);
      return null;
    }
  }

  Future<Result<void>> setJson(String key, Object value) async {
    try {
      await _prefs.setString(key, jsonEncode(value));
      return const Ok(null);
    } catch (error) {
      return Err(StorageError('Could not save $key.', cause: error));
    }
  }

  /// Reads and decodes a JSON array, with the same corrupt-value handling.
  List<dynamic>? getJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      _prefs.remove(key);
      return null;
    }
  }
}

/// Every persistence key in the app, in one place.
///
/// These strings are verified against what the shipped app already writes.
/// They are camelCase because that is what is on real devices - renaming any
/// of them would silently orphan a user's saved servers, checkpoints and
/// prompt history, so they must stay exactly as they are.
abstract final class PrefKeys {
  static const schemaVersion = 'storageSchemaVersion';

  static const activeEngine = 'activeBackendKind';

  static const forgeHost = 'serverIP';
  static const forgePort = 'serverPort';
  static const comfyHost = 'comfyServerIP';
  static const comfyPort = 'comfyServerPort';

  static const checkpointData = 'checkpointDataMap';
  static const activeCheckpoint = 'currentCheckpointName';
  static const loraData = 'loraDataMap';

  static const maskBlur = 'maskBlur';
  static const maskFill = 'maskFill';
  static const batchSize = 'batchSize';
  static const negativePrompt = 'negativePrompt';
  static const positivePrompt = 'positivePrompt';
  static const routerModel = 'routerModel';

  static const promptHistory = 'inpaintHistory';
  static const promptFavourites = 'favoritePrompts';

  /// Comfy workflow storage is namespaced per server, so two different
  /// ComfyUI machines don't share saved workflows.
  static String comfyWorkflowIndex(String endpointId) =>
      'comfy.$endpointId.workflowIndex';
  static String comfyWorkflow(String endpointId, String workflowId) =>
      'comfy.$endpointId.workflow.$workflowId';
  static String comfyActiveWorkflow(String endpointId) =>
      'comfy.$endpointId.activeWorkflowId';
}
