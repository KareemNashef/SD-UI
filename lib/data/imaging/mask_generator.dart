// ==================== Mask Generator ==================== //

// Flutter imports
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/domain/drawing/canvas_geometry.dart';
import 'package:sd_companion/domain/drawing/stroke.dart';

// Mask Generator Implementation

/// Generates a mask image from drawing paths
Future<Uint8List?> generateDrawingMask({
  required ui.Image decodedImage,
  required List<DrawingPath> paths,
  required Size canvasRenderedSize,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final imageSize = Size(
    decodedImage.width.toDouble(),
    decodedImage.height.toDouble(),
  );

  canvas.drawRect(
    Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
    Paint()..color = Colors.black,
  );

  canvas.saveLayer(
    Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
    Paint(),
  );

  // One definition of the letterbox maths, shared with the coordinate
  // converter and the painter - see the note on `displayRectFor`.
  final averageScaleFactor = maskStrokeScale(
    imageSize: imageSize,
    containerSize: canvasRenderedSize,
  );

  for (final pathData in paths) {
    if (pathData.points.isEmpty) continue;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = pathData.strokeWidth * averageScaleFactor
      ..style = PaintingStyle.stroke;

    if (pathData.mode == DrawingMode.draw) {
      paint.color = Colors.white;
      paint.blendMode = BlendMode.srcOver;
    } else {
      paint.color = Colors.transparent;
      paint.blendMode = BlendMode.clear;
    }

    final path = Path();
    for (int i = 0; i < pathData.points.length; i++) {
      final point = pathData.points[i].point;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
  }
  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(
    imageSize.width.toInt(),
    imageSize.height.toInt(),
  );
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}
