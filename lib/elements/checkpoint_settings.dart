// ==================== Checkpoint Settings ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Local imports - Elements
import 'package:sd_companion/elements/modern_slider.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/api_calls.dart';

// ========== Checkpoint Settings Class ========== //

class CheckpointSettings extends StatefulWidget {
  const CheckpointSettings({Key? key}) : super(key: key);

  @override
  State<CheckpointSettings> createState() => CheckpointSettingsState();
}

class CheckpointSettingsState extends State<CheckpointSettings>
    with SingleTickerProviderStateMixin {
  // ===== Class Variables ===== //

  // We keep these for the refresh logic
  List<String> _checkpointOptions = globalCheckpointDataMap.keys.toList();
  List<String> _checkpointImages = globalCheckpointDataMap.values
      .map((e) => e.imageURL)
      .toList();

  bool _isChangingCheckpoint = false; // Used for the main preview loading state

  // Refresh Animation Controller
  late AnimationController _refreshController;

  final samplerNames = [
    "DPM++ 2M",
    "DPM++ SDE",
    "DPM++ 2M SDE",
    "DPM++ 3M SDE",
    "Euler a",
    "Euler",
    "LMS",
    "Heun",
    "DPM2",
    "Restart",
    "DDPM",
    "DDIM",
    "PLMS",
    "UniPC",
    "LCM",
    "DPM++ 2M CFG++",
    "DPM++ SDE CFG++",
    "DPM++ 2M SDE CFG++",
    "DPM++ 3M SDE CFG++",
    "Euler a CFG++",
    "Euler CFG++",
  ];

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  // ===== Edit Modal Logic (Long Press) ===== //

  void _showEditModelDetails(BuildContext context, String modelName) {
    // Get existing data
    final data = globalCheckpointDataMap[modelName];
    if (data == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CheckpointEditorSheet(
        modelName: modelName,
        data: data,
        samplerNames: samplerNames,
        onSave: () {
          saveCheckpointDataMap();
          // Force UI update
          setState(() {
            _checkpointOptions = globalCheckpointDataMap.keys.toList();
            _checkpointImages = globalCheckpointDataMap.values
                .map((e) => e.imageURL)
                .toList();
          });
          Navigator.pop(context); // Close editor
          // Optionally close the selector modal too if you want,
          // or keep it open to see changes. keeping it open:
          // Navigator.pop(context);
        },
      ),
    );
  }

  // ===== Model Selector Modal Logic ===== //

  void _showModelSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            // Group the data by baseModel
            final Map<String, List<String>> groupedModels = {};
            final sortedKeys = globalCheckpointDataMap.keys.toList()..sort();

            for (var key in sortedKeys) {
              final data = globalCheckpointDataMap[key];
              final base =
                  (data?.baseModel != null && data!.baseModel.isNotEmpty)
                  ? data.baseModel
                  : 'Other';

              if (!groupedModels.containsKey(base)) {
                groupedModels[base] = [];
              }
              groupedModels[base]!.add(key);
            }
            final sortedGroupKeys = groupedModels.keys.toList()..sort();

            return FractionallySizedBox(
              heightFactor: 0.85,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24.0),
                    topRight: Radius.circular(24.0),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // --- Header ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.grid_view_rounded,
                            color: Colors.cyan.shade300,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Select Model',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          RotationTransition(
                            turns: _refreshController,
                            child: IconButton(
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white70,
                              ),
                              onPressed: () async {
                                if (_refreshController.isAnimating) return;
                                _refreshController.repeat();
                                await syncCheckpointDataFromServer(force: true);
                                if (mounted) {
                                  setState(() {
                                    _checkpointOptions = globalCheckpointDataMap
                                        .keys
                                        .toList();
                                    _checkpointImages = globalCheckpointDataMap
                                        .values
                                        .map((e) => e.imageURL)
                                        .toList();
                                  });
                                }
                                modalSetState(() {});
                                _refreshController.stop();
                                _refreshController.reset();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // --- List of Groups ---
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: sortedGroupKeys.length,
                        itemBuilder: (context, groupIndex) {
                          final baseModelName = sortedGroupKeys[groupIndex];
                          final modelsInGroup = groupedModels[baseModelName]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section Divider
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16.0,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.cyan.shade900.withValues(
                                          alpha: 0.3,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.cyan.shade800,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Text(
                                        baseModelName,
                                        style: TextStyle(
                                          color: Colors.cyan.shade100,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Divider(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        thickness: 1,
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
                                      childAspectRatio: 0.8,
                                    ),
                                itemCount: modelsInGroup.length,
                                itemBuilder: (context, index) {
                                  final option = modelsInGroup[index];
                                  final data = globalCheckpointDataMap[option];
                                  final imageUrl = data?.imageURL ?? '';
                                  final isSelected =
                                      option == globalCurrentCheckpointName;

                                  return _AnimatedModelCard(
                                    name: option,
                                    imageUrl: imageUrl,
                                    isSelected: isSelected,
                                    onTap: () async {
                                      Navigator.pop(context);
                                      setState(() {
                                        _isChangingCheckpoint = true;
                                        globalCurrentCheckpointName = option;
                                        if (data != null) {
                                          globalCurrentSamplingSteps =
                                              data.samplingSteps;
                                          globalCurrentSamplingMethod =
                                              data.samplingMethod;
                                          globalCurrentCfgScale = data.cfgScale;
                                          globalCurrentResolutionWidth =
                                              data.resolutionWidth;
                                          globalCurrentResolutionHeight =
                                              data.resolutionHeight;
                                        }
                                        saveCheckpointDataMap();
                                      });
                                      await setCheckpoint();
                                      setState(() {
                                        _isChangingCheckpoint = false;
                                      });
                                    },
                                    onLongPress: () {
                                      // Trigger Edit Modal inside the sheet
                                      _showEditModelDetails(context, option);
                                      // We need to refresh the list after closing edit
                                      // but we can rely on modalSetState wrapping the
                                      // builder if we pass a callback.
                                      // For now, the user can pull-to-refresh or close/reopen.
                                    },
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSamplerSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24.0),
                topRight: Radius.circular(24.0),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.waves,
                            color: Colors.cyan.shade300,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Sampling Method',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: samplerNames.length,
                    itemBuilder: (context, index) {
                      final option = samplerNames[index];
                      final isSelected = option == globalCurrentSamplingMethod;
                      return _AnimatedSamplerTile(
                        text: option,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            globalCurrentSamplingMethod = option;
                            globalCheckpointDataMap[globalCurrentCheckpointName]!
                                    .samplingMethod =
                                option;
                            saveCheckpointDataMap();
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    final currentData = globalCheckpointDataMap[globalCurrentCheckpointName];
    final currentBaseModel = currentData?.baseModel ?? "";
    final currentImageUrl = currentData?.imageURL ?? "";

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.cyan.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: Colors.cyan.shade300,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Checkpoint Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Model Checkpoint',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            InkWell(
              onTap: () => _showModelSelector(context),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isChangingCheckpoint
                        ? Colors.cyan.shade300
                        : Colors.white.withValues(alpha: 0.1),
                    width: _isChangingCheckpoint ? 2 : 1,
                  ),
                  boxShadow: _isChangingCheckpoint
                      ? [
                          BoxShadow(
                            color: Colors.cyan.shade900.withValues(alpha: 0.4),
                            blurRadius: 15,
                          ),
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (globalCurrentCheckpointName.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: currentImageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade800,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.cyan,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade800,
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.white24,
                              size: 48,
                            ),
                          ),
                        )
                      else
                        Container(
                          color: Colors.grey.shade800,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Colors.white24,
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Select a Model",
                                style: TextStyle(color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.9),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                globalCurrentCheckpointName.isEmpty
                                    ? 'Tap to select...'
                                    : globalCurrentCheckpointName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (globalCurrentCheckpointName.isNotEmpty)
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.greenAccent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.green,
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Active Checkpoint',
                                      style: TextStyle(
                                        color: Colors.cyan.shade100,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (currentBaseModel.isNotEmpty)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hub_rounded,
                                  color: Colors.cyan.shade300,
                                  size: 12,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  currentBaseModel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_isChangingCheckpoint)
                        Container(
                          color: Colors.black54,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  color: Colors.cyan,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Loading Model...",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
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
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Sampling Method',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            InkWell(
              onTap: () => _showSamplerSelector(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      globalCurrentSamplingMethod,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(Icons.unfold_more, color: Colors.white38),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ModernSlider(
              label: 'Sampling Steps',
              value: globalCurrentSamplingSteps.toDouble(),
              min: 8,
              max: 50,
              onChanged: (value) {
                setState(() {
                  globalCurrentSamplingSteps = value.toInt();
                  globalCheckpointDataMap[globalCurrentCheckpointName]!
                      .samplingSteps = value
                      .toInt();
                  saveCheckpointDataMap();
                });
              },
              valueFormatter: (val) => val.toInt().toString(),
            ),
            const SizedBox(height: 20),
            ModernSlider(
              label: 'CFG Scale',
              value: globalCurrentCfgScale,
              min: 1.0,
              max: 10.0,
              divisions: 18,
              onChanged: (value) {
                setState(() {
                  globalCurrentCfgScale = value;
                  globalCheckpointDataMap[globalCurrentCheckpointName]!
                          .cfgScale =
                      value;
                  saveCheckpointDataMap();
                });
              },
              valueFormatter: (val) => val.toStringAsFixed(1),
            ),
            const SizedBox(height: 20),
            ModernSlider(
              label: 'Width',
              value: globalCurrentResolutionWidth.toDouble(),
              min: 256,
              max: 2048,
              divisions: 56,
              onChanged: (value) {
                setState(() {
                  globalCurrentResolutionWidth = ((value / 32).round() * 32.0)
                      .toInt();
                  globalCheckpointDataMap[globalCurrentCheckpointName]!
                          .resolutionWidth =
                      globalCurrentResolutionWidth;
                  saveCheckpointDataMap();
                });
              },
              valueFormatter: (val) => '${val.toInt()}px',
            ),
            const SizedBox(height: 20),
            ModernSlider(
              label: 'Height',
              value: globalCurrentResolutionHeight.toDouble(),
              min: 256,
              max: 2048,
              divisions: 56,
              onChanged: (value) {
                setState(() {
                  globalCurrentResolutionHeight = ((value / 32).round() * 32.0)
                      .toInt();
                  globalCheckpointDataMap[globalCurrentCheckpointName]!
                          .resolutionHeight =
                      globalCurrentResolutionHeight;
                  saveCheckpointDataMap();
                });
              },
              valueFormatter: (val) => '${val.toInt()}px',
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// EDITOR SHEET (NEW)
// ==========================================

class _CheckpointEditorSheet extends StatefulWidget {
  final String modelName;
  final dynamic data; // CheckpointData
  final List<String> samplerNames;
  final VoidCallback onSave;

  const _CheckpointEditorSheet({
    Key? key,
    required this.modelName,
    required this.data,
    required this.samplerNames,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_CheckpointEditorSheet> createState() => _CheckpointEditorSheetState();
}

class _CheckpointEditorSheetState extends State<_CheckpointEditorSheet> {
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
    'Pony',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.data.imageURL);
    _baseModel =
        (widget.data.baseModel != null && widget.data.baseModel.isNotEmpty)
        ? widget.data.baseModel
        : 'Other';
    // Ensure base model is in options, otherwise add it or set to Other
    if (!_baseModelOptions.contains(_baseModel)) {
      _baseModelOptions.add(_baseModel);
    }

    _sampler = widget.data.samplingMethod;
    _steps = widget.data.samplingSteps.toDouble();
    _cfg = widget.data.cfgScale;
    _width = widget.data.resolutionWidth.toDouble();
    _height = widget.data.resolutionHeight.toDouble();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _save() {
    // Update the object
    widget.data.imageURL = _urlController.text;
    widget.data.baseModel = _baseModel;
    widget.data.samplingMethod = _sampler;
    widget.data.samplingSteps = _steps.toInt();
    widget.data.cfgScale = _cfg;
    widget.data.resolutionWidth = _width.toInt();
    widget.data.resolutionHeight = _height.toInt();

    // Callback to parent to save to disk and refresh
    widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: Colors.cyan.shade300,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.modelName,
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white10, height: 1),

            // --- Form ---
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Base Model Dropdown
                  Text(
                    "Base Model Type",
                    style: TextStyle(
                      color: Colors.cyan.shade100,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _baseModel,
                        dropdownColor: Colors.grey.shade800,
                        isExpanded: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        items: _baseModelOptions.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) =>
                            setState(() => _baseModel = newValue!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Image URL Field
                  Text(
                    "Preview Image URL",
                    style: TextStyle(
                      color: Colors.cyan.shade100,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      hintText: "http://...",
                      hintStyle: TextStyle(color: Colors.white24),
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.cyan.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sampler Dropdown
                  Text(
                    "Default Sampler",
                    style: TextStyle(
                      color: Colors.cyan.shade100,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: widget.samplerNames.contains(_sampler)
                            ? _sampler
                            : null,
                        hint: Text(
                          _sampler,
                          style: TextStyle(color: Colors.white),
                        ),
                        dropdownColor: Colors.grey.shade800,
                        isExpanded: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        items: widget.samplerNames.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) =>
                            setState(() => _sampler = newValue!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sliders
                  ModernSlider(
                    label: "Default Steps",
                    value: _steps,
                    min: 1,
                    max: 60,
                    onChanged: (v) => setState(() => _steps = v),
                    valueFormatter: (v) => v.toInt().toString(),
                  ),
                  const SizedBox(height: 16),
                  ModernSlider(
                    label: "Default CFG",
                    value: _cfg,
                    min: 1,
                    max: 15,
                    divisions: 28,
                    onChanged: (v) => setState(() => _cfg = v),
                    valueFormatter: (v) => v.toStringAsFixed(1),
                  ),
                  const SizedBox(height: 16),
                  ModernSlider(
                    label: "Default Width",
                    value: _width,
                    min: 256,
                    max: 2048,
                    divisions: 56,
                    onChanged: (v) => setState(
                      () => _width = ((v / 32).round() * 32.0).toDouble(),
                    ),
                    valueFormatter: (v) => '${v.toInt()}px',
                  ),
                  const SizedBox(height: 16),
                  ModernSlider(
                    label: "Default Height",
                    value: _height,
                    min: 256,
                    max: 2048,
                    divisions: 56,
                    onChanged: (v) => setState(
                      () => _height = ((v / 32).round() * 32.0).toDouble(),
                    ),
                    valueFormatter: (v) => '${v.toInt()}px',
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),

            // --- Save Button ---
            Padding(
              padding: const EdgeInsets.all(20),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: Colors.cyan.withValues(alpha: 0.4),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// ANIMATED WIDGETS
// ==========================================

class _AnimatedModelCard extends StatefulWidget {
  final String name;
  final String imageUrl;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // Added

  const _AnimatedModelCard({
    Key? key,
    required this.name,
    required this.imageUrl,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  State<_AnimatedModelCard> createState() => _AnimatedModelCardState();
}

class _AnimatedModelCardState extends State<_AnimatedModelCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress, // Added
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? Colors.cyan.shade300
                  : Colors.white.withValues(alpha: 0.1),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: Colors.cyan.shade500.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: Colors.grey.shade800),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.shade800,
                    child: Icon(Icons.broken_image, color: Colors.white24),
                  ),
                ),
                // Gradient & Text
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (widget.isSelected)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.cyan.shade300,
                            size: 16,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          widget.name,
                          style: TextStyle(
                            color: widget.isSelected
                                ? Colors.cyan.shade100
                                : Colors.white,
                            fontSize: 12,
                            fontWeight: widget.isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSamplerTile extends StatefulWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedSamplerTile({
    Key? key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_AnimatedSamplerTile> createState() => _AnimatedSamplerTileState();
}

class _AnimatedSamplerTileState extends State<_AnimatedSamplerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? Colors.cyan.shade900.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? Colors.cyan.shade400.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: widget.isSelected ? Colors.white : Colors.white70,
                    fontWeight: widget.isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 15,
                  ),
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.check_circle, color: Colors.cyan.shade300, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
