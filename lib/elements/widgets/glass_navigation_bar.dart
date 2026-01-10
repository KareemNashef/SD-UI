// ==================== Glass Navigation Bar ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Glass Navigation Bar Implementation

class GlassNavigationBar extends StatelessWidget {
  final List<GlassNavigationBarItem> items;
  final Function(int) onTabSelected;
  final PageController? controller;

  const GlassNavigationBar({
    super.key,
    required this.items,
    required this.onTabSelected,
    this.controller,
  });

  // ===== Class Methods ===== //

  double _calculateSelectionValue(int index, double currentPage) {
    double difference = (currentPage - index).abs();
    return (1.0 - difference).clamp(0.0, 1.0);
  }

  // ===== Class Widgets ===== //

  Widget _buildTabItem(int index, double selectionValue) {
    final iconOpacity = (1.0 - (selectionValue * 1.5)).clamp(0.0, 1.0);
    final textOpacity = ((selectionValue - 0.3) * 1.5).clamp(0.0, 1.0);
    final translationY = selectionValue * 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(0, translationY),
            child: Opacity(
              opacity: iconOpacity,
              child: Icon(
                items[index].icon,
                color: AppTheme.textTertiary,
                size: 24,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, (1.0 - selectionValue) * 10),
            child: Opacity(
              opacity: textOpacity,
              child: Transform.scale(
                scale: 0.8 + (selectionValue * 0.2),
                child: Text(
                  items[index].title,
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

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    const double barHeight = 65.0;
    const double indicatorHeight = 45.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          // NO BackdropFilter - massive performance improvement
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
            final tabWidth = constraints.maxWidth / items.length;

            return AnimatedBuilder(
              animation: controller ?? globalPageIndex,
              builder: (context, child) {
                double currentScrollPage;
                if (controller != null && controller!.hasClients) {
                  currentScrollPage = controller!.page ?? 0.0;
                } else {
                  currentScrollPage = globalPageIndex.value.toDouble();
                }

                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Sliding pill indicator
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
                    // Tab items
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(items.length, (index) {
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
                                onTabSelected(index);
                              }
                            },
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusFull,
                            ),
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            child: Center(
                              child: _buildTabItem(index, selectionValue),
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
    );
  }
}

class GlassNavigationBarItem {
  final IconData icon;
  final String title;

  const GlassNavigationBarItem({required this.icon, required this.title});
}
