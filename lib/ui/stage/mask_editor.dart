// ==================== Mask Editor ==================== //
//
// Paint the region an inpaint run should regenerate.
//
// Three things here are load-bearing and were learned the hard way in the
// previous build - they are preserved deliberately:
//
//  1. **Points are stored in image coordinates, not screen coordinates.**
//     The canvas is letterboxed (BoxFit.contain), so screen space depends on
//     the container's aspect ratio. Storing screen points would make every
//     stroke wrong the moment the layout changed, and would make the
//     generated mask wrong at any resolution but the one it was drawn at.
//     `convertScreenToImageCoordinates` does the conversion, including
//     clamping to the image rect so a drag off the edge doesn't paint
//     outside the picture.
//
//  2. **Stroke width stays in display units** and is scaled to image units
//     only when the mask is rasterised (`generateDrawingMask` multiplies by
//     the average scale factor). That keeps the brush a constant size under
//     the finger regardless of image resolution, which is what a person
//     expects from a brush.
//
//  3. **Erase needs a `saveLayer`.** `BlendMode.clear` only clears within
//     the current layer; without the explicit layer it would punch a hole
//     straight through the photograph underneath.
//
// The mask is black/white: white = regenerate, black = keep. Both engines
// already consume exactly that (`ForgeEngine` sends it alongside
// `mask_blur`/`inpainting_fill`; `ComfyEngine` folds it into the upload's
// alpha channel), so nothing below the UI changed for this screen.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:sd_companion/data/imaging/mask_generator.dart';
import 'package:sd_companion/domain/drawing/canvas_geometry.dart';
import 'package:sd_companion/domain/drawing/stroke.dart';
import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_gestures.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// What the editor hands back. Null instead of a [MaskResult] means the
/// user backed out, which must leave whatever mask already existed alone.
class MaskResult {
  /// The rendered mask PNG, or null when the user cleared the canvas -
  /// "no mask" and "a mask covering nothing" behave differently downstream,
  /// and the former is what clearing means.
  final Uint8List? bytes;

  /// The strokes behind [bytes], so this same mask can be reopened and
  /// carried on with rather than redrawn.
  final MaskDraft draft;

  const MaskResult({required this.bytes, required this.draft});
}

class MaskEditor extends StatefulWidget {
  final ui.Image image;
  final ImageProvider display;

  /// Strokes to open with, from a mask painted earlier in this session.
  final MaskDraft? initial;

  const MaskEditor({
    super.key,
    required this.image,
    required this.display,
    this.initial,
  });

  @override
  State<MaskEditor> createState() => _MaskEditorState();
}

class _MaskEditorState extends State<MaskEditor> {
  final List<DrawingPath> _paths = [];
  final List<List<DrawingPath>> _undo = [];
  List<DrawingPoint> _current = [];

  DrawingMode _mode = DrawingMode.draw;
  double _brush = 40;
  bool _busy = false;

  /// The paint area's size. `generateDrawingMask` needs it to convert brush
  /// width into image units, and so does restoring a draft - so it is taken
  /// from the layout rather than only learned once a stroke is drawn.
  Size? _canvasSize;

  /// Whether [MaskEditor.initial] has been laid into `_paths` yet. It needs
  /// the canvas size to size its brushes, which is only known at layout.
  bool _restored = false;

  /// Where the finger is, for the loupe. Null when not drawing.
  Offset? _fingerAt;

  Size get _imageSize =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  List<DrawingPath> get _allPaths => [
        ..._paths,
        if (_current.isNotEmpty)
          DrawingPath(points: _current, mode: _mode, strokeWidth: _brush),
      ];

  // ===== Drawing ===== //

  void _panStart(DragStartDetails d, Size size) {
    setState(() {
      // Snapshot before the stroke, so undo steps back over whole strokes
      // rather than individual points.
      _undo.add(List<DrawingPath>.from(_paths));
      _current = [];
    });
    _addPoint(d.localPosition, size);
  }

  void _panUpdate(DragUpdateDetails d, Size size) {
    _addPoint(d.localPosition, size);
  }

  void _panEnd(DragEndDetails d) {
    setState(() {
      if (_current.isNotEmpty) {
        _paths.add(DrawingPath(
          points: List.of(_current),
          mode: _mode,
          strokeWidth: _brush,
        ));
      } else if (_undo.isNotEmpty) {
        // Nothing was drawn, so the snapshot taken on start is just noise.
        _undo.removeLast();
      }
      _current = [];
      _fingerAt = null;
    });
  }

  void _addPoint(Offset local, Size size) {
    _canvasSize = size;
    final imagePoint = convertScreenToImageCoordinates(
      localPosition: local,
      containerSize: size,
      decodedImage: widget.image,
    );
    setState(() {
      _fingerAt = local;
      _current.add(DrawingPoint(point: imagePoint));
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _paths
        ..clear()
        ..addAll(_undo.removeLast());
    });
  }

