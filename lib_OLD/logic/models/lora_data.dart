// ==================== Lora Data ==================== //

// Lora Data Model Implementation

class LoraData {
  // ===== Class Variables ===== //
  String name;
  String displayName;
  Set<String> trainedWords;
  String thumbnailUrl;
  String baseModel;
  double loraStrength = 1.0;

  // ===== Constructor ===== //
  LoraData({
    required this.name,
    required this.displayName,
    required this.trainedWords,
    required this.thumbnailUrl,
    required this.baseModel,
    this.loraStrength = 1.0,
  });

  // ===== Class Methods ===== //

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'trainedWords': trainedWords.toList(),
    'thumbnailUrl': thumbnailUrl,
    'baseModel': baseModel,
    'loraStrength': loraStrength,
  };

  factory LoraData.fromJson(Map<String, dynamic> json) => LoraData(
    name: json['name'],
    displayName: json['displayName'],
    trainedWords: Set<String>.from(json['trainedWords']),
    thumbnailUrl: json['thumbnailUrl'],
    baseModel: json['baseModel'],
    loraStrength: (json['loraStrength'] as num?)?.toDouble() ?? 1.0,
  );
}
