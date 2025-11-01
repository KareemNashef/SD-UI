// ==================== Progress Overlay ==================== //

// Flutter imports
import 'dart:convert';
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Progress Overlay Class ========== //

class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({super.key});

  Widget _buildProgressContent(Map<String, dynamic> progressData) {
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
      color: Colors.black.withValues(alpha:0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.grey.shade800.withValues(alpha:0.95),
                Colors.grey.shade900.withValues(alpha:0.98),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.purple.shade400.withValues(alpha:0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.shade400.withValues(alpha:0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: Colors.purple.shade300,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generating Images',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Current Image Preview
              if (currentImage != null) ...[
                Container(
                  height: 200,
                  width: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.purple.shade400.withValues(alpha:0.8),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(currentImage),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Progress Bar
              Column(
                children: [
                  // Main Progress Bar
                  Container(
                    width: double.infinity,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha:0.2),
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
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        // Progress fill
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple.shade400,
                                  Colors.purple.shade300,
                                  Colors.blue.shade400,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.shade400.withValues(alpha:
                                    0.5,
                                  ),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Progress percentage
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Progress Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha:0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha:0.1),
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
                              color: Colors.white.withValues(alpha:0.8),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '$samplingStep / $samplingSteps',
                            style: TextStyle(
                              color: Colors.purple.shade300,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Batch Progress
                    if (jobCount > 1) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Batch',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha:0.8),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${jobNo + 1} / $jobCount',
                            style: TextStyle(
                              color: Colors.blue.shade300,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ETA
                    if (eta > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ETA',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha:0.8),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${eta.toStringAsFixed(0)}s',
                            style: TextStyle(
                              color: Colors.green.shade300,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Animated loading indicator
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.purple.shade400, Colors.blue.shade400],
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
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

  Widget _buildSimpleLoading() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha:0.85),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.grey.shade800.withValues(alpha:0.95),
                Colors.grey.shade900.withValues(alpha:0.98),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.purple.shade400.withValues(alpha:0.5),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.purple.shade400, Colors.blue.shade400],
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Initializing...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
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
              return _buildSimpleLoading();
            }

            return _buildProgressContent(progressData);
          },
        );
      },
    );
  }
}
