// ==================== Checkpoint Organizer ==================== //

// Local imports - Logic
import 'package:sd_companion/logic/globals.dart';

// Checkpoint Organizer Implementation

/// Groups checkpoints by their base model
Map<String, List<String>> groupCheckpointsByBaseModel() {
  final Map<String, List<String>> grouped = {};
  final sortedKeys = globalCheckpointDataMap.keys.toList()..sort();

  for (var key in sortedKeys) {
    final data = globalCheckpointDataMap[key];
    final base = (data?.baseModel != null && data!.baseModel.isNotEmpty)
        ? data.baseModel
        : 'Other';

    if (!grouped.containsKey(base)) {
      grouped[base] = [];
    }
    grouped[base]!.add(key);
  }

  return grouped;
}

/// Gets sorted list of base model keys
List<String> getSortedBaseModelKeys() {
  final grouped = groupCheckpointsByBaseModel();
  return grouped.keys.toList()..sort();
}
