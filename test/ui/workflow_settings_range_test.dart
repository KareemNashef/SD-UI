// The ruler bands the settings drawer draws. ComfyUI's declared bounds are
// what the node's code tolerates, not what is worth generating: `cfg` is
// 0-100 and `ref_boost` 0-1000, both of which put every value anyone
// actually uses inside the first few pixels of a phone-width ruler.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/ui/stage/workflow_settings.dart';

late StaticComfyNodeSchemaProvider _schemas;

Future<ComfyInputSpec> _input(String nodeType, String name) async {
  final schema = await _schemas.schemaFor(nodeType);
  return schema.inputByName(name)!;
}

void main() {
  setUpAll(() {
    _schemas = StaticComfyNodeSchemaProvider(
      jsonDecode(File('test/fixtures/comfy_object_info.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  test('a narrowed band overrides the schema bounds', () async {
    final cfg = await _input('KSampler', 'cfg');
    expect(cfg.options['max'], 100, reason: 'the schema really does say 100');
    final range = rulerRange(cfg)!;
    expect(range.min, 0);
    expect(range.max, 10);

    final megapixels = await _input('ResolutionSelector', 'megapixels');
    expect(megapixels.options['max'], 16);
    expect(rulerRange(megapixels)!.min, 0.5);
    expect(rulerRange(megapixels)!.max, 3);

    final refBoost = await _input('Krea2EditModelPatch', 'ref_boost');
    expect(refBoost.options['max'], 1000);
    expect(rulerRange(refBoost)!.min, 1);
    expect(rulerRange(refBoost)!.max, 15);
  });

  test('every narrowed band divides into a usable number of steps', () {
    for (final entry in narrowedRanges.entries) {
      final range = entry.value;
      expect(range.max, greaterThan(range.min), reason: entry.key);
      final divisions = (range.max - range.min) / range.step!;
      expect(divisions, lessThanOrEqualTo(1000),
          reason: '${entry.key} would fall back to a continuous ruler');
      expect(divisions, greaterThan(4), reason: '${entry.key} is too coarse');
    }
  });

  test('an unnarrowed widget keeps its declared bounds', () async {
    final multiple = await _input('ResolutionSelector', 'multiple');
    final range = rulerRange(multiple)!;
    expect(range.min, 8);
    expect(range.max, 128);
  });

  test('steps is held to what a sampler can actually use', () async {
    final steps = await _input('KSampler', 'steps');
    expect(steps.options['max'], 10000, reason: 'the schema really says that');
    final range = rulerRange(steps)!;
    expect(range.min, 4);
    expect(range.max, 50);
  });

  test('seed gets no ruler at all', () async {
    expect(rulerRange(await _input('KSampler', 'seed')), isNull,
        reason: 'a 2^64 span would move billions of values per pixel');
  });
}
