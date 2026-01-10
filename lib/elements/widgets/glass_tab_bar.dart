// ==================== Glass Tab Bar ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Tab Bar Implementation

/// Standard tab bar with glassmorphism styling
class GlassTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.padding,
    this.margin,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: AppTheme.accentPrimary,
        ),
        dividerColor: Colors.transparent,
        labelColor: Colors.black,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: tabs.map((label) {
          return Tab(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(label),
            ),
          );
        }).toList(),
      ),
    );
  }
}
