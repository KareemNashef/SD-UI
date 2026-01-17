// ==================== Glass Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/elements/widgets/glass_drag_handle.dart';

// Glass Modal Implementation

class GlassModal extends StatelessWidget {
  final Widget child;
  final double heightFactor;
  final bool showDragHandle;
  final Color? backgroundColor;
  final Color? borderColor;

  const GlassModal({
    super.key,
    required this.child,
    this.heightFactor = AppTheme.modalHeightFactor,
    this.showDragHandle = true,
    this.backgroundColor,
    this.borderColor,
  });

  // ===== Class Methods ===== //

  static void show(
    BuildContext context, {
    required Widget child,
    double heightFactor = AppTheme.modalHeightFactor,
    bool showDragHandle = true,
    Color? backgroundColor,
    Color? borderColor,
  }) {
    // Unfocus any active input before showing the modal to prevent
    // focus restoration issues when the modal closes.
    FocusManager.instance.primaryFocus?.unfocus();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => GlassModal(
        heightFactor: heightFactor,
        showDragHandle: showDragHandle,
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        child: child,
      ),
    ).then((_) {
      // Force focus away from any text fields to a new detached node.
      // This is more effective than unfocus() for preventing auto-restoration
      // of the keyboard when a modal closes.
      if (context.mounted) {
        FocusScope.of(context).requestFocus(FocusNode());
      }
    });
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Explicitly clear focus when the modal is popped to prevent
          // the framework from restoring focus to background inputs.
          FocusScope.of(context).unfocus();
        }
      },
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        child: Container(
          decoration: BoxDecoration(
            color: (backgroundColor ?? AppTheme.glassBackgroundLight)
                .withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.modalBorderRadius),
            ),
            border: Border(
              top: BorderSide(
                color: borderColor ?? AppTheme.glassBorder,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              if (showDragHandle) const GlassDragHandle(),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
