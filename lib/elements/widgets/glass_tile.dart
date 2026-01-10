// ==================== Glass Tile ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Tile Implementation

class GlassTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? accentColor;
  final IconData? leadingIcon;
  final IconData? selectedIcon;
  final IconData? unselectedIcon;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showCheckbox;

  const GlassTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.accentColor,
    this.leadingIcon,
    this.selectedIcon,
    this.unselectedIcon,
    this.trailing,
    this.padding,
    this.margin,
    this.showCheckbox = false,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? effectiveAccent.withValues(alpha: 0.15)
            : const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? effectiveAccent.withValues(alpha: 0.5)
              : const Color(0x14FFFFFF),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(12.0),
            child: Row(
              children: [
                if (showCheckbox || leadingIcon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Icon(
                      showCheckbox
                          ? (isSelected
                                ? (selectedIcon ?? Icons.check_circle)
                                : (unselectedIcon ?? Icons.circle_outlined))
                          : leadingIcon,
                      color: isSelected ? effectiveAccent : Colors.white24,
                      size: 24,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xCCFFFFFF),
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
