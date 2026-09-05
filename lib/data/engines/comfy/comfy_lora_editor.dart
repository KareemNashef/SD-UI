// ==================== Comfy LoRA Editor ==================== //
//
// Adds and removes LoRA loaders in a workflow's model chain.
//
// A LoRA in ComfyUI is not a setting, it is a *node*: it has to be spliced
// into the wire between the model loader and whatever consumes the model,
// and unspliced again on the way out. That is the whole reason using LoRAs
// from a phone was awkward - the app could edit values on nodes that already
// existed, but not change the shape of the graph.
//
// The surgery is deliberately minimal. Adding reuses the link that was
// already there for the new node's *output* and creates only one new link,
// for its input - so the downstream node's own `inputs` entry never has to
// be touched. Removing does the mirror image: every link leaving the node is
// repointed at that node's own upstream source, so again no downstream entry
// changes. Fewer edits, fewer ways to leave a graph inconsistent.
//
// Everything here works on the editor-export document, which is what gets
// persisted and what `ComfyGraphConverter` reads - so a spliced-in LoRA is
// indistinguishable from one drawn in ComfyUI itself, and the workflow still
// opens correctly there.

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/data/engines/comfy/workflow_auto_detector.dart';

class ComfyLoraEditor {
  final ComfyNodeSchemaProvider schemaProvider;
  const ComfyLoraEditor(this.schemaProvider);

  /// Splices a new LoRA loader into [doc], at the end of the existing run of
  /// LoRAs or immediately after the model loader when there are none - so
  /// the list in the UI reads in the order the model flows through it.
  ///
  /// [doc] is mutated. Returns the new node's id.
  Future<int> add(
    ComfyWorkflowDocument doc,
    DetectedWorkflowSettings detected, {
    required String file,
    double strength = 1,
  }) async {
    final type = detected.loraLoaderType;
    if (type == null) {
      throw const ValidationError(
          'This server has no LoRA loader this app can wire up on its own');
    }
    final chain = detected.modelChain;
    if (chain.length < 2) {
      throw const ValidationError(
          'Could not find the model chain to add a LoRA to');
    }

    final schema = await schemaProvider.schemaFor(type);
    ComfyInputSpec? modelInput;
    for (final input in schema.inputs) {
      if (!input.isWidgetCapable && input.type == 'MODEL') {
        modelInput = input;
        break;
      }
    }
    if (!schema.known || modelInput == null) {
      throw ValidationError('The server did not describe "$type"');
    }

    // Splice after the last existing LoRA, else straight after the loader.
    var afterIndex = 0;
    if (detected.loras.isNotEmpty) {
      final index = chain.indexOf(detected.loras.last.nodeId);
      if (index >= 0 && index < chain.length - 1) afterIndex = index;
    }
    final upstreamId = chain[afterIndex];
    final downstreamId = chain[afterIndex + 1];

    final carrier = _rawLink(doc, upstreamId, downstreamId);
    if (carrier == null) {
      throw const ValidationError(
          'The model chain is wired in a way this cannot splice into');
    }
    final carrierId = (carrier[0] as num).toInt();
    final originSlot = (carrier[2] as num).toInt();

    final nodeId = _nextNodeId(doc);
    final linkId = _nextLinkId(doc);

    // The new link feeds the LoRA; the link that was already there is
    // repointed to leave the LoRA, so the downstream node still refers to
    // the same link id it always did.
    carrier[1] = nodeId;
    carrier[2] = 0;

    (doc.raw['links'] as List).add(
      <dynamic>[linkId, upstreamId, originSlot, nodeId, 0, 'MODEL'],
    );
    _replaceOutputLink(doc, upstreamId, originSlot, carrierId, linkId);

    final fileSlot = _fileWidgetName(schema);
    final strengthSlot = _strengthWidgetName(schema);
    final values = <dynamic>[];
    for (final slot in schema.widgetSlots) {
      if (slot.name == fileSlot) {
        values.add(file);
      } else if (slot.name == strengthSlot) {
        values.add(strength);
      } else {
        values.add(slot.options['default']);
      }
    }

    final anchorPos = (doc.nodeById(upstreamId)?.raw['pos'] as List?) ?? const [];
    final x = anchorPos.isNotEmpty ? (anchorPos[0] as num).toDouble() : 0.0;
    final y = anchorPos.length > 1 ? (anchorPos[1] as num).toDouble() : 0.0;

    (doc.raw['nodes'] as List).add(<String, dynamic>{
      'id': nodeId,
      'type': type,
      // Stacked below whatever it was spliced after, so the graph is still
      // readable if this workflow is opened in ComfyUI later.
      'pos': <dynamic>[x, y + 160],
      'size': <dynamic>[340, 100],
      'flags': <String, dynamic>{},
      'order': 0, // ComfyUI recomputes execution order on load
      'mode': 0,
      'inputs': <dynamic>[
        <String, dynamic>{
          'name': modelInput.name,
          'type': 'MODEL',
          'link': linkId,
        },
      ],
      'outputs': <dynamic>[
        <String, dynamic>{
          'name':
              schema.outputNames.isEmpty ? 'MODEL' : schema.outputNames.first,
          'type': 'MODEL',
          'links': <dynamic>[carrierId],
        },
      ],
      'properties': <String, dynamic>{'Node name for S&R': type},
      'widgets_values': values,
    });

    doc.raw['last_node_id'] = nodeId;
    doc.raw['last_link_id'] = linkId;
    return nodeId;
  }

