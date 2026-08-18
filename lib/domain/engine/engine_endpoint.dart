// ==================== Engine Endpoint ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/domain/engine/engine_kind.dart';

/// Where an engine lives on the network.
///
/// Each engine keeps its own endpoint, so switching from Forge to ComfyUI
/// and back never loses the other one's address - the single biggest
/// papercut in the original single-address design.
@immutable
class EngineEndpoint {
  final EngineKind kind;
  final String scheme; // http | https
  final String host;
  final String port;

  /// Optional reverse-proxy prefix, no leading slash.
  final String? basePath;

  const EngineEndpoint({
    required this.kind,
    required this.host,
    required this.port,
    this.scheme = 'http',
    this.basePath,
  });

  factory EngineEndpoint.defaultFor(EngineKind kind) => EngineEndpoint(
        kind: kind,
        host: '127.0.0.1',
        port: kind.defaultPort,
      );

  bool get isSecure => scheme == 'https';

  /// Stable identity for this endpoint. Storage keys are namespaced by this
  /// rather than by [kind], so per-server data (saved workflows, cached
  /// galleries) doesn't leak between two different ComfyUI machines.
  String get id => '${kind.storageKey}:$scheme:$host:$port${_prefix.isEmpty ? '' : _prefix}';

  String get _prefix =>
      (basePath == null || basePath!.isEmpty) ? '' : '/$basePath';

  /// Human-readable address for the UI.
  String get display => '$host:$port';

  Uri http(String path, [Map<String, dynamic>? query]) => Uri(
        scheme: scheme,
        host: host,
        port: int.tryParse(port),
        path: '$_prefix${path.startsWith('/') ? path : '/$path'}',
        queryParameters: query,
      );

  Uri ws(String path, [Map<String, dynamic>? query]) => Uri(
        scheme: isSecure ? 'wss' : 'ws',
        host: host,
        port: int.tryParse(port),
        path: '$_prefix${path.startsWith('/') ? path : '/$path'}',
        queryParameters: query,
      );

  EngineEndpoint copyWith({
    String? scheme,
    String? host,
    String? port,
    String? basePath,
  }) =>
      EngineEndpoint(
        kind: kind,
        scheme: scheme ?? this.scheme,
        host: host ?? this.host,
        port: port ?? this.port,
        basePath: basePath ?? this.basePath,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.storageKey,
        'scheme': scheme,
        'host': host,
        'port': port,
        if (basePath != null) 'basePath': basePath,
      };

  factory EngineEndpoint.fromJson(Map<String, dynamic> json) => EngineEndpoint(
        kind: EngineKind.fromStorageKey(json['kind'] as String?),
        scheme: json['scheme'] as String? ?? 'http',
        host: json['host'] as String? ?? '127.0.0.1',
        port: json['port'] as String? ?? '7860',
        basePath: json['basePath'] as String?,
      );

  @override
  bool operator ==(Object other) => other is EngineEndpoint && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EngineEndpoint($id)';
}
