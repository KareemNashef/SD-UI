// Pinned against the shapes the live ComfyUI-Lora-Manager addon actually
// returns, captured by calling it on a running server.
//
// The load-bearing one is the name matching. The addon and ComfyUI describe
// the same file two different ways - `folder: "krea"` plus an absolute
// POSIX path on one side, `krea\file.safetensors` on the other - and if
// they fail to line up the browser silently shows every model as unknown,
// or worse, writes a name into the graph that the node will not load.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sd_companion/data/engines/comfy/lora_manager_client.dart';
import 'package:sd_companion/data/engines/comfy/model_library.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/ui/stage/model_browser_page.dart';

const _root = 'C:/Users/someone/ComfyUI/models';

Map<String, dynamic> loraJson({
  String name = 'Realism Enhancer Krea2',
  String fileName = 'SummerVibesHM_krea2_epoch8',
  String folder = 'krea',
  String extension = '.safetensors',
  String previewExtension = '.jpeg',
}) =>
    {
      'model_name': name,
      'file_name': fileName,
      'folder': folder,
      'file_path': '$_root/loras/$folder/$fileName$extension',
      'preview_url': '/api/lm/previews?path='
          '${Uri.encodeComponent('$_root/loras/$folder/$fileName$previewExtension')}',
      'base_model': 'Krea 2',
      'file_size': 228587200,
      'tags': ['krea2', 'concept', 'realism'],
      'favorite': false,
    };

String listBody(List<Map<String, dynamic>> items,
        {int page = 1, int totalPages = 1}) =>
    jsonEncode({
      'items': items,
      'total': items.length,
      'page': page,
      'page_size': 100,
      'total_pages': totalPages,
    });

const _endpoint = EngineEndpoint(
  kind: EngineKind.comfy,
  host: '10.0.0.5',
  port: '8188',
);

