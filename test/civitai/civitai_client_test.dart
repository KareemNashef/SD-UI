// Pinned against the shapes the live API actually returns, captured by
// calling it. Two of these encode findings that cost real debugging time:
// `withMeta=true` is mandatory, and `meta` is *null* rather than empty on
// roughly half of all images.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sd_companion/data/civitai/civitai_client.dart';

/// An item with generation data, shaped exactly like a real response.
Map<String, dynamic> itemWithMeta({int id = 1}) => {
      'id': id,
      'url': 'https://image.civitai.com/abc/$id/original=true/$id.jpeg',
      'width': 832,
      'height': 1248,
      'nsfwLevel': 'None',
      'username': 'someone',
      'baseModel': 'Illustrious',
      'meta': {
        'prompt': 'masterpiece, a castle on a hill',
        'negativePrompt': 'blurry, watermark',
        'steps': 15,
        'cfgScale': 1,
        'sampler': 'Euler',
        'seed': 3990174051,
        'Model': 'someCheckpoint',
        'scheduler': 'karras',
        // Nested values are resource lists - noise in a settings table.
        'resources': [
          {'name': 'lora', 'weight': 0.8}
        ],
        'hashes': {'model': 'abc123'},
      },
    };

/// The other half of the feed: no metadata at all.
Map<String, dynamic> itemWithoutMeta({int id = 2}) => {
      'id': id,
      'url': 'https://image.civitai.com/abc/$id/original=true/$id.jpeg',
      'width': 1000,
      'height': 1000,
      'nsfwLevel': 'None',
      'username': 'nobody',
      'meta': null,
    };

String body(List<Map<String, dynamic>> items, {String? nextCursor}) =>
    jsonEncode({
      'items': items,
      'metadata': {if (nextCursor != null) 'nextCursor': nextCursor},
    });

