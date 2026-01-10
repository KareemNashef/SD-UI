// ==================== Glass Input ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Input Implementation

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
  final bool enabled;

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
    this.enabled = true,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      onChanged: onChanged,
      enabled: enabled,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: const Color(0x4DFFFFFF), size: 20)
            : null,
        hintStyle: const TextStyle(color: Color(0x4DFFFFFF), fontSize: 14),
        labelStyle: const TextStyle(color: Color(0x99FFFFFF), fontSize: 14),
        filled: true,
        fillColor: const Color(0x33000000),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: Color(0x0DFFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(
            color: effectiveAccent.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: Color(0x0DFFFFFF)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

/// Multiline text input optimized for prompts/descriptions
class GlassTextArea extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final Color? accentColor;
  final int minLines;
  final int maxLines;
  final bool enabled;

  const GlassTextArea({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.accentColor,
    this.minLines = 3,
    this.maxLines = 8,
    this.enabled = true,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GlassInput(
      controller: controller,
      hintText: hintText,
      onChanged: onChanged,
      accentColor: accentColor,
      maxLines: maxLines,
      keyboardType: TextInputType.multiline,
      enabled: enabled,
    );
  }
}
