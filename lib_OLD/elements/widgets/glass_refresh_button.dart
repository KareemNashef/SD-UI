// ==================== Glass Refresh Button ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Refresh Button Implementation

class GlassRefreshButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isRefreshing;
  final Color? accentColor;
  final double turns;

  const GlassRefreshButton({
    super.key,
    this.onTap,
    this.isRefreshing = false,
    this.accentColor,
    this.turns = 0.0,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.mist10),
            color: AppTheme.mist.withValues(alpha: 0.05),
          ),
          child: Transform.rotate(
            angle: turns * 6.28318, // 2π radians per turn
            child: Icon(
              Icons.refresh_rounded,
              color: isRefreshing ? effectiveAccent : AppTheme.mist80,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
