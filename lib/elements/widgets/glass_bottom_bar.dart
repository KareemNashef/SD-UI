// ==================== Glass Bottom Bar ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/elements/widgets/glass_button.dart';

/// Standard bottom action bar for modals
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(top: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: SafeArea(
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
