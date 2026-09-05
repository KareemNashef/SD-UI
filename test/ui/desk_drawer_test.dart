// DESIGN.md 7.13 specifies "drag down to dismiss, with velocity carried",
// and the 40x4 grip existed for a whole release as pure decoration - it
// looked draggable and wasn't, which is worse than having no grip. Nothing
// caught that because a decorative widget analyses and renders perfectly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';

/// Opens a drawer and returns once it has settled.
Future<void> _openDrawer(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Desk(
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDeskDrawer<void>(
                  context: context,
                  title: 'Test drawer',
                  builder: (_) => const SizedBox(height: 200, child: Text('Body')),
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
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a firm downward drag dismisses the drawer', (tester) async {
    await _openDrawer(tester);
    expect(find.text('Test drawer'), findsOneWidget);

    // Drag from the grip/title area, well past the dismiss threshold.
    await tester.drag(find.text('Test drawer'), const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(find.text('Test drawer'), findsNothing,
        reason: 'dragging the head down must dismiss, per DESIGN.md 7.13');
  });

  testWidgets('a small drag springs back instead of dismissing', (tester) async {
    await _openDrawer(tester);
    expect(find.text('Test drawer'), findsOneWidget);

    // Well under the threshold, and slowly enough not to read as a flick.
    await tester.timedDrag(
      find.text('Test drawer'),
      const Offset(0, 30),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test drawer'), findsOneWidget,
        reason: 'a nudge must not throw the drawer away');
  });

  testWidgets('dragging upward never lifts the drawer off the bottom edge',
      (tester) async {
    await _openDrawer(tester);
    final before = tester.getTopLeft(find.text('Test drawer'));

    await tester.drag(find.text('Test drawer'), const Offset(0, -120));
    await tester.pump();

    final after = tester.getTopLeft(find.text('Test drawer'));
    expect(after.dy, greaterThanOrEqualTo(before.dy - 0.5),
        reason: 'upward travel is clamped; the sheet is anchored to the bottom');
    expect(find.text('Test drawer'), findsOneWidget);
  });

  testWidgets('tapping the scrim still dismisses', (tester) async {
    await _openDrawer(tester);
    expect(find.text('Test drawer'), findsOneWidget);

    // Near the top of the screen, above the sheet itself.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.text('Test drawer'), findsNothing);
  });
}
