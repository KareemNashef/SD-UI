// Graph surgery is the one place in this app that changes a workflow's
// *shape* rather than a value on it, so these tests check the wiring
// itself: after every add and remove the document must still convert into
// a runnable API graph with the model flowing through exactly the nodes it
// is supposed to, and no link pointing at anything that is gone.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/data/engines/comfy/comfy_graph_converter.dart';
import 'package:sd_companion/data/engines/comfy/comfy_lora_editor.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/data/engines/comfy/workflow_auto_detector.dart';

late StaticComfyNodeSchemaProvider _schemas;
late WorkflowAutoDetector _detector;
late ComfyLoraEditor _editor;

ComfyWorkflowDocument _loadDoc(String name) => ComfyWorkflowDocument(
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>);

/// Where each node gets its MODEL from, as the API graph states it.
Future<Map<String, dynamic>> _apiGraph(ComfyWorkflowDocument doc) async =>
    (await ComfyGraphConverter(_schemas).convert(doc)).apiGraph;

dynamic _modelSourceOf(Map<String, dynamic> graph, int nodeId) =>
    (graph['$nodeId'] as Map)['inputs']['model'];

/// Every link must join two nodes that exist, and every input entry must
/// name a link that exists. A splice that breaks either of these produces a
/// workflow ComfyUI refuses to open, which is not something a conversion
/// test would necessarily notice.
void _expectWiringIsSound(ComfyWorkflowDocument doc) {
  final linkIds = {for (final link in doc.links) link.id};
  final nodeIds = {for (final node in doc.nodes) node.id};
  for (final link in doc.links) {
    expect(nodeIds, contains(link.originNodeId),
        reason: 'link ${link.id} comes from a node that is gone');
    expect(nodeIds, contains(link.targetNodeId),
        reason: 'link ${link.id} goes to a node that is gone');
  }
  for (final node in doc.nodes) {
    for (final entry in node.inputs) {
      final id = entry['link'];
      if (id == null) continue;
      expect(linkIds, contains((id as num).toInt()),
          reason: 'node ${node.id} input "${entry['name']}" points at a '
              'link that no longer exists');
    }
    // Nothing in this app reads `outputs[].links` - the converter walks
    // inputs - so a splice could corrupt it silently and only show up when
    // the workflow was next opened in ComfyUI.
    for (var slot = 0; slot < node.outputs.length; slot++) {
      final declared = ((node.outputs[slot]['links'] as List?) ?? const [])
          .map((id) => (id as num).toInt())
          .toSet();
      final actual = {
        for (final link in doc.links)
          if (link.originNodeId == node.id && link.originSlot == slot) link.id,
      };
      expect(declared, actual,
          reason: 'node ${node.id} output $slot lists the wrong links');
    }
  }
}

void main() {
  setUpAll(() {
    _schemas = StaticComfyNodeSchemaProvider(
      jsonDecode(File('test/fixtures/comfy_object_info.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    _detector = WorkflowAutoDetector(_schemas);
    _editor = ComfyLoraEditor(_schemas);
  });

  group('adding', () {
    test('splices onto the end of an existing LoRA run', () async {
      final doc = _loadDoc('krea-edit-multi-lora.json');
      final added = await _editor.add(
        doc,
        await _detector.detect(doc),
        file: 'extra.safetensors',
        strength: 0.65,
      );

      _expectWiringIsSound(doc);
      final result = await _detector.detect(doc);
      // Chain was 26 -> 6 -> 30 -> 31 -> 9 -> 2; the new node lands after
      // the last LoRA, not after the loader and not after the Krea2 patch.
      expect(result.modelChain, [26, 6, 30, 31, added, 9, 2]);
      expect(result.loras.map((l) => l.nodeId).toList(), [6, 30, 31, added]);
      expect(result.loras.last.fileName, 'extra.safetensors');
      expect(result.loras.last.strengthValue, 0.65);
    });

    test('the spliced node is what actually gets run', () async {
      final doc = _loadDoc('krea-edit-multi-lora.json');
      final added = await _editor.add(doc, await _detector.detect(doc),
          file: 'extra.safetensors', strength: 0.65);

      final graph = await _apiGraph(doc);
      expect(graph.containsKey('$added'), isTrue);
      expect((graph['$added'] as Map)['class_type'], 'LoraLoaderModelOnly');
      expect((graph['$added'] as Map)['inputs']['lora_name'],
          'extra.safetensors');
      expect((graph['$added'] as Map)['inputs']['strength_model'], 0.65);
      // Fed by the last old LoRA, feeding what that LoRA used to feed.
      expect(_modelSourceOf(graph, added), ['31', 0]);
      expect(_modelSourceOf(graph, 9), ['$added', 0]);
    });

    test('goes straight after the loader when there is no LoRA yet', () async {
      final doc = _loadDoc('qwen-img2img.json');
      final before = await _detector.detect(doc);
      expect(before.loras, isEmpty);

      final added = await _editor.add(doc, before, file: 'first.safetensors');
      _expectWiringIsSound(doc);

      final result = await _detector.detect(doc);
      // Loader(101) -> ModelSamplingAuraFlow(66) -> CFGNorm(75) -> KSampler(3),
      // so the LoRA belongs between the loader and the first patch.
      expect(result.modelChain, [101, added, 66, 75, 3]);
      expect(result.loras.single.strengthValue, 1,
          reason: 'a new LoRA starts at full strength');

      final graph = await _apiGraph(doc);
      expect(_modelSourceOf(graph, added), ['101', 0]);
      expect(_modelSourceOf(graph, 66), ['$added', 0]);
    });
  });

  group('removing', () {
    test('reconnects the chain around the node it takes out', () async {
      final doc = _loadDoc('krea-edit-multi-lora.json');
      _editor.remove(doc, 30); // the middle of the three

      _expectWiringIsSound(doc);
      expect(doc.nodeById(30), isNull);

      final result = await _detector.detect(doc);
      expect(result.modelChain, [26, 6, 31, 9, 2]);
      expect(result.loras.map((l) => l.nodeId).toList(), [6, 31]);

      final graph = await _apiGraph(doc);
      expect(graph.containsKey('30'), isFalse);
      expect(_modelSourceOf(graph, 31), ['6', 0],
          reason: 'the node after the removed one now reads from the node '
              'before it');
    });

    test('taking out the last one still reaches the sampler', () async {
      final doc = _loadDoc('krea-edit-multi-lora.json');
      _editor.remove(doc, 31);

      _expectWiringIsSound(doc);
      final graph = await _apiGraph(doc);
      expect(_modelSourceOf(graph, 9), ['30', 0]);
    });

    test('an add and a matching remove leave the graph as it was', () async {
      final original = _loadDoc('krea-edit-multi-lora.json');
      final before = await _apiGraph(original);

      final doc = _loadDoc('krea-edit-multi-lora.json');
      final added = await _editor.add(doc, await _detector.detect(doc),
          file: 'extra.safetensors');
      _editor.remove(doc, added);

      _expectWiringIsSound(doc);
      expect(await _apiGraph(doc), before);
    });
  });
}
