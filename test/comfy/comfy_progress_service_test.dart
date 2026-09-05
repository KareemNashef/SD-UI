// Drives real ComfyUI WebSocket message payloads through
// ComfyProgressService, which is the layer my previous test skipped
// entirely - it hand-fed RunProgress values straight into the store, so it
// proved only "store -> UI" and never exercised the message decoding where
// the reported "stuck progress bar" actually lived.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/data/engines/comfy/comfy_progress_service.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';

void main() {
  late ComfyProgressService service;
  const promptId = 'prompt-1';

  setUp(() {
    service = ComfyProgressService();
    service.beginTracking(promptId);
  });

  tearDown(() => service.dispose());

  /// Feeds a text frame exactly as ComfyUI sends it. The service's message
  /// handler is private, so this goes through the same JSON shape the socket
  /// delivers rather than calling internals.
  void send(String type, Map<String, dynamic> data) {
    service.handleTextMessage(jsonEncode({'type': type, 'data': data}));
  }

  test('progress events set a fraction from value/max', () {
    send('execution_start', {'prompt_id': promptId});
    send('progress', {'prompt_id': promptId, 'value': 5, 'max': 20});

    expect(service.current.phase, RunPhase.running);
    expect(service.current.fraction, closeTo(0.25, 1e-9));
  });

  test('moving to a new node clears the previous node\'s step counts', () {
    send('executing', {'prompt_id': promptId, 'node': '3'});
    send('progress', {'prompt_id': promptId, 'value': 20, 'max': 20});
    expect(service.current.fraction, 1.0);

    // The sampler finished; ComfyUI moves on to VAE decode, which reports no
    // per-step progress. The bar must fall back to indeterminate rather than
    // sitting at a full, motionless 100% for the rest of the run - which is
    // exactly what the user saw on device.
    send('executing', {'prompt_id': promptId, 'node': '8'});

    expect(service.current.fraction, isNull,
        reason: 'stale step counts leaked into the next node');
    expect(service.current.phase, RunPhase.running);
  });

  test('repeated executing events for the same node keep its progress', () {
    send('executing', {'prompt_id': promptId, 'node': '3'});
    send('progress', {'prompt_id': promptId, 'value': 7, 'max': 20});
    send('executing', {'prompt_id': promptId, 'node': '3'});

    expect(service.current.fraction, closeTo(0.35, 1e-9),
        reason: 'a duplicate event for the same node should not reset it');
  });

  test('a new run does not inherit the previous run\'s progress', () {
    send('executing', {'prompt_id': promptId, 'node': '3'});
    send('progress', {'prompt_id': promptId, 'value': 20, 'max': 20});
    send('executing', {'prompt_id': promptId, 'node': null});
    expect(service.current.phase, RunPhase.completed);

    service.beginTracking('prompt-2');
    expect(service.current.phase, RunPhase.queued);
    expect(service.current.fraction, isNull);
    expect(service.current.queuePosition, isNull);
  });

  test('events for a different prompt id are ignored', () {
    send('progress', {'prompt_id': 'someone-elses-job', 'value': 9, 'max': 10});
    expect(service.current.fraction, isNull);
  });

  group('binary preview frames', () {
    /// ComfyUI type 1: [4B eventType][4B imageType][image bytes].
    Uint8List classicPreview(List<int> image) {
      final out = BytesBuilder();
      final header = ByteData(8)
        ..setUint32(0, 1, Endian.big)
        ..setUint32(4, 1, Endian.big);
      out.add(header.buffer.asUint8List());
      out.add(image);
      return out.toBytes();
    }

    const jpegBody = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];

    test('a classic PREVIEW_IMAGE frame is decoded', () {
      service.handleBinaryMessage(classicPreview(jpegBody));
      expect(service.current.preview, isNotNull);
      expect(service.current.preview, equals(Uint8List.fromList(jpegBody)));
      expect(service.current.phase, RunPhase.running);
    });

    test('a preview carrying a metadata header is still found by signature', () {
      // Newer builds prepend a metadata block before the image. The exact
      // length encoding differs by version, so decoding locates the image by
      // its magic bytes instead of trusting a fixed offset.
      final out = BytesBuilder();
      final header = ByteData(8)
        ..setUint32(0, 4, Endian.big)
        ..setUint32(4, 12, Endian.big);
      out.add(header.buffer.asUint8List());
      out.add(utf8.encode('{"node":"6"}')); // 12 bytes of metadata
      out.add(jpegBody);

      service.handleBinaryMessage(out.toBytes());
      expect(service.current.preview, equals(Uint8List.fromList(jpegBody)),
          reason: 'metadata-prefixed previews must still decode');
    });

    test('a PNG preview is decoded', () {
      const pngBody = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      service.handleBinaryMessage(classicPreview(pngBody));
      expect(service.current.preview, equals(Uint8List.fromList(pngBody)));
    });

    test('a frame with no image signature is ignored, not shown as garbage', () {
      final out = BytesBuilder();
      final header = ByteData(8)
        ..setUint32(0, 3, Endian.big) // TEXT
        ..setUint32(4, 0, Endian.big);
      out.add(header.buffer.asUint8List());
      out.add(utf8.encode('not an image'));

      service.handleBinaryMessage(out.toBytes());
      expect(service.current.preview, isNull);
    });

    test('preview frames are ignored when no run is tracked', () {
      service.endTracking();
      service.handleBinaryMessage(classicPreview(jpegBody));
      expect(service.current.preview, isNull);
    });
  });

  test('a status frame while untracked never republishes a stale phase', () {
    // Reproduces the real ordering on device. ComfyUI pushes a `status`
    // frame the moment the socket opens, and `connect()` runs *after* the
    // runtime called run.begin() but *before* beginTracking(). If that
    // frame emits, it publishes the previous run's terminal phase into a
    // run that just started - the UI clears its active flag and every
    // later progress frame gets dropped as "late".
    final fresh = ComfyProgressService();
    addTearDown(fresh.dispose);

    // Run 1 finishes.
    fresh.beginTracking('run-1');
    fresh.handleTextMessage(jsonEncode({
      'type': 'executing',
      'data': {'prompt_id': 'run-1', 'node': null},
    }));
    expect(fresh.current.phase, RunPhase.completed);
    fresh.endTracking();

    final phasesSeen = <RunPhase>[];
    fresh.notifier.addListener(() => phasesSeen.add(fresh.current.phase));

    // Socket reopens for run 2; server greets it with a status frame.
    fresh.handleTextMessage(jsonEncode({
      'type': 'status',
      'data': {
        'status': {
          'exec_info': {'queue_remaining': 1},
        },
      },
    }));

    expect(phasesSeen, isEmpty,
        reason: 'a status frame while untracked must not publish anything - '
            'it carried the previous run\'s terminal phase into the next run');
  });
}
