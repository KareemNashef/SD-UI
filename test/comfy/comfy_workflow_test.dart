import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/logic/comfy/comfy_workflow.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('ComfyWorkflowDocument', () {
    late ComfyWorkflowDocument doc;

    setUp(() {
      doc = ComfyWorkflowDocument(
        _loadFixture('krea2_identity_edit_workflow.json'),
      );
    });

    test('parses the editor-format fixture', () {
      expect(doc.isApiFormat, isFalse);
      expect(doc.nodes, isNotEmpty);
      expect(doc.nodeById(84)?.type, 'Krea2EditGroundedEncode');
      expect(doc.nodeById(72)?.type, 'LoadImage');
    });

    test('preserves node ids, bypass mode, widget values and links', () {
      final loadImage90 = doc.nodeById(90)!;
      expect(loadImage90.isBypassed, isTrue);
      expect(loadImage90.widgetsValues, ['example_person.png', 'image']);

      final ksampler = doc.nodeById(53)!;
      expect(ksampler.isActive, isTrue);
      expect(ksampler.widgetsValues, [
        1088049369132323,
        'randomize',
        10,
        1,
        'euler',
        'simple',
        1,
      ]);

      expect(doc.links, isNotEmpty);
      final saveImageLink = doc.links.firstWhere((l) => l.targetNodeId == 29);
      expect(saveImageLink.originNodeId, 54);
      expect(saveImageLink.type, 'IMAGE');
    });

    test('clone() deep-copies so mutations never touch the source', () {
      final clone = doc.clone();
      clone.nodeById(84)!.widgetsValues = ['mutated', 768, ''];

      expect(doc.nodeById(84)!.widgetsValues[0], 'Change her outfit to a red raincoat.');
      expect(clone.nodeById(84)!.widgetsValues[0], 'mutated');
    });

    test('validation accepts the reference fixture cleanly', () {
      final validation = ComfyWorkflowValidation.of(doc);
      expect(validation.isValid, isTrue, reason: validation.issues.map((i) => i.message).join('; '));
    });
  });

  group('ComfyWorkflowValidation', () {
    test('flags a link pointing at a missing node', () {
      final raw = _loadFixture('krea2_identity_edit_workflow.json');
      (raw['links'] as List).add([9999, 999, 0, 53, 0, 'MODEL']);
      final validation = ComfyWorkflowValidation.of(ComfyWorkflowDocument(raw));
      expect(validation.isValid, isFalse);
      expect(
        validation.blockingIssues.any((i) => i.message.contains('999')),
        isTrue,
      );
    });

    test('rejects a document with no nodes array', () {
      final validation = ComfyWorkflowValidation.of(
        ComfyWorkflowDocument({'not_a_workflow': true}),
      );
      expect(validation.isValid, isFalse);
    });

    test('accepts an API-format graph without editor-shape checks', () {
      final validation = ComfyWorkflowValidation.of(
        ComfyWorkflowDocument({
          '1': {
            'class_type': 'KSampler',
            'inputs': {'seed': 1},
          },
        }),
      );
      expect(validation.isValid, isTrue);
    });
  });
}
