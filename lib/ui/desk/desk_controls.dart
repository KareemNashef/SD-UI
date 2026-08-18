// ==================== Desk Controls ==================== //
//
// Everything you press, drag or type into.
//
// The signature interaction is press-into-shadow: on tap down the object
// translates by exactly its shadow offset and the shadow shrinks, so it looks
// like it has been pushed into the desk. On release it springs back past rest
// and settles. There are no ripples anywhere in this file - that press *is*
// the feedback, and Material's ink splash is explicitly suppressed wherever a
// Material ancestor would otherwise supply one.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sd_companion/ui/desk/desk_tokens.dart';

/// Shared press-into-shadow behaviour.
///
/// Mixed into every pressable control so the physics cannot drift between
/// them - the moment two controls press differently, the illusion that they
/// are objects on one surface breaks.
mixin _Pressable<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  late final AnimationController pressCtl = AnimationController(
    vsync: this,
    duration: Motion.press,
    reverseDuration: const Duration(milliseconds: 180),
  );

  /// 0 at rest, 1 fully pressed.
  double get pressT => pressCtl.value;

  void pressDown() => pressCtl.forward();
  void pressUp() => pressCtl.reverse();

  @override
  void dispose() {
    pressCtl.dispose();
    super.dispose();
  }

  /// Wraps [child] so it sinks into its own shadow while held.
  Widget pressWrap({
    required Widget Function(Elevation elevation) builder,
    required Elevation rest,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => pressDown() : null,
      onTapUp: enabled ? (_) => pressUp() : null,
      onTapCancel: enabled ? pressUp : null,
      onTap: enabled ? onTap : null,
      child: AnimatedBuilder(
        animation: pressCtl,
        builder: (context, _) {
          if (!enabled) return builder(Elevation.none);
          final still = reduceMotion(context);
          final t = still ? 0.0 : Curves.easeOut.transform(pressT);
          final elevation = Elevation.lerp(rest, Elevation.pressed, t);
          // Travel by exactly the shadow it is losing, so the object appears
          // to move down into the desk rather than merely shrink.
          final travel = rest.offset - elevation.offset;
          return Transform.translate(
            offset: travel,
            child: builder(elevation),
          );
        },
      ),
    );
  }
}

// ===== Button ===== //

enum DeskButtonKind { primary, secondary, ghost, destructive }

class DeskButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final DeskButtonKind kind;
  final bool expand;

  const DeskButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = DeskButtonKind.secondary,
    this.expand = false,
  });

  @override
  State<DeskButton> createState() => _DeskButtonState();
}

class _DeskButtonState extends State<DeskButton>
    with SingleTickerProviderStateMixin, _Pressable {
  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final enabled = widget.onPressed != null;

    final (Color fill, Color fg, Color border) = switch (widget.kind) {
      DeskButtonKind.primary => (p.clay, p.paper, p.ink),
      DeskButtonKind.secondary => (p.paper, p.ink, p.ink),
      DeskButtonKind.ghost => (Colors.transparent, p.ink, p.ink),
      DeskButtonKind.destructive => (p.paper, DeskPalette.alert, DeskPalette.alert),
    };

    return pressWrap(
      rest: widget.kind == DeskButtonKind.ghost
          ? Elevation.none
          : Elevation.raised,
      enabled: enabled,
      onTap: widget.onPressed,
      builder: (elevation) => Container(
        width: widget.expand ? double.infinity : null,
        constraints: const BoxConstraints(minHeight: Space.touch),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        decoration: BoxDecoration(
          color: enabled ? fill : p.paperEdge,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(
            color: enabled ? border : p.inkFaint,
            width: Stroke.standard,
          ),
          boxShadow: elevation.shadows(p.ink),
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 16, color: enabled ? fg : p.inkFaint),
              const SizedBox(width: Space.sm),
            ],
            Text(
              widget.label,
              style: Type.label.copyWith(color: enabled ? fg : p.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Field ===== //

/// The micro label sits above and outside the field, never as a placeholder -
/// a placeholder disappears exactly when you need it.
class DeskField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const DeskField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  State<DeskField> createState() => _DeskFieldState();
}

class _DeskFieldState extends State<DeskField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final focused = _focus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(),
            style: Type.micro.copyWith(color: p.inkFaint)),
        const SizedBox(height: Space.xs),
        Container(
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(Corner.control),
            border: Border.all(
              color: focused ? p.clay : p.ink,
              width: focused ? Stroke.live : Stroke.standard,
            ),
            boxShadow: Elevation.raised.shadows(p.ink),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: Space.md + 2, vertical: Space.md),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            maxLines: widget.maxLines,
            onChanged: widget.onChanged,
            cursorColor: p.clay,
            cursorWidth: 2,
            style: Type.body.copyWith(color: p.ink),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: widget.hint,
              hintStyle: Type.body.copyWith(color: p.inkFaint),
            ),
          ),
        ),
      ],
    );
  }
}

// ===== Chip ===== //

