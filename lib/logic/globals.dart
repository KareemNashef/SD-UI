// ==================== Global Variables ==================== //

// Flutter imports
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ===== App Variables ===== //

// Page index
ValueNotifier<int> globalPageIndex = ValueNotifier(0);

// ===== Server Variables ===== //

// Server status
ValueNotifier<bool> globalServerStatus = ValueNotifier(false);

// Server IP
ValueNotifier<String> globalServerIP = ValueNotifier('');

// Server port
ValueNotifier<String> globalServerPort = ValueNotifier('');

// Save values
Future<void> saveServerSettings(String ip, String port) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('serverIP', ip);
  await prefs.setString('serverPort', port);
}

// Load values
Future<void> loadServerSettings() async {
  final prefs = await SharedPreferences.getInstance();
  globalServerIP.value = prefs.getString('serverIP') ?? '';
  globalServerPort.value = prefs.getString('serverPort') ?? '';
}

// ===== Checkpoint Variables ===== //

// Checkpoint data
class CheckpointData {
  String title;
  String imageURL;
  double samplingSteps;
  String samplingMethod;
  double cfgScale;
  double resolutionHeight;
  double resolutionWidth;

  CheckpointData({
    required this.title,
    required this.imageURL,
    required this.samplingSteps,
    required this.samplingMethod,
    required this.cfgScale,
    required this.resolutionHeight,
    required this.resolutionWidth,
  });

  Map<String, dynamic> toJson() => {
    'Title': title,
    'imageURL': imageURL,
    'samplingSteps': samplingSteps,
    'samplingMethod': samplingMethod,
    'cfgScale': cfgScale,
    'resolutionHeight': resolutionHeight,
    'resolutionWidth': resolutionWidth,
  };

  factory CheckpointData.fromJson(Map<String, dynamic> json) => CheckpointData(
    title: json['Title'] ?? '',
    imageURL: json['imageURL'] ?? '',
    samplingSteps: (json['samplingSteps'] as num).toDouble(),
    samplingMethod: json['samplingMethod'],
    cfgScale: (json['cfgScale'] as num).toDouble(),
    resolutionHeight: (json['resolutionHeight'] ?? 512 as num).toDouble(),
    resolutionWidth: (json['resolutionWidth'] ?? 512 as num).toDouble(),
  );
}

// Checkpoint data
Map<String, CheckpointData> globalCheckpointDataMap = {};

// Save values
Future<void> saveCheckpointDataMap() async {
  final prefs = await SharedPreferences.getInstance();

  // Save the map
  final mapJson = jsonEncode(
    globalCheckpointDataMap.map((key, value) => MapEntry(key, value.toJson())),
  );
  await prefs.setString('checkpointDataMap', mapJson);

  // Save the last selected name
  await prefs.setString('currentCheckpointName', globalCurrentCheckpointName);
}

// Load values
Future<void> loadCheckpointDataMap() async {
  final prefs = await SharedPreferences.getInstance();

  // Load the map
  final mapJson = prefs.getString('checkpointDataMap');
  if (mapJson != null) {
    final Map<String, dynamic> decoded = jsonDecode(mapJson);
    globalCheckpointDataMap = decoded.map(
      (key, value) =>
          MapEntry(key, CheckpointData.fromJson(value as Map<String, dynamic>)),
    );
  }

  // Load the name of the last selected checkpoint
  globalCurrentCheckpointName = prefs.getString('currentCheckpointName') ?? '';

  // Check if the last selected checkpoint exists
  if (!globalCheckpointDataMap.containsKey(globalCurrentCheckpointName)) {
    globalCurrentCheckpointName = globalCheckpointDataMap.keys.first;
  }

  // Sync all other plain globals after loading.
  final data = globalCheckpointDataMap[globalCurrentCheckpointName];
  if (data != null) {
    globalCurrentResolutionHeight = data.resolutionHeight;
    globalCurrentResolutionWidth = data.resolutionWidth;
    globalCurrentSamplingSteps = data.samplingSteps;
    globalCurrentSamplingMethod = data.samplingMethod;
    globalCurrentCfgScale = data.cfgScale;
  } else {
    globalCurrentResolutionHeight = 512;
    globalCurrentResolutionWidth = 512;
    globalCurrentSamplingSteps = 20;
    globalCurrentSamplingMethod = 'DPM++ 2M';
    globalCurrentCfgScale = 3.5;
  }
}

// Selected checkpoint name
late String globalCurrentCheckpointName;

// Selected resolution
late double globalCurrentResolutionHeight;
late double globalCurrentResolutionWidth;

// Selected checkpoint sampling steps
late double globalCurrentSamplingSteps;

// Selected checkpoint sampling method
late String globalCurrentSamplingMethod;

// Selected checkpoint cfg scale
late double globalCurrentCfgScale;

// ===== Generation Variables ===== //

late double globalDenoiseStrength;
late int globalMaskBlur;
late String globalMaskFill;
late int globalBatchSize;
late String globalNegativePrompt;

Future<void> saveDenoiseStrength() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('denoiseStrength', globalDenoiseStrength);
}

Future<void> saveMaskBlur() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('maskBlur', globalMaskBlur);
}

Future<void> saveMaskFill() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('maskFill', globalMaskFill);
}

Future<void> saveBatchSize() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('batchSize', globalBatchSize);
}

Future<void> saveNegativePrompt() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('negativePrompt', globalNegativePrompt);
}

Future<void> loadGenerationSettings() async {
  final prefs = await SharedPreferences.getInstance();
  globalDenoiseStrength = prefs.getDouble('denoiseStrength') ?? 0.5;
  globalMaskBlur = prefs.getInt('maskBlur') ?? 8;
  globalMaskFill = prefs.getString('maskFill') ?? 'fill';
  globalBatchSize = prefs.getInt('batchSize') ?? 2;
  globalNegativePrompt = prefs.getString('negativePrompt') ?? '';
}

// ===== Checkpoint Testing Variables ===== //

ValueNotifier<bool> globalIsCheckpointTesting = ValueNotifier<bool>(false);
ValueNotifier<String?> globalCurrentTestingCheckpoint = ValueNotifier<String?>(null);
ValueNotifier<int> globalCurrentCheckpointTestIndex = ValueNotifier<int>(0);
ValueNotifier<int> globalTotalCheckpointsToTest = ValueNotifier<int>(0);
ValueNotifier<bool> globalIsChangingCheckpoint = ValueNotifier<bool>(false);

// ===== Inpaint Variables ===== //

// Current inpaint image
final ValueNotifier<String?> globalImageToEdit = ValueNotifier(null);

// Current inpaint prompt
String globalInpaintPrompt = '';

// Inpaint prompt history
Set<String> globalInpaintHistory = {};

Future<void> saveInpaintHistory() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('inpaintHistory', globalInpaintHistory.toList());
}

Future<void> loadInpaintHistory() async {
  final prefs = await SharedPreferences.getInstance();
  globalInpaintHistory = Set<String>.from(
    prefs.getStringList('inpaintHistory') ?? [].toSet(),
  );
}

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
