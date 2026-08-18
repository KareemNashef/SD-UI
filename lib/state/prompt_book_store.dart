// ==================== Prompt Book Store ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/store.dart';

/// Prompts the user has run before, and the ones they starred.
///
/// Replaces `globalInpaintHistory` and `globalFavoritePrompts` - two bare
/// `Set<String>`s that any file could mutate, with persistence triggered by
/// whoever happened to remember to call `saveInpaintHistory()` afterwards.
/// Here, every mutation goes through a method, and [onChanged] fires once so
/// the owner can persist without every call site knowing about storage.
@immutable
class PromptBookState {
  /// Most recently used first.
  final List<String> history;

  final Set<String> favourites;

  const PromptBookState({this.history = const [], this.favourites = const {}});

  bool isFavourite(String prompt) => favourites.contains(prompt);

  /// The individual comma-separated fragments across all history, ranked by
  /// how often they appear. This is what powers prompt composition.
  List<PromptFragment> get fragments {
    final counts = <String, int>{};
    final display = <String, String>{};

    for (final prompt in history) {
      for (final raw in prompt.split(',')) {
        final text = raw.trim();
        if (text.isEmpty) continue;
        final key = text.toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
        display.putIfAbsent(key, () => text);
      }
    }

    final result = counts.entries
        .map((e) => PromptFragment(text: display[e.key]!, uses: e.value))
        .toList()
      ..sort((a, b) => b.uses.compareTo(a.uses));
    return result;
  }

  PromptBookState copyWith({List<String>? history, Set<String>? favourites}) =>
      PromptBookState(
        history: history ?? this.history,
        favourites: favourites ?? this.favourites,
      );

  @override
  bool operator ==(Object other) =>
      other is PromptBookState &&
      listEquals(other.history, history) &&
      setEquals(other.favourites, favourites);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(history), Object.hashAll(favourites));
}

@immutable
class PromptFragment {
  final String text;
  final int uses;
  const PromptFragment({required this.text, required this.uses});
}

class PromptBookStore extends Store<PromptBookState> {
  /// How many prompts to keep. The old code kept every prompt ever typed in
  /// an unbounded Set, which grew without limit and made the history sheet
  /// slower the longer the app was used.
  static const int maxHistory = 300;

  /// Fired after any change, so the owner can persist. Keeps storage out of
  /// this store entirely.
  final VoidCallback? onChanged;

  PromptBookStore({PromptBookState? initial, this.onChanged})
      : super(initial ?? const PromptBookState());

  void _commit(PromptBookState next) {
    emit(next);
    onChanged?.call();
  }

  /// Records a prompt as used. Moves it to the front if already present, so
  /// history is genuinely most-recent-first rather than insertion-ordered.
  void record(String prompt) {
    final text = prompt.trim();
    if (text.isEmpty) return;

    final next = [text, ...state.history.where((p) => p != text)];
    if (next.length > maxHistory) next.removeRange(maxHistory, next.length);
    _commit(state.copyWith(history: next));
  }

  void toggleFavourite(String prompt) {
    final next = {...state.favourites};
    if (!next.remove(prompt)) next.add(prompt);
    _commit(state.copyWith(favourites: next));
  }

  void forget(String prompt) {
    _commit(state.copyWith(
      history: state.history.where((p) => p != prompt).toList(),
      favourites: {...state.favourites}..remove(prompt),
    ));
  }

  void forgetAll(Iterable<String> prompts) {
    final drop = prompts.toSet();
    _commit(state.copyWith(
      history: state.history.where((p) => !drop.contains(p)).toList(),
      favourites: {...state.favourites}..removeAll(drop),
    ));
  }

  /// Replaces everything, without firing [onChanged] - used when loading
  /// from storage, where persisting straight back would be pointless.
  void hydrate(PromptBookState loaded) => emit(loaded);
}
