// ==================== Lora Data Model ==================== //

class LoraData {
  String name;
  String displayName;
  Set<String> trainedWords;
  String thumbnailUrl;
  String baseModel;
  double maxStrength = 1.0;

  LoraData({
    required this.name,
    required this.displayName,
    required this.trainedWords,
    required this.thumbnailUrl,
    required this.baseModel,
    this.maxStrength = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'trainedWords': trainedWords.toList(),
    'thumbnailUrl': thumbnailUrl,
    'baseModel': baseModel,
    'maxStrength': maxStrength,
  };

  factory LoraData.fromJson(Map<String, dynamic> json) => LoraData(
    name: json['name'],
    displayName: json['displayName'],
    trainedWords: Set<String>.from(json['trainedWords']),
    thumbnailUrl: json['thumbnailUrl'],
    baseModel: json['baseModel'],
    maxStrength: (json['maxStrength'] as num?)?.toDouble() ?? 1.0,
  );
}
