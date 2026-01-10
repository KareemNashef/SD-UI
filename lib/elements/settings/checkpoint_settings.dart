// ==================== Checkpoint Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/checkpoint_select_modal.dart';
import 'package:sd_companion/elements/modals/sampler_select_modal.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_slider.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/storage/storage_service.dart';

// Checkpoint Settings Implementation

/// Main Widget for the Checkpoint Settings Section
class CheckpointSettings extends StatefulWidget {
  const CheckpointSettings({super.key});

  @override
  State<CheckpointSettings> createState() => CheckpointSettingsState();
}

class CheckpointSettingsState extends State<CheckpointSettings> {
  // ===== Class Variables ===== //
  bool _isChangingCheckpoint = false;

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    syncActiveCheckpointSettings();
  }

  // ===== Class Methods ===== //

  void _applyModelDefaults(String modelName) {
    final data = globalCheckpointDataMap[modelName];
    if (data != null) {
      setState(() {
        globalCurrentSamplingSteps = data.samplingSteps;
        globalCurrentSamplingMethod = data.samplingMethod;
        globalCurrentCfgScale = data.cfgScale;
        globalDenoiseStrength = data.denoisingStrength;
        globalCurrentResolutionWidth = data.resolutionWidth;
        globalCurrentResolutionHeight = data.resolutionHeight;
        StorageService.saveCheckpointDataMap();
      });
    }
  }

  // ===== Class Widgets ===== //

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentPrimary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.accentPrimary.withValues(alpha: 0.3),
            ),
          ),
          child: const Icon(
            Icons.dns_rounded,
            color: AppTheme.accentPrimary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CHECKPOINT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Model Configuration',
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

  Widget _buildSamplerTile(BuildContext context) {
    return InkWell(
      onTap: () => showSamplerSelectModal(
        context: context,
        currentSampler: globalCurrentSamplingMethod,
        onSelect: (sampler) {
          setState(() {
            globalCurrentSamplingMethod = sampler;
          });
        },
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.waves, color: AppTheme.accentSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SAMPLING METHOD",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    globalCurrentSamplingMethod,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white24,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliders() {
    void save() {
      if (globalCheckpointDataMap[globalCurrentCheckpointName] != null) {
        final data = globalCheckpointDataMap[globalCurrentCheckpointName]!;
        data.samplingSteps = globalCurrentSamplingSteps;
        data.cfgScale = globalCurrentCfgScale;
        data.denoisingStrength = globalDenoiseStrength;
        data.resolutionWidth = globalCurrentResolutionWidth;
        data.resolutionHeight = globalCurrentResolutionHeight;
        StorageService.saveCheckpointDataMap();
      }
    }

    return Column(
      children: [
        GlassSlider(
          label: 'Denoising Strength',
          value: globalDenoiseStrength,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          accentColor: AppTheme.accentSecondary,
          onChanged: (val) {
            setState(() {
              globalDenoiseStrength = val;
            });
          },
          onChangeEnd: (_) => save(),
          valueFormatter: (val) => val.toStringAsFixed(2),
        ),
        const SizedBox(height: 24),
        GlassSlider(
          label: 'Sampling Steps',
          value: globalCurrentSamplingSteps.toDouble(),
          min: 8,
          max: 60,
          accentColor: AppTheme.accentSecondary,
          onChanged: (val) {
            setState(() {
              globalCurrentSamplingSteps = val.toInt();
            });
          },
          onChangeEnd: (_) => save(),
          valueFormatter: (val) => val.toInt().toString(),
        ),
        const SizedBox(height: 24),
        GlassSlider(
          label: 'CFG Scale',
          value: globalCurrentCfgScale,
          min: 1.0,
          max: 15.0,
          divisions: 28,
          accentColor: AppTheme.accentSecondary,
          onChanged: (val) {
            setState(() {
              globalCurrentCfgScale = val;
            });
          },
          onChangeEnd: (_) => save(),
          valueFormatter: (val) => val.toStringAsFixed(1),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GlassSlider(
                label: 'Width',
                value: globalCurrentResolutionWidth.toDouble(),
                min: 256,
                max: 2048,
                divisions: 56,
                accentColor: AppTheme.accentTertiary,
                onChanged: (val) {
                  setState(() {
                    globalCurrentResolutionWidth = ((val / 32).round() * 32.0)
                        .toInt();
                  });
                },
                onChangeEnd: (_) => save(),
                valueFormatter: (val) => '${val.toInt()}',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassSlider(
                label: 'Height',
                value: globalCurrentResolutionHeight.toDouble(),
                min: 256,
                max: 2048,
                divisions: 56,
                accentColor: AppTheme.accentTertiary,
                onChanged: (val) {
                  setState(() {
                    globalCurrentResolutionHeight = ((val / 32).round() * 32.0)
                        .toInt();
                  });
                },
                onChangeEnd: (_) => save(),
                valueFormatter: (val) => '${val.toInt()}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    final currentData = globalCheckpointDataMap[globalCurrentCheckpointName];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GlassContainer(
        backgroundColor: AppTheme.surfaceCard,
        borderColor: AppTheme.glassBorder,
        borderRadius: AppTheme.radiusLarge,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 24),

            // Main Card
            CheckpointDisplayCard(
              modelName: globalCurrentCheckpointName,
              imageUrl: currentData?.imageURL,
              baseModel: currentData?.baseModel,
              isLoading: _isChangingCheckpoint,
              onTap: () => showCheckpointSelectModal(
                context: context,
                onSelect: (modelName) async {
                  Navigator.pop(context);
                  setState(() => _isChangingCheckpoint = true);

                  globalCurrentCheckpointName = modelName;
                  _applyModelDefaults(modelName);

                  await setCheckpoint();
                  if (mounted) setState(() => _isChangingCheckpoint = false);
                },
              ),
            ),

            const SizedBox(height: 24),

            // Sampler Tile
            _buildSamplerTile(context),

            const SizedBox(height: 32),

            // Configuration Sliders
            _buildSliders(),
          ],
        ),
      ),
    );
  }
}

// ==================== Checkpoint Display Card ==================== //

class CheckpointDisplayCard extends StatelessWidget {
  final String modelName;
  final String? imageUrl;
  final String? baseModel;
  final bool isLoading;
  final VoidCallback onTap;

  const CheckpointDisplayCard({
    super.key,
    required this.modelName,
    this.imageUrl,
    this.baseModel,
    this.isLoading = false,
    required this.onTap,
  });

  // ===== Class Widgets ===== //

  Widget _placeholder() => Container(
    color: AppTheme.surfaceCard,
    child: Icon(
      Icons.image_not_supported,
      color: Colors.white.withValues(alpha: 0.1),
      size: 40,
    ),
  );

  // ===== Build Methods ===== //

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 220,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLoading
                ? AppTheme.accentPrimary
                : AppTheme.glassBorderLight,
            width: isLoading ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isLoading
                  ? AppTheme.accentPrimary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background
              if (modelName.isNotEmpty)
                (imageUrl?.startsWith('http') ?? false)
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder()
              else
                _placeholder(),

              // Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                    stops: const [0.5, 0.7, 1.0],
                  ),
                ),
              ),

              // Content
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (baseModel?.isNotEmpty == true)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentPrimary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          baseModel!.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    Text(
                      modelName.isEmpty ? 'Select Model' : modelName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Loading State
              if (isLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: AppTheme.accentPrimary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          "LOADING",
                          style: TextStyle(
                            color: AppTheme.accentPrimary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
