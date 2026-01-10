import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/logic/globals.dart';

class GlassNavigationBar extends StatefulWidget {
  final List<GlassNavigationBarItem> items;
  final Function(int) onTabSelected;
  final Duration animationDuration;
  final Curve animationCurve;
  final double iconSize;
  // ADDED: The controller from your PageView
  final PageController? controller;

  const GlassNavigationBar({
    super.key,
    required this.items,
    required this.onTabSelected,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeOutQuart,
    this.iconSize = 24.0,
    this.controller,
  });

  @override
  State<GlassNavigationBar> createState() => _GlassNavigationBarState();
}

class _GlassNavigationBarState extends State<GlassNavigationBar> {
  // Helper to calculate scroll progress for a specific index
  double _calculateSelectionValue(int index, double currentPage) {
    // 0.0 = Far away, 1.0 = Exactly on this index
    double difference = (currentPage - index).abs();
    return (1.0 - difference).clamp(0.0, 1.0);
  }

  Widget buildTabItem(int index, double selectionValue) {
    // selectionValue: 0.0 (Unselected) -> 1.0 (Selected)

    // 1. Icon Opacity: Visible when unselected (0.0), hidden when selected (1.0)
    // We make it fade out faster (0.5 threshold) for a cleaner crossover
    final double iconOpacity = (1.0 - (selectionValue * 1.5)).clamp(0.0, 1.0);

    // 2. Text Opacity: Hidden when unselected (0.0), visible when selected (1.0)
    // We make it fade in later
    final double textOpacity = ((selectionValue - 0.3) * 1.5).clamp(0.0, 1.0);

    // 3. Movement Offset
    // Icon moves down when selected, Text moves up when appearing
    final double translationY = selectionValue * 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ===== Inactive State: Icon ===== //
          Transform.translate(
            offset: Offset(0, translationY), // Moves down as it fades out
            child: Opacity(
              opacity: iconOpacity,
              child: Icon(
                widget.items[index].icon,
                color: AppTheme.textTertiary,
                size: widget.iconSize,
              ),
            ),
          ),

          // ===== Active State: Text ===== //
          Transform.translate(
            offset: Offset(
              0,
              (1.0 - selectionValue) * 10,
            ), // Moves up into place
            child: Opacity(
              opacity: textOpacity,
              child: Transform.scale(
                scale: 0.8 + (selectionValue * 0.2), // Scales 0.8 -> 1.0
                child: Text(
                  widget.items[index].title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    shadows: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double barHeight = 65.0;
    const double indicatorHeight = 45.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppTheme.blurSigma,
            sigmaY: AppTheme.blurSigma,
          ),
          child: Container(
            height: barHeight,
            decoration: BoxDecoration(
              color: AppTheme.glassBackground,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(color: AppTheme.glassBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(5.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / widget.items.length;

                // We listen to the controller if available, otherwise fallback to global index
                return AnimatedBuilder(
                  animation: widget.controller ?? globalPageIndex,
                  builder: (context, child) {
                    // Get the exact continuous position (e.g. 0.5, 1.2, etc.)
                    double currentScrollPage;
                    if (widget.controller != null &&
                        widget.controller!.hasClients) {
                      currentScrollPage = widget.controller!.page ?? 0.0;
                    } else {
                      // Fallback for initial render or if no controller passed
                      currentScrollPage = globalPageIndex.value.toDouble();
                    }

                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // ==================== The Sliding Pill Indicator ==================== //
                        // Instead of AnimatedPositioned, we use Positioned with exact calculations
                        Positioned(
                          left: currentScrollPage * tabWidth,
                          top: 0,
                          bottom: 0,
                          width: tabWidth,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.0),
                            decoration: BoxDecoration(
                              color: AppTheme.accentPrimary,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentPrimary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ==================== The Tab Items ==================== //
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: List.generate(widget.items.length, (index) {
                            // Calculate specific morph state for this item based on swipe
                            double selectionValue = _calculateSelectionValue(
                              index,
                              currentScrollPage,
                            );

                            return SizedBox(
                              width: tabWidth,
                              height: indicatorHeight,
                              child: InkWell(
                                onTap: () {
                                  if (globalPageIndex.value != index) {
                                    HapticFeedback.selectionClick();
                                    widget.onTabSelected(index);
                                  }
                                },
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull,
                                ),
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                child: Center(
                                  child: buildTabItem(index, selectionValue),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class GlassNavigationBarItem {
  final IconData icon;
  final String title;

  const GlassNavigationBarItem({required this.icon, required this.title});
}
