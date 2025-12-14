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

  // ===== Modal Logic ===== //

  void _showModelSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
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
                          // Refresh Button
                          RotationTransition(
                            turns: _refreshController,
                            child: IconButton(
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white70,
                              ),
                              onPressed: () async {
                                if (_refreshController.isAnimating) return;

                                _refreshController.repeat(); // Start spinning

                                await syncCheckpointDataFromServer(force: true);

                                // Update lists
                                modalSetState(() {
                                  _checkpointOptions = globalCheckpointDataMap
                                      .keys
                                      .toList();
                                  _checkpointImages = globalCheckpointDataMap
                                      .values
                                      .map((e) => e.imageURL)
                                      .toList();
                                });

                                // Update parent as well
                                setState(() {});

                                _refreshController.stop(); // Stop spinning
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

                    // --- Grid ---
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
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

                          return _AnimatedModelCard(
                            name: option,
                            imageUrl: imageUrl,
                            isSelected: isSelected,
                            onTap: () async {
                              Navigator.pop(context);

                              // Trigger main loading state
                              setState(() {
                                _isChangingCheckpoint = true;
                                globalCurrentCheckpointName = option;

                                // Update settings based on new checkpoint
                                final data =
                                    globalCheckpointDataMap[globalCurrentCheckpointName];
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

                              // Wait for backend
                              await setCheckpoint();

                              setState(() {
                                _isChangingCheckpoint = false;
                              });
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
                // --- Header ---
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

                // --- List ---
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        // Theme
        decoration: BoxDecoration(
          color: Colors.grey.shade900.withValues(
            alpha: 0.6,
          ), // Slightly darker base
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),

        // Padding
        padding: const EdgeInsets.all(20.0),

        // Content
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Title ---
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

            // --- Checkpoint Preview Box ---
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
                      // Image
                      if (globalCurrentCheckpointName.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl:
                              _checkpointImages[_checkpointOptions.indexOf(
                                globalCurrentCheckpointName,
                              )],
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

                      // Gradient Overlay for Text
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
                                Text(
                                  'Active Checkpoint',
                                  style: TextStyle(
                                    color: Colors.cyan.shade300,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Loading Overlay
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

            // --- Sampling Method ---
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

            // --- Sliders ---
            // Assuming ModernSlider has its own internal styling.
            // If not, wrap them in Containers similar to above.
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
// ANIMATED WIDGETS
// ==========================================

class _AnimatedModelCard extends StatefulWidget {
  final String name;
  final String imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedModelCard({
    Key? key,
    required this.name,
    required this.imageUrl,
    required this.isSelected,
    required this.onTap,
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
