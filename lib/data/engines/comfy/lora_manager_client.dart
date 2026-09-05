// ==================== LoRA Manager Client ==================== //
//
// Reads the local model library that the `ComfyUI-Lora-Manager` addon keeps
// alongside the weights themselves.
//
// The addon writes a `<model>.metadata.json` and a `<model>.jpeg|.mp4`
// preview next to every checkpoint and LoRA, and serves them over an HTTP
// API. That is the difference between picking a model from a dropdown of
// filenames like `krea\SummerVibesHM_krea2_epoch8.safetensors` and picking
// one from a wall of thumbnails that says "Realism Enhancer Krea2, Krea 2,
// 218 MB, tagged realism". None of it needs a Civitai round trip - the
// addon has already resolved and cached all of it on disk.
//
// Two shapes of truth have to be reconciled here, and getting it wrong
// would write an unrunnable graph:
//
//   * The addon describes a model by its absolute path plus a `folder`
//     relative to the model root ("krea").
//   * ComfyUI's own `/object_info` combo - the only value a node will
//     accept - is the path relative to that root, Windows-separated:
//     `krea\SummerVibesHM_krea2_epoch8.safetensors`.
//
// So the browser only ever offers entries it can map back onto one of the
// node's real combo options, and hands that option string back. Anything
// the addon knows about but this node cannot load simply isn't shown.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';

enum ManagedModelKind {
  /// Everything the addon files under "checkpoints", which includes the
  /// `diffusion_models`/unet root - so a UNETLoader's model is here too.
  checkpoint,
  lora;

  String get prefix => this == ManagedModelKind.lora ? 'loras' : 'checkpoints';
  String get label => this == ManagedModelKind.lora ? 'LoRA' : 'Model';
}

const _videoExtensions = {'.mp4', '.webm', '.mov', '.mkv', '.avi'};

/// One model as the addon's list endpoint describes it.
class ManagedModel {
  /// The human name from Civitai ("Realism Enhancer Krea2"), or the file
  /// name when the addon could not resolve one.
  final String name;

  /// File name without extension, as the addon reports it.
  final String fileName;

  /// Absolute path on the server. The key for the detail endpoints.
  final String filePath;

  /// Folder relative to the model root, or empty at the root.
  final String folder;

  final String baseModel;
  final List<String> tags;
  final int sizeBytes;
  final bool favorite;

  /// Relative URL of the preview the addon serves, or empty.
  final String previewPath;

  const ManagedModel({
    required this.name,
    required this.fileName,
    required this.filePath,
    required this.folder,
    required this.baseModel,
    required this.tags,
    required this.sizeBytes,
    required this.favorite,
    required this.previewPath,
  });

  factory ManagedModel.fromJson(Map<String, dynamic> json) {
    final path = (json['file_path'] as String? ?? '').replaceAll('\\', '/');
    final fileName = json['file_name'] as String? ?? '';
    return ManagedModel(
      name: (json['model_name'] as String?)?.trim().isNotEmpty == true
          ? json['model_name'] as String
          : fileName,
      fileName: fileName,
      filePath: path,
      folder: json['folder'] as String? ?? '',
      baseModel: json['base_model'] as String? ?? '',
      tags: [for (final tag in (json['tags'] as List?) ?? const []) '$tag'],
      sizeBytes: (json['file_size'] as num?)?.toInt() ?? 0,
      favorite: json['favorite'] == true,
      previewPath: json['preview_url'] as String? ?? '',
    );
  }

  /// `SummerVibesHM_krea2_epoch8.safetensors`.
  String get basename =>
      filePath.contains('/') ? filePath.split('/').last : filePath;

  /// The path relative to the model root, forward-slashed and lowercased -
  /// the form a ComfyUI combo option is matched against.
  String get comfyKey =>
      (folder.isEmpty ? basename : '$folder/$basename').toLowerCase();

  bool get previewIsVideo {
    final path = Uri.tryParse(previewPath)?.queryParameters['path'] ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _videoExtensions.contains(path.substring(dot).toLowerCase());
  }

  bool get hasPreview => previewPath.isNotEmpty;

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final gb = sizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }

  /// Where to fetch the preview from. The addon returns an already-encoded
  /// relative URL; it is re-encoded through [EngineEndpoint.http] so the
  /// absolute Windows path in the query survives intact.
  Uri? previewUri(EngineEndpoint endpoint) {
    if (previewPath.isEmpty) return null;
    final relative = Uri.tryParse(previewPath);
    if (relative == null) return null;
    return endpoint.http(relative.path, relative.queryParameters);
  }
}

/// The rest of what the addon cached from Civitai, fetched per model.
class ManagedModelDetail {
  final String description;
  final List<String> trainedWords;
  final String creator;

  /// Remote Civitai stills for this model. Videos are excluded - there is
  /// no player here, and a poster still is what the grid actually needs.
  final List<String> imageUrls;

