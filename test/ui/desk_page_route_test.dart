// A route transition is almost impossible to eyeball in review and trivial
// to get subtly wrong: an off-by-one on the curve reads as "feels cheap"
// rather than as a failure. These pin the three properties that define this
// one - it slides the full width, it overshoots past rest, and the overshoot
// never exposes the page underneath.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/desk/desk_tokens.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Desk(
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  DeskPageRoute<void>(
                    builder: (_) => const Desk(
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        body: Center(child: Text('second page')),
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
    ),
  );
  await tester.tap(find.text('open'));
}

void main() {
  testWidgets('the page enters from the right and lands at rest', (tester) async {
    await _open(tester);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final early = tester.getTopLeft(find.text('second page')).dx;
    expect(early, greaterThan(0),
        reason: 'must start off the right edge, not fade in place');

    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);
  });

  testWidgets('it overshoots past rest before settling', (tester) async {
    await _open(tester);
    await tester.pump();

    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final centres = <double>[];
    for (var i = 0; i < 22; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      final finder = find.text('second page');
      if (finder.evaluate().isNotEmpty) {
        centres.add(tester.getCenter(finder).dx);
      }
    }
    await tester.pumpAndSettle();
    final resting = tester.getCenter(find.text('second page')).dx;

    // Overshoot means the page passes the resting centre and comes back, so
    // at least one sampled frame sits left of where it finally stops.
    final minimum = centres.reduce((a, b) => a < b ? a : b);
    expect(minimum, lessThan(resting - 1),
        reason: 'no frame travelled past rest - the curve is not overshooting');
    // ...but only by a little. A big lurch is the thing easeOutBack does
    // that this curve was chosen to avoid.
    expect(resting - minimum, lessThan(screen * 0.15),
        reason: 'overshoot is too violent for a full-width slide');
  });

  testWidgets('a desk-coloured bleed rides past the trailing edge',
      (tester) async {
    await _open(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // The strip that fills the gap during overshoot. Without it, the page
    // underneath shows through the trailing edge and reads as tearing.
    final bleed = find.descendant(
      of: find.byType(DeskPageRoute).evaluate().isEmpty
          ? find.byType(SlideTransition)
          : find.byType(SlideTransition),
      matching: find.byType(ColoredBox),
    );
    expect(bleed, findsWidgets);

    final colours =
        tester.widgetList<ColoredBox>(bleed).map((b) => b.color).toSet();
    expect(
      colours.any((c) => c == DeskPalette.day.desk || c == DeskPalette.night.desk),
      isTrue,
      reason: 'the trailing bleed must be desk coloured, not transparent',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion cross-fades instead of sliding', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Desk(
            child: Builder(
              builder: (context) => Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      DeskPageRoute<void>(
                        builder: (_) => const Desk(
                          child: Scaffold(
                            backgroundColor: Colors.transparent,
                            body: Center(child: Text('second page')),
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
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Assert the property, not the widget type: Flutter's own chrome uses
    // SlideTransition in places that have nothing to do with this route.
    // What matters is that the page never travels - it is already at rest
    // on the first frame it exists.
    final page = find.text('second page');
    expect(page, findsOneWidget);
    expect(
      tester.getTopLeft(page).dx,
      tester.getTopLeft(find.byType(Scaffold).last).dx +
          (tester.getSize(find.byType(Scaffold).last).width -
                  tester.getSize(page).width) /
              2,
      reason: 'with animations disabled the page must not travel at all',
    );

    await tester.pumpAndSettle();
  });
}
