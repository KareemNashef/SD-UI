// Typing into anything near the bottom of a drawer meant typing blind.
//
// A Desk drawer is bottom-aligned and sized to its content, so when the
// keyboard came up the sheet did not move and its scroll view did not
// shrink. `EditableText` asks its nearest scrollable to reveal the focused
// field, and that scrollable saw a field already inside its viewport - so
// it scrolled nothing, and the keyboard simply sat on top.
//
// The settings page never had this - its Scaffold resizes and its list
// scrolls the focused field up - which is why the fix is here and not
// there. It is not covered by a second test because, since the tape
// replaced the LoRA strength field, the only text field left on that page
// is the seed, and it sits at the top of its own tab where no keyboard can
// reach it.


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_overlays.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';

/// A phone-shaped screen, and a keyboard tall enough to matter.
const _keyboard = 330.0;

double _screenHeight(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio;

void _raiseKeyboard(WidgetTester tester) {
  tester.view.viewInsets =
      FakeViewPadding(bottom: _keyboard * tester.view.devicePixelRatio);
}

void main() {
  testWidgets('a field at the bottom of a drawer clears the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Desk(
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: TextButton(
                onPressed: () => showDeskDrawer<void>(
                  context: context,
                  title: 'Rename',
                  // Enough above it that the field lands near the bottom of
                  // the sheet, which is where the bug lived.
                  builder: (_) => Column(
                    children: [
                      for (var i = 0; i < 3; i++)
                        const SizedBox(height: 100),
                      DeskField(label: 'Name', controller: controller),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    final keyboardTop = _screenHeight(tester) - _keyboard;
    expect(tester.getRect(field).top, greaterThan(keyboardTop),
        reason: 'the test is pointless unless the field starts under where '
            'the keyboard will be');

    await tester.tap(field);
    await tester.pumpAndSettle();
    _raiseKeyboard(tester);
    await tester.pumpAndSettle();

    expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboardTop),
        reason: 'the sheet must lift and shrink, not sit under the keyboard');
  });
}
