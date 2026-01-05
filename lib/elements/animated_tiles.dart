// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ==========================================
// ANIMATED LORA TILE
// ==========================================

class AnimatedLoraTile extends StatefulWidget {
  final String loraName;
  final LoraData loraData;
  final bool isSelected;
  final double strength;
  final bool isExpanded;
  final Set<String> selectedTags;
  final bool showAllTags;
  final VoidCallback onToggleSelection;
  final Function(double) onStrengthChanged;
  final VoidCallback onToggleExpand;
  final Function(String) onToggleTag;
  final VoidCallback onToggleShowAllTags;

  const AnimatedLoraTile({
    Key? key,
    required this.loraName,
    required this.loraData,
    required this.isSelected,
    required this.strength,
    required this.isExpanded,
    required this.selectedTags,
    required this.showAllTags,
    required this.onToggleSelection,
    required this.onStrengthChanged,
    required this.onToggleExpand,
    required this.onToggleTag,
    required this.onToggleShowAllTags,
  }) : super(key: key);

  @override
  State<AnimatedLoraTile> createState() => _AnimatedLoraTileState();
}

class _AnimatedLoraTileState extends State<AnimatedLoraTile>
    with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    // 1. Setup Bounce Animation (Selection)
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    // 2. Setup Expand Animation
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.fastOutSlowIn,
    );
  }

  @override
  void didUpdateWidget(AnimatedLoraTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isSelected && !oldWidget.isSelected) {
      _bounceController
          .forward(from: 0.0)
          .then((_) => _bounceController.reverse());
    }

    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTags = widget.loraData.tags;
    final tagsToShow = (allTags.length > 10 && !widget.showAllTags)
        ? allTags.take(10).toList()
        : allTags;
    final hiddenTagCount = allTags.length - 10;

    // Ensure maxStrength is at least 1.0 to prevent division by zero errors
    double currentMaxStrength = widget.loraData.maxStrength < 1.0
        ? 1.0
        : widget.loraData.maxStrength;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? Colors.cyan.shade900.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected
              ? Colors.cyan.shade400.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: widget.isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // --- Main Row ---
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Toggle Icon
                GestureDetector(
                  onTap: widget.onToggleSelection,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: widget.isSelected
                            ? LinearGradient(
                                colors: [
                                  Colors.cyan.shade400,
                                  Colors.teal.shade400,
                                ],
                              )
                            : const LinearGradient(
                                colors: [Colors.white10, Colors.white10],
                              ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: widget.isSelected
                            ? Colors.white
                            : Colors.white38,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Text Info
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onToggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.loraData.title,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.loraData.alias,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (allTags.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.circle,
                                size: 4,
                                color: Colors.white24,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${allTags.length} tags',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              if (widget.selectedTags.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    ' • ${widget.selectedTags.length} active',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.cyan.shade300,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (allTags.isNotEmpty)
                  IconButton(
                    icon: RotationTransition(
                      turns: Tween(
                        begin: 0.0,
                        end: 0.5,
                      ).animate(_expandAnimation),
                      child: const Icon(
                        Icons.expand_more,
                        color: Colors.white38,
                      ),
                    ),
                    onPressed: widget.onToggleExpand,
                  ),
              ],
            ),
          ),

          // --- Strength Slider Section ---
          SizeTransition(
            sizeFactor: widget.isSelected
                ? const AlwaysStoppedAnimation(1.0)
                : const AlwaysStoppedAnimation(0.0),
            axisAlignment: -1.0,
            child: widget.isSelected
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 12,
                    ),
                    child: Column(
                      children: [
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.tune,
                              size: 16,
                              color: Colors.cyan.shade300,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Strength',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),

                            // --- NEW: Range Toggle Button ---
                            InkWell(
                              onTap: () {
                                setState(() {
                                  // Toggle logic: If 1.0 -> 5.0, else -> 1.0
                                  double newMax = currentMaxStrength > 1.0
                                      ? 1.0
                                      : 5.0;
                                  widget.loraData.maxStrength = newMax;

                                  // Clamp logic: If current strength > newMax, reduce it
                                  if (widget.strength > newMax) {
                                    widget.onStrengthChanged(newMax);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: currentMaxStrength > 1.0
                                      ? Colors.cyan.shade900.withValues(
                                          alpha: 0.4,
                                        )
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: currentMaxStrength > 1.0
                                        ? Colors.cyan.shade400.withValues(
                                            alpha: 0.5,
                                          )
                                        : Colors.white12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.speed,
                                      size: 12,
                                      color: currentMaxStrength > 1.0
                                          ? Colors.cyan.shade200
                                          : Colors.white54,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Max: ${currentMaxStrength.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: currentMaxStrength > 1.0
                                            ? Colors.cyan.shade200
                                            : Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // --- Value Display ---
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.strength.toStringAsFixed(2),
                                style: TextStyle(
                                  color: Colors.cyan.shade200,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),

                        // --- Slider ---
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.cyan.shade400,
                            inactiveTrackColor: Colors.black26,
                            thumbColor: Colors.white,
                            overlayColor: Colors.cyan.shade400.withValues(
                              alpha: 0.2,
                            ),
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value: widget.strength,
                            min: 0.0,
                            // Use the dynamic max
                            max: currentMaxStrength,
                            // Calculate divisions to keep steps roughly 0.05
                            divisions: (currentMaxStrength * 20).toInt(),
                            onChanged: widget.onStrengthChanged,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // --- Tags Section (Collapsible) ---
          if (allTags.isNotEmpty)
            SizeTransition(
              sizeFactor: _expandAnimation,
              axis: Axis.vertical,
              axisAlignment: -1.0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AVAILABLE TAGS',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...tagsToShow.map((tag) {
                          final isTagSelected = widget.selectedTags.contains(
                            tag,
                          );
                          return InkWell(
                            onTap: () => widget.onToggleTag(tag),
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isTagSelected
                                    ? Colors.cyan.shade700.withValues(
                                        alpha: 0.5,
                                      )
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isTagSelected
                                      ? Colors.cyan.shade400
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isTagSelected) ...[
                                    Icon(
                                      Icons.check,
                                      size: 12,
                                      color: Colors.cyan.shade100,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      color: isTagSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: isTagSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (allTags.length > 10)
                          InkWell(
                            onTap: widget.onToggleShowAllTags,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.showAllTags
                                        ? 'Show Less'
                                        : 'Show $hiddenTagCount more',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    widget.showAllTags
                                        ? Icons.arrow_drop_up
                                        : Icons.arrow_drop_down,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// ANIMATED HISTORY TILE
// ==========================================

class AnimatedHistoryTile extends StatefulWidget {
  final String text;
  final bool isMultiSelectMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const AnimatedHistoryTile({
    Key? key,
    required this.text,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  }) : super(key: key);

  @override
  State<AnimatedHistoryTile> createState() => _AnimatedHistoryTileState();
}

class _AnimatedHistoryTileState extends State<AnimatedHistoryTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.0,
    ).animate(_bounceController);
  }

  @override
  void didUpdateWidget(AnimatedHistoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _bounceController
          .forward(from: 0.0)
          .then((_) => _bounceController.reverse());
      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
        CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
      );
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? Colors.cyan.shade900.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected
              ? Colors.cyan.shade400.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.05),
          width: widget.isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Animated Checkbox / Icon
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: widget.isMultiSelectMode
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Icon(
                              widget.isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: widget.isSelected
                                  ? Colors.cyan.shade300
                                  : Colors.white24,
                              size: 24,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // Text
                Expanded(
                  child: Text(
                    widget.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ANIMATED CHECKPOINT TILE
// ==========================================

class AnimatedCheckpointTile extends StatefulWidget {
  final String name;
  final dynamic data; // Replace with your CheckpointData type
  final bool isSelected;
  final VoidCallback onTap;

  const AnimatedCheckpointTile({
    Key? key,
    required this.name,
    required this.data,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedCheckpointTile> createState() => _AnimatedCheckpointTileState();
}

class _AnimatedCheckpointTileState extends State<AnimatedCheckpointTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.0,
    ).animate(_bounceController);
  }

  @override
  void didUpdateWidget(AnimatedCheckpointTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _bounceController
          .forward(from: 0.0)
          .then((_) => _bounceController.reverse());
      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
        CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
      );
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? Colors.cyan.shade900.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected
              ? Colors.cyan.shade400.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Bouncy Icon
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: widget.isSelected
                          ? LinearGradient(
                              colors: [
                                Colors.cyan.shade400,
                                Colors.teal.shade400,
                              ],
                            )
                          : LinearGradient(
                              colors: [Colors.white10, Colors.white10],
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.isSelected ? Icons.check : Icons.circle_outlined,
                      color: widget.isSelected ? Colors.white : Colors.white24,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (widget.data != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.compare_arrows_sharp,
                              size: 12,
                              color: Colors.white38,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.data.samplingMethod}',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.bolt, size: 12, color: Colors.white38),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.data.samplingSteps.toInt()} steps',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ANIMATED SAMPLER TILE
// ==========================================

class AnimatedSamplerTile extends StatefulWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  const AnimatedSamplerTile({
    Key? key,
    required this.name,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedSamplerTile> createState() => _AnimatedSamplerTileState();
}

class _AnimatedSamplerTileState extends State<AnimatedSamplerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.0,
    ).animate(_bounceController);
  }

  @override
  void didUpdateWidget(AnimatedSamplerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _bounceController
          .forward(from: 0.0)
          .then((_) => _bounceController.reverse());
      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
        CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
      );
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? Colors.purple.shade900.withValues(
                alpha: 0.3,
              ) // Different tint for Samplers
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected
              ? Colors.purple.shade400.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: widget.isSelected
                          ? LinearGradient(
                              colors: [
                                Colors.purple.shade400,
                                Colors.pink.shade400,
                              ],
                            )
                          : LinearGradient(
                              colors: [Colors.white10, Colors.white10],
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.isSelected ? Icons.waves : Icons.circle_outlined,
                      color: widget.isSelected ? Colors.white : Colors.white24,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
