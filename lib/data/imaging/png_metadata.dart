// ==================== PNG Metadata ==================== //
//
// Reads what a generator wrote into the PNG itself. No API call is involved
// and none is needed: both A1111 and ComfyUI embed everything in text chunks
// at save time, so this works offline, works on images the app didn't make,
// and keeps working after the server that made them is gone.
//
// Conventions:
//  * **A1111 / Forge** writes a single `parameters` chunk - the same block
//    you see in its own UI: prompt, then `Negative prompt:`, then a comma
//    separated `Key: value` line.
//  * **ComfyUI** writes `prompt` (the API graph it actually executed) and
//    normally `workflow` (the editor graph, which is what re-imports). Both
//    are raw JSON, so the readable summary here is derived by walking the
//    graph for the nodes that carry settings.
//
// The chunks are walked directly rather than by decoding the image, because
// decoding a 4000px PNG to read a few hundred bytes of text is an enormous
// waste - this reads the header and skips over the pixel data entirely.

import 'dart:convert';
import 'dart:io' show gzip, ZLibCodec;
import 'dart:typed_data';

import 'package:sd_companion/data/imaging/image_metadata_parser.dart';
import 'package:sd_companion/domain/generation/image_metadata.dart';

const List<int> _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// The image's true pixel size, read straight from the PNG header.
///
/// This is authoritative in a way the graph is not: a workflow's `width`
/// may be wired from another node, may describe a latent rather than the
/// output, and may have been changed by an upscale further down the graph.
(int, int)? readPngDimensions(Uint8List bytes) {
  if (bytes.length < 33) return null;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  // IHDR is required to be the first chunk: [len][type][w][h]...
  if (String.fromCharCodes(bytes, 12, 16) != 'IHDR') return null;
  return (data.getUint32(16, Endian.big), data.getUint32(20, Endian.big));
}

/// Every text chunk in [bytes], keyed by PNG keyword.
///
/// Handles `tEXt` (plain), `zTXt` (deflated) and `iTXt` (UTF-8, optionally
/// deflated). Returns an empty map for anything that isn't a PNG, rather
/// than throwing - a JPEG from the gallery is a normal input here.
Map<String, String> readPngTextChunks(Uint8List bytes) {
  if (bytes.length < 8) return const {};
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) return const {};
  }

  final out = <String, String>{};
  final data = ByteData.sublistView(bytes);
  var offset = 8;

  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset, Endian.big);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    final start = offset + 8;
    final end = start + length;
    if (end > bytes.length) break;

    switch (type) {
      case 'tEXt':
        final entry = _splitKeyword(bytes, start, end);
        if (entry != null) {
          out[entry.$1] = latin1.decode(entry.$2, allowInvalid: true);
        }
      case 'zTXt':
        final entry = _splitKeyword(bytes, start, end);
        if (entry != null && entry.$2.isNotEmpty) {
          // [0] is the compression method; the rest is the deflate stream.
          final text = _inflate(entry.$2.sublist(1));
          if (text != null) out[entry.$1] = text;
        }
      case 'iTXt':
        final entry = _readInternationalText(bytes, start, end);
        if (entry != null) out[entry.$1] = entry.$2;
      case 'IEND':
        return out;
    }

    offset = end + 4; // skip the trailing CRC
  }
  return out;
}

/// Splits `keyword\0rest` out of a chunk body.
(String, Uint8List)? _splitKeyword(Uint8List bytes, int start, int end) {
  for (var i = start; i < end; i++) {
    if (bytes[i] == 0) {
      final keyword = latin1.decode(bytes.sublist(start, i), allowInvalid: true);
      return (keyword, bytes.sublist(i + 1, end));
    }
  }
  return null;
}

/// `keyword\0 compressionFlag compressionMethod languageTag\0 translated\0 text`
(String, String)? _readInternationalText(Uint8List bytes, int start, int end) {
  final split = _splitKeyword(bytes, start, end);
  if (split == null) return null;
  final body = split.$2;
  if (body.length < 2) return null;

  final compressed = body[0] == 1;
  var cursor = 2; // past the compression flag and method
  var seenNulls = 0;
  while (cursor < body.length && seenNulls < 2) {
    if (body[cursor] == 0) seenNulls++;
    cursor++;
  }
  if (cursor > body.length) return null;

  final payload = body.sublist(cursor);
  final text = compressed ? _inflate(payload) : utf8.decode(payload, allowMalformed: true);
  return text == null ? null : (split.$1, text);
}

