// ==================== Generation Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/glass_selection_chip.dart';
import 'package:sd_companion/elements/widgets/glass_slider.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

// Generation Settings Implementation

class GenerationSettings extends StatefulWidget {
  const GenerationSettings({super.key});

  @override
  State<GenerationSettings> createState() => GenerationSettingsState();
}

class GenerationSettingsState extends State<GenerationSettings> {
  // ===== Class Variables ===== //
  final _negativePromptController = TextEditingController(text: globalNegativePrompt);
  final _negativeFocusNode = FocusNode();

  final _positivePromptController = TextEditingController(text: globalPositivePrompt);
  final _positiveFocusNode = FocusNode();

  // ===== Lifecycle Methods ===== //

  @override
  void dispose() {
    _negativePromptController.dispose();
    _negativeFocusNode.dispose();
    _positivePromptController.dispose();
    _positiveFocusNode.dispose();
    super.dispose();
  }

  // ===== Class Widgets ===== //

  Widget _buildMainHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentSecondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accentSecondary.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.tune_rounded, color: AppTheme.accentSecondary, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GENERATION',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white54, letterSpacing: 1.5),
            ),
            const SizedBox(height: 2),
            Text(
              'Parameters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.95)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMaskOption(String label, String value) {
    final isSelected = globalMaskFill == value;
    return GlassSelectionChip(
      label: label,
      isSelected: isSelected,
      accentColor: AppTheme.accentPrimary,
      onTap: () => setState(() {
        globalMaskFill = value;
        StorageService.saveMaskFill();
      }),
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GlassContainer(
        backgroundColor: AppTheme.surfaceCard,
        borderColor: AppTheme.glassBorder,
        borderRadius: AppTheme.radiusLarge,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Header ===== //
            _buildMainHeader(),
            const SizedBox(height: 32),

            // ===== Artistic Controls ===== //
            GlassSlider(
              label: 'Mask Blur',
              value: globalMaskBlur.toDouble(),
              min: 0,
              max: 64,
              accentColor: AppTheme.accentSecondary,
              onChanged: (value) {
                setState(() {
                  globalMaskBlur = value.toInt();
                });
              },
              onChangeEnd: (_) => StorageService.saveMaskBlur(),
              valueFormatter: (val) => '${val.toInt()}px',
            ),

            const SizedBox(height: 32),

            // ===== System Controls ===== //
            GlassSlider(
              label: 'Batch Size',
              value: globalBatchSize.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              accentColor: AppTheme.accentTertiary,
              onChanged: (value) {
                setState(() {
                  globalBatchSize = value.toInt();
                });
              },
              onChangeEnd: (_) => StorageService.saveBatchSize(),
              valueFormatter: (val) => val.toInt().toString(),
            ),

            const SizedBox(height: 32),

            // ===== Inpainting Mode ===== //
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.start, children: [_buildMaskOption('Fill', 'fill'), _buildMaskOption('Original', 'original'), _buildMaskOption('Latent Noise', 'latent noise'), _buildMaskOption('Latent Nothing', 'latent nothing')]),

            const SizedBox(height: 32),

            // ===== Positive Prompt ===== //
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'POSITIVE PROMPT',
                  style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 12),
                GlassTextArea(
                  controller: _positivePromptController,
                  focusNode: _positiveFocusNode,
                  hintText: 'cinematic, photo, ultra realistic, detailed...',
                  minLines: 3,
                  maxLines: 5,
                  prefixIcon: Icons.add_circle_outline,
                  accentColor: AppTheme.accentPrimary,
                  onChanged: (value) {
                    globalPositivePrompt = value;
                    StorageService.savePositivePrompt();
                  },
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ===== Negative Prompt ===== //
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEGATIVE PROMPT',
                  style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 12),
                GlassTextArea(
                  controller: _negativePromptController,
                  focusNode: _negativeFocusNode,
                  hintText: 'blur, low quality, watermark, text, bad anatomy...',
                  minLines: 3,
                  maxLines: 5,
                  prefixIcon: Icons.block,
                  accentColor: AppTheme.accentSecondary,
                  onChanged: (value) {
                    globalNegativePrompt = value;
                    StorageService.saveNegativePrompt();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
