// ==================== Comfy Gallery Client ==================== //
//
// Talks to the PanicTitan/ComfyUI-Gallery custom node's
// `GET /api/Gallery/images?relative_path=...` endpoint - a third-party
// addon, not part of ComfyUI core, so every call here has to tolerate the
// endpoint simply not existing on a given server.
//
// Confirmed against the addon's own server.py: the route takes exactly one
// query parameter (`relative_path`), does a full disk rescan on every
// request, and has no pagination/limit/offset/date-filter support at all.
// So a server with thousands of images sends everything - including a full
// embedded prompt/workflow graph per image - in one giant response, and
// there is no way to ask it for less. This client can't change that; it can
// only avoid making it worse: decode + extract on a background isolate so
// an 11,000-image reply doesn't freeze the UI thread, drop the heavy
// per-image prompt/workflow blobs immediately after parsing instead of
// retaining them, and cache the resulting (lightweight) list per server so
// re-opening the browser doesn't pay for another full rescan+refetch.

import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';

/// One image the Gallery addon reports, with just enough to browse/preview
/// it - the addon also embeds the full prompt/workflow graph that produced
/// each image, but that's dropped during parsing rather than retained, so a
/// server with thousands of images doesn't leave thousands of full graphs
/// sitting in memory for data this app never uses.
class ComfyGalleryImage {
  final String filename;
  final String url; // server-relative, e.g. '/static_gallery/a/b/c.png'
  final List<String> pathSegments; // e.g. ['a', 'b'] for a nested folder
  final DateTime? createdAt;
  final String? resolution; // e.g. '800x1184'
  final String? sizeLabel; // e.g. '1.32 MB'

  const ComfyGalleryImage({
    required this.filename,
    required this.url,
    required this.pathSegments,
    this.createdAt,
    this.resolution,
    this.sizeLabel,
  });

  String get subfolder => pathSegments.join('/');

  Uri viewUri(EngineEndpoint endpoint) => endpoint.http(url);

  GeneratedImage toGeneratedImage(EngineEndpoint endpoint) =>
      GeneratedImage.fromServerLibrary(
        url: viewUri(endpoint).toString(),
        engine: endpoint.kind,
        comfy: ComfyOrigin(
          filename: filename,
          subfolder: subfolder,
        ),
        createdAt: createdAt,
      );
}

/// Thrown when the addon's endpoint doesn't respond the way the addon
/// would (404/unreachable), so the UI can tell "not installed" apart from
/// "installed but empty" or a generic network error.
class ComfyGalleryUnavailableException implements Exception {
  final String message;
  const ComfyGalleryUnavailableException(this.message);
  @override
  String toString() => message;
}

class ComfyGalleryClient {
  final http.Client _client;

  ComfyGalleryClient({http.Client? client}) : _client = client ?? http.Client();

  // A full rescan+refetch is expensive (potentially tens of thousands of
  // images with embedded metadata) and the addon has no way to ask for only
  // what changed, so the last successful result is kept around per server
  // and reused until the caller explicitly asks for a refresh.
  static final Map<String, List<ComfyGalleryImage>> _cache = {};

  /// Fetches the entire recursive image tree under the output root. Returns
  /// the cached result from a previous call unless [forceRefresh] is set.
  Future<List<ComfyGalleryImage>> fetchAll(
    EngineEndpoint endpoint, {
    bool forceRefresh = false,
  }) async {
    final cached = _cache[endpoint.id];
    if (cached != null && !forceRefresh) return cached;

    final http.Response response;
    try {
      response = await _client
          .get(endpoint.http('/api/Gallery/images', {'relative_path': './'}))
          // A server with thousands of images and per-image embedded
          // metadata can genuinely take a while to both rescan on disk and
          // transfer - a short timeout here would fail exactly the servers
          // this feature exists for.
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw ComfyGalleryUnavailableException('Could not reach the Gallery addon: $e');
    }

    if (response.statusCode == 404) {
      throw const ComfyGalleryUnavailableException(
        'ComfyUI-Gallery addon not found on this server. Install PanicTitan/ComfyUI-Gallery to browse its output history.',
      );
    }
    if (response.statusCode != 200) {
      throw ServerError('Gallery addon returned ${response.statusCode}');
    }

    final List<ComfyGalleryImage> images;
    try {
      // Decoding + extracting off the main isolate: with thousands of
      // entries each carrying a full embedded prompt/workflow graph, the
      // raw JSON can run tens of megabytes, and jsonDecode is synchronous -
      // doing it inline would freeze the UI for the entire parse.
      images = await compute(_parseGalleryBody, response.body);
    } catch (e) {
      throw ComfyGalleryUnavailableException('Unexpected response from the Gallery addon: $e');
    }

    _cache[endpoint.id] = images;
    return images;
  }

  void dispose() => _client.close();
}

/// Top-level so it's eligible for `compute()`. Parses the addon's response
/// and immediately discards everything except the handful of lightweight
/// fields the gallery UI actually needs - in particular, never holds onto
/// `metadata.prompt`/`metadata.workflow`, which is where nearly all of the
/// response's size lives.
List<ComfyGalleryImage> _parseGalleryBody(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final folders = (decoded['folders'] as Map?)?.cast<String, dynamic>() ?? {};
  final images = <ComfyGalleryImage>[];

  for (final folderEntry in folders.entries) {
    final segments = _pathSegmentsFor(folderEntry.key);
    final files = (folderEntry.value as Map?)?.cast<String, dynamic>() ?? {};
    for (final fileEntry in files.entries) {
      final file = fileEntry.value as Map<String, dynamic>?;
      if (file == null) continue;
      if ((file['type'] as String?) != 'image') continue;
      final name = file['name'] as String? ?? fileEntry.key;
      final url = file['url'] as String?;
      if (url == null) continue;
      final ts = file['timestamp'] as num?;
      final fileinfo = (file['metadata'] as Map?)?['fileinfo'] as Map?;
      images.add(ComfyGalleryImage(
        filename: name,
        url: url,
        pathSegments: segments,
        createdAt: ts != null ? DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()) : null,
        resolution: fileinfo?['resolution'] as String?,
        sizeLabel: fileinfo?['size'] as String?,
      ));
    }
  }

  images.sort((a, b) {
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null || bt == null) return 0;
    return bt.compareTo(at);
  });
  return images;
}

/// The addon's folder keys are relative to the ComfyUI install root (e.g.
/// 'output/krea2edit', or bare 'output' for the root itself) rather than
/// the output directory - strip that leading 'output' segment so this app's
/// folder tree is rooted at the output directory, matching what the user
/// actually sees as "the output folder".
List<String> _pathSegmentsFor(String folderKey) {
  final parts = folderKey.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.isNotEmpty && parts.first.toLowerCase() == 'output') {
    return parts.sublist(1);
  }
  return parts;
}
