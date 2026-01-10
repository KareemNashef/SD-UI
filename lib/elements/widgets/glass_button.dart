// ==================== Glass Button ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// Standard primary button with glassmorphism styling
class GlassPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final Color? accentColor;
  final IconData? icon;
  final EdgeInsetsGeometry? padding;

  const GlassPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isEnabled = true,
    this.accentColor,
    this.icon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.accentPrimary;
    final enabled = isEnabled && onPressed != null;

    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? effectiveAccent : Colors.white10,
        foregroundColor: enabled ? Colors.black : Colors.white38,
        elevation: enabled ? 8 : 0,
        shadowColor: effectiveAccent.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Standard secondary button
class GlassSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? textColor;

  const GlassSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? Colors.white.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// Standard icon button with glass styling
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? iconColor;
  final double? size;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconColor,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white10),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: Icon(
            icon,
            color: iconColor ?? Colors.white70,
            size: size ?? 20,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
