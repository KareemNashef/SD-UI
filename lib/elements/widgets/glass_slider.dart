import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// A premium, glassmorphic slider with a gradient track and glowing thumb.
class GlassSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Function(double) onChanged;
  final String Function(double)? valueFormatter;
  final Color? accentColor;

  const GlassSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.valueFormatter,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    // Formatting logic
    final displayValue =
        valueFormatter?.call(value) ??
        value.toStringAsFixed(divisions != null ? 0 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: Label and Value Pill
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),

              // Value Display Capsule
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  // Darker glass background
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: effectiveAccent.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: effectiveAccent.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Text(
                  displayValue,
                  style: TextStyle(
                    color: effectiveAccent, // Text glows with accent color
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'monospace', // Tech/Data feel
                    shadows: [
                      BoxShadow(
                        color: effectiveAccent.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // The Custom Slider
        SizedBox(
          height: 40, // Height for the touch target/thumb glow
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              // Custom Shape for Gradient Track
              trackShape: _GradientGlassTrackShape(
                gradient: LinearGradient(
                  colors: [
                    effectiveAccent.withValues(alpha: 0.7),
                    effectiveAccent,
                    AppTheme.accentSecondary,
                  ],
                ),
                darkenInactive: true,
              ),
              // Custom Shape for Glowing Thumb
              thumbShape: _NeonGlassThumbShape(
                color: effectiveAccent,
                ringColor: Colors.white,
                thumbRadius: 12,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              overlayColor: effectiveAccent.withValues(alpha: 0.1),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== Custom Painters ==================== //

/// Paints a track with a gradient active segment and a "sunken" inactive segment
class _GradientGlassTrackShape extends SliderTrackShape {
  final Gradient gradient;
  final bool darkenInactive;

  const _GradientGlassTrackShape({
    required this.gradient,
    this.darkenInactive = true,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 6;
    final double trackLeft = offset.dx + 8; // Padding for thumb start
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth =
        parentBox.size.width - 16; // Padding for thumb end
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Radius radius = Radius.circular(trackRect.height / 2);

    // 1. Paint Inactive Track (The "Trough")
    // We paint the whole width as inactive first
    final Paint inactivePaint = Paint()
      ..color = AppTheme.surfaceOverlay.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Add an inner shadow feel by drawing a darker border on top
    final Paint troughBorder = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), inactivePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), troughBorder);

    // 2. Paint Active Track (The "Light Beam")
    // Calculate width based on thumb position
    final double activeWidth = thumbCenter.dx - trackRect.left;
    final Rect activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      activeWidth,
      trackRect.height,
    );

    if (activeWidth > 0) {
      final Paint activePaint = Paint()
        ..shader = gradient.createShader(trackRect)
        ..style = PaintingStyle.fill;

      // Add a subtle glow to the track itself
      final Paint activeGlow = Paint()
        ..color = sliderTheme.activeTrackColor!.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      // Draw Glow
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect.inflate(1), radius),
        activeGlow,
      );

      // Draw Gradient Fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        activePaint,
      );
    }
  }
}

/// Paints a thumb that looks like a glass/metal bead with a neon core
class _NeonGlassThumbShape extends SliderComponentShape {
  final Color color;
  final Color ringColor;
  final double thumbRadius;

  const _NeonGlassThumbShape({
    required this.color,
    this.ringColor = Colors.white,
    this.thumbRadius = 12.0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Use activation animation to grow the thumb slightly when user touches it
    final double scale = 1.0 + (activationAnimation.value * 0.15);
    final double currentRadius = thumbRadius * scale;

    // 1. Drop Shadow (lifts the bead off the glass)
    final shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: currentRadius));
    canvas.drawShadow(shadowPath, Colors.black, 4, true);

    // 2. Outer Glow (The "Neon" effect)
    final Paint glowPaint = Paint()
      ..color = color.withValues(alpha: 0.5 + (activationAnimation.value * 0.3))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, currentRadius + 2, glowPaint);

    // 3. Solid White Ring (The "Container")
    final Paint ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, currentRadius, ringPaint);

    // 4. Inner Gradient Core (The "Energy")
    // Just slightly smaller than the ring
    final double innerRadius = currentRadius - 2.5;
    final Rect innerRect = Rect.fromCircle(center: center, radius: innerRadius);
    final Paint innerPaint = Paint()
      ..shader = RadialGradient(
        colors: [color, Color.lerp(color, Colors.black, 0.4)!],
        stops: const [0.0, 1.0],
      ).createShader(innerRect);
    canvas.drawCircle(center, innerRadius, innerPaint);

    // 5. Specular Highlight (The "Glass" Reflection)
    // A small white oval on top-left
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromLTWH(
        center.dx - (innerRadius * 0.5),
        center.dy - (innerRadius * 0.6),
        innerRadius * 0.5,
        innerRadius * 0.35,
      ),
      highlightPaint,
    );
  }
}
