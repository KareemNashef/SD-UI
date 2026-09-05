// ==================== Desk Overlays ==================== //
//
// Dropdowns, drawers and sticky notes. Every one of these replaces a Material
// equivalent outright - a native menu, a native BottomSheet or a SnackBar all
// arrive with soft shadows, pill shapes and ripples, none of which belong on
// this desk.

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/desk/desk_tokens.dart';

// ===== Dropdown ===== //

class DeskOption<T> {
  final T value;
  final String label;
  final String? detail;
  const DeskOption({required this.value, required this.label, this.detail});
}

/// The index card. Tapping the trigger drops a paper card anchored beneath
/// it; the selected row carries a clay bar on its left edge.
class DeskDropdown<T> extends StatefulWidget {
  final String label;
  final T value;
  final List<DeskOption<T>> options;
  final ValueChanged<T> onChanged;

  const DeskDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  State<DeskDropdown<T>> createState() => _DeskDropdownState<T>();
}

class _DeskDropdownState<T> extends State<DeskDropdown<T>> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _remove();
      setState(() {});
      return;
    }
    final box = context.findRenderObject() as RenderBox;
    final p = DeskTheme.of(context);
    final mode = DeskTheme.modeOf(context);

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Tap-away layer. Transparent, never a scrim - a dropdown is a card
          // laid on the desk, not a modal.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _remove();
                setState(() {});
              },
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, Space.sm),
            child: DeskTheme(
              palette: p,
              mode: mode,
              child: Align(
                alignment: Alignment.topLeft,
                child: _Card<T>(
                  width: box.size.width,
                  options: widget.options,
                  value: widget.value,
                  onPick: (v) {
                    widget.onChanged(v);
                    _remove();
                    setState(() {});
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final current = widget.options
        .where((o) => o.value == widget.value)
        .map((o) => o.label)
        .firstOrNull;

    return CompositedTransformTarget(
      link: _link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label.toUpperCase(),
              style: Type.micro.copyWith(color: p.inkFaint)),
          const SizedBox(height: Space.xs),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Container(
              height: Space.touch,
              padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
              decoration: BoxDecoration(
                color: p.paper,
                borderRadius: BorderRadius.circular(Corner.control),
                border: Border.all(
                  color: _entry != null ? p.clay : p.ink,
                  width: _entry != null ? Stroke.live : Stroke.standard,
                ),
                boxShadow: Elevation.raised.shadows(p.ink),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      current ?? '—',
                      style: Type.label.copyWith(color: p.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _entry != null
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: p.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card<T> extends StatefulWidget {
  final double width;
  final List<DeskOption<T>> options;
  final T value;
  final ValueChanged<T> onPick;

  const _Card({
    required this.width,
    required this.options,
    required this.value,
    required this.onPick,
  });

  @override
  State<_Card<T>> createState() => _CardState<T>();
}

class _CardState<T> extends State<_Card<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.fade,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ScaleTransition(
        // A 4px overshoot on arrival, anchored at the top edge so the card
        // reads as dropping out of the trigger.
        scale: Tween(begin: 0.96, end: 1.0)
            .animate(CurvedAnimation(parent: _c, curve: Motion.settle)),
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _c,
          child: Container(
            width: widget.width,
            constraints: const BoxConstraints(maxHeight: 8 * Space.touch),
            decoration: BoxDecoration(
              color: p.paper,
              borderRadius: BorderRadius.circular(Corner.control),
              border: Border.all(color: p.ink, width: Stroke.standard),
              boxShadow: Elevation.raised.shadows(p.ink),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corner.control - 2),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: widget.options.length,
                separatorBuilder: (_, __) => Container(
                  height: Stroke.hairline,
                  color: p.ink.withValues(alpha: 0.2),
                ),
                itemBuilder: (context, i) {
                  final option = widget.options[i];
                  final selected = option.value == widget.value;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onPick(option.value),
                    child: SizedBox(
                      height: Space.touch,
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: double.infinity,
                            color: selected ? p.clay : Colors.transparent,
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Text(
                              option.label,
                              style: Type.label.copyWith(
                                color: selected ? p.ink : p.inkMuted,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (option.detail != null) ...[
                            Text(option.detail!,
                                style: Type.micro.copyWith(color: p.inkFaint)),
                            const SizedBox(width: Space.md),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Drawer ===== //

/// Every modal is a drawer pulled up from the bottom edge: full width, paper,
/// a 3px ink top border, rounded on the top corners only, and a flat ink
/// scrim behind it — never a blur.
Future<T?> showDeskDrawer<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  Widget? action,
}) {
  final p = DeskTheme.of(context);
  final mode = DeskTheme.modeOf(context);

  return showGeneralRoute<T>(
    context: context,
    palette: p,
    mode: mode,
    title: title,
    builder: builder,
    action: action,
  );
}

Future<T?> showGeneralRoute<T>({
  required BuildContext context,
  required DeskPalette palette,
  required DeskMode mode,
  required String title,
  required WidgetBuilder builder,
  Widget? action,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: palette.ink.withValues(alpha: 0.32),
      transitionDuration: Motion.drawer,
      reverseTransitionDuration: Motion.fade,
      pageBuilder: (context, animation, _) => DeskTheme(
        palette: palette,
        mode: mode,
        child: _Drawer(title: title, action: action, builder: builder),
      ),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Motion.ease),
        ),
        child: child,
      ),
    ),
  );
}

class _Drawer extends StatefulWidget {
  final String title;
  final Widget? action;
  final WidgetBuilder builder;

  const _Drawer({required this.title, this.action, required this.builder});

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  /// How far the sheet has been dragged down, in logical pixels.
  double _drag = 0;

  /// Past this, releasing dismisses rather than springs back.
  static const _dismissAt = 110.0;

  /// A firm flick dismisses regardless of distance, so the gesture doesn't
  /// demand a long drag to feel responsive.
  static const _flickVelocity = 700.0;

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      // Only downward travel counts; dragging up must not lift the sheet off
      // the bottom edge it is anchored to.
      _drag = (_drag + d.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (_drag > _dismissAt || velocity > _flickVelocity) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final title = widget.title;
    final action = widget.action;
    final builder = widget.builder;

    // The sheet is bottom-aligned, so without this the keyboard simply
    // covers it: the sheet does not move, its scroll view does not shrink,
    // and so `EditableText` sees the focused field as already visible and
    // scrolls nothing. Typing into anything near the bottom of a drawer -
    // a rename, a strength, a seed - meant typing blind.
    //
    // Lifting the sheet by the inset *and* capping its height to what is
    // left above the keyboard fixes both halves: the sheet clears the
    // keyboard, and its scroll view now has a smaller viewport, which is
    // what lets a focused field be scrolled into it.
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = keyboard > 0
        ? (size.height - keyboard - Space.xxl).clamp(160.0, size.height)
        : size.height * 0.88;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Transform.translate(
        offset: Offset(0, _drag),
        child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: p.paper,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Corner.panel),
                topRight: Radius.circular(Corner.panel),
              ),
              border: Border(
                top: BorderSide(color: p.ink, width: Stroke.frame),
              ),
              boxShadow: Elevation.drawer.shadows(p.ink),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The handle and the title row are the drag surface, per
                  // DESIGN.md 7.13 ("drag down to dismiss, with velocity
                  // carried"). The body below stays scrollable, so dragging
                  // a list never fights the dismiss gesture. The grip was
                  // previously decoration only - it looked draggable and
                  // wasn't, which is worse than no grip at all.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: Space.md),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.ink,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Space.lg, Space.lg, Space.lg, Space.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(title,
                                    style: Type.sheetTitle.copyWith(color: p.ink)),
                              ),
                              if (action != null) action,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          Space.lg, 0, Space.lg, Space.lg),
                      child: Builder(builder: builder),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}

// ===== Sticky note ===== //

/// Transient messages are sticky notes: paper, no border, slightly rotated,
/// arriving from the top-right.
class StickyNote extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onDismiss;

  const StickyNote({
    super.key,
    required this.message,
    this.isError = false,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Transform.rotate(
      angle: -2 * 3.14159265 / 180,
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.lg, vertical: Space.md),
          decoration: BoxDecoration(
            color: p.paper,
            border: isError
                ? Border.all(color: DeskPalette.alert, width: Stroke.standard)
                : null,
            boxShadow: Elevation.rest.shadows(p.ink),
          ),
          child: Text(
            message,
            style: Type.body.copyWith(
              color: isError ? DeskPalette.alert : p.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Page route ===== //

/// The transition every full-screen Aperture page uses.
///
/// A full-width slide from the right that **overshoots and settles**, rather
/// than the platform default's linear-feeling glide. It is the same physics
/// as the press-into-shadow on every button: objects on this desk have
/// weight, so they travel a little past where they are going and come back.
///
/// The trailing edge is the subtle part. Overshooting a full-screen slide
/// pulls the page's right edge away from the screen for ~80ms, which would
/// otherwise expose a strip of the page underneath and read as tearing. So
/// the page carries a strip of desk colour past its own right edge, wide
/// enough to cover the overshoot - the gap is filled by the sheet itself.
class DeskPageRoute<T> extends PageRouteBuilder<T> {
  DeskPageRoute({
    required WidgetBuilder builder,
    super.fullscreenDialog,
  }) : super(
          transitionDuration: Motion.page,
          reverseTransitionDuration: Motion.fade,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            // Reduced motion gets a plain cross-fade: the arrival still
            // reads, but nothing travels and nothing overshoots.
            if (reduceMotion(context)) {
              return FadeTransition(opacity: animation, child: child);
            }

            final slide = CurvedAnimation(
              parent: animation,
              curve: Motion.pageIn,
              // Leaving is a plain decelerate - a page bouncing on its way
              // out looks indecisive rather than physical.
              reverseCurve: Motion.ease.flipped,
            );

            // The desk colour behind the page, so the overshoot has
            // something of its own to reveal.
            final palette = DeskPalette.of(
              MediaQuery.platformBrightnessOf(context) == Brightness.dark
                  ? DeskMode.night
                  : DeskMode.day,
            );
            final bleed = MediaQuery.sizeOf(context).width * 0.2;

            return SlideTransition(
              position: Tween(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(slide),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: -bleed,
                    width: bleed,
                    child: ColoredBox(color: palette.desk),
                  ),
                  child,
                ],
              ),
            );
          },
        );
}
