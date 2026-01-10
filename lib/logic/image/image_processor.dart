// ==================== Image Processor ==================== //

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Creates a mosaic (pixelated) version of an image by downscaling and upscaling
Future<ui.Image> createMosaic(
  ui.Image image,
  int tilesWidth,
  int tilesHeight,
) async {
  // Step 1: Downscale to create mosaic tiles
  final recorder1 = ui.PictureRecorder();
  final canvas1 = Canvas(recorder1);

  canvas1.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, tilesWidth.toDouble(), tilesHeight.toDouble()),
    Paint()..filterQuality = FilterQuality.none,
  );

  final picture1 = recorder1.endRecording();
  final downscaled = await picture1.toImage(tilesWidth, tilesHeight);

  // Step 2: Upscale back to original size (creates blocky/mosaic effect)
  final recorder2 = ui.PictureRecorder();
  final canvas2 = Canvas(recorder2);

  canvas2.drawImageRect(
    downscaled,
    Rect.fromLTWH(0, 0, tilesWidth.toDouble(), tilesHeight.toDouble()),
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Paint()..filterQuality = FilterQuality.none,
  );

  final picture2 = recorder2.endRecording();
  final mosaic = await picture2.toImage(image.width, image.height);

  downscaled.dispose();
  return mosaic;
}

/// Extracts edge pixels and stretches them to fill a region
Future<ui.Image> stretchEdge(
  ui.Image source,
  double targetWidth,
  double targetHeight,
  String direction, // 'left', 'right', 'top', 'bottom'
  double stretchPercent, // How much of the edge to use (e.g., 0.1 = 10%)
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final srcW = source.width.toDouble();
  final srcH = source.height.toDouble();

  // Calculate how many pixels from the edge to use
  final edgeThickness = direction == 'left' || direction == 'right'
      ? (srcW * stretchPercent).clamp(1.0, srcW)
      : (srcH * stretchPercent).clamp(1.0, srcH);

  Rect srcRect;

  switch (direction) {
    case 'left':
      srcRect = Rect.fromLTWH(0, 0, edgeThickness, srcH);
      break;
    case 'right':
      srcRect = Rect.fromLTWH(srcW - edgeThickness, 0, edgeThickness, srcH);
      break;
    case 'top':
      srcRect = Rect.fromLTWH(0, 0, srcW, edgeThickness);
      break;
    case 'bottom':
      srcRect = Rect.fromLTWH(0, srcH - edgeThickness, srcW, edgeThickness);
      break;
    default:
      srcRect = Rect.fromLTWH(0, 0, srcW, srcH);
  }

  // Stretch the edge to fill the target size
  final dstRect = Rect.fromLTWH(0, 0, targetWidth, targetHeight);

  canvas.drawImageRect(
    source,
    srcRect,
    dstRect,
    Paint()..filterQuality = FilterQuality.low,
  );

  final picture = recorder.endRecording();
  return await picture.toImage(targetWidth.toInt(), targetHeight.toInt());
}

/// Generates outpainting data (image and mask) from an image with padding
Future<List<Uint8List>> generateOutpaintData({
  required ui.Image decodedImage,
  required double padLeft,
  required double padRight,
  required double padTop,
  required double padBottom,
}) async {
  final imgW = decodedImage.width.toDouble();
  final imgH = decodedImage.height.toDouble();
  final totalW = imgW + padLeft + padRight;
  final totalH = imgH + padTop + padBottom;

  // Mosaic tile counts
  const int tilesShort = 8;
  const int tilesLong = 16;
  final tilesAverage = ((tilesShort + tilesLong) / 2).round();

  // Stretch parameters
  const double stretchPercent = 0.10;

  // 1. Composite Image with Mosaic Pattern
  final recorderImg = ui.PictureRecorder();
  final canvasImg = Canvas(recorderImg);

  // Fill background with black first
  canvasImg.drawRect(
    Rect.fromLTWH(0, 0, totalW, totalH),
    Paint()..color = Colors.black,
  );

  // Process each padded region with stretched edges
  if (padTop > 0 && padLeft > 0) {
    final stretched = await stretchEdge(decodedImage, padLeft, padTop, 'left', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesAverage, tilesAverage);
    canvasImg.drawImage(mosaic, const Offset(0, 0), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padTop > 0) {
    final stretched = await stretchEdge(decodedImage, imgW, padTop, 'top', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesLong, tilesShort);
    canvasImg.drawImage(mosaic, Offset(padLeft, 0), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padTop > 0 && padRight > 0) {
    final stretched = await stretchEdge(decodedImage, padRight, padTop, 'right', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesAverage, tilesAverage);
    canvasImg.drawImage(mosaic, Offset(padLeft + imgW, 0), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padLeft > 0) {
    final stretched = await stretchEdge(decodedImage, padLeft, imgH, 'left', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesShort, tilesLong);
    canvasImg.drawImage(mosaic, Offset(0, padTop), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padRight > 0) {
    final stretched = await stretchEdge(decodedImage, padRight, imgH, 'right', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesShort, tilesLong);
    canvasImg.drawImage(mosaic, Offset(padLeft + imgW, padTop), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padBottom > 0 && padLeft > 0) {
    final stretched = await stretchEdge(decodedImage, padLeft, padBottom, 'left', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesAverage, tilesAverage);
    canvasImg.drawImage(mosaic, Offset(0, padTop + imgH), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padBottom > 0) {
    final stretched = await stretchEdge(decodedImage, imgW, padBottom, 'bottom', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesLong, tilesShort);
    canvasImg.drawImage(mosaic, Offset(padLeft, padTop + imgH), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  if (padBottom > 0 && padRight > 0) {
    final stretched = await stretchEdge(decodedImage, padRight, padBottom, 'right', stretchPercent);
    final mosaic = await createMosaic(stretched, tilesAverage, tilesAverage);
    canvasImg.drawImage(mosaic, Offset(padLeft + imgW, padTop + imgH), Paint());
    stretched.dispose();
    mosaic.dispose();
  }

  // Draw the original image on top (centered)
  canvasImg.drawImage(decodedImage, Offset(padLeft, padTop), Paint());

  final pictureImg = recorderImg.endRecording();
  final outImg = await pictureImg.toImage(totalW.toInt(), totalH.toInt());
  final outImgBytes = (await outImg.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

  outImg.dispose();

  // 2. Mask
  final recorderMask = ui.PictureRecorder();
  final canvasMask = Canvas(recorderMask);

  canvasMask.drawRect(
    Rect.fromLTWH(0, 0, totalW, totalH),
    Paint()..color = Colors.white,
  );

  const double overlap = 16.0;
  final double leftOverlap = padLeft > 0 ? overlap : 0;
  final double topOverlap = padTop > 0 ? overlap : 0;
  final double rightOverlap = padRight > 0 ? overlap : 0;
  final double bottomOverlap = padBottom > 0 ? overlap : 0;

  final keepRect = Rect.fromLTWH(
    padLeft + leftOverlap,
    padTop + topOverlap,
    math.max(0, imgW - (leftOverlap + rightOverlap)),
    math.max(0, imgH - (topOverlap + bottomOverlap)),
  );

  canvasMask.drawRect(keepRect, Paint()..color = Colors.black);

  final pictureMask = recorderMask.endRecording();
  final outMask = await pictureMask.toImage(totalW.toInt(), totalH.toInt());
  final outMaskBytes = (await outMask.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

  outMask.dispose();

  return [outImgBytes, outMaskBytes];
}
