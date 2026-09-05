// The bundled prompt-generator workflow, converted the way the engine
// converts it.
//
// It is here because this graph is the one that exposed a real hole in the
// slot arithmetic. `PromptGenerator.prompt_input` is declared STRING in
// `/object_info`, so the schema counted it as a widget - but the graph
// declares it as a plain socket, and the ComfyUI frontend gives such an
// input no `widgets_values` entry at all. Every widget after it therefore
// read one place early: the generator was handed the *model name* as its
// input text, and its model setting fell back to a default.
//
// A generator whose whole job is to write from nothing is exactly the node
// where being handed a stray input text is worst, and the mistake is
// invisible - the graph runs, it just runs wrong.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/data/engines/comfy/comfy_graph_converter.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';

late StaticComfyNodeSchemaProvider _schemas;
late ComfyGraphConverter _converter;

ComfyWorkflowDocument _bundled() => ComfyWorkflowDocument.parse(
    File('assets/comfy/prompt_generate.json').readAsStringSync());

Map<String, dynamic> _inputsOf(Map<String, dynamic> graph, String nodeId) =>
    ((graph[nodeId] as Map)['inputs'] as Map).cast<String, dynamic>();

void main() {
  setUpAll(() {
    _schemas = StaticComfyNodeSchemaProvider(
      jsonDecode(File('test/fixtures/comfy_object_info.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    _converter = ComfyGraphConverter(_schemas);
  });

  test('the bundled workflow is shaped the way the engine expects', () {
    final doc = _bundled();
    final types = {for (final node in doc.nodes) node.type};
    expect(types, contains('PromptGenerator'),
        reason: 'the engine finds the node it overrides by this type');
    expect(types, contains('PreviewAny'),
        reason: 'the text output is read back through PreviewAny');

    final generator = doc.nodes.firstWhere((n) => n.type == 'PromptGenerator');
    // No image, no prompt, nothing wired in from outside: this button takes
    // no input, which is the whole reason it is a second tool rather than a
    // mode of the enhancer.
    for (final entry in generator.inputs) {
      if (entry['name'] == 'options') continue; // its own settings node
      expect(entry['link'], isNull,
          reason: '${entry['name']} must not expect an input');
    }
  });

  test('the generator gets its own widgets, not the ones after them',
      () async {
    final doc = _bundled();
    final graph = (await _converter.convert(doc, overrides: {'7:seed': 42}))
        .apiGraph;
    final generator = _inputsOf(graph, '7');

    expect(generator.containsKey('prompt_input'), isFalse,
        reason: 'the graph declares it a socket, and it is not connected');
    expect(generator['model'], '(use default)',
        reason: 'reading one slot early left this on a schema default');
    expect(generator['system_prompt'], 'Image / Krea2');
    expect(generator['stop_server_after'], true);
    expect(generator['clear_vram_on_run'], true);
  });

  test('the intensity is what the user prompt carries', () async {
    // The bundled system prompt reads this node's `prompt` widget as a
    // number from 1 to 10 and nothing else, so that widget is the entire
    // interface between the app and what gets written.
    final graph = (await _converter
            .convert(_bundled(), overrides: {'7:prompt': '3'}))
        .apiGraph;
    expect(_inputsOf(graph, '7')['prompt'], '3');
    expect(_inputsOf(graph, '7')['prompt'], isA<String>(),
        reason: 'the widget is declared STRING; an int would be rejected');
  });

  test('a fresh seed is what makes a second press a second prompt', () async {
    // ComfyUI caches node outputs by their resolved inputs, so without this
    // the button would return the same sentence forever.
    final graph =
        (await _converter.convert(_bundled(), overrides: {'7:seed': 12345}))
            .apiGraph;
    expect(_inputsOf(graph, '7')['seed'], 12345);

    final untouched = (await _converter.convert(_bundled())).apiGraph;
    expect(_inputsOf(untouched, '7')['seed'], isNot(12345),
        reason: 'the stored seed is what the override exists to replace');
  });

  test('the whole graph converts and terminates in the text preview',
      () async {
    final graph = (await _converter.convert(_bundled())).apiGraph;
    // Three nodes, all active, all resolvable - anything unknown here would
    // have thrown rather than silently dropped.
    expect(graph.keys.toSet(), {'2', '7', '8'});
    expect((graph['2'] as Map)['class_type'], 'PreviewAny');
    expect(_inputsOf(graph, '2')['source'], ['7', 0],
        reason: 'the preview reads the generator output, not its thoughts');
    expect(_inputsOf(graph, '7')['options'], ['8', 0]);
  });
}
