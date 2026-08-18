// ==================== Drawing Coordinates ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

// Drawing Coordinates Implementation

/// Converts screen coordinates to image coordinates
Offset convertScreenToImageCoordinates({
  required Offset localPosition,
  required Size containerSize,
  required ui.Image decodedImage,
}) {
  final imageSize = Size(
    decodedImage.width.toDouble(),
    decodedImage.height.toDouble(),
  );
  final imageAspectRatio = imageSize.width / imageSize.height;
  final containerAspectRatio = containerSize.width / containerSize.height;

  late final Size displaySize;
  late final Offset displayOffset;

  if (imageAspectRatio > containerAspectRatio) {
    displaySize = Size(
      containerSize.width,
      containerSize.width / imageAspectRatio,
    );
    displayOffset = Offset(0, (containerSize.height - displaySize.height) / 2);
  } else {
    displaySize = Size(
      containerSize.height * imageAspectRatio,
      containerSize.height,
    );
    displayOffset = Offset((containerSize.width - displaySize.width) / 2, 0);
  }

  final imageRect = Rect.fromLTWH(
    displayOffset.dx,
    displayOffset.dy,
    displaySize.width,
    displaySize.height,
  );

  // Clamp position to image bounds
  Offset clampedPosition = localPosition;
  if (!imageRect.contains(localPosition)) {
    clampedPosition = Offset(
      localPosition.dx.clamp(imageRect.left, imageRect.right),
      localPosition.dy.clamp(imageRect.top, imageRect.bottom),
    );
  }

  // Convert to image coordinates
  final imageX =
      (clampedPosition.dx - displayOffset.dx) /
      displaySize.width *
      imageSize.width;
  final imageY =
      (clampedPosition.dy - displayOffset.dy) /
      displaySize.height *
      imageSize.height;

  return Offset(imageX, imageY);
}
