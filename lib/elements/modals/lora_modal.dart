import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/models/lora_data.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_tab_bar.dart';
import 'package:sd_companion/elements/widgets/glass_bottom_bar.dart';
import 'package:sd_companion/elements/widgets/glass_badge.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'dart:collection';

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
  late Map<String, double> _tempSelectedLoras;
  late Map<String, Set<String>> _tempSelectedLoraTags;
  late Map<String, List<LoraData>> _groupedLoras;
  TabController? _tabController;
  bool _isRefreshing = false;
  double _refreshTurns = 0.0;

  @override
  void initState() {
    super.initState();
    _tempSelectedLoras = Map.from(widget.selectedLoras);
    _tempSelectedLoraTags = {};
    widget.selectedLoraTags.forEach((key, value) {
      _tempSelectedLoraTags[key] = Set.from(value);
    });
    _groupLoras();
  }

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

    // Dispose previous controller if exists to prevent leaks during refresh
    _tabController?.dispose();
    _tabController = TabController(length: _groupedLoras.length, vsync: this);
  }

  Future<void> _refreshLoras() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _refreshTurns += 1.0;
      // Optional: Don't clear selections on refresh unless necessary
      // _tempSelectedLoras.clear();
      // _tempSelectedLoraTags.clear();
    });

    await loadLoraDataFromServer();
    if (mounted) {
      setState(() {
        _groupLoras();
        _isRefreshing = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassHeader(
          title: 'LoRA Library',
          trailing: Row(
            children: [
              if (_tempSelectedLoras.isNotEmpty) ...[
                GlassBadge(
                  label: '${_tempSelectedLoras.length} Active',
                  icon: Icons.bolt,
                  accentColor: AppTheme.accentPrimary,
                ),
                const SizedBox(width: 12),
              ],
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
      children: _groupedLoras.values.map((loras) {
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            100,
          ), // Bottom pad for button
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            childAspectRatio: 0.7, // Taller for better visual
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: loras.length,
          itemBuilder: (context, index) {
            final lora = loras[index];
            return RepaintBoundary(
              // Performance optimization
              child: _GlassLoraTile(
                lora: lora,
                isSelected: _tempSelectedLoras.containsKey(lora.name),
                strength: _tempSelectedLoras[lora.name] ?? 0.0,
                selectedTags: _tempSelectedLoraTags[lora.name] ?? {},
                accentColor: AppTheme.accentPrimary,
                onTap: () {
                  setState(() {
                    if (_tempSelectedLoras.containsKey(lora.name)) {
                      _tempSelectedLoras.remove(lora.name);
                      _tempSelectedLoraTags.remove(lora.name);
                    } else {
                      _tempSelectedLoras[lora.name] = 1.0;
                    }
                  });
                },
                onStrengthChanged: (val) {
                  // We update logic but rely on tile to repaint efficiently
                  setState(() {
                    if (val == 0) {
                      _tempSelectedLoras.remove(lora.name);
                      _tempSelectedLoraTags.remove(lora.name);
                    } else {
                      _tempSelectedLoras[lora.name] = val;
                    }
                  });
                },
                onToggleTag: (tag) {
                  setState(() {
                    if (!_tempSelectedLoraTags.containsKey(lora.name)) {
                      _tempSelectedLoraTags[lora.name] = {};
                    }
                    final tags = _tempSelectedLoraTags[lora.name]!;
                    if (tags.contains(tag)) {
                      tags.remove(tag);
                    } else {
                      tags.add(tag);
                    }
                  });
                },
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildGlassBottomBar() {
    return GlassBottomBar(
      secondaryLabel: 'Reset',
      onSecondary: () {
        setState(() {
          _tempSelectedLoras.clear();
          _tempSelectedLoraTags.clear();
        });
      },
      primaryLabel: _tempSelectedLoras.isEmpty ? 'Cancel' : 'Apply Changes',
      onPrimary: () {
        widget.onApply(_tempSelectedLoras, _tempSelectedLoraTags);
        Navigator.pop(context);
      },
      primaryEnabled: true,
      primaryAccentColor: AppTheme.accentPrimary,
    );
  }
}

class _GlassLoraTile extends StatelessWidget {
  final LoraData lora;
  final bool isSelected;
  final double strength;
  final Set<String> selectedTags;
  final VoidCallback onTap;
  final Function(double) onStrengthChanged;
  final Function(String) onToggleTag;
  final Color accentColor;

  const _GlassLoraTile({
    required this.lora,
    required this.isSelected,
    required this.strength,
    required this.selectedTags,
    required this.onTap,
    required this.onStrengthChanged,
    required this.onToggleTag,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? accentColor
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // Background Image
              Positioned.fill(
                child: Image.network(
                  lora.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (c, o, s) => Container(
                    color: Colors.grey.shade900,
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white24,
                    ),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey.shade900,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                          color: Colors.white24,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Gradient Overlay (Always visible for text readability)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),

              // Glass Overlay when selected
              if (isSelected)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ),

              // Title and content
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      lora.displayName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.w900
                            : FontWeight.bold,
                        fontSize: isSelected ? 16 : 13,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                      maxLines: isSelected ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Controls (Only visible when selected)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: isSelected
                        ? _buildControls()
                        : const SizedBox.shrink(),
                  ),
                ],
              ),

              // Selection Checkmark Badge
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    // Fix: Convert the Set to a List so we can access it by index in the ListView
    final trainedWordsList = lora.trainedWords.toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Strength Label & Value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Strength Label
              const Text(
                "Strength",
                style: TextStyle(color: Colors.white60, fontSize: 10),
              ),

              // Strength Value
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
          // Slider
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: accentColor,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
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

          const SizedBox(height: 4),

          // Tags - Horizontally Scrollable
          if (trainedWordsList.isNotEmpty)
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: trainedWordsList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  // Now accessing from the converted List
                  final word = trainedWordsList[index];
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
      ),
    );
  }
}
