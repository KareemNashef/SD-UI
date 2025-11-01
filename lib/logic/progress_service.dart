// ==================== Progress Service ==================== //

// Flutter/Dart imports
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// ========== Progress Service Class ========== //

class ProgressService {
  // ===== Singleton Pattern ===== //
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;
  ProgressService._internal();

  // ===== Class Variables ===== //
  Timer? _progressTimer;
  bool _isPolling = false;
  bool _hasStartedGeneration =
      false; // Track if generation has actually started
  int _errorCount = 0; // Track consecutive errors
  DateTime? _startTime; // Track when polling started
  static const int _maxErrors = 3; // Max consecutive errors before stopping
  static const int _minPollingTimeMs =
      2000; // Minimum time before allowing completion check

  // ===== Public Methods ===== //

  /// Starts polling the progress API
  void startProgressPolling() {
    if (_isPolling) return;

    _isPolling = true;
    _hasStartedGeneration = false; // Reset generation tracking
    _errorCount = 0; // Reset error count
    _startTime = DateTime.now(); // Track when we started polling
    globalIsGenerating.value = true;
    globalProgressData.value = null; // Reset progress data

    // Poll every 500ms for smooth updates
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) => _fetchProgress(),
    );
  }

  /// Stops polling the progress API
  void stopProgressPolling() {
    _isPolling = false;
    _hasStartedGeneration = false;
    _errorCount = 0;
    _startTime = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    globalIsGenerating.value = false;
    globalProgressData.value = null;
  }

  /// Checks if currently polling
  bool get isPolling => _isPolling;

  // ===== Private Methods ===== //

  /// Fetches progress data from the API
  Future<void> _fetchProgress() async {
    if (!_isPolling) return;

    try {
      // Check server connection first
      if (!globalServerStatus.value) {
        debugPrint('Server offline - stopping progress polling');
        stopProgressPolling();
        return;
      }

      // Build progress API URL
      final url = Uri.parse(
        'http://${globalServerIP.value}:${globalServerPort.value}/sdapi/v1/progress',
      );

      // Make the API request with timeout
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('Progress request timeout');
            },
          );

      if (response.statusCode == 200) {
        _errorCount = 0; // Reset error count on success

        final progressData = jsonDecode(response.body) as Map<String, dynamic>;

        // Update global progress data
        globalProgressData.value = progressData;

        // Get progress information
        final progress = (progressData['progress'] as num?)?.toDouble() ?? 0.0;
        final state = progressData['state'] as Map<String, dynamic>? ?? {};
        final jobCount = state['job_count'] as int? ?? 0;
        final samplingSteps = state['sampling_steps'] as int? ?? 0;

        // Check if generation has actually started
        if (!_hasStartedGeneration) {
          // Consider generation started if:
          // - Progress > 0 AND (job count > 0 OR sampling step > 0)
          // This prevents false positives from inconsistent initial API responses
          _hasStartedGeneration =
              progress > 0.0 &&
              (jobCount > 0 || ((state['sampling_step'] as int?) ?? 0) > 0);

          if (_hasStartedGeneration) {
            debugPrint(
              'Generation detected as started - progress: $progress, jobs: $jobCount, steps: $samplingSteps',
            );
          }
        }

        // Only check for completion if:
        // 1. Generation has started
        // 2. We've been polling for at least minimum time (to avoid false positives)
        if (_hasStartedGeneration && _hasMinimumPollingTime()) {
          final isComplete = _isGenerationComplete(progressData);

          if (isComplete) {
            debugPrint('Generation completed - stopping polling');
            // Wait a bit for final images to be processed
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (_isPolling) {
                stopProgressPolling();
              }
            });
          }
        } else {
          // If we haven't started yet or haven't waited long enough, log the current state
          final timeSinceStart = _startTime != null
              ? DateTime.now().difference(_startTime!).inMilliseconds
              : 0;
          debugPrint(
            'Waiting for generation (${timeSinceStart}ms) - progress: $progress, jobs: $jobCount, steps: $samplingSteps, started: $_hasStartedGeneration',
          );
        }
      } else {
        // Handle API errors
        _errorCount++;
        debugPrint(
          'Progress API error: ${response.statusCode} (error count: $_errorCount)',
        );

        if (response.statusCode >= 400 && _errorCount >= _maxErrors) {
          debugPrint('Too many API errors - stopping progress polling');
          stopProgressPolling();
        }
      }
    } catch (e) {
      // Handle network errors
      _errorCount++;
      debugPrint('Progress fetch error: $e (error count: $_errorCount)');

      // Stop polling on persistent errors after max attempts
      if (_errorCount >= _maxErrors) {
        debugPrint('Too many consecutive errors - stopping progress polling');
        stopProgressPolling();
      } else if (e is TimeoutException || e.toString().contains('Connection')) {
        // Wait a bit longer on connection issues before next attempt
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Check if minimum polling time has elapsed
  bool _hasMinimumPollingTime() {
    if (_startTime == null) return false;
    final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
    return elapsed >= _minPollingTimeMs;
  }

  /// Check if generation is actually complete
  bool _isGenerationComplete(Map<String, dynamic> progressData) {
    final progress = (progressData['progress'] as num?)?.toDouble() ?? 0.0;
    final state = progressData['state'] as Map<String, dynamic>? ?? {};
    final jobCount = state['job_count'] as int? ?? 0;
    final samplingStep = state['sampling_step'] as int? ?? 0;
    final samplingSteps = state['sampling_steps'] as int? ?? 0;
    final jobNo = state['job_no'] as int? ?? 0;

    // Generation is complete if:
    // 1. Progress is 1.0 (100% complete)
    // 2. OR (we have steps info and current step equals total steps and we're on the last job)

    bool isComplete = false;

    if (progress >= 1.0) {
      debugPrint('Complete: Progress at 100%');
      isComplete = true;
    } else if (samplingSteps > 0 && samplingStep >= samplingSteps) {
      // Check if we're on the last job
      if (jobCount <= 1 || jobNo >= jobCount - 1) {
        debugPrint('Complete: Final sampling step on last job');
        isComplete = true;
      } else {
        debugPrint(
          'Sampling step complete but more jobs remaining: ${jobNo + 1}/$jobCount',
        );
      }
    }

    // Remove the problematic zero-progress completion check entirely
    // as it was causing premature completion detection

    if (!isComplete) {
      debugPrint(
        'Still generating - Progress: $progress, Step: $samplingStep/$samplingSteps, Job: ${jobNo + 1}/$jobCount',
      );
    }

    return isComplete;
  }
}

// ========== Progress Service Extensions ========== //

/// Extension to easily access the progress service
extension ProgressServiceExtension on ProgressService {
  /// Convenience method to start generation tracking
  void trackGeneration() {
    startProgressPolling();
  }

  /// Convenience method to stop generation tracking
  void stopTracking() {
    stopProgressPolling();
  }
}
