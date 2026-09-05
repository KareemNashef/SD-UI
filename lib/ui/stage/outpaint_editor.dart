// ==================== Outpaint Editor ==================== //
//
// Extend the canvas outward and let the model fill the new space.
//
// The heavy lifting is already done by `generateOutpaintData`, ported intact
// from the previous build. It returns two images: the source composited onto
// the enlarged canvas with each padded edge filled by a stretched, mosaicked
// copy of the adjacent strip, and a mask marking that new area for
// regeneration. Seeding the padding with plausible colour rather than flat
// black matters - a sampler handed pure black tends to paint a dark vignette
// into the result instead of continuing the picture.
//
// The mask deliberately overlaps the original by 16px on every padded edge,
// so the model re-paints a thin band of known content and the seam blends
// instead of butting up against an exact rectangle.
//
// Outpainting is inpainting with a bigger canvas, so the result is written
// straight into the session as source image + mask. Order matters:
// `setSourceImage` clears any existing mask by design, so the mask is set
// second.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:sd_companion/data/imaging/image_processor.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_gestures.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// What the editor hands back: the enlarged image and its mask.
class OutpaintResult {
  final Uint8List image;
  final Uint8List mask;
  const OutpaintResult({required this.image, required this.mask});
}

class OutpaintEditor extends StatefulWidget {
  final ui.Image image;
  final ImageProvider display;

  const OutpaintEditor({super.key, required this.image, required this.display});

  @override
  State<OutpaintEditor> createState() => _OutpaintEditorState();
}

class _OutpaintEditorState extends State<OutpaintEditor> {
  double _padLeft = 0;
  double _padRight = 0;
  double _padTop = 0;
  double _padBottom = 0;
  bool _busy = false;

  double get _imgW => widget.image.width.toDouble();
  double get _imgH => widget.image.height.toDouble();
  double get _totalW => _imgW + _padLeft + _padRight;
  double get _totalH => _imgH + _padTop + _padBottom;
  bool get _hasPadding =>
      _padLeft > 0 || _padRight > 0 || _padTop > 0 || _padBottom > 0;

  void _reset() => setState(() {
        _padLeft = 0;
        _padRight = 0;
        _padTop = 0;
        _padBottom = 0;
      });

