// ==================== Glass Container ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Container Implementation

/// A reusable glassmorphism container
/// OPTIMIZED: Blur removed by default, simplified decoration
class GlassContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppTheme.radiusLarge,
    this.padding,
    this.margin,
    this.boxShadow,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: backgroundColor ?? AppTheme.glassBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: borderColor != null
          ? Border.all(color: borderColor!, width: 1)
          : null,
      boxShadow: boxShadow,
    );

    Widget content = Container(
      decoration: decoration,
      padding: padding,
      margin: margin,
      child: child,
    );

    return content;
  }
}