String? _inflate(Uint8List deflated) {
  for (final codec in [ZLibCodec(raw: false), ZLibCodec(raw: true)]) {
    try {
      return utf8.decode(codec.decode(deflated), allowMalformed: true);
    } catch (_) {
      // Try the next framing before giving up.
    }
  }
  try {
    return utf8.decode(gzip.decode(deflated), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// Reads [bytes] and interprets whatever convention it finds.
ImageMetadata readImageMetadata(Uint8List bytes) {
  final chunks = readPngTextChunks(bytes);
  final size = readPngDimensions(bytes);
  if (chunks.isEmpty) {
    return size == null
        ? ImageMetadata.empty
        : ImageMetadata(
            source: MetadataSource.none,
            fields: {'Dimensions': '${size.$1} × ${size.$2}'},
          );
  }

  final parameters = chunks['parameters'];
  if (parameters != null && parameters.trim().isNotEmpty) {
    return _fromAutomatic1111(parameters, chunks, size);
  }

  final prompt = chunks['prompt'];
  if (prompt != null && prompt.trim().isNotEmpty) {
    return _fromComfy(prompt, chunks, size);
  }

  return ImageMetadata(
    source: MetadataSource.unknown,
    raw: chunks,
    fields: size == null ? const {} : {'Dimensions': '${size.$1} × ${size.$2}'},
  );
}

/// Puts the real pixel size at the head of the field list.
Map<String, String> _withDimensions(Map<String, String> fields, (int, int)? size) {
  if (size == null) return fields;
  return {'Dimensions': '${size.$1} × ${size.$2}', ...fields};
}

ImageMetadata _fromAutomatic1111(
    String parameters, Map<String, String> chunks, (int, int)? size) {
  final parsed = parseImageInfo(parameters);
  final prompt = parsed.remove('prompt');
  final negative = parsed.remove('negativePrompt');
  return ImageMetadata(
    source: MetadataSource.automatic1111,
    prompt: prompt,
    negativePrompt: negative,
    fields: _withDimensions(parsed, size),
    raw: chunks,
  );
}

/// Walks the executed API graph for the handful of nodes that carry settings
/// a person would actually want to read back.
///
/// This is deliberately shape-driven rather than a fixed node-type list:
/// custom samplers and loaders are the norm in ComfyUI, so matching on the
/// *input names* a node exposes survives graphs this code has never seen.
ImageMetadata _fromComfy(
    String promptJson, Map<String, String> chunks, (int, int)? size) {
  Map<String, dynamic> graph;
  try {
    graph = (jsonDecode(promptJson) as Map).cast<String, dynamic>();
  } catch (_) {
    return ImageMetadata(
      source: MetadataSource.comfyui,
      raw: chunks,
      fields: _withDimensions(const {}, size),
    );
  }

  final fields = <String, String>{};
  final prompts = <String>[];
  final negatives = <String>[];

  // A CLIPTextEncode feeding a sampler's `negative` input is the negative
  // prompt; there is no flag on the node itself saying so.
  final negativeNodeIds = <String>{};
  for (final node in graph.values) {
    if (node is! Map) continue;
    final inputs = node['inputs'];
    if (inputs is! Map) continue;
    final link = inputs['negative'];
    if (link is List && link.isNotEmpty) negativeNodeIds.add('${link.first}');
  }

  void put(String label, Object? value) {
    if (value == null) return;
    // `["83", 1]` is a wire to another node's output, not a value. Printing
    // it produced settings like `Width: [83, 1]`, which is worse than
    // omitting the row - the real number is read from the file header.
    if (value is List || value is Map) return;
    final text = value is double && value == value.roundToDouble()
        ? value.toInt().toString()
        : '$value';
    if (text.isEmpty || fields.containsKey(label)) return;
    fields[label] = text;
  }

  for (final entry in graph.entries) {
    final node = entry.value;
    if (node is! Map) continue;
    final inputs = (node['inputs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final type = '${node['class_type'] ?? ''}';

    final text = inputs['text'];
    if (text is String && text.trim().isNotEmpty) {
      (negativeNodeIds.contains(entry.key) ? negatives : prompts).add(text.trim());
    }

    put('Steps', inputs['steps']);
    put('CFG', inputs['cfg']);
    put('Sampler', inputs['sampler_name']);
    put('Scheduler', inputs['scheduler']);
    put('Denoise', inputs['denoise']);
    put('Seed', inputs['seed'] ?? inputs['noise_seed']);
    put('Batch size', inputs['batch_size']);
    put('Model', inputs['ckpt_name'] ?? inputs['unet_name'] ?? inputs['model_name']);
    put('VAE', inputs['vae_name']);
    if (type.contains('LoraLoader')) put('LoRA', inputs['lora_name']);
  }

  fields['Nodes'] = '${graph.length}';

  return ImageMetadata(
    source: MetadataSource.comfyui,
    prompt: prompts.isEmpty ? null : prompts.join('\n\n'),
    negativePrompt: negatives.isEmpty ? null : negatives.join('\n\n'),
    fields: _withDimensions(fields, size),
    raw: chunks,
  );
}
