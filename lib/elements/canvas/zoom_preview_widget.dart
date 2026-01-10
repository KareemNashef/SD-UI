// ==================== Zoom Preview Widget ==================== //

// Flutter imports
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/models/drawing_models.dart';

// Zoom Preview Widget Implementation

class ZoomPreviewWidget extends StatelessWidget {
  final ui.Image decodedImage;
  final List<DrawingPath> allPaths;
  final List<DrawingPoint> currentPath;
  final DrawingMode currentDrawingMode;
  final double strokeWidth;
  final Offset currentDrawingPoint;
  final Size originalCanvasSize;
  final double zoomFactor;
  final Rect displayRect;
  final Size previewSize = const Size(
    180,
    180,
  ); // INCREASED FROM 120 to 180 (1.5x)

  const ZoomPreviewWidget({
    super.key,
    required this.decodedImage,
    required this.allPaths,
    required this.currentPath,
    required this.currentDrawingMode,
    required this.strokeWidth,
    required this.currentDrawingPoint,
    required this.originalCanvasSize,
    required this.zoomFactor,
    required this.displayRect,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    // ISSUE 2 FIX: Ensure there's always buffer space around the brush
    // We want the brush to take up at most 60% of the preview diameter
    final double maxBrushDiameter = previewSize.width * 0.6;
    final double fittingZoomFactor = (strokeWidth > 0)
        ? maxBrushDiameter / strokeWidth
        : double.infinity;

    // Use the smaller of the two zoom factors
    final double effectiveZoomFactor = min(zoomFactor, fittingZoomFactor);

    // Calculate the viewport using this new, safe "effectiveZoomFactor"
    final double viewportWidth = previewSize.width / effectiveZoomFactor;
    final double viewportHeight = previewSize.height / effectiveZoomFactor;

    // Convert the user's touch point from screen coordinates to display coordinates
    final pointOnDisplay = currentDrawingPoint - displayRect.topLeft;

    // Center the viewport on the user's touch point
    double viewportLeft = pointOnDisplay.dx - (viewportWidth / 2);
    double viewportTop = pointOnDisplay.dy - (viewportHeight / 2);

    final viewportRect = Rect.fromLTWH(
      viewportLeft,
      viewportTop,
      viewportWidth,
      viewportHeight,
    );

    return Container(
      width: previewSize.width,
      height: previewSize.height,
      decoration: BoxDecoration(
        color: Colors.black, // Dark background behind the image
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(previewSize.width),
      ),
      child: CustomPaint(
        foregroundPainter: _ReticlePainter(
          brushSize: strokeWidth,
          zoomFactor: effectiveZoomFactor,
          isErasing: currentDrawingMode == DrawingMode.erase,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(previewSize.width),
          child: SizedBox(
            width: previewSize.width,
            height: previewSize.height,
            child: CustomPaint(
              painter: _ZoomViewPainter(
                image: decodedImage,
                paths: [
                  ...allPaths,
                  DrawingPath(
                    points: currentPath,
                    mode: currentDrawingMode,
                    strokeWidth: strokeWidth,
                  ),
                ],
                imageSize: Size(
                  decodedImage.width.toDouble(),
                  decodedImage.height.toDouble(),
                ),
                displayRect: displayRect,
                viewportRect: viewportRect,
                zoomFactor: effectiveZoomFactor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Custom Painters ==================== //

class _ZoomViewPainter extends CustomPainter {
  final ui.Image image;
  final List<DrawingPath> paths;
  final Size imageSize;
  final Rect displayRect;
  final Rect viewportRect;
  final double zoomFactor;

  _ZoomViewPainter({
    required this.image,
    required this.paths,
    required this.imageSize,
    required this.displayRect,
    required this.viewportRect,
    required this.zoomFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final destinationRect = Rect.fromLTWH(0, 0, size.width, size.height);

    final double srcLeft =
        (viewportRect.left / displayRect.width) * imageSize.width;
    final double srcTop =
        (viewportRect.top / displayRect.height) * imageSize.height;
    final double srcWidth =
        (viewportRect.width / displayRect.width) * imageSize.width;
    final double srcHeight =
        (viewportRect.height / displayRect.height) * imageSize.height;
    final imageSourceRect = Rect.fromLTWH(srcLeft, srcTop, srcWidth, srcHeight);

    canvas.save();
    canvas.drawImageRect(image, imageSourceRect, destinationRect, Paint());

    canvas.saveLayer(destinationRect, Paint());

    for (final path in paths) {
      if (path.points.isEmpty) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      paint.strokeWidth = path.strokeWidth * zoomFactor;

      if (path.mode == DrawingMode.draw) {
        paint.color = Colors.white.withValues(alpha: 0.6);
        paint.blendMode = BlendMode.src;
      } else {
        paint.color = Colors.transparent;
        paint.blendMode = BlendMode.clear;
      }

      final drawPath = Path();
      bool isFirst = true;
      for (final drawingPoint in path.points) {
        final double relativeX = drawingPoint.point.dx - imageSourceRect.left;
        final double relativeY = drawingPoint.point.dy - imageSourceRect.top;
        final double canvasX = (relativeX / imageSourceRect.width) * size.width;
        final double canvasY =
            (relativeY / imageSourceRect.height) * size.height;
        final transformedPoint = Offset(canvasX, canvasY);

        if (isFirst) {
          drawPath.moveTo(transformedPoint.dx, transformedPoint.dy);
          isFirst = false;
        } else {
          drawPath.lineTo(transformedPoint.dx, transformedPoint.dy);
        }
      }
      canvas.drawPath(drawPath, paint);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ZoomViewPainter oldDelegate) {
    return oldDelegate.viewportRect != viewportRect ||
        oldDelegate.paths.length != paths.length ||
        oldDelegate.zoomFactor != zoomFactor ||
        oldDelegate.image != image;
  }
}

class _ReticlePainter extends CustomPainter {
  final double brushSize;
  final double zoomFactor;
  final bool isErasing;

  _ReticlePainter({
    required this.brushSize,
    required this.zoomFactor,
    required this.isErasing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final apparentBrushRadius = (brushSize * zoomFactor) / 2;

    // Outer Glow for visibility on dark images
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = (isErasing ? Colors.redAccent : Colors.cyanAccent).withValues(
        alpha: 0.3,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center, apparentBrushRadius, glowPaint);

    // Main Brush Circle
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      // Updated colors: Cyan for draw, Magenta/Red for erase
      ..color = (isErasing ? Colors.redAccent : Colors.cyanAccent).withValues(
        alpha: 0.9,
      );
    canvas.drawCircle(center, apparentBrushRadius, paint);

    // Crosshair (White with shadow for contrast)
    final crosshairShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;

    final crosshairPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0;

    // Draw Shadow First
    canvas.drawLine(
      Offset(center.dx - 6, center.dy),
      Offset(center.dx + 6, center.dy),
      crosshairShadow,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 6),
      Offset(center.dx, center.dy + 6),
      crosshairShadow,
    );

    // Draw White Line
    canvas.drawLine(
      Offset(center.dx - 5, center.dy),
      Offset(center.dx + 5, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 5),
      Offset(center.dx, center.dy + 5),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) =>
      oldDelegate.brushSize != brushSize ||
      oldDelegate.zoomFactor != zoomFactor ||
      oldDelegate.isErasing != isErasing;
}
