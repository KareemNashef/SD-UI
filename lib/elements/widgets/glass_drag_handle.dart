// ==================== Glass Drag Handle ==================== //

import 'package:flutter/material.dart';

/// Standard drag handle for modals
class GlassDragHandle extends StatelessWidget {
  final EdgeInsetsGeometry? margin;

  const GlassDragHandle({
    super.key,
    this.margin,
  });

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
