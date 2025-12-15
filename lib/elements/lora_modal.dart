import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/elements/animated_tiles.dart';

void showLorasModal(
  BuildContext context,
  Map<String, double> selectedLoras,
  Map<String, Set<String>> selectedLoraTags,
  Function(Map<String, double>, Map<String, Set<String>>) onApply,
) {
  // 1. Initialize temporary state from passed data
  Map<String, double> tempSelectedLoras = Map.from(selectedLoras);
  Map<String, Set<String>> tempSelectedLoraTags = {};

  // Deep copy sets to avoid reference issues
  selectedLoraTags.forEach((key, value) {
    tempSelectedLoraTags[key] = Set.from(value);
  });

  Map<String, bool> expandedLoras = {};
  Map<String, bool> showAllTags = {};

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      bool isRefreshing = false;
      double refreshTurns = 0.0;

      return StatefulBuilder(
        builder: (BuildContext context, StateSetter modalSetState) {
          final availableLoras = globalLoraDataMap.keys.toList()..sort();

          return FractionallySizedBox(
            heightFactor: 0.75,
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
                  // --- Header ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_mosaic,
                              color: Colors.cyan.shade300,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Loras',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Refresh Button
                            IconButton(
                              icon: AnimatedRotation(
                                turns: refreshTurns,
                                duration: const Duration(seconds: 1),
                                curve: Curves.easeInOut,
                                child: Icon(
                                  Icons.refresh_rounded,
                                  color: isRefreshing
                                      ? Colors.cyan.shade300
                                      : Colors.white38,
                                ),
                              ),
                              onPressed: () async {
                                if (isRefreshing) return;
                                modalSetState(() {
                                  isRefreshing = true;
                                  refreshTurns += 1.0;
                                });
                                await loadLoraDataFromServer();
                                if (context.mounted) {
                                  modalSetState(() {
                                    isRefreshing = false;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        // Active Count & Close
                        Row(
                          children: [
                            if (tempSelectedLoras.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.cyan.shade900.withValues(
                                    alpha: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.cyan.shade700,
                                  ),
                                ),
                                child: Text(
                                  '${tempSelectedLoras.length} active',
                                  style: TextStyle(
                                    color: Colors.cyan.shade200,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              onPressed: () => Navigator.pop(
                                context,
                              ), // Close without saving (Cancel)
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --- Clear Button ---
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    child: tempSelectedLoras.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  modalSetState(() {
                                    tempSelectedLoras.clear();
                                    tempSelectedLoraTags.clear();
                                    expandedLoras.clear();
                                    showAllTags.clear();
                                  });
                                },
                                icon: Icon(
                                  Icons.clear_all,
                                  color: Colors.red.shade400,
                                  size: 18,
                                ),
                                label: Text(
                                  'Clear All',
                                  style: TextStyle(
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // --- List ---
                  Expanded(
                    child: availableLoras.isEmpty
                        ? Center(
                            child: Text(
                              'No Loras Found',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            itemCount: availableLoras.length,
                            itemBuilder: (context, index) {
                              final loraName = availableLoras[index];
                              final loraData = globalLoraDataMap[loraName]!;

                              return AnimatedLoraTile(
                                key: ValueKey(loraName),
                                loraName: loraName,
                                loraData: loraData,
                                isSelected: tempSelectedLoras.containsKey(
                                  loraName,
                                ),
                                strength: tempSelectedLoras[loraName] ?? 0.0,
                                isExpanded: expandedLoras[loraName] ?? false,
                                selectedTags:
                                    tempSelectedLoraTags[loraName] ?? {},
                                showAllTags: showAllTags[loraName] ?? false,
                                onToggleSelection: () {
                                  modalSetState(() {
                                    if (tempSelectedLoras.containsKey(
                                      loraName,
                                    )) {
                                      tempSelectedLoras.remove(loraName);
                                    } else {
                                      tempSelectedLoras[loraName] = 1.0;
                                    }
                                  });
                                },
                                onStrengthChanged: (val) {
                                  modalSetState(() {
                                    if (val == 0) {
                                      tempSelectedLoras.remove(loraName);
                                      tempSelectedLoraTags.remove(loraName);
                                    } else {
                                      tempSelectedLoras[loraName] = val;
                                    }
                                  });
                                },
                                onToggleExpand: () {
                                  modalSetState(() {
                                    expandedLoras[loraName] =
                                        !(expandedLoras[loraName] ?? false);
                                  });
                                },
                                onToggleTag: (tag) {
                                  modalSetState(() {
                                    if (!tempSelectedLoras.containsKey(
                                      loraName,
                                    )) {
                                      tempSelectedLoras[loraName] = 0.5;
                                    }
                                    if (!tempSelectedLoraTags.containsKey(
                                      loraName,
                                    )) {
                                      tempSelectedLoraTags[loraName] = {};
                                    }
                                    final tags =
                                        tempSelectedLoraTags[loraName]!;
                                    if (tags.contains(tag))
                                      tags.remove(tag);
                                    else
                                      tags.add(tag);
                                  });
                                },
                                onToggleShowAllTags: () {
                                  modalSetState(() {
                                    showAllTags[loraName] =
                                        !(showAllTags[loraName] ?? false);
                                  });
                                },
                              );
                            },
                          ),
                  ),

                  // --- Bottom Apply Button ---
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SafeArea(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: tempSelectedLoras.isEmpty
                                ? [Colors.grey.shade700, Colors.grey.shade600]
                                : [Colors.cyan.shade500, Colors.lime.shade500],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              // --- FIX IS HERE ---
                              // 1. Send data back to parent
                              onApply(tempSelectedLoras, tempSelectedLoraTags);
                              // 2. Close Modal
                              Navigator.pop(context);
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  tempSelectedLoras.isEmpty
                                      ? Icons.close
                                      : Icons.check_rounded,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  tempSelectedLoras.isEmpty
                                      ? 'Close'
                                      : 'Apply ${tempSelectedLoras.length} Lora${tempSelectedLoras.length > 1 ? 's' : ''}',
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
