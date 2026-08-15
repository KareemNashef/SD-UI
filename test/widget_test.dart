// Smoke test: the app must boot into either the offline/connect screen (no
// server reachable in the test sandbox) or straight into the main shell,
// without throwing, and it must default to Forge Neo as the active backend
// on a fresh install with no saved preference.

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

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(globalActiveBackendKind.value, BackendKind.forge);

    // Either the offline/connect screen or the main shell should be
    // showing - never a bare error widget.
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
