// ==================== Global Variables ==================== //

// Flutter imports
import 'dart:io';
import 'package:flutter/material.dart';

// Local imports - Logic
import 'package:sd_companion/logic/backend/a1111_backend.dart';
import 'package:sd_companion/logic/models/checkpoint_data.dart';
import 'package:sd_companion/logic/models/lora_data.dart';

// Local imports - Pages
import 'package:sd_companion/main_page.dart';

// Global Variables Implementation

// ===== Backend Variables ===== //

final A1111Backend globalBackend = A1111Backend();

// ===== App Variables ===== //

// MainPageState key
final GlobalKey<MainPageState> mainPageKey = GlobalKey<MainPageState>();

// Function to navigate to inpaint page
void navigateToInpaintPage() {
  mainPageKey.currentState?.switchToPage(0);
}

// Function to navigate to results page
void navigateToResultsPage() {
  mainPageKey.currentState?.switchToPage(1);
}

// Function to navigate to settings page
void navigateToSettingsPage() {
  mainPageKey.currentState?.switchToPage(2);
}

// ===== Server Variables ===== //

// Server status
ValueNotifier<bool> globalServerStatus = ValueNotifier(false);

// Server IP
ValueNotifier<String> globalServerIP = ValueNotifier('127.0.0.1');

// Server port
ValueNotifier<String> globalServerPort = ValueNotifier('7860');

// ===== Checkpoint Variables ===== //

// Checkpoint data map
Map<String, CheckpointData> globalCheckpointDataMap = {};

// Internal function to sync local settings (resolution, steps, etc.) from the active backend's selected model
void syncActiveCheckpointSettings() {
  final name = globalCurrentCheckpointName;
  final data = globalCheckpointDataMap[name];

  if (data != null) {
    globalCurrentResolutionHeight = data.resolutionHeight;
    globalCurrentResolutionWidth = data.resolutionWidth;
    globalCurrentSamplingSteps = data.samplingSteps;
    globalCurrentSamplingMethod = data.samplingMethod;
    globalCurrentCfgScale = data.cfgScale;
    globalDenoiseStrength = data.denoisingStrength;
  } else {
    // Fallbacks if no checkpoint or data
    if (globalCheckpointDataMap.isNotEmpty) {
      // If we have models but non-selected, select the first one
      final firstKey = globalCheckpointDataMap.keys.first;
      globalCurrentCheckpointName = firstKey;
      syncActiveCheckpointSettings(); // Re-run with the new selection
      return;
    }
    globalCurrentResolutionHeight = 512;
    globalCurrentResolutionWidth = 512;
    globalCurrentSamplingSteps = 20;
    globalCurrentSamplingMethod = 'DPM++ 2M';
    globalCurrentCfgScale = 3.5;
    globalDenoiseStrength = 0.95;
  }
}

// Selected checkpoint name storage
String globalCurrentCheckpointName = '';

// Selected resolution
int globalCurrentResolutionHeight = 512;
int globalCurrentResolutionWidth = 512;

// Selected checkpoint sampling steps
int globalCurrentSamplingSteps = 20;

// Selected checkpoint sampling method
String globalCurrentSamplingMethod = 'Euler a';

// Selected checkpoint cfg scale
double globalCurrentCfgScale = 7.0;

// ===== Generation Variables ===== //

double globalDenoiseStrength = 0.95;
int globalMaskBlur = 8;
String globalMaskFill = 'fill';
int globalBatchSize = 1;
String globalNegativePrompt = '';

// ===== Checkpoint Testing Variables ===== //

ValueNotifier<bool> globalIsCheckpointTesting = ValueNotifier<bool>(false);
ValueNotifier<String?> globalCurrentTestingCheckpoint = ValueNotifier<String?>(
  null,
);
ValueNotifier<int> globalCurrentCheckpointTestIndex = ValueNotifier<int>(0);
ValueNotifier<int> globalTotalCheckpointsToTest = ValueNotifier<int>(0);
ValueNotifier<bool> globalIsChangingCheckpoint = ValueNotifier<bool>(false);

// ===== Inpaint Variables ===== //

// Current inpaint image
final ValueNotifier<String?> globalImageToEdit = ValueNotifier(null);
final ValueNotifier<File?> globalInputImage = ValueNotifier(null);

// Current inpaint prompt
String globalInpaintPrompt = '';

// Inpaint prompt history
Set<String> globalInpaintHistory = {};
Set<String> globalFavoritePrompts = {};

// ===== Results Variables ===== //

// Global storage for result images
ValueNotifier<Set<String>> globalResultImages = ValueNotifier({});

// Global flag to track if image generation is currently in progress
final ValueNotifier<bool> globalIsGenerating = ValueNotifier<bool>(false);

// Global storage for current progress data from the API
final ValueNotifier<Map<String, dynamic>?> globalProgressData =
    ValueNotifier<Map<String, dynamic>?>(null);

// Global flag to track if we should show intermediate images
final ValueNotifier<bool> globalShowProgressImages = ValueNotifier<bool>(true);

// How often to poll for progress updates (in milliseconds)
final ValueNotifier<int> globalProgressPollInterval = ValueNotifier<int>(500);

// Whether to show detailed progress information (steps, ETA, etc.)
final ValueNotifier<bool> globalShowDetailedProgress = ValueNotifier<bool>(
  true,
);

// Whether to automatically hide progress overlay when complete
final ValueNotifier<bool> globalAutoHideProgress = ValueNotifier<bool>(true);

// ===== Lora Variables ===== //

// Lora data map
Map<String, LoraData> globalLoraDataMap = {};
