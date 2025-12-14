// ==================== Custom Navigation Bar ==================== //

// Flutter imports
import 'dart:ui';
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Custom Navigation Bar Class ========== //

class CustomNavigationBar extends StatefulWidget {
  // ===== Input Variables ===== //
  final List<AnimatedBottomBarItem> items;
  final Function(int) onTabSelected;
  final Duration animationDuration;
  final Curve animationCurve;
  final double iconSize;

  // ===== Constructor ===== //
  const CustomNavigationBar({
    super.key,
    required this.items,
    required this.onTabSelected,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeOutBack,
    this.iconSize = 24.0,
  });

  @override
  CustomNavigationBarState createState() => CustomNavigationBarState();
}

class CustomNavigationBarState extends State<CustomNavigationBar> {
  // ===== Class Widgets ===== //

  Widget buildTabItem(int index) {
    final isSelected = index == globalPageIndex.value;

    return SizedBox(
      height: 44.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Icon animation
          AnimatedOpacity(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
            opacity: isSelected ? 0.0 : 1.0,
            child: TweenAnimationBuilder<double>(
              duration: widget.animationDuration,
              curve: widget.animationCurve,
              tween: Tween<double>(
                begin: isSelected ? 0.0 : 1.0,
                end: isSelected ? -1.0 : 0.0,
              ),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, isSelected ? value * 10 : 0),
                  child: child,
                );
              },
              child: Icon(
                widget.items[index].icon,
                // UPDATED: Dimmed white for inactive state
                color: Colors.white.withValues(alpha: 0.5),
                size: widget.iconSize,
              ),
            ),
          ),

          // Text animation
          AnimatedOpacity(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
            opacity: isSelected ? 1.0 : 0.0,
            child: TweenAnimationBuilder<double>(
              duration: widget.animationDuration,
              curve: widget.animationCurve,
              tween: Tween<double>(
                begin: isSelected ? 1.0 : 0.0,
                end: isSelected ? 0.0 : 1.0,
              ),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value * 10),
                  child: child,
                );
              },
              child: Text(
                widget.items[index].title,
                style: TextStyle(
                  // UPDATED: Cyan accent for active text
                  color: Colors.cyan.shade300,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    BoxShadow(
                      color: Colors.cyan.shade900.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(
            // UPDATED: Darker, glassier background with shadow
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),

            // Padding
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),

            // Content
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / widget.items.length;
                final indicatorPosition =
                    tabWidth * globalPageIndex.value + (tabWidth - 40) / 2;

                return Stack(
                  children: [
                    // Bottom indicator
                    AnimatedPositioned(
                      duration: widget.animationDuration,
                      curve: widget.animationCurve,
                      bottom: 4, // Raised slightly
                      left: indicatorPosition,
                      child: Container(
                        width: 40,
                        height: 4, // Slightly thicker
                        decoration: BoxDecoration(
                          // UPDATED: Gradient Cyan Glow
                          gradient: LinearGradient(
                            colors: [
                              Colors.cyan.shade400,
                              Colors.teal.shade400,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyan.shade400.withValues(
                                alpha: 0.6,
                              ),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Tabs
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(widget.items.length, (index) {
                        return Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                globalPageIndex.value = index;
                              });
                              widget.onTabSelected(index);
                            },
                            borderRadius: BorderRadius.circular(50.0),
                            child: buildTabItem(index),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedBottomBarItem {
  final IconData icon;
  final String title;

  const AnimatedBottomBarItem({required this.icon, required this.title});
}
