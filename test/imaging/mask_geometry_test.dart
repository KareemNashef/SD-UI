// The mask pipeline's failure mode is silent: a wrong coordinate mapping
// still produces a valid PNG, the run still completes, and the only symptom
// is that the wrong part of the picture changed. These tests pin the
// letterbox maths and the black/white convention that both engines rely on.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/data/imaging/image_processor.dart';
import 'package:sd_companion/data/imaging/mask_generator.dart';
import 'package:sd_companion/domain/drawing/canvas_geometry.dart';
import 'package:sd_companion/domain/drawing/stroke.dart';

/// A solid image of the given size, to paint a mask against.
Future<ui.Image> _image(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF808080),
  );
  return recorder.endRecording().toImage(w, h);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('displayRectFor', () {
    test('a wide image letterboxes with bars top and bottom', () {
      final rect = displayRectFor(
        imageSize: const Size(200, 100), // 2:1
        containerSize: const Size(200, 200),
      );
      expect(rect.width, 200);
      expect(rect.height, 100);
      expect(rect.left, 0);
      expect(rect.top, 50, reason: 'should be vertically centred');
    });

    test('a tall image letterboxes with bars left and right', () {
      final rect = displayRectFor(
        imageSize: const Size(100, 200), // 1:2
        containerSize: const Size(200, 200),
      );
      expect(rect.width, 100);
      expect(rect.height, 200);
      expect(rect.top, 0);
      expect(rect.left, 50, reason: 'should be horizontally centred');
    });

    test('a matching aspect ratio fills the container exactly', () {
      final rect = displayRectFor(
        imageSize: const Size(400, 400),
        containerSize: const Size(200, 200),
      );
      expect(rect, const Rect.fromLTWH(0, 0, 200, 200));
    });
  });

  group('convertScreenToImageCoordinates', () {
    late ui.Image image;
    setUp(() async => image = await _image(200, 100));
    tearDown(() => image.dispose());

    test('the centre of the letterboxed area maps to the image centre', () {
      final point = convertScreenToImageCoordinates(
        localPosition: const Offset(100, 100), // container centre
        containerSize: const Size(200, 200),
        decodedImage: image,
      );
      expect(point.dx, closeTo(100, 0.01));
      expect(point.dy, closeTo(50, 0.01));
    });

    test('a tap in the letterbox bar clamps into the image, not outside it', () {
      // y=10 is inside the top bar (image occupies y 50..150).
      final point = convertScreenToImageCoordinates(
        localPosition: const Offset(100, 10),
        containerSize: const Size(200, 200),
        decodedImage: image,
      );
      expect(point.dy, closeTo(0, 0.01),
          reason: 'must clamp to the top edge rather than go negative');
      expect(point.dy, greaterThanOrEqualTo(0));
    });

    test('the far corner maps to the far corner of the image', () {
      final point = convertScreenToImageCoordinates(
        localPosition: const Offset(200, 150),
        containerSize: const Size(200, 200),
        decodedImage: image,
      );
      expect(point.dx, closeTo(200, 0.01));
      expect(point.dy, closeTo(100, 0.01));
    });
  });

  group('generateDrawingMask', () {
    test('produces a mask at the image resolution, not the canvas size', () async {
      final image = await _image(320, 200);
      addTearDown(image.dispose);

      final mask = await generateDrawingMask(
        decodedImage: image,
        paths: [
          DrawingPath(
            points: [
              DrawingPoint(point: const Offset(100, 100)),
              DrawingPoint(point: const Offset(200, 100)),
            ],
            mode: DrawingMode.draw,
            strokeWidth: 20,
          ),
        ],
        // Deliberately a different size from the image: the mask must come
        // back at image resolution regardless of how big the canvas was.
        canvasRenderedSize: const Size(160, 100),
      );

      expect(mask, isNotNull);
      final decoded = await decodeImageFromList(mask!);
      addTearDown(decoded.dispose);
      expect(decoded.width, 320);
      expect(decoded.height, 200);
    });

    test('paints white where drawn and leaves black where not', () async {
      final image = await _image(64, 64);
      addTearDown(image.dispose);

      final mask = await generateDrawingMask(
        decodedImage: image,
        paths: [
          DrawingPath(
            points: [
              DrawingPoint(point: const Offset(32, 32)),
              DrawingPoint(point: const Offset(33, 32)),
            ],
            mode: DrawingMode.draw,
            strokeWidth: 20,
          ),
        ],
        canvasRenderedSize: const Size(64, 64),
      );
      expect(mask, isNotNull);

      final decoded = await decodeImageFromList(mask!);
      addTearDown(decoded.dispose);
      final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);

      int lumAt(int x, int y) {
        final offset = (y * decoded.width + x) * 4;
        return data!.getUint8(offset); // red channel; mask is greyscale
      }

      expect(lumAt(32, 32), greaterThan(200),
          reason: 'the painted centre must be white = regenerate');
      expect(lumAt(2, 2), lessThan(50),
          reason: 'an untouched corner must stay black = keep');
    });

    test('an erase stroke removes paint rather than adding it', () async {
      final image = await _image(64, 64);
      addTearDown(image.dispose);

      final mask = await generateDrawingMask(
        decodedImage: image,
        paths: [
          DrawingPath(
            points: [
              DrawingPoint(point: const Offset(32, 32)),
              DrawingPoint(point: const Offset(33, 32)),
            ],
            mode: DrawingMode.draw,
            strokeWidth: 40,
          ),
          DrawingPath(
            points: [
              DrawingPoint(point: const Offset(32, 32)),
              DrawingPoint(point: const Offset(33, 32)),
            ],
            mode: DrawingMode.erase,
            strokeWidth: 40,
          ),
        ],
        canvasRenderedSize: const Size(64, 64),
      );
      expect(mask, isNotNull);

      final decoded = await decodeImageFromList(mask!);
      addTearDown(decoded.dispose);
      final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      final centre = data!.getUint8((32 * decoded.width + 32) * 4);

      expect(centre, lessThan(50),
          reason: 'erasing over a painted area must return it to keep-black, '
              'which only works if the generator wraps strokes in a saveLayer');
    });
  });

  group('generateOutpaintData', () {
    test('enlarges the canvas by the padding on every side', () async {
      final image = await _image(100, 80);
      addTearDown(image.dispose);

      final data = await generateOutpaintData(
        decodedImage: image,
        padLeft: 20,
        padRight: 10,
        padTop: 5,
        padBottom: 15,
      );
      expect(data, hasLength(2), reason: 'returns [image, mask]');

      final expanded = await decodeImageFromList(data[0]);
      addTearDown(expanded.dispose);
      expect(expanded.width, 130); // 100 + 20 + 10
      expect(expanded.height, 100); // 80 + 5 + 15

      final mask = await decodeImageFromList(data[1]);
      addTearDown(mask.dispose);
      expect(mask.width, expanded.width,
          reason: 'mask and image must agree, or the engine crops one to the other');
      expect(mask.height, expanded.height);
    });

    test('marks the new area for regeneration and keeps the original', () async {
      final image = await _image(100, 100);
      addTearDown(image.dispose);

      final data = await generateOutpaintData(
        decodedImage: image,
        padLeft: 40,
        padRight: 40,
        padTop: 40,
        padBottom: 40,
      );
      final mask = await decodeImageFromList(data[1]);
      addTearDown(mask.dispose);
      final bytes = await mask.toByteData(format: ui.ImageByteFormat.rawRgba);

      int lumAt(int x, int y) => bytes!.getUint8((y * mask.width + x) * 4);

      expect(lumAt(5, 5), greaterThan(200),
          reason: 'padded area must be white = regenerate');
      expect(lumAt(90, 90), lessThan(50),
          reason: 'the original centre must be black = keep');
    });

    test('the keep region is inset, so the seam has overlap to blend into', () async {
      final image = await _image(100, 100);
      addTearDown(image.dispose);

      final data = await generateOutpaintData(
        decodedImage: image,
        padLeft: 40,
        padRight: 0,
        padTop: 0,
        padBottom: 0,
      );
      final mask = await decodeImageFromList(data[1]);
      addTearDown(mask.dispose);
      final bytes = await mask.toByteData(format: ui.ImageByteFormat.rawRgba);

      int lumAt(int x, int y) => bytes!.getUint8((y * mask.width + x) * 4);

      // The original starts at x=40. A 16px overlap means x=41..55 is still
      // marked for regeneration so the model repaints across the join
      // instead of butting up against a hard rectangle.
      expect(lumAt(45, 50), greaterThan(200),
          reason: 'the overlap band just inside the original must regenerate');
      expect(lumAt(80, 50), lessThan(50),
          reason: 'well inside the original must be kept');
    });
  });
}