  /// The first still, asked for at thumbnail size. Civitai serves these at
  /// `original=true` - two or three megabytes each - and a grid of those
  /// downloaded in full is the whole cost worth avoiding, the same trap the
  /// Civitai browser had to sidestep.
  String? posterUrl({int width = 450}) => imageUrls.isEmpty
      ? null
      : imageUrls.first.replaceFirst(RegExp(r'original=true'), 'width=$width');

  /// Prompts attached to those stills, for reading what the model responds
  /// to. Same order as [imageUrls] is not guaranteed; these are only the
  /// entries that had one.
  final List<String> examplePrompts;

  const ManagedModelDetail({
    required this.description,
    required this.trainedWords,
    required this.creator,
    required this.imageUrls,
    required this.examplePrompts,
  });

  static const empty = ManagedModelDetail(
    description: '',
    trainedWords: [],
    creator: '',
    imageUrls: [],
    examplePrompts: [],
  );

  bool get isEmpty =>
      description.isEmpty &&
      trainedWords.isEmpty &&
      imageUrls.isEmpty &&
      examplePrompts.isEmpty;

  factory ManagedModelDetail.fromMetadata(Map<String, dynamic> meta) {
    final images = <String>[];
    final prompts = <String>[];
    for (final raw in (meta['images'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final url = raw['url'] as String?;
      if (url != null && url.isNotEmpty && raw['type'] != 'video') {
        images.add(url);
      }
      final prompt = (raw['meta'] as Map?)?['prompt'];
      if (prompt is String && prompt.trim().isNotEmpty) {
        prompts.add(prompt.trim());
      }
    }
    final model = (meta['model'] as Map?)?.cast<String, dynamic>();
    final description = meta['description'] as String? ??
        model?['description'] as String? ??
        '';
    return ManagedModelDetail(
      description: stripHtml(description),
      trainedWords: [
        for (final word in (meta['trainedWords'] as List?) ?? const [])
          if ('$word'.trim().isNotEmpty) '$word'.trim(),
      ],
      creator: (meta['creator'] as Map?)?['username'] as String? ?? '',
      imageUrls: images,
      examplePrompts: prompts,
    );
  }
}

/// Civitai descriptions are HTML. Nothing here renders HTML, and showing
/// the raw tags is worse than showing nothing, so they are flattened to
/// readable text with paragraph breaks preserved.
String stripHtml(String html) {
  if (html.isEmpty) return '';
  final withBreaks = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      // A paragraph break is a blank line, a list item is not - that
      // difference is most of what makes a long description readable.
      .replaceAll(RegExp(r'</(p|div|h[1-6])>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ');
  final text = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class LoraManagerClient {
  final EngineEndpoint endpoint;
  final http.Client _http;

  LoraManagerClient(this.endpoint, {http.Client? client})
      : _http = client ?? http.Client();

  void dispose() => _http.close();

  /// Everything the addon knows about, in one go.
  ///
  /// The library is small - a few dozen files, not the eleven thousand
  /// images the output gallery had to page through - so this pulls the lot
  /// and lets the browser filter locally. That keeps search and the folder
  /// and base-model chips instant instead of a request per keystroke.
  Future<List<ManagedModel>> list(ManagedModelKind kind, {int cap = 600}) async {
    final models = <ManagedModel>[];
    var page = 1;
    while (models.length < cap) {
      final body = await _json(
        endpoint.http('/api/lm/${kind.prefix}/list', {
          'page': '$page',
          'page_size': '100',
          'sort_by': 'name',
        }),
      );
      for (final raw in (body['items'] as List?) ?? const []) {
        if (raw is Map<String, dynamic>) models.add(ManagedModel.fromJson(raw));
      }
      final totalPages = (body['total_pages'] as num?)?.toInt() ?? page;
      if (page >= totalPages) break;
      page++;
    }
    return models;
  }

  /// The cached Civitai record for one model. Returns [ManagedModelDetail
  /// .empty] rather than throwing when the addon has nothing - a model
  /// that was never on Civitai is a normal case, not a failure.
  Future<ManagedModelDetail> detail(
    ManagedModelKind kind,
    ManagedModel model,
  ) async {
    try {
      final body = await _json(
        endpoint.http('/api/lm/${kind.prefix}/metadata', {
          'file_path': model.filePath,
        }),
      );
      final meta = (body['metadata'] as Map?)?.cast<String, dynamic>();
      if (meta == null) return ManagedModelDetail.empty;
      return ManagedModelDetail.fromMetadata(meta);
    } catch (_) {
      return ManagedModelDetail.empty;
    }
  }

  /// Whether the addon is installed on this server at all.
  Future<bool> isInstalled() async {
    try {
      await _json(endpoint.http('/api/lm/loras/folders'));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) {
      throw const ServerError(
          'The ComfyUI-Lora-Manager addon is not installed on this server',
          statusCode: 404);
    }
    if (response.statusCode != 200) {
      throw ServerError('The model library returned ${response.statusCode}',
          statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ServerError('The model library sent an unreadable reply');
    }
    return decoded;
  }
}
