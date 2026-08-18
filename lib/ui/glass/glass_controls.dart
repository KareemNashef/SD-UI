// ==================== Glass Controls ==================== //

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'package:sd_companion/ui/glass/glass_tokens.dart';
import 'package:sd_companion/ui/glass/liquid_glass.dart';

/// The app's interactive controls, all cut from the same glass.
///
/// The thing that makes these feel like glass rather than like buttons with
/// a blur behind them is that pressing one *changes its optics*: the slab
/// gets thinner and the light swings toward the touch, so the pane visibly
/// flexes under a finger. That is animated on the real settings, not faked
/// with an opacity change.

/// Press-driven glass settings, shared by every control here.
mixin _PressableGlass<T extends StatefulWidget> on State<T> {
  bool pressed = false;
  double lightAngle = GlassWeight.defaultLightAngle;

  void press(bool value) {
    if (pressed == value) return;
    if (value) HapticFeedback.lightImpact();
    setState(() => pressed = value);
  }

  /// Aims the specular highlight at a local point.
  void aimLight(Offset local, Size size) {
    final dx = local.dx - size.width / 2;
    final dy = local.dy - size.height / 2;
    if (dx == 0 && dy == 0) return;
    setState(() => lightAngle = math.atan2(dy, dx));
  }

  /// Pressed glass reads thinner and brighter, as though compressed.
  double get pressedScale => pressed ? 0.97 : 1.0;
}

// ===== Button ===== //

class GlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? tint;
  final bool filled;
  final GlassWeight weight;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tint,
    this.filled = false,
    this.weight = GlassWeight.lens,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> with _PressableGlass {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final accent = widget.tint ?? Palette.chalk;

    return Listener(
      onPointerDown: (e) {
        if (!enabled) return;
        press(true);
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) aimLight(e.localPosition, box.size);
      },
      onPointerMove: (e) {
        if (!enabled || !pressed) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) aimLight(e.localPosition, box.size);
      },
      onPointerUp: (_) {
        if (!enabled) return;
        press(false);
        widget.onPressed!.call();
      },
      onPointerCancel: (_) => press(false),
      child: AnimatedScale(
        scale: pressedScale,
        duration: Motion.press,
        curve: Motion.ease,
        child: GlassSurface(
          weight: widget.weight,
          radius: Radii.pill,
          tint: widget.filled ? accent : null,
          lightAngle: lightAngle,
          child: Container(
            height: 48, // above the 44pt minimum
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: 18,
                      color: enabled ? accent : Palette.chalk40),
                  const SizedBox(width: Space.sm),
                ],
                Text(
                  widget.label,
                  style: Type.label.copyWith(
                    color: enabled ? Palette.chalk : Palette.chalk40,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Slider ===== //

/// A slider whose thumb is itself a bead of glass.
class GlassSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double)? format;
  final Color? tint;

  const GlassSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.format,
    this.tint,
  });

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> with _PressableGlass {
  @override
  Widget build(BuildContext context) {
    final accent = widget.tint ?? Palette.chalk;
    final t = ((widget.value - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0);
    final text = widget.format?.call(widget.value) ??
        widget.value.toStringAsFixed(widget.divisions == null ? 2 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label, style: Type.label)),
            // Every numeral in the app is mono, so columns of these line up
            // and a value changing under a drag doesn't jitter its width.
            Text(text, style: Type.readout),
          ],
        ),
        const SizedBox(height: Space.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            const thumb = 30.0;
            final travel = constraints.maxWidth - thumb;

            return SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 17,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Palette.chalk08,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  // Filled portion
                  Positioned(
                    left: 0,
                    top: 17,
                    child: Container(
                      width: (travel * t) + thumb / 2,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  // Glass thumb
                  Positioned(
                    left: travel * t,
                    top: 5,
                    child: AnimatedScale(
                      scale: pressed ? 1.15 : 1.0,
                      duration: Motion.press,
                      curve: Motion.ease,
                      child: GlassSurface(
                        weight: GlassWeight.prism,
                        radius: thumb / 2,
                        tint: accent,
                        lightAngle: lightAngle,
                        child: const SizedBox.square(dimension: thumb),
                      ),
                    ),
                  ),
                  // Gesture surface over the whole track
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) {
                        press(true);
                        _emit(d.localPosition.dx, travel, thumb);
                      },
                      onHorizontalDragUpdate: (d) =>
                          _emit(d.localPosition.dx, travel, thumb),
                      onHorizontalDragEnd: (_) => press(false),
                      onTapDown: (d) => _emit(d.localPosition.dx, travel, thumb),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _emit(double dx, double travel, double thumb) {
    final raw = ((dx - thumb / 2) / travel).clamp(0.0, 1.0);
    var next = widget.min + raw * (widget.max - widget.min);
    if (widget.divisions != null) {
      final step = (widget.max - widget.min) / widget.divisions!;
      next = widget.min + (((next - widget.min) / step).round() * step);
    }
    // Swing the light with the thumb, so the bead looks lit from where it is.
    setState(() => lightAngle = GlassWeight.defaultLightAngle + raw * math.pi);
    widget.onChanged(next);
  }
}

// ===== Segmented selector ===== //

/// A segmented control. All segments share one glass layer so the selected
/// pane can blend with its neighbours instead of floating separately.
class GlassSegmented<T> extends StatefulWidget {
  final List<GlassSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final Color? tint;

  const GlassSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.tint,
  });

  @override
  State<GlassSegmented<T>> createState() => _GlassSegmentedState<T>();
}

class GlassSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const GlassSegment({required this.value, required this.label, this.icon});
}

class _GlassSegmentedState<T> extends State<GlassSegmented<T>> {
  @override
  Widget build(BuildContext context) {
    final accent = widget.tint ?? Palette.chalk;

    return GlassSurface(
      weight: GlassWeight.vapor,
      radius: Radii.pill,
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          for (final segment in widget.segments)
            Expanded(
              child: _Segment(
                segment: segment,
                selected: segment.value == widget.value,
                accent: accent,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onChanged(segment.value);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  final GlassSegment<T> segment;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Segment({
    required this.segment,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (segment.icon != null) ...[
            Icon(segment.icon,
                size: 16, color: selected ? Palette.chalk : Palette.chalk40),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              segment.label,
              overflow: TextOverflow.ellipsis,
              style: Type.label.copyWith(
                fontSize: 12.5,
                color: selected ? Palette.chalk : Palette.chalk40,
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: selected
          // Only the selected segment is a real pane of glass - the rest are
          // just holes in the track, which is what makes the selection read.
          ? GlassSurface(
              weight: GlassWeight.lens,
              radius: Radii.pill,
              tint: accent,
              child: content,
            )
          : content,
    );
  }
}

// ===== Switch ===== //

class GlassSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? tint;

  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.tint,
  });

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> with _PressableGlass {
  @override
  Widget build(BuildContext context) {
    final accent = widget.tint ?? Palette.chalk;
    const w = 62.0, h = 36.0, knob = 28.0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onChanged(!widget.value);
      },
      onTapDown: (_) => press(true),
      onTapUp: (_) => press(false),
      onTapCancel: () => press(false),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            // Track: tints toward the accent when on.
            AnimatedContainer(
              duration: Motion.pane,
              curve: Motion.ease,
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: widget.value
                    ? accent.withValues(alpha: 0.35)
                    : Palette.chalk08,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(
                  color: widget.value
                      ? accent.withValues(alpha: 0.6)
                      : Palette.chalk15,
                ),
              ),
            ),
            AnimatedPositioned(
              duration: Motion.pane,
              curve: Motion.rise,
              left: widget.value ? w - knob - 4 : 4,
              top: (h - knob) / 2,
              child: AnimatedScale(
                scale: pressed ? 0.9 : 1.0,
                duration: Motion.press,
                child: GlassSurface(
                  weight: GlassWeight.prism,
                  radius: knob / 2,
                  tint: widget.value ? accent : null,
                  child: const SizedBox.square(dimension: knob),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Glow wrapper ===== //

/// Touch-responsive glow, from the package. Used on the primary action so
/// it feels alive under a finger.
class GlassGlowWrap extends StatelessWidget {
  final Widget child;
  final Color color;

  const GlassGlowWrap({super.key, required this.child, required this.color});

  @override
  Widget build(BuildContext context) =>
      GlassGlow(glowColor: color, child: child);
}

// ==================== Field ==================== //

/// A text input framed in glass.
///
/// The material can't sit *behind* live text - the refraction pass would
/// bend the glyphs along with the backdrop and make them unreadable. So the
/// glass forms the frame and the text sits on a quiet well inside it, which
/// is the same compromise Apple's own search fields make.
class GlassField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const GlassField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      weight: GlassWeight.vapor,
      radius: Radii.well,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: Type.micro),
          const SizedBox(height: Space.xs),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: onChanged,
            cursorColor: Palette.iris,
            style: Type.body.copyWith(color: Palette.chalk),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: hint,
              hintStyle: Type.body.copyWith(color: Palette.chalk40),
            ),
          ),
        ],
      ),
    );
  }
}
