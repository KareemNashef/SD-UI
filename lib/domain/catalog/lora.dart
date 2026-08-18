// ==================== LoRA ==================== //

import 'package:flutter/foundation.dart';

/// A LoRA available on a Forge server.
///
/// Selection state (weight, chosen tags) deliberately does *not* live here.
/// A LoRA is a fact about the server; what the user picked is session state
/// and belongs in CatalogStore. Keeping them apart means refreshing the
/// inventory can't silently wipe the user's selections.
@immutable
class Lora {
  final String name;

  /// Display name, when the server reports one different from [name].
  final String? alias;

  /// Trigger words this LoRA was trained with.
  final List<String> tags;

  /// Base model it was trained against, used to warn on mismatch.
  final String? baseModel;

  final String? previewUrl;

  const Lora({
    required this.name,
    this.alias,
    this.tags = const [],
    this.baseModel,
    this.previewUrl,
  });

  String get label => alias?.isNotEmpty == true ? alias! : name;

  Map<String, dynamic> toJson() => {
        'name': name,
        'alias': alias,
        'tags': tags,
        'baseModel': baseModel,
        'previewUrl': previewUrl,
      };

  factory Lora.fromJson(Map<String, dynamic> json) => Lora(
        name: json['name'] as String,
        alias: json['alias'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        baseModel: json['baseModel'] as String?,
        previewUrl: json['previewUrl'] as String?,
      );

  @override
  bool operator ==(Object other) => other is Lora && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
