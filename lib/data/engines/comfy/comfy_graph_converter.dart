// ==================== Comfy Graph Converter ==================== //
//
// Converts a ComfyUI editor-export document into the API prompt graph
// expected by POST /prompt (`{nodeId: {class_type, inputs}}`), using live
// node schemas rather than a hardcoded per-node-type mapper so custom nodes
// (Krea2EditGroundedEncode, Krea2EditModelPatch, ...) work unmodified.

import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/core/app_error.dart';

class ComfyGraphConversionResult {
  final Map<String, dynamic> apiGraph;
  const ComfyGraphConversionResult(this.apiGraph);
}

class ComfyGraphConverter {
  final ComfyNodeSchemaProvider schemaProvider;
  const ComfyGraphConverter(this.schemaProvider);

  /// [overrides] maps `"<nodeId>:<widgetName>"` to a replacement widget
  /// value (favorite edits, current prompt/negative-prompt text, uploaded
  /// image filenames). Anything not overridden falls back to the workflow's
  /// own saved `widgets_values`.
  ///
  /// The source [document] is never mutated: a clone is converted instead.
  Future<ComfyGraphConversionResult> convert(
    ComfyWorkflowDocument document, {
    Map<String, dynamic> overrides = const {},
  }) async {
    final doc = document.clone();
    final apiGraph = <String, dynamic>{};

    for (final node in doc.nodes) {
      if (!node.isActive) continue; // bypassed/muted nodes are never emitted

      final schema = await schemaProvider.schemaFor(node.type);
      if (!schema.known) {
        final participates = doc.links.any(
          (l) => l.originNodeId == node.id || l.targetNodeId == node.id,
        );
        if (!participates) {
          continue; // decorative node (e.g. Note): safe to drop
        }
        throw ValidationError('Node ${node.id} ("${node.type}"): could not load its node definition from the server');
      }

      final inputsMap = <String, dynamic>{};

      for (final inputSpec in schema.inputs) {
        final entry = node.inputEntry(inputSpec.name);
        final hasLink = entry != null && entry['link'] != null;

        if (hasLink) {
          final link = _linkById(doc, entry['link'] as num);
          if (link == null) {
            throw ValidationError('Node ${node.id}: input "${inputSpec.name}" references a missing link');
          }
          final resolved = _resolveEffectiveSource(
            doc,
            link.originNodeId,
            link.originSlot,
            link.type,
          );
          if (resolved == null) {
            if (inputSpec.isRequired) {
              throw ValidationError('Node ${node.id}: required input "${inputSpec.name}" has no active source '
                '(its connection passes through a bypassed/disabled node)');
            }
            continue; // optional + unresolvable through bypass chain: omit
          }
          inputsMap[inputSpec.name] = [resolved.$1.toString(), resolved.$2];
          continue;
        }

        // A widget-typed input the graph declares as a socket is a socket:
        // it has no stored value, and reading one would take the next
        // widget's. Unconnected and optional, so it is simply omitted.
        if (inputSpec.isWidgetCapable && !isSocketOnly(node, inputSpec.name)) {
          final overrideKey = '${node.id}:${inputSpec.name}';
          if (overrides.containsKey(overrideKey)) {
            inputsMap[inputSpec.name] = overrides[overrideKey];
            continue;
          }
          final slotIndex = widgetSlotIndexFor(schema, node, inputSpec.name);
          final values = node.widgetsValues;
          final value = (slotIndex != null && slotIndex < values.length)
              ? values[slotIndex]
              : inputSpec.options['default'];
          inputsMap[inputSpec.name] = value;
          continue;
        }

        if (inputSpec.isRequired) {
          throw ValidationError('Node ${node.id} ("${node.type}"): required input "${inputSpec.name}" is not connected');
        }
        // optional, unconnected, socket-only: omit
      }

      apiGraph[node.id.toString()] = {
        'class_type': node.type,
        'inputs': inputsMap,
      };
    }

    if (apiGraph.isEmpty) {
      throw const ValidationError('This workflow has no active nodes to run');
    }

    return ComfyGraphConversionResult(apiGraph);
  }

  ComfyEditorLink? _linkById(ComfyWorkflowDocument doc, num id) {
    for (final link in doc.links) {
      if (link.id == id.toInt()) return link;
    }
    return null;
  }

  /// Mirrors the ComfyUI frontend's bypass rerouting: an active node's
  /// output resolves directly; a bypassed node's output resolves through
  /// whichever of its own inputs shares the requested link [type], one hop
  /// at a time. Returns null when no active source can be found (dangling
  /// bypass chain), matching what the real frontend does when a bypassed
  /// node has nothing of a matching type to pass through.
  (int, int)? _resolveEffectiveSource(
    ComfyWorkflowDocument doc,
    int nodeId,
    int outputSlot,
    String type, {
    int depth = 0,
  }) {
    if (depth > 12) return null; // guards against cyclic/malformed graphs
    final node = doc.nodeById(nodeId);
    if (node == null || node.isMuted) return null;
    if (node.isActive) return (nodeId, outputSlot);

    // Bypassed: look for one of this node's own inputs of the same type
    // that has a link, and follow it.
    for (final input in node.inputs) {
      if (input['type'] != type) continue;
      final link = input['link'];
      if (link == null) continue;
      final upstream = _linkById(doc, link as num);
      if (upstream == null) continue;
      final resolved = _resolveEffectiveSource(
        doc,
        upstream.originNodeId,
        upstream.originSlot,
        type,
        depth: depth + 1,
      );
      if (resolved != null) return resolved;
    }
    return null;
  }
}
