// ==================== Glass App Bar ==================== //

// Flutter imports
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Glass App Bar Implementation

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showStatusIndicator;
  final double height;
  final Widget? leading;
  final VoidCallback? onTitleTap;

  const GlassAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showStatusIndicator = true,
    this.height = 100,
    this.leading,
    this.onTitleTap,
  });

  // ===== Class Methods ===== //

  @override
  Size get preferredSize => Size.fromHeight(height);

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppTheme.glassBlurRegular, sigmaY: AppTheme.glassBlurRegular),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: AppTheme.ink.withValues(alpha: 0.75),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder, width: 1)),
          ),
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                AppBar(
                  toolbarHeight: height,
                  centerTitle: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.light,
                  leading: leading,
                  actions: actions,
                  title: GestureDetector(
                    onTap: onTitleTap,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: AppTheme.titleLarge),
                        if (subtitle != null) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.mist.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppTheme.mist18, width: 1),
                            ),
                            child: Text(subtitle!, style: AppTheme.subtitleMedium),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showStatusIndicator)
                  const Positioned(bottom: 0, left: 0, right: 0, child: _StatusBorderLine())
                else
                  Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 1, color: AppTheme.mist10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBorderLine extends StatelessWidget {
  const _StatusBorderLine();

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalServerStatus,
      builder: (context, isOnline, child) {
        // Online reflects the active backend's identity tint, not a fixed
        // "success" green - Comfy connected should read violet, not green.
        final color = isOnline ? AppTheme.accentPrimary : AppTheme.error;

        return Container(
          height: 2.5,
          decoration: BoxDecoration(
            color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 1)],
          ),
        );
      },
    );
  }
}
