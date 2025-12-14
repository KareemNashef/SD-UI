// ==================== Progress Overlay ==================== //

// Flutter imports
import 'dart:convert';
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Progress Overlay Class ========== //

class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({super.key});

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
                        Icon(
                          Icons.science,
                          color: Colors.lime.shade300,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Checkpoint Testing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.lime.shade400.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.lime.shade400.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Testing ${currentIndex + 1} of $totalCheckpoints',
                        style: TextStyle(
                          color: Colors.lime.shade300,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (currentCheckpoint != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.cyan.shade400.withValues(alpha: 0.2),
                              Colors.lime.shade400.withValues(alpha: 0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.cyan.shade400.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.architecture,
                              color: Colors.cyan.shade300,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                currentCheckpoint,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
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
        return ValueListenableBuilder<int>(
          valueListenable: globalCurrentCheckpointTestIndex,
          builder: (context, currentIndex, child) {
            return ValueListenableBuilder<int>(
              valueListenable: globalTotalCheckpointsToTest,
              builder: (context, totalCheckpoints, child) {
                return Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black.withValues(alpha: 0.85),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.lime.shade800.withValues(alpha: 0.95),
                            Colors.cyan.shade900.withValues(alpha: 0.98),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.lime.shade400.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.lime.shade400.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          _buildCheckpointTestingHeader(),

                          const SizedBox(height: 24),

                          // Changing checkpoint icon
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.lime.shade400,
                                  Colors.cyan.shade400,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.lime.shade400.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.sync,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Status text
                          Text(
                            'Changing Checkpoint',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
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

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isCheckpointTesting
                  ? [
                      Colors.lime.shade800.withValues(alpha: 0.95),
                      Colors.cyan.shade900.withValues(alpha: 0.98),
                    ]
                  : [
                      Colors.grey.shade800.withValues(alpha: 0.95),
                      Colors.grey.shade900.withValues(alpha: 0.98),
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCheckpointTesting
                  ? Colors.lime.shade400.withValues(alpha: 0.5)
                  : Colors.cyan.shade400.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isCheckpointTesting
                    ? Colors.lime.shade400.withValues(alpha: 0.3)
                    : Colors.cyan.shade400.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
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
                    Icon(
                      Icons.auto_awesome,
                      color: Colors.cyan.shade300,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Generating Images',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 24),

              // Current Image Preview
              if (currentImage != null) ...[
                Container(
                  height: 160,
                  width: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCheckpointTesting
                          ? Colors.lime.shade400.withValues(alpha: 0.8)
                          : Colors.cyan.shade400.withValues(alpha: 0.8),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(currentImage),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Progress Bar
              Column(
                children: [
                  // Main Progress Bar
                  Container(
                    width: double.infinity,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Background gradient
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.grey.shade800,
                                Colors.grey.shade700,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        // Progress fill
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isCheckpointTesting
                                    ? [
                                        Colors.lime.shade400,
                                        Colors.cyan.shade400,
                                        Colors.lime.shade300,
                                      ]
                                    : [
                                        Colors.cyan.shade400,
                                        Colors.cyan.shade300,
                                        Colors.lime.shade400,
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: [
                                BoxShadow(
                                  color: isCheckpointTesting
                                      ? Colors.lime.shade400.withValues(
                                          alpha: 0.5,
                                        )
                                      : Colors.cyan.shade400.withValues(
                                          alpha: 0.5,
                                        ),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Progress percentage
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress Details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    // Sampling Steps
                    if (samplingSteps > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Step',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$samplingStep / $samplingSteps',
                            style: TextStyle(
                              color: isCheckpointTesting
                                  ? Colors.lime.shade300
                                  : Colors.cyan.shade300,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    // Batch Progress
                    if (jobCount > 1) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Batch',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${jobNo + 1} / $jobCount',
                            style: TextStyle(
                              color: Colors.lime.shade300,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    // ETA
                    if (eta > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ETA',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${eta.toStringAsFixed(0)}s',
                            style: TextStyle(
                              color: Colors.green.shade300,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Animated loading indicator
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isCheckpointTesting
                        ? [Colors.lime.shade400, Colors.cyan.shade400]
                        : [Colors.cyan.shade400, Colors.lime.shade400],
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleLoading(bool isCheckpointTesting) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isCheckpointTesting
                  ? [
                      Colors.lime.shade800.withValues(alpha: 0.95),
                      Colors.cyan.shade900.withValues(alpha: 0.98),
                    ]
                  : [
                      Colors.grey.shade800.withValues(alpha: 0.95),
                      Colors.grey.shade900.withValues(alpha: 0.98),
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCheckpointTesting
                  ? Colors.lime.shade400.withValues(alpha: 0.5)
                  : Colors.cyan.shade400.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isCheckpointTesting
                    ? Colors.lime.shade400.withValues(alpha: 0.3)
                    : Colors.cyan.shade400.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCheckpointTesting) _buildCheckpointTestingHeader(),
              if (isCheckpointTesting) const SizedBox(height: 24),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isCheckpointTesting
                        ? [Colors.lime.shade400, Colors.cyan.shade400]
                        : [Colors.cyan.shade400, Colors.lime.shade400],
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isCheckpointTesting ? 'Preparing...' : 'Initializing...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // First check if checkpoint testing is active
    return ValueListenableBuilder<bool>(
      valueListenable: globalIsCheckpointTesting,
      builder: (context, isCheckpointTesting, child) {
        // Checkpoint testing mode - overlay stays visible throughout
        if (isCheckpointTesting) {
          return ValueListenableBuilder<bool>(
            valueListenable: globalIsChangingCheckpoint,
            builder: (context, isChangingCheckpoint, child) {
              // Show "Changing Checkpoint" screen when switching checkpoints
              if (isChangingCheckpoint) {
                return _buildChangingCheckpointOverlay();
              }

              // Show progress when generating
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: globalProgressData,
                builder: (context, progressData, child) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: globalIsGenerating,
                    builder: (context, isGenerating, child) {
                      // Always show something during checkpoint testing
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

        // Normal generation mode (not checkpoint testing)
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
    );
  }
}
