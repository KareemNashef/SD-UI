// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

class GlassSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Function(double) onChanged;
  final Function(double)? onChangeEnd;
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
    this.onChangeEnd,
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
        // Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Label
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),

              // Modern Value Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: effectiveAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  displayValue,
                  style: TextStyle(
                    color: effectiveAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Slider Container
        SizedBox(
          height: 30,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              // Modern Capsule Track
              trackShape: _ModernCapsuleTrackShape(
                gradient: LinearGradient(
                  colors: [
                    effectiveAccent.withValues(alpha: 0.5),
                    effectiveAccent,
                  ],
                ),
              ),
              // Sleek White Pill/Circle Thumb
              thumbShape: _SleekThumbShape(
                thumbRadius: 10,
                color: Colors.white,
                borderColor: effectiveAccent, // Optional colored ring
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              overlayColor: effectiveAccent.withValues(alpha: 0.08),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== Modern Painters ==================== //

class _ModernCapsuleTrackShape extends SliderTrackShape {
  final Gradient gradient;

  const _ModernCapsuleTrackShape({required this.gradient});

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 6;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
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

    // 1. Inactive Track (Subtle Grey/Dark background)
    final Paint inactivePaint = Paint()
      ..color = Colors.grey
          .withValues(alpha: 0.15) // Clean grey, no borders
      ..style = PaintingStyle.fill;

    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), inactivePaint);

    // 2. Active Track (Gradient)
    final double activeWidth = thumbCenter.dx - trackRect.left;
    final Rect activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      activeWidth,
      trackRect.height,
    );

    if (activeWidth > 0) {
      final Paint activePaint = Paint()
        ..shader = gradient.createShader(activeRect)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        activePaint,
      );
    }
  }
}

class _SleekThumbShape extends SliderComponentShape {
  final double thumbRadius;
  final Color color;
  final Color borderColor;

  const _SleekThumbShape({
    this.thumbRadius = 10.0,
    required this.color,
    required this.borderColor,
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

    // Subtle animation on touch (scale up slightly)
    final double currentRadius = thumbRadius + (activationAnimation.value * 2);

    // 1. Soft Shadow (Elevation)
    // Standard sleek UI shadow
    final Path shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: currentRadius));

    canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.5), 3, true);

    // 2. Main Thumb Body (Solid White/Color)
    final Paint thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, currentRadius, thumbPaint);

    // 3. Subtle Border/Stroke (Matches accent color for integration)
    if (activationAnimation.value > 0.1) {
      final Paint borderPaint = Paint()
        ..color = borderColor.withValues(alpha: activationAnimation.value)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, currentRadius, borderPaint);
    }
  }
}
