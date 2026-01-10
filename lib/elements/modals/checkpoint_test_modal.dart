import 'package:flutter/material.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/utils/sampler_names.dart';
import 'package:sd_companion/logic/utils/test_mode.dart';
import 'package:sd_companion/logic/utils/checkpoint_organizer.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_tab_bar.dart';
import 'package:sd_companion/elements/widgets/glass_bottom_bar.dart';
import 'package:sd_companion/elements/widgets/glass_card.dart';
import 'package:sd_companion/elements/widgets/glass_tile.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

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

  GlassModal.show(
    context,
    child: _CheckpointTesterModalContent(
      availableCheckpoints: availableCheckpoints,
      onStartTesting: onStartTesting,
    ),
  );
}

class _CheckpointTesterModalContent extends StatefulWidget {
  final List<String> availableCheckpoints;
  final Function(TestMode, List<String>) onStartTesting;

  const _CheckpointTesterModalContent({
    required this.availableCheckpoints,
    required this.onStartTesting,
  });

  @override
  State<_CheckpointTesterModalContent> createState() =>
      _CheckpointTesterModalContentState();
}

class _CheckpointTesterModalContentState
    extends State<_CheckpointTesterModalContent>
    with SingleTickerProviderStateMixin {
  // State
  late TabController _tabController;
  TestMode _currentMode = TestMode.checkpoints;

  // Selections
  Set<String> _selectedCheckpoints = {};
  Set<String> _selectedSamplers = {};

  // Grouped Data Cache
  Map<String, List<String>> _groupedCheckpoints = {};
  List<String> _sortedGroupKeys = [];

  Color get _activeAccent => _currentMode == TestMode.checkpoints
      ? AppTheme.accentPrimary
      : AppTheme.accentTertiary;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentMode = _tabController.index == 0
              ? TestMode.checkpoints
              : TestMode.samplers;
        });
      }
    });
    _organizeCheckpoints();
  }

  void _organizeCheckpoints() {
    _groupedCheckpoints = groupCheckpointsByBaseModel();
    _sortedGroupKeys = getSortedBaseModelKeys();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return Column(
      children: [
        GlassHeader(
          title: 'Test Lab',
          icon: Icons.science_outlined,
          iconColor: _activeAccent,
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        GlassTabBar(
          controller: _tabController,
          tabs: const ['Checkpoints', 'Samplers'],
        ),
        _buildSelectionHeader(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const BouncingScrollPhysics(),
            children: [_buildCheckpointsList(), _buildSamplersList()],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildSelectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              '$_selectionCount selected',
              key: ValueKey("sel_$_selectionCount"),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleSelectAll,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _activeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _activeAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _selectionCount == _totalCount ? 'None' : 'All',
                  style: TextStyle(
                    color: _activeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Content Lists ---

  Widget _buildCheckpointsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: _sortedGroupKeys.length,
      itemBuilder: (context, groupIndex) {
        final baseModel = _sortedGroupKeys[groupIndex];
        final models = _groupedCheckpoints[baseModel]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20.0, bottom: 12.0, left: 8),
              child: Row(
                children: [
                  Text(
                    baseModel.toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.accentPrimary.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
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
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75, // Taller aspect ratio for images
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: models.length,
              itemBuilder: (context, index) {
                final name = models[index];
                final data = globalCheckpointDataMap[name];
                final isSelected = _selectedCheckpoints.contains(name);

                return GlassCard(
                  name: name,
                  imageUrl: data?.imageURL,
                  isSelected: isSelected,
                  accentColor: AppTheme.accentPrimary,
                  onTap: () => setState(() {
                    isSelected
                        ? _selectedCheckpoints.remove(name)
                        : _selectedCheckpoints.add(name);
                  }),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSamplersList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: samplerNames.length,
      itemBuilder: (context, index) {
        final name = samplerNames[index];
        final isSelected = _selectedSamplers.contains(name);

        return GlassTile(
          label: name,
          isSelected: isSelected,
          accentColor: AppTheme.accentTertiary,
          leadingIcon: Icons.waves,
          onTap: () => setState(() {
            isSelected
                ? _selectedSamplers.remove(name)
                : _selectedSamplers.add(name);
          }),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return GlassBottomBar(
      primaryLabel: 'Start Test ($_selectionCount)',
      onPrimary: _selectionCount == 0
          ? null
          : () {
              Navigator.pop(context);
              if (_currentMode == TestMode.checkpoints) {
                widget.onStartTesting(
                  _currentMode,
                  _selectedCheckpoints.toList(),
                );
              } else {
                widget.onStartTesting(_currentMode, _selectedSamplers.toList());
              }
            },
      primaryEnabled: _selectionCount > 0,
      primaryAccentColor: _activeAccent,
    );
  }
}
