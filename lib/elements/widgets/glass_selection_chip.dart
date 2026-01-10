// ==================== Glass Selection Chip ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// A reusable selection chip widget with glassmorphism styling
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

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: padding ?? const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? effectiveAccent
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? effectiveAccent
                  : Colors.white.withValues(alpha: 0.1),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: effectiveAccent.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
