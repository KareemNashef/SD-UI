// Smoke test: the app must boot without throwing, and default to Forge Neo
// on a fresh install.
//
// It asserts on logic-layer state rather than on any particular widget, so
// it keeps guarding the app while the interface is rebuilt screen by screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/main.dart';
import 'package:sd_companion/runtime/aperture_runtime.dart';

void main() {
  testWidgets('App boots without throwing and defaults to Forge Neo', (
    WidgetTester tester,
  ) async {
    final runtime = ApertureRuntime.forTesting();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(ApertureApp(runtime: runtime));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(runtime.engine.active, EngineKind.forge);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('Runtime is reachable from the widget tree via RuntimeScope', (
    WidgetTester tester,
  ) async {
    final runtime = ApertureRuntime.forTesting();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(ApertureApp(runtime: runtime));
    await tester.pump(const Duration(milliseconds: 100));

    // The dev harness reads the runtime through the scope; if the wiring were
    // wrong this would have thrown during the pump above.
    expect(tester.takeException(), isNull);
  });
}
