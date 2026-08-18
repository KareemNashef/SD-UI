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
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final Color? accentColor;
  final IconData? prefixIcon;
  final bool enabled;
  final FocusNode? focusNode;

  const GlassInput({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.accentColor,
    this.prefixIcon,
    this.enabled = true,
    this.focusNode,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      enabled: enabled,
      onTapOutside: (event) => FocusScope.of(context).unfocus(),
      style: TextStyle(color: AppTheme.mist, fontSize: 14, fontFamily: AppTheme.fontUI),
      cursorColor: effectiveAccent,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppTheme.mist35, size: 20) : null,
        hintStyle: TextStyle(color: AppTheme.mist35, fontSize: 14, fontFamily: AppTheme.fontUI),
        labelStyle: TextStyle(color: AppTheme.mist55, fontSize: 14, fontFamily: AppTheme.fontUI),
        filled: true,
        fillColor: AppTheme.ink.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: AppTheme.mist10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: effectiveAccent.withValues(alpha: 0.55), width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: AppTheme.mist10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
  final FocusNode? focusNode;
  final IconData? prefixIcon;

  const GlassTextArea({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.accentColor,
    this.minLines = 3,
    this.maxLines = 8,
    this.enabled = true,
    this.focusNode,
    this.prefixIcon,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GlassInput(
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      onChanged: onChanged,
      accentColor: accentColor,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: TextInputType.multiline,
      enabled: enabled,
      prefixIcon: prefixIcon,
    );
  }
}
