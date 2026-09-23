// The shelf, and staying inside the picture it floats on.
//
// The cards were a Row whose children were slid left by `Transform.translate`
// to overlap into a deck. A transform does not change layout, so the row
// measured wider than it drew - and the scroll view was `Clip.none`, so once
// the shelf scrolled at all the deck painted straight out over the desk on
// both sides of the canvas: prints to the left of the paper, prints past its
// right border.
//
// Two things follow from laying the cards out at real positions instead:
// nothing escapes the box, and the scroll ends where the deck ends rather
// than a hundred points into empty paper.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/desk/desk_surface.dart';

/// Narrow on purpose: eight cards in 260 points is a shelf that must scroll.
const _shelfWidth = 260.0;

Future<void> _pump(WidgetTester tester, int count, {String? selected}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Desk(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: SizedBox(
              width: _shelfWidth,
              child: PrintShelf(
                selectedId: selected,
                entries: [
                  for (var i = 0; i < count; i++) PrintEntry(id: 'print-$i'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _shelf(WidgetTester tester) => tester.getRect(find.byType(PrintShelf));

/// Every card on the shelf, in the order they were laid out - which is *not*
/// the order they are painted in, since the picked one goes last.
List<Rect> _cards(WidgetTester tester) => [
      for (final id in [for (var i = 0; i < 8; i++) 'print-$i'])
        if (find.byKey(ValueKey(id)).evaluate().isNotEmpty)
          tester.getRect(find.byKey(ValueKey(id)))
    ];

void main() {
  testWidgets('the deck never paints outside the shelf', (tester) async {
    await _pump(tester, 8);
    final shelf = _shelf(tester);

    final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView));
    expect(scroll.clipBehavior, Clip.hardEdge,
        reason: 'an unclipped shelf paints its scrolled-away cards over '
            'whatever is beside the canvas');

    // Nothing starts to the left of the shelf's own edge, before a finger
    // has touched it or after.
    expect(_cards(tester).first.left, greaterThanOrEqualTo(shelf.left));

    await tester.drag(find.byType(PrintShelf), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_cards(tester).first.left, greaterThanOrEqualTo(shelf.left - 400),
        reason: 'scrolled-away cards may sit outside the box in layout; '
            'the clip is what stops them being seen there');
  });

  testWidgets('the scroll ends where the deck ends', (tester) async {
    await _pump(tester, 8);
    final shelf = _shelf(tester);

    await tester.drag(find.byType(PrintShelf), const Offset(-1000, 0));
    await tester.pumpAndSettle();

    final last = _cards(tester).last;
    expect(last.right, lessThanOrEqualTo(shelf.right + 1),
        reason: 'scrolled to the end, the last card is inside the shelf');
    expect(last.right, greaterThan(shelf.right - 40),
        reason: 'and it is *at* the end: the overlap used to be drawn but '
            'not measured, so the shelf scrolled a card-and-a-half past the '
            'last print into blank paper');
  });

  testWidgets('the picked card is painted over its neighbours',
      (tester) async {
    await _pump(tester, 8, selected: 'print-3');

    // The cards overlap, so paint order decides which one you can see whole.
    // Laid out in order, a card rising out of the deck came up *behind* the
    // one to its right, which read as the shelf lifting the wrong print.
    final stack = find.descendant(
      of: find.byType(PrintShelf),
      matching: find.byType(Stack),
    );
    final children = tester
        .widgetList<Positioned>(find.descendant(
            of: stack.first, matching: find.byType(Positioned)))
        .toList();
    expect((children.last.key as ValueKey).value, 'print-3');
  });
}
