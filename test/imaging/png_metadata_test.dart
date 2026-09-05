// Metadata is read straight out of the file, so these build real PNG byte
// streams rather than mocking the reader. A chunk walker that is subtly
// wrong still returns *something*, which is exactly the kind of bug that
// survives a casual look at the screen.

import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/data/imaging/png_metadata.dart';
import 'package:sd_companion/domain/generation/image_metadata.dart';

const _signature = [137, 80, 78, 71, 13, 10, 26, 10];

/// Builds a PNG containing [chunks] plus the structural chunks a real file
/// has, so the walker has to skip IHDR/IDAT correctly to reach the text.
Uint8List buildPng(List<(String, List<int>)> chunks) {
  final out = BytesBuilder()..add(_signature);

  void addChunk(String type, List<int> body) {
    final header = ByteData(4)..setUint32(0, body.length, Endian.big);
    out
      ..add(header.buffer.asUint8List())
      ..add(ascii.encode(type))
      ..add(body)
      ..add([0, 0, 0, 0]); // CRC - never validated by the reader
  }

  // A plausible IHDR, then the text, then pixel data, then IEND.
  final ihdr = ByteData(13)
    ..setUint32(0, 64, Endian.big)
    ..setUint32(4, 64, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  addChunk('IHDR', ihdr.buffer.asUint8List());
  for (final chunk in chunks) {
    addChunk(chunk.$1, chunk.$2);
  }
  addChunk('IDAT', List<int>.filled(2048, 7));
  addChunk('IEND', const []);
  return out.toBytes();
}

List<int> textChunk(String keyword, String text) =>
    [...latin1.encode(keyword), 0, ...latin1.encode(text)];

List<int> compressedTextChunk(String keyword, String text) => [
      ...latin1.encode(keyword),
      0,
      0, // compression method: deflate
      ...ZLibCodec().encode(utf8.encode(text)),
    ];

void main() {
  group('readPngTextChunks', () {
    test('reads a plain tEXt chunk past IHDR', () {
      final png = buildPng([('tEXt', textChunk('parameters', 'a cat'))]);
      expect(readPngTextChunks(png), {'parameters': 'a cat'});
    });

    test('reads a deflated zTXt chunk', () {
      final png = buildPng([
        ('zTXt', compressedTextChunk('workflow', '{"nodes":[]}')),
      ]);
      expect(readPngTextChunks(png)['workflow'], '{"nodes":[]}');
    });

    test('reads several chunks in one file', () {
      final png = buildPng([
        ('tEXt', textChunk('prompt', '{"1":{}}')),
        ('tEXt', textChunk('workflow', '{"nodes":[]}')),
      ]);
      final chunks = readPngTextChunks(png);
      expect(chunks.keys, containsAll(['prompt', 'workflow']));
    });

    test('a non-PNG returns empty rather than throwing', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5]);
      expect(readPngTextChunks(jpeg), isEmpty);
    });

    test('a truncated file returns what it could read, without throwing', () {
      final png = buildPng([('tEXt', textChunk('parameters', 'a cat'))]);
      expect(() => readPngTextChunks(png.sublist(0, 30)), returnsNormally);
    });
  });

  group('readImageMetadata - A1111 / Forge', () {
    test('splits prompt, negative prompt and settings', () {
      const block = 'a photo of a cat, golden hour\n'
          'Negative prompt: blurry, low quality\n'
          'Steps: 28, Sampler: DPM++ 2M, CFG scale: 6.5, Seed: 12345, Size: 768x512';
      final png = buildPng([('tEXt', textChunk('parameters', block))]);

      final meta = readImageMetadata(png);
      expect(meta.source, MetadataSource.automatic1111);
      expect(meta.prompt, contains('golden hour'));
      expect(meta.negativePrompt, contains('blurry'));
      expect(meta.fields, isNotEmpty);
      expect(meta.raw['parameters'], block);
    });
  });

  group('readImageMetadata - ComfyUI', () {
    /// A minimal but realistic API graph: a checkpoint loader, two text
    /// encoders (one wired to the sampler's negative input), a sampler and
    /// a latent.
    const graph = '''
{
  "4": {"class_type": "CheckpointLoaderSimple",
        "inputs": {"ckpt_name": "illustrious.safetensors"}},
  "6": {"class_type": "CLIPTextEncode",
        "inputs": {"text": "a castle on a hill", "clip": ["4", 1]}},
  "7": {"class_type": "CLIPTextEncode",
        "inputs": {"text": "watermark, text", "clip": ["4", 1]}},
  "3": {"class_type": "KSampler",
        "inputs": {"seed": 987654, "steps": 24, "cfg": 7.5,
                   "sampler_name": "euler", "scheduler": "normal",
                   "denoise": 1.0, "positive": ["6", 0], "negative": ["7", 0]}},
  "5": {"class_type": "EmptyLatentImage",
        "inputs": {"width": 832, "height": 1216, "batch_size": 1}}
}''';

    test('summarises the executed graph without any server call', () {
      final png = buildPng([('tEXt', textChunk('prompt', graph))]);
      final meta = readImageMetadata(png);

      expect(meta.source, MetadataSource.comfyui);
      expect(meta.fields['Steps'], '24');
      expect(meta.fields['CFG'], '7.5');
      expect(meta.fields['Sampler'], 'euler');
      expect(meta.fields['Seed'], '987654');
      expect(meta.fields['Dimensions'], '64 × 64',
          reason: 'size must come from the file header, not the graph');
      expect(meta.fields['Model'], 'illustrious.safetensors');
    });

    test('tells the positive prompt from the negative by how it is wired', () {
      final png = buildPng([('tEXt', textChunk('prompt', graph))]);
      final meta = readImageMetadata(png);

      expect(meta.prompt, contains('castle'));
      expect(meta.negativePrompt, contains('watermark'));
      expect(meta.prompt, isNot(contains('watermark')),
          reason: 'the node feeding `negative` must not land in the prompt');
    });

    test('keeps the raw graphs so a workflow can be recovered verbatim', () {
      final png = buildPng([
        ('tEXt', textChunk('prompt', graph)),
        ('tEXt', textChunk('workflow', '{"nodes":[1,2,3]}')),
      ]);
      final meta = readImageMetadata(png);
      expect(meta.comfyPrompt, graph);
      expect(meta.comfyWorkflow, '{"nodes":[1,2,3]}');
    });

    test('malformed graph JSON degrades to "ComfyUI, no detail"', () {
      final png = buildPng([('tEXt', textChunk('prompt', '{not json'))]);
      final meta = readImageMetadata(png);
      expect(meta.source, MetadataSource.comfyui);
      // No graph detail survives, but the file header still knows its size.
      expect(meta.fields.keys, ['Dimensions']);
    });
  });

  test('an image with no text chunks reports none, not a crash', () {
    final png = buildPng(const []);
    expect(readImageMetadata(png).source, MetadataSource.none);
    expect(readImageMetadata(png).isEmpty, isTrue);
  });

  group('dimensions and node links', () {
    test('reads the true pixel size from IHDR without decoding', () {
      final png = buildPng(const []);
      expect(readPngDimensions(png), (64, 64));
    });

    test('a wired width is omitted rather than printed as a link', () {
      // `["83", 1]` is a wire to node 83's output - the shape ComfyUI uses
      // whenever a value is computed upstream. It once rendered as
      // `Width: [83, 1]`.
      const graph = '{"5": {"class_type": "EmptyLatentImage",'
          '"inputs": {"width": ["83", 1], "height": ["83", 2], "batch_size": 1}}}';
      final png = buildPng([('tEXt', textChunk('prompt', graph))]);
      final meta = readImageMetadata(png);

      expect(meta.fields.values.any((v) => v.contains('[')), isFalse,
          reason: 'no field may render a node link as its value');
      expect(meta.fields['Dimensions'], '64 × 64');
      expect(meta.fields['Batch size'], '1');
    });

    test('an image with no metadata still reports its size', () {
      final png = buildPng(const []);
      expect(readImageMetadata(png).fields['Dimensions'], '64 × 64');
    });
  });
}