/// A value at a glance: micro unit above, large value below.
class DeskChip extends StatefulWidget {
  final String unit;
  final String value;
  final VoidCallback? onTap;
  final bool expand;

  const DeskChip({
    super.key,
    required this.unit,
    required this.value,
    this.onTap,
    this.expand = true,
  });

  @override
  State<DeskChip> createState() => _DeskChipState();
}

class _DeskChipState extends State<DeskChip>
    with SingleTickerProviderStateMixin, _Pressable {
  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final chip = pressWrap(
      rest: Elevation.rest,
      onTap: widget.onTap,
      builder: (elevation) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(color: p.ink, width: Stroke.standard),
          boxShadow: elevation.shadows(p.ink),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.unit.toUpperCase(),
                style: Type.micro.copyWith(color: p.inkFaint)),
            const SizedBox(height: 1),
            Text(widget.value, style: Type.value.copyWith(color: p.ink)),
          ],
        ),
      ),
    );
    return widget.expand ? Expanded(child: chip) : chip;
  }
}

// ===== Ruler slider ===== //

/// Sliders are rulers, because a desk has one.
///
/// A bordered track with tick marks, a clay fill behind the ticks, and a
/// paper tab that sticks up above the track carrying the current value.
class DeskRuler extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double)? format;

  const DeskRuler({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.format,
  });

  @override
  State<DeskRuler> createState() => _DeskRulerState();
}

class _DeskRulerState extends State<DeskRuler> {
  bool _dragging = false;

