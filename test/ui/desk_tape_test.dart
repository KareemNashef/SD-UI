// The tape replaced the ruler for every numeric setting, and it is the one
// control in the app whose behaviour cannot be read off its layout: the
// value follows how *far* the finger travelled, and the step it moves in
// changes depending on how far from the strip that finger is.
//
// So these drive real gestures. The precision switch in particular is the
// kind of thing that works on the first try and then silently stops working
// the day someone swaps the horizontal recogniser for a pan.

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/desk/desk_controls.dart';
import 'package:sd_companion/ui/desk/desk_surface.dart';
import 'package:sd_companion/ui/stage/workflow_settings.dart';

/// Pixels the tape travels per tick, mirrored from `_DeskTapeState`. One
/// tick is one step, whatever the step is currently worth.
const _tickGap = 22.0;

/// A tape wired to a value that actually updates, so a drag accumulates the
/// way it does in the app rather than fighting a frozen widget.
class _Harness extends StatefulWidget {
  final double initial;
  final List<double> steps;
  final double? min;
  final double? max;
  final ValueChanged<double>? onChanged;

  const _Harness({
    super.key,
    required this.initial,
    required this.steps,
    this.min,
    this.max,
    this.onChanged,
  });

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late double _value = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Desk(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DeskTape(
                  label: 'Strength',
                  value: _value,
                  min: widget.min,
                  max: widget.max,
                  steps: widget.steps,
                  format: (v) => trimNumber(v, 2),
                  onChanged: (v) {
                    setState(() => _value = v);
                    widget.onChanged?.call(v);
                  },
                ),
              ),
            ),
          ),
        ),
      );
}

