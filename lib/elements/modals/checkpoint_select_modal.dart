// ==================== Checkpoint Select Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_card.dart';
import 'package:sd_companion/elements/widgets/glass_refresh_button.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'checkpoint_edit_modal.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';
import 'package:sd_companion/logic/utils/checkpoint_organizer.dart';

// Checkpoint Select Modal Implementation

void showCheckpointSelectModal({
  required BuildContext context,
  required ValueChanged<String> onSelect,
}) {
  GlassModal.show(
    context,
    heightFactor: 0.85,
    child: CheckpointSelectModal(onSelect: onSelect),
  );
}

class CheckpointSelectModal extends StatefulWidget {
  final ValueChanged<String> onSelect;

  const CheckpointSelectModal({super.key, required this.onSelect});

  @override
  State<CheckpointSelectModal> createState() => _CheckpointSelectModalState();
}

class _CheckpointSelectModalState extends State<CheckpointSelectModal> {
  // ===== Class Variables ===== //
  bool _isRefreshing = false;

  // ===== Lifecycle Methods ===== //
  // None explicit

  // ===== Class Methods ===== //
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    // Logic from api_calls.dart
    await syncCheckpointDataFromServer(force: true);

    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  void _handleEdit(String modelName) {
    final data = globalCheckpointDataMap[modelName];
    if (data == null) return;

    showCheckpointEditorModal(
      context: context,
      modelName: modelName,
      data: data,
      onSave: () {
        StorageService.saveCheckpointDataMap();
        setState(() {}); // Rebuild to show updated images/names
        // Note: The editor modal closes itself, we stay in the library
      },
    );
  }

  // ===== Class Widgets ===== //
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            "No models found",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _handleRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text("Refresh Server"),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accentPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    // Get organized data
    final groupedModels = groupCheckpointsByBaseModel();
    final sortedGroupKeys = getSortedBaseModelKeys();

    return Column(
      children: [
        // Header
        GlassHeader(
          title: 'Library',
          subtitle: 'Select or Long Press to Edit',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassRefreshButton(
                isRefreshing: _isRefreshing,
                onTap: _handleRefresh,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: sortedGroupKeys.isEmpty
              ? _buildEmptyState()
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    for (final baseModelName in sortedGroupKeys) ...[
                      // Group Label
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Text(
                                baseModelName.toUpperCase(),
                                style: TextStyle(
                                  color: AppTheme.accentPrimary.withValues(
                                    alpha: 0.9,
                                  ),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Grid
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.75, // Card ratio
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final modelsInGroup = groupedModels[baseModelName]!;
                            final option = modelsInGroup[index];
                            final data = globalCheckpointDataMap[option];
                            final isSelected =
                                option == globalCurrentCheckpointName;

                            return RepaintBoundary(
                              child: GlassCard(
                                name: option,
                                imageUrl: data?.imageURL ?? '',
                                isSelected: isSelected,
                                accentColor: AppTheme.accentPrimary,
                                onTap: () => widget.onSelect(option),
                                onLongPress: () => _handleEdit(option),
                              ),
                            );
                          }, childCount: groupedModels[baseModelName]!.length),
                        ),
                      ),
                    ],
                    // Bottom padding
                    const SliverPadding(padding: EdgeInsets.only(bottom: 30)),
                  ],
                ),
        ),
      ],
    );
  }
}
