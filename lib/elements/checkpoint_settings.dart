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

class CheckpointSettingsState extends State<CheckpointSettings> {
  // ===== Class Variables ===== //

  List<String> _checkpointOptions = globalCheckpointDataMap.keys.toList();
  List<String> _checkpointImages = globalCheckpointDataMap.values
      .map((e) => e.imageURL)
      .toList();

  bool isLoading = false;
  bool _isChangingCheckpoint = false;

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

  // ===== Build Method ===== //

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Container(
        // Theme
        decoration: BoxDecoration(
          color: Colors.grey.shade800.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),

        // Padding
        padding: const EdgeInsets.all(16.0),

        // Content
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title with Icon
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Checkpoint Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            // Spacer
            const SizedBox(height: 16),

            // Checkpoint Selection - Title
            const Text(
              'Model Checkpoint',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),

            // Spacer
            const SizedBox(height: 8),

            // Checkpoint Selection - Advanced Selector
            InkWell(
              // Bottom Sheet
              onTap: () {
                double turns = 0.0; // Rotation state for the refresh icon
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) {
                    // StatefulBuilder provides a local setState for the modal's content
                    return StatefulBuilder(
                      builder: (BuildContext context, StateSetter modalSetState) {
                        return Container(
                          // Theme
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),

                          // Content
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Menu Header
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    Text(
                                      'Select a Model',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),

                                    // FIX: Refresh button with continuous animation
                                    IconButton(
                                      icon: AnimatedRotation(
                                        turns: turns,
                                        duration: const Duration(
                                          milliseconds: 800,
                                        ),
                                        onEnd: () {
                                          // If still loading, continue the animation loop
                                          if (isLoading) {
                                            modalSetState(() {
                                              turns += 1.0;
                                            });
                                          }
                                        },
                                        child: const Icon(
                                          Icons.refresh_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                      onPressed: () async {
                                        if (isLoading)
                                          return; // Prevent multiple presses

                                        // Start loading and trigger animation
                                        modalSetState(() {
                                          isLoading = true;
                                          turns += 1.0;
                                        });

                                        await syncCheckpointDataFromServer(
                                          force: true,
                                        );

                                        // Resync lists with new data
                                        _checkpointOptions =
                                            globalCheckpointDataMap.keys
                                                .toList();
                                        _checkpointImages =
                                            globalCheckpointDataMap.values
                                                .map((e) => e.imageURL)
                                                .toList();

                                        // FIX: Stop animation and refresh modal content
                                        modalSetState(() {
                                          isLoading = false;
                                        });
                                        // Refresh the parent widget state as well
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              // Scrollable Grid of Options
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                  ),
                                  child: GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                          childAspectRatio: 0.8,
                                        ),
                                    itemCount: _checkpointOptions.length,
                                    itemBuilder: (context, index) {
                                      final option = _checkpointOptions[index];
                                      final imageUrl = _checkpointImages[index];
                                      final isSelected =
                                          option == globalCurrentCheckpointName;

                                      return GestureDetector(
                                        onTap: () async {
                                          // Start flashing animation
                                          setState(() {
                                            globalCurrentCheckpointName =
                                                option;
                                            final data =
                                                globalCheckpointDataMap[globalCurrentCheckpointName];
                                            if (data != null) {
                                              globalCurrentSamplingSteps =
                                                  data.samplingSteps;
                                              globalCurrentSamplingMethod =
                                                  data.samplingMethod;
                                              globalCurrentCfgScale =
                                                  data.cfgScale;
                                            }
                                            _isChangingCheckpoint = true;
                                            saveCheckpointDataMap();
                                          });
                                          Navigator.pop(context);

                                          // Wait for checkpoint change to complete
                                          await setCheckpoint();

                                          // Stop flashing animation
                                          setState(() {
                                            _isChangingCheckpoint = false;
                                          });
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.cyan.shade300
                                                  : Colors.white.withValues(
                                                      alpha: 0.3,
                                                    ),
                                              width: isSelected ? 2 : 1,
                                            ),
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              // Image Section
                                              Expanded(
                                                flex: 3,
                                                child: Container(
                                                  width: double.infinity,
                                                  decoration: const BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                12,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                12,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                    child: CachedNetworkImage(
                                                      imageUrl: imageUrl,
                                                      fit: BoxFit.cover,
                                                      placeholder:
                                                          (
                                                            context,
                                                            url,
                                                          ) => Container(
                                                            color: Colors
                                                                .grey
                                                                .shade700,
                                                            child: const Center(
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    color: Colors
                                                                        .cyan,
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                            ),
                                                          ),
                                                      errorWidget:
                                                          (
                                                            context,
                                                            url,
                                                            error,
                                                          ) => Container(
                                                            color: Colors
                                                                .grey
                                                                .shade700,
                                                            child: Icon(
                                                              Icons
                                                                  .error_outline,
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                    alpha: 0.6,
                                                                  ),
                                                              size: 24,
                                                            ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // Text Section
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? Colors.cyan.shade300
                                                              .withValues(
                                                                alpha: 0.2,
                                                              )
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          bottomLeft:
                                                              Radius.circular(
                                                                12,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        option,
                                                        style: TextStyle(
                                                          color: isSelected
                                                              ? Colors
                                                                    .cyan
                                                                    .shade300
                                                              : Colors.white,
                                                          fontWeight: isSelected
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                          fontSize: 12,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              // Bottom padding
                              const SizedBox(height: 16),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },

              // Selector
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: 200,
                decoration: BoxDecoration(
                  color: _isChangingCheckpoint
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: _isChangingCheckpoint
                      ? Border.all(color: Colors.cyan.shade300, width: 2)
                      : null,
                ),
                child: Column(
                  children: [
                    // Image Section
                    Expanded(
                      flex: 5,
                      child: Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                              child: globalCurrentCheckpointName.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl:
                                          _checkpointImages[_checkpointOptions
                                              .indexOf(
                                                globalCurrentCheckpointName,
                                              )],
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey.shade700,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.cyan,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            color: Colors.grey.shade700,
                                            child: Icon(
                                              Icons.image_not_supported,
                                              color: Colors.white.withValues(
                                                alpha: 0.6,
                                              ),
                                              size: 24,
                                            ),
                                          ),
                                    )
                                  : Container(
                                      color: Colors.grey.shade700,
                                      child: Icon(
                                        Icons.add_photo_alternate,
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        size: 24,
                                      ),
                                    ),
                            ),
                          ),
                          // Loading overlay
                          if (_isChangingCheckpoint)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.cyan,
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Text Section
                    Expanded(
                      flex: 1,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Center(
                          child: Text(
                            globalCurrentCheckpointName.isEmpty
                                ? 'Select a model...'
                                : globalCurrentCheckpointName,
                            style: TextStyle(
                              color: globalCurrentCheckpointName.isEmpty
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: globalCurrentCheckpointName.isEmpty
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Spacer
            const SizedBox(height: 16),

            // Sampling Method - Title
            const Text(
              'Sampling Method',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),

            // Spacer
            const SizedBox(height: 16),

            // Sampling Method - Dropdown
            InkWell(
              // Bottom Sheet
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) {
                    return Container(
                      // Theme
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),

                      // Content
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Menu Header
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'Select a Method',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          // Scrollable List of Options
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: samplerNames.length,
                              itemBuilder: (context, index) {
                                final option = samplerNames[index];
                                final isSelected =
                                    option == globalCurrentSamplingMethod;
                                return ListTile(
                                  title: Text(
                                    option,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.cyan.shade300
                                          : Colors.white,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: Colors.cyan.shade300,
                                        )
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      globalCurrentSamplingMethod = option;
                                      globalCheckpointDataMap[globalCurrentCheckpointName]!
                                              .samplingMethod =
                                          option;
                                      saveCheckpointDataMap();
                                    });
                                    Navigator.pop(
                                      context,
                                    ); // Close the bottom sheet
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },

              // Selector
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      globalCurrentSamplingMethod,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),

            // Spacer
            const SizedBox(height: 20),

            // Sampling Steps
            ModernSlider(
              label: 'Sampling Steps',
              value: globalCurrentSamplingSteps,
              min: 8,
              max: 50,
              onChanged: (value) {
                setState(() {
                  globalCurrentSamplingSteps = value;
                  globalCheckpointDataMap[globalCurrentCheckpointName]!
                          .samplingSteps =
                      value;
                  saveCheckpointDataMap();
                });
              },
            ),

            // Spacer
            const SizedBox(height: 20),

            // CFG Scale
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
          ],
        ),
      ),
    );
  }
}
