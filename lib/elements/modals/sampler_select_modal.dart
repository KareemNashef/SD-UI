// ==================== Sampler Select Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_tile.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/utils/sampler_names.dart';

// Sampler Select Modal Implementation

void showSamplerSelectModal({
  required BuildContext context,
  required String currentSampler,
  required ValueChanged<String> onSelect,
}) {
  GlassModal.show(
    context,
    heightFactor: 0.75,
    child: SamplerSelectModal(
      currentSampler: currentSampler,
      onSelect: onSelect,
    ),
  );
}

class SamplerSelectModal extends StatefulWidget {
  final String currentSampler;
  final ValueChanged<String> onSelect;

  const SamplerSelectModal({
    super.key,
    required this.currentSampler,
    required this.onSelect,
  });

  @override
  State<SamplerSelectModal> createState() => _SamplerSelectModalState();
}

class _SamplerSelectModalState extends State<SamplerSelectModal> {
  // ===== Class Variables ===== //
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredSamplers = [];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    _filteredSamplers = samplerNames;
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
        _filteredSamplers = samplerNames;
      } else {
        _filteredSamplers = samplerNames
            .where((sampler) => sampler.toLowerCase().contains(query))
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
          title: 'Sampler',
          subtitle: 'Algorithm Selection',
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
            hintText: 'Search samplers...',
            prefixIcon: Icons.search,
            maxLines: 1,
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: _filteredSamplers.length,
            itemBuilder: (context, index) {
              final option = _filteredSamplers[index];
              final isSelected = option == widget.currentSampler;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassTile(
                  label: option,
                  isSelected: isSelected,
                  accentColor: AppTheme.accentSecondary,
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
