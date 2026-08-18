// ==================== Engine Store ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/store.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';

/// Which engine is active, where both engines live, and whether the active
/// one is reachable.
///
/// Replaces five loose globals (`globalActiveBackendKind`,
/// `globalServerIP/Port`, `globalComfyServerIP/Port`, `globalServerStatus`)
/// that had to be kept in agreement by hand. Holding them in one snapshot
/// makes the invariant - *capabilities always match the active engine* -
/// impossible to break, because [capabilities] is derived, not stored.
@immutable
class EngineState {
  final EngineKind active;

  /// Every engine's endpoint, so switching never loses the other address.
  final Map<EngineKind, EngineEndpoint> endpoints;

  final ConnectionStatus status;

  /// Why the last connection attempt failed, for the UI to show.
  final String? lastError;

  const EngineState({
    required this.active,
    required this.endpoints,
    this.status = ConnectionStatus.unknown,
    this.lastError,
  });

  factory EngineState.initial() => EngineState(
        active: EngineKind.forge,
        endpoints: {
          for (final kind in EngineKind.values)
            kind: EngineEndpoint.defaultFor(kind),
        },
      );

  /// The active engine's endpoint.
  EngineEndpoint get endpoint => endpoints[active]!;

  /// Derived, never stored - so it can't drift out of sync with [active].
  EngineCapabilities get capabilities => EngineCapabilities.of(active);

  bool get isConnected => status == ConnectionStatus.connected;

  EngineState copyWith({
    EngineKind? active,
    Map<EngineKind, EngineEndpoint>? endpoints,
    ConnectionStatus? status,
    String? lastError,
    bool clearError = false,
  }) =>
      EngineState(
        active: active ?? this.active,
        endpoints: endpoints ?? this.endpoints,
        status: status ?? this.status,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  @override
  bool operator ==(Object other) =>
      other is EngineState &&
      other.active == active &&
      mapEquals(other.endpoints, endpoints) &&
      other.status == status &&
      other.lastError == lastError;

  @override
  int get hashCode =>
      Object.hash(active, Object.hashAll(endpoints.values), status, lastError);
}

enum ConnectionStatus {
  unknown,
  connecting,
  connected,
  unreachable;

  String get label => switch (this) {
        ConnectionStatus.unknown => 'Not connected',
        ConnectionStatus.connecting => 'Connecting',
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.unreachable => 'Unreachable',
      };
}

class EngineStore extends Store<EngineState> {
  EngineStore([EngineState? initial]) : super(initial ?? EngineState.initial());

  EngineKind get active => state.active;
  EngineEndpoint get endpoint => state.endpoint;
  EngineCapabilities get capabilities => state.capabilities;

  /// Switches the active engine. Connection status resets, because a status
  /// from the previous engine says nothing about this one - the stale-badge
  /// bug the old code had to remember to clear by hand at each call site.
  void setActive(EngineKind kind) {
    if (state.active == kind) return;
    emit(state.copyWith(
      active: kind,
      status: ConnectionStatus.unknown,
      clearError: true,
    ));
  }

  void setEndpoint(EngineEndpoint endpoint) {
    emit(state.copyWith(
      endpoints: {...state.endpoints, endpoint.kind: endpoint},
    ));
  }

  /// Updates the active engine's address.
  void setAddress({String? host, String? port}) {
    setEndpoint(state.endpoint.copyWith(host: host, port: port));
  }

  void markConnecting() =>
      emit(state.copyWith(status: ConnectionStatus.connecting, clearError: true));

  void markConnected() =>
      emit(state.copyWith(status: ConnectionStatus.connected, clearError: true));

  void markUnreachable([String? reason]) => emit(state.copyWith(
        status: ConnectionStatus.unreachable,
        lastError: reason,
      ));
}
