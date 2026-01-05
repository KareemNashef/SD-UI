// ==================== Checkpoint Tester Modal ==================== //

import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/elements/animated_tiles.dart';

final samplerNames = [
  "DPM++ 2M",
  "DPM++ SDE",
  "DPM++ 2M SDE",
  "DPM++ 3M SDE",
  "Euler a",
  "Euler",
  "LMS",
  "Heun",
  "DPM2",
  "Restart",
  "DDPM",
  "DDIM",
  "PLMS",
  "UniPC",
  "LCM",
  "DPM++ 2M CFG++",
  "DPM++ SDE CFG++",
  "DPM++ 2M SDE CFG++",
  "DPM++ 3M SDE CFG++",
  "Euler a CFG++",
  "Euler CFG++",
];

enum TestMode { checkpoints, samplers }

void showCheckpointTesterModal(
  BuildContext context,
  Function(TestMode, List<String>) onStartTesting,
) {
  final availableCheckpoints = globalCheckpointDataMap.keys.toList();

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
    builder: (ctx) => _CheckpointTesterModalContent(
      availableCheckpoints: availableCheckpoints,
      onStartTesting: onStartTesting,
    ),
  );
}

class _CheckpointTesterModalContent extends StatefulWidget {
  final List<String> availableCheckpoints;
  final Function(TestMode, List<String>) onStartTesting;

  const _CheckpointTesterModalContent({
    Key? key,
    required this.availableCheckpoints,
    required this.onStartTesting,
  }) : super(key: key);

  @override
  State<_CheckpointTesterModalContent> createState() =>
      _CheckpointTesterModalContentState();
}

