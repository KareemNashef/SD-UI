// Crop and resize are pixel surgery: a rect that is one pixel out still
// returns a perfectly valid image, so the only way to know it is right is
// to check the actual dimensions and where the colours landed.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:sd_companion/data/imaging/image_processor.dart';

/// A PNG with four distinctly coloured quadrants, so a crop can be checked
/// by which colour survived rather than only by size.
Uint8List quadrantPng(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final left = x < w / 2;
      final top = y < h / 2;
      final colour = top
          ? (left ? [255, 0, 0] : [0, 255, 0])
          : (left ? [0, 0, 255] : [255, 255, 0]);
      image.setPixelRgb(x, y, colour[0], colour[1], colour[2]);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cropImageBytes', () {
    test('returns exactly the requested rect', () async {
      final out = await cropImageBytes(
        bytes: quadrantPng(200, 100),
        x: 20,
        y: 10,
        width: 60,
        height: 40,
      );
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 60);
      expect(decoded.height, 40);
    });

    test('keeps the region asked for, not a neighbouring one', () async {
      // Bottom-right quadrant of a 200x100 image is yellow.
      final out = await cropImageBytes(
        bytes: quadrantPng(200, 100),
        x: 150,
        y: 75,
        width: 40,
        height: 20,
      );
      final decoded = img.decodeImage(out!)!;
      final pixel = decoded.getPixel(5, 5);
      expect(pixel.r, greaterThan(200));
      expect(pixel.g, greaterThan(200));
      expect(pixel.b, lessThan(60), reason: 'expected the yellow quadrant');
    });

    test('a rect running past the edge is clamped, not thrown', () async {
      final out = await cropImageBytes(
        bytes: quadrantPng(100, 100),
        x: 80,
        y: 80,
        width: 500,
        height: 500,
      );
      expect(out, isNotNull, reason: 'an over-large rect must clip, not fail');
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 20);
      expect(decoded.height, 20);
    });

    test('undecodable bytes return null rather than throwing', () async {
      final out = await cropImageBytes(
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        x: 0,
        y: 0,
        width: 10,
        height: 10,
      );
      expect(out, isNull);
    });
  });

  group('resizeImageBytes', () {
    test('produces exactly the requested size', () async {
      final out = await resizeImageBytes(
        bytes: quadrantPng(400, 300),
        width: 160,
        height: 120,
      );
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 160);
      expect(decoded.height, 120);
    });

    test('upscaling works as well as downscaling', () async {
      final out = await resizeImageBytes(
        bytes: quadrantPng(50, 50),
        width: 200,
        height: 200,
      );
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 200);
      expect(decoded.height, 200);
    });

    test('a zero or negative target is clamped to a real image', () async {
      final out =
          await resizeImageBytes(bytes: quadrantPng(64, 64), width: 0, height: 0);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, greaterThanOrEqualTo(1));
      expect(decoded.height, greaterThanOrEqualTo(1));
    });
  });
}