void main() {
  test('withMeta=true is always sent', () async {
    Uri? seen;
    final client = CivitaiClient(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(body([itemWithMeta()]), 200);
      }),
    );
    addTearDown(client.dispose);

    await client.images();
    expect(seen!.queryParameters['withMeta'], 'true',
        reason: 'without it every image comes back with meta:null, which '
            'makes the whole screen pointless');
  });

  test('the feed defaults to safe content', () async {
    Uri? seen;
    final client = CivitaiClient(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(body([itemWithMeta()]), 200);
      }),
    );
    addTearDown(client.dispose);

    await client.images();
    expect(seen!.queryParameters['browsingLevel'], '1',
        reason: 'the default must be the narrowest level');
  });

  test('ratings are exclusive, not cumulative', () async {
    final sent = <String, String?>{};
    final client = CivitaiClient(
      client: MockClient((request) async {
        sent[request.url.queryParameters['browsingLevel'] ?? ''] = 'seen';
        return http.Response(body([itemWithMeta()]), 200);
      }),
    );
    addTearDown(client.dispose);

    // Actually issue a request per rating, so this fails if the client stops
    // sending browsingLevel or falls back to the cumulative `nsfw` param.
    for (final rating in CivitaiRating.values) {
      await client.images(rating: rating);
    }

    expect(sent.keys, containsAll(['1', '2', '4', '8', '15']));
    expect(sent.containsKey(''), isFalse,
        reason: 'every request must carry a browsingLevel');

    // Each exclusive level must be a single bit. `nsfw=Mature` also returns
    // Soft and None; a non-power-of-two here would silently do the same.
    for (final rating in CivitaiRating.values) {
      if (rating == CivitaiRating.all) continue;
      expect(rating.level & (rating.level - 1), 0,
          reason: '${rating.label} is not a single bit, so it is cumulative');
    }
    expect(CivitaiRating.all.level, 15,
        reason: 'all levels is the union of every bit');
  });

  test('the cumulative nsfw parameter is not sent at all', () async {
    Uri? seen;
    final client = CivitaiClient(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(body([itemWithMeta()]), 200);
      }),
    );
    addTearDown(client.dispose);

    await client.images(rating: CivitaiRating.mature);
    expect(seen!.queryParameters.containsKey('nsfw'), isFalse,
        reason: 'sending both would re-widen the feed and defeat the '
            'exclusive filter');
  });

  test('the feed is restricted to images', () async {
    Uri? seen;
    final client = CivitaiClient(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(body([itemWithMeta()]), 200);
      }),
    );
    addTearDown(client.dispose);

    await client.images();
    expect(seen!.queryParameters['type'], 'image',
        reason: 'the feed mixes in videos, whose .mp4 URLs would reach '
            'Image.network and render as broken cells');
  });

  test('tag ids are sent as a comma list, and omitted when empty', () async {
    Uri? seen;
    final client = CivitaiClient(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(body([itemWithMeta()]), 200);
      }),
    );
    addTearDown(client.dispose);

    await client.images();
    expect(seen!.queryParameters.containsKey('tags'), isFalse,
        reason: 'an empty tag list must not narrow the feed to nothing');

    await client.images(tagIds: const [5133, 111]);
    expect(seen!.queryParameters['tags'], '5133,111');
  });

  test('generation data is pulled out of meta', () async {
    final client = CivitaiClient(
      client: MockClient(
          (_) async => http.Response(body([itemWithMeta()]), 200)),
    );
    addTearDown(client.dispose);

    final image = (await client.images()).items.single;
    expect(image.hasPrompt, isTrue);
    expect(image.prompt, contains('castle'));
    expect(image.negativePrompt, contains('watermark'));
    expect(image.steps, 15);
    expect(image.cfgScale, 1);
    expect(image.sampler, 'Euler');
    expect(image.seed, '3990174051');
    expect(image.model, 'someCheckpoint');
    expect(image.baseModel, 'Illustrious');
  });

  test('unrecognised scalar settings are kept, nested ones dropped', () async {
    final client = CivitaiClient(
      client: MockClient(
          (_) async => http.Response(body([itemWithMeta()]), 200)),
    );
    addTearDown(client.dispose);

    final image = (await client.images()).items.single;
    expect(image.extra['scheduler'], 'karras',
        reason: 'an unusual pipeline should still show its settings');
    expect(image.extra.containsKey('resources'), isFalse);
    expect(image.extra.containsKey('hashes'), isFalse);
    expect(image.extra.containsKey('prompt'), isFalse,
        reason: 'known fields must not be duplicated into the extras table');
  });

  test('a null meta is a normal image, not a failure', () async {
    final client = CivitaiClient(
      client: MockClient(
          (_) async => http.Response(body([itemWithoutMeta()]), 200)),
    );
    addTearDown(client.dispose);

    final image = (await client.images()).items.single;
    expect(image.hasPrompt, isFalse);
    expect(image.prompt, isNull);
    expect(image.id, 2, reason: 'the image itself must still parse');
    expect(image.url, isNotEmpty);
  });

  test('thumbnails ask the CDN to resize instead of pulling originals',
      () async {
    final client = CivitaiClient(
      client: MockClient(
          (_) async => http.Response(body([itemWithMeta()]), 200)),
    );
    addTearDown(client.dispose);

    final image = (await client.images()).items.single;
    expect(image.url, contains('original=true'));
    expect(image.thumbUrl(width: 450), contains('width=450'));
    expect(image.thumbUrl(width: 450), isNot(contains('original=true')),
        reason: 'a grid of full-resolution JPEGs is the whole cost being '
            'avoided here');
  });

  test('the cursor drives paging and null ends it', () async {
    final client = CivitaiClient(
      client: MockClient((request) async {
        final cursor = request.url.queryParameters['cursor'];
        return http.Response(
          cursor == null
              ? body([itemWithMeta()], nextCursor: 'page-2')
              : body([itemWithMeta(id: 9)]),
          200,
        );
      }),
    );
    addTearDown(client.dispose);

    final first = await client.images();
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, 'page-2');

    final second = await client.images(cursor: first.nextCursor);
    expect(second.hasMore, isFalse);
  });

  test('rate limiting says so rather than surfacing a raw code', () async {
    final client = CivitaiClient(
      client: MockClient((_) async => http.Response('slow down', 429)),
    );
    addTearDown(client.dispose);

    expect(
      () => client.images(),
      throwsA(isA<CivitaiException>().having(
          (e) => e.message, 'message', contains('rate limiting'))),
    );
  });

  test('an unreadable body fails cleanly', () async {
    final client = CivitaiClient(
      client: MockClient((_) async => http.Response('<html>nope', 200)),
    );
    addTearDown(client.dispose);

    expect(() => client.images(), throwsA(isA<CivitaiException>()));
  });
}
