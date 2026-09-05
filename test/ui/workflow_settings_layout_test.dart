// The settings page was one flat scroll of every widget the graph exposes.
// Against a real Krea2 edit workflow that is seventeen controls plus a LoRA
// list, all weighted the same, so finding "steps" meant scrolling past the
// VAE loader. These pin the arrangement that replaced it - which tab each
// setting lands on, what stays behind the fold, and that nothing is shown
// twice.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow.dart';
import 'package:sd_companion/data/engines/comfy/comfy_workflow_service.dart';
import 'package:sd_companion/data/engines/comfy/lora_manager_client.dart';
import 'package:sd_companion/data/engines/comfy/model_library.dart';
import 'package:sd_companion/data/engines/comfy/workflow_auto_detector.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/ui/stage/workflow_settings.dart';

late StaticComfyNodeSchemaProvider _schemas;
late WorkflowAutoDetector _detector;

Future<DetectedWorkflowSettings> _detect(String fixture) async {
  final doc = ComfyWorkflowDocument(
      jsonDecode(File('test/fixtures/$fixture').readAsStringSync())
          as Map<String, dynamic>);
  return _detector.detect(doc);
}

List<String> _names(List<DetectedWidget> settings) =>
    [for (final s in settings) s.input.name];

List<String> _primary(SettingsTab tab, DetectedWorkflowSettings d) =>
    _names(settingsForTab(tab, d).where((s) => !isAdvancedSetting(s)).toList());

List<String> _advanced(SettingsTab tab, DetectedWorkflowSettings d) =>
    _names(settingsForTab(tab, d).where(isAdvancedSetting).toList());

/// A library that answers with nothing, so the model tiles fall back to
/// filenames instead of reaching the network.
ModelLibrary _emptyLibrary() => ModelLibrary(
      const EngineEndpoint(
          kind: EngineKind.comfy, host: '127.0.0.1', port: '8188'),
      client: LoraManagerClient(
        const EngineEndpoint(
            kind: EngineKind.comfy, host: '127.0.0.1', port: '8188'),
        client: MockClient((_) async => http.Response('nope', 404)),
      ),
    );

void main() {
  setUpAll(() {
    _schemas = StaticComfyNodeSchemaProvider(
      jsonDecode(File('test/fixtures/comfy_object_info.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    _detector = WorkflowAutoDetector(_schemas);
  });

  group('krea-realism-img2img (the workflow that overcrowded the drawer)', () {
    late DetectedWorkflowSettings detected;

    setUp(() async {
      detected = await _detect('krea-realism-img2img.json');
    });

    test('the settings split across four tabs', () {
      expect(tabsFor(detected).map((t) => t.label).toList(),
          ['Output', 'Sampling', 'Model', 'LoRAs']);
    });

    test('each tab carries only what belongs to it', () {
      expect(_primary(SettingsTab.output, detected),
          ['aspect_ratio', 'megapixels', 'batch_size']);
      expect(_primary(SettingsTab.sampling, detected),
          ['seed', 'steps', 'cfg', 'sampler_name', 'scheduler', 'denoise']);
      // The model file comes first, then the dials on the nodes the model is
      // patched through on its way to the sampler.
      expect(_primary(SettingsTab.model, detected),
          ['unet_name', 'ref_boost', 'ref_boost_a', 'fit_mode']);
    });

    test('plumbing goes behind the fold, tuning stays on the face', () {
      // `multiple` is flagged advanced by ComfyUI itself; the CLIP and VAE
      // loaders are set once with the workflow and never tuned.
      expect(_advanced(SettingsTab.output, detected), ['multiple']);
      expect(_advanced(SettingsTab.model, detected),
          ['clip_name', 'type', 'vae_name']);
      expect(_advanced(SettingsTab.sampling, detected), isEmpty,
          reason: 'every sampler widget is something you actually turn');
    });

    test('no tab is as long as the list it replaced', () {
      final flat = detected.latentSettings.length +
          detected.samplerSettings.length +
          detected.modelSettings.length +
          detected.clipSettings.length +
          detected.vaeSettings.length;
      expect(flat, 17, reason: 'this is what used to be one scroll');

      for (final tab in tabsFor(detected)) {
        expect(_primary(tab, detected).length, lessThanOrEqualTo(6),
            reason: '${tab.label} is crowded again');
      }
    });

    test('no setting appears on two tabs', () {
      final seen = <String>{};
      for (final tab in tabsFor(detected)) {
        for (final setting in settingsForTab(tab, detected)) {
          expect(seen.add('${setting.node.id}:${setting.input.name}'), isTrue,
              reason: '${setting.input.name} is shown twice');
        }
      }
    });
  });

  test('a checkpoint loader is not listed three times', () async {
    // CheckpointLoaderSimple emits MODEL, CLIP and VAE from one node, so the
    // detector - tracing each chain separately, as it has to - reaches the
    // same `ckpt_name` widget three times.
    final detected = await _detect('illustrious-inpainting.json');
    final model = settingsForTab(SettingsTab.model, detected);
    expect(_names(model).where((n) => n == 'ckpt_name'), hasLength(1));
    expect(_advanced(SettingsTab.model, detected), isEmpty,
        reason: 'the duplicates were the only thing in the fold');
  });

  test('an img2img graph has no Output tab at all', () async {
    // Its size comes from the input image, so there is no latent to shape.
    final detected = await _detect('qwen-img2img.json');
    expect(tabsFor(detected).map((t) => t.label).toList(),
        ['Sampling', 'Model', 'LoRAs']);
  });

  testWidgets('the page shows one tab at a time and can reach the rest',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final detected = await _detect('krea-realism-img2img.json');
    final workflows = ComfyWorkflowService()..activeDetected.value = detected;
    final library = _emptyLibrary();
    addTearDown(library.dispose);

    await tester.pumpWidget(MaterialApp(
      home: WorkflowSettingsPage(
        workflows: workflows,
        library: library,
        title: 'Krea realism',
      ),
    ));
    await tester.pump();

    // Opens on Output. Sampling's controls exist but are not built - that is
    // the entire point of the tabs.
    expect(find.text('MEGAPIXELS'), findsOneWidget);
    expect(find.text('STEPS'), findsNothing);
    expect(find.text('CLIP LOADER'), findsNothing,
        reason: 'a different tab, and behind a fold even there');

    // The fold names how much it is hiding, and opens.
    expect(find.text('ADVANCED'), findsOneWidget);
    expect(find.text('MULTIPLE OF'), findsNothing);
    await tester.tap(find.text('ADVANCED'));
    await tester.pumpAndSettle();
    expect(find.text('MULTIPLE OF'), findsOneWidget);

    await tester.tap(find.text('Sampling'));
    await tester.pumpAndSettle();
    expect(find.text('STEPS'), findsOneWidget);
    expect(find.text('GUIDANCE'), findsOneWidget);
    expect(find.text('MEGAPIXELS'), findsNothing);
    expect(find.text('ADVANCED'), findsNothing,
        reason: 'nothing on this tab is plumbing');

    // Help is off by default; turning it on prints the node's own tooltip.
    expect(find.textContaining('Classifier-Free Guidance'), findsNothing);
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Classifier-Free Guidance'), findsOneWidget);

    await tester.tap(find.text('LoRAs'));
    await tester.pumpAndSettle();
    expect(find.text('LORA 1'), findsOneWidget);
    expect(find.text('LORA 2'), findsOneWidget);
    expect(find.text('Add LoRA'), findsOneWidget);
  });
}
