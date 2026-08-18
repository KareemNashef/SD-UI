// ==================== Checkpoint Testing Service ==================== //

// Local imports - Logic
import 'package:sd_companion/logic/api_calls.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';

// Checkpoint Testing Service Implementation

/// Service for managing checkpoint testing operations
class CheckpointTestingService {
  // ===== Class Variables ===== //
  CheckpointData? _originalConfig;
  bool _isTesting = false;

  bool get isTesting => _isTesting;

  // ===== Class Methods ===== //

  /// Starts testing a list of checkpoints
  Future<void> startCheckpointTesting({
    required List<String> checkpoints,
    required Function() onGenerate,
  }) async {
    if (_isTesting) return;

    // Save original config
    _originalConfig = CheckpointData(
      title: globalCurrentCheckpointName,
      imageURL: '',
      samplingSteps: globalCurrentSamplingSteps,
      samplingMethod: globalCurrentSamplingMethod,
      cfgScale: globalCurrentCfgScale,
      resolutionHeight: globalCurrentResolutionHeight,
      resolutionWidth: globalCurrentResolutionWidth,
    );

    _isTesting = true;
    globalIsCheckpointTesting.value = true;
    globalTotalCheckpointsToTest.value = checkpoints.length;
    navigateToResultsPage();

    for (int i = 0; i < checkpoints.length; i++) {
      if (!_isTesting) break;
      globalCurrentCheckpointTestIndex.value = i;
      globalCurrentTestingCheckpoint.value = checkpoints[i];
      await _testCheckpoint(checkpoints[i], onGenerate);
      if (i < checkpoints.length - 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    await _restoreConfig();
  }

  /// Starts testing a list of samplers on a specific checkpoint
  Future<void> startSamplerTesting({
    required List<String> samplers,
    required String targetCheckpoint,
    required Function() onGenerate,
  }) async {
    if (_isTesting) return;

    // 1. Save Original Config
    _originalConfig = CheckpointData(
      title: globalCurrentCheckpointName,
      imageURL: '',
      samplingSteps: globalCurrentSamplingSteps,
      samplingMethod: globalCurrentSamplingMethod,
      cfgScale: globalCurrentCfgScale,
      resolutionHeight: globalCurrentResolutionHeight,
      resolutionWidth: globalCurrentResolutionWidth,
    );

    _isTesting = true;
    globalIsCheckpointTesting.value = true;
    globalTotalCheckpointsToTest.value = samplers.length;
    navigateToResultsPage();

    try {
      // 2. Switch to the target checkpoint ONCE
      globalIsChangingCheckpoint.value = true;
      globalCurrentCheckpointName = targetCheckpoint;

      // Load standard settings for this checkpoint if available
      final data = globalCheckpointDataMap[targetCheckpoint];
      if (data != null) {
        globalCurrentResolutionWidth = data.resolutionWidth;
        globalCurrentResolutionHeight = data.resolutionHeight;
        globalCurrentCfgScale = data.cfgScale;
        globalCurrentSamplingSteps = data.samplingSteps;
      }

      await setCheckpoint();
      await Future.delayed(const Duration(milliseconds: 500));
      globalIsChangingCheckpoint.value = false;

      // 3. Iterate Samplers
      for (int i = 0; i < samplers.length; i++) {
        if (!_isTesting) break; // Check for cancellation

        globalCurrentCheckpointTestIndex.value = i;
        // Update label to show sampler name instead of checkpoint name
        globalCurrentTestingCheckpoint.value = samplers[i];

        // Change only the sampler
        globalCurrentSamplingMethod = samplers[i];

        await onGenerate();

        if (i < samplers.length - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } catch (e) {
      // Log error internally if needed, logic is kept robust
    } finally {
      await _restoreConfig();
    }
  }

  /// Stops the current testing session
  void stopTesting() {
    _isTesting = false;
  }

  // ===== Helper Methods ===== //

  Future<void> _testCheckpoint(
    String checkpointName,
    Function() onGenerate,
  ) async {
    try {
      globalIsChangingCheckpoint.value = true;
      final data = globalCheckpointDataMap[checkpointName];
      if (data == null) {
        globalIsChangingCheckpoint.value = false;
        return;
      }
      globalCurrentCheckpointName = checkpointName;
      globalCurrentSamplingSteps = data.samplingSteps;
      globalCurrentSamplingMethod = data.samplingMethod;
      globalCurrentCfgScale = data.cfgScale;
      await setCheckpoint();
      await Future.delayed(const Duration(milliseconds: 500));
      globalIsChangingCheckpoint.value = false;
      await onGenerate();
    } catch (e) {
      globalIsChangingCheckpoint.value = false;
    }
  }

  Future<void> _restoreConfig() async {
    if (_originalConfig != null) {
      globalCurrentCheckpointName = _originalConfig!.title;
      globalCurrentSamplingSteps = _originalConfig!.samplingSteps;
      globalCurrentSamplingMethod = _originalConfig!.samplingMethod;
      globalCurrentCfgScale = _originalConfig!.cfgScale;
      globalCurrentResolutionWidth = _originalConfig!.resolutionWidth;
      globalCurrentResolutionHeight = _originalConfig!.resolutionHeight;
      await setCheckpoint();
    }

    _isTesting = false;
    globalIsCheckpointTesting.value = false;
    globalIsChangingCheckpoint.value = false;
    globalCurrentTestingCheckpoint.value = null;
  }
}
