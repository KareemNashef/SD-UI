// Covers the Store primitive every piece of app state is built on.
//
// The property that matters most here is the equality guard: without it,
// every emit would rebuild every listening widget, which is what makes a
// naive ValueNotifier-based app janky. The old code avoided the problem by
// not making most state observable at all.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/core/store.dart';

@immutable
class _Counter {
  final int count;
  final String label;
  const _Counter({this.count = 0, this.label = ''});

  _Counter copyWith({int? count, String? label}) =>
      _Counter(count: count ?? this.count, label: label ?? this.label);

  @override
  bool operator ==(Object other) =>
      other is _Counter && other.count == count && other.label == label;

  @override
  int get hashCode => Object.hash(count, label);
}

class _CounterStore extends Store<_Counter> {
  _CounterStore() : super(const _Counter());

  void increment() => update((s) => s.copyWith(count: s.count + 1));
  void setLabel(String label) => update((s) => s.copyWith(label: label));
  void replaceWithIdentical() => emit(state);
}

void main() {
  group('Store', () {
    test('starts at its initial state', () {
      final store = _CounterStore();
      expect(store.state.count, 0);
      addTearDown(store.dispose);
    });

    test('notifies listeners when state actually changes', () {
      final store = _CounterStore();
      addTearDown(store.dispose);

      var notifications = 0;
      store.addListener(() => notifications++);

      store.increment();
      store.increment();

      expect(store.state.count, 2);
      expect(notifications, 2);
    });

    test('does NOT notify when the new state equals the old one', () {
      final store = _CounterStore();
      addTearDown(store.dispose);

      var notifications = 0;
      store.addListener(() => notifications++);

      store.replaceWithIdentical();
      store.setLabel(''); // same value it already had

      expect(notifications, 0,
          reason: 'equality-guarded emits are what stop redundant rebuilds');
    });

    test('exposes state through ValueListenable, so it drops into builders', () {
      final store = _CounterStore();
      addTearDown(store.dispose);

      final ValueListenable<_Counter> listenable = store;
      expect(listenable.value.count, 0);

      store.increment();
      expect(listenable.value.count, 1);
      expect(listenable.value, same(store.state));
    });

    test('ignores emits after disposal instead of throwing', () {
      final store = _CounterStore();
      store.dispose();

      expect(store.isDisposed, isTrue);
      expect(() => store.increment(), returnsNormally);
      expect(store.state.count, 0);
    });
  });

  group('ValueStore', () {
    test('sets and mutates a scalar', () {
      final store = ValueStore<int>(1);
      addTearDown(store.dispose);

      store.set(5);
      expect(store.state, 5);

      store.mutate((v) => v * 2);
      expect(store.state, 10);
    });

    test('is equality-guarded like any other store', () {
      final store = ValueStore<int>(1);
      addTearDown(store.dispose);

      var notifications = 0;
      store.addListener(() => notifications++);

      store.set(1);
      expect(notifications, 0);

      store.set(2);
      expect(notifications, 1);
    });
  });

  group('StoreGroup', () {
    test('fires when any watched store changes', () {
      final a = ValueStore<int>(0);
      final b = ValueStore<String>('');
      final group = StoreGroup([a, b]);
      addTearDown(() {
        group.dispose();
        a.dispose();
        b.dispose();
      });

      var notifications = 0;
      group.addListener(() => notifications++);

      a.set(1);
      b.set('x');

      expect(notifications, 2);
    });

    test('detaches from its sources on dispose', () {
      final a = ValueStore<int>(0);
      final group = StoreGroup([a]);

      var notifications = 0;
      group.addListener(() => notifications++);
      group.dispose();

      a.set(99);
      expect(notifications, 0);
      a.dispose();
    });
  });
}
