import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';

// Intelligent prompt analyzer that extracts and tracks individual elements
class PromptIntelligence {
  static Map<String, PromptElement> analyzeHistory(List<String> prompts) {
    Map<String, PromptElement> elements = {};

    for (String prompt in prompts) {
      List<String> parts = prompt
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      for (String part in parts) {
        String normalized = part.toLowerCase();
        if (elements.containsKey(normalized)) {
          elements[normalized]!.count++;
          elements[normalized]!.lastUsed = DateTime.now();
        } else {
          elements[normalized] = PromptElement(
            text: part,
            count: 1,
            lastUsed: DateTime.now(),
          );
        }
      }
    }

    return elements;
  }

  static List<String> getFrequentElements(
    Map<String, PromptElement> elements, {
    int minCount = 2,
  }) {
    var sorted = elements.values.where((e) => e.count >= minCount).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return sorted.map((e) => e.text).toList();
  }

  static List<String> getRecentElements(
    Map<String, PromptElement> elements, {
    int limit = 20,
  }) {
    var sorted = elements.values.toList()
      ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return sorted.take(limit).map((e) => e.text).toList();
  }
}

class PromptElement {
  String text;
  int count;
  DateTime lastUsed;

  PromptElement({
    required this.text,
    required this.count,
    required this.lastUsed,
  });
}

