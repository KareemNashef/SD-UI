// ==================== Progress Overlay ==================== //

// Flutter imports
import 'dart:convert';
import 'dart:ui'; // Required for BackdropFilter
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Progress Overlay Class ========== //

class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({super.key});

  // Helper: Common Glass/Gradient Container Style
  BoxDecoration _buildGlassDecoration({bool isCheckpointTesting = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isCheckpointTesting
            ? [
                Colors.lime.shade900.withValues(alpha: 0.9),
                Colors.cyan.shade900.withValues(alpha: 0.95),
              ]
            : [
                Colors.grey.shade900.withValues(alpha: 0.9),
                Colors.black.withValues(alpha: 0.95),
              ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: isCheckpointTesting
            ? Colors.lime.shade400.withValues(alpha: 0.3)
            : Colors.cyan.shade400.withValues(alpha: 0.3),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: isCheckpointTesting
              ? Colors.lime.shade900.withValues(alpha: 0.5)
              : Colors.cyan.shade900.withValues(alpha: 0.5),
          blurRadius: 30,
          spreadRadius: 5,
        ),
      ],
    );
  }

  Widget _buildCheckpointTestingHeader() {
    return ValueListenableBuilder<String?>(
      valueListenable: globalCurrentTestingCheckpoint,
      builder: (context, currentCheckpoint, child) {
        return ValueListenableBuilder<int>(
          valueListenable: globalCurrentCheckpointTestIndex,
          builder: (context, currentIndex, child) {
            return ValueListenableBuilder<int>(
              valueListenable: globalTotalCheckpointsToTest,
              builder: (context, totalCheckpoints, child) {
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SpinningIcon(
                          icon: Icons.science,
                          color: Colors.lime.shade300,
                          size: 24,
                          duration: const Duration(seconds: 4),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Checkpoint Testing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.lime.shade400.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.lime.shade400.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Testing ${currentIndex + 1} of $totalCheckpoints',
                        style: TextStyle(
                          color: Colors.lime.shade300,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (currentCheckpoint != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.dns_rounded,
                              color: Colors.cyan.shade300,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                currentCheckpoint,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChangingCheckpointOverlay() {
    return ValueListenableBuilder<String?>(
      valueListenable: globalCurrentTestingCheckpoint,
      builder: (context, currentCheckpoint, child) {
        return _OverlayBackground(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: _buildGlassDecoration(isCheckpointTesting: true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCheckpointTestingHeader(),
                const SizedBox(height: 40),
                
                // Animated Loading Icon
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.lime.shade400.withValues(alpha: 0.3),
                      ),
                    ),
                    _SpinningIcon(
                      icon: Icons.sync,
                      color: Colors.cyan.shade300,
                      size: 32,
                      duration: const Duration(seconds: 1),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Text(
                  'Switching Checkpoint...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressContent(
    Map<String, dynamic> progressData,
    bool isCheckpointTesting,
  ) {
    final progress = (progressData['progress'] as num?)?.toDouble() ?? 0.0;
    final eta = progressData['eta_relative'] as num? ?? 0;
    final state = progressData['state'] as Map<String, dynamic>? ?? {};
    final currentImage = progressData['current_image'] as String?;

    final samplingStep = state['sampling_step'] as int? ?? 0;
    final samplingSteps = state['sampling_steps'] as int? ?? 0;
    final jobCount = state['job_count'] as int? ?? 0;
    final jobNo = state['job_no'] as int? ?? 0;

    final accentColor = isCheckpointTesting
        ? Colors.lime.shade400
        : Colors.cyan.shade400;

    return _OverlayBackground(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: _buildGlassDecoration(
          isCheckpointTesting: isCheckpointTesting,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            if (isCheckpointTesting)
              _buildCheckpointTestingHeader()
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PulsingIcon(
                    icon: Icons.auto_awesome,
                    color: Colors.cyan.shade300,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Generating...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            // Animated Image Preview
            if (currentImage != null)
              Container(
                height: 200,
                width: 200,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.2),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _AnimatedImagePreview(base64String: currentImage),
                ),
              ),

            // Animated Progress Bar
            _AnimatedProgressBar(
              progress: progress,
              color: accentColor,
            ),
            
            const SizedBox(height: 8),
            
            // Percentage Text
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),

            const SizedBox(height: 20),

            // Stats Grid
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (samplingSteps > 0)
                    _buildStatItem('Step', '$samplingStep/$samplingSteps', accentColor),
                  
                  if (jobCount > 1)
                    _buildStatItem('Batch', '${jobNo + 1}/$jobCount', Colors.white),
                  
                  if (eta > 0)
                    _buildStatItem('ETA', '${eta.toStringAsFixed(0)}s', Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleLoading(bool isCheckpointTesting) {
    return _OverlayBackground(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: _buildGlassDecoration(
          isCheckpointTesting: isCheckpointTesting,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCheckpointTesting) ...[
              _buildCheckpointTestingHeader(),
              const SizedBox(height: 32),
            ],
            
            // Custom Spinner
            SizedBox(
              height: 60,
              width: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    color: isCheckpointTesting 
                      ? Colors.lime.shade400 
                      : Colors.cyan.shade400,
                    strokeWidth: 3,
                  ),
                  _PulsingIcon(
                    icon: Icons.hourglass_empty_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 24,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            Text(
              isCheckpointTesting ? 'Preparing Environment...' : 'Initializing...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsCheckpointTesting,
      builder: (context, isCheckpointTesting, child) {
        
        // Wrap logic in a switcher for smooth fades between modes
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Builder(
            key: ValueKey<bool>(isCheckpointTesting),
            builder: (context) {
              if (isCheckpointTesting) {
                return ValueListenableBuilder<bool>(
                  valueListenable: globalIsChangingCheckpoint,
                  builder: (context, isChangingCheckpoint, child) {
                    if (isChangingCheckpoint) {
                      return _buildChangingCheckpointOverlay();
                    }
                    return ValueListenableBuilder<Map<String, dynamic>?>(
                      valueListenable: globalProgressData,
                      builder: (context, progressData, child) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: globalIsGenerating,
                          builder: (context, isGenerating, child) {
                            if (progressData == null || !isGenerating) {
                              return _buildSimpleLoading(true);
                            }
                            return _buildProgressContent(progressData, true);
                          },
                        );
                      },
                    );
                  },
                );
              }

              return ValueListenableBuilder<bool>(
                valueListenable: globalIsGenerating,
                builder: (context, isGenerating, child) {
                  if (!isGenerating) {
                    return const SizedBox.shrink();
                  }
                  return ValueListenableBuilder<Map<String, dynamic>?>(
                    valueListenable: globalProgressData,
                    builder: (context, progressData, child) {
                      if (progressData == null) {
                        return _buildSimpleLoading(false);
                      }
                      return _buildProgressContent(progressData, false);
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ==========================================
// ANIMATED HELPER WIDGETS
// ==========================================

class _OverlayBackground extends StatelessWidget {
  final Widget child;
  const _OverlayBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    // Adds a Blur effect to the entire screen behind the modal
    return Stack(
      children: [
        // Backdrop Blur
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
        ),
        // Content
        Center(child: child),
      ],
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _AnimatedProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Smoothly animated width
          LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: constraints.maxWidth * progress,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.7),
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AnimatedImagePreview extends StatelessWidget {
  final String base64String;

  const _AnimatedImagePreview({required this.base64String});

  @override
  Widget build(BuildContext context) {
    // Cross-fade between image updates
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Image.memory(
        base64Decode(base64String),
        key: ValueKey(base64String.hashCode), // Forces refresh animation
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final Duration duration;

  const _SpinningIcon({
    required this.icon,
    required this.color,
    required this.size,
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _PulsingIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}