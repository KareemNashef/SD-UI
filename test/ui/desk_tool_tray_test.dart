// The compare tool is a momentary switch, not a button: it must engage the
// instant the finger lands and release on lift. Routing it through a normal
// tap or a long-press would add a delay that defeats the point of a quick
// A/B comparison, and that delay is invisible in code review.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';

Future<void> _pump(WidgetTester tester, List<DeskTool> tools) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Desk(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(children: [DeskToolTray(tools: tools)]),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a momentary tool engages on press and releases on lift',
      (tester) async {
    final events = <String>[];
    await _pump(tester, [
      DeskTool(
        icon: Icons.compare_rounded,
        name: 'Compare',
        onHoldStart: () => events.add('start'),
        onHoldEnd: () => events.add('end'),
      ),
    ]);

    final icon = find.byIcon(Icons.compare_rounded);
    final gesture = await tester.startGesture(tester.getCenter(icon));
    await tester.pump();

    expect(events, ['start'],
        reason: 'must fire on pointer-down, not after a tap or long-press');

    await gesture.up();
    await tester.pump();
    expect(events, ['start', 'end']);
  });

  testWidgets('a cancelled press still releases, so compare cannot stick',
      (tester) async {
    final events = <String>[];
    await _pump(tester, [
      DeskTool(
        icon: Icons.compare_rounded,
        name: 'Compare',
        onHoldStart: () => events.add('start'),
        onHoldEnd: () => events.add('end'),
      ),
    ]);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.compare_rounded)));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(events, ['start', 'end'],
        reason: 'a cancelled pointer must not leave the stage stuck on input');
  });

  testWidgets('an ordinary tool still fires on tap', (tester) async {
    var taps = 0;
    await _pump(tester, [
      DeskTool(icon: Icons.tune_rounded, name: 'Settings', onTap: () => taps++),
    ]);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('ordinary tools carry a long-press label', (tester) async {
    await _pump(tester, [
      const DeskTool(icon: Icons.crop_rounded, name: 'Crop'),
      const DeskTool(
        icon: Icons.info_outline_rounded,
        name: 'Details',
        hint: 'What made this image',
      ),
    ]);

    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
    expect(tooltips, hasLength(2));
    expect(tooltips.map((t) => t.message),
        containsAll(['Crop', 'What made this image']));
  });

  testWidgets('no tool is highlighted when none is active', (tester) async {
    await _pump(tester, [
      const DeskTool(icon: Icons.crop_rounded, name: 'Crop'),
      const DeskTool(icon: Icons.tune_rounded, name: 'Settings'),
    ]);

    // Every icon should render at the same unselected opacity; a highlighted
    // one would be full-strength paper on clay.
    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons, hasLength(2));
    final colours = icons.map((i) => i.color).toSet();
    expect(colours, hasLength(1),
        reason: 'with no activeIndex, no tool may look armed');
  });
}
