// ==================== Mask Generator ==================== //

// Flutter imports
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/models/drawing_models.dart';

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

  // Calculate Aspect Ratios for scaling
  final imageAspectRatio = imageSize.width / imageSize.height;
  final containerAspectRatio =
      canvasRenderedSize.width / canvasRenderedSize.height;
  late final Size displaySize;

  if (imageAspectRatio > containerAspectRatio) {
    displaySize = Size(
      canvasRenderedSize.width,
      canvasRenderedSize.width / imageAspectRatio,
    );
  } else {
    displaySize = Size(
      canvasRenderedSize.height * imageAspectRatio,
      canvasRenderedSize.height,
    );
  }

  final double scaleFactorX = imageSize.width / displaySize.width;
  final double scaleFactorY = imageSize.height / displaySize.height;
  final double averageScaleFactor = (scaleFactorX + scaleFactorY) / 2;

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
