// ==================== Checkpoint Testing Service ==================== //

import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';
import 'package:sd_companion/logic/api_calls.dart';

/// Service for managing checkpoint testing operations
class CheckpointTestingService {
  CheckpointData? _originalConfig;
  bool _isTesting = false;

  bool get isTesting => _isTesting;

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
    globalPageIndex.value = 1;

    for (int i = 0; i < checkpoints.length; i++) {
      if (!_isTesting) break;
      globalCurrentCheckpointTestIndex.value = i;
      globalCurrentTestingCheckpoint.value = checkpoints[i];
      await _testCheckpoint(checkpoints[i], onGenerate);
      if (i < checkpoints.length - 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Restore original config
    if (_originalConfig != null) {
      globalCurrentCheckpointName = _originalConfig!.title;
      await setCheckpoint();
    }

    _isTesting = false;
    globalIsCheckpointTesting.value = false;
    globalCurrentTestingCheckpoint.value = null;
  }

  /// Stops the current testing session
  void stopTesting() {
    _isTesting = false;
  }

  Future<void> _testCheckpoint(String checkpointName, Function() onGenerate) async {
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
}
