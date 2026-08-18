// ==================== Aperture Dock ==================== //

// Flutter imports
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Aperture Dock Implementation
//
// The primary loop - Create, Gallery - gets two equal, labeled, thumb-wide
// targets. Settings is real work but reached far less often, so it's a
// small icon-only third target rather than a peer of the other two: two
// taps for the everyday loop, not three equal menus.

class GlassNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const GlassNavigationBar({super.key, required this.currentIndex, required this.onTabSelected});

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppTheme.glassBlurThick, sigmaY: AppTheme.glassBlurThick),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.mist.withValues(alpha: 0.09), AppTheme.ink.withValues(alpha: 0.6)],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(color: AppTheme.glassBorder, width: 1),
            boxShadow: [BoxShadow(color: AppTheme.ink.withValues(alpha: 0.5), blurRadius: 28, offset: const Offset(0, 12))],
          ),
          child: Row(
            children: [
              Expanded(
                child: _DockDestination(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Create',
                  selected: currentIndex == 0,
                  onTap: () => _select(0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _DockDestination(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  selected: currentIndex == 1,
                  onTap: () => _select(1),
                ),
              ),
              Container(width: 1, height: 26, color: AppTheme.mist18, margin: const EdgeInsets.symmetric(horizontal: 8)),
              _DockSettingsButton(selected: currentIndex == 2, onTap: () => _select(2)),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int index) {
    if (index != currentIndex) HapticFeedback.selectionClick();
    onTabSelected(index);
  }
}

class _DockDestination extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DockDestination({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: AppTheme.durationMedium,
          curve: AppTheme.ease,
          height: 52,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            boxShadow: selected
                ? [BoxShadow(color: AppTheme.accentPrimary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? AppTheme.ink : AppTheme.mist55),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppTheme.ink : AppTheme.mist55,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockSettingsButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _DockSettingsButton({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: AppTheme.durationMedium,
          curve: AppTheme.ease,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: selected ? AppTheme.mist.withValues(alpha: 0.12) : Colors.transparent,
            shape: BoxShape.circle,
            border: selected ? Border.all(color: AppTheme.mist18) : null,
          ),
          child: Icon(Icons.tune_rounded, size: 20, color: selected ? AppTheme.mist : AppTheme.mist35),
        ),
      ),
    );
  }
}