  /// Unsplices the LoRA node [nodeId], reconnecting whatever it fed to
  /// whatever fed it. [doc] is mutated.
  void remove(ComfyWorkflowDocument doc, int nodeId) {
    final links = (doc.raw['links'] as List?) ?? <dynamic>[];
    List<dynamic>? incoming;
    final outgoing = <List<dynamic>>[];
    for (final raw in links) {
      if (raw is! List || raw.length < 6) continue;
      if ((raw[3] as num).toInt() == nodeId) incoming = raw;
      if ((raw[1] as num).toInt() == nodeId) outgoing.add(raw);
    }
    if (incoming == null) {
      throw const ValidationError('That LoRA is not wired into the chain');
    }
    final incomingId = (incoming[0] as num).toInt();
    final sourceId = (incoming[1] as num).toInt();
    final sourceSlot = (incoming[2] as num).toInt();

    // Everything the LoRA fed now comes straight from the LoRA's own source,
    // keeping its link id - so no downstream `inputs` entry has to change.
    for (final raw in outgoing) {
      raw[1] = sourceId;
      raw[2] = sourceSlot;
    }
    links.remove(incoming);

    _replaceOutputLink(
      doc,
      sourceId,
      sourceSlot,
      incomingId,
      null,
      add: [for (final raw in outgoing) (raw[0] as num).toInt()],
    );

    (doc.raw['nodes'] as List?)?.removeWhere(
      (n) => n is Map && (n['id'] as num?)?.toInt() == nodeId,
    );
  }

  // ===== Helpers ===== //

  static String? _fileWidgetName(ComfyNodeSchema schema) {
    for (final slot in schema.widgetSlots) {
      if (slot.type == 'COMBO' && slot.name.toLowerCase().contains('lora')) {
        return slot.name;
      }
    }
    return null;
  }

  static String? _strengthWidgetName(ComfyNodeSchema schema) {
    for (final slot in schema.widgetSlots) {
      if (slot.type == 'FLOAT') return slot.name;
    }
    return null;
  }

  static List<dynamic>? _rawLink(
    ComfyWorkflowDocument doc,
    int originId,
    int targetId,
  ) {
    for (final raw in (doc.raw['links'] as List?) ?? const []) {
      if (raw is! List || raw.length < 6) continue;
      if ((raw[1] as num).toInt() == originId &&
          (raw[3] as num).toInt() == targetId &&
          raw[5] == 'MODEL') {
        return raw;
      }
    }
    return null;
  }

  /// Keeps a node's `outputs[slot].links` honest. Nothing in this app reads
  /// it for generation - the converter walks `inputs` - but ComfyUI does,
  /// and a workflow exported from here should still open there.
  static void _replaceOutputLink(
    ComfyWorkflowDocument doc,
    int nodeId,
    int slot,
    int oldLinkId,
    int? newLinkId, {
    List<int> add = const [],
  }) {
    final node = doc.nodeById(nodeId);
    if (node == null) return;
    final outputs = node.raw['outputs'];
    if (outputs is! List || slot >= outputs.length) return;
    final output = outputs[slot];
    if (output is! Map) return;
    final links = (output['links'] as List?)?.toList() ?? <dynamic>[];
    links.removeWhere((id) => (id as num?)?.toInt() == oldLinkId);
    if (newLinkId != null) links.add(newLinkId);
    for (final id in add) {
      if (!links.any((existing) => (existing as num?)?.toInt() == id)) {
        links.add(id);
      }
    }
    output['links'] = links;
  }

  static int _nextNodeId(ComfyWorkflowDocument doc) {
    var highest = (doc.raw['last_node_id'] as num?)?.toInt() ?? 0;
    for (final node in doc.nodes) {
      if (node.id > highest) highest = node.id;
    }
    return highest + 1;
  }

  static int _nextLinkId(ComfyWorkflowDocument doc) {
    var highest = (doc.raw['last_link_id'] as num?)?.toInt() ?? 0;
    for (final link in doc.links) {
      if (link.id > highest) highest = link.id;
    }
    return highest + 1;
  }
}
