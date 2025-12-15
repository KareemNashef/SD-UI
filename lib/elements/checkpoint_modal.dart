import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/elements/animated_tiles.dart';

void showCheckpointTesterModal(
  BuildContext context,
  Function(List<String>) onStartTesting,
) {
  final availableCheckpoints = globalCheckpointDataMap.keys.toList();
  Set<String> selectedCheckpoints = {};

  if (availableCheckpoints.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No checkpoints available'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter modalSetState) {
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
                  // --- HEADER ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.science,
                              color: Colors.cyan.shade300,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Checkpoint Tester',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // --- Select All Row ---
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${selectedCheckpoints.length} selected',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            modalSetState(() {
                              if (selectedCheckpoints.length ==
                                  availableCheckpoints.length) {
                                selectedCheckpoints.clear();
                              } else {
                                selectedCheckpoints = Set.from(
                                  availableCheckpoints,
                                );
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              selectedCheckpoints.length ==
                                      availableCheckpoints.length
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: TextStyle(
                                color: Colors.cyan.shade300,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- LIST ---
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: availableCheckpoints.length,
                      itemBuilder: (context, index) {
                        final checkpointName = availableCheckpoints[index];
                        final data = globalCheckpointDataMap[checkpointName];

                        return AnimatedCheckpointTile(
                          key: ValueKey(checkpointName),
                          name: checkpointName,
                          data: data,
                          isSelected: selectedCheckpoints.contains(
                            checkpointName,
                          ),
                          onTap: () {
                            modalSetState(() {
                              if (selectedCheckpoints.contains(
                                checkpointName,
                              )) {
                                selectedCheckpoints.remove(checkpointName);
                              } else {
                                selectedCheckpoints.add(checkpointName);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),

                  // --- BOTTOM ACTION BUTTON ---
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SafeArea(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: selectedCheckpoints.isEmpty
                              ? LinearGradient(
                                  colors: [
                                    Colors.grey.shade800,
                                    Colors.grey.shade700,
                                  ],
                                )
                              : LinearGradient(
                                  colors: [
                                    Colors.cyan.shade500,
                                    Colors.lime.shade500,
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: selectedCheckpoints.isEmpty
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.cyan.shade500.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: selectedCheckpoints.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    onStartTesting(
                                      selectedCheckpoints.toList(),
                                    );
                                  },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: selectedCheckpoints.isEmpty
                                      ? Colors.white38
                                      : Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Start Testing (${selectedCheckpoints.length})',
                                  style: TextStyle(
                                    color: selectedCheckpoints.isEmpty
                                        ? Colors.white38
                                        : Colors.white,
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
