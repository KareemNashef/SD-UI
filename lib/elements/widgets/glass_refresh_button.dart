// ==================== Glass Refresh Button ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

/// A reusable refresh button with rotation animation
class GlassRefreshButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isRefreshing;
  final Color? accentColor;

  const GlassRefreshButton({
    super.key,
    this.onTap,
    this.isRefreshing = false,
    this.accentColor,
  });

  @override
  State<GlassRefreshButton> createState() => _GlassRefreshButtonState();
}

class _GlassRefreshButtonState extends State<GlassRefreshButton> {
  double _rotationTurns = 0.0;

  @override
  void didUpdateWidget(GlassRefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRefreshing && !oldWidget.isRefreshing) {
      _startRotation();
    } else if (!widget.isRefreshing && oldWidget.isRefreshing) {
      _stopRotation();
    }
  }

  void _startRotation() {
    Future.doWhile(() async {
      if (!mounted || !widget.isRefreshing) return false;
      setState(() {
        _rotationTurns += 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 50));
      return widget.isRefreshing;
    });
  }

  void _stopRotation() {
    setState(() {
      _rotationTurns = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = widget.accentColor ?? AppTheme.accentPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white10),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: AnimatedRotation(
            turns: _rotationTurns,
            duration: const Duration(seconds: 1),
            child: Icon(
              Icons.refresh_rounded,
              color: widget.isRefreshing ? effectiveAccent : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