/// Runs one drag over the strip and returns the value it left behind.
///
/// [liftFirst] carries the finger away from the strip before the sideways
/// travel, which is how the finer steps are reached.
Future<double> _drag(
  WidgetTester tester, {
  required double initial,
  required List<double> steps,
  required double travel,
  double? min,
  double? max,
  Offset? liftFirst,
}) async {
  var latest = initial;
  await tester.pumpWidget(_Harness(
    // A fresh state each time: without this a second drag in the same test
    // silently continues from where the first one left off.
    key: UniqueKey(),
    initial: initial,
    steps: steps,
    min: min,
    max: max,
    onChanged: (v) => latest = v,
  ));
  await tester.pumpAndSettle();

  final strip = tester.getCenter(find.descendant(
      of: find.byType(DeskTape),
      matching: find.byType(CompositedTransformTarget)));
  final gesture = await tester.startGesture(strip);
  // Claim the gesture for the horizontal recogniser, then come back to
  // where it started so the slop itself is not counted as travel.
  await gesture.moveBy(const Offset(kTouchSlop + 1.0, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(-kTouchSlop - 1.0, 0));
  await tester.pump();
  if (liftFirst != null) {
    await gesture.moveBy(liftFirst);
    await tester.pump();
  }
  await gesture.moveBy(Offset(travel, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  return latest;
}

/// True when [value] lands exactly on a multiple of [step] - no floating
/// point crumbs, which is what accumulating a drag one frame at a time
/// produces if nothing rounds.
bool _isMultipleOf(double value, double step) =>
    ((value / step) - (value / step).round()).abs() < 1e-9;

void main() {
  group('dragging', () {
    testWidgets('moves the value in whole coarse steps', (tester) async {
      final value = await _drag(tester,
          initial: 1, steps: const [0.5, 0.1, 0.01], travel: -_tickGap * 4);
      expect(value, greaterThan(1));
      expect(_isMultipleOf(value, 0.5), isTrue,
          reason: 'a flat drag must not leave a value between the ticks');
    });

    testWidgets('the tape goes where the finger goes', (tester) async {
      // Dragging right carries the tape right, which brings the numbers to
      // its left onto the line - so the value falls. Driving it the other
      // way round is what read as broken: the marks disagreeing with the
      // hand that is moving them.
      final right = await _drag(tester,
          initial: 0, steps: const [0.5], travel: _tickGap * 4);
      final left = await _drag(tester,
          initial: 0, steps: const [0.5], travel: -_tickGap * 4);
      expect(right, lessThan(0));
      expect(left, greaterThan(0));
      expect(left, closeTo(-right, 0.001),
          reason: 'the same travel either way must be worth the same');
    });

    testWidgets('lifting the finger away switches to a finer step',
        (tester) async {
      // Identical horizontal travel three times over: flat, away, and
      // further away. Same distance, three different resolutions.
      const travel = -_tickGap * 6;
      final coarse = await _drag(tester,
          initial: 1, steps: const [0.5, 0.1, 0.01], travel: travel);
      final fine = await _drag(tester,
          initial: 1,
          steps: const [0.5, 0.1, 0.01],
          liftFirst: const Offset(0, -40),
          travel: travel);
      final finest = await _drag(tester,
          initial: 1,
          steps: const [0.5, 0.1, 0.01],
          liftFirst: const Offset(0, -100),
          travel: travel);

      expect(coarse - 1, greaterThan(fine - 1));
      expect(fine - 1, greaterThan(finest - 1));
      expect(_isMultipleOf(fine, 0.1), isTrue);
      expect(_isMultipleOf(finest, 0.01), isTrue);
      // The ladder is worth having only if the steps are properly apart.
      expect(coarse - 1, greaterThan((fine - 1) * 4));
      expect(fine - 1, greaterThan((finest - 1) * 4));
    });

    testWidgets('the ends hold, even though the tape carries on',
        (tester) async {
      final low = await _drag(tester,
          initial: 0,
          steps: const [0.5],
          min: -1,
          max: 1,
          travel: _tickGap * 20);
      final high = await _drag(tester,
          initial: 0,
          steps: const [0.5],
          min: -1,
          max: 1,
          travel: -_tickGap * 20);
      expect(low, -1);
      expect(high, 1);
    });

    testWidgets('a value is never left with floating-point crumbs',
        (tester) async {
      // Tenths accumulated one frame at a time is exactly where
      // 0.7000000000000001 comes from, and that reaches the workflow file.
      final value = await _drag(tester,
          initial: 0, steps: const [0.1], travel: -_tickGap * 7);
      expect(_isMultipleOf(value, 0.1), isTrue);
      expect(value.toString().split('.').last.length, lessThanOrEqualTo(2));
    });
  });

  testWidgets('the end pads move one coarse step without a drag',
      (tester) async {
    var latest = 4.0;
    await tester.pumpWidget(_Harness(
      key: UniqueKey(),
      initial: 4,
      steps: const [0.5, 0.1],
      onChanged: (v) => latest = v,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(latest, closeTo(3.5, 0.001));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(latest, closeTo(4.0, 0.001));
  });

  testWidgets('a fine adjustment survives the finger coming off',
      (tester) async {
    // The reported bug: nudge to 3, lift into the fine lane, set 3.2, let
    // go - and the readout snapped back to 3 because the *display* was
    // re-rounding a stored value onto the coarse grid.
    await tester.pumpWidget(_Harness(
      key: UniqueKey(),
      initial: 3,
      steps: const [0.5, 0.1],
    ));
    await tester.pumpAndSettle();

    final strip = tester.getCenter(find.descendant(
        of: find.byType(DeskTape),
        matching: find.byType(CompositedTransformTarget)));
    final gesture = await tester.startGesture(strip);
    await gesture.moveBy(const Offset(kTouchSlop + 1.0, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-kTouchSlop - 1.0, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40)); // into the fine lane
    await tester.pump();
    await gesture.moveBy(const Offset(-_tickGap * 2, 0));
    await tester.pump();
    expect(find.text('3.2'), findsWidgets, reason: 'two tenths up from 3');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('3.2'), findsOneWidget,
        reason: 'letting go must not round the value back to the coarse grid');
  });

  testWidgets('the precision lanes are shown, not implied', (tester) async {
    // Whether a finer step is available, and which one is in force, used to
    // be knowable only by trying it. The lanes are drawn above the strip
    // while the finger is down, and light up as it reaches them.
    await tester.pumpWidget(_Harness(
      key: UniqueKey(),
      initial: 1,
      steps: const [0.5, 0.1, 0.01],
    ));
    await tester.pumpAndSettle();
    expect(find.text('±0.1'), findsNothing,
        reason: 'at rest the row is just a setting');

    final strip = tester.getCenter(find.descendant(
        of: find.byType(DeskTape),
        matching: find.byType(CompositedTransformTarget)));
    final gesture = await tester.startGesture(strip);
    await gesture.moveBy(const Offset(kTouchSlop + 1.0, 0));
    await tester.pumpAndSettle();

    expect(find.text('±0.1'), findsOneWidget);
    expect(find.text('±0.01'), findsOneWidget);
    expect(find.text('±0.5'), findsOneWidget,
        reason: 'including the one currently in force');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('±0.1'), findsNothing,
        reason: 'and they go away with the finger');
  });

  testWidgets('the tape scrolls inside a page that scrolls the other way',
      (tester) async {
    // The tape uses a horizontal recogniser precisely so a vertical list can
    // still be scrolled by dragging over it. A pan recogniser here would
    // swallow the scroll.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var value = 4.0;

    await tester.pumpWidget(MaterialApp(
      home: Desk(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 400),
              StatefulBuilder(
                builder: (context, setState) => DeskTape(
                  label: 'Strength',
                  value: value,
                  steps: const [0.5],
                  format: (v) => trimNumber(v, 2),
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(DeskTape), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100),
        reason: 'a vertical drag over the tape must scroll the page');
    expect(value, 4.0, reason: 'and must not move the value');
  });

  group('step ladders', () {
    test('a bounded float gets a coarse step it can cross the range with', () {
      // Guidance: 0-10 in tenths.
      expect(stepLadder(isInt: false, schemaStep: 0.1, span: 10),
          [0.5, 0.1]);
      // Reference boost: 1-15 in hundredths.
      expect(stepLadder(isInt: false, schemaStep: 0.01, span: 14),
          [0.5, 0.1, 0.05]);
      // Denoise: 0-1. Half a point would be a third of the whole range.
      expect(stepLadder(isInt: false, schemaStep: 0.01, span: 1),
          [0.05, 0.01]);
    });

    test('the node its own step is the floor', () {
      expect(stepLadder(isInt: false, schemaStep: 0.1, span: 2).last, 0.1,
          reason: 'a node that says tenths must never be sent hundredths');
      expect(stepLadder(isInt: true, schemaStep: 4, span: 120), [40.0, 4.0]);
    });

    test('an unbounded value still gets a sensible ladder', () {
      expect(stepLadder(isInt: false, schemaStep: 0.01, span: null),
          [0.5, 0.1, 0.05]);
    });

    test('integers do not get fractional steps', () {
      expect(stepLadder(isInt: true, schemaStep: null, span: 9999),
          [10.0, 1.0]);
      expect(stepLadder(isInt: true, schemaStep: null, span: 4), [1.0]);
    });
  });

  test('numbers are trimmed to what they actually say', () {
    expect(trimNumber(8, 2), '8');
    expect(trimNumber(7.5, 2), '7.5');
    expect(trimNumber(0.05, 2), '0.05');
    expect(trimNumber(-0.001, 2), '0', reason: 'never "-0"');
    expect(trimNumber(12, 0), '12');
  });
}
