// ==================== Glass Container ==================== //

// Flutter imports
import 'dart:ui';
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Container Implementation

/// Aperture's base material: a translucent panel with a soft top-left
/// highlight (simulating light catching curved glass) and an optional
/// [tint] that pulls the border/glow toward a backend or semantic color.
///
/// [blurred] defaults to false - real backdrop blur is genuinely expensive
/// when there are many instances on screen at once (a grid of thumbnails,
/// a long settings list), so it's reserved for the handful of persistent,
/// non-repeated chrome surfaces (the dock, the context strip, the prompt
/// capsule, modal sheets) that opt in explicitly. Everywhere else gets the
/// same gradient/highlight/border treatment without the blur pass - still
/// reads as glass, costs nothing extra to scroll past.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? boxShadow;
  final bool blurred;
  final Color? tint;

  const GlassContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppTheme.radiusLarge,
    this.padding,
    this.margin,
    this.boxShadow,
    this.blurred = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final base = backgroundColor ?? AppTheme.glassBackground;
    final border = borderColor ?? (tint != null ? tint!.withValues(alpha: 0.4) : AppTheme.glassBorder);

    Widget surface = Container(
      decoration: BoxDecoration(
        color: base,
        borderRadius: radius,
        border: Border.all(color: border, width: 1),
      ),
      child: Stack(
        children: [
          // Top-left highlight + bottom-right falloff - the static stand-in
          // for a specular reflection, cheap enough to run everywhere.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.mist.withValues(alpha: 0.10),
                    AppTheme.mist.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.06),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          if (tint != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.3,
                    colors: [tint!.withValues(alpha: 0.14), Colors.transparent],
                  ),
                ),
              ),
            ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );

    if (blurred) {
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppTheme.glassBlurRegular, sigmaY: AppTheme.glassBlurRegular),
          child: surface,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: boxShadow != null
          ? BoxDecoration(borderRadius: radius, boxShadow: boxShadow)
          : null,
      child: surface,
    );
  }
}
