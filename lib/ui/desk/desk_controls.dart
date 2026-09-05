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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show TextInputFormatter, SystemUiOverlayStyle, HapticFeedback;

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

  /// A held press releases immediately. A completed tap does not: it waits
  /// for the press-in to finish landing before springing back out. Without
  /// that wait, a fast tap fires `onTapUp` before the 90ms press-in animation
  /// reaches 1.0, cutting the dip short - so a quick single tap looked like
  /// it barely moved, and only holding the press showed the full travel.
  Future<void> pressUpFull() async {
    if (pressCtl.status == AnimationStatus.forward) {
      try {
        await pressCtl.forward().orCancel;
      } catch (_) {
        return; // disposed or superseded mid-flight
      }
    }
    if (mounted) pressCtl.reverse();
  }

  /// An aborted press (the finger dragged away) snaps back immediately -
  /// only a genuine completed tap earns the forced full-travel wait above.
  void pressUpCancelled() => pressCtl.reverse();

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
      onTapUp: enabled ? (_) => pressUpFull() : null,
      onTapCancel: enabled ? pressUpCancelled : null,
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
  final List<TextInputFormatter>? inputFormatters;

  /// Optional control shown on the label row, right-aligned. The label line
  /// is otherwise dead space, and it keeps a field-level action out of the
  /// input itself where it would crowd the text.
  final Widget? trailing;

  const DeskField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.inputFormatters,
    this.trailing,
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
        Row(
          children: [
            Expanded(
              child: Text(widget.label.toUpperCase(),
                  style: Type.micro.copyWith(color: p.inkFaint)),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
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
            inputFormatters: widget.inputFormatters,
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
                        // Insets the fill inside the ink line. Without this,
                        // the fill's ClipRRect used the *outer* radius while
                        // sitting flush against the border - Flutter deflates
                        // a rounded border's visible curve by half its stroke
                        // width, so the two curves didn't coincide and a
                        // sliver of paperEdge showed through in the corners.
                        padding: const EdgeInsets.all(Stroke.standard),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                              (Corner.photo - Stroke.standard)
                                  .clamp(0, Corner.photo)),
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
                          // `lifted` (offset 6,8) is scaled for objects the
                          // size of a print or a whole card - on a thumb this
                          // thin it read as a stray dark rectangle trailing
                          // behind rather than a shadow attached to it.
                          // `raised` keeps the same "picked up" cue at a
                          // proportionate scale.
                          boxShadow: (_dragging
                                  ? Elevation.raised
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
                      // Flexible, not bare: four tabs on a narrow phone
                      // (or at a large text scale) overflow a Row that
                      // sizes to its children, and an overflowing tab strip
                      // clips silently rather than shrinking.
                      Flexible(
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: Type.label.copyWith(
                            color: tab.value == value ? p.paper : p.inkMuted,
                          ),
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

  /// Optional press-and-hold behaviour. When [onHoldStart] is set the tool
  /// acts as a momentary switch instead of a button: it fires the instant
  /// the finger lands and releases on lift, which is what "hold to compare"
  /// needs. A long-press delay would make the comparison feel laggy.
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  /// Longer description shown on long-press. Defaults to [name].
  final String? hint;

  const DeskTool({
    required this.icon,
    required this.name,
    this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
    this.hint,
  });

  bool get isMomentary => onHoldStart != null;
}

/// The tray bolted to the left edge: square against the frame, rounded on its
/// outer edge, because it is attached rather than lying on the desk.
///
/// It holds only the tools the active engine supports. A missing tool leaves
/// no gap - the tray is simply shorter.
///
/// TODO(front page): the tray's *contents* also need to change with context,
/// not just with the engine's capability flags. What belongs in it while
/// typing a text2img prompt (workflow/checkpoint, LoRAs) is not what belongs
/// in it once an image is loaded for img2img (mask brush, outpaint handles
/// toggle) or while viewing a past result (upscale, save, compare, send back
/// to source). The caller passes `tools` fresh per rebuild already, so the
/// fix is at the call site - build the list from `(engine, sessionMode,
/// viewingResult)` rather than a fixed list - not in this widget.
class DeskToolTray extends StatelessWidget {
  final List<DeskTool> tools;

  /// Which tool is *currently in effect*. Null means none - which is the
  /// right answer for a tray of one-shot actions (save, undo, extend), where
  /// highlighting the last thing tapped implies a mode that isn't there.
  /// Reserve a non-null value for genuinely modal tools.
  final int? activeIndex;

  final ValueChanged<int>? onSelect;

  const DeskToolTray({
    super.key,
    required this.tools,
    this.activeIndex,
    this.onSelect,
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
      // A scroll view rather than a bare Column: the tray's tool count is
      // context-driven (capability- and context-gated), so a short device or
      // a context with several tools active at once must not overflow -
      // it should scroll rather than throw.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tools.length; i++)
              _TrayTool(
                tool: tools[i],
                active: i == activeIndex,
                onTap: () {
                  onSelect?.call(i);
                  tools[i].onTap?.call();
                },
              ),
          ],
        ),
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
    // Must handle the fraction going back to null, not just null -> value.
    // A ComfyUI run reports steps per node, so the bar legitimately returns
    // to indeterminate between nodes; without restarting the loop here it
    // froze at the last node's value for the rest of the run.
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
    final fraction = widget.fraction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const thumbW = 34.0;
            final travel = (constraints.maxWidth - thumbW).clamp(0.0, double.infinity);
            final t = (fraction ?? 0).clamp(0.0, 1.0);

            return SizedBox(
              // Matches DeskRuler's geometry exactly, because DESIGN.md 7.14
              // says progress *is* the ruler - same track, same brass tab
              // sticking up above it, just driven by the engine instead of
              // by a finger.
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 7,
                    child: Container(
                      height: 26,
                      decoration: BoxDecoration(
                        color: p.paperEdge,
                        borderRadius: BorderRadius.circular(Corner.photo),
                        border: Border.all(color: p.ink, width: Stroke.standard),
                      ),
                      // Same inset as the ruler track, and for the same
                      // reason: without it the fill's corner clip and the
                      // border's corner curve don't coincide, and paperEdge
                      // shows through the gap.
                      padding: const EdgeInsets.all(Stroke.standard),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            (Corner.photo - Stroke.standard).clamp(0, Corner.photo)),
                        child: AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) => CustomPaint(
                            painter: _ProgressPainter(
                              fraction: fraction,
                              phase: _c.value,
                              fill: p.clay,
                              tick: p.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // The thumb only exists when there is a real number to put
                  // on it. Indeterminate progress has no position to point
                  // at, so parking a tab at 0% would be a lie - the
                  // travelling segment carries that state instead.
                  if (fraction != null)
                    AnimatedPositioned(
                      duration: Motion.fade,
                      curve: Motion.ease,
                      left: travel * t,
                      top: 0,
                      child: Container(
                        width: thumbW,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.paper,
                          borderRadius: BorderRadius.circular(Corner.photo),
                          border: Border.all(color: p.ink, width: Stroke.standard),
                          boxShadow: Elevation.rest.shadows(p.ink),
                        ),
                        child: Text(
                          '${(t * 100).round()}',
                          style: Type.readout.copyWith(color: p.ink, fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
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

// ===== Page header ===== //

/// The title bar for a full-screen editor (mask, extend, import).
///
/// It sits on **paper**, not directly on the desk. Title text is `ink`, and
/// in night mode `ink` (#14110C) against `desk` (#2A241B) is very nearly the
/// same colour - a title written straight onto the work surface was legible
/// in day mode and almost invisible at night. Putting the header on a paper
/// strip restores the ink-on-paper contrast the rest of the app relies on,
/// and reads as the head of a sheet rather than words painted on the desk.
class DeskPageHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget? action;

  const DeskPageHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final mode = DeskTheme.modeOf(context);
    // Paint the paper *behind* the status bar rather than starting below it.
    // Leaving that strip on the desk colour made the header read as a band
    // wedged between two different surfaces instead of the top of a sheet.
    final statusBarHeight = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Paper is light in both modes, so the status bar icons must be dark
      // in both - matching them to the *header*, not to the app's theme.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: mode == DeskMode.day ? Brightness.light : Brightness.light,
      ),
      child: Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(bottom: BorderSide(color: p.ink, width: Stroke.frame)),
        boxShadow: Elevation.rest.shadows(p.ink),
      ),
      padding: EdgeInsets.fromLTRB(
          Space.sm, Space.sm + statusBarHeight, Space.md, Space.sm),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: SizedBox(
              width: Space.touch,
              height: Space.touch,
              child: Icon(Icons.close_rounded, color: p.ink),
            ),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              title,
              style: Type.sheetTitle.copyWith(color: p.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null) ...[const SizedBox(width: Space.sm), action!],
        ],
      ),
      ),
    );
  }
}


/// One tool in the tray.
///
/// The tray is a column of unlabelled icons, which is fine until there are
/// six of them - so every tool names itself on long-press. Momentary tools
/// (hold-to-compare) opt out of that, because for them the hold *is* the
/// gesture; they respond on pointer-down rather than after a long-press
/// delay, so the thing they toggle feels instantaneous.
class _TrayTool extends StatefulWidget {
  final DeskTool tool;
  final bool active;
  final VoidCallback onTap;

  const _TrayTool({
    required this.tool,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TrayTool> createState() => _TrayToolState();
}

class _TrayToolState extends State<_TrayTool> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);
    final tool = widget.tool;
    final lit = widget.active || _held;

    Widget icon = AnimatedContainer(
      duration: Motion.press,
      curve: Motion.snap,
      width: 30,
      height: 30,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: lit ? p.clay : Colors.transparent,
        borderRadius: BorderRadius.circular(Corner.control),
      ),
      child: Icon(
        tool.icon,
        size: 16,
        color: lit ? p.paper : p.paper.withValues(alpha: 0.7),
      ),
    );

    if (tool.isMomentary) {
      // Listener, not GestureDetector: this must not wait to find out
      // whether the press becomes a tap, a drag or a long-press.
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          setState(() => _held = true);
          tool.onHoldStart?.call();
        },
        onPointerUp: (_) {
          setState(() => _held = false);
          tool.onHoldEnd?.call();
        },
        onPointerCancel: (_) {
          setState(() => _held = false);
          tool.onHoldEnd?.call();
        },
        child: icon,
      );
    }

    return Tooltip(
      message: tool.hint ?? tool.name,
      preferBelow: false,
      triggerMode: TooltipTriggerMode.longPress,
      verticalOffset: 20,
      textStyle: Type.label.copyWith(color: p.ink),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(Corner.control),
        border: Border.all(color: p.ink, width: Stroke.standard),
        boxShadow: Elevation.raised.shadows(p.ink),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: icon,
      ),
    );
  }
}

