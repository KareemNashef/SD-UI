// ==================== Glass App Bar ==================== //

// Flutter imports
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

  const GlassAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showStatusIndicator = true,
    this.height = 100,
    this.leading,
  });

  // ===== Class Methods ===== //

  @override
  Size get preferredSize => Size.fromHeight(height);

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xE6000000), // 90% opacity black
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
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
              title: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x0DFFFFFF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0x26FFFFFF),
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
                child: Container(height: 1, color: const Color(0x1AFFFFFF)),
              ),
          ],
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
        final color = isOnline ? AppTheme.success : AppTheme.error;

        return Container(
          height: 3,
          decoration: BoxDecoration(
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
