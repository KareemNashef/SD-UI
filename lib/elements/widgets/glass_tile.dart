// ==================== Glass Tile ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// A reusable selectable tile widget with glassmorphism styling
/// Replaces AnimatedHistoryTile, AnimatedCheckpointTile, and AnimatedSamplerTile
class GlassTile extends StatefulWidget {
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
  final bool bounceOnSelect;

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
    this.bounceOnSelect = true,
  });

  @override
  State<GlassTile> createState() => _GlassTileState();
}

class _GlassTileState extends State<GlassTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.0,
    ).animate(_bounceController);
  }

  @override
  void didUpdateWidget(GlassTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bounceOnSelect && widget.isSelected && !oldWidget.isSelected) {
      _bounceController
          .forward(from: 0.0)
          .then((_) => _bounceController.reverse());
      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
        CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
      );
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = widget.accentColor ?? AppTheme.accentPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: widget.margin ?? const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? effectiveAccent.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected
              ? effectiveAccent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: widget.padding ?? const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Leading Icon/Checkbox
                if (widget.showCheckbox || widget.leadingIcon != null)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: widget.showCheckbox
                            ? Icon(
                                widget.isSelected
                                    ? (widget.selectedIcon ??
                                          Icons.check_circle)
                                    : (widget.unselectedIcon ??
                                          Icons.circle_outlined),
                                color: widget.isSelected
                                    ? effectiveAccent
                                    : Colors.white24,
                                size: 24,
                              )
                            : Icon(
                                widget.leadingIcon,
                                color: widget.isSelected
                                    ? effectiveAccent
                                    : Colors.white38,
                                size: 20,
                              ),
                      ),
                    ),
                  ),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
