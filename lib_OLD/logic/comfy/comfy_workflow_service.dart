// ==================== Comfy Workflow Service ==================== //
//
// In-memory orchestration for ComfyUI workflows: import/select/duplicate/
// delete, and auto-detected setting edits. The saved workflow JSON is the
// source of truth; this service keeps SharedPreferences and the detected
// settings view in sync with it.

import 'package:flutter/foundation.dart';

import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/comfy/comfy_node_schema.dart';
import 'package:sd_companion/logic/comfy/comfy_object_info_client.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow_type.dart';
import 'package:sd_companion/logic/comfy/workflow_auto_detector.dart';
import 'package:sd_companion/logic/storage/comfy_storage_service.dart';

class ComfyWorkflowRecord {
  final String id;
  String name;
  ComfyWorkflowType workflowType;
  ComfyWorkflowDocument imported; // exactly as imported, for reset-to-imported
  ComfyWorkflowDocument current; // edited/persisted working copy
  DateTime updatedAt;

  ComfyWorkflowRecord({
    required this.id,
    required this.name,
    required this.workflowType,
    required this.imported,
    required this.current,
    required this.updatedAt,
  });

  ComfyWorkflowRecordData toData() => ComfyWorkflowRecordData(
    id: id,
    name: name,
    workflowType: workflowType,
    importedDocument: imported.raw,
    currentDocument: current.raw,
    updatedAt: updatedAt,
  );

  static ComfyWorkflowRecord fromData(ComfyWorkflowRecordData data) =>
      ComfyWorkflowRecord(
        id: data.id,
        name: data.name,
        workflowType: data.workflowType,
        imported: ComfyWorkflowDocument(data.importedDocument),
        current: ComfyWorkflowDocument(data.currentDocument),
        updatedAt: data.updatedAt,
      );
}

class ComfyWorkflowService {
  ComfyWorkflowService._();
  static final ComfyWorkflowService instance = ComfyWorkflowService._();

  final ValueNotifier<List<ComfyWorkflowRecord>> workflows = ValueNotifier([]);
  final ValueNotifier<String?> activeWorkflowId = ValueNotifier(null);
  final ValueNotifier<DetectedWorkflowSettings?> activeDetected = ValueNotifier(null);
  final ValueNotifier<String?> activeError = ValueNotifier(null);

  String? _loadedProfileId;
  ComfyNodeSchemaProvider? _schemaProvider;

  ComfyWorkflowRecord? get activeRecord {
    final id = activeWorkflowId.value;
    if (id == null) return null;
    for (final wf in workflows.value) {
      if (wf.id == id) return wf;
    }
    return null;
  }

  /// (Re)binds this service to a ComfyUI server profile and loads its saved
  /// workflows. Safe to call repeatedly (e.g. on every backend switch); a
  /// no-op if already loaded for the same profile.
  Future<void> loadForProfile(ServerProfile profile) async {
    if (_loadedProfileId == profile.id) return;
    _loadedProfileId = profile.id;
    _schemaProvider = HttpComfyNodeSchemaProvider(profile);

    final index = await ComfyStorageService.loadIndex(profile.id);
    final loaded = <ComfyWorkflowRecord>[];
    for (final entry in index) {
      final data = await ComfyStorageService.loadWorkflow(profile.id, entry.id);
      if (data == null) continue; // skip corrupt/missing records, don't crash
      loaded.add(ComfyWorkflowRecord.fromData(data));
    }
    workflows.value = loaded;

    final savedActiveId = await ComfyStorageService.loadActiveWorkflowId(profile.id);
    activeWorkflowId.value =
        loaded.any((w) => w.id == savedActiveId) ? savedActiveId : null;
    await _refreshDetected();
  }

