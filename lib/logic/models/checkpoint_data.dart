// ==================== Checkpoint Data ==================== //

// Checkpoint Data Model Implementation

enum Img2ImgMode { inpaint, fullImage }

class CheckpointData {
  // ===== Class Variables ===== //
  String title;
  String imageURL;
  int samplingSteps;
  String samplingMethod;
  double cfgScale;
  double denoisingStrength;
  int resolutionHeight;
  int resolutionWidth;
  String baseModel = "SD 1.5";
  String scheduler;
  List<String> forgeAdditionalModules;
  Img2ImgMode img2imgMode;

  // ===== Constructor ===== //
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
    this.scheduler = "Automatic",
    List<String> forgeAdditionalModules = const [],
    this.img2imgMode = Img2ImgMode.inpaint,
  }) : forgeAdditionalModules = List<String>.from(forgeAdditionalModules);

  // ===== Class Methods ===== //

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
    'scheduler': scheduler,
    'forgeAdditionalModules': forgeAdditionalModules,
    'img2imgMode': img2imgMode.name,
  };

  factory CheckpointData.fromJson(Map<String, dynamic> json) {
    final rawModules = json['forgeAdditionalModules'];
    final savedMode = json['img2imgMode'] as String?;

    return CheckpointData(
      title: json['Title'] ?? '',
      imageURL: json['imageURL'] ?? '',
      samplingSteps: (json['samplingSteps'] as num).toInt(),
      samplingMethod: json['samplingMethod'],
      cfgScale: (json['cfgScale'] as num).toDouble(),
      denoisingStrength: (json['denoisingStrength'] as num? ?? 0.95).toDouble(),
      resolutionHeight: (json['resolutionHeight'] ?? 512 as num).toInt(),
      resolutionWidth: (json['resolutionWidth'] ?? 512 as num).toInt(),
      baseModel: json['baseModel'] ?? "SD 1.5",
      scheduler: json['scheduler'] ?? "Automatic",
      forgeAdditionalModules: rawModules is List
          ? rawModules.map((module) => module.toString()).toList()
          : const [],
      img2imgMode: Img2ImgMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => Img2ImgMode.inpaint,
      ),
    );
  }
}
