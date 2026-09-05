// ==================== Civitai Client ==================== //
//
// Reads Civitai's public image feed, for browsing what other people made and
// lifting the prompt behind it.
//
// Two things about this API are worth knowing before reading the code, both
// established by calling it rather than from the docs:
//
//  * **`withMeta=true` is mandatory.** Without it every image comes back with
//    `meta: null` - not an empty object, null - so the feature this exists
//    for silently yields nothing. It is off by default.
//  * **Roughly half of all images have no prompt anyway**, because `meta` is
//    only present when the uploader left it in. That is not an error and
//    must not be presented as one; it is the normal state of a large chunk
//    of the site.
//
// No API key is involved. Anonymous callers are capped at the public
// browsing level, which is exactly where this defaults.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Exactly one content level, or all of them.
///
/// The obvious `nsfw` parameter is **cumulative** - asking for `Mature` also
/// returns `Soft` and `None`, so there is no way to say "only mature". The
/// undocumented-looking `browsingLevel` is a bitmask and does exactly that,
/// verified against the live API: 1 returns only `None`, 2 only `Soft`, 4
/// only `Mature`, 8 only `X`, and 15 returns the lot.
enum CivitaiRating {
  safe(1, 'Safe'),
  suggestive(2, 'Suggestive'),
  mature(4, 'Mature'),
  explicit(8, 'Explicit'),
  all(15, 'All');

  /// Bitmask passed as `browsingLevel`.
  final int level;
  final String label;
  const CivitaiRating(this.level, this.label);
}

enum CivitaiSort {
  reactions('Most Reactions', 'Popular'),
  newest('Newest', 'Newest'),
  comments('Most Comments', 'Discussed');

  final String query;
  final String label;
  const CivitaiSort(this.query, this.label);
}

enum CivitaiPeriod {
  day('Day', 'Today'),
  week('Week', 'Week'),
  month('Month', 'Month'),
  allTime('AllTime', 'All time');

  final String query;
  final String label;
  const CivitaiPeriod(this.query, this.label);
}

/// One image from the feed, plus whatever generation data survived upload.
class CivitaiImage {
  final int id;
  final String url;
  final int width;
  final int height;
  final String? username;
  final String? baseModel;
  final String nsfwLevel;

  final String? prompt;
  final String? negativePrompt;
  final String? model;
  final String? sampler;
  final int? steps;
  final double? cfgScale;
  final String? seed;

  /// Anything else the uploader's tool wrote, in the order it arrived. Kept
  /// so an unusual pipeline's settings are still readable rather than
  /// discarded for not matching a known field.
  final Map<String, String> extra;

  const CivitaiImage({
    required this.id,
    required this.url,
    required this.width,
    required this.height,
    required this.nsfwLevel,
    this.username,
    this.baseModel,
    this.prompt,
    this.negativePrompt,
    this.model,
    this.sampler,
    this.steps,
    this.cfgScale,
    this.seed,
    this.extra = const {},
  });

  bool get hasPrompt => prompt != null && prompt!.trim().isNotEmpty;

  /// The page this image lives on, for opening it in a browser.
  Uri get pageUri => Uri.parse('https://civitai.com/images/$id');

  /// A CDN-resized copy. The feed hands back `original=true` URLs, which on
  /// a phone means downloading a 1000x1700 JPEG per grid cell; swapping the
  /// segment asks Civitai's CDN to resize before sending.
  String thumbUrl({int width = 450}) =>
      url.replaceFirst(RegExp(r'original=true'), 'width=$width');

  static const _knownKeys = {
    'prompt', 'negativePrompt', 'Model', 'sampler', 'steps', 'cfgScale',
    'seed', 'resources', 'civitaiResources', 'hashes', 'Model hash',
  };

  factory CivitaiImage.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>();

    String? text(String key) {
      final value = meta?[key];
      if (value == null) return null;
      final string = '$value'.trim();
      return string.isEmpty ? null : string;
    }

    final extra = <String, String>{};
    if (meta != null) {
      for (final entry in meta.entries) {
        if (_knownKeys.contains(entry.key)) continue;
        final value = entry.value;
        // Nested objects are resource lists and hash maps - useful to the
        // site, noise in a settings table.
        if (value == null || value is Map || value is List) continue;
        final string = '$value'.trim();
        if (string.isEmpty) continue;
        extra[entry.key] = string;
      }
    }

    return CivitaiImage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      nsfwLevel: json['nsfwLevel'] as String? ?? 'None',
      username: json['username'] as String?,
      baseModel: json['baseModel'] as String?,
      prompt: text('prompt'),
      negativePrompt: text('negativePrompt'),
      model: text('Model'),
      sampler: text('sampler'),
      steps: (meta?['steps'] as num?)?.toInt(),
      cfgScale: (meta?['cfgScale'] as num?)?.toDouble(),
      seed: text('seed'),
      extra: extra,
    );
  }
}

/// One page of the feed, with the cursor for the next.
class CivitaiPage {
  final List<CivitaiImage> items;

  /// Opaque cursor from `metadata.nextCursor`. Null at the end of the feed.
  final String? nextCursor;

  const CivitaiPage({required this.items, this.nextCursor});

  bool get hasMore => nextCursor != null;
}

class CivitaiException implements Exception {
  final String message;
  const CivitaiException(this.message);
  @override
  String toString() => message;
}

class CivitaiClient {
  final http.Client _client;

  CivitaiClient({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://civitai.com/api/v1/images';

  Future<CivitaiPage> images({
    int limit = 40,
    String? cursor,
    CivitaiRating rating = CivitaiRating.safe,
    CivitaiSort sort = CivitaiSort.reactions,
    CivitaiPeriod period = CivitaiPeriod.week,
    String? username,
    List<int> tagIds = const [],
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      // Not optional. Omitting it returns `meta: null` on every single
      // image, which makes the whole screen pointless.
      'withMeta': 'true',
      // Exclusive rather than cumulative - see CivitaiRating.
      'browsingLevel': '${rating.level}',
      // Images only. The feed mixes in videos, whose .mp4 URLs would reach
      // Image.network and render as a grid of broken cells.
      'type': 'image',
      'sort': sort.query,
      'period': period.query,
      if (cursor != null) 'cursor': cursor,
      if (username != null && username.isNotEmpty) 'username': username,
      // Numeric ids only; the API rejects names with a 400.
      if (tagIds.isNotEmpty) 'tags': tagIds.join(','),
    };

    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(_base).replace(queryParameters: query))
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw CivitaiException('Could not reach Civitai: $e');
    }

    if (response.statusCode == 429) {
      throw const CivitaiException(
          'Civitai is rate limiting this device. Wait a moment and try again.');
    }
    if (response.statusCode != 200) {
      throw CivitaiException('Civitai returned ${response.statusCode}');
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw const CivitaiException(
          'Civitai sent a response that could not be read');
    }

    return CivitaiPage(
      items: [
        for (final entry in (decoded['items'] as List? ?? const []))
          if (entry is Map) CivitaiImage.fromJson(entry.cast<String, dynamic>()),
      ],
      nextCursor:
          (decoded['metadata'] as Map?)?['nextCursor']?.toString(),
    );
  }

  void dispose() => _client.close();
}
