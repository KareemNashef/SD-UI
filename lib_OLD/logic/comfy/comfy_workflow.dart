// ==================== Comfy Workflow Document ==================== //
//
// A thin, non-lossy wrapper around a decoded ComfyUI editor-export JSON
// document. The raw Map is always the source of truth - node/link
// accessors are views over it, and cloning deep-copies the Map so callers
// can freely mutate the clone (to apply detected-setting overrides before
// saving) without ever touching the stored original.

import 'dart:convert';

class ComfyWorkflowParseException implements Exception {
  final String message;
  const ComfyWorkflowParseException(this.message);
  @override
  String toString() => message;
}

class ComfyEditorLink {
  final int id;
  final int originNodeId;
  final int originSlot;
  final int targetNodeId;
  final int targetSlot;
  final String type;

  const ComfyEditorLink({
    required this.id,
    required this.originNodeId,
    required this.originSlot,
    required this.targetNodeId,
    required this.targetSlot,
    required this.type,
  });

  factory ComfyEditorLink.fromRaw(List<dynamic> raw) => ComfyEditorLink(
    id: (raw[0] as num).toInt(),
    originNodeId: (raw[1] as num).toInt(),
    originSlot: (raw[2] as num).toInt(),
    targetNodeId: (raw[3] as num).toInt(),
    targetSlot: (raw[4] as num).toInt(),
    type: raw[5]?.toString() ?? '',
  );
}

/// ComfyUI node `mode` values: 0 = always active, 1 = on-event (treated as
/// active for our purposes), 2 = never/muted, 4 = bypassed.
class ComfyEditorNode {
  final Map<String, dynamic> raw;
  const ComfyEditorNode(this.raw);

  int get id => (raw['id'] as num).toInt();
  String get type => raw['type'] as String? ?? '';
  int get mode => (raw['mode'] as num?)?.toInt() ?? 0;
  bool get isBypassed => mode == 4;
  bool get isMuted => mode == 2;
  bool get isActive => !isBypassed && !isMuted;
  String? get title => raw['title'] as String?;

  List<dynamic> get widgetsValues =>
      (raw['widgets_values'] as List?) ?? const [];
  set widgetsValues(List<dynamic> values) => raw['widgets_values'] = values;

  List<Map<String, dynamic>> get inputs =>
      ((raw['inputs'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get outputs =>
      ((raw['outputs'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  /// The node's own declared input entry for [name], if the editor graph
  /// recorded one (i.e. it's linked or was converted-to-input).
  Map<String, dynamic>? inputEntry(String name) {
    for (final entry in inputs) {
      if (entry['name'] == name) return entry;
    }
    return null;
  }
}

class ComfyWorkflowDocument {
  final Map<String, dynamic> raw;
  const ComfyWorkflowDocument(this.raw);

  factory ComfyWorkflowDocument.parse(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      throw ComfyWorkflowParseException('Not valid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ComfyWorkflowParseException(
        'Workflow file must contain a JSON object at the root',
      );
    }
    return ComfyWorkflowDocument(decoded);
  }

  /// True for ComfyUI's API prompt format (`{nodeId: {class_type, inputs}}`)
  /// as opposed to the editor-export format (`{nodes: [...], links: [...]}`).
  bool get isApiFormat {
    if (raw.containsKey('nodes')) return false;
    if (raw.isEmpty) return false;
    return raw.values.every((v) => v is Map && v.containsKey('class_type'));
  }

  List<ComfyEditorNode> get nodes => ((raw['nodes'] as List?) ?? const [])
      .cast<Map<String, dynamic>>()
      .map(ComfyEditorNode.new)
      .toList();

  ComfyEditorNode? nodeById(int id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<ComfyEditorLink> get links => ((raw['links'] as List?) ?? const [])
      .map((e) => ComfyEditorLink.fromRaw(e as List<dynamic>))
      .toList();

  Map<String, dynamic> get extra =>
      (raw['extra'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Deep clone so callers can apply per-generation overrides without ever
  /// mutating the stored document.
  ComfyWorkflowDocument clone() =>
      ComfyWorkflowDocument(jsonDecode(jsonEncode(raw)) as Map<String, dynamic>);

  String encode() => jsonEncode(raw);
}

/// A single validation finding. [blocking] issues must be fixed before the
/// workflow can be used for generation; non-blocking ones are surfaced but
/// don't prevent import/selection.
class ComfyWorkflowIssue {
  final String message;
  final bool blocking;
  const ComfyWorkflowIssue(this.message, {this.blocking = true});
}

class ComfyWorkflowValidation {
  final List<ComfyWorkflowIssue> issues;
  const ComfyWorkflowValidation(this.issues);

  bool get isValid => !issues.any((i) => i.blocking);
  List<ComfyWorkflowIssue> get blockingIssues =>
      issues.where((i) => i.blocking).toList();

  /// Structural validation only (shape of nodes/links). Setting
  /// resolvability is checked separately by WorkflowAutoDetector, which
  /// needs live node schemas.
  static ComfyWorkflowValidation of(ComfyWorkflowDocument doc) {
    final issues = <ComfyWorkflowIssue>[];

    if (doc.isApiFormat) {
      // API-format graphs have no nodes/links shape to validate the same
      // way; accept them as-is (bonus path per spec).
      return const ComfyWorkflowValidation([]);
    }

    final rawNodes = doc.raw['nodes'];
    if (rawNodes is! List) {
      issues.add(const ComfyWorkflowIssue('Workflow is missing a "nodes" array'));
      return ComfyWorkflowValidation(issues);
    }

    final seenIds = <int>{};
    for (final entry in rawNodes) {
      if (entry is! Map<String, dynamic>) {
        issues.add(const ComfyWorkflowIssue('Found a node entry that is not an object'));
        continue;
      }
      final id = entry['id'];
      if (id is! num) {
        issues.add(const ComfyWorkflowIssue('Found a node with a missing or non-numeric id'));
        continue;
      }
      if (!seenIds.add(id.toInt())) {
        issues.add(ComfyWorkflowIssue('Duplicate node id ${id.toInt()}'));
      }
      final type = entry['type'];
      if (type is! String || type.isEmpty) {
        issues.add(ComfyWorkflowIssue('Node ${id.toInt()} is missing a "type"'));
      }
    }

    final rawLinks = doc.raw['links'];
    if (rawLinks != null && rawLinks is! List) {
      issues.add(const ComfyWorkflowIssue('"links" must be an array when present'));
    } else if (rawLinks is List) {
      for (final link in rawLinks) {
        if (link is! List || link.length < 6) {
          issues.add(const ComfyWorkflowIssue('Found a malformed link entry'));
          continue;
        }
        final originId = (link[1] as num?)?.toInt();
        final targetId = (link[3] as num?)?.toInt();
        if (originId == null || !seenIds.contains(originId)) {
          issues.add(ComfyWorkflowIssue('Link ${link[0]} references missing origin node $originId'));
        }
        if (targetId == null || !seenIds.contains(targetId)) {
          issues.add(ComfyWorkflowIssue('Link ${link[0]} references missing target node $targetId'));
        }
      }
    }

    return ComfyWorkflowValidation(issues);
  }
}
