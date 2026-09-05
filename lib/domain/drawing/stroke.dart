// ==================== Drawing Models ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Drawing Models Implementation

// ===== Drawing Mode Enum ===== //

enum DrawingMode { draw, erase }

// ===== Drawing Point Data ===== //

class DrawingPoint {
  final Offset
  point; // Coordinates are relative to the original image dimensions
  DrawingPoint({required this.point});
}

// ===== Drawing Path Data ===== //

class DrawingPath {
  final List<DrawingPoint> points;
  final DrawingMode mode;
  final double strokeWidth; // Stroke width is in logical pixels on the display
  DrawingPath({
    required this.points,
    required this.mode,
    required this.strokeWidth,
  });
}

// ===== Reopenable Mask ===== //

/// A mask kept as the strokes that made it, rather than only as the
/// rendered bitmap.
///
/// The rendered PNG is what the engines consume, but it cannot be drawn on
/// again - reopening the editor with only the bitmap meant starting the
/// whole mask over, which is a lot of careful work to lose to a stray tap.
///
/// Widths here are in **image** units, unlike a live [DrawingPath] whose
/// width is in display units (that is what keeps the brush constant under
/// the finger). The editor's canvas is whatever size the layout gives it,
/// so a width captured against one canvas would be a visibly different
/// brush in another; converting on the way in and out makes the draft
/// independent of the screen it was drawn on.
@immutable
class MaskDraft {
  final List<DrawingPath> paths;
  const MaskDraft(this.paths);

  bool get isEmpty => paths.isEmpty;

  /// Captures live editor paths, whose widths are in display units.
  /// [strokeScale] comes from `maskStrokeScale`.
  factory MaskDraft.fromCanvas(List<DrawingPath> paths, double strokeScale) =>
      MaskDraft([
        for (final path in paths)
          DrawingPath(
            points: path.points,
            mode: path.mode,
            strokeWidth: path.strokeWidth * strokeScale,
          ),
      ]);

  /// The same strokes, sized for a canvas with the given [strokeScale].
  List<DrawingPath> forCanvas(double strokeScale) => [
        for (final path in paths)
          DrawingPath(
            points: path.points,
            mode: path.mode,
            strokeWidth: path.strokeWidth / strokeScale,
          ),
      ];
}
