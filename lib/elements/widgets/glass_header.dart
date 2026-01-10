// ==================== Glass Header ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// Standard header for modals and sections
class GlassHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color? iconColor;
  final EdgeInsetsGeometry? padding;

  const GlassHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.iconColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: iconColor ?? AppTheme.accentPrimary,
                  size: 24,
                ),
                const SizedBox(width: 12),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.titleLarge),
                  if (subtitle != null)
                    Text(subtitle!, style: AppTheme.subtitleMedium),
                ],
              ),
            ],
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
