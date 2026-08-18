// ==================== Ambient Field ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Ambient Field Implementation
//
// The slow-drifting color blobs every glass panel in the app sits above -
// without something moving behind it, blur is just a soft grey haze; this
// is what gives it something to actually catch. Three blurred circles,
// tinted toward the active backend, drifting slowly. Respects the OS-level
// "reduce motion" setting (MediaQuery.disableAnimations) by freezing in
// place instead of animating.
class AmbientField extends StatefulWidget {
  const AmbientField({super.key});

  @override
  State<AmbientField> createState() => _AmbientFieldState();
}

class _AmbientFieldState extends State<AmbientField> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 34))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final tint = AppTheme.accentPrimary;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppTheme.ink),
        child: reduceMotion
            ? _AmbientBlobs(t: 0, tint: tint)
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => _AmbientBlobs(t: _controller.value, tint: tint),
              ),
      ),
    );
  }
}

class _AmbientBlobs extends StatelessWidget {
  final double t; // 0..1 loop position
  final Color tint;

  const _AmbientBlobs({required this.t, required this.tint});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    double wave(double phase, double speed) => (0.5 + 0.5 * (((t * speed + phase) % 1.0) * 2 - 1).abs());

    return Stack(
      children: [
        Positioned(
          left: -size.width * 0.3 + wave(0.0, 1.0) * size.width * 0.25,
          top: -size.height * 0.12,
          child: _Blob(diameter: size.width * 1.3, color: tint.withValues(alpha: 0.20)),
        ),
        Positioned(
          right: -size.width * 0.35 + wave(0.4, 1.3) * size.width * 0.2,
          top: size.height * 0.22,
          child: _Blob(diameter: size.width * 1.05, color: AppTheme.comfyTint.withValues(alpha: 0.10)),
        ),
        Positioned(
          left: size.width * 0.05 + wave(0.7, 0.8) * size.width * 0.2,
          bottom: -size.height * 0.2,
          child: _Blob(diameter: size.width * 1.15, color: AppTheme.forgeTint.withValues(alpha: 0.08)),
        ),
        // Vignette so glass panels near the edges stay legible.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.1,
                colors: [Colors.transparent, AppTheme.ink.withValues(alpha: 0.55), AppTheme.ink.withValues(alpha: 0.85)],
                stops: const [0.0, 0.75, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final double diameter;
  final Color color;

  const _Blob({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