  Future<void> _done() async {
    if (!_hasPadding) {
      Navigator.of(context).pop<OutpaintResult?>(null);
      return;
    }
    setState(() => _busy = true);
    final data = await generateOutpaintData(
      decodedImage: widget.image,
      padLeft: _padLeft,
      padRight: _padRight,
      padTop: _padTop,
      padBottom: _padBottom,
    );
    if (!mounted) return;
    if (data.length < 2) {
      setState(() => _busy = false);
      Navigator.of(context).pop<OutpaintResult?>(null);
      return;
    }
    Navigator.of(context)
        .pop<OutpaintResult?>(OutpaintResult(image: data[0], mask: data[1]));
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Desk(
      mode: brightness == Brightness.dark ? DeskMode.night : DeskMode.day,
      child: Builder(
        builder: (context) {
          final p = DeskTheme.of(context);
          return Scaffold(
            backgroundColor: Colors.transparent,
            // top:false - DeskPageHeader paints its own paper behind the
            // status bar and adds that inset itself.
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  _header(context, p),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xxl),
                      child: _canvas(p),
                    ),
                  ),
                  _footer(p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, DeskPalette p) => DeskPageHeader(
        title: 'Extend canvas',
        onClose: () => Navigator.of(context).pop<OutpaintResult?>(null),
        action: DeskButton(
          label: _busy ? 'Working…' : 'Done',
          icon: Icons.check_rounded,
          kind: DeskButtonKind.primary,
          onPressed: _busy || !_hasPadding ? null : _done,
        ),
      );

  Widget _canvas(DeskPalette p) => LayoutBuilder(
        builder: (context, constraints) {
          // Leave room to grow: the view stays zoomed out to at least twice
          // the original so there is visible space to drag a handle into,
          // rather than the picture filling the frame with nowhere to go.
          final virtualW = math.max(_totalW, _imgW * 2.0);
          final virtualH = math.max(_totalH, _imgH * 2.0);
          final scale = math.min(
            constraints.maxWidth / virtualW,
            constraints.maxHeight / virtualH,
          );

          return Center(
            child: SizedBox(
              width: _totalW * scale,
              height: _totalH * scale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The area being added reads as blank mat board waiting
                  // to be filled: paperEdge with the desk's own diagonal
                  // grain over it, so it is visibly *empty canvas* rather
                  // than a grey rectangle that might be part of the picture.
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.paperEdge,
                        border: Border.all(color: p.ink, width: Stroke.frame),
                        boxShadow: Elevation.sheet.shadows(p.ink),
                      ),
                      child: CustomPaint(painter: _HatchPainter(p.ink)),
                    ),
                  ),
                  // The original sits on top, square-cornered like any other
                  // photograph on this desk.
                  Positioned(
                    left: _padLeft * scale,
                    top: _padTop * scale,
                    width: _imgW * scale,
                    height: _imgH * scale,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: Elevation.rest.shadows(p.ink),
                      ),
                      child: Image(image: widget.display, fit: BoxFit.fill),
                    ),
                  ),
                  _handle(
                    p,
                    top: -14,
                    left: 0,
                    right: 0,
                    height: 28,
                    horizontal: true,
                    onDrag: (d) => setState(
                        () => _padTop = math.max(0, _padTop - d.dy / scale)),
                  ),
                  _handle(
                    p,
                    bottom: -14,
                    left: 0,
                    right: 0,
                    height: 28,
                    horizontal: true,
                    onDrag: (d) => setState(
                        () => _padBottom = math.max(0, _padBottom + d.dy / scale)),
                  ),
                  _handle(
                    p,
                    left: -14,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    horizontal: false,
                    onDrag: (d) => setState(
                        () => _padLeft = math.max(0, _padLeft - d.dx / scale)),
                  ),
                  _handle(
                    p,
                    right: -14,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    horizontal: false,
                    onDrag: (d) => setState(
                        () => _padRight = math.max(0, _padRight + d.dx / scale)),
                  ),
                ],
              ),
            ),
          );
        },
      );

  /// An edge grip. Uses [AlwaysWinPanGestureRecognizer] so the drag is not
  /// lost to an ancestor deciding it might be a scroll first.
  Widget _handle(
    DeskPalette p, {
    double? top,
    double? bottom,
    double? left,
    double? right,
    double? width,
    double? height,
    required bool horizontal,
    required void Function(Offset delta) onDrag,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      width: width,
      height: height,
      child: RawGestureDetector(
        gestures: {
          AlwaysWinPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<AlwaysWinPanGestureRecognizer>(
            AlwaysWinPanGestureRecognizer.new,
            (instance) => instance..onUpdate = (d) => onDrag(d.delta),
          ),
        },
        child: Center(
          child: Container(
            width: horizontal ? 44 : Stroke.frame + 3,
            height: horizontal ? Stroke.frame + 3 : 44,
            decoration: BoxDecoration(
              color: p.clay,
              borderRadius: BorderRadius.circular(Corner.photo),
              boxShadow: Elevation.rest.shadows(p.ink),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(DeskPalette p) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.gutter, Space.md, Space.gutter, Space.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CANVAS', style: Type.micro.copyWith(color: p.inkFaint)),
                  const SizedBox(height: 2),
                  Text(
                    '${_totalW.round()} × ${_totalH.round()}',
                    style: Type.readout.copyWith(color: p.ink),
                  ),
                ],
              ),
            ),
            DeskButton(
              label: 'Reset',
              icon: Icons.restart_alt_rounded,
              onPressed: _hasPadding ? _reset : null,
            ),
          ],
        ),
      );
}


/// Faint diagonal hatching for the not-yet-filled canvas, in the same
/// language as the desk's grain - flat lines, no gradient, no blur.
class _HatchPainter extends CustomPainter {
  final Color ink;
  const _HatchPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const spacing = 10.0;
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.ink != ink;
}
