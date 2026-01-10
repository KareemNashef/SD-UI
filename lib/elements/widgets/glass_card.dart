// ==================== Glass Card ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Glass Card Implementation

/// A reusable image card widget with selection state
class GlassCard extends StatefulWidget {
  final String name;
  final String? imageUrl;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? accentColor;
  final double? aspectRatio;

  const GlassCard({
    super.key,
    required this.name,
    this.imageUrl,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.accentColor,
    this.aspectRatio,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  // ===== Class Variables ===== //
  late AnimationController _controller;
  late Animation<double> _scale;

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = widget.accentColor ?? AppTheme.accentPrimary;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? effectiveAccent
                  : Colors.white.withValues(alpha: 0.1),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: effectiveAccent.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: widget.aspectRatio ?? 0.75,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background Image
                  widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                      ? (widget.imageUrl!.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: widget.imageUrl!,
                                fit: BoxFit.cover,
                                memCacheWidth: 500, // Optimize memory
                                placeholder: (_, __) =>
                                    Container(color: Colors.grey.shade900),
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.white24,
                                  ),
                                ),
                              )
                            : Image.asset(
                                widget.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (c, o, s) =>
                                    Container(color: Colors.grey.shade900),
                              ))
                      : Container(
                          color: Colors.white10,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.white24,
                            size: 40,
                          ),
                        ),

                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                          Colors.black.withValues(alpha: 0.9),
                        ],
                        stops: const [0.3, 0.7, 1.0],
                      ),
                    ),
                  ),

                  // Selected Overlay
                  if (widget.isSelected)
                    Container(color: effectiveAccent.withValues(alpha: 0.2)),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: widget.isSelected
                                ? FontWeight.w900
                                : FontWeight.bold,
                            fontSize: 12,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Checkmark Badge
                  if (widget.isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: effectiveAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 12,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
