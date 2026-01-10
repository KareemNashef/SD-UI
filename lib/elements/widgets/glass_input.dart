// ==================== Glass Input ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// Standard text input field with glassmorphism styling
class GlassInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final Color? accentColor;
  final IconData? prefixIcon;

  const GlassInput({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.onChanged,
    this.accentColor,
    this.prefixIcon,
  });

  static InputDecoration decoration({
    required String hint,
    IconData? icon,
    Color? accentColor,
  }) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, color: Colors.white30, size: 20)
          : null,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        borderSide: BorderSide(
          color: effectiveAccent.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: decoration(
        hint: hintText ?? '',
        icon: prefixIcon,
        accentColor: accentColor,
      ),
    );
  }
}