  double get _t =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _emit(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    var v = widget.min + t * (widget.max - widget.min);
    final divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      final step = (widget.max - widget.min) / divisions;
      v = widget.min + (((v - widget.min) / step).round() * step);
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final text = widget.format?.call(widget.value) ??
        widget.value.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(),
            style: Type.micro.copyWith(color: p.inkFaint)),
        const SizedBox(height: Space.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const thumbW = 22.0;
            final travel = width - thumbW;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) {
                setState(() => _dragging = true);
                _emit(d.localPosition.dx - thumbW / 2, travel);
              },
              onHorizontalDragUpdate: (d) =>
                  _emit(d.localPosition.dx - thumbW / 2, travel),
              onHorizontalDragEnd: (_) => setState(() => _dragging = false),
              onTapDown: (d) => _emit(d.localPosition.dx - thumbW / 2, travel),
              child: SizedBox(
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0, right: 0, top: 7,
                      child: Container(
                        height: 26,
                        decoration: BoxDecoration(
                          color: p.paperEdge,
                          borderRadius: BorderRadius.circular(Corner.photo),
                          border:
                              Border.all(color: p.ink, width: Stroke.standard),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Corner.photo),
                          child: CustomPaint(
                            painter: _RulerPainter(
                              fraction: _t,
                              fill: p.clay,
                              tick: p.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: travel * _t,
                      top: 0,
                      child: Container(
                        width: thumbW,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.paper,
                          borderRadius: BorderRadius.circular(Corner.photo),
                          border:
                              Border.all(color: p.ink, width: Stroke.standard),
                          boxShadow: (_dragging
                                  ? Elevation.lifted
                                  : Elevation.rest)
                              .shadows(p.ink),
                        ),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            text,
                            style: Type.readout
                                .copyWith(color: p.ink, fontSize: 9.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double fraction;
  final Color fill;
  final Color tick;

  const _RulerPainter({
    required this.fraction,
    required this.fill,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * fraction, size.height),
      Paint()..color = fill,
    );
    // Ticks sit on top of the fill, so the ruler reads as one object rather
    // than as a progress bar with marks floating over it.
    final paint = Paint()
      ..color = tick.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      final h = i == 5 ? size.height * 0.62 : size.height * 0.34;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), paint);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.fraction != fraction || old.fill != fill || old.tick != tick;
}

// ===== Toggle ===== //

/// A paper tab sliding in a slot. When on, the *slot* fills clay - the tab
/// never changes colour, because a physical tab doesn't.
class DeskToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const DeskToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final enabled = onChanged != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: Motion.press,
        curve: Motion.snap,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: value ? p.clay : p.paperEdge,
          borderRadius: BorderRadius.circular(Corner.control),
          border: Border.all(
            color: enabled ? p.ink : p.inkFaint,
            width: Stroke.standard,
          ),
        ),
        child: AnimatedAlign(
          duration: Motion.press,
          curve: Motion.snap,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: p.paper,
              borderRadius: BorderRadius.circular(Corner.photo + 4),
              border: Border.all(color: p.ink, width: Stroke.standard),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Tab strip ===== //

class DeskTab<T> {
  final T value;
  final String label;
  final IconData? icon;
  const DeskTab({required this.value, required this.label, this.icon});
}

/// Folder tabs: rounded on the top corners only, sitting flush on whatever
/// they label. The active tab fills clay and sits 2px higher.
class DeskTabStrip<T> extends StatelessWidget {
  final List<DeskTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  const DeskTabStrip({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final tab in tabs)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(tab.value),
                child: AnimatedContainer(
                  duration: Motion.press,
                  curve: Motion.snap,
                  height: tab.value == value ? 40 : 34,
                  margin: const EdgeInsets.only(right: Space.xs),
                  decoration: BoxDecoration(
                    color: tab.value == value ? p.clay : p.paper,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(Corner.control),
                      topRight: Radius.circular(Corner.control),
                    ),
                    border: Border(
                      top: BorderSide(color: p.ink, width: Stroke.standard),
                      left: BorderSide(color: p.ink, width: Stroke.standard),
                      right: BorderSide(color: p.ink, width: Stroke.standard),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (tab.icon != null) ...[
                        Icon(tab.icon,
                            size: 14,
                            color: tab.value == value ? p.paper : p.inkMuted),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        tab.label,
                        style: Type.label.copyWith(
                          color: tab.value == value ? p.paper : p.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== Tool tray ===== //

class DeskTool {
  final IconData icon;
  final String name;
  final VoidCallback? onTap;
  const DeskTool({required this.icon, required this.name, this.onTap});
}

/// The tray bolted to the left edge: square against the frame, rounded on its
/// outer edge, because it is attached rather than lying on the desk.
///
/// It holds only the tools the active engine supports. A missing tool leaves
/// no gap - the tray is simply shorter.
class DeskToolTray extends StatelessWidget {
  final List<DeskTool> tools;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const DeskToolTray({
    super.key,
    required this.tools,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Container(
      width: Space.trayWidth,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Corner.trayOuter),
          bottomRight: Radius.circular(Corner.trayOuter),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tools.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onSelect(i);
                tools[i].onTap?.call();
              },
              child: AnimatedContainer(
                duration: Motion.press,
                curve: Motion.snap,
                width: 30,
                height: 30,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: i == activeIndex ? p.clay : Colors.transparent,
                  borderRadius: BorderRadius.circular(Corner.control),
                ),
                child: Icon(
                  tools[i].icon,
                  size: 16,
                  color: i == activeIndex
                      ? p.paper
                      : p.paper.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== Stamp ===== //

/// Semantic status: text plus a border, never a fill, so it cannot compete
/// with clay.
class DeskStamp extends StatelessWidget {
  final String label;
  final Color color;

  const DeskStamp({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: Stroke.standard),
        borderRadius: BorderRadius.circular(Corner.photo),
      ),
      child: Text(label.toUpperCase(), style: Type.micro.copyWith(color: color)),
    );
  }
}

// ===== Progress ===== //

/// Generation progress reuses the ruler: same track, filling in clay.
class DeskProgress extends StatefulWidget {
  /// Null renders the indeterminate segment travelling the track.
  final double? fraction;
  final String? caption;

  const DeskProgress({super.key, this.fraction, this.caption});

  @override
  State<DeskProgress> createState() => _DeskProgressState();
}

class _DeskProgressState extends State<DeskProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.fraction == null) _c.repeat();
  }

  @override
  void didUpdateWidget(DeskProgress old) {
    super.didUpdateWidget(old);
    if (widget.fraction == null && !_c.isAnimating) {
      _c.repeat();
    } else if (widget.fraction != null && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 22,
          decoration: BoxDecoration(
            color: p.paperEdge,
            borderRadius: BorderRadius.circular(Corner.photo),
            border: Border.all(color: p.ink, width: Stroke.standard),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Corner.photo),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _ProgressPainter(
                  fraction: widget.fraction,
                  phase: _c.value,
                  fill: p.clay,
                  tick: p.ink,
                ),
              ),
            ),
          ),
        ),
        if (widget.caption != null) ...[
          const SizedBox(height: Space.xs),
          Text(widget.caption!, style: Type.micro.copyWith(color: p.inkFaint)),
        ],
      ],
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double? fraction;
  final double phase;
  final Color fill;
  final Color tick;

  const _ProgressPainter({
    required this.fraction,
    required this.phase,
    required this.fill,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = fill;
    final f = fraction;
    if (f != null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width * f.clamp(0, 1), size.height), paint);
    } else {
      // A 25% segment travelling the track.
      const seg = 0.25;
      final left = (phase * (1 + seg) - seg) * size.width;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, size.width * seg, size.height),
        paint,
      );
    }
    final ticks = Paint()
      ..color = tick.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      final h = i == 5 ? size.height * 0.6 : size.height * 0.32;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), ticks);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.fraction != fraction || old.phase != phase || old.fill != fill;
}

/// Small helper so mockup panels get consistent internal padding.
class DeskPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DeskPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(Corner.panel),
        border: Border.all(color: p.ink, width: Stroke.standard),
        boxShadow: Elevation.rest.shadows(p.ink),
      ),
      child: child,
    );
  }
}

/// Rotation helper used by sticky notes and anything else that should sit
/// slightly askew. Kept here so the angle language stays in one place.
double get stickyAngle => -2 * math.pi / 180;
