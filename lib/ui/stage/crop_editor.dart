// ==================== Crop Editor ==================== //
//
// Trim an image down to a region, optionally locked to an aspect ratio.
//
// The crop rect is kept in **image pixel** coordinates, not screen ones, for
// the same reason mask strokes are: the picture is letterboxed inside its
// frame, so screen space depends on the container's shape. Keeping pixels
// means the rect survives a rotation, and the numbers shown to the user are
// the real output size rather than something scaled by the current layout.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:sd_companion/data/imaging/image_processor.dart';
import 'package:sd_companion/domain/drawing/canvas_geometry.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_gestures.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// A named aspect lock. Null ratio means free-form.
class CropAspect {
  final String label;
  final double? ratio;
  const CropAspect(this.label, this.ratio);

  static const options = [
    CropAspect('Free', null),
    CropAspect('1:1', 1),
    CropAspect('4:3', 4 / 3),
    CropAspect('3:4', 3 / 4),
    CropAspect('16:9', 16 / 9),
    CropAspect('9:16', 9 / 16),
    // Tall phones are nearer 9:19.5-9:21 than 9:16, so a wallpaper cropped
    // to 9:16 still gets trimmed by the launcher.
    CropAspect('9:21', 9 / 21),
  ];

  /// The ratio of the screen this is running on, so "fits my phone exactly"
  /// needs no guessing at which of the tall ratios a given handset uses.
  static CropAspect phone(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ratio = size.height <= 0 ? 9 / 20 : size.width / size.height;
    return CropAspect('Phone', ratio);
  }
}

class CropEditor extends StatefulWidget {
  final ui.Image image;
  final Uint8List bytes;
  final ImageProvider display;

  const CropEditor({
    super.key,
    required this.image,
    required this.bytes,
    required this.display,
  });

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late Rect _crop; // in image pixels
  CropAspect _aspect = CropAspect.options.first;
  bool _busy = false;

  double get _imgW => widget.image.width.toDouble();
  double get _imgH => widget.image.height.toDouble();

  @override
  void initState() {
    super.initState();
    _crop = Rect.fromLTWH(0, 0, _imgW, _imgH);
  }

  void _applyAspect(CropAspect aspect) {
    setState(() {
      _aspect = aspect;
      final ratio = aspect.ratio;
      if (ratio == null) return;
      // Fit the largest rect of this ratio inside the image, centred - a
      // predictable starting point beats trying to preserve the old rect.
      var w = _imgW;
      var h = w / ratio;
      if (h > _imgH) {
        h = _imgH;
        w = h * ratio;
      }
      _crop = Rect.fromLTWH((_imgW - w) / 2, (_imgH - h) / 2, w, h);
    });
  }

  /// Moves one edge, keeping the rect inside the image and above a minimum
  /// size. With an aspect lock, the opposite dimension follows.
  void _dragEdge(_Edge edge, Offset deltaImagePx) {
    setState(() {
      var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
      const minSize = 32.0;

      switch (edge) {
        case _Edge.left:
          l = (l + deltaImagePx.dx).clamp(0.0, r - minSize);
        case _Edge.right:
          r = (r + deltaImagePx.dx).clamp(l + minSize, _imgW);
        case _Edge.top:
          t = (t + deltaImagePx.dy).clamp(0.0, b - minSize);
        case _Edge.bottom:
          b = (b + deltaImagePx.dy).clamp(t + minSize, _imgH);
      }

      var rect = Rect.fromLTRB(l, t, r, b);
      final ratio = _aspect.ratio;
      if (ratio != null) {
        // Anchor the edge being dragged and derive the other axis from it.
        if (edge == _Edge.left || edge == _Edge.right) {
          final h = (rect.width / ratio).clamp(minSize, _imgH);
          final cy = rect.center.dy.clamp(h / 2, _imgH - h / 2);
          rect = Rect.fromCenter(
              center: Offset(rect.center.dx, cy), width: rect.width, height: h);
        } else {
          final w = (rect.height * ratio).clamp(minSize, _imgW);
          final cx = rect.center.dx.clamp(w / 2, _imgW - w / 2);
          rect = Rect.fromCenter(
              center: Offset(cx, rect.center.dy), width: w, height: rect.height);
        }
      }
      _crop = rect;
    });
  }

