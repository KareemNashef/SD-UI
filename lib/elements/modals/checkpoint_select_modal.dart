import 'package:flutter/material.dart';

// UI Widgets
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_card.dart';
import 'package:sd_companion/elements/widgets/glass_refresh_button.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';
import 'package:sd_companion/logic/utils/checkpoint_organizer.dart';

// Dependent Modals
import 'checkpoint_edit_modal.dart';

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
  bool _isRefreshing = false;

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
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                  physics: const BouncingScrollPhysics(),
                  itemCount: sortedGroupKeys.length,
                  itemBuilder: (context, groupIndex) {
                    final baseModelName = sortedGroupKeys[groupIndex];
                    final modelsInGroup = groupedModels[baseModelName]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group Label
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 12),
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

                        // Grid
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.75, // Card ratio
                              ),
                          itemCount: modelsInGroup.length,
                          itemBuilder: (context, index) {
                            final option = modelsInGroup[index];
                            final data = globalCheckpointDataMap[option];
                            final isSelected =
                                option == globalCurrentCheckpointName;

                            return GlassCard(
                              name: option,
                              imageUrl: data?.imageURL ?? '',
                              isSelected: isSelected,
                              accentColor: AppTheme.accentPrimary,
                              onTap: () => widget.onSelect(option),
                              onLongPress: () => _handleEdit(option),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

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
}