void main() {
  group('parsing', () {
    test('a listing entry keeps what the browser needs', () {
      final model = ManagedModel.fromJson(loraJson());
      expect(model.name, 'Realism Enhancer Krea2');
      expect(model.basename, 'SummerVibesHM_krea2_epoch8.safetensors');
      expect(model.baseModel, 'Krea 2');
      expect(model.tags, contains('realism'));
      expect(model.sizeLabel, '218 MB');
      expect(model.previewIsVideo, isFalse);
    });

    test('an entry with no Civitai name falls back to its file name', () {
      final model = ManagedModel.fromJson({
        ...loraJson(),
        'model_name': '',
      });
      expect(model.name, 'SummerVibesHM_krea2_epoch8');
    });

    test('a video preview is recognised so it can be swapped for a poster',
        () {
      final model =
          ManagedModel.fromJson(loraJson(previewExtension: '.mp4'));
      expect(model.previewIsVideo, isTrue,
          reason: 'nothing here can decode an mp4; the card needs to know');
    });

    test('the preview URL is rebuilt against the server, path intact', () {
      final model = ManagedModel.fromJson(loraJson());
      final uri = model.previewUri(_endpoint)!;
      expect(uri.host, '10.0.0.5');
      expect(uri.path, '/api/lm/previews');
      // The Windows drive letter and colon have to survive the round trip -
      // the addon rejects anything it cannot resolve back to a real file.
      expect(uri.queryParameters['path'],
          '$_root/loras/krea/SummerVibesHM_krea2_epoch8.jpeg');
    });

    test('a poster still is asked for at thumbnail size', () {
      final detail = ManagedModelDetail.fromMetadata({
        'trainedWords': ['androgynous femboy', ''],
        'creator': {'username': 'HearmemanAI'},
        'images': [
          {'url': 'https://image.civitai.com/x/1/original=true/1.mp4',
            'type': 'video'},
          {'url': 'https://image.civitai.com/x/2/original=true/2.jpeg',
            'type': 'image', 'meta': {'prompt': 'a woman on a street'}},
        ],
      });
      expect(detail.imageUrls, hasLength(1),
          reason: 'a video cannot stand in for a poster either');
      expect(detail.posterUrl(width: 450),
          'https://image.civitai.com/x/2/width=450/2.jpeg',
          reason: 'the full-size original is 2-3 MB per card');
      expect(detail.trainedWords, ['androgynous femboy']);
      expect(detail.creator, 'HearmemanAI');
      expect(detail.examplePrompts.single, 'a woman on a street');
      expect(ManagedModelDetail.empty.posterUrl(), isNull);
    });

    test('an HTML description is flattened rather than shown raw', () {
      const html = '<p>Trained on 500 images.<br />Use with '
          '<a href="x">this</a>.</p><p>Second &amp; last.</p>';
      expect(stripHtml(html), 'Trained on 500 images.\nUse with this.\n\n'
          'Second & last.');
      expect(stripHtml(''), '');
    });
  });

  group('listing', () {
    test('every page is pulled, not just the first', () async {
      final pages = <String>[];
      final client = LoraManagerClient(
        _endpoint,
        client: MockClient((request) async {
          final page = request.url.queryParameters['page']!;
          pages.add(page);
          return http.Response(
            listBody([loraJson(fileName: 'lora_$page')],
                page: int.parse(page), totalPages: 3),
            200,
          );
        }),
      );
      addTearDown(client.dispose);

      final models = await client.list(ManagedModelKind.lora);
      expect(pages, ['1', '2', '3']);
      expect(models, hasLength(3),
          reason: 'a library larger than one page must not be truncated');
    });

    test('loras and checkpoints go to their own endpoints', () async {
      final seen = <String>[];
      final client = LoraManagerClient(
        _endpoint,
        client: MockClient((request) async {
          seen.add(request.url.path);
          return http.Response(listBody([]), 200);
        }),
      );
      addTearDown(client.dispose);

      await client.list(ManagedModelKind.lora);
      await client.list(ManagedModelKind.checkpoint);
      // "checkpoints" is also where the addon files the diffusion_models
      // (unet) root, which is where a UNETLoader's model lives.
      expect(seen, ['/api/lm/loras/list', '/api/lm/checkpoints/list']);
    });

    test('a server without the addon says so instead of hanging', () async {
      final client = LoraManagerClient(
        _endpoint,
        client: MockClient((_) async => http.Response('Not Found', 404)),
      );
      addTearDown(client.dispose);

      expect(
        () => client.list(ManagedModelKind.lora),
        throwsA(predicate((e) => '$e'.contains('not installed'))),
      );
    });
  });

  group('matching a combo option to a model', () {
    final models = [
      ManagedModel.fromJson(loraJson()),
      ManagedModel.fromJson(loraJson(
          name: 'Identity Edit',
          fileName: 'krea2_identity_edit_v1_2',
          folder: 'krea')),
      ManagedModel.fromJson(loraJson(
          name: 'Angles', fileName: 'angles-lora', folder: 'qwen')),
    ];

    test('a Windows-separated option finds its model', () {
      final paired = pairOptionsWithModels(
        [r'krea\SummerVibesHM_krea2_epoch8.safetensors'],
        models,
      );
      expect(paired.single.model?.name, 'Realism Enhancer Krea2',
          reason: 'ComfyUI reports backslashes; the addon reports a folder');
      expect(paired.single.displayName, 'Realism Enhancer Krea2');
    });

    test('an option in no folder still matches on the file name', () {
      // Some roots are enumerated flat, so the combo carries no folder at
      // all even though the addon recorded one.
      final paired = pairOptionsWithModels(
        ['krea2_identity_edit_v1_2.safetensors'],
        models,
      );
      expect(paired.single.model?.name, 'Identity Edit');
    });

    test('an option the addon has never seen is still offered', () {
      final paired = pairOptionsWithModels(
        [r'krea\something_hand_trained.safetensors'],
        models,
      );
      expect(paired.single.model, isNull);
      expect(paired.single.displayName, 'something_hand_trained.safetensors',
          reason: 'an unknown file must stay pickable, not disappear');
      expect(paired.single.folder, 'krea');
    });

    test('a model with no matching option never appears', () {
      final paired = pairOptionsWithModels(
        [r'krea\SummerVibesHM_krea2_epoch8.safetensors'],
        models,
      );
      expect(paired, hasLength(1),
          reason: 'picking a file this node cannot load would write a graph '
              'that fails at run time');
    });

    test('search covers the human name, the path and the tags', () {
      final entry = pairOptionsWithModels(
          [r'krea\SummerVibesHM_krea2_epoch8.safetensors'], models).single;
      expect(entry.matches('realism enhancer'), isTrue);
      expect(entry.matches('summervibes'), isTrue);
      expect(entry.matches('concept'), isTrue, reason: 'a tag');
      expect(entry.matches('illustrious'), isFalse);
    });
  });

  group('library', () {
    ModelLibrary buildLibrary(void Function() onRequest) => ModelLibrary(
          _endpoint,
          client: LoraManagerClient(
            _endpoint,
            client: MockClient((_) async {
              onRequest();
              return http.Response(listBody([loraJson()]), 200);
            }),
          ),
        );

    test('the library is fetched once and shared', () async {
      var requests = 0;
      final library = buildLibrary(() => requests++);
      addTearDown(library.dispose);

      await Future.wait([
        library.ensureLoaded(ManagedModelKind.lora),
        library.ensureLoaded(ManagedModelKind.lora),
      ]);
      await library.ensureLoaded(ManagedModelKind.lora);

      expect(requests, 1,
          reason: 'the settings drawer, every LoRA row and the browser all '
              'ask for this at once');
      expect(library.modelsFor(ManagedModelKind.lora), hasLength(1));
    });

    test('resolve finds the entry behind a combo value', () async {
      final library = buildLibrary(() {});
      addTearDown(library.dispose);
      await library.ensureLoaded(ManagedModelKind.lora);

      expect(
        library
            .resolve(ManagedModelKind.lora,
                r'krea\SummerVibesHM_krea2_epoch8.safetensors')
            ?.name,
        'Realism Enhancer Krea2',
      );
      expect(library.resolve(ManagedModelKind.lora, 'nothing.safetensors'),
          isNull);
      expect(library.resolve(ManagedModelKind.lora, ''), isNull);
    });

    test('a missing addon is a degraded page, not an error', () async {
      final library = ModelLibrary(
        _endpoint,
        client: LoraManagerClient(
          _endpoint,
          client: MockClient((_) async => http.Response('nope', 404)),
        ),
      );
      addTearDown(library.dispose);

      await library.ensureLoaded(ManagedModelKind.lora);
      expect(library.unavailable.value, isTrue);
      expect(library.modelsFor(ManagedModelKind.lora), isEmpty);
      expect(library.resolve(ManagedModelKind.lora, 'anything'), isNull,
          reason: 'the UI reads null as "just show the filename"');
    });
  });
}
