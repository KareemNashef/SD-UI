import 'package:flutter/material.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_input.dart';
import 'package:sd_companion/elements/widgets/glass_selection_chip.dart';
import 'package:sd_companion/elements/widgets/glass_slider.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

class GenerationSettings extends StatefulWidget {
  const GenerationSettings({super.key});

  @override
  State<GenerationSettings> createState() => GenerationSettingsState();
}

class GenerationSettingsState extends State<GenerationSettings> {
  final _negativePromptController = TextEditingController(
    text: globalNegativePrompt,
  );

  @override
  void dispose() {
    _negativePromptController.dispose();
    super.dispose();
  }

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
            _buildSectionHeader('IMAGE ADJUSTMENTS', Icons.brush_outlined),
            const SizedBox(height: 20),

            GlassSlider(
              label: 'Mask Blur',
              value: globalMaskBlur.toDouble(),
              min: 0,
              max: 64,
              accentColor: AppTheme.accentSecondary,
              onChanged: (value) {
                setState(() {
                  globalMaskBlur = value.toInt();
                  StorageService.saveMaskBlur();
                });
              },
              valueFormatter: (val) => '${val.toInt()}px',
            ),

            const SizedBox(height: 32),

            // ===== System Controls ===== //
            _buildSectionHeader('BATCH PROCESSING', Icons.layers_outlined),
            const SizedBox(height: 20),

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
                  StorageService.saveBatchSize();
                });
              },
              valueFormatter: (val) => val.toInt().toString(),
            ),

            const SizedBox(height: 32),

            // ===== Inpainting Mode ===== //
            _buildSectionHeader(
              'INPAINT FILL MODE',
              Icons.format_paint_outlined,
            ),
            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    _buildMaskOption('Fill', 'fill'),
                    _buildMaskOption('Original', 'original'),
                    _buildMaskOption('Latent Noise', 'latent noise'),
                    _buildMaskOption('Latent Nothing', 'latent nothing'),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // ===== Negative Prompt ===== //
            Row(
              children: [
                Icon(
                  Icons.remove_circle_outline,
                  color: AppTheme.warning.withValues(alpha: 0.8),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'NEGATIVE PROMPT',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassInput(
              controller: _negativePromptController,
              hintText: 'blur, low quality, watermark, text, bad anatomy...',
              maxLines: 3,
              prefixIcon: Icons.block_flipped,
              onChanged: (value) {
                globalNegativePrompt = value;
                StorageService.saveNegativePrompt();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentSecondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.accentSecondary.withValues(alpha: 0.3),
            ),
          ),
          child: const Icon(
            Icons.tune_rounded,
            color: AppTheme.accentSecondary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GENERATION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Parameters',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white24, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.05),
          ),
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
}
