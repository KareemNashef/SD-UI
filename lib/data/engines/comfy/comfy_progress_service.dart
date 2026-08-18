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
      _socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 5));
      _reconnectAttempt = 0;
      _subscription = _socket!.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Comfy WebSocket connect failed: $e');
      _scheduleReconnect();
    }
  }

  void beginTracking(String promptId) {
    _trackedPromptId = promptId;
    _phase = RunPhase.queued;
    _currentNodeId = null;
    _stepCurrent = null;
    _stepTotal = null;
    _previewBytes = null;
    _errorMessage = null;
    _emit(jobId: promptId);
  }

  void endTracking() {
    _trackedPromptId = null;
  }

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
    }
  }

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
    if (type == 'status') {
      final queueRemaining =
          (data['status']?['exec_info']?['queue_remaining'] as num?)?.toInt();
      if (queueRemaining != null) {
        _queuePosition = queueRemaining;
        _emit();
      }
      return;
    }

    if (_trackedPromptId == null || promptId != _trackedPromptId) return;

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
          _currentNodeId = node.toString();
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
    if (_trackedPromptId == null || data.length < 8) return;
    final view = ByteData.sublistView(data, 0, 8);
    final eventType = view.getUint32(0, Endian.big);
    if (eventType != 1) return; // 1 = PREVIEW_IMAGE
    _previewBytes = data.sublist(8);
    _phase = RunPhase.running;
    _emit();
  }

  void _emit({String? jobId}) {
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
