// The prompt book's failure mode is performance, not correctness: with 300
// paragraph-length prompts it still rendered the right thing, just far too
// slowly. These pin the two structural properties that keep it fast, since
// neither is visible in a screenshot.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/state/prompt_book_store.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/stage/prompt_book.dart';

/// A history of long prompts, like a real one after a few weeks of use.
PromptBookStore _bigStore({int count = 300}) {
  final store = PromptBookStore();
  store.hydrate(PromptBookState(
    history: [
      for (var i = 0; i < count; i++)
        'prompt $i, ${'a very long descriptive clause ' * 12}, tag$i',
    ],
    favourites: const {},
  ));
  return store;
}

Future<void> _pump(WidgetTester tester, PromptBookStore store,
    {List<String> used = const []}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Desk(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SingleChildScrollView(
            child: PromptBookBody(
              store: store,
              onUse: used.add,
              onAppend: used.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('only the visible rows are built, not all 300', (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = _bigStore();
    addTearDown(store.dispose);
    await _pump(tester, store);

    // A lazy, bounded list builds a screenful. An eager Column would build
    // every entry - which is exactly what made this crawl.
    final rows = find.byType(GestureDetector, skipOffstage: true);
    expect(rows.evaluate().length, lessThan(60),
        reason: 'the list must be lazy; building all 300 rows is the bug');
  });

  testWidgets('filtering narrows the list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = PromptBookStore();
    addTearDown(store.dispose);
    store.hydrate(const PromptBookState(
      history: ['a red barn at dusk', 'a blue whale', 'a red car'],
    ));
    await _pump(tester, store);

    expect(find.textContaining('whale'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'red');
    await tester.pump();

    expect(find.textContaining('whale'), findsNothing);
    expect(find.textContaining('red barn'), findsOneWidget);
    expect(find.textContaining('red car'), findsOneWidget);
  });

  testWidgets('an empty search reports itself rather than looking broken',
      (tester) async {
    final store = PromptBookStore();
    addTearDown(store.dispose);
    store.hydrate(const PromptBookState(history: ['a red barn']));
    await _pump(tester, store);

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pump();

    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });

  testWidgets('tapping a prompt hands it back and closes', (tester) async {
    final used = <String>[];
    final store = PromptBookStore();
    addTearDown(store.dispose);
    store.hydrate(const PromptBookState(history: ['a red barn at dusk']));

    // Pushed as a route so the body's Navigator.pop has something to pop.
    await tester.pumpWidget(
      MaterialApp(
        home: Desk(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: SingleChildScrollView(
                        child: PromptBookBody(
                          store: store,
                          onUse: used.add,
                          onAppend: used.add,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('red barn'));
    await tester.pumpAndSettle();

    expect(used, ['a red barn at dusk']);
  });
}
