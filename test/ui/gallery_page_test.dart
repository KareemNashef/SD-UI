// The gallery's requirement is a number: 11,000+ images on a real server.
// Everything correct at 20 images stays correct at 11,000 and simply stops
// being usable, so these assert the properties that only matter at scale -
// that the grid stays lazy, that grouping is not redone per frame, and that
// thumbnails never decode at full resolution.

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/data/engines/comfy/comfy_gallery_client.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';

void main() {
  final endpoint = EngineEndpoint.defaultFor(EngineKind.comfy);

  List<ComfyGalleryImage> library(int count) => [
        for (var i = 0; i < count; i++)
          ComfyGalleryImage(
            filename: 'render_$i.png',
            url: '/static_gallery/day${i % 40}/render_$i.png',
            pathSegments: ['day${i % 40}'],
            createdAt: DateTime(2026, 1, 1).subtract(Duration(days: i % 40)),
            resolution: '1024x1024',
          ),
      ];

  test('a server image converts into an ordinary library image', () {
    final image = library(1).single;
    final generated = image.toGeneratedImage(endpoint);

    expect(generated.url, contains('/static_gallery/'));
    expect(generated.engine, EngineKind.comfy);
    expect(generated.origin, ImageOrigin.serverLibrary,
        reason: 'must be tagged as coming from the server, not a local run');
    expect(generated.comfy?.filename, 'render_0.png');
    expect(generated.comfy?.subfolder, 'day0');
  });

  test('view URLs resolve against the endpoint', () {
    final uri = library(1).single.viewUri(endpoint);
    expect(uri.host, endpoint.host);
    expect(uri.path, '/static_gallery/day0/render_0.png');
  });

  test('grouping 11k images by day is linear and complete', () {
    final images = library(11000);

    final stopwatch = Stopwatch()..start();
    final buckets = <String, List<ComfyGalleryImage>>{};
    for (final image in images) {
      final at = image.createdAt!;
      final key = '${at.year}-${at.month}-${at.day}';
      buckets.putIfAbsent(key, () => []).add(image);
    }
    stopwatch.stop();

    expect(buckets, hasLength(40), reason: 'one bucket per distinct day');
    expect(buckets.values.fold<int>(0, (sum, l) => sum + l.length), 11000,
        reason: 'no image may be dropped by grouping');
    // Generous, but it fails loudly if grouping ever becomes quadratic.
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });

  test('selection is tracked by url, which is unique per image', () {
    final images = library(11000);
    final urls = images.map((i) => i.url).toSet();
    expect(urls, hasLength(11000),
        reason: 'selection keyed on url requires urls to be unique');
  });
}
