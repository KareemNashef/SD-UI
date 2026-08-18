// ==================== Glass Drag Handle ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Drag Handle Implementation

class GlassDragHandle extends StatelessWidget {
  final EdgeInsetsGeometry? margin;

  const GlassDragHandle({super.key, this.margin});

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: margin ?? const EdgeInsets.only(top: 14, bottom: 4),
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.mist35,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
