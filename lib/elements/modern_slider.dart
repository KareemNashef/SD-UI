// ==================== Modern Slider Widget ==================== //

import 'package:flutter/material.dart';

class ModernSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Function(double) onChanged;
  final String Function(double)? valueFormatter;

  const ModernSlider({
    Key? key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.valueFormatter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final displayValue =
        valueFormatter?.call(value) ??
        value.toStringAsFixed(divisions != null ? 2 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with integrated value chip
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.cyan.shade400.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.cyan.shade400.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: Colors.cyan.shade100,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Modern rail-style slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: _ModernThumbShape(),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            activeTrackColor: Colors.cyan.shade400,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            thumbColor: Colors.white,
            overlayColor: Colors.cyan.shade400.withValues(alpha: 0.2),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// Modern thumb with glow effect
class _ModernThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(22, 22);
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

    // Outer glow
    final outerGlow = Paint()
      ..color = Colors.cyan.shade400.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, 16, outerGlow);

    // Inner glow
    final innerGlow = Paint()
      ..color = Colors.cyan.shade300.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center, 12, innerGlow);

    // White outer ring
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 11, ringPaint);

    // Cyan gradient center
    final gradientPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.cyan.shade200, Colors.cyan.shade500],
      ).createShader(Rect.fromCircle(center: center, radius: 8));
    canvas.drawCircle(center, 8, gradientPaint);

    // Highlight spot
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.8);
    canvas.drawCircle(center.translate(-2, -2), 2.5, highlight);
  }
}