  Future<ComfyWorkflowRecord> importWorkflow(
    String jsonText, {
    required String name,
    required ComfyWorkflowType workflowType,
  }) async {
    final doc = ComfyWorkflowDocument.parse(jsonText);
    final validation = ComfyWorkflowValidation.of(doc);
    if (!validation.isValid) {
      throw ComfyWorkflowParseException(
        validation.blockingIssues.map((i) => i.message).join('; '),
      );
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final record = ComfyWorkflowRecord(
      id: id,
      name: name,
      workflowType: workflowType,
      imported: doc,
      current: doc.clone(),
      updatedAt: DateTime.now(),
    );

    workflows.value = [...workflows.value, record];
    await _persistRecord(record);
    await _persistIndex();
    await selectWorkflow(id);
    return record;
  }

  Future<void> selectWorkflow(String id) async {
    if (!workflows.value.any((w) => w.id == id)) return;
    activeWorkflowId.value = id;
    if (_loadedProfileId != null) {
      await ComfyStorageService.saveActiveWorkflowId(_loadedProfileId!, id);
    }
    await _refreshDetected();
  }

  Future<void> renameWorkflow(String id, String name) async {
    final record = _find(id);
    if (record == null) return;
    record.name = name;
    record.updatedAt = DateTime.now();
    await _persistRecord(record);
    await _persistIndex();
    workflows.value = [...workflows.value];
  }

  Future<void> setWorkflowType(String id, ComfyWorkflowType type) async {
    final record = _find(id);
    if (record == null) return;
    record.workflowType = type;
    record.updatedAt = DateTime.now();
    await _persistRecord(record);
    workflows.value = [...workflows.value];
  }

  Future<ComfyWorkflowRecord> duplicateWorkflow(String id) async {
    final source = _find(id);
    if (source == null) {
      throw StateError('Workflow $id not found');
    }
    final newId = DateTime.now().microsecondsSinceEpoch.toString();
    final copy = ComfyWorkflowRecord(
      id: newId,
      name: '${source.name} copy',
      workflowType: source.workflowType,
      imported: source.imported.clone(),
      current: source.current.clone(),
      updatedAt: DateTime.now(),
    );
    workflows.value = [...workflows.value, copy];
    await _persistRecord(copy);
    await _persistIndex();
    return copy;
  }

  Future<void> deleteWorkflow(String id) async {
    workflows.value = workflows.value.where((w) => w.id != id).toList();
    if (_loadedProfileId != null) {
      await ComfyStorageService.deleteWorkflow(_loadedProfileId!, id);
    }
    await _persistIndex();
    if (activeWorkflowId.value == id) {
      activeWorkflowId.value = workflows.value.isEmpty ? null : workflows.value.first.id;
      if (_loadedProfileId != null) {
        await ComfyStorageService.saveActiveWorkflowId(
          _loadedProfileId!,
          activeWorkflowId.value,
        );
      }
      await _refreshDetected();
    }
  }

  /// Applies a new value to a detected setting (model/CLIP/VAE/sampler/
  /// latent) and persists it immediately. Prompt/negative-prompt/image are
  /// bound to the shared canvas fields instead and are applied at
  /// generation time (see ComfyBackend.generate), not edited here.
  Future<void> updateDetectedSettingValue(DetectedWidget widget, dynamic value) async {
    final record = activeRecord;
    if (record == null || widget.widgetSlotIndex == null) return;
    final node = record.current.nodeById(widget.node.id);
    if (node == null) return;
    final values = List<dynamic>.from(node.widgetsValues);
    while (values.length <= widget.widgetSlotIndex!) {
      values.add(null);
    }
    values[widget.widgetSlotIndex!] = value;
    node.widgetsValues = values;
    record.updatedAt = DateTime.now();
    await _persistRecord(record);
    await _refreshDetected();
  }

  /// Flips a seed widget's synthetic `control_after_generate` companion
  /// slot between "randomize" and "fixed". Only meaningful for widgets with
  /// [DetectedWidget.controlAfterGenerateSlotIndex] set.
  Future<void> updateSeedRandomFlag(DetectedWidget widget, bool random) async {
    final record = activeRecord;
    final slotIndex = widget.controlAfterGenerateSlotIndex;
    if (record == null || slotIndex == null) return;
    final node = record.current.nodeById(widget.node.id);
    if (node == null) return;
    final values = List<dynamic>.from(node.widgetsValues);
    while (values.length <= slotIndex) {
      values.add(null);
    }
    values[slotIndex] = random ? 'randomize' : 'fixed';
    node.widgetsValues = values;
    record.updatedAt = DateTime.now();
    await _persistRecord(record);
    await _refreshDetected();
  }

  Future<void> resetDetectedSettingToImportedValue(DetectedWidget widget) async {
    final record = activeRecord;
    if (record == null || widget.widgetSlotIndex == null) return;
    final importedNode = record.imported.nodeById(widget.node.id);
    if (importedNode == null) return;
    final values = importedNode.widgetsValues;
    if (widget.widgetSlotIndex! >= values.length) return;
    await updateDetectedSettingValue(widget, values[widget.widgetSlotIndex!]);
  }

  Future<void> _refreshDetected() async {
    final record = activeRecord;
    final provider = _schemaProvider;
    if (record == null || provider == null) {
      activeDetected.value = null;
      activeError.value = null;
      return;
    }
    try {
      final detector = WorkflowAutoDetector(provider);
      activeDetected.value = await detector.detect(record.current);
      activeError.value = null;
    } catch (e) {
      activeDetected.value = null;
      activeError.value = e.toString();
    }
  }

  Future<void> _persistRecord(ComfyWorkflowRecord record) async {
    if (_loadedProfileId == null) return;
    await ComfyStorageService.saveWorkflow(_loadedProfileId!, record.toData());
    workflows.value = [...workflows.value];
  }

  Future<void> _persistIndex() async {
    if (_loadedProfileId == null) return;
    final index = workflows.value
        .map((w) => ComfyWorkflowIndexEntry(id: w.id, name: w.name, updatedAt: w.updatedAt))
        .toList();
    await ComfyStorageService.saveIndex(_loadedProfileId!, index);
  }

  ComfyWorkflowRecord? _find(String id) {
    for (final wf in workflows.value) {
      if (wf.id == id) return wf;
    }
    return null;
  }
}
