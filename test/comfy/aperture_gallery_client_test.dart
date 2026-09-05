// The addon and this client are two halves of one contract, and the addon
// lives in Python where Dart tests cannot reach it. These pin the Dart half
// against the exact JSON the addon emits, so a change on either side that
// breaks the pairing shows up here rather than as an empty grid on a phone.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sd_companion/data/engines/comfy/aperture_gallery_client.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';

void main() {
  final endpoint = EngineEndpoint.defaultFor(EngineKind.comfy);

  // The cache is static, which is right for the app (one process, one
  // library) and wrong for tests, where it would otherwise leak between
  // cases and make them order-dependent.
  setUp(() => ApertureGalleryClient.clearCache(endpoint));

  /// Mirrors `/aperture/gallery/list` exactly as the addon builds it.
  String listBody({
    required int total,
    required int offset,
    int? nextOffset,
    int count = 2,
  }) =>
      jsonEncode({
        'total': total,
        'offset': offset,
        'limit': 60,
        'next_offset': nextOffset,
        'items': [
          for (var i = 0; i < count; i++)
            {
              'path': 'day-a/render_${offset + i}.png',
              'name': 'render_${offset + i}.png',
              'subfolder': 'day-a',
              'mtime': 1767225600.0 + i,
              'size': 2048 + i,
            },
        ],
      });

  test('a list page parses into items with a real timestamp', () async {
    final client = ApertureGalleryClient(
      client: MockClient((_) async => http.Response(
          listBody(total: 500, offset: 0, nextOffset: 60), 200)),
    );
    addTearDown(client.dispose);

    final page = await client.list(endpoint);
    expect(page.total, 500);
    expect(page.items, hasLength(2));
    expect(page.items.first.name, 'render_0.png');
    expect(page.items.first.subfolder, 'day-a');
    expect(page.items.first.modifiedAt.year, greaterThan(2000),
        reason: 'mtime is epoch *seconds*, not milliseconds');
  });

  test('next_offset drives paging, and null means the end', () async {
    final client = ApertureGalleryClient(
      client: MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        return http.Response(
          listBody(
            total: 120,
            offset: offset,
            nextOffset: offset >= 60 ? null : 60,
          ),
          200,
        );
      }),
    );
    addTearDown(client.dispose);

    final first = await client.list(endpoint);
    expect(first.hasMore, isTrue);
    expect(first.nextOffset, 60);

    final last = await client.list(endpoint, offset: first.nextOffset!);
    expect(last.hasMore, isFalse,
        reason: 'a null next_offset must stop the infinite scroll');
  });

  test('filters are sent to the server, not applied on the client', () async {
    Uri? seen;
    final client = ApertureGalleryClient(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(listBody(total: 1, offset: 0), 200);
      }),
    );
    addTearDown(client.dispose);

    await client.list(endpoint,
        since: 100.0, until: 200.0, query: 'castle', limit: 30);

    expect(seen!.queryParameters['since'], '100.0');
    expect(seen!.queryParameters['until'], '200.0');
    expect(seen!.queryParameters['q'], 'castle');
    expect(seen!.queryParameters['limit'], '30');
  });

  test('a missing addon is reported as such, so the caller can fall back',
      () async {
    final client = ApertureGalleryClient(
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    addTearDown(client.dispose);

    expect(
      () => client.list(endpoint),
      throwsA(isA<ApertureGalleryMissing>()),
    );
  });

  test('days parse into buckets with usable local bounds', () async {
    final client = ApertureGalleryClient(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'total': 30,
              'days': [
                {'day': '2026-01-02', 'count': 20},
                {'day': '2026-01-01', 'count': 10},
              ],
            }),
            200,
          )),
    );
    addTearDown(client.dispose);

    final days = await client.days(endpoint);
    expect(days, hasLength(2));
    expect(days.first.day, '2026-01-02');
    expect(days.first.count, 20);

    final (since, until) = days.first.bounds;
    expect(until - since, 24 * 60 * 60,
        reason: 'a day filter must span exactly one day');
  });

  test('an entry promotes to an ordinary library image via /view', () {
    final item = ApertureGalleryItem(
      path: 'day-a/render_0.png',
      name: 'render_0.png',
      subfolder: 'day-a',
      modifiedAt: DateTime(2026, 1, 1),
      sizeBytes: 2048,
    );

    final thumb = item.thumbUri(endpoint, width: 256);
    expect(thumb.path, '/aperture/gallery/thumb');
    expect(thumb.queryParameters['path'], 'day-a/render_0.png');
    expect(thumb.queryParameters['w'], '256');

    final generated = item.toGeneratedImage(endpoint);
    expect(generated.url, contains('/view'));
    expect(generated.origin, ImageOrigin.serverLibrary);
    expect(generated.comfy?.filename, 'render_0.png');
    expect(generated.comfy?.subfolder, 'day-a');
  });

  group('caching', () {
    test('a repeated page is served from cache without a second request',
        () async {
      var requests = 0;
      final client = ApertureGalleryClient(
        client: MockClient((_) async {
          requests++;
          return http.Response(listBody(total: 10, offset: 0), 200);
        }),
      );
      addTearDown(client.dispose);

      await client.list(endpoint);
      await client.list(endpoint);
      expect(requests, 1, reason: 'reopening must not refetch what it has');
    });

    test('refresh bypasses the cache and asks the server to rescan', () async {
      var requests = 0;
      Uri? last;
      final client = ApertureGalleryClient(
        client: MockClient((request) async {
          requests++;
          last = request.url;
          return http.Response(listBody(total: 10, offset: 0), 200);
        }),
      );
      addTearDown(client.dispose);

      await client.list(endpoint);
      await client.list(endpoint, refresh: true);
      expect(requests, 2);
      expect(last!.queryParameters['refresh'], '1',
          reason: 'refresh must reach the addon, not just the local cache');
    });

    test('different filters are cached separately', () async {
      var requests = 0;
      final client = ApertureGalleryClient(
        client: MockClient((_) async {
          requests++;
          return http.Response(listBody(total: 10, offset: 0), 200);
        }),
      );
      addTearDown(client.dispose);

      await client.list(endpoint);
      await client.list(endpoint, since: 100, until: 200);
      await client.list(endpoint, query: 'castle');
      await client.list(endpoint); // cached
      expect(requests, 3, reason: 'one request per distinct filter set');
    });

    test('hasCachedFirstPage reports whether the screen can open warm',
        () async {
      final client = ApertureGalleryClient(
        client: MockClient(
            (_) async => http.Response(listBody(total: 10, offset: 0), 200)),
      );
      addTearDown(client.dispose);

      expect(client.hasCachedFirstPage(endpoint), isFalse);
      await client.list(endpoint);
      expect(client.hasCachedFirstPage(endpoint), isTrue);

      ApertureGalleryClient.clearCache(endpoint);
      expect(client.hasCachedFirstPage(endpoint), isFalse,
          reason: 'an explicit refresh must distrust the cache entirely');
    });

    test('day counts are cached too', () async {
      var requests = 0;
      final client = ApertureGalleryClient(
        client: MockClient((_) async {
          requests++;
          return http.Response(
              jsonEncode({'total': 1, 'days': [{'day': '2026-01-01', 'count': 1}]}),
              200);
        }),
      );
      addTearDown(client.dispose);

      await client.days(endpoint);
      await client.days(endpoint);
      expect(requests, 1);
    });
  });
}
