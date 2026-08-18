// ==================== Scheduler Select Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_tile.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/utils/scheduler_names.dart';

// Scheduler Select Modal Implementation

void showSchedulerSelectModal({
  required BuildContext context,
  required String currentScheduler,
  required ValueChanged<String> onSelect,
}) {
  GlassModal.show(
    context,
    heightFactor: 0.75,
    child: SchedulerSelectModal(
      currentScheduler: currentScheduler,
      onSelect: onSelect,
    ),
  );
}

class SchedulerSelectModal extends StatefulWidget {
  final String currentScheduler;
  final ValueChanged<String> onSelect;

  const SchedulerSelectModal({
    super.key,
    required this.currentScheduler,
    required this.onSelect,
  });

  @override
  State<SchedulerSelectModal> createState() => _SchedulerSelectModalState();
}

class _SchedulerSelectModalState extends State<SchedulerSelectModal> {
  // ===== Class Variables ===== //
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredSchedulers = [];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    _filteredSchedulers = schedulerNames;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSchedulers = schedulerNames;
      } else {
        _filteredSchedulers = schedulerNames
            .where((scheduler) => scheduler.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        GlassHeader(
          title: 'Scheduler',
          subtitle: 'Schedule Method Selection',
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ),

        // Search Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GlassInput(
            controller: _searchController,
            hintText: 'Search schedulers...',
            prefixIcon: Icons.search,
            maxLines: 1,
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: _filteredSchedulers.length,
            itemBuilder: (context, index) {
              final option = _filteredSchedulers[index];
              final isSelected = option == widget.currentScheduler;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassTile(
                  label: option,
                  isSelected: isSelected,
                  accentColor: AppTheme.accentTertiary,
                  onTap: () {
                    widget.onSelect(option);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
