// ==================== Desk Surfaces ==================== //
//
// The things that are *objects on a desk*: the desk itself, plain paper, the
// mounted source sheet, and a print. Controls live in desk_controls.dart.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// The app background: a warm surface with a diagonal grain.
///
/// The grain is painted once inside a [RepaintBoundary] and never animates.
/// It is texture, never structure - nothing is ever positioned relative to it.
class Desk extends StatelessWidget {
  final Widget child;
  final DeskMode mode;

  const Desk({super.key, required this.child, this.mode = DeskMode.day});

  @override
  Widget build(BuildContext context) {
    final palette = DeskPalette.of(mode);
    return DeskTheme(
      palette: palette,
      mode: mode,
      child: ColoredBox(
        color: palette.desk,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: _GrainPainter(palette.deskGrain)),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final Color color;
  const _GrainPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 96 degrees off horizontal, 2px on / 7px off. Drawn as long diagonals
    // across a canvas wide enough that the slant never shows a seam.
    const spacing = 9.0;
    final slant = math.tan((96 - 90) * math.pi / 180) * size.height;
    for (var x = -slant.abs() - spacing; x < size.width + spacing; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + slant, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.color != color;
}

/// A plain paper object. Square corners by default, because paper is content.
class Paper extends StatelessWidget {
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double borderWidth;
  final Color? borderColor;
  final Color? fill;
  final Elevation elevation;
  final double? width;
  final double? height;

  const Paper({
    super.key,
    this.child,
    this.padding,
    this.radius = Corner.paper,
    this.borderWidth = 0,
    this.borderColor,
    this.fill,
    this.elevation = Elevation.rest,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? p.paper,
        borderRadius: BorderRadius.circular(radius),
        border: borderWidth > 0
            ? Border.all(color: borderColor ?? p.ink, width: borderWidth)
            : null,
        boxShadow: elevation.shadows(p.ink),
      ),
      child: child,
    );
  }
}

/// The mounted source sheet - the single most important object on screen.
///
/// Paper with a 3px ink frame, the image inset by 12 so the paper reads as a
/// mat board around a photograph, and four pulsing outpaint handles at the
/// corners. Those handles are the only permanently animating element in the
/// app; they exist to teach one gesture that is otherwise undiscoverable.
class MountedSheet extends StatefulWidget {
  final Widget image;
  final String caption;
  final bool showHandles;
  final VoidCallback? onTap;

  const MountedSheet({
    super.key,
    required this.image,
    this.caption = 'SOURCE',
    this.showHandles = true,
    this.onTap,
  });

  @override
  State<MountedSheet> createState() => _MountedSheetState();
}

class _MountedSheetState extends State<MountedSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.pulse,
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final still = reduceMotion(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: p.paper,
              border: Border.all(color: p.ink, width: Stroke.frame),
              boxShadow: Elevation.sheet.shadows(p.ink),
            ),
            padding: const EdgeInsets.all(Space.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: p.paperEdge, child: widget.image),
                Positioned(
                  left: Space.sm,
                  bottom: Space.sm - 1,
                  child: Text(
                    widget.caption,
                    style: Type.micro.copyWith(color: p.paper),
                  ),
                ),
              ],
            ),
          ),
          if (widget.showHandles)
            for (final corner in _Corner.values)
              Positioned(
                left: corner.isLeft ? -8 : null,
                right: corner.isLeft ? null : -8,
                top: corner.isTop ? -8 : null,
                bottom: corner.isTop ? null : -8,
                child: still
                    ? _handle(p, 1)
                    : AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) {
                          // 1.0 -> 1.35 -> 1.0 across the period.
                          final t = math.sin(_pulse.value * 2 * math.pi);
                          return _handle(p, 1 + 0.175 * (t + 1) / 2 * 2);
                        },
                      ),
              ),
        ],
      ),
    );
  }

  Widget _handle(DeskPalette p, double scale) => Transform.scale(
        scale: scale,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: p.paper,
            border: Border.all(color: p.clay, width: Stroke.live),
          ),
        ),
      );
}

enum _Corner {
  topLeft(true, true),
  topRight(false, true),
  bottomLeft(true, false),
  bottomRight(false, false);

  final bool isLeft;
  final bool isTop;
  const _Corner(this.isLeft, this.isTop);
}

/// One result: a photographic print with a wide lower margin.
///
/// Its resting angle comes from [id] rather than from `Random()`, so it never
/// jitters when the list rebuilds. A print that is still generating shows
/// [paperEdge] and fills in as preview frames arrive.
class Print extends StatelessWidget {
  final String id;
  final Widget? image;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  const Print({
    super.key,
    required this.id,
    this.image,
    this.selected = false,
    this.onTap,
    this.width = 74,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Transform.rotate(
      angle: restAngleFor(id),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: p.paper,
            border: selected
                ? Border.all(color: p.ink, width: Stroke.standard)
                : null,
            boxShadow:
                (selected ? Elevation.raised : Elevation.rest).shadows(p.ink),
          ),
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 14),
          child: AspectRatio(
            aspectRatio: 1,
            child: ColoredBox(
              color: p.paperEdge,
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}

/// The horizontal band of results. Scrolls within itself; never scrolls the
/// page, because comparing a result to the source is the app's core act and
/// both must stay visible.
class PrintShelf extends StatelessWidget {
  final List<Widget> prints;
  final String? stamp;

  const PrintShelf({super.key, required this.prints, this.stamp});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return SizedBox(
      height: 110,
      child: Row(
        children: [
          if (stamp != null) ...[
            RotatedBox(
              quarterTurns: 3,
              child: Text(stamp!, style: Type.micro.copyWith(color: p.inkMuted)),
            ),
            const SizedBox(width: Space.xs),
          ],
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              itemCount: prints.length,
              // Prints overlap by about a third of their width. `Padding`
              // rejects negative insets outright, so the overlap is a
              // transform - shifting each print left into its predecessor
              // rather than shrinking the gap between them.
              itemBuilder: (context, i) => Transform.translate(
                offset: Offset(i == 0 ? 0 : -18.0 * i, 0),
                child: prints[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled card tucked into the title row: the loaded checkpoint or
/// workflow, and the LoRA count when any are active.
class DeskCard extends StatelessWidget {
  final String label;
  final bool accent;
  final VoidCallback? onTap;

  const DeskCard({
    super.key,
    required this.label,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: accent ? p.clay : p.ink,
          borderRadius: BorderRadius.circular(Corner.photo),
        ),
        child: Text(
          label.toUpperCase(),
          style: Type.micro.copyWith(color: p.paper),
        ),
      ),
    );
  }
}