// ===== Tape measure ===== //

/// A ruler that moves under a fixed line, rather than a thumb that moves
/// along a track.
///
/// [DeskRuler] maps a finger position onto a range, which is exactly right
/// when the range is small and visible - a brush from 4 to 140. It falls
/// apart when the range is large or open-ended: a LoRA strength runs from
/// -100 to 100 but is used between -2 and 2, so on a phone-width track every
/// value anyone wants lives inside four pixels.
///
/// Three decisions make this one work, all of them learned by getting them
/// wrong first:
///
///  1. **The tape follows the finger.** Drag right and the tape goes right,
///     which brings the numbers on its left onto the line - so dragging
///     right *lowers* the value, the way dragging a map right shows you what
///     was to the west. Driving it the other way round (finger right, value
///     up, marks sliding left underneath) is the one thing that reliably
///     reads as broken: the object visibly disagrees with the hand.
///  2. **Precision is a lane you move into, and the lanes are drawn.** While
///     dragging, the finer steps appear as stacked lanes above the strip and
///     light up as the finger rises into them. An invisible "drag up for
///     precision" rule is a secret; a lane you can see is a place.
///  3. **A drag never snaps on its first pixel.** The value holds until the
///     finger has travelled half a step, so beginning a coarse drag from a
///     finely-tuned value does not immediately throw the fine part away.
class DeskTape extends StatefulWidget {
  final String label;
  final double value;

