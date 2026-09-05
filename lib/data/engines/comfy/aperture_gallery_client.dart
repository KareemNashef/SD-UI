// ==================== Aperture Gallery Client ==================== //
//
// Talks to the purpose-built `aperture_gallery` addon (see comfy_addon/).
//
// The difference from [ComfyGalleryClient] is where the work happens. That
// one asks for the entire output tree and does all filtering, sorting and
// paging on the phone, which is why it needs isolate parsing and a full
// in-memory cache. This one asks the server a narrow question - "60 images,
// newest first, from this day, matching this text" - and gets back a small
// answer, so no caching or background parsing is needed at all.
//
// It also gets thumbnails, which is the real prize: a grid of 256px JPEGs
// instead of a grid of full-resolution PNGs.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';

/// One image in the server's output folder.
class ApertureGalleryItem {
  /// Path relative to the output root, e.g. `2026-01/render_004.png`.
  final String path;
  final String name;
  final String subfolder;
  final DateTime modifiedAt;
  final int sizeBytes;

  const ApertureGalleryItem({
    required this.path,
    required this.name,
    required this.subfolder,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  factory ApertureGalleryItem.fromJson(Map<String, dynamic> json) {
    final seconds = (json['mtime'] as num?)?.toDouble() ?? 0;
    return ApertureGalleryItem(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      subfolder: json['subfolder'] as String? ?? '',
      modifiedAt:
          DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()),
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// The server-rendered thumbnail. [width] is a hint; the addon clamps it.
  Uri thumbUri(EngineEndpoint endpoint, {int width = 256}) =>
      endpoint.http('/aperture/gallery/thumb', {
        'path': path,
        'w': '$width',
      });

  /// Full resolution, via ComfyUI's own `/view` - the addon deliberately
  /// does not duplicate an endpoint that already exists.
  Uri fullUri(EngineEndpoint endpoint) => endpoint.http('/view', {
        'filename': name,
        'subfolder': subfolder,
        'type': 'output',
      });

  GeneratedImage toGeneratedImage(EngineEndpoint endpoint) =>
      GeneratedImage.fromServerLibrary(
        url: fullUri(endpoint).toString(),
        engine: endpoint.kind,
        comfy: ComfyOrigin(filename: name, subfolder: subfolder),
        createdAt: modifiedAt,
      );
}

/// One page of results.
class ApertureGalleryPage {
  final List<ApertureGalleryItem> items;
  final int total;

  /// Offset to request next, or null when this was the last page.
  final int? nextOffset;

  const ApertureGalleryPage({
    required this.items,
    required this.total,
    required this.nextOffset,
  });

  bool get hasMore => nextOffset != null;
}

/// A day with images in it.
class ApertureGalleryDay {
  final String day; // yyyy-MM-dd, server-local
  final int count;
  const ApertureGalleryDay(this.day, this.count);

  /// Local midnight bounds for this day, as the addon's `since`/`until`
  /// filters expect (epoch seconds).
  (double, double) get bounds {
    final parts = day.split('-').map(int.parse).toList();
    final start = DateTime(parts[0], parts[1], parts[2]);
    final end = start.add(const Duration(days: 1));
    return (
      start.millisecondsSinceEpoch / 1000,
      end.millisecondsSinceEpoch / 1000,
    );
  }
}

/// Raised when the addon is not installed, so the caller can fall back
/// rather than treat it as a hard failure.
class ApertureGalleryMissing implements Exception {
  const ApertureGalleryMissing();
  @override
  String toString() => 'aperture_gallery addon not installed';
}

class ApertureGalleryClient {
  final http.Client _client;

  ApertureGalleryClient({http.Client? client})
      : _client = client ?? http.Client();

  /// Whether this server has the addon. Cached per endpoint, because the
  /// answer cannot change without a ComfyUI restart.
  static final Map<String, bool> _available = {};

  /// Pages and day counts, held across screen opens.
  ///
  /// Re-fetching the whole first screen every time the gallery opens is
  /// wasteful when the answer almost never changed: output folders grow at
  /// the top and are otherwise static. So results are kept, shown instantly
  /// on reopen, and only the newest page is re-asked for.
  static final Map<String, ApertureGalleryPage> _pages = {};
  static final Map<String, List<ApertureGalleryDay>> _dayCache = {};

  static String _pageKey(
    EngineEndpoint endpoint,
    int offset,
    double? since,
    double? until,
    String? query,
  ) =>
      '${endpoint.id}|$offset|${since ?? ''}|${until ?? ''}|${query ?? ''}';

  /// Drops everything remembered for [endpoint]. Used by an explicit
  /// refresh, where the point is to distrust the cache entirely.
  static void clearCache(EngineEndpoint endpoint) {
    _pages.removeWhere((key, _) => key.startsWith('${endpoint.id}|'));
    _dayCache.remove(endpoint.id);
  }

  Future<bool> isAvailable(EngineEndpoint endpoint) async {
    final cached = _available[endpoint.id];
    if (cached != null) return cached;
    try {
      final response = await _client
          .get(endpoint.http('/aperture/gallery/ping'))
          .timeout(const Duration(seconds: 4));
      final ok = response.statusCode == 200;
      _available[endpoint.id] = ok;
      return ok;
    } catch (_) {
      _available[endpoint.id] = false;
      return false;
    }
  }

  /// Day counts, from cache unless [refresh] is set.
  Future<List<ApertureGalleryDay>> days(
    EngineEndpoint endpoint, {
    bool refresh = false,
  }) async {
    final cached = _dayCache[endpoint.id];
    if (cached != null && !refresh) return cached;
    final response = await _get(
      endpoint,
      '/aperture/gallery/days',
      {if (refresh) 'refresh': '1'},
    );
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    final days = [
      for (final entry in (decoded['days'] as List? ?? const []))
        if (entry is Map)
          ApertureGalleryDay(
            entry['day'] as String? ?? '',
            (entry['count'] as num?)?.toInt() ?? 0,
          ),
    ];
    _dayCache[endpoint.id] = days;
    return days;
  }

  /// A page of results.
  ///
  /// [refresh] both asks the server to rebuild its index and bypasses the
  /// local cache; [useCache] lets a caller read a page it already has
  /// without a round trip. A cached page is still a *correct* page - the
  /// only thing it can miss is images created since it was fetched, which
  /// is exactly what refreshing the newest page fixes.
  Future<ApertureGalleryPage> list(
    EngineEndpoint endpoint, {
    int offset = 0,
    int limit = 60,
    double? since,
    double? until,
    String? query,
    bool refresh = false,
    bool useCache = true,
  }) async {
    final key = _pageKey(endpoint, offset, since, until, query);
    if (useCache && !refresh) {
      final cached = _pages[key];
      if (cached != null) return cached;
    }

    final response = await _get(endpoint, '/aperture/gallery/list', {
      'offset': '$offset',
      'limit': '$limit',
      if (since != null) 'since': '$since',
      if (until != null) 'until': '$until',
      if (query != null && query.isNotEmpty) 'q': query,
      if (refresh) 'refresh': '1',
    });
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    final page = ApertureGalleryPage(
      total: (decoded['total'] as num?)?.toInt() ?? 0,
      nextOffset: (decoded['next_offset'] as num?)?.toInt(),
      items: [
        for (final entry in (decoded['items'] as List? ?? const []))
          if (entry is Map)
            ApertureGalleryItem.fromJson(entry.cast<String, dynamic>()),
      ],
    );
    _pages[key] = page;
    return page;
  }

  /// True when a first page for these filters is already in hand, so the
  /// caller can decide whether it has anything to draw immediately.
  bool hasCachedFirstPage(
    EngineEndpoint endpoint, {
    double? since,
    double? until,
    String? query,
  }) =>
      _pages.containsKey(_pageKey(endpoint, 0, since, until, query));

  Future<String> _get(
    EngineEndpoint endpoint,
    String path,
    Map<String, dynamic> query,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .get(endpoint.http(path, query))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Exception('Could not reach the gallery addon: $e');
    }
    if (response.statusCode == 404) {
      _available[endpoint.id] = false;
      throw const ApertureGalleryMissing();
    }
    if (response.statusCode != 200) {
      throw Exception('Gallery addon returned ${response.statusCode}');
    }
    return response.body;
  }

  void dispose() => _client.close();
}
