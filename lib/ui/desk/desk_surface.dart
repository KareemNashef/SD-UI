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
/// mat board around a photograph, and four small corner brackets - a
/// viewfinder mark rather than a draggable handle, since nothing here is
/// wired to a drag gesture yet. Static, in ink's live accent, and inset
/// flush with the frame rather than overhanging it.
class MountedSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
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
                ColoredBox(color: p.paperEdge, child: image),
                Positioned(
                  left: Space.sm,
                  bottom: Space.sm - 1,
                  child: Text(
                    caption,
                    style: Type.micro.copyWith(color: p.paper),
                  ),
                ),
              ],
            ),
          ),
          if (showHandles)
            for (final corner in _Corner.values)
              Positioned(
                left: corner.isLeft ? Space.xs : null,
                right: corner.isLeft ? null : Space.xs,
                top: corner.isTop ? Space.xs : null,
                bottom: corner.isTop ? null : Space.xs,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CustomPaint(
                    painter: _BracketPainter(
                      isLeft: corner.isLeft,
                      isTop: corner.isTop,
                      color: p.clay,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final bool isLeft;
  final bool isTop;
  final Color color;

  const _BracketPainter({required this.isLeft, required this.isTop, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = Stroke.live
      ..strokeCap = StrokeCap.square;
    final x = isLeft ? 0.0 : size.width;
    final y = isTop ? 0.0 : size.height;
    final dx = isLeft ? size.width : -size.width;
    final dy = isTop ? size.height : -size.height;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.isLeft != isLeft || old.isTop != isTop;
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
///
/// [lift] (0..1) is how far it has risen off the shelf - 1.0 is fully picked
/// out of the deck, 0.0 is flat. [PrintShelf] drives this continuously as the
/// shelf scrolls; a caller using a bare [Print] outside a shelf can ignore it
/// and just pass [selected] for the same sensible resting state.
class Print extends StatelessWidget {
  final String id;
  final Widget? image;
  final bool selected;
  final double? lift;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final double width;

  const Print({
    super.key,
    required this.id,
    this.image,
    this.selected = false,
    this.lift,
    this.onTap,
    this.onDoubleTap,
    this.width = 74,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final t = (lift ?? (selected ? 1.0 : 0.0)).clamp(0.0, 1.0);
    final elevation = Elevation.lerp(Elevation.rest, Elevation.lifted, t);

    return Transform.translate(
      // A card picked out of a deck rises, it doesn't slide sideways - and
      // rises a lot, so the shelf reads as a hand fanning through a deck
      // rather than a row of thumbnails nudging apart.
      offset: Offset(0, -26 * t),
      child: Transform.scale(
        scale: 1 + 0.14 * t,
        child: Transform.rotate(
          // It also straightens as it comes up - by the time it's fully
          // risen it reads as squared to the shelf, not tilted like the rest.
          angle: restAngleFor(id) * (1 - t),
          child: GestureDetector(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: p.paper,
                // The border tracks selection and *only* selection. It used
                // to also switch on `lift > 0.5`, so a card that merely rose
                // as its neighbour was picked grew a border too - which read
                // as the shelf highlighting the wrong print.
                border: selected
                    ? Border.all(color: p.ink, width: Stroke.standard)
                    : null,
                boxShadow: elevation.shadows(p.ink),
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
        ),
      ),
    );
  }
}

/// One entry on the shelf: an identity plus what it shows. [PrintShelf] needs
/// the identity itself (not just a pre-built [Print] widget) so it can own
/// the lift animation and report which entry the shelf has settled on.
class PrintEntry {
  final String id;
  final Widget? image;

  /// Optional secondary action for this card. The input card uses it for
  /// double-tap-to-replace, so swapping the source image never costs a trip
  /// through the tray.
  final VoidCallback? onDoubleTap;

  const PrintEntry({required this.id, this.image, this.onDoubleTap});
}

/// The horizontal band of images: the source image (when there is one) at the
/// left, a divider, then every result. Scrolls within itself; never scrolls
/// the page, because comparing a result to the source is the app's core act
/// and both must stay visible.
///
/// Lift is driven by **selection**, not by scroll position. The earlier
/// version rose whichever card sat nearest the viewport centre, which meant
/// a shelf too short to scroll never animated at all and, when it did, the
/// raised card was whatever happened to be centred rather than the one the
/// user picked. Here the focused index animates to the selection and each
/// card's height falls off with its distance from it - so tapping any card
/// lifts *that* card, with its neighbours rising in a parabola around it,
/// at any list length.
class PrintShelf extends StatefulWidget {
  final List<PrintEntry> entries;

  /// The source image, pinned to the left of the divider. Selectable exactly
  /// like a result - tapping it promotes it to the main display.
  final PrintEntry? input;

  final String? selectedId;
  final ValueChanged<String>? onSelect;

  const PrintShelf({
    super.key,
    required this.entries,
    this.input,
    this.selectedId,
    this.onSelect,
  });

  @override
  State<PrintShelf> createState() => _PrintShelfState();
}

class _PrintShelfState extends State<PrintShelf> {
  static const _itemWidth = 74.0;
  static const _overlap = 22.0;
  static const _pitch = _itemWidth - _overlap; // visual spacing, post-overlap
  static const _dividerGap = 20.0;

  /// How many neighbours on each side visibly rise with the focused card.
  /// Above 1 so the shelf reads as a hand fanning a deck, not one card
  /// popping alone.
  static const _spread = 2.4;

  final _scroll = ScrollController();

  List<PrintEntry> get _all =>
      [if (widget.input != null) widget.input!, ...widget.entries];

  bool get _hasInput => widget.input != null;

  int get _focusIndex {
    final id = widget.selectedId;
    if (id == null) return 0;
    final i = _all.indexWhere((e) => e.id == id);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(PrintShelf old) {
    super.didUpdateWidget(old);
    if (widget.selectedId != old.selectedId && widget.selectedId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocused());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Left edge of the card at [index], accounting for the input card sitting
  /// clear of the overlapping result stack.
  double _xFor(int index) {
    if (_hasInput && index == 0) return 0;
    final resultIndex = _hasInput ? index - 1 : index;
    final lead = _hasInput ? _itemWidth + _dividerGap : 0.0;
    return lead + resultIndex * _pitch;
  }

  /// Brings the focused card into view without yanking the shelf around when
  /// it is already visible.
  void _revealFocused() {
    if (!_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final x = _xFor(_focusIndex);
    final target =
        (x + _itemWidth / 2 - viewport / 2).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: Motion.arrival, curve: Motion.ease);
  }

  double _liftFor(int index, double focus) {
    final distance = (index - focus).abs();
    final t = (1 - distance / _spread).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t); // smoothstep - a gentle falloff, not a cliff
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final all = _all;

    return SizedBox(
      height: 142,
      // Animating the *focus position* rather than each card's lift means
      // the whole parabola slides along the shelf, so the cards between the
      // old and new selection rise and fall on the way past instead of two
      // cards cross-fading in place.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: _focusIndex.toDouble(), end: _focusIndex.toDouble()),
        duration: Motion.arrival,
        curve: Motion.ease,
        builder: (context, focus, _) => SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < all.length; i++) ...[
                if (_hasInput && i == 1) _divider(p),
                Transform.translate(
                  // Results overlap into each other; the input card
                  // deliberately does not, so the divider reads as a
                  // real separation rather than a gap in one deck.
                  offset: Offset(
                    (_hasInput && i == 0) ? 0 : -_overlap * (_hasInput ? i - 1 : i),
                    0,
                  ),
                  child: Print(
                    id: all[i].id,
                    image: all[i].image,
                    selected: all[i].id == widget.selectedId,
                    lift: _liftFor(i, focus),
                    width: _itemWidth,
                    onTap: () => widget.onSelect?.call(all[i].id),
                    onDoubleTap: all[i].onDoubleTap,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(DeskPalette p) => Container(
        width: Stroke.standard,
        height: 66,
        margin: const EdgeInsets.symmetric(horizontal: (_dividerGap - Stroke.standard) / 2),
        color: p.ink.withValues(alpha: 0.28),
      );
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
