// Covers ComfyGalleryClient against a mocked HTTP layer (no live server
// needed): folder-key parsing, sorting, the not-installed/404 path, and the
// per-profile cache that keeps repeat opens of the server library from
// re-triggering a full disk rescan + multi-megabyte refetch.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/backend/server_profile.dart';
import 'package:sd_companion/logic/comfy/comfy_gallery_client.dart';

const _profile = ServerProfile(kind: BackendKind.comfy, host: '127.0.0.1', port: '8188');

Map<String, dynamic> _fileEntry({
  required String name,
  required String url,
  required double timestamp,
  String? resolution,
  String? size,
}) => {
  'name': name,
  'url': url,
  'timestamp': timestamp,
  'date': '2026-08-15 00:00:00',
  'type': 'image',
  'metadata': {
    if (resolution != null || size != null)
      'fileinfo': {if (resolution != null) 'resolution': resolution, if (size != null) 'size': size},
    // Real responses embed a full prompt/workflow graph per image; keep a
    // stand-in here to make sure parsing tolerates (and ignores) it.
    'prompt': {'1': 'unused'},
  },
};

void main() {
  test('parses a flat output folder, newest first', () async {
    var callCount = 0;
    final mock = MockClient((request) async {
      callCount++;
      return http.Response(
        jsonEncode({
          'folders': {
            'output': {
              'b.png': _fileEntry(name: 'b.png', url: '/static_gallery/b.png', timestamp: 200, resolution: '512x512', size: '1 MB'),
              'a.png': _fileEntry(name: 'a.png', url: '/static_gallery/a.png', timestamp: 100),
            },
          },
        }),
        200,
      );
    });

    final client = ComfyGalleryClient(client: mock);
    final images = await client.fetchAll(_profile);

    expect(callCount, 1);
    expect(images, hasLength(2));
    expect(images.first.filename, 'b.png'); // newer timestamp sorts first
    expect(images.first.pathSegments, isEmpty); // 'output' root strips to no segments
    expect(images.first.resolution, '512x512');
    expect(images.first.sizeLabel, '1 MB');
    expect(images.last.filename, 'a.png');
    client.dispose();
  });

  test('strips the leading "output" segment from nested folder keys', () async {
    final mock = MockClient((request) async => http.Response(
      jsonEncode({
        'folders': {
          'output/krea2edit': {
            'c.png': _fileEntry(name: 'c.png', url: '/static_gallery/krea2edit/c.png', timestamp: 100),
          },
        },
      }),
      200,
    ));

    final client = ComfyGalleryClient(client: mock);
    final images = await client.fetchAll(_profile, forceRefresh: true);

    expect(images.single.pathSegments, ['krea2edit']);
    expect(images.single.subfolder, 'krea2edit');
    client.dispose();
  });

  test('caches the result and only refetches on forceRefresh', () async {
    var callCount = 0;
    final mock = MockClient((request) async {
      callCount++;
      return http.Response(
        jsonEncode({
          'folders': {
            'output': {'a.png': _fileEntry(name: 'a.png', url: '/static_gallery/a.png', timestamp: 100)},
          },
        }),
        200,
      );
    });

    final client = ComfyGalleryClient(client: mock);
    final first = await client.fetchAll(_profile, forceRefresh: true);
    final second = await client.fetchAll(_profile); // should hit cache
    expect(callCount, 1);
    expect(identical(first, second), isTrue);

    await client.fetchAll(_profile, forceRefresh: true); // bypasses cache
    expect(callCount, 2);
    client.dispose();
  });

  test('reports a clear error when the addon endpoint is missing (404)', () async {
    final mock = MockClient((request) async => http.Response('not found', 404));
    final client = ComfyGalleryClient(client: mock);

    await expectLater(
      client.fetchAll(_profile, forceRefresh: true),
      throwsA(isA<ComfyGalleryUnavailableException>()),
    );
    client.dispose();
  });

  test('ignores non-image entries and entries missing a url', () async {
    final mock = MockClient((request) async => http.Response(
      jsonEncode({
        'folders': {
          'output': {
            'a.png': _fileEntry(name: 'a.png', url: '/static_gallery/a.png', timestamp: 100),
            'video.mp4': {..._fileEntry(name: 'video.mp4', url: '/static_gallery/video.mp4', timestamp: 50), 'type': 'video'},
            'broken.png': {'name': 'broken.png', 'timestamp': 10, 'type': 'image'}, // no url
          },
        },
      }),
      200,
    ));

    final client = ComfyGalleryClient(client: mock);
    final images = await client.fetchAll(_profile, forceRefresh: true);

    expect(images, hasLength(1));
    expect(images.single.filename, 'a.png');
    client.dispose();
  });
}
