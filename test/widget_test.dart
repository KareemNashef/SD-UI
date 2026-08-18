// Smoke test: the app must boot without throwing, and it must default to
// Forge Neo as the active backend on a fresh install with no saved
// preference.
//
// The UI is being rebuilt from scratch, so this deliberately asserts only
// on boot-safety and logic-layer state - never on any particular widget -
// so it keeps guarding the app while the interface is replaced.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sd_companion/logic/backend/backend_kind.dart';
import 'package:sd_companion/logic/globals.dart';
import 'package:sd_companion/main.dart';

void main() {
  testWidgets('App boots without throwing and defaults to Forge Neo', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ApertureApp());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(globalActiveBackendKind.value, BackendKind.forge);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
