// ==================== Glass Action Buttons ==================== //

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// The Primary "Generate" Action Button
/// Features a glowing gradient core, glass overlay, and haptic feedback.
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

class _GlassGenButtonState extends State<GlassGenButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 100),
    );

    // Scale breathing effect
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );

    // Slight rotation for the icon to feel mechanical
    _rotate = Tween<double>(
      begin: 0.0,
      end: 0.1, // Small rotation in radians
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(_) {
    if (widget.isLoading) return;
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _handleTapUp(_) {
    if (widget.isLoading) return;
    HapticFeedback.selectionClick();
    _controller.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20), // Slightly softer rect
                gradient: LinearGradient(
                  colors: widget.isLoading
                      ? [Colors.grey.shade800, Colors.grey.shade700]
                      : [AppTheme.accentSecondary, AppTheme.accentPrimary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: widget.isLoading
                    ? []
                    : [
                        // Outer colored glow
                        BoxShadow(
                          color: AppTheme.accentPrimary.withValues(alpha: 0.5),
                          blurRadius: 16,
                          spreadRadius: -2,
                        ),
                      ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Specular Highlight (The "Glassy" shine on top)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.3),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),

                  // The Content
                  widget.isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white54,
                          ),
                        )
                      : Transform.rotate(
                          angle: _rotate.value,
                          child: const Icon(
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
                        ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Secondary Utility Button (Settings, Share, etc.)
/// Resembles a physical frosted glass key.
class GlassOptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive; // Optional: to show if a toggle is active

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

class _GlassOptionButtonState extends State<GlassOptionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(_) {
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _handleTapUp(_) {
    _controller.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // Determine color based on active state
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
      child: ScaleTransition(
        scale: _scale,
        child: Tooltip(
          message: widget.tooltip,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 56,
                width: 56,
                decoration: BoxDecoration(
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
                child: Center(
                  child: Icon(widget.icon, color: iconColor, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
