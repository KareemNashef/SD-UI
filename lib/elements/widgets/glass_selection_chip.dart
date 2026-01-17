// ==================== Glass Selection Chip ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Selection Chip Implementation

class GlassSelectionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? accentColor;
  final EdgeInsetsGeometry? padding;

  const GlassSelectionChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.accentColor,
    this.padding,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            padding ?? const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected ? effectiveAccent : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? effectiveAccent : const Color(0x1AFFFFFF),
          ),
          // Simplified shadow
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: effectiveAccent.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