class _CheckpointTesterModalContentState
    extends State<_CheckpointTesterModalContent> {
  // State
  late PageController _pageController;
  TestMode _currentMode = TestMode.checkpoints;

  // Selections
  Set<String> _selectedCheckpoints = {};
  Set<String> _selectedSamplers = {};

  // Grouped Data Cache
  late Map<String, List<String>> _groupedCheckpoints;
  late List<String> _sortedGroupKeys;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _organizeCheckpoints();
  }

  void _organizeCheckpoints() {
    _groupedCheckpoints = {};
    
    // Sort keys alphabetically first for internal list order
    final sortedCheckpoints = List<String>.from(widget.availableCheckpoints)..sort();

    for (var name in sortedCheckpoints) {
      final data = globalCheckpointDataMap[name];
      // Fallback if baseModel is empty
      final base = (data?.baseModel != null && data!.baseModel.isNotEmpty)
          ? data.baseModel
          : 'Other';

      if (!_groupedCheckpoints.containsKey(base)) {
        _groupedCheckpoints[base] = [];
      }
      _groupedCheckpoints[base]!.add(name);
    }

    _sortedGroupKeys = _groupedCheckpoints.keys.toList()..sort();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchMode(TestMode mode) {
    setState(() => _currentMode = mode);
    _pageController.animateToPage(
      mode == TestMode.checkpoints ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutQuart,
    );
  }

  void _handlePageChanged(int page) {
    setState(
      () => _currentMode = page == 0 ? TestMode.checkpoints : TestMode.samplers,
    );
  }

  int get _selectionCount => _currentMode == TestMode.checkpoints
      ? _selectedCheckpoints.length
      : _selectedSamplers.length;

  int get _totalCount => _currentMode == TestMode.checkpoints
      ? widget.availableCheckpoints.length
      : samplerNames.length;

  void _toggleSelectAll() {
    setState(() {
      if (_currentMode == TestMode.checkpoints) {
        if (_selectedCheckpoints.length == widget.availableCheckpoints.length) {
          _selectedCheckpoints.clear();
        } else {
          _selectedCheckpoints = Set.from(widget.availableCheckpoints);
        }
      } else {
        if (_selectedSamplers.length == samplerNames.length) {
          _selectedSamplers.clear();
        } else {
          _selectedSamplers = Set.from(samplerNames);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.80,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
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
                        'Test Lab',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
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

            // --- MODE TOGGLE ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                height: 45,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    _buildToggleOption("Checkpoints", TestMode.checkpoints),
                    _buildToggleOption("Samplers", TestMode.samplers),
                  ],
                ),
              ),
            ),

            // --- SELECT ALL ROW ---
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_selectionCount selected',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  InkWell(
                    onTap: _toggleSelectAll,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _selectionCount == _totalCount
                            ? 'Deselect All'
                            : 'Select All',
                        style: TextStyle(
                          color: _currentMode == TestMode.checkpoints
                              ? Colors.cyan.shade300
                              : Colors.purple.shade300,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- SLIDING LIST AREA (PageView) ---
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _handlePageChanged,
                physics: const BouncingScrollPhysics(),
                children: [
                  // PAGE 1: CHECKPOINTS (Grouped by BaseModel)
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: _sortedGroupKeys.length,
                    itemBuilder: (context, groupIndex) {
                      final baseModel = _sortedGroupKeys[groupIndex];
                      final models = _groupedCheckpoints[baseModel]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Section Divider ---
                          Padding(
                            padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.cyan.shade900
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.cyan.shade800, width: 0.5),
                                  ),
                                  child: Text(
                                    baseModel,
                                    style: TextStyle(
                                      color: Colors.cyan.shade100,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Divider(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    thickness: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // --- Items in Group ---
                          ...models.map((name) {
                            final data = globalCheckpointDataMap[name];
                            return AnimatedCheckpointTile(
                              key: ValueKey("ckpt_$name"),
                              name: name,
                              data: data,
                              isSelected: _selectedCheckpoints.contains(name),
                              onTap: () => setState(() {
                                _selectedCheckpoints.contains(name)
                                    ? _selectedCheckpoints.remove(name)
                                    : _selectedCheckpoints.add(name);
                              }),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  ),

                  // PAGE 2: SAMPLERS
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: samplerNames.length,
                    itemBuilder: (context, index) {
                      final name = samplerNames[index];
                      return AnimatedSamplerTile(
                        key: ValueKey("smpl_$name"),
                        name: name,
                        isSelected: _selectedSamplers.contains(name),
                        onTap: () => setState(() {
                          _selectedSamplers.contains(name)
                              ? _selectedSamplers.remove(name)
                              : _selectedSamplers.add(name);
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),

            // --- ACTION BUTTON ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SafeArea(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: _selectionCount == 0
                        ? LinearGradient(
                            colors: [
                              Colors.grey.shade800,
                              Colors.grey.shade700,
                            ],
                          )
                        : _currentMode == TestMode.checkpoints
                        ? LinearGradient(
                            colors: [
                              Colors.cyan.shade500,
                              Colors.lime.shade500,
                            ],
                          )
                        : LinearGradient(
                            colors: [
                              Colors.purple.shade500,
                              Colors.pink.shade500,
                            ],
                          ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _selectionCount == 0
                        ? []
                        : [
                            BoxShadow(
                              color:
                                  (_currentMode == TestMode.checkpoints
                                          ? Colors.cyan
                                          : Colors.purple)
                                      .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _selectionCount == 0
                          ? null
                          : () {
                              Navigator.pop(context);
                              if (_currentMode == TestMode.checkpoints) {
                                widget.onStartTesting(
                                  _currentMode,
                                  _selectedCheckpoints.toList(),
                                );
                              } else {
                                widget.onStartTesting(
                                  _currentMode,
                                  _selectedSamplers.toList(),
                                );
                              }
                            },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            color: _selectionCount == 0
                                ? Colors.white38
                                : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Test ${_currentMode == TestMode.checkpoints ? "Checkpoints" : "Samplers"} ($_selectionCount)',
                            style: TextStyle(
                              color: _selectionCount == 0
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
  }

  Widget _buildToggleOption(String text, TestMode mode) {
    final isSelected = mode == _currentMode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected
                ? (mode == TestMode.checkpoints
                      ? Colors.cyan.shade700
                      : Colors.purple.shade700)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}