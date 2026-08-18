// ==================== Catalog Store ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/store.dart';
import 'package:sd_companion/domain/catalog/checkpoint.dart';
import 'package:sd_companion/domain/catalog/lora.dart';

/// What the connected engine has installed: checkpoints and LoRAs.
///
/// Replaces `globalCheckpointDataMap`, `globalCurrentCheckpointName`,
/// `globalLoraDataMap`, `globalSelectedLoras` and `globalSelectedLoraTags` -
/// five globals that had to agree with each other, with nothing enforcing
/// it. Selecting a LoRA that wasn't in the map, or a checkpoint name with no
/// matching data, were both reachable states.
@immutable
class CatalogState {
  final List<Checkpoint> checkpoints;

  /// Name of the loaded checkpoint. Empty when none is selected.
  final String activeCheckpoint;

  final List<Lora> loras;

  /// Selected LoRAs and their weights, keyed by LoRA name.
  final Map<String, double> loraWeights;

  /// Selected trigger tags per LoRA.
  final Map<String, Set<String>> loraTags;

  final bool isLoading;

  const CatalogState({
    this.checkpoints = const [],
    this.activeCheckpoint = '',
    this.loras = const [],
    this.loraWeights = const {},
    this.loraTags = const {},
    this.isLoading = false,
  });

  Checkpoint? get active {
    for (final c in checkpoints) {
      if (c.name == activeCheckpoint) return c;
    }
    return null;
  }

  /// Checkpoints grouped by base model, for a sectioned picker.
  Map<String, List<Checkpoint>> get byBaseModel {
    final groups = <String, List<Checkpoint>>{};
    for (final c in checkpoints) {
      groups.putIfAbsent(c.baseModel ?? 'Other', () => []).add(c);
    }
    return groups;
  }

  /// LoRAs actually contributing to the prompt (weight above zero).
  Iterable<MapEntry<String, double>> get activeLoras =>
      loraWeights.entries.where((e) => e.value > 0);

  CatalogState copyWith({
    List<Checkpoint>? checkpoints,
    String? activeCheckpoint,
    List<Lora>? loras,
    Map<String, double>? loraWeights,
    Map<String, Set<String>>? loraTags,
    bool? isLoading,
  }) =>
      CatalogState(
        checkpoints: checkpoints ?? this.checkpoints,
        activeCheckpoint: activeCheckpoint ?? this.activeCheckpoint,
        loras: loras ?? this.loras,
        loraWeights: loraWeights ?? this.loraWeights,
        loraTags: loraTags ?? this.loraTags,
        isLoading: isLoading ?? this.isLoading,
      );

  // Every field must appear here. Store.emit is equality-guarded, so a field
  // omitted from == is a field whose changes get silently swallowed - which
  // is exactly what happened to loraTags before a test caught it.
  @override
  bool operator ==(Object other) =>
      other is CatalogState &&
      listEquals(other.checkpoints, checkpoints) &&
      other.activeCheckpoint == activeCheckpoint &&
      listEquals(other.loras, loras) &&
      mapEquals(other.loraWeights, loraWeights) &&
      _tagsEqual(other.loraTags, loraTags) &&
      other.isLoading == isLoading;

  static bool _tagsEqual(
      Map<String, Set<String>> a, Map<String, Set<String>> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !setEquals(entry.value, other)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(checkpoints),
        activeCheckpoint,
        Object.hashAll(loras),
        Object.hashAll(loraWeights.keys),
        Object.hashAll(loraTags.keys),
        isLoading,
      );
}

class CatalogStore extends Store<CatalogState> {
  CatalogStore([CatalogState? initial]) : super(initial ?? const CatalogState());

  void setLoading(bool value) => update((s) => s.copyWith(isLoading: value));

  void setCheckpoints(List<Checkpoint> checkpoints) => update((s) {
        // If the previously-active checkpoint is gone, fall back to the first
        // available rather than leaving a dangling name pointing at nothing.
        final stillThere = checkpoints.any((c) => c.name == s.activeCheckpoint);
        return s.copyWith(
          checkpoints: checkpoints,
          activeCheckpoint: stillThere
              ? s.activeCheckpoint
              : (checkpoints.isEmpty ? '' : checkpoints.first.name),
          isLoading: false,
        );
      });

  void selectCheckpoint(String name) =>
      update((s) => s.copyWith(activeCheckpoint: name));

  /// Replaces a checkpoint's stored metadata (preview image, base model, and
  /// its remembered default sampling params).
  void updateCheckpoint(Checkpoint updated) => update((s) => s.copyWith(
        checkpoints: [
          for (final c in s.checkpoints) c.name == updated.name ? updated : c,
        ],
      ));

  void setLoras(List<Lora> loras) => update((s) => s.copyWith(loras: loras));

  void setLoraWeight(String name, double weight) => update((s) {
        final weights = {...s.loraWeights};
        if (weight <= 0) {
          weights.remove(name);
        } else {
          weights[name] = weight;
        }
        return s.copyWith(loraWeights: weights);
      });

  void setLoraTags(String name, Set<String> tags) => update((s) {
        final tagMap = {...s.loraTags};
        if (tags.isEmpty) {
          tagMap.remove(name);
        } else {
          tagMap[name] = tags;
        }
        return s.copyWith(loraTags: tagMap);
      });

  /// Clears LoRA selections. Called when the base model changes, since LoRAs
  /// are trained against a specific base and carrying them across is wrong.
  void clearLoraSelection() =>
      update((s) => s.copyWith(loraWeights: const {}, loraTags: const {}));

  /// Compiles the selected LoRAs into the `<lora:name:weight>` fragment
  /// Forge expects, followed by any chosen trigger tags.
  String buildPromptFragment() {
    final parts = <String>[];
    for (final entry in state.activeLoras) {
      parts.add('<lora:${entry.key}:${entry.value.toStringAsFixed(2)}>');
      final tags = state.loraTags[entry.key];
      if (tags != null && tags.isNotEmpty) parts.addAll(tags);
    }
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }
}
