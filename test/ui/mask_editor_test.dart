// The loupe shipped broken in a way no analyzer or unit test could catch:
// `Positioned.fill` passes *tight* constraints, so the magnified scene was
// squashed to the loupe's own size and then translated off-view by canvas
// coordinates, leaving only the backing colour. It rendered, it just showed
// nothing. These tests exercise the widget tree so that class of failure
// surfaces as a size assertion rather than as a blank square on a phone.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/ui/stage/mask_editor.dart';

Future<ui.Image> _solidImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  return recorder.endRecording().toImage(w, h);
}

/// An ImageProvider that resolves synchronously from a decoded image, so a
/// widget test never waits on real file or network I/O.
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

void main() {
  testWidgets('the loupe magnifies the real canvas, not a collapsed copy',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final image = await _solidImage(800, 600);
    addTearDown(image.dispose);

    await tester.pumpWidget(MaterialApp(
      home: MaskEditor(image: image, display: _DirectImageProvider(image)),
    ));
    await tester.pump();

    // Drag across the canvas to raise the loupe.
    final canvas = find.byType(RawGestureDetector).first;
    final centre = tester.getCenter(canvas);
    final gesture = await tester.startGesture(centre);
    await tester.pump();
    await gesture.moveBy(const Offset(20, 12));
    await tester.pump();

    // Measure what the scene was actually laid out at, not what its widget
    // declares - the bug was purely a constraint one, so the declared width
    // stayed correct while the rendered box collapsed to the loupe.
    final scene = find.byKey(loupeSceneKey);
    expect(scene, findsOneWidget);

    final sceneSize = tester.getSize(scene);

    // The loupe window is 120 logical pixels. A scene laid out at the canvas
    // size is several times that; a scene collapsed by tight constraints is
    // the loupe's own size or smaller, which is the blank-square bug.
    expect(
      sceneSize.width,
      greaterThan(200),
      reason: 'the loupe scene collapsed to ${sceneSize.width}px - it must be '
          'laid out at the canvas size, not the loupe box',
    );
    expect(sceneSize.height, greaterThan(150));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('painting then undoing leaves nothing to clear', (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final image = await _solidImage(400, 400);
    addTearDown(image.dispose);

    await tester.pumpWidget(MaterialApp(
      home: MaskEditor(image: image, display: _DirectImageProvider(image)),
    ));
    await tester.pump();

    Finder buttonByLabel(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(GestureDetector),
        );

    // Clear starts disabled because nothing is painted.
    expect(find.text('Clear'), findsOneWidget);

    final canvas = find.byType(RawGestureDetector).first;
    final centre = tester.getCenter(canvas);
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(30, 30));
    await gesture.up();
    await tester.pump();

    // One stroke exists; undo should take it back off again.
    await tester.tap(buttonByLabel('Undo').first);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
