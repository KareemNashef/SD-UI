// ==================== Comfy Progress Service ==================== //
//
// Owns the ComfyUI `/ws?clientId=...` lifecycle: connects lazily, filters
// every message by the currently-tracked prompt id, maps status/execution/
// progress/error events (plus binary preview frames) onto the shared
// GenerationProgress model, and reconnects with backoff on drop. Actual
// generation *completion* is still driven by ComfyBackend's `/history`
// poll - this service only feeds the UI; if the socket never connects or
// drops mid-run, generation still finishes normally.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/diagnostics.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';

class ComfyProgressService {
  WebSocket? _socket;
  StreamSubscription? _subscription;
  String? _clientId;
  String? _trackedPromptId;
  EngineEndpoint? _connectedEndpoint;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  RunPhase _phase = RunPhase.idle;
  String? _currentNodeId;
  int? _stepCurrent;
  int? _stepTotal;
  int? _queuePosition;
  Uint8List? _previewBytes;
  String? _errorMessage;

  final ValueNotifier<RunProgress> notifier = ValueNotifier(RunProgress.idle);

  RunProgress get current => notifier.value;

  String ensureClientId() {
    _clientId ??= _randomId();
    return _clientId!;
  }

  /// Opens (or reuses) the WebSocket for [endpoint]. Safe to call
  /// repeatedly; failures are swallowed since generation falls back to
  /// history polling regardless.
  ///
  /// Reuse is only trusted if the existing socket reports itself as still
  /// open - a half-dead socket (e.g. the app was backgrounded and the OS
  /// silently dropped the connection) would otherwise pass the old
  /// "is it non-null" check and every future "executing"/"progress" event
  /// and preview frame would be silently lost, leaving the generation
  /// overlay stuck on its initial state for the whole run. Pass
  /// [force] to always reopen regardless of reported state, which is used
  /// right before queueing a new generation to guarantee a fresh socket.
  Future<void> connect(EngineEndpoint endpoint, {bool force = false}) async {
    if (_disposed) return;
    if (!force &&
        _socket != null &&
        _socket!.readyState == WebSocket.open &&
        _connectedEndpoint?.id == endpoint.id) {
      return;
    }
    await _closeSocket();
    _connectedEndpoint = endpoint;

    try {
      final uri = endpoint.ws('/ws', {'clientId': ensureClientId()});
      trace('preview', 'socket registering clientId=${ensureClientId()}');
      trace('ws', 'connecting to $uri (force=$force)');
      _socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 5));
      _reconnectAttempt = 0;
      _subscription = _socket!.listen(
        _onMessage,
        onDone: () {
          trace('ws', 'socket closed by peer');
          _scheduleReconnect();
        },
        onError: (Object e) {
          trace('ws', 'socket error: $e');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
      trace('ws', 'CONNECTED, listening');
    } catch (e) {
      trace('ws', 'CONNECT FAILED: $e  (progress will be dead this run)');
      debugPrint('Comfy WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void beginTracking(String promptId) {
    trace('track', 'BEGIN promptId=$promptId (was phase=${_phase.name})');
    _trackedPromptId = promptId;
    _phase = RunPhase.queued;
    _currentNodeId = null;
    _stepCurrent = null;
    _stepTotal = null;
    _queuePosition = null;
    _previewBytes = null;
    _errorMessage = null;
    _emit(jobId: promptId);
  }

  void endTracking() {
    trace('track', 'END (final phase=${_phase.name})');
    _trackedPromptId = null;
  }

  void _log(String message) => trace('ws', message);

  /// Defense-in-depth for the overlay getting stuck on "queued": if
  /// `/history` polling confirms the job hasn't errored or completed yet
  /// but no WebSocket event has moved it off "queued", nudge it to
  /// "running" so the UI doesn't sit frozen on its initial state for the
  /// whole generation when the socket is unreliable.
  void nudgeRunningIfQueued() {
    if (_phase != RunPhase.queued) return;
    _phase = RunPhase.running;
    _emit();
  }

  void _onMessage(dynamic message) {
    if (message is String) {
      _onTextMessage(message);
    } else if (message is List<int>) {
      _onBinaryMessage(Uint8List.fromList(message));
    } else {
      // Neither text nor bytes. Worth knowing about: if previews ever arrive
      // in a shape this code does not recognise, silence here would look
      // identical to the server not sending them at all.
      trace('preview', 'UNKNOWN frame type ${message.runtimeType} - ignored');
    }
  }

  /// Feeds one raw text frame in, exactly as the socket delivers it. Exists
  /// so the message decoding can be tested without standing up a WebSocket -
  /// the per-node step-count handling below is subtle enough that it needs
  /// direct coverage.
  @visibleForTesting
  void handleTextMessage(String text) => _onTextMessage(text);

  /// Feeds one raw binary frame in, as the socket delivers it.
  @visibleForTesting
  void handleBinaryMessage(Uint8List data) => _onBinaryMessage(data);

  void _onTextMessage(String text) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = decoded['type'] as String?;
    final data = (decoded['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final promptId = data['prompt_id'] as String?;

    // "status" carries queue length globally, not scoped to a prompt id.
    //
    // It must NOT emit while no run is being tracked. ComfyUI sends a status
    // frame the instant the socket opens, and `connect()` happens *after*
    // the runtime has already called `run.begin()` but *before*
    // `beginTracking()` resets the phase. Emitting there published the
    // previous run's phase (`completed`, or `idle` on the first run) into a
    // run that had only just started - which cleared RunStore's active
    // flag, and from then on RunStore's late-frame guard dropped every real
    // progress frame for the rest of the run. That is the "flashes for a
    // split second, then never progresses" bug, and it was timing-dependent
    // on when the server's first status frame landed.
    if (type == 'status') {
      final queueRemaining =
          (data['status']?['exec_info']?['queue_remaining'] as num?)?.toInt();
      if (queueRemaining != null) {
        _queuePosition = queueRemaining;
        if (_trackedPromptId != null) {
          _emit();
        } else {
          _log('status queue=$queueRemaining (not tracking - not emitted)');
        }
      }
      return;
    }

    if (_trackedPromptId == null || promptId != _trackedPromptId) {
      _log('IGNORED type=$type promptId=$promptId tracked=$_trackedPromptId');
      return;
    }

    _log('recv type=$type data=${_summarise(type, data)}');

    switch (type) {
      case 'execution_start':
        _phase = RunPhase.running;
        _emit();
        break;
      case 'executing':
        final node = data['node'];
        if (node == null) {
          _phase = RunPhase.completed;
        } else {
          _phase = RunPhase.running;
          final next = node.toString();
          // Step counts are reported *per node*. Carrying the previous
          // node's counts into the next one is what made the bar freeze:
          // a sampler that ended at 20/20 left fraction pinned to 1.0, and
          // every later node that doesn't report progress (VAE decode, save,
          // upscale, ...) kept showing a full, motionless bar for the rest
          // of the run. Clearing them drops the bar back to indeterminate,
          // which is the honest state - "working, can't say how far".
          if (next != _currentNodeId) {
            _stepCurrent = null;
            _stepTotal = null;
          }
          _currentNodeId = next;
        }
        _emit();
        break;
      case 'progress':
        _stepCurrent = (data['value'] as num?)?.toInt();
        _stepTotal = (data['max'] as num?)?.toInt();
        _phase = RunPhase.running;
        _emit();
        break;
      case 'execution_success':
        _phase = RunPhase.completed;
        _emit();
        break;
      case 'execution_error':
        _phase = RunPhase.failed;
        _errorMessage = data['exception_message']?.toString() ?? 'Execution error';
        _emit();
        break;
      case 'execution_interrupted':
        _phase = RunPhase.cancelled;
        _emit();
        break;
    }
  }

  void _onBinaryMessage(Uint8List data) {
    if (data.length < 8) {
      trace('ws', 'BINARY too short (${data.length}B) - ignored');
      return;
    }
    final view = ByteData.sublistView(data, 0, 8);
    final eventType = view.getUint32(0, Endian.big);
    final secondWord = view.getUint32(4, Endian.big);
    trace(
      'ws',
      'BINARY ${data.length}B eventType=$eventType word2=$secondWord '
          'tracked=$_trackedPromptId',
    );

    if (_trackedPromptId == null) return;

    // ComfyUI's BinaryEventTypes: 1 = PREVIEW_IMAGE, 2 = UNENCODED_PREVIEW_IMAGE,
    // 3 = TEXT, 4 = PREVIEW_IMAGE_WITH_METADATA (newer builds). Type 1 puts
    // the image straight after an 8-byte header; type 4 inserts a metadata
    // block whose length encoding this code does not want to guess at. So
    // rather than hard-code a layout per version, find where the image
    // actually starts by its magic bytes - that is version-proof, and the
    // header scan is a few bytes.
    if (eventType == 3) return; // TEXT, not an image

    final start = _imageStart(data);
    if (start == null) {
      trace('preview',
          'REJECTED binary frame: eventType=$eventType carried no PNG or '
          'JPEG signature in its first 64 bytes. The transport works but '
          'the payload shape is unrecognised - relay this line.');
      return;
    }
    _previewBytes = data.sublist(start);
    _phase = RunPhase.running;
    trace('preview',
        'ACCEPTED ${_previewBytes!.length}B from a ${data.length}B frame '
        '(image starts at byte $start) - handing it to the UI');
    _emit();
  }

  /// Offset of the first PNG/JPEG signature, searched over the header region
  /// only. Returns null when the payload holds no image.
  static int? _imageStart(Uint8List data) {
    const jpeg = [0xFF, 0xD8, 0xFF];
    const png = [0x89, 0x50, 0x4E, 0x47];
    final limit = data.length < 64 ? data.length : 64;
    for (var i = 0; i < limit; i++) {
      if (i + 3 <= data.length &&
          data[i] == jpeg[0] &&
          data[i + 1] == jpeg[1] &&
          data[i + 2] == jpeg[2]) {
        return i;
      }
      if (i + 4 <= data.length &&
          data[i] == png[0] &&
          data[i + 1] == png[1] &&
          data[i + 2] == png[2] &&
          data[i + 3] == png[3]) {
        return i;
      }
    }
    return null;
  }

  /// Compact one-line view of the fields that actually matter per type, so
  /// the log stays readable when a run emits hundreds of frames.
  String _summarise(String? type, Map<String, dynamic> data) => switch (type) {
        'progress' => 'value=${data['value']} max=${data['max']}',
        'executing' => 'node=${data['node']}',
        'execution_error' => 'msg=${data['exception_message']}',
        _ => '-',
      };

  void _emit({String? jobId}) {
    final fraction =
        (_stepCurrent != null && _stepTotal != null && _stepTotal! > 0)
            ? _stepCurrent! / _stepTotal!
            : null;
    trace(
      'emit',
      '$traceClock phase=${_phase.name} '
          'frac=${fraction?.toStringAsFixed(3) ?? "null"} '
          'step=$_stepCurrent/$_stepTotal node=$_currentNodeId '
          'queue=$_queuePosition preview=${_previewBytes?.length ?? 0}B',
    );
    notifier.value = RunProgress(
      phase: _phase,
      currentNode: _currentNodeId,
      stepCurrent: _stepCurrent,
      stepTotal: _stepTotal,
      fraction: (_stepCurrent != null && _stepTotal != null && _stepTotal! > 0)
          ? _stepCurrent! / _stepTotal!
          : null,
      queuePosition: _queuePosition,
      preview: _previewBytes,
      failureMessage: _errorMessage,
    );
  }

  void _scheduleReconnect() {
    _socket = null;
    _subscription = null;
    if (_disposed || _connectedEndpoint == null) return;
    _reconnectAttempt = min(_reconnectAttempt + 1, 5);
    final delay = Duration(seconds: _reconnectAttempt * 2);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      final endpoint = _connectedEndpoint;
      if (endpoint != null && !_disposed) connect(endpoint);
    });
  }

  Future<void> _closeSocket() async {
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    _disposed = true;
    _closeSocket();
  }

  String _randomId() {
    final rand = Random();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
