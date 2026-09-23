// The two bundled prompt workflows, converted the way the engine converts
// them.
//
// Both are built on `LMStudioPromptGenerator`, whose own JavaScript adds six
// widgets `/object_info` has never heard of - a status line, a "Check
// connection" button, a "Copy response" button. Those occupy positions in
// `widgets_values`, so counting widgets from the schema alone lands seven
// places out: the temperature reads as a model name, the timeout as a
// temperature, and the server rejects the graph. `widgets_values_named` is
// the same data keyed by name and immune to it, which is why it is
// preferred wherever the export carries one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/data/engines/comfy/comfy_engine.dart';
import 'package:sd_companion/data/engines/comfy/comfy_graph_converter.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';

late StaticComfyNodeSchemaProvider _schemas;
late ComfyGraphConverter _converter;

ComfyWorkflowDocument _asset(String name) =>
    ComfyWorkflowDocument.parse(File('assets/comfy/$name').readAsStringSync());

Map<String, dynamic> _inputsOf(Map<String, dynamic> graph, String nodeId) =>
    ((graph[nodeId] as Map)['inputs'] as Map).cast<String, dynamic>();

/// The generator node in a converted graph, whichever id it happens to have.
Map<String, dynamic> _generatorOf(Map<String, dynamic> graph) => graph.values
    .cast<Map<String, dynamic>>()
    .firstWhere((n) => n['class_type'] == 'LMStudioPromptGenerator')['inputs'] as Map<String, dynamic>;

void main() {
  setUpAll(() {
    _schemas = StaticComfyNodeSchemaProvider(
      jsonDecode(File('test/fixtures/comfy_object_info.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    _converter = ComfyGraphConverter(_schemas);
  });

  group('every widget reaches the node it belongs to', () {
    for (final asset in ['prompt_generate.json', 'img2prompt.json']) {
      test(asset, () async {
        final graph = (await _converter.convert(_asset(asset))).apiGraph;
        final generator = _generatorOf(graph);

        // The values either side of the JS-injected widgets. Read
        // positionally, `temperature` comes back as the model name and the
        // server rejects the whole graph.
        expect(generator['server_url'], 'http://localhost:1234');
        expect(generator['temperature'], isA<num>());
        expect(generator['max_tokens'], isA<num>());
        expect(generator['timeout'], 300);
        expect(generator['seed'], isA<num>());
        expect(generator['reasoning'], 'low');
        expect(generator['unload_after'], false);
        expect(generator['save_to_chat_history'], false);
        expect('${generator['system_prompt']}', startsWith('You are a raw'));
        expect(generator['model'],
            'huihui-gemma-4-e4b-it-qat-unquantized-abliterated');

        // Neither workflow leaves anything for the frontend's own widgets:
        // they are not inputs, and sending them would be rejected.
        expect(generator.containsKey('status'), isFalse);
        expect(generator.containsKey('Copy response'), isFalse);
      });
    }
  });

  test('the writer terminates in the text preview, taking no input',
      () async {
    final doc = _asset('prompt_generate.json');
    final graph = (await _converter.convert(doc)).apiGraph;
    expect(graph.length, 2, reason: 'a generator and a preview, nothing else');

    final preview = graph.values
        .cast<Map<String, dynamic>>()
        .firstWhere((n) => n['class_type'] == 'PreviewAny');
    // Output 0 is `text`; 1 is `thinking` and 2 is `stats`, neither of which
    // is the prompt.
    expect((preview['inputs'] as Map)['source'][1], 0);

    final generator =
        doc.nodes.firstWhere((n) => n.type == 'LMStudioPromptGenerator');
    for (final entry in generator.inputs) {
      expect(entry['link'], isNull,
          reason: 'the writer takes nothing but its own dial');
    }
  });

  test('the describer reads the uploaded image', () async {
    final doc = _asset('img2prompt.json');
    final loadImage = doc.nodes.firstWhere((n) => n.type == 'LoadImage');
    final graph = (await _converter
            .convert(doc, overrides: {'${loadImage.id}:image': 'upload.png'}))
        .apiGraph;

    expect(_inputsOf(graph, '${loadImage.id}')['image'], 'upload.png');
    expect(_generatorOf(graph)['image'], ['${loadImage.id}', 0],
        reason: 'the caption is of the picture, so it must be wired to it');
  });

  group('intensity', () {
    test('replaces the last number in the user prompt, and nothing else', () {
      expect(withIntensity('Make it good. Intensity level: 1', 7),
          'Make it good. Intensity level: 7');
      // The wording is the workflow's to change; only the number is ours.
      expect(withIntensity('2 paragraphs, graphic. Intensity level: 10', 3),
          '2 paragraphs, graphic. Intensity level: 3');
    });

    test('is clamped, and appended when there is nothing to replace', () {
      expect(withIntensity('Intensity level: 5', 99), 'Intensity level: 10');
      expect(withIntensity('Intensity level: 5', 0), 'Intensity level: 1');
      expect(withIntensity('no numbers here', 4), 'no numbers here 4');
    });

    test('the bundled user prompt really does end in a number', () {
      final doc = _asset('prompt_generate.json');
      final generator =
          doc.nodes.firstWhere((n) => n.type == 'LMStudioPromptGenerator');
      final stored = '${generator.widgetsValuesNamed!['user_prompt']}';
      expect(RegExp(r'\d+$').hasMatch(stored.trim()), isTrue,
          reason: 'the dial writes over the last number, so there must be '
              'one at the end for it to write over');
      expect(withIntensity(stored, 8), endsWith('8'));
    });
  });
}
