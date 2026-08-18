// ==================== Comfy Storage Service ==================== //
//
// Namespaces every ComfyUI-related key by server profile id so a Forge
// connection and a ComfyUI connection (or two different ComfyUI hosts)
// never overwrite each other's saved workflows. Shape:
//
//   comfy.<profileId>.workflowIndex      -> [{id, name, updatedAt}]
//   comfy.<profileId>.workflow.<id>      -> {importedDocument, currentDocument, roleOverrides}
//   comfy.<profileId>.activeWorkflowId   -> "<id>"
//
// Malformed JSON or missing fields never throw past this layer - callers
// get null/empty results and startup keeps going.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sd_companion/data/engines/comfy/comfy_workflow_type.dart';

class ComfyWorkflowIndexEntry {
  final String id;
  final String name;
  final DateTime updatedAt;

  const ComfyWorkflowIndexEntry({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static ComfyWorkflowIndexEntry? tryParse(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return ComfyWorkflowIndexEntry(
      id: id,
      name: name,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

class ComfyWorkflowRecordData {
  final String id;
  final String name;
  final ComfyWorkflowType workflowType;
  final Map<String, dynamic> importedDocument;
  final Map<String, dynamic> currentDocument;
  final DateTime updatedAt;

  const ComfyWorkflowRecordData({
    required this.id,
    required this.name,
    required this.workflowType,
    required this.importedDocument,
    required this.currentDocument,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'workflowType': workflowType.storageKey,
    'importedDocument': importedDocument,
    'currentDocument': currentDocument,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static ComfyWorkflowRecordData? tryParse(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['id'];
      final name = decoded['name'];
      final imported = decoded['importedDocument'];
      final current = decoded['currentDocument'];
      if (id is! String || name is! String) return null;
      if (imported is! Map<String, dynamic> || current is! Map<String, dynamic>) {
        return null;
      }
      final updatedAt = DateTime.tryParse(decoded['updatedAt']?.toString() ?? '');
      return ComfyWorkflowRecordData(
        id: id,
        name: name,
        workflowType: ComfyWorkflowTypeLabel.fromStorageKey(decoded['workflowType'] as String?),
        importedDocument: imported,
        currentDocument: current,
        updatedAt: updatedAt ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ComfyWorkflowStorage {
  static String _indexKey(String profileId) => 'comfy.$profileId.workflowIndex';
  static String _workflowKey(String profileId, String id) =>
      'comfy.$profileId.workflow.$id';
  static String _activeWorkflowKey(String profileId) =>
      'comfy.$profileId.activeWorkflowId';

  static Future<List<ComfyWorkflowIndexEntry>> loadIndex(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey(profileId));
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(ComfyWorkflowIndexEntry.tryParse)
          .whereType<ComfyWorkflowIndexEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveIndex(
    String profileId,
    List<ComfyWorkflowIndexEntry> index,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _indexKey(profileId),
      jsonEncode(index.map((e) => e.toJson()).toList()),
    );
  }

  static Future<ComfyWorkflowRecordData?> loadWorkflow(
    String profileId,
    String id,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workflowKey(profileId, id));
    if (raw == null) return null;
    return ComfyWorkflowRecordData.tryParse(raw);
  }

  static Future<void> saveWorkflow(
    String profileId,
    ComfyWorkflowRecordData record,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _workflowKey(profileId, record.id),
      jsonEncode(record.toJson()),
    );
  }

  static Future<void> deleteWorkflow(String profileId, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workflowKey(profileId, id));
  }

  static Future<String?> loadActiveWorkflowId(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeWorkflowKey(profileId));
  }

  static Future<void> saveActiveWorkflowId(String profileId, String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeWorkflowKey(profileId));
    } else {
      await prefs.setString(_activeWorkflowKey(profileId), id);
    }
  }
}
