// ==================== Library Store ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/store.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';

/// Every image this session has produced or pulled back from the server.
///
/// Replaces `globalResultImages` plus the selection bookkeeping that used to
/// live inside the results widget's State - which meant selection was lost
/// whenever that widget rebuilt, and the "which image is showing" question
/// had two possible answers depending on who you asked.
@immutable
class LibraryState {
  /// Newest first. The UI never has to reverse this.
  final List<GeneratedImage> images;

  /// Which image the Stage is showing.
  final String? selectedId;

  const LibraryState({this.images = const [], this.selectedId});

  bool get isEmpty => images.isEmpty;
  int get count => images.length;

  GeneratedImage? get selected {
    if (selectedId == null) return null;
    for (final image in images) {
      if (image.id == selectedId) return image;
    }
    return null;
  }

  LibraryState copyWith({
    List<GeneratedImage>? images,
    String? selectedId,
    bool clearSelection = false,
  }) =>
      LibraryState(
        images: images ?? this.images,
        selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
      );

  @override
  bool operator ==(Object other) =>
      other is LibraryState &&
      listEquals(other.images, images) &&
      other.selectedId == selectedId;

  @override
  int get hashCode => Object.hash(Object.hashAll(images), selectedId);
}

class LibraryStore extends Store<LibraryState> {
  LibraryStore([LibraryState? initial]) : super(initial ?? const LibraryState());

  List<GeneratedImage> get images => state.images;
  GeneratedImage? get selected => state.selected;

  /// Adds new images and selects the newest, which is almost always what the
  /// user wants to look at right after a run finishes.
  void add(List<GeneratedImage> incoming) {
    if (incoming.isEmpty) return;
    emit(state.copyWith(
      images: [...incoming, ...state.images],
      selectedId: incoming.first.id,
    ));
  }

  void select(String id) => emit(state.copyWith(selectedId: id));

  /// Removes an image, moving the selection to a sensible neighbour rather
  /// than leaving the Stage blank.
  void remove(String id) {
    final index = state.images.indexWhere((i) => i.id == id);
    if (index == -1) return;

    final next = [...state.images]..removeAt(index);
    if (next.isEmpty) {
      emit(const LibraryState());
      return;
    }

    var selectedId = state.selectedId;
    if (selectedId == id) {
      // Prefer the one that slid into this slot; fall back to the previous.
      selectedId = next[index < next.length ? index : next.length - 1].id;
    }
    emit(LibraryState(images: next, selectedId: selectedId));
  }

  void clear() => emit(const LibraryState());
}
