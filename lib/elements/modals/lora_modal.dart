// ==================== Lora Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'dart:collection';

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

// Lora Modal Content

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
  // ===== Class Variables ===== //
  late final ValueNotifier<int> _activeCountNotifier;
  late final Map<String, double> _tempSelectedLoras;
  late final Map<String, Set<String>> _tempSelectedLoraTags;

  late Map<String, List<LoraData>> _groupedLoras;
  TabController? _tabController;
  bool _isRefreshing = false;
  double _refreshTurns = 0.0;

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    _tempSelectedLoras = Map.from(widget.selectedLoras);
    _tempSelectedLoraTags = {};
    widget.selectedLoraTags.forEach((key, value) {
      _tempSelectedLoraTags[key] = Set.from(value);
    });

    _activeCountNotifier = ValueNotifier(_tempSelectedLoras.length);
    _groupLoras();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _activeCountNotifier.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  void _groupLoras() {
    final sortedMap = SplayTreeMap<String, List<LoraData>>();
    final loras = globalLoraDataMap.values.toList();
    loras.sort((a, b) => a.displayName.compareTo(b.displayName));

    for (var lora in loras) {
      final key = lora.baseModel;
      if (!sortedMap.containsKey(key)) {
        sortedMap[key] = [];
      }
      sortedMap[key]!.add(lora);
    }
    _groupedLoras = sortedMap;

    _tabController?.dispose();
    _tabController = TabController(
      length: _groupedLoras.length,
      vsync: this,
      animationDuration: const Duration(
        milliseconds: 200,
      ), // Faster transitions
    );
  }

  Future<void> _refreshLoras() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _refreshTurns += 1.0;
    });

    await loadLoraDataFromServer();
    if (mounted) {
      setState(() {
        _groupLoras();
        _isRefreshing = false;
      });
    }
  }

  // ===== Class Widgets ===== //

  Widget _buildTabContent() {
    if (_groupedLoras.isEmpty) {
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
      children: _groupedLoras.values.map((loras) {
        // Use AutomaticKeepAliveClientMixin wrapper to preserve scroll position
        return _GridViewKeepAlive(
          loras: loras,
          tempSelectedLoras: _tempSelectedLoras,
          tempSelectedLoraTags: _tempSelectedLoraTags,
          accentColor: AppTheme.accentPrimary,
          onUpdate: (loraName, strength, tags, isSelected) {
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

            final newCount = _tempSelectedLoras.length;
            if (_activeCountNotifier.value != newCount) {
              _activeCountNotifier.value = newCount;
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildGlassBottomBar() {
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

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header is already lightweight, no changes needed
        GlassHeader(
          title: 'LoRA Library',
          trailing: Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _activeCountNotifier,
                builder: (context, count, child) {
                  if (count == 0) return const SizedBox.shrink();
                  return Row(
                    children: [
                      GlassBadge(
                        label: '$count Active',
                        icon: Icons.bolt,
                        accentColor: AppTheme.accentPrimary,
                      ),
                      const SizedBox(width: 12),
                    ],
                  );
                },
              ),
              Material(
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
                        color: _isRefreshing
                            ? AppTheme.accentPrimary
                            : Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_groupedLoras.isNotEmpty && _tabController != null)
          GlassTabBar(
            controller: _tabController!,
            tabs: _groupedLoras.keys.toList(),
          ),
        Expanded(child: _buildTabContent()),
        _buildGlassBottomBar(),
      ],
    );
  }
}

// Keep-alive wrapper for GridView to preserve state during tab switches
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
  // ===== Lifecycle Methods ===== //
  @override
  bool get wantKeepAlive => true;

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return GridView.builder(
      // Critical optimizations for smooth scrolling
      cacheExtent: 2000, // Preload more items
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

        return _OptimizedLoraTile(
          key: ValueKey(lora.name),
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
// OPTIMIZED TILE - Maximum performance
// -----------------------------------------------------------------------------

class _OptimizedLoraTile extends StatefulWidget {
  final LoraData lora;
  final double initialStrength;
  final Set<String> initialSelectedTags;
  final Color accentColor;
  final Function(double strength, Set<String> tags, bool isSelected) onUpdate;

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
  // ===== Class Variables ===== //
  late bool _isSelected;
  late double _strength;
  late Set<String> _selectedTags;
  late ValueNotifier<double> _strengthNotifier;

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    _strength = widget.initialStrength == 0.0 ? 1.0 : widget.initialStrength;
    _isSelected = widget.initialStrength != 0.0;
    _selectedTags = Set.from(widget.initialSelectedTags);
    _strengthNotifier = ValueNotifier(_strength);
  }

  @override
  void dispose() {
    _strengthNotifier.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  void _notifyParent() {
    widget.onUpdate(_strength, _selectedTags, _isSelected);
  }

  void _toggleSelection() {
    setState(() {
      _isSelected = !_isSelected;
      if (_isSelected && _strength == 0.0) {
        _strength = 1.0;
        _strengthNotifier.value = 1.0;
      }
    });
    _notifyParent();
  }

  void _updateStrength(double val) {
    _strength = val;
    _strengthNotifier.value = val;

    if (_strength == 0.0 && _isSelected) {
      setState(() {
        _isSelected = false;
      });
    }
    _notifyParent();
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    _notifyParent();
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates this tile from others
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _toggleSelection,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: _isSelected
                ? Border.all(color: widget.accentColor, width: 2)
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
            boxShadow: _isSelected
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Cached Network Image - MAJOR PERFORMANCE BOOST
                _TileImage(url: widget.lora.thumbnailUrl),

                // 2. Static Gradient Overlay
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black12,
                          Colors.black87,
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),

                // 3. Selection Dimmer - Simple and fast
                if (_isSelected)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0xB3000000), // 70% opacity
                    ),
                  ),

                // 4. Content
                Column(
                  children: [
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
                      )
                    else
                      const SizedBox(height: 36),

                    const Spacer(),

                    // Title
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        widget.lora.displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: _isSelected
                              ? FontWeight.w900
                              : FontWeight.bold,
                          fontSize: 13,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Controls - only render when selected
                    if (_isSelected)
                      _TileControls(
                        strengthNotifier: _strengthNotifier,
                        accentColor: widget.accentColor,
                        trainedWords: widget.lora.trainedWords,
                        selectedTags: _selectedTags,
                        onStrengthChanged: _updateStrength,
                        onToggleTag: _toggleTag,
                      )
                    else
                      const SizedBox(height: 4),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// High-performance Cached Image Widget
class _TileImage extends StatelessWidget {
  final String url;
  const _TileImage({required this.url});

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 440, // 2x resolution for quality
      memCacheHeight: 630,
      maxWidthDiskCache: 440,
      maxHeightDiskCache: 630,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, url) => Container(
        color: const Color(0xFF212121),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white24),
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: const Color(0xFF212121),
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white24, size: 32),
        ),
      ),
    );
  }
}

// Slider controls with ValueNotifier optimization
class _TileControls extends StatelessWidget {
  final ValueNotifier<double> strengthNotifier;
  final Color accentColor;
  final Set<String> trainedWords;
  final Set<String> selectedTags;
  final Function(double) onStrengthChanged;
  final Function(String) onToggleTag;

  const _TileControls({
    required this.strengthNotifier,
    required this.accentColor,
    required this.trainedWords,
    required this.selectedTags,
    required this.onStrengthChanged,
    required this.onToggleTag,
  });

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final wordsList = trainedWords.toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Only the slider value rebuilds during interaction
          ValueListenableBuilder<double>(
            valueListenable: strengthNotifier,
            builder: (context, strength, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
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
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
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
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          // Tag chips
          if (wordsList.isNotEmpty)
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: wordsList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final word = wordsList[index];
                  final isActive = selectedTags.contains(word);
                  return GestureDetector(
                    onTap: () => onToggleTag(word),
                    behavior: HitTestBehavior.opaque,
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
      ),
    );
  }
}
