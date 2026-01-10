// ==================== Mask Painter ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/models/drawing_models.dart';

// Mask Painter Implementation

class MaskPainter extends CustomPainter {
  final List<DrawingPath> paths;
  final Size imageSize;
  final Size containerSize;

  MaskPainter({
    required this.paths,
    required this.imageSize,
    required this.containerSize,
  });

  // ===== Class Methods ===== //

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate how the image fits within the container (BoxFit.contain)
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio = containerSize.width / containerSize.height;

    late final Size displaySize;
    late final Offset displayOffset;

    if (imageAspectRatio > containerAspectRatio) {
      displaySize = Size(
        containerSize.width,
        containerSize.width / imageAspectRatio,
      );
      displayOffset = Offset(
        0,
        (containerSize.height - displaySize.height) / 2,
      );
    } else {
      displaySize = Size(
        containerSize.height * imageAspectRatio,
        containerSize.height,
      );
      displayOffset = Offset((containerSize.width - displaySize.width) / 2, 0);
    }

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final path in paths) {
      if (path.points.isEmpty) continue;

      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = path.strokeWidth
        ..style = PaintingStyle.stroke;

      if (path.mode == DrawingMode.draw) {
        paint.color = Colors.white.withValues(alpha: 0.6);
        paint.blendMode = BlendMode.src;
      } else {
        paint.color = Colors.transparent;
        paint.blendMode = BlendMode.clear;
      }

      final drawPath = Path();
      for (int i = 0; i < path.points.length; i++) {
        final point = path.points[i].point;
        final displayX =
            displayOffset.dx + (point.dx / imageSize.width) * displaySize.width;
        final displayY =
            displayOffset.dy +
            (point.dy / imageSize.height) * displaySize.height;

        if (i == 0) {
          drawPath.moveTo(displayX, displayY);
        } else {
          drawPath.lineTo(displayX, displayY);
        }
      }
      canvas.drawPath(drawPath, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
