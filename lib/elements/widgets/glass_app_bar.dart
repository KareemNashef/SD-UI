// ==================== Glass App Bar ==================== //

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/logic/globals.dart';

/// Standardized glassmorphic app bar with integrated system status
/// Matches the "Lora Modal" and "Glass Tab Bar" aesthetic.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showStatusIndicator;
  final double height;
  final Widget? leading;

  const GlassAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showStatusIndicator = true,
    this.height = 60,
    this.leading,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: preferredSize,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppTheme.blurSigma,
            sigmaY: AppTheme.blurSigma,
          ),
          child: Stack(
            children: [
              // 2. The AppBar Content
              AppBar(
                toolbarHeight: height,
                centerTitle: true,
                backgroundColor: Colors.transparent, // Handled by container
                elevation: 0,
                scrolledUnderElevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                leading: leading, // Auto-handles back button if null
                actions: actions,
                title: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main Title
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),

                    // Subtitle Chip (Tech/Spec style)
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Status Indicator (The Glowing Bottom Border)
              if (showStatusIndicator)
                const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _StatusBorderLine(),
                )
              else
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An animated line at the bottom of the AppBar that indicates connection status
/// Glowing Cyan = Online, Glowing Red = Offline
class _StatusBorderLine extends StatelessWidget {
  const _StatusBorderLine();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalServerStatus,
      builder: (context, isOnline, child) {
        final color = isOnline ? AppTheme.success : AppTheme.error;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          height: 3, // Thickness of the status line
          decoration: BoxDecoration(
            color: color,
            boxShadow: [
              // The Glow Effect
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 10, // Wider blur for neon effect
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
