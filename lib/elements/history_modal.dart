import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/elements/animated_tiles.dart';

void showInpaintHistory(BuildContext context, Function(String) onSelect) {
  // Create a local copy of the list
  final historyList = globalInpaintHistory.toList().reversed.toList();
  
  // State for multi-selection
  bool isMultiSelectMode = false;
  Set<String> selectedItems = {};

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter modalSetState) {
          
          void deleteSelected() {
            globalInpaintHistory.removeAll(selectedItems);
            saveInpaintHistory();
            modalSetState(() {
              historyList.removeWhere((item) => selectedItems.contains(item));
              selectedItems.clear();
              isMultiSelectMode = false;
            });
          }

          void clearAll() {
            globalInpaintHistory.clear();
            saveInpaintHistory();
            modalSetState(() {
              historyList.clear();
            });
            Navigator.pop(context);
          }

          return FractionallySizedBox(
            heightFactor: 0.6,
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
                  // --- HEADER ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history, color: Colors.cyan.shade300, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              isMultiSelectMode ? 'Select Items' : 'Prompt History',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            isMultiSelectMode ? Icons.close : Icons.keyboard_arrow_down,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            if (isMultiSelectMode) {
                              modalSetState(() {
                                isMultiSelectMode = false;
                                selectedItems.clear();
                              });
                            } else {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // --- Clear All Button ---
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    child: (!isMultiSelectMode && historyList.isNotEmpty)
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      backgroundColor: Colors.grey.shade900,
                                      title: const Text('Clear History?', style: TextStyle(color: Colors.white)),
                                      content: const Text('Delete all prompts?', style: TextStyle(color: Colors.white70)),
                                      actions: [
                                        TextButton(
                                          child: const Text('Cancel'),
                                          onPressed: () => Navigator.pop(dialogContext),
                                        ),
                                        TextButton(
                                          child: Text('Clear All', style: TextStyle(color: Colors.red.shade400)),
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            clearAll();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: Icon(Icons.delete_forever, color: Colors.red.shade400, size: 18),
                                label: Text('Clear All', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // --- LIST ---
                  if (historyList.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history_toggle_off, size: 48, color: Colors.white24),
                            const SizedBox(height: 16),
                            Text('No history yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: historyList.length,
                        itemBuilder: (context, index) {
                          final item = historyList[index];
                          final isSelected = selectedItems.contains(item);

                          Widget content = AnimatedHistoryTile(
                            key: ValueKey(item),
                            text: item,
                            isMultiSelectMode: isMultiSelectMode,
                            isSelected: isSelected,
                            onTap: () {
                              modalSetState(() {
                                if (isMultiSelectMode) {
                                  if (isSelected) {
                                    selectedItems.remove(item);
                                    if (selectedItems.isEmpty) isMultiSelectMode = false;
                                  } else {
                                    selectedItems.add(item);
                                  }
                                } else {
                                  // --- FIX IS HERE ---
                                  onSelect(item);         // 1. Send data back
                                  Navigator.pop(context); // 2. Close modal
                                }
                              });
                            },
                            onLongPress: () {
                              modalSetState(() {
                                isMultiSelectMode = true;
                                selectedItems.add(item);
                              });
                            },
                          );

                          if (isMultiSelectMode) return content;

                          return Dismissible(
                            key: Key(item),
                            direction: DismissDirection.endToStart,
                            onDismissed: (direction) {
                              globalInpaintHistory.remove(item);
                              saveInpaintHistory();
                              modalSetState(() {
                                historyList.removeAt(index);
                              });
                            },
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade900.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20.0),
                              child: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
                            ),
                            child: content,
                          );
                        },
                      ),
                    ),

                  // --- BOTTOM BUTTON ---
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SafeArea(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: isMultiSelectMode
                              ? LinearGradient(colors: [Colors.red.shade500, Colors.orange.shade500])
                              : LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade700]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: isMultiSelectMode ? deleteSelected : () => Navigator.pop(context),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(isMultiSelectMode ? Icons.delete_outline : Icons.close, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  isMultiSelectMode ? 'Delete ${selectedItems.length} Selected' : 'Close',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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