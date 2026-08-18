import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/data/engines/comfy/comfy_graph_converter.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/core/app_error.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late ComfyWorkflowDocument doc;
  late StaticComfyNodeSchemaProvider schemaProvider;
  late ComfyGraphConverter converter;

  setUp(() {
    doc = ComfyWorkflowDocument(_loadFixture('krea2_identity_edit_workflow.json'));
    schemaProvider = StaticComfyNodeSchemaProvider(_loadFixture('comfy_object_info.json'));
    converter = ComfyGraphConverter(schemaProvider);
  });

  test('converts the reference workflow to a valid API graph', () async {
    final result = await converter.convert(doc);
    final graph = result.apiGraph;

    // Note nodes (100-107) are decorative and must be dropped.
    for (final noteId in [100, 101, 102, 103, 104, 105, 106, 107]) {
      expect(graph.containsKey('$noteId'), isFalse, reason: 'Note $noteId should be dropped');
    }

    // Bypassed nodes (90, 92) must not appear as graph entries.
    expect(graph.containsKey('90'), isFalse);
    expect(graph.containsKey('92'), isFalse);

    // SaveImage retained with its link to VAEDecode intact.
    expect(graph['29'], {
      'class_type': 'SaveImage',
      'inputs': {
        'images': ['54', 0],
        'filename_prefix': 'krea2_identity_edit',
      },
    });

    // KSampler: widget values preserved, positive/negative point at the
    // two Krea2EditGroundedEncode nodes.
    final ksampler = graph['53'] as Map<String, dynamic>;
    expect(ksampler['class_type'], 'KSampler');
    expect(ksampler['inputs']['model'], ['79', 0]);
    expect(ksampler['inputs']['positive'], ['84', 0]);
    expect(ksampler['inputs']['negative'], ['85', 0]);
    expect(ksampler['inputs']['latent_image'], ['82', 0]);
    expect(ksampler['inputs']['seed'], 1088049369132323);
    expect(ksampler['inputs']['steps'], 10);
    expect(ksampler['inputs']['cfg'], 1);
    expect(ksampler['inputs']['sampler_name'], 'euler');
    expect(ksampler['inputs']['scheduler'], 'simple');
    expect(ksampler['inputs']['denoise'], 1);
    // control_after_generate is a frontend-only widget slot, never sent.
    expect(ksampler['inputs'].containsKey('control_after_generate'), isFalse);

    // Custom node retained with its optional bypass-only links dropped and
    // its active links/widgets intact.
    final patch = graph['79'] as Map<String, dynamic>;
    expect(patch['class_type'], 'Krea2EditModelPatch');
    expect(patch['inputs']['model'], ['71', 0]);
    expect(patch['inputs']['source_latent'], ['73', 0]);
    expect(patch['inputs']['vae'], ['57', 0]);
    expect(patch['inputs']['source_image'], ['72', 0]);
    expect(patch['inputs']['target_latent'], ['82', 0]);
    expect(patch['inputs']['ref_boost'], 4);
    expect(patch['inputs']['ref_boost_a'], 1);
    expect(patch['inputs']['fit_mode'], 'fit');
    // These all traced back through the bypassed second-reference group.
    expect(patch['inputs'].containsKey('source_latent_b'), isFalse);
    expect(patch['inputs'].containsKey('source_image_b'), isFalse);
    expect(patch['inputs'].containsKey('ref_boost_mask'), isFalse);

    // Other custom node instance (negative) keeps its own image_b dropped too.
    final negative = graph['85'] as Map<String, dynamic>;
    expect(negative['class_type'], 'Krea2EditGroundedEncode');
    expect(negative['inputs']['clip'], ['56', 0]);
    expect(negative['inputs']['image'], ['72', 0]);
    expect(negative['inputs'].containsKey('image_b'), isFalse);
    expect(negative['inputs']['prompt'], '');
    expect(negative['inputs']['grounding_px'], 768);

    // LoadImage: only the filename widget is sent, not the synthetic
    // upload-mode slot.
    final loadImage = graph['72'] as Map<String, dynamic>;
    expect(loadImage['inputs'], {'image': 'example.png'});
  });

  test('applies overrides for favorited prompt/image/steps values', () async {
    final result = await converter.convert(
      doc,
      overrides: const {
        '84:prompt': 'Give her a blue jacket instead.',
        '72:image': 'uploaded_1234.png',
        '53:steps': 24,
      },
    );
    final graph = result.apiGraph;
    expect((graph['84'] as Map)['inputs']['prompt'], 'Give her a blue jacket instead.');
    expect((graph['72'] as Map)['inputs']['image'], 'uploaded_1234.png');
    expect((graph['53'] as Map)['inputs']['steps'], 24);
  });

  test('never mutates the source document', () async {
    final before = jsonEncode(doc.raw);
    await converter.convert(doc, overrides: const {'84:prompt': 'mutated?'});
    expect(jsonEncode(doc.raw), before);
  });

  test('throws a typed validation error for an unknown custom node with links', () async {
    final raw = _loadFixture('krea2_identity_edit_workflow.json');
    (raw['nodes'] as List).add({
      'id': 999,
      'type': 'SomeUnshippedCustomNode',
      'mode': 0,
      'inputs': [],
      'outputs': [
        {'name': 'IMAGE', 'type': 'IMAGE', 'links': [1000]},
      ],
      'widgets_values': [],
    });
    (raw['links'] as List).add([1000, 999, 0, 29, 0, 'IMAGE']);
    final badDoc = ComfyWorkflowDocument(raw);

    expect(
      () => converter.convert(badDoc),
      throwsA(isA<ValidationError>()),
    );
  });

  test('drops an unknown decorative node type with no links', () async {
    final raw = _loadFixture('krea2_identity_edit_workflow.json');
    (raw['nodes'] as List).add({
      'id': 998,
      'type': 'SomeDecorativeThing',
      'mode': 0,
      'inputs': [],
      'outputs': [],
      'widgets_values': [],
    });
    final result = await converter.convert(ComfyWorkflowDocument(raw));
    expect(result.apiGraph.containsKey('998'), isFalse);
  });
}
