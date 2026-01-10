// ==================== Drawing Models ==================== //

import 'package:flutter/material.dart';

// ========== Drawing Mode Enum ========== //
enum DrawingMode { draw, erase }

// ========== Drawing Point Data ========== //
class DrawingPoint {
  final Offset point; // Coordinates are relative to the original image dimensions
  DrawingPoint({required this.point});
}

// ========== Drawing Path Data ========== //
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
