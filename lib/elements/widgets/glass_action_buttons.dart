// ==================== Glass Action Buttons ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Action Buttons Implementation

/// The main Generate action - a circular floating button (an aperture
/// iris, in keeping with the icon) rather than the old full-width bar, so
/// it reads as one deliberate, reachable action rather than another row.
class GlassGenButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLoading;
  final double size;

  const GlassGenButton({
    super.key,
    required this.onTap,
    this.isLoading = false,
    this.size = 60,
  });

  @override
  State<GlassGenButton> createState() => _GlassGenButtonState();
}

class _GlassGenButtonState extends State<GlassGenButton> {
  // ===== Class Variables ===== //
  bool _isPressed = false;

  // ===== Class Methods ===== //

  void _handleTapDown(_) {
    if (widget.isLoading) return;
    HapticFeedback.lightImpact();
    setState(() => _isPressed = true);
  }

  void _handleTapUp(_) {
    if (widget.isLoading) return;
    setState(() => _isPressed = false);
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: AppTheme.durationFast,
        curve: AppTheme.ease,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: widget.isLoading
                  ? [AppTheme.ink4, AppTheme.ink3]
                  : [AppTheme.accentSecondary, AppTheme.accentPrimary],
              center: Alignment.topLeft,
              radius: 1.3,
            ),
            boxShadow: widget.isLoading
                ? null
                : [
                    BoxShadow(color: AppTheme.accentPrimary.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: 1),
                    BoxShadow(color: AppTheme.ink.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8)),
                  ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Static specular highlight, upper-left - the glass catching light.
              Positioned(
                top: widget.size * 0.1,
                left: widget.size * 0.14,
                child: Container(
                  width: widget.size * 0.34,
                  height: widget.size * 0.2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.white.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              widget.isLoading
                  ? SizedBox(
                      width: widget.size * 0.4,
                      height: widget.size * 0.4,
                      child: const CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white54)),
                    )
                  : Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: widget.size * 0.46,
                      shadows: const [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small square glass action button - the control-bar icons (Test Lab,
/// LoRAs, Prompt Vault, Describe Image, ...).
class GlassOptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  const GlassOptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  State<GlassOptionButton> createState() => _GlassOptionButtonState();
}

class _GlassOptionButtonState extends State<GlassOptionButton> {
  // ===== Class Variables ===== //
  bool _isPressed = false;

  // ===== Class Methods ===== //

  void _handleTapDown(_) {
    HapticFeedback.lightImpact();
    setState(() => _isPressed = true);
  }

  void _handleTapUp(_) {
    setState(() => _isPressed = false);
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isActive ? AppTheme.accentPrimary : AppTheme.mist80;
    final borderColor = widget.isActive ? AppTheme.accentPrimary.withValues(alpha: 0.5) : AppTheme.glassBorder;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedScale(
          scale: _isPressed ? 0.90 : 1.0,
          duration: AppTheme.durationFast,
          curve: AppTheme.ease,
          child: Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: widget.isActive ? AppTheme.accentPrimary.withValues(alpha: 0.15) : AppTheme.glassBackground,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: borderColor, width: 1.4),
              boxShadow: [
                BoxShadow(color: AppTheme.ink.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Center(child: Icon(widget.icon, color: iconColor, size: 22)),
          ),
        ),
      ),
    );
  }
}
