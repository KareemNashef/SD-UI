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

/// How many image pixels one display pixel of brush width covers.
///
/// A stroke's width is stored in display units - that is what keeps the
/// brush a constant size under the finger - so it has to be scaled by this
/// to be painted into the mask, and divided by it to be restored into a
/// canvas of a different size.
double maskStrokeScale({
  required Size imageSize,
  required Size containerSize,
}) {
  final display = displayRectFor(
    imageSize: imageSize,
    containerSize: containerSize,
  );
  if (display.width <= 0 || display.height <= 0) return 1;
  return ((imageSize.width / display.width) +
          (imageSize.height / display.height)) /
      2;
}

/// Where a [BoxFit.contain] image actually lands inside its container.
///
/// This letterbox calculation was duplicated in the painter, the mask
/// generator and the coordinate converter, which is precisely the kind of
/// triplication that lets a mask drift out of alignment with what was drawn
/// when only two of the three get fixed. One definition, three callers.
Rect displayRectFor({
  required Size imageSize,
  required Size containerSize,
}) {
  final imageAspect = imageSize.width / imageSize.height;
  final containerAspect = containerSize.width / containerSize.height;

  if (imageAspect > containerAspect) {
    final height = containerSize.width / imageAspect;
    return Rect.fromLTWH(
      0,
      (containerSize.height - height) / 2,
      containerSize.width,
      height,
    );
  }
  final width = containerSize.height * imageAspect;
  return Rect.fromLTWH(
    (containerSize.width - width) / 2,
    0,
    width,
    containerSize.height,
  );
}
