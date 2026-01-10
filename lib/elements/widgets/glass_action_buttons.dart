// ==================== Glass Action Buttons ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Action Buttons Implementation

class GlassGenButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLoading;

  const GlassGenButton({
    super.key,
    required this.onTap,
    this.isLoading = false,
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
      child: Transform.scale(
        scale: _isPressed ? 0.92 : 1.0,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: widget.isLoading
                  ? [const Color(0xFF424242), const Color(0xFF616161)]
                  : [AppTheme.accentSecondary, AppTheme.accentPrimary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            // Simplified shadow - removed glow when loading
            boxShadow: widget.isLoading
                ? null
                : [
                    BoxShadow(
                      color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Static specular highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 28,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x4DFFFFFF), Color(0x00FFFFFF)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),
              ),
              // Icon - no rotation animation
              widget.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white54),
                      ),
                    )
                  : const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 26,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final iconColor = widget.isActive
        ? AppTheme.accentPrimary
        : Colors.white.withValues(alpha: 0.8);

    final borderColor = widget.isActive
        ? AppTheme.accentPrimary.withValues(alpha: 0.5)
        : AppTheme.glassBorder;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: Tooltip(
        message: widget.tooltip,
        child: Transform.scale(
          scale: _isPressed ? 0.90 : 1.0,
          child: Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              // NO BackdropFilter - massive performance win
              color: widget.isActive
                  ? AppTheme.accentPrimary.withValues(alpha: 0.15)
                  : AppTheme.glassBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(child: Icon(widget.icon, color: iconColor, size: 24)),
          ),
        ),
      ),
    );
  }
}
