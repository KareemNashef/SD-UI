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
        value.toStringAsFixed(divisions != null ? 0 : 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Label
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
            
            // Value Chip (Digital/Tech look)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.cyan.shade700.withValues(alpha: 0.5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.shade900.withValues(alpha: 0.2),
                    blurRadius: 8,
                  )
                ],
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: Colors.cyan.shade300,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'monospace', // Prevents jitter when numbers change
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Slider
        SizedBox(
          height: 30, // constrain height to keep it tight
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              trackShape: const RoundedRectSliderTrackShape(),
              
              // Colors
              activeTrackColor: Colors.cyan.shade400,
              inactiveTrackColor: Colors.black.withValues(alpha: 0.4),
              thumbColor: Colors.white,
              overlayColor: Colors.cyan.shade400.withValues(alpha: 0.1),
              
              // Shapes
              thumbShape: _ModernThumbShape(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
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

// Custom Painter for the "Glowing LED" Thumb
class _ModernThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(24, 24);
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

    // 1. Ambient Glow (Wide and soft)
    final outerGlow = Paint()
      ..color = Colors.cyan.shade400.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, 14, outerGlow);

    // 2. Intense Core Glow (Tight)
    final innerGlow = Paint()
      ..color = Colors.cyan.shade300.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, 10, innerGlow);

    // 3. The Metal Ring (White border)
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 9, ringPaint);

    // 4. The Gradient Core (Cyan -> Teal)
    final gradientPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.cyan.shade200, Colors.teal.shade500],
        stops: const [0.2, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 7));
    canvas.drawCircle(center, 7, gradientPaint);

    // 5. Specular Highlight (The shiny dot)
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(center.translate(-2.5, -2.5), 2.0, highlight);
  }
}