  /// Soft ends. The tape still draws past them - they are shaded, not
  /// missing - but the value stops. Null on a side means genuinely open.
  final double? min;
  final double? max;

  /// Coarse first. [steps].first is what a plain sideways drag moves in;
  /// each further entry is a finer lane, reached by dragging upwards.
  final List<double> steps;

  final ValueChanged<double> onChanged;
  final String Function(double) format;

  const DeskTape({
    super.key,
    required this.label,
    required this.value,
    required this.steps,
    required this.onChanged,
    required this.format,
    this.min,
    this.max,
  });

  @override
  State<DeskTape> createState() => _DeskTapeState();
}

class _DeskTapeState extends State<DeskTape>
    with SingleTickerProviderStateMixin {
  /// Pixels the tape travels per tick, whatever the tick is worth. Holding
  /// this constant is what makes a finer step *feel* finer: the tape simply
  /// travels less far for the same movement of the hand.
  static const _tickGap = 22.0;
  static const _stripHeight = 46.0;
  static const _laneHeight = 34.0;

  /// The nudge pads at either end of the strip.
  static const _padWidth = 36.0;

  /// How far up the finger has to be for each lane, measured to match where
  /// the lanes are actually drawn.
  static const _laneStartsAt = 26.0;

  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 220),
  );

  final _link = LayerLink();
  OverlayEntry? _hud;

  int _level = 0;

  /// Unsnapped value while dragging, and the value the drag began from. The
  /// second is what lets the tape hold still until the finger has actually
  /// committed to a step.
  double? _raw;
  double _from = 0;
  double _originY = 0;
  double _stripWidth = 0;

  List<double> get _steps => widget.steps.isEmpty ? const [1.0] : widget.steps;
  double get _step => _steps[_level.clamp(0, _steps.length - 1)];
  double get _pixelsPerUnit => _tickGap / _step;

  /// What the line is reading. Idle, that is simply the value it was given -
  /// re-snapping a stored 3.2 onto the coarse grid was what made a fine
  /// adjustment appear to jump back the moment the finger lifted.
  double get _shown {
    final raw = _raw;
    if (raw == null) return widget.value;
    if ((raw - _from).abs() < _step / 2) return _from;
    return _snap(raw);
  }

  double _clamp(double v) {
    var out = v;
    if (widget.min != null) out = math.max(out, widget.min!);
    if (widget.max != null) out = math.min(out, widget.max!);
    return out;
  }

  double _snap(double v) {
    final snapped = (v / _step).round() * _step;
    // Rounded to the step's own decimals: tenths accumulated in floating
    // point otherwise land on 2.7000000000000006 and reach the workflow.
    return double.parse(_clamp(snapped).toStringAsFixed(4));
  }

  @override
  void dispose() {
    _removeHud();
    _lift.dispose();
    super.dispose();
  }

  // ===== The lane HUD ===== //

  void _showHud() {
    if (_hud != null || _steps.length < 2) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _hud = OverlayEntry(builder: _buildHud);
    overlay.insert(_hud!);
  }

  void _removeHud() {
    _hud?.remove();
    _hud = null;
  }

  Widget _buildHud(BuildContext context) {
    final p = DeskTheme.of(this.context);
    return Positioned(
      width: _stripWidth,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
        offset: const Offset(0, -Space.sm),
        child: AnimatedBuilder(
          animation: _lift,
          builder: (context, child) {
            final t = Curves.easeOutBack.transform(_lift.value.clamp(0, 1));
            return Opacity(
              opacity: _lift.value.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 14),
                child: child,
              ),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Finest at the top, so the stack matches the hand: the
                // further you reach, the finer it gets.
                for (var i = _steps.length - 1; i >= 1; i--) _lane(p, i),
                _lane(p, 0, readout: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lane(DeskPalette p, int index, {bool readout = false}) {
    final active = _level == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Motion.snap,
      height: _laneHeight,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: active ? p.clay : p.paper,
        borderRadius: BorderRadius.circular(Corner.control),
        border: Border.all(color: p.ink, width: Stroke.standard),
        boxShadow: (active ? Elevation.raised : Elevation.rest).shadows(p.ink),
      ),
      child: Row(
        children: [
          if (readout) ...[
            Expanded(
              child: Text(
                widget.format(_shown),
                style: Type.value.copyWith(
                    color: active ? p.paper : p.ink, fontSize: 18),
              ),
            ),
          ] else
            const Spacer(),
          Text('±${widget.format(_steps[index])}',
              style: Type.micro.copyWith(color: active ? p.paper : p.inkFaint)),
        ],
      ),
    );
  }

  // ===== Gesture ===== //

  void _start(DragStartDetails details) {
    HapticFeedback.selectionClick();
    setState(() {
      _level = 0;
      _from = widget.value;
      _raw = widget.value;
      _originY = details.globalPosition.dy;
    });
    _lift.forward();
    _showHud();
  }

  void _update(DragUpdateDetails details) {
    final up = _originY - details.globalPosition.dy;
    var level = 0;
    for (var i = 1; i < _steps.length; i++) {
      if (up >= _laneStartsAt + (i - 1) * _laneHeight) level = i;
    }
    if (level != _level) {
      HapticFeedback.mediumImpact();
      // Re-base on where the tape actually is, so changing lanes never
      // moves the value on its own.
      _from = _shown;
      _raw = _from;
      _level = level;
    }

    final before = _shown;
    // Minus: the tape goes where the finger goes, so the numbers under the
    // line run the other way.
    _raw = _clamp(_raw! - details.delta.dx / _pixelsPerUnit);
    final now = _shown;
    if (now != before) HapticFeedback.selectionClick();
    setState(() {});
    _hud?.markNeedsBuild();
    if (now != widget.value) widget.onChanged(now);
  }

  void _end() {
    _lift.reverse();
    _removeHud();
    setState(() {
      _raw = null;
      _level = 0;
    });
  }

  void _nudge(double by) {
    final step = _steps.first;
    final next = double.parse(
        _clamp(((widget.value + by * step) / step).round() * step)
            .toStringAsFixed(4));
    if (next == widget.value) return;
    HapticFeedback.selectionClick();
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Shrink-wrapped: a loose parent would otherwise stretch the column
      // and leave the strip floating at the top of a tall empty box.
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label.toUpperCase(),
                  style: Type.micro.copyWith(color: p.inkFaint)),
            ),
            AnimatedBuilder(
              animation: _lift,
              builder: (context, _) => Text(
                widget.format(_shown),
                style: Type.readout.copyWith(
                  color: Color.lerp(p.ink, p.clay, _lift.value),
                  fontSize: 12 + 2 * _lift.value,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            _stripWidth = constraints.maxWidth;
            return CompositedTransformTarget(
              link: _link,
              child: SizedBox(
                height: _stripHeight,
                child: Row(
                  children: [
                    _pad(p, -1, Icons.remove_rounded),
                    Expanded(child: _strip(p)),
                    _pad(p, 1, Icons.add_rounded),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// A step either way without a drag at all, and the fastest way to make a
  /// one-notch correction.
  Widget _pad(DeskPalette p, int direction, IconData icon) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _nudge(direction.toDouble()),
        child: SizedBox(
          width: _padWidth,
          height: _stripHeight,
          child: Icon(icon, size: 16, color: p.inkMuted),
        ),
      );

  Widget _strip(DeskPalette p) => AnimatedBuilder(
        animation: _lift,
        builder: (context, _) {
          final t = _lift.value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A horizontal recogniser, not a pan: this lives inside a
            // vertically scrolling page, and only the horizontal one can
            // win that arena. Once it has, the finger is free to travel
            // upwards - which is where the precision lanes are.
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            child: Container(
              decoration: BoxDecoration(
                color: p.paperEdge,
                borderRadius: BorderRadius.circular(Corner.photo),
                border: Border.all(
                  color: Color.lerp(p.ink, p.clay, t)!,
                  width: Stroke.standard + t,
                ),
                boxShadow:
                    Elevation.lerp(Elevation.rest, Elevation.raised, t)
                        .shadows(p.ink),
              ),
              padding: const EdgeInsets.all(Stroke.standard),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                    (Corner.photo - Stroke.standard).clamp(0, Corner.photo)),
                child: CustomPaint(
                  painter: _TapePainter(
                    value: _shown,
                    step: _step,
                    pixelsPerUnit: _pixelsPerUnit,
                    min: widget.min,
                    max: widget.max,
                    ink: p.ink,
                    faint: p.inkFaint,
                    clay: p.clay,
                    edge: p.paperEdge,
                    beyond: p.ink.withValues(alpha: 0.07),
                    engaged: t,
                    format: widget.format,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      );
}

class _TapePainter extends CustomPainter {
  final double value;
  final double step;
  final double pixelsPerUnit;
  final double? min;
  final double? max;
  final Color ink;
  final Color faint;
  final Color clay;
  final Color edge;
  final Color beyond;

  /// 0 at rest, 1 mid-drag. Drives everything that should wake up under the
  /// finger, so the tape reads as live rather than as a picture of a tape.
  final double engaged;

  final String Function(double) format;

  const _TapePainter({
    required this.value,
    required this.step,
    required this.pixelsPerUnit,
    required this.min,
    required this.max,
    required this.ink,
    required this.faint,
    required this.clay,
    required this.edge,
    required this.beyond,
    required this.engaged,
    required this.format,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    double xOf(double v) => centre + (v - value) * pixelsPerUnit;

    // Past an end the tape keeps going, dimmed. Stopping the marks dead
    // would read as a rendering fault; a shaded run reads as "there is
    // nothing for you over here".
    if (min != null) {
      final at = xOf(min!);
      if (at > 0) {
        canvas.drawRect(
            Rect.fromLTRB(0, 0, math.min(at, size.width), size.height),
            Paint()..color = beyond);
      }
    }
    if (max != null) {
      final at = xOf(max!);
      if (at < size.width) {
        canvas.drawRect(
            Rect.fromLTRB(math.max(at, 0), 0, size.width, size.height),
            Paint()..color = beyond);
      }
    }

    final minor = Paint()
      ..color = faint
      ..strokeWidth = Stroke.standard;
    final major = Paint()
      ..color = ink
      ..strokeWidth = Stroke.standard + engaged * 0.5;

    final span = (size.width / 2) / pixelsPerUnit;
    final first = ((value - span) / step).floor();
    final last = ((value + span) / step).ceil();
    // Fixed tick spacing caps this whatever the step, but a malformed step
    // should not be able to hang the frame.
    if (last - first > 200) return;

    for (var n = first; n <= last; n++) {
      final v = n * step;
      final x = xOf(v);
      if (x < -24 || x > size.width + 24) continue;
      final isMajor = n % 5 == 0;
      final height = (isMajor ? 0.42 : 0.22) * size.height;
      canvas.drawLine(
          Offset(x, 0), Offset(x, height), isMajor ? major : minor);
      if (!isMajor) continue;

      final painter = TextPainter(
        text: TextSpan(
          text: format(double.parse(v.toStringAsFixed(4))),
          style: Type.micro.copyWith(color: faint),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(x - painter.width / 2, size.height - painter.height - 3),
      );
    }

    // Both ends fade out, which is the whole claim of the control: the tape
    // has no ends, you are only ever looking at part of it.
    const fade = 26.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fade, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(fade, 0),
          [edge, edge.withValues(alpha: 0)],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - fade, 0, fade, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width - fade, 0),
          Offset(size.width, 0),
          [edge.withValues(alpha: 0), edge],
        ),
    );

    // The line the value is read against, and a tab above it so the eye
    // finds it before it finds the numbers. Both grow under the finger.
    final marker = Paint()..color = clay;
    final thickness = 2 + engaged;
    canvas.drawRect(
        Rect.fromLTWH(centre - thickness / 2, 0, thickness, size.height),
        marker);
    final tab = 5 + engaged * 3;
    canvas.drawPath(
      Path()
        ..moveTo(centre - tab, 0)
        ..lineTo(centre + tab, 0)
        ..lineTo(centre, tab * 1.4)
        ..close(),
      marker,
    );
  }

  @override
  bool shouldRepaint(_TapePainter old) =>
      old.value != value ||
      old.step != step ||
      old.pixelsPerUnit != pixelsPerUnit ||
      old.engaged != engaged ||
      old.ink != ink ||
      old.clay != clay;
}