void showInpaintHistory(BuildContext context, Function(String) onSelect) {
  final historyList = globalInpaintHistory.toList().reversed.toList();

  // Build intelligent prompt composer
  List<String> buildingPrompt = [];
  String searchQuery = '';
  String selectedTab = 'compose'; // 'compose' or 'history'
  bool isMultiSelectMode = false;
  Set<String> selectedForDeletion = {};

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter modalSetState) {
          final intelligence = PromptIntelligence.analyzeHistory(historyList);
          final frequentElements = PromptIntelligence.getFrequentElements(
            intelligence,
            minCount: 1,
          );

          // Filter elements based on search and sort by frequency
          List<String> getFilteredElements() {
            List<String> source = frequentElements;
            List<String> filtered = searchQuery.isEmpty
                ? source
                : source
                      .where(
                        (e) =>
                            e.toLowerCase().contains(searchQuery.toLowerCase()),
                      )
                      .toList();

            // Sort by frequency (most used first)
            filtered.sort((a, b) {
              int countA = intelligence[a.toLowerCase()]?.count ?? 0;
              int countB = intelligence[b.toLowerCase()]?.count ?? 0;
              return countB.compareTo(countA);
            });

            return filtered;
          }

          void toggleInBuild(String element) {
            modalSetState(() {
              if (buildingPrompt.contains(element)) {
                buildingPrompt.remove(element);
              } else {
                buildingPrompt.add(element);
              }
            });
          }

          void removeFromBuild(String element) {
            modalSetState(() {
              buildingPrompt.remove(element);
            });
          }

          void usePrompt() {
            if (buildingPrompt.isNotEmpty) {
              String finalPrompt = buildingPrompt.join(', ');
              onSelect(finalPrompt);
              Navigator.pop(context);
            }
          }

          void useFullPrompt(String prompt) {
            onSelect(prompt);
            Navigator.pop(context);
          }

          void deleteSelectedPrompts() {
            globalInpaintHistory.removeAll(selectedForDeletion);
            saveInpaintHistory();
            modalSetState(() {
              historyList.removeWhere(
                (item) => selectedForDeletion.contains(item),
              );
              selectedForDeletion.clear();
              isMultiSelectMode = false;
            });
          }

          void clearAll() {
            globalInpaintHistory.clear();
            saveInpaintHistory();
            Navigator.pop(context);
          }

          return FractionallySizedBox(
            heightFactor: 0.85,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24.0),
                  topRight: Radius.circular(24.0),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.psychology_outlined,
                              color: Colors.cyan.shade300,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isMultiSelectMode
                                  ? 'Select Prompts'
                                  : 'Prompt Builder',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (historyList.isNotEmpty && !isMultiSelectMode)
                              IconButton(
                                icon: Icon(
                                  Icons.delete_forever,
                                  color: Colors.red.shade400,
                                  size: 20,
                                ),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      backgroundColor: Colors.grey.shade900,
                                      title: const Text(
                                        'Clear All?',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: const Text(
                                        'This will delete all history and learned elements.',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      actions: [
                                        TextButton(
                                          child: const Text('Cancel'),
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Clear',
                                            style: TextStyle(
                                              color: Colors.red.shade400,
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            clearAll();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            IconButton(
                              icon: Icon(
                                isMultiSelectMode
                                    ? Icons.close
                                    : Icons.keyboard_arrow_down,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                if (isMultiSelectMode) {
                                  modalSetState(() {
                                    isMultiSelectMode = false;
                                    selectedForDeletion.clear();
                                  });
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Building Area
                  if (selectedTab == 'compose')
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.cyan.shade900.withValues(alpha: 0.3),
                            Colors.blue.shade900.withValues(alpha: 0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.cyan.shade700.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.construction,
                                color: Colors.cyan.shade300,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Building',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const Spacer(),
                              if (buildingPrompt.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () {
                                    modalSetState(() {
                                      buildingPrompt.clear();
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.clear_all,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  label: const Text(
                                    'Clear',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          buildingPrompt.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Text(
                                      'Tap elements below to build your prompt',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: buildingPrompt.asMap().entries.map((
                                    entry,
                                  ) {
                                    int index = entry.key;
                                    String element = entry.value;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.cyan.shade600,
                                            Colors.blue.shade600,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.cyan.shade700
                                                .withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.6,
                                              ),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            element,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () =>
                                                removeFromBuild(element),
                                            child: Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.white.withValues(
                                                alpha: 0.8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ],
                      ),
                    ),

                  // Tab Bar
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              modalSetState(() {
                                selectedTab = 'compose';
                                searchQuery = '';
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: selectedTab == 'compose'
                                    ? LinearGradient(
                                        colors: [
                                          Colors.cyan.shade700,
                                          Colors.blue.shade700,
                                        ],
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.build_circle_outlined,
                                    color: selectedTab == 'compose'
                                        ? Colors.white
                                        : Colors.white54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Compose',
                                    style: TextStyle(
                                      color: selectedTab == 'compose'
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 13,
                                      fontWeight: selectedTab == 'compose'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              modalSetState(() {
                                selectedTab = 'history';
                                searchQuery = '';
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: selectedTab == 'history'
                                    ? LinearGradient(
                                        colors: [
                                          Colors.cyan.shade700,
                                          Colors.blue.shade700,
                                        ],
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    color: selectedTab == 'history'
                                        ? Colors.white
                                        : Colors.white54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'History',
                                    style: TextStyle(
                                      color: selectedTab == 'history'
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 13,
                                      fontWeight: selectedTab == 'history'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search Bar
                  if (selectedTab == 'compose')
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        onChanged: (value) {
                          modalSetState(() {
                            searchQuery = value;
                          });
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search elements...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.cyan.shade300,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade800,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),

                  // Content Area
                  Expanded(
                    child: historyList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.psychology_outlined,
                                  size: 64,
                                  color: Colors.cyan.shade300.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No history yet',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Start creating to build your library',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : selectedTab == 'history'
                        ? _buildHistoryView(
                            historyList,
                            useFullPrompt,
                            () => isMultiSelectMode,
                            (value) => isMultiSelectMode = value,
                            selectedForDeletion,
                            modalSetState,
                            context,
                          )
                        : _buildElementsView(
                            getFilteredElements(),
                            intelligence,
                            toggleInBuild,
                            buildingPrompt,
                            modalSetState,
                          ),
                  ),

                  // Bottom Action Button
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SafeArea(
                      child: isMultiSelectMode
                          ? AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade600,
                                    Colors.orange.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: deleteSelectedPrompts,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.delete_outline,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Delete ${selectedForDeletion.length} Selected',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : selectedTab == 'compose' &&
                                buildingPrompt.isNotEmpty
                          ? AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.cyan.shade600,
                                    Colors.blue.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.cyan.shade600.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: usePrompt,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Use Prompt (${buildingPrompt.length} elements)',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => Navigator.pop(context),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.close, color: Colors.white70),
                                      SizedBox(width: 8),
                                      Text(
                                        'Close',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildElementsView(
  List<String> elements,
  Map<String, PromptElement> intelligence,
  Function(String) onToggle,
  List<String> buildingPrompt,
  StateSetter setState,
) {
  if (elements.isEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  return ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    itemCount: elements.length,
    itemBuilder: (context, index) {
      final element = elements[index];
      final info = intelligence[element.toLowerCase()]!;
      final isInBuild = buildingPrompt.contains(element);

      return GestureDetector(
        onTap: () => onToggle(element),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: isInBuild
                ? LinearGradient(
                    colors: [
                      Colors.cyan.shade800.withValues(alpha: 0.3),
                      Colors.blue.shade800.withValues(alpha: 0.3),
                    ],
                  )
                : LinearGradient(
                    colors: [Colors.grey.shade800, Colors.grey.shade800],
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isInBuild
                  ? Colors.cyan.shade600.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
              width: isInBuild ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isInBuild
                      ? Colors.cyan.shade700
                      : Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isInBuild ? Icons.check : Icons.add,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      element,
                      style: TextStyle(
                        color: isInBuild ? Colors.cyan.shade200 : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Used ${info.count}x',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.cyan.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${info.count}',
                  style: TextStyle(
                    color: Colors.cyan.shade300,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildHistoryView(
  List<String> historyList,
  Function(String) onSelect,
  bool Function() getMultiSelectMode,
  Function(bool) setMultiSelectMode,
  Set<String> selectedForDeletion,
  StateSetter setState,
  BuildContext context,
) {
  return ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    itemCount: historyList.length,
    itemBuilder: (context, index) {
      final prompt = historyList[index];
      final parts = prompt
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final isSelected = selectedForDeletion.contains(prompt);
      final isMultiSelectMode = getMultiSelectMode();

      Widget card = GestureDetector(
        onTap: () {
          if (isMultiSelectMode) {
            // Toggle selection in multi-select mode
            setState(() {
              if (isSelected) {
                selectedForDeletion.remove(prompt);
                // Exit multi-select mode if nothing is selected
                if (selectedForDeletion.isEmpty) {
                  setMultiSelectMode(false);
                }
              } else {
                selectedForDeletion.add(prompt);
              }
            });
          } else {
            // Normal tap - use the prompt
            onSelect(prompt);
          }
        },
        onLongPress: () {
          // Enter multi-select mode and select this item
          setState(() {
            setMultiSelectMode(true);
            selectedForDeletion.add(prompt);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      Colors.red.shade800.withValues(alpha: 0.5),
                      Colors.orange.shade800.withValues(alpha: 0.5),
                    ],
                  )
                : LinearGradient(
                    colors: [Colors.grey.shade800, Colors.grey.shade800],
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.red.shade600.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isMultiSelectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected
                            ? Colors.red.shade400
                            : Colors.white54,
                        size: 24,
                      ),
                    ),
                  Icon(
                    Icons.description_outlined,
                    color: isSelected
                        ? Colors.red.shade300
                        : Colors.cyan.shade300,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${parts.length} elements',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.red.shade300
                          : Colors.cyan.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: parts.map((part) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.red.shade900.withValues(alpha: 0.3)
                          : Colors.grey.shade700.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      part,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );

      // Only wrap in Dismissible if NOT in multi-select mode
      if (isMultiSelectMode) {
        return card;
      }

      return Dismissible(
        key: Key(prompt),
        direction: DismissDirection.endToStart,
        onDismissed: (direction) {
          globalInpaintHistory.remove(prompt);
          saveInpaintHistory();
          setState(() {
            historyList.removeAt(index);
          });
        },
        background: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.red.shade900.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20.0),
          child: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
        ),
        child: card,
      );
    },
  );
}
