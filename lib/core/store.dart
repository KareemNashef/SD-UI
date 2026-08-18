// ==================== Store ==================== //
//
// The app's one state primitive.
//
// The old code split its state arbitrarily: about fifteen values were
// `ValueNotifier`s the UI could rebuild from, and twenty more were plain
// mutable globals it could not - so those twenty were kept on screen by
// scattering manual `setState` calls and, in the worst case, remounting
// whole subtrees. A Store makes that distinction impossible: every piece of
// app state is observable, and the only way to change it is to emit a new
// immutable snapshot.
//
// It deliberately implements [ValueListenable] so it drops straight into
// `ValueListenableBuilder` and `ListenableBuilder` with no adapter and no
// third-party state package.

import 'package:flutter/foundation.dart';

/// Holds one immutable state value of type [S] and notifies on change.
///
/// Subclasses expose intent-named methods (`setPrompt`, `markConnected`)
/// and call [emit] with a new snapshot - never mutate [state] in place.
abstract class Store<S> extends ChangeNotifier implements ValueListenable<S> {
  S _state;

  Store(S initial) : _state = initial;

  /// The current snapshot.
  S get state => _state;

  /// [ValueListenable] conformance, so `ValueListenableBuilder` works
  /// directly against a Store.
  @override
  S get value => _state;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Publishes a new snapshot. No-ops when the value is unchanged, so
  /// stores can emit freely without causing redundant rebuilds.
  @protected
  void emit(S next) {
    if (_disposed) return;
    if (identical(_state, next) || _state == next) return;
    _state = next;
    notifyListeners();
  }

  /// Derives the next snapshot from the current one.
  @protected
  void update(S Function(S current) transform) => emit(transform(_state));

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  String toString() => '$runtimeType($_state)';
}

/// A store whose state is a single value - for genuinely scalar concerns
/// where a dedicated state class would be ceremony (a flag, a selected id).
class ValueStore<T> extends Store<T> {
  ValueStore(super.initial);

  /// Replaces the value.
  void set(T next) => emit(next);

  /// Derives the next value from the current one.
  void mutate(T Function(T current) transform) => update(transform);
}

/// Watches several [Listenable]s and reports when any of them changes.
///
/// Lets a screen depend on a couple of stores without nesting builders, and
/// lets a store derive from others without hand-wiring listeners.
class StoreGroup extends ChangeNotifier {
  final List<Listenable> _sources;

  StoreGroup(this._sources) {
    for (final source in _sources) {
      source.addListener(notifyListeners);
    }
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
