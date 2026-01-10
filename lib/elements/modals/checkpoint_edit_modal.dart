// ==================== Checkpoint Edit Modal ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_modal.dart';
import 'package:sd_companion/elements/widgets/glass_header.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/glass_slider.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/utils/sampler_names.dart';

// Checkpoint Edit Modal Implementation

/// Helper function to show the editor modal
void showCheckpointEditorModal({
  required BuildContext context,
  required String modelName,
  required dynamic data, // Your CheckpointData class
  required VoidCallback onSave,
}) {
  GlassModal.show(
    context,
    heightFactor: 0.9,
    child: CheckpointEditorModal(
      modelName: modelName,
      data: data,
      onSave: onSave,
    ),
  );
}

class CheckpointEditorModal extends StatefulWidget {
  final String modelName;
  final dynamic data;
  final VoidCallback onSave;

  const CheckpointEditorModal({
    super.key,
    required this.modelName,
    required this.data,
    required this.onSave,
  });

  @override
  State<CheckpointEditorModal> createState() => _CheckpointEditorModalState();
}

class _CheckpointEditorModalState extends State<CheckpointEditorModal> {
  // ===== Class Variables ===== //
  late TextEditingController _urlController;
  late String _baseModel;
  late String _sampler;
  late double _steps;
  late double _cfg;
  late double _width;
  late double _height;

  final List<String> _baseModelOptions = [
    'SD 1.5',
    'SDXL 1.0',
    'SDXL Turbo',
    'Pony',
    'Flux',
    'Other',
  ];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    // Initialize state from existing data
    _urlController = TextEditingController(text: widget.data.imageURL);

    _baseModel = (widget.data.baseModel?.isNotEmpty == true)
        ? widget.data.baseModel
        : 'Other';

    // Ensure the current base model is in the list
    if (!_baseModelOptions.contains(_baseModel)) {
      _baseModelOptions.add(_baseModel);
    }

    _sampler = widget.data.samplingMethod ?? 'Euler a';
    _steps = (widget.data.samplingSteps ?? 20).toDouble();
    _cfg = (widget.data.cfgScale ?? 7.0).toDouble();
    _width = (widget.data.resolutionWidth ?? 512).toDouble();
    _height = (widget.data.resolutionHeight ?? 512).toDouble();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ===== Class Methods ===== //

  void _handleSave() {
    // Update the data object
    widget.data
      ..imageURL = _urlController.text
      ..baseModel = _baseModel
      ..samplingMethod = _sampler
      ..samplingSteps = _steps.toInt()
      ..cfgScale = _cfg
      ..resolutionWidth = _width.toInt()
      ..resolutionHeight = _height.toInt();

    // Trigger the save callback (StorageService save)
    widget.onSave();
  }

  // ===== Class Widgets ===== //

  Widget _buildSectionLabel(String text) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: AppTheme.accentPrimary.withValues(alpha: 0.8),
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
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorderLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : null,
              dropdownColor: AppTheme
                  .surfaceCard, // Matches glass background color roughly
              borderRadius: BorderRadius.circular(16),
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white54,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              items: items.map((String val) {
                return DropdownMenuItem<String>(value: val, child: Text(val));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ===== Header ===== //
        GlassHeader(
          title: 'Edit Config',
          subtitle: widget.modelName,
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ),

        // ===== Scrollable Form ===== //
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            physics: const BouncingScrollPhysics(),
            children: [
              const SizedBox(height: 10),

              // --- Identity Section ---
              _buildSectionLabel("IDENTITY"),
              const SizedBox(height: 12),

              _buildDropdown(
                label: 'Base Model Architecture',
                value: _baseModel,
                items: _baseModelOptions,
                onChanged: (val) => setState(() => _baseModel = val!),
              ),

              const SizedBox(height: 20),

              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  "Preview Image URL",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GlassInput(
                controller: _urlController,
                hintText: "https://civitai.com/image...",
                prefixIcon: Icons.link_rounded,
                maxLines: 1,
              ),

              const SizedBox(height: 32),

              // --- Defaults Section ---
              _buildSectionLabel("DEFAULT PARAMETERS"),
              const SizedBox(height: 16),

              _buildDropdown(
                label: 'Default Sampler',
                value: _sampler,
                items: samplerNames, // From logic/utils
                onChanged: (val) => setState(() => _sampler = val!),
              ),

              const SizedBox(height: 24),

              GlassSlider(
                label: "Steps",
                value: _steps,
                min: 1,
                max: 60,
                accentColor: AppTheme.accentSecondary,
                onChanged: (v) => setState(() => _steps = v),
                valueFormatter: (v) => v.toInt().toString(),
              ),

              const SizedBox(height: 24),

              GlassSlider(
                label: "CFG Scale",
                value: _cfg,
                min: 1,
                max: 20,
                divisions: 38,
                accentColor: AppTheme.accentSecondary,
                onChanged: (v) => setState(() => _cfg = v),
                valueFormatter: (v) => v.toStringAsFixed(1),
              ),

              const SizedBox(height: 24),

              GlassSlider(
                label: "Width",
                value: _width,
                min: 256,
                max: 2048,
                divisions: 56,
                accentColor: AppTheme.accentTertiary,
                onChanged: (v) => setState(
                  () => _width = ((v / 32).round() * 32.0).toDouble(),
                ),
                valueFormatter: (v) => '${v.toInt()}px',
              ),

              const SizedBox(height: 24),

              GlassSlider(
                label: "Height",
                value: _height,
                min: 256,
                max: 2048,
                divisions: 56,
                accentColor: AppTheme.accentTertiary,
                onChanged: (v) => setState(
                  () => _height = ((v / 32).round() * 32.0).toDouble(),
                ),
                valueFormatter: (v) => '${v.toInt()}px',
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),

        // ===== Save Button ===== //
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Save Configuration',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