  void _clear() {
    if (_paths.isEmpty) return;
    setState(() {
      _undo.add(List<DrawingPath>.from(_paths));
      _paths.clear();
    });
  }

  double get _strokeScale => maskStrokeScale(
        imageSize: _imageSize,
        containerSize: _canvasSize ?? _imageSize,
      );

  Future<void> _done() async {
    final size = _canvasSize;
    if (_paths.isEmpty || size == null) {
      // An editor opened on an existing mask and left empty is a deliberate
      // clear, not a cancel - the strokes were there and the user removed
      // them. Opened empty and left empty, there is nothing to say.
      Navigator.of(context).pop<MaskResult?>(
        widget.initial != null
            ? const MaskResult(bytes: null, draft: MaskDraft([]))
            : null,
      );
      return;
    }
    setState(() => _busy = true);
    final scale = _strokeScale;
    final mask = await generateDrawingMask(
      decodedImage: widget.image,
      paths: _paths,
      canvasRenderedSize: size,
    );
    if (!mounted) return;
    Navigator.of(context).pop<MaskResult?>(
      MaskResult(bytes: mask, draft: MaskDraft.fromCanvas(_paths, scale)),
    );
  }

  // ===== Build ===== //

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
                      padding:
                          const EdgeInsets.symmetric(horizontal: Space.gutter),
                      child: _canvas(p),
                    ),
                  ),
                  _toolbar(p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, DeskPalette p) => DeskPageHeader(
        title: 'Mask',
        onClose: () => Navigator.of(context).pop<MaskResult?>(null),
        action: DeskButton(
          label: _busy ? 'Working…' : 'Done',
          icon: Icons.check_rounded,
          kind: DeskButtonKind.primary,
          onPressed: _busy ? null : _done,
        ),
      );

  Widget _canvas(DeskPalette p) => Center(
        child: AspectRatio(
          // Hugging the image's own aspect ratio means the frame wraps the
          // picture instead of leaving tall empty bands above and below it,
          // and it makes the paint area equal to the image area - so there
          // is almost no letterbox for a stroke to be clamped against.
          aspectRatio: _imageSize.width / _imageSize.height,
          child: Container(
            decoration: BoxDecoration(
              color: p.paper,
              border: Border.all(color: p.ink, width: Stroke.frame),
              boxShadow: Elevation.sheet.shadows(p.ink),
            ),
            child: _paintArea(p),
          ),
        ),
      );

  Widget _paintArea(DeskPalette p) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // Layout is the first moment the brush scale is known, and the
          // painter below reads `_paths` later in this same build - so the
          // restore happens here, with a plain assignment rather than
          // setState (which is illegal during layout and unnecessary).
          _canvasSize = size;
          final initial = widget.initial;
          if (!_restored && initial != null && !initial.isEmpty) {
            _restored = true;
            _paths.addAll(initial.forCanvas(_strokeScale));
            // The toolbar was built before layout ran, so Undo and Clear
            // are still sitting there disabled over a canvas that now has
            // strokes on it. One more frame and they know about them.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return RawGestureDetector(
            gestures: {
              AlwaysWinPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  AlwaysWinPanGestureRecognizer>(
                AlwaysWinPanGestureRecognizer.new,
                (instance) {
                  instance.onStart = (d) => _panStart(d, size);
                  instance.onUpdate = (d) => _panUpdate(d, size);
                  instance.onEnd = _panEnd;
                },
              ),
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image(image: widget.display, fit: BoxFit.contain),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: MaskStrokePainter(
                      paths: _allPaths,
                      imageSize: _imageSize,
                      containerSize: size,
                      colour: p.clay,
                    ),
                  ),
                ),
                // A finger covers exactly the pixels being painted, so
                // without a loupe fine masking is guesswork. It sits in
                // whichever top corner the finger is furthest from.
                if (_fingerAt != null)
                  Positioned(
                    top: Space.sm,
                    left: _fingerAt!.dx > size.width * 0.5 ? Space.sm : null,
                    right: _fingerAt!.dx > size.width * 0.5 ? null : Space.sm,
                    child: _Loupe(
                      display: widget.display,
                      imageSize: _imageSize,
                      containerSize: size,
                      at: _fingerAt!,
                      paths: _allPaths,
                      brush: _brush,
                      palette: p,
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _toolbar(DeskPalette p) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.gutter, Space.md, Space.gutter, Space.md),
        child: Column(
          children: [
            DeskRuler(
              label: 'Brush',
              value: _brush,
              min: 4,
              max: 140,
              format: (v) => v.round().toString(),
              onChanged: (v) => setState(() => _brush = v),
            ),
            const SizedBox(height: Space.md),
            // Mode is the mode switch; undo/clear are actions. Splitting
            // them across two rows stops four controls fighting for width
            // and lets the tab strip sit flush on the row it labels, the
            // way DESIGN.md 7.12 intends folder tabs to work.
            DeskTabStrip<DrawingMode>(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
              tabs: const [
                DeskTab(
                    value: DrawingMode.draw,
                    label: 'Paint',
                    icon: Icons.brush_rounded),
                DeskTab(
                    value: DrawingMode.erase,
                    label: 'Erase',
                    icon: Icons.auto_fix_normal_rounded),
              ],
            ),
            Container(height: Stroke.standard, color: p.ink),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: DeskButton(
                    label: 'Undo',
                    icon: Icons.undo_rounded,
                    expand: true,
                    onPressed: _undo.isEmpty ? null : _undoLast,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: DeskButton(
                    label: 'Clear',
                    icon: Icons.layers_clear_rounded,
                    kind: DeskButtonKind.destructive,
                    expand: true,
                    onPressed: _paths.isEmpty ? null : _clear,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// Draws mask strokes over the photograph in clay, per DESIGN.md 7.2.
///
/// Shared with the loupe, which renders the same scene magnified - drawing
/// it twice from one painter is what keeps the preview honest.
class MaskStrokePainter extends CustomPainter {
  final List<DrawingPath> paths;
  final Size imageSize;
  final Size containerSize;
  final Color colour;

  const MaskStrokePainter({
    required this.paths,
    required this.imageSize,
    required this.containerSize,
    required this.colour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        displayRectFor(imageSize: imageSize, containerSize: containerSize);

    // Erase uses BlendMode.clear, which only affects the current layer -
    // without this explicit layer it would punch through the photograph.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final path in paths) {
      if (path.points.isEmpty) continue;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = path.strokeWidth
        ..style = PaintingStyle.stroke;

      if (path.mode == DrawingMode.draw) {
        paint.color = colour.withValues(alpha: 0.45);
        paint.blendMode = BlendMode.src;
      } else {
        paint.color = const Color(0x00000000);
        paint.blendMode = BlendMode.clear;
      }

      final drawn = Path();
      for (var i = 0; i < path.points.length; i++) {
        final pt = path.points[i].point;
        final x = rect.left + (pt.dx / imageSize.width) * rect.width;
        final y = rect.top + (pt.dy / imageSize.height) * rect.height;
        if (i == 0) {
          drawn.moveTo(x, y);
        } else {
          drawn.lineTo(x, y);
        }
      }
      canvas.drawPath(drawn, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MaskStrokePainter old) => true;
}

/// Identifies the loupe's magnified scene, so a widget test can measure the
/// size it was actually laid out at - the difference between working and
/// blank is a layout constraint, not anything visible in the widget tree.
const Key loupeSceneKey = Key('loupe-scene');

/// A magnified window on the area under the finger.
class _Loupe extends StatelessWidget {
  final ImageProvider display;
  final Size imageSize;
  final Size containerSize;
  final Offset at;
  final List<DrawingPath> paths;
  final double brush;
  final DeskPalette palette;

  static const double _size = 120;

  const _Loupe({
    required this.display,
    required this.imageSize,
    required this.containerSize,
    required this.at,
    required this.paths,
    required this.brush,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the brush under ~60% of the window so there is always context
    // around it; a brush wider than the loupe makes the loupe useless.
    // Keep the brush under ~60% of the window so there is always context
    // around it, but never magnify so little that the loupe is pointless.
    final fitting = brush > 0 ? (_size * 0.6) / brush : 3.0;
    final capped = fitting < 3.0 ? fitting : 3.0;
    final zoom = capped > 1.4 ? capped : 1.4;

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: palette.paperEdge,
        border: Border.all(color: palette.ink, width: Stroke.frame),
        boxShadow: Elevation.sheet.shadows(palette.ink),
      ),
      child: ClipRect(
        child: Stack(
          children: [
            // `Positioned(left/top)` rather than `Positioned.fill`: fill
            // passes *tight* constraints, which squashed the scene to the
            // loupe's own 120px and then translated it off-view by canvas
            // coordinates - leaving nothing but the backing colour. Loose
            // constraints let the SizedBox take the canvas's real size.
            Positioned(
              left: 0,
              top: 0,
              child: Transform(
                alignment: Alignment.topLeft,
                // Scale about the origin, then slide the point under the
                // finger to the centre of the window.
                transform: Matrix4.identity()
                  ..translateByDouble(
                      _size / 2 - at.dx * zoom, _size / 2 - at.dy * zoom, 0, 1)
                  ..scaleByDouble(zoom, zoom, 1, 1),
                child: SizedBox(
                  key: loupeSceneKey,
                  width: containerSize.width,
                  height: containerSize.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image(image: display, fit: BoxFit.contain),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: MaskStrokePainter(
                            paths: paths,
                            imageSize: imageSize,
                            containerSize: containerSize,
                            colour: palette.clay,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Ring showing the brush's true footprint at this zoom.
            Center(
              child: Container(
                width: brush * zoom,
                height: brush * zoom,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.ink, width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
