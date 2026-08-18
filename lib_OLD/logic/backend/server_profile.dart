// ==================== Server Profile ==================== //

import 'package:sd_companion/logic/backend/backend_kind.dart';

/// Identifies a single server connection (scheme/host/port/base path) for a
/// given backend kind. Two profiles with the same [kind] but different hosts
/// are different profiles, so storage keys must be namespaced by [id], not
/// by [kind] alone.
class ServerProfile {
  final BackendKind kind;
  final String scheme; // 'http' or 'https'
  final String host;
  final String port;
  final String? basePath; // optional reverse-proxy prefix, no leading slash

  const ServerProfile({
    required this.kind,
    required this.host,
    required this.port,
    this.scheme = 'http',
    this.basePath,
  });

  /// A normalized, storage-safe identifier for this profile.
  String get id {
    final path = (basePath == null || basePath!.isEmpty) ? '' : '/$basePath';
    return '${kind.storageKey}:$scheme:$host:$port$path';
  }

  bool get isSecure => scheme == 'https';

  String get _pathPrefix =>
      (basePath == null || basePath!.isEmpty) ? '' : '/$basePath';

  Uri httpUri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: scheme,
      host: host,
      port: int.tryParse(port),
      path: '$_pathPrefix$normalizedPath',
      queryParameters: queryParameters,
    );
  }

  Uri wsUri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: isSecure ? 'wss' : 'ws',
      host: host,
      port: int.tryParse(port),
      path: '$_pathPrefix$normalizedPath',
      queryParameters: queryParameters,
    );
  }

  ServerProfile copyWith({
    BackendKind? kind,
    String? scheme,
    String? host,
    String? port,
    String? basePath,
  }) {
    return ServerProfile(
      kind: kind ?? this.kind,
      scheme: scheme ?? this.scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      basePath: basePath ?? this.basePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.storageKey,
    'scheme': scheme,
    'host': host,
    'port': port,
    if (basePath != null) 'basePath': basePath,
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    kind: BackendKindLabel.fromStorageKey(json['kind'] as String?),
    scheme: json['scheme'] as String? ?? 'http',
    host: json['host'] as String? ?? '127.0.0.1',
    port: json['port'] as String? ?? '',
    basePath: json['basePath'] as String?,
  );

  static ServerProfile defaultFor(BackendKind kind) => switch (kind) {
    BackendKind.forge => const ServerProfile(
      kind: BackendKind.forge,
      host: '127.0.0.1',
      port: '7860',
    ),
    BackendKind.comfy => const ServerProfile(
      kind: BackendKind.comfy,
      host: '127.0.0.1',
      port: '8188',
    ),
  };
}
