// ==================== Glass Container ==================== //

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// A reusable glassmorphism container with backdrop blur
class GlassContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool applyBlur;
  final double blurSigma;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppTheme.radiusLarge,
    this.padding,
    this.margin,
    this.applyBlur = false,
    this.blurSigma = AppTheme.blurSigma,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.glassBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1)
            : null,
        boxShadow: boxShadow,
      ),
      padding: padding,
      margin: margin,
      child: child,
    );

    if (applyBlur) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    }

    return content;
  }
}
