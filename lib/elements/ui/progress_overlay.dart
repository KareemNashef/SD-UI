// ==================== Progress Overlay ==================== //

// Flutter imports
import 'dart:convert';
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/widgets/theme_constants.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Progress Overlay Implementation

class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsCheckpointTesting,
      builder: (context, isCheckpointTesting, child) {
        final accentColor = isCheckpointTesting
            ? AppTheme.accentSecondary
            : AppTheme.accentPrimary;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Builder(
            key: ValueKey<bool>(isCheckpointTesting),
            builder: (context) {
              // 1. Checkpoint Testing Mode
              if (isCheckpointTesting) {
                return _buildTestingFlow(accentColor);
              }
              // 2. Standard Generation Mode
              return _buildGenerationFlow(accentColor);
            },
          ),
        );
      },
    );
  }

  Widget _buildTestingFlow(Color accentColor) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsChangingCheckpoint,
      builder: (context, isChangingCheckpoint, child) {
        if (isChangingCheckpoint) {
          return _GlassHudCard(
            accentColor: accentColor,
            child: _buildCheckpointLoader(accentColor),
          );
        }
        return ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: globalProgressData,
          builder: (context, progressData, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: globalIsGenerating,
              builder: (context, isGenerating, child) {
                if (progressData == null || !isGenerating) {
                  return _GlassHudCard(
                    accentColor: accentColor,
                    child: _buildSimpleLoader("Preparing Test...", accentColor),
                  );
                }
                return _GlassHudCard(
                  accentColor: accentColor,
                  child: _buildProgressContent(
                    progressData,
                    accentColor,
                    isTesting: true,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGenerationFlow(Color accentColor) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsGenerating,
      builder: (context, isGenerating, child) {
        if (!isGenerating) return const SizedBox.shrink();

        return ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: globalProgressData,
          builder: (context, progressData, child) {
            if (progressData == null) {
              return _GlassHudCard(
                accentColor: accentColor,
                child: _buildSimpleLoader("Initializing...", accentColor),
              );
            }

            // --- CHECKPOINT CHANGE DETECTION ---
            // Extract state info to see if the backend is loading a model
            final state = progressData['state'] as Map<String, dynamic>? ?? {};
            final jobDescription = (state['job'] as String? ?? '')
                .toLowerCase();

            // Check for keywords often sent by SD WebUI during model loads
            final bool isSwitchingModel =
                jobDescription.contains('loading') ||
                jobDescription.contains('checkpoint') ||
                jobDescription.contains('weights');

            if (isSwitchingModel) {
              return _GlassHudCard(
                accentColor: accentColor,
                child: _buildCheckpointLoader(
                  accentColor,
                  // Pass a generic message since we might not know the exact target name here
                  overrideMessage: "Loading Model...",
                ),
              );
            }
            // -----------------------------------

            return _GlassHudCard(
              accentColor: accentColor,
              child: _buildProgressContent(
                progressData,
                accentColor,
                isTesting: false,
              ),
            );
          },
        );
      },
    );
  }

  // ==================== Content Builders ==================== //

  Widget _buildSimpleLoader(String message, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 60,
          width: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(color: accentColor, strokeWidth: 2.5),
              Icon(
                Icons.auto_awesome,
                color: Colors.white.withValues(alpha: 0.8),
                size: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Updated to support an override message for standard generation flow
  Widget _buildCheckpointLoader(Color accentColor, {String? overrideMessage}) {
    if (overrideMessage != null) {
      // Logic for Standard Generation (Static message)
      return _buildCheckpointContent(accentColor, overrideMessage);
    }

    // Logic for Testing Mode (Dynamic Global Listener)
    return ValueListenableBuilder<String?>(
      valueListenable: globalCurrentTestingCheckpoint,
      builder: (context, checkpointName, _) {
        return _buildCheckpointContent(
          accentColor,
          checkpointName ?? "Loading...",
        );
      },
    );
  }

  // Extracted helper to avoid code duplication
  Widget _buildCheckpointContent(Color accentColor, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SpinningGear(color: accentColor, size: 48),
        const SizedBox(height: 24),
        const Text(
          'Switching Model',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressContent(
    Map<String, dynamic> data,
    Color accentColor, {
    required bool isTesting,
  }) {
    // Extract Data
    final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
    final eta = data['eta_relative'] as num? ?? 0;
    final state = data['state'] as Map<String, dynamic>? ?? {};
    final currentImage = data['current_image'] as String?;

    final stepCurrent = state['sampling_step'] as int? ?? 0;
    final stepTotal = state['sampling_steps'] as int? ?? 0;
    final jobCurrent = (state['job_no'] as int? ?? 0) + 1;
    final jobTotal = state['job_count'] as int? ?? 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Dynamic Header
        if (isTesting)
          _buildTestingHeader(accentColor)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bolt, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'GENERATING',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

        const SizedBox(height: 20),

        // 2. Scanner Frame Image Preview
        if (currentImage != null)
          _ScannerPreviewFrame(
            base64Image: currentImage,
            accentColor: accentColor,
          ),

        const SizedBox(height: 24),

        // 3. Progress Bar & Percentage
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PROGRESS",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "${(progress * 100).toInt()}%",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _NeonProgressBar(progress: progress, color: accentColor),

        const SizedBox(height: 24),

        // 4. Stats Grid
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatBadge(
              label: "STEP",
              value: "$stepCurrent/$stepTotal",
              icon: Icons.layers,
            ),
            if (jobTotal > 1)
              _StatBadge(
                label: "BATCH",
                value: "$jobCurrent/$jobTotal",
                icon: Icons.copy,
              ),
            _StatBadge(
              label: "ETA",
              value: "${eta.toInt()}s",
              icon: Icons.timer,
              valueColor: accentColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTestingHeader(Color accentColor) {
    return ValueListenableBuilder<int>(
      valueListenable: globalCurrentCheckpointTestIndex,
      builder: (context, index, _) {
        return ValueListenableBuilder<int>(
          valueListenable: globalTotalCheckpointsToTest,
          builder: (context, total, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.science, color: accentColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    "TEST ${index + 1} / $total",
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ==================== Helper Widgets ==================== //

// ... (Rest of your helper widgets: _GlassHudCard, _ScannerPreviewFrame, etc., remain unchanged)
class _GlassHudCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;

  const _GlassHudCard({required this.child, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.7)),
        ),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.glassBackground.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _ScannerPreviewFrame extends StatelessWidget {
  final String base64Image;
  final Color accentColor;

  const _ScannerPreviewFrame({
    required this.base64Image,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Image.memory(
                base64Decode(base64Image),
                key: ValueKey(base64Image.hashCode),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    accentColor.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _NeonProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth * progress;
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: width,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.5), color],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SpinningGear extends StatefulWidget {
  final Color color;
  final double size;

  const _SpinningGear({required this.color, required this.size});

  @override
  State<_SpinningGear> createState() => _SpinningGearState();
}

class _SpinningGearState extends State<_SpinningGear>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
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
      child: Icon(
        Icons.settings_suggest,
        color: widget.color,
        size: widget.size,
      ),
    );
  }
}
