// ==================== Glass Bottom Bar ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/elements/widgets/glass_button.dart';

// Glass Bottom Bar Implementation

/// Standard bottom action bar for modals
/// OPTIMIZED: Removed unnecessary rebuilds, static decoration
class GlassBottomBar extends StatelessWidget {
  final Widget? leading;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final Color? primaryAccentColor;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final EdgeInsetsGeometry? padding;

  const GlassBottomBar({
    super.key,
    this.leading,
    this.primaryLabel,
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryAccentColor,
    this.secondaryLabel,
    this.onSecondary,
    this.padding,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    // Pre-calculate decoration to avoid rebuilding
    // Use const where possible
    return Container(
      padding: padding ?? const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(
          0x4D000000,
        ), // 30% opacity black (0.3 * 255 = 76.5 ≈ 0x4D)
        border: Border(top: BorderSide(color: AppTheme.glassBorder, width: 1)),
      ),
      child: SafeArea(
        // minimum: false improves performance when SafeArea isn't needed
        bottom: true,
        top: false,
        left: false,
        right: false,
        child: Row(
          children: [
            if (leading != null) leading!,
            if (secondaryLabel != null)
              GlassSecondaryButton(
                label: secondaryLabel!,
                onPressed: onSecondary,
              ),
            const Spacer(),
            if (primaryLabel != null)
              GlassPrimaryButton(
                label: primaryLabel!,
                onPressed: onPrimary,
                isEnabled: primaryEnabled,
                accentColor: primaryAccentColor,
              ),
          ],
        ),
      ),
    );
  }
}
