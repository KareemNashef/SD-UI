// ==================== Glass Drag Handle ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Glass Drag Handle Implementation

class GlassDragHandle extends StatelessWidget {
  final EdgeInsetsGeometry? margin;

  const GlassDragHandle({super.key, this.margin});

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: margin ?? const EdgeInsets.only(top: 12, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
