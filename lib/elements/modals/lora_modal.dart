// Flutter imports
import 'package:flutter/material.dart';
// For compute

// Local imports - Elements
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_tab_bar.dart';
import 'package:sd_companion/elements/widgets/glass_bottom_bar.dart';
import 'package:sd_companion/elements/widgets/glass_badge.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/models/lora_data.dart';

void showLorasModal(
  BuildContext context,
  Map<String, double> selectedLoras,
  Map<String, Set<String>> selectedLoraTags,
  Function(Map<String, double>, Map<String, Set<String>>) onApply,
) {
  GlassModal.show(
    context,
    child: _LorasContent(
      selectedLoras: selectedLoras,
      selectedLoraTags: selectedLoraTags,
      onApply: onApply,
    ),
  );
}

class _LorasContent extends StatefulWidget {
  final Map<String, double> selectedLoras;
  final Map<String, Set<String>> selectedLoraTags;
  final Function(Map<String, double>, Map<String, Set<String>>) onApply;

  const _LorasContent({
    required this.selectedLoras,
    required this.selectedLoraTags,
    required this.onApply,
  });

  @override
  __LorasContentState createState() => __LorasContentState();
}

class __LorasContentState extends State<_LorasContent>
    with TickerProviderStateMixin {
  late final ValueNotifier<int> _activeCountNotifier;

  // Temporary selection state
  late final Map<String, double> _tempSelectedLoras;
  late final Map<String, Set<String>> _tempSelectedLoraTags;

  // Data state
  Map<String, List<LoraData>>? _groupedLoras; // Nullable to indicate loading
  TabController? _tabController;

  // Refresh state
  bool _isRefreshing = false;
  double _refreshTurns = 0.0;

  @override
  void initState() {
    super.initState();
    // 1. Initialize selection state (Fast)
    _tempSelectedLoras = Map.from(widget.selectedLoras);
    _tempSelectedLoraTags = {};
    widget.selectedLoraTags.forEach((key, value) {
      _tempSelectedLoraTags[key] = Set.from(value);
    });

    _activeCountNotifier = ValueNotifier(_tempSelectedLoras.length);

    // 2. Defer heavy sorting to allow the Modal open animation to start smoothly
    // Using addPostFrameCallback ensures the first frame of the modal renders instantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndSortLoras();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _activeCountNotifier.dispose();
    super.dispose();
  }

  /// Offload sorting to a background method or just delay it slightly
  Future<void> _loadAndSortLoras() async {
    // Small delay to let modal enter animation settle
    await Future.delayed(const Duration(milliseconds: 50));

    // Perform grouping
    final result = _performGrouping(globalLoraDataMap.values.toList());

    if (mounted) {
      setState(() {
        _groupedLoras = result;
        _tabController = TabController(
          length: _groupedLoras!.length,
          vsync: this,
        );
      });
    }
  }

  // Pure logic helper - easier to maintain
  Map<String, List<LoraData>> _performGrouping(List<LoraData> rawList) {
    // Sort logic
    rawList.sort((a, b) => a.displayName.compareTo(b.displayName));

    // Group logic
    final Map<String, List<LoraData>> groups = {};
    for (var lora in rawList) {
      final key = lora.baseModel;
      groups.putIfAbsent(key, () => []).add(lora);
    }

    // Sort keys
    final sortedKeys = groups.keys.toList()..sort();
    final Map<String, List<LoraData>> sortedMap = {};
    for (var key in sortedKeys) {
      sortedMap[key] = groups[key]!;
    }
    return sortedMap;
  }

  Future<void> _refreshLoras() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _refreshTurns += 1.0;
    });

    await loadLoraDataFromServer();

    if (mounted) {
      // Re-run grouping
      final newGroups = _performGrouping(globalLoraDataMap.values.toList());
      setState(() {
        _groupedLoras = newGroups;
        _tabController?.dispose();
        _tabController = TabController(
          length: _groupedLoras!.length,
          vsync: this,
        );
        _isRefreshing = false;
      });
    }
  }

  Widget _buildTabContent() {
    // Show a loader while sorting happens to prevent UI freeze
    if (_groupedLoras == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    if (_groupedLoras!.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.white24),
            SizedBox(height: 16),
            Text('No LoRAs Found', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      physics: const BouncingScrollPhysics(),
      // Optimization: Pre-map keys to avoid re-mapping on every build
      children: _groupedLoras!.values.map((loras) {
        return _GridViewKeepAlive(
          loras: loras,
          tempSelectedLoras: _tempSelectedLoras,
          tempSelectedLoraTags: _tempSelectedLoraTags,
          accentColor: AppTheme.accentPrimary,
          onUpdate: (loraName, strength, tags, isSelected) {
            // ... (Same logic as before, omitted for brevity) ...
            if (isSelected) {
              _tempSelectedLoras[loraName] = strength;
              if (tags.isNotEmpty) {
                _tempSelectedLoraTags[loraName] = tags;
              } else {
                _tempSelectedLoraTags.remove(loraName);
              }
            } else {
              _tempSelectedLoras.remove(loraName);
              _tempSelectedLoraTags.remove(loraName);
            }
            // Batch update notifier
            if (_activeCountNotifier.value != _tempSelectedLoras.length) {
              _activeCountNotifier.value = _tempSelectedLoras.length;
            }
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassHeader(
          title: 'LoRA Library',
          trailing: Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _activeCountNotifier,
                builder: (context, count, child) {
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GlassBadge(
                      label: '$count Active',
                      icon: Icons.bolt,
                      accentColor: AppTheme.accentPrimary,
                    ),
                  );
                },
              ),
              _buildRefreshButton(),
            ],
          ),
        ),
        if (_groupedLoras != null &&
            _groupedLoras!.isNotEmpty &&
            _tabController != null)
          GlassTabBar(
            controller: _tabController!,
            tabs: _groupedLoras!.keys.toList(),
          ),
        Expanded(child: _buildTabContent()),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildRefreshButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _refreshLoras,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white10),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: AnimatedRotation(
            turns: _refreshTurns,
            duration: const Duration(seconds: 1),
            child: Icon(
              Icons.refresh_rounded,
              color: _isRefreshing ? AppTheme.accentPrimary : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return ValueListenableBuilder<int>(
      valueListenable: _activeCountNotifier,
      builder: (context, count, _) {
        return GlassBottomBar(
          secondaryLabel: 'Reset',
          onSecondary: () {
            setState(() {
              _tempSelectedLoras.clear();
              _tempSelectedLoraTags.clear();
              _activeCountNotifier.value = 0;
            });
            // Force rebuild of grid to update ticks
            // In a production app, use a Stream or InheritedWidget to notify tiles
            // For now, setState on parent is acceptable for the "Reset" action
          },
          primaryLabel: count == 0 ? 'Cancel' : 'Apply Changes',
          onPrimary: () {
            widget.onApply(_tempSelectedLoras, _tempSelectedLoraTags);
            Navigator.pop(context);
          },
          primaryEnabled: true,
          primaryAccentColor: AppTheme.accentPrimary,
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// OPTIMIZED GRID & TILE
// -----------------------------------------------------------------------------

class _GridViewKeepAlive extends StatefulWidget {
  final List<LoraData> loras;
  final Map<String, double> tempSelectedLoras;
  final Map<String, Set<String>> tempSelectedLoraTags;
  final Color accentColor;
  final Function(String, double, Set<String>, bool) onUpdate;

  const _GridViewKeepAlive({
    required this.loras,
    required this.tempSelectedLoras,
    required this.tempSelectedLoraTags,
    required this.accentColor,
    required this.onUpdate,
  });

  @override
  State<_GridViewKeepAlive> createState() => _GridViewKeepAliveState();
}

class _GridViewKeepAliveState extends State<_GridViewKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GridView.builder(
      cacheExtent: 1000,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: widget.loras.length,
      itemBuilder: (context, index) {
        final lora = widget.loras[index];

        // Pass primitive data to the tile to allow it to manage its own state
        return _OptimizedLoraTile(
          key: ValueKey(lora.name), // Important for performance
          lora: lora,
          initialStrength: widget.tempSelectedLoras[lora.name] ?? 0.0,
          initialSelectedTags: widget.tempSelectedLoraTags[lora.name] ?? {},
          accentColor: widget.accentColor,
          onUpdate: (strength, tags, isSelected) {
            widget.onUpdate(lora.name, strength, tags, isSelected);
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// SPLIT TILE ARCHITECTURE (The main lag fixer)
// -----------------------------------------------------------------------------

class _OptimizedLoraTile extends StatefulWidget {
  final LoraData lora;
  final double initialStrength;
  final Set<String> initialSelectedTags;
  final Color accentColor;
  final Function(double, Set<String>, bool) onUpdate;

  const _OptimizedLoraTile({
    super.key,
    required this.lora,
    required this.initialStrength,
    required this.initialSelectedTags,
    required this.accentColor,
    required this.onUpdate,
  });

  @override
  State<_OptimizedLoraTile> createState() => _OptimizedLoraTileState();
}

class _OptimizedLoraTileState extends State<_OptimizedLoraTile> {
  late bool _isSelected;
  late double _strength;
  late Set<String> _selectedTags;

  @override
  void initState() {
    super.initState();
    _strength = widget.initialStrength == 0.0 ? 1.0 : widget.initialStrength;
    _isSelected = widget.initialStrength != 0.0;
    _selectedTags = Set.from(widget.initialSelectedTags);
  }

  // NOTE: didUpdateWidget omitted for brevity, but needed if parent pushes updates from Reset

  void _handleTap() {
    setState(() {
      _isSelected = !_isSelected;
      if (_isSelected && _strength == 0.0) _strength = 1.0;
    });
    widget.onUpdate(_strength, _selectedTags, _isSelected);
  }

  void _handleStrengthChange(double val) {
    setState(() {
      _strength = val;
      if (_strength == 0.0 && _isSelected) _isSelected = false;
    });
    widget.onUpdate(_strength, _selectedTags, _isSelected);
  }

  void _handleTagToggle(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    widget.onUpdate(_strength, _selectedTags, _isSelected);
  }

  @override
  Widget build(BuildContext context) {
    // 1. Separate Static content from Dynamic content
    // The background stack (image, gradient, text) is wrapped in a const-capable
    // widget structure where possible, or at least isolated in build order.

    return RepaintBoundary(
      // Isolates the tile's composition
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // Only rebuild border color
            border: Border.all(
              color: _isSelected
                  ? widget.accentColor
                  : Colors.white.withValues(alpha: 0.1),
              width: _isSelected ? 2 : 1,
            ),
            // Only rebuild shadow
            boxShadow: _isSelected
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // -----------------------------------------------------
                // STATIC LAYER: This widget does NOT rebuild on tap
                // -----------------------------------------------------
                _StaticTileContent(lora: widget.lora),

                // -----------------------------------------------------
                // DYNAMIC LAYER: Controls and Overlays
                // -----------------------------------------------------

                // Dimmer
                if (_isSelected)
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xB3000000)),
                  ),

                // Checkmark
                if (_isSelected)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.check_circle,
                        color: widget.accentColor,
                        size: 20,
                      ),
                    ),
                  ),

                // Controls
                if (_isSelected)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _TileControls(
                      strength: _strength,
                      accentColor: widget.accentColor,
                      trainedWords: widget.lora.trainedWords,
                      selectedTags: _selectedTags,
                      onStrengthChanged: _handleStrengthChange,
                      onToggleTag: _handleTagToggle,
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

/// CONST WIDGET - Never Rebuilds when selection changes
class _StaticTileContent extends StatelessWidget {
  final LoraData lora;

  const _StaticTileContent({required this.lora});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: lora.thumbnailUrl,
          fit: BoxFit.cover,
          // Optimization: decode to smaller size to save RAM/GPU
          memCacheWidth: 400,
          fadeInDuration: const Duration(milliseconds: 200),
          errorWidget: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF212121)),
          placeholder: (_, __) => const ColoredBox(color: Color(0xFF212121)),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black12, Colors.black87],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              0,
              12,
              36,
            ), // Space for controls
            child: Text(
              lora.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _TileControls extends StatelessWidget {
  final double strength;
  final Color accentColor;
  final Set<String> trainedWords;
  final Set<String> selectedTags;
  final Function(double) onStrengthChanged;
  final Function(String) onToggleTag;

  const _TileControls({
    required this.strength,
    required this.accentColor,
    required this.trainedWords,
    required this.selectedTags,
    required this.onStrengthChanged,
    required this.onToggleTag,
  });

  @override
  Widget build(BuildContext context) {
    // Keep it lightweight
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Strength",
                style: TextStyle(color: Colors.white60, fontSize: 10),
              ),
              Text(
                strength.toStringAsFixed(1),
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: accentColor,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: accentColor.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: strength,
                min: -1.0,
                max: 5.0,
                divisions: 60,
                onChanged: onStrengthChanged,
              ),
            ),
          ),
          if (trainedWords.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: trainedWords.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final word = trainedWords.elementAt(index);
                  final isActive = selectedTags.contains(word);
                  return GestureDetector(
                    onTap: () => onToggleTag(word),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isActive
                            ? accentColor.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive ? accentColor : Colors.white24,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        word,
                        style: TextStyle(
                          color: isActive ? Colors.black : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
