import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/prompt/prompt_intelligence.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_tab_bar.dart';
import 'package:sd_companion/elements/widgets/glass_tile.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// --- Entry Point ---
void showInpaintHistory(BuildContext context, Function(String) onSelect) {
  GlassModal.show(context, child: _PromptIntelligenceSheet(onSelect: onSelect));
}

// --- Main Modal Content ---
class _PromptIntelligenceSheet extends StatefulWidget {
  final Function(String) onSelect;

  const _PromptIntelligenceSheet({required this.onSelect});

  @override
  State<_PromptIntelligenceSheet> createState() =>
      _PromptIntelligenceSheetState();
}

class _PromptIntelligenceSheetState extends State<_PromptIntelligenceSheet>
    with SingleTickerProviderStateMixin {
  late List<String> historyList;
  late TabController _tabController;

  // Data State
  List<String> buildingPrompt = [];
  String searchQuery = '';
  bool isMultiSelectMode = false;
  Set<String> selectedForDeletion = {};

  // Logic helpers
  late Map<String, PromptElement> intelligence;
  late List<String> frequentElements;

  @override
  void initState() {
    super.initState();
    historyList = globalInpaintHistory.toList().reversed.toList();
    _tabController = TabController(length: 2, vsync: this);

    // Initialize Intelligence
    intelligence = PromptIntelligence.analyzeHistory(historyList);
    frequentElements = PromptIntelligence.getFrequentElements(
      intelligence,
      minCount: 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleInBuild(String element) {
    setState(() {
      if (buildingPrompt.contains(element)) {
        buildingPrompt.remove(element);
      } else {
        buildingPrompt.add(element);
      }
    });
  }

  List<String> _getFilteredElements() {
    List<String> source = frequentElements;
    List<String> filtered = searchQuery.isEmpty
        ? source
        : source
              .where((e) => e.toLowerCase().contains(searchQuery.toLowerCase()))
              .toList();

    filtered.sort((a, b) {
      int countA = intelligence[a.toLowerCase()]?.count ?? 0;
      int countB = intelligence[b.toLowerCase()]?.count ?? 0;
      return countB.compareTo(countA);
    });
    return filtered;
  }

  void _deleteSelectedPrompts() {
    globalInpaintHistory.removeAll(selectedForDeletion);
    StorageService.saveInpaintHistory();
    setState(() {
      historyList.removeWhere((item) => selectedForDeletion.contains(item));
      selectedForDeletion.clear();
      isMultiSelectMode = false;
      // Re-analyze
      intelligence = PromptIntelligence.analyzeHistory(historyList);
      frequentElements = PromptIntelligence.getFrequentElements(
        intelligence,
        minCount: 1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassHeader(
          title: isMultiSelectMode ? 'Selection Mode' : 'Prompt Builder',
          trailing: isMultiSelectMode
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
                    setState(() {
                      isMultiSelectMode = false;
                      selectedForDeletion.clear();
                    });
                  },
                )
              : null,
        ),
        const SizedBox(height: 8),
        GlassTabBar(
          controller: _tabController,
          tabs: const ['Compose', 'History'],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildComposeTab(), _buildHistoryTab()],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildComposeTab() {
    return Column(
      children: [
        // Active Draft - Fixed Height, Horizontal Scroll
        Container(
          height: 80, // Fixed size container
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Tiny Label
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ACTIVE DRAFT',
                    style: TextStyle(
                      color: AppTheme.accentPrimary.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  if (buildingPrompt.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => buildingPrompt.clear()),
                      child: const Text(
                        'CLEAR',
                        style: TextStyle(
                          color: Colors.white30,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Horizontal Scrollable List
              Expanded(
                child: buildingPrompt.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select elements below...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: buildingPrompt.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.accentPrimary.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.accentPrimary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  buildingPrompt[index],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => setState(
                                    () => buildingPrompt.removeAt(index),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            height: 40,
            child: TextField(
              onChanged: (value) => setState(() => searchQuery = value),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: AppTheme.accentPrimary,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: 'Search known elements...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppTheme.accentPrimary.withValues(alpha: 0.7),
                  size: 18,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),

        // Elements List
        Expanded(
          child: _getFilteredElements().isEmpty
              ? Center(
                  child: Text(
                    'No elements found',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _getFilteredElements().length,
                  itemBuilder: (context, index) {
                    final element = _getFilteredElements()[index];
                    final info = intelligence[element.toLowerCase()]!;
                    final isInBuild = buildingPrompt.contains(element);

                    return GestureDetector(
                      onTap: () => _toggleInBuild(element),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isInBuild
                              ? AppTheme.accentPrimary.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isInBuild
                                ? AppTheme.accentPrimary.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isInBuild
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: isInBuild
                                  ? AppTheme.accentPrimary
                                  : Colors.white30,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                element,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              '${info.count}x',
                              style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (historyList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 48, color: Colors.white10),
            SizedBox(height: 10),
            Text('No history', style: TextStyle(color: Colors.white30)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      physics: const BouncingScrollPhysics(),
      itemCount: historyList.length,
      itemBuilder: (context, index) {
        final prompt = historyList[index];
        final isSelected = selectedForDeletion.contains(prompt);

        return GlassTile(
          label: prompt,
          isSelected: isSelected,
          accentColor: Colors.red,
          showCheckbox: isMultiSelectMode,
          onTap: () {
            if (isMultiSelectMode) {
              setState(() {
                if (isSelected) {
                  selectedForDeletion.remove(prompt);
                  if (selectedForDeletion.isEmpty) isMultiSelectMode = false;
                } else {
                  selectedForDeletion.add(prompt);
                }
              });
            } else {
              widget.onSelect(prompt);
              Navigator.pop(context);
            }
          },
          onLongPress: () {
            setState(() {
              isMultiSelectMode = true;
              selectedForDeletion.add(prompt);
            });
          },
          padding: const EdgeInsets.all(12),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(top: BorderSide(color: AppTheme.glassBorder)),
      ),
      child: SafeArea(
        child: isMultiSelectMode
            ? SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _deleteSelectedPrompts,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  label: Text('Delete ${selectedForDeletion.length} Selected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            : Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_tabController.index ==
                      0) // Only show Apply on Compose tab usually, but we track UI updates via setState so we check buildingPrompt
                    ElevatedButton(
                      onPressed: buildingPrompt.isNotEmpty
                          ? () {
                              widget.onSelect(buildingPrompt.join(', '));
                              Navigator.pop(context);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buildingPrompt.isNotEmpty
                            ? AppTheme.accentPrimary
                            : Colors.white10,
                        foregroundColor: buildingPrompt.isNotEmpty
                            ? Colors.black
                            : Colors.white38,
                        elevation: buildingPrompt.isNotEmpty ? 8 : 0,
                        shadowColor: AppTheme.accentPrimary.withValues(
                          alpha: 0.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      child: Text(
                        buildingPrompt.isEmpty ? 'Add Elements' : 'Use Prompt',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
