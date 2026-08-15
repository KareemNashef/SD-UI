// ==================== Checkpoint Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modals/checkpoint_select_modal.dart';
import 'package:sd_companion/elements/modals/sampler_select_modal.dart';
import 'package:sd_companion/elements/modals/scheduler_select_modal.dart';
import 'package:sd_companion/elements/widgets/glass_container.dart';
import 'package:sd_companion/elements/widgets/glass_slider.dart';
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';
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
  bool _isLoadingModules = true;
  bool _showModules = false;
  String? _moduleLoadError;
  List<String> _availableForgeModules = const [];

  // ===== Lifecycle Methods ===== //

  @override
  void initState() {
    super.initState();
    syncActiveCheckpointSettings();
    _loadForgeModules();
  }

  // ===== Class Methods ===== //

  void _applyModelDefaults(String modelName) {
    final data = globalCheckpointDataMap[modelName];
    if (data != null) {
      setState(() {
        globalCurrentSamplingSteps = data.samplingSteps;
        globalCurrentSamplingMethod = data.samplingMethod;
        globalCurrentScheduler = data.scheduler;
        globalCurrentCfgScale = data.cfgScale;
        globalDenoiseStrength = data.denoisingStrength;
        globalCurrentResolutionWidth = data.resolutionWidth;
        globalCurrentResolutionHeight = data.resolutionHeight;
        StorageService.saveCheckpointDataMap();
      });
    }
  }

  void _saveCurrentSettingsToModel() {
    if (globalCheckpointDataMap[globalCurrentCheckpointName] != null) {
      final data = globalCheckpointDataMap[globalCurrentCheckpointName]!;
      data.samplingSteps = globalCurrentSamplingSteps;
      data.samplingMethod = globalCurrentSamplingMethod;
      data.scheduler = globalCurrentScheduler;
      data.cfgScale = globalCurrentCfgScale;
      data.denoisingStrength = globalDenoiseStrength;
      data.resolutionWidth = globalCurrentResolutionWidth;
      data.resolutionHeight = globalCurrentResolutionHeight;
      StorageService.saveCheckpointDataMap();
    }
  }

  Future<void> _loadForgeModules() async {
    if (mounted) {
      setState(() {
        _isLoadingModules = true;
        _moduleLoadError = null;
      });
    }

    try {
      final modules = await fetchForgeModules();
      if (!mounted) return;
      setState(() {
        _availableForgeModules = modules.where((module) {
          final normalized = module.trim().toLowerCase();
          return normalized.isNotEmpty &&
              normalized != 'automatic' &&
              normalized != 'use automatic';
        }).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _moduleLoadError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingModules = false);
    }
  }

  Future<void> _toggleForgeModule(
    CheckpointData checkpoint,
    String module,
    bool selected,
  ) async {
    final modules = Set<String>.from(checkpoint.forgeAdditionalModules);
    selected ? modules.add(module) : modules.remove(module);

    setState(() {
      checkpoint.forgeAdditionalModules = modules.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    });
    await StorageService.saveCheckpointDataMap();

    try {
      await applyCheckpointConfiguration();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selection saved. Forge could not apply it yet: $error',
          ),
        ),
      );
    }
  }

  Future<void> _setImg2ImgMode(
    CheckpointData checkpoint,
    Img2ImgMode mode,
  ) async {
    setState(() => checkpoint.img2imgMode = mode);
    await StorageService.saveCheckpointDataMap();
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
          child: Icon(
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
            _saveCurrentSettingsToModel();
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
            Icon(Icons.waves, color: AppTheme.accentSecondary, size: 20),
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

  Widget _buildSchedulerTile(BuildContext context) {
    return InkWell(
      onTap: () => showSchedulerSelectModal(
        context: context,
        currentScheduler: globalCurrentScheduler,
        onSelect: (scheduler) {
          setState(() {
            globalCurrentScheduler = scheduler;
            _saveCurrentSettingsToModel();
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
            Icon(
              Icons.schedule,
              color: AppTheme.accentTertiary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SCHEDULE METHOD",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    globalCurrentScheduler,
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
          onChangeEnd: (_) => _saveCurrentSettingsToModel(),
          valueFormatter: (val) => val.toStringAsFixed(2),
        ),
        const SizedBox(height: 24),
        GlassSlider(
          label: 'Sampling Steps',
          value: globalCurrentSamplingSteps.toDouble(),
          min: 4,
          max: 60,
          accentColor: AppTheme.accentSecondary,
          onChanged: (val) {
            setState(() {
              globalCurrentSamplingSteps = val.toInt();
            });
          },
          onChangeEnd: (_) => _saveCurrentSettingsToModel(),
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
          onChangeEnd: (_) => _saveCurrentSettingsToModel(),
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
                onChangeEnd: (_) => _saveCurrentSettingsToModel(),
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
                onChangeEnd: (_) => _saveCurrentSettingsToModel(),
                valueFormatter: (val) => '${val.toInt()}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModelInputConfiguration(CheckpointData checkpoint) {
    final selectedModules = checkpoint.forgeAdditionalModules;
    final modules = <String>{
      ..._availableForgeModules,
      ...selectedModules,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showModules = !_showModules),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: AppTheme.accentSecondary,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VAE & TEXT ENCODERS',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          selectedModules.isEmpty
                              ? 'No files selected'
                              : '${selectedModules.length} file${selectedModules.length == 1 ? '' : 's'} selected',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh VAE and encoders',
                    onPressed: _isLoadingModules ? null : _loadForgeModules,
                    icon: _isLoadingModules
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                  ),
                  AnimatedRotation(
                    turns: _showModules ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: !_showModules
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    child: _moduleLoadError != null && modules.isEmpty
                        ? Row(
                            children: [
                              const Icon(
                                Icons.cloud_off_rounded,
                                color: Colors.white38,
                                size: 18,
                              ),
                              const SizedBox(width: 9),
                              const Expanded(
                                child: Text(
                                  'Could not load files from Forge.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadForgeModules,
                                child: const Text('Retry'),
                              ),
                            ],
                          )
                        : modules.isEmpty
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Forge did not report any VAE or encoder files.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: modules.map((module) {
                              return FilterChip(
                                label: Text(module),
                                selected: selectedModules.contains(module),
                                onSelected: (selected) => _toggleForgeModule(
                                  checkpoint,
                                  module,
                                  selected,
                                ),
                              );
                            }).toList(),
                          ),
                  ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: _buildImg2ImgModeButton(
                    label: 'Inpaint',
                    icon: Icons.gesture_rounded,
                    selected: checkpoint.img2imgMode == Img2ImgMode.inpaint,
                    onTap: () =>
                        _setImg2ImgMode(checkpoint, Img2ImgMode.inpaint),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildImg2ImgModeButton(
                    label: 'Full image',
                    icon: Icons.photo_size_select_large_rounded,
                    selected: checkpoint.img2imgMode == Img2ImgMode.fullImage,
                    onTap: () =>
                        _setImg2ImgMode(checkpoint, Img2ImgMode.fullImage),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImg2ImgModeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppTheme.accentPrimary.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.accentPrimary.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppTheme.accentPrimary : Colors.white54,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
                  final oldModelName = globalCurrentCheckpointName;
                  final oldData = globalCheckpointDataMap[oldModelName];
                  final newData = globalCheckpointDataMap[modelName];

                  Navigator.pop(context);
                  setState(() => _isChangingCheckpoint = true);

                  // Clear loras if base model changed
                  if (oldData?.baseModel != newData?.baseModel) {
                    globalSelectedLoras.value = {};
                    globalSelectedLoraTags.value = {};
                  }

                  globalCurrentCheckpointName = modelName;
                  _applyModelDefaults(modelName);

                  await setCheckpoint();
                  if (mounted) setState(() => _isChangingCheckpoint = false);
                },
              ),
            ),

            const SizedBox(height: 24),

            if (currentData != null) ...[
              _buildModelInputConfiguration(currentData),
              const SizedBox(height: 24),
            ],

            // Sampler Tile
            _buildSamplerTile(context),

            const SizedBox(height: 16),

            // Scheduler Tile
            _buildSchedulerTile(context),

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
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: AppTheme.accentPrimary,
                        ),
                        const SizedBox(height: 12),
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
