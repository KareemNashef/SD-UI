// ==================== Generic Option Select Modal ==================== //
//
// Same look as SamplerSelectModal/SchedulerSelectModal, but generic over
// whatever option list a ComfyUI COMBO widget reports - used for Workflow
// Settings controls so a Comfy "Sampler" tile opens the exact same kind of
// picker a Forge "Sampling Method" tile does.

import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_tile.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

void showGenericOptionSelectModal({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<String> options,
  required String current,
  Color? accentColor,
  required ValueChanged<String> onSelect,
}) {
  GlassModal.show(
    context,
    heightFactor: 0.75,
    child: _GenericOptionSelectModal(
      title: title,
      subtitle: subtitle,
      options: options,
      current: current,
      accentColor: accentColor,
      onSelect: onSelect,
    ),
  );
}

class _GenericOptionSelectModal extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<String> options;
  final String current;
  final Color? accentColor;
  final ValueChanged<String> onSelect;

  const _GenericOptionSelectModal({
    required this.title,
    this.subtitle,
    required this.options,
    required this.current,
    this.accentColor,
    required this.onSelect,
  });

  @override
  State<_GenericOptionSelectModal> createState() => _GenericOptionSelectModalState();
}

class _GenericOptionSelectModalState extends State<_GenericOptionSelectModal> {
  final TextEditingController _searchController = TextEditingController();
  late List<String> _filtered = widget.options;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.options
          : widget.options.where((o) => o.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? AppTheme.accentPrimary;

    return Column(
      children: [
        GlassHeader(
          title: widget.title,
          subtitle: widget.subtitle,
          iconColor: accent,
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        if (widget.options.length > 8)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GlassInput(
              controller: _searchController,
              hintText: 'Search...',
              prefixIcon: Icons.search,
              maxLines: 1,
            ),
          ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: _filtered.length,
            itemBuilder: (context, index) {
              final option = _filtered[index];
              final isSelected = option == widget.current;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassTile(
                  label: option,
                  isSelected: isSelected,
                  accentColor: accent,
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
