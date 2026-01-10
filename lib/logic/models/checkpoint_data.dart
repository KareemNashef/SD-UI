// ==================== Checkpoint Data Model ==================== //

class CheckpointData {
  String title;
  String imageURL;
  int samplingSteps;
  String samplingMethod;
  double cfgScale;
  double denoisingStrength;
  int resolutionHeight;
  int resolutionWidth;
  String baseModel = "SD 1.5";

  CheckpointData({
    required this.title,
    required this.imageURL,
    required this.samplingSteps,
    required this.samplingMethod,
    required this.cfgScale,
    this.denoisingStrength = 0.95,
    required this.resolutionHeight,
    required this.resolutionWidth,
    this.baseModel = "SD 1.5",
  });

  Map<String, dynamic> toJson() => {
    'Title': title,
    'imageURL': imageURL,
    'samplingSteps': samplingSteps,
    'samplingMethod': samplingMethod,
    'cfgScale': cfgScale,
    'denoisingStrength': denoisingStrength,
    'resolutionHeight': resolutionHeight,
    'resolutionWidth': resolutionWidth,
    'baseModel': baseModel,
  };

  factory CheckpointData.fromJson(Map<String, dynamic> json) => CheckpointData(
    title: json['Title'] ?? '',
    imageURL: json['imageURL'] ?? '',
    samplingSteps: (json['samplingSteps'] as num).toInt(),
    samplingMethod: json['samplingMethod'],
    cfgScale: (json['cfgScale'] as num).toDouble(),
    denoisingStrength: (json['denoisingStrength'] as num? ?? 0.95).toDouble(),
    resolutionHeight: (json['resolutionHeight'] ?? 512 as num).toInt(),
    resolutionWidth: (json['resolutionWidth'] ?? 512 as num).toInt(),
    baseModel: json['baseModel'] ?? "SD 1.5",
  );
}