  void _pan(Offset deltaImagePx) {
    setState(() {
      final dx = deltaImagePx.dx.clamp(-_crop.left, _imgW - _crop.right);
      final dy = deltaImagePx.dy.clamp(-_crop.top, _imgH - _crop.bottom);
      _crop = _crop.shift(Offset(dx, dy));
    });
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final cropped = await cropImageBytes(
      bytes: widget.bytes,
      x: _crop.left.round(),
      y: _crop.top.round(),
      width: _crop.width.round(),
      height: _crop.height.round(),
    );
    if (!mounted) return;
    if (cropped == null) {
      setState(() => _busy = false);
      Navigator.of(context).pop<Uint8List?>(null);
      return;
    }
    Navigator.of(context).pop<Uint8List?>(cropped);
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
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  DeskPageHeader(
                    title: 'Crop',
                    onClose: () => Navigator.of(context).pop<Uint8List?>(null),
                    action: DeskButton(
                      label: _busy ? 'Working…' : 'Done',
                      icon: Icons.check_rounded,
                      kind: DeskButtonKind.primary,
                      onPressed: _busy ? null : _done,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _imgW / _imgH,
                          child: Container(
                            decoration: BoxDecoration(
                              color: p.paper,
                              border:
                                  Border.all(color: p.ink, width: Stroke.frame),
                              boxShadow: Elevation.sheet.shadows(p.ink),
                            ),
                            child: _canvas(p),
                          ),
                        ),
                      ),
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

  Widget _canvas(DeskPalette p) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final view =
              displayRectFor(imageSize: Size(_imgW, _imgH), containerSize: size);
          final scale = view.width / _imgW;

          Rect toScreen(Rect r) => Rect.fromLTWH(
                view.left + r.left * scale,
                view.top + r.top * scale,
                r.width * scale,
                r.height * scale,
              );
          final box = toScreen(_crop);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image(image: widget.display, fit: BoxFit.contain),
              ),
              // Everything outside the crop is dimmed, so the kept region is
              // read as the subject rather than as a floating rectangle.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CropShadePainter(box: box, ink: p.ink),
                  ),
                ),
              ),
              Positioned(
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
                child: RawGestureDetector(
                  gestures: {
                    AlwaysWinPanGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            AlwaysWinPanGestureRecognizer>(
                      AlwaysWinPanGestureRecognizer.new,
                      (instance) {
                        instance.onUpdate =
                            (d) => _pan(d.delta / scale);
                      },
                    ),
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: p.clay, width: Stroke.live),
                    ),
                  ),
                ),
              ),
              for (final edge in _Edge.values)
                _edgeHandle(p, edge, box, scale),
            ],
          );
        },
      );

  Widget _edgeHandle(DeskPalette p, _Edge edge, Rect box, double scale) {
    const grab = 30.0;
    final horizontal = edge == _Edge.top || edge == _Edge.bottom;
    return Positioned(
      left: horizontal ? box.left : box.left + (edge == _Edge.left ? 0 : box.width) - grab / 2,
      top: horizontal ? box.top + (edge == _Edge.top ? 0 : box.height) - grab / 2 : box.top,
      width: horizontal ? box.width : grab,
      height: horizontal ? grab : box.height,
      child: RawGestureDetector(
        gestures: {
          AlwaysWinPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<AlwaysWinPanGestureRecognizer>(
            AlwaysWinPanGestureRecognizer.new,
            (instance) {
              instance.onUpdate = (d) => _dragEdge(edge, d.delta / scale);
            },
          ),
        },
        child: Center(
          child: Container(
            width: horizontal ? 40 : Stroke.frame + 3,
            height: horizontal ? Stroke.frame + 3 : 40,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in [
                    ...CropAspect.options,
                    CropAspect.phone(context),
                  ]) ...[
                    _AspectChip(
                      label: option.label,
                      selected: option.label == _aspect.label,
                      onTap: () => _applyAspect(option),
                    ),
                    const SizedBox(width: Space.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OUTPUT',
                          style: Type.micro.copyWith(color: p.inkFaint)),
                      const SizedBox(height: 2),
                      Text(
                        '${_crop.width.round()} × ${_crop.height.round()}',
                        style: Type.readout.copyWith(color: p.ink),
                      ),
                    ],
                  ),
                ),
                DeskButton(
                  label: 'Reset',
                  icon: Icons.restart_alt_rounded,
                  onPressed: () => setState(() {
                    _aspect = CropAspect.options.first;
                    _crop = Rect.fromLTWH(0, 0, _imgW, _imgH);
                  }),
                ),
              ],
            ),
          ],
        ),
      );
}

enum _Edge { left, right, top, bottom }

class _AspectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AspectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: Space.touch,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: selected ? p.clay : p.paper,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(color: p.ink, width: Stroke.standard),
          boxShadow: Elevation.rest.shadows(p.ink),
        ),
        child: Text(
          label,
          style: Type.label.copyWith(color: selected ? p.paper : p.ink),
        ),
      ),
    );
  }
}

/// Dims everything outside the crop, drawn as four flat rectangles - no
/// blur, no gradient, in keeping with the rest of the surface work.
class _CropShadePainter extends CustomPainter {
  final Rect box;
  final Color ink;

  const _CropShadePainter({required this.box, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink.withValues(alpha: 0.55);
    final full = Offset.zero & size;
    canvas.drawRect(
        Rect.fromLTRB(full.left, full.top, full.right, math.max(0, box.top)), paint);
    canvas.drawRect(
        Rect.fromLTRB(full.left, box.bottom, full.right, full.bottom), paint);
    canvas.drawRect(
        Rect.fromLTRB(full.left, box.top, math.max(0, box.left), box.bottom), paint);
    canvas.drawRect(
        Rect.fromLTRB(box.right, box.top, full.right, box.bottom), paint);
  }

  @override
  bool shouldRepaint(_CropShadePainter old) => old.box != box || old.ink != ink;
}
