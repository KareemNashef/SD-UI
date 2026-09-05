// Reopening the mask editor used to hand back a blank canvas: the session
// kept only the rendered PNG, which cannot be drawn on, so every visit
// started the mask over. These pin the round trip - the strokes go out with
// the mask and come back sized for whatever canvas the editor gets next.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/domain/drawing/canvas_geometry.dart';
import 'package:sd_companion/domain/drawing/stroke.dart';
import 'package:sd_companion/state/session_store.dart';
import 'package:sd_companion/ui/stage/mask_editor.dart';

Future<ui.Image> _solidImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  return recorder.endRecording().toImage(w, h);
}

class _DirectImageProvider extends ImageProvider<_DirectImageProvider> {
  final ui.Image image;
  const _DirectImageProvider(this.image);

  @override
  Future<_DirectImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DirectImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      _DirectImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}

MaskDraft _draftOf(List<Offset> points, {double width = 60}) => MaskDraft([
      DrawingPath(
        points: [for (final point in points) DrawingPoint(point: point)],
        mode: DrawingMode.draw,
        strokeWidth: width,
      ),
    ]);

/// Pushes the editor, runs [act] on it, and returns what it popped.
Future<MaskResult?> _runEditor(
  WidgetTester tester, {
  required ui.Image image,
  MaskDraft? initial,
  required Future<void> Function(WidgetTester tester) act,
}) async {
  MaskResult? popped;
  var finished = false;

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<MaskResult?>(
              MaterialPageRoute(
                builder: (_) => MaskEditor(
                  image: image,
                  display: _DirectImageProvider(image),
                  initial: initial,
                ),
              ),
            );
            finished = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act(tester);
  await tester.pumpAndSettle();

  // Rendering the mask is real async work (`Picture.toImage`), which the
  // fake-async pump does not drive - so the editor is genuinely still busy
  // at this point unless it took the shortcut of popping straight away.
  if (!finished) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  expect(finished, isTrue, reason: 'the editor never closed');
  return popped;
}

void main() {
  testWidgets('an existing mask reopens with its strokes still there',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final image = await _solidImage(800, 600);
    addTearDown(image.dispose);

    final result = await _runEditor(
      tester,
      image: image,
      initial: _draftOf(const [Offset(200, 200), Offset(600, 400)]),
      // Straight to Done, drawing nothing: everything handed back has to
      // have come from the draft.
      act: (tester) => tester.tap(find.text('Done')),
    );

    expect(result, isNotNull,
        reason: 'closing on a restored mask must not read as a cancel');
    expect(result!.bytes, isNotNull, reason: 'the mask was re-rendered');
    expect(result.draft.paths, hasLength(1));
    expect(result.draft.paths.single.points.map((p) => p.point).toList(),
        const [Offset(200, 200), Offset(600, 400)]);
  });

  testWidgets('clearing a restored mask is a clear, not a cancel',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final image = await _solidImage(800, 600);
    addTearDown(image.dispose);

    final result = await _runEditor(
      tester,
      image: image,
      initial: _draftOf(const [Offset(200, 200), Offset(600, 400)]),
      act: (tester) async {
        // Clear is only enabled when there are strokes to clear, so this
        // also proves the restore reached `_paths` rather than only the
        // painter.
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
      },
    );

    expect(result, isNotNull);
    expect(result!.bytes, isNull, reason: 'the caller should drop the mask');
    expect(result.draft.isEmpty, isTrue);
  });

  testWidgets('opening empty and closing empty is still a cancel',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final image = await _solidImage(800, 600);
    addTearDown(image.dispose);

    final result = await _runEditor(
      tester,
      image: image,
      act: (tester) => tester.tap(find.text('Done')),
    );

    expect(result, isNull,
        reason: 'nothing was painted, so nothing should change');
  });

  test('a draft keeps the same brush size on a different canvas', () {
    const imageSize = Size(800, 600);
    const phone = Size(360, 270);
    const tablet = Size(720, 540);

    final phoneScale =
        maskStrokeScale(imageSize: imageSize, containerSize: phone);
    final tabletScale =
        maskStrokeScale(imageSize: imageSize, containerSize: tablet);

    // 40 logical pixels of brush on the phone is a fixed number of image
    // pixels; reopened on a wider canvas it has to be the same number of
    // image pixels, not the same number of logical ones - otherwise the
    // restored strokes would be visibly fatter or thinner than the mask
    // that was actually generated.
    final draft = MaskDraft.fromCanvas(
      [
        DrawingPath(
          points: [DrawingPoint(point: const Offset(10, 10))],
          mode: DrawingMode.draw,
          strokeWidth: 40,
        ),
      ],
      phoneScale,
    );
    expect(draft.paths.single.strokeWidth, closeTo(40 * phoneScale, 0.001));

    final onTablet = draft.forCanvas(tabletScale);
    expect(onTablet.single.strokeWidth * tabletScale,
        closeTo(40 * phoneScale, 0.001),
        reason: 'same width in image pixels');
    expect(onTablet.single.strokeWidth, isNot(closeTo(40, 0.5)),
        reason: 'and therefore a different width in display pixels');
  });

  test('replacing the mask replaces the strokes behind it', () {
    final session = SessionStore();
    final bytes = Uint8List.fromList([1, 2, 3]);

    session.setMask(bytes, draft: _draftOf(const [Offset(1, 1)]));
    expect(session.state.maskDraft, isNotNull);

    // An outpaint border is a mask with no strokes to reopen. Keeping the
    // previous draft would let the editor reopen strokes belonging to a
    // completely different mask.
    session.setMask(Uint8List.fromList([4, 5, 6]));
    expect(session.state.maskDraft, isNull);

    session.setMask(bytes, draft: _draftOf(const [Offset(1, 1)]));
    session.setMask(null);
    expect(session.state.mask, isNull);
    expect(session.state.maskDraft, isNull);
  });
}
