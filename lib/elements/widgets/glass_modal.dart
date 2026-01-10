// ==================== Glass Modal ==================== //

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_drag_handle.dart';

/// A standard glassmorphism modal bottom sheet wrapper
class GlassModal extends StatelessWidget {
  final Widget child;
  final double heightFactor;
  final bool showDragHandle;
  final Color? backgroundColor;
  final Color? borderColor;

  const GlassModal({
    super.key,
    required this.child,
    this.heightFactor = AppTheme.modalHeightFactor,
    this.showDragHandle = true,
    this.backgroundColor,
    this.borderColor,
  });

  static void show(
    BuildContext context, {
    required Widget child,
    double heightFactor = AppTheme.modalHeightFactor,
    bool showDragHandle = true,
    Color? backgroundColor,
    Color? borderColor,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => GlassModal(
        heightFactor: heightFactor,
        showDragHandle: showDragHandle,
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: heightFactor,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.modalBorderRadius),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppTheme.blurSigma,
            sigmaY: AppTheme.blurSigma,
          ),
          child: GlassContainer(
            backgroundColor: backgroundColor ?? AppTheme.glassBackgroundLight,
            borderColor: borderColor ?? AppTheme.glassBorder,
            borderRadius: AppTheme.modalBorderRadius,
            padding: EdgeInsets.zero,
            applyBlur: false, // Already applied by BackdropFilter
            child: Column(
              children: [
                if (showDragHandle) const GlassDragHandle(),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
