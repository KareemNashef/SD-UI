// ==================== Comfy Object Info Client ==================== //

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/data/engines/comfy/comfy_node_schema.dart';
import 'package:sd_companion/core/app_error.dart';

/// Fetches and caches `/object_info/<type>` from a live ComfyUI server.
class HttpComfyNodeSchemaProvider implements ComfyNodeSchemaProvider {
  final EngineEndpoint endpoint;
  final http.Client _client;
  final Map<String, ComfyNodeSchema> _cache = {};

  HttpComfyNodeSchemaProvider(this.endpoint, {http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<ComfyNodeSchema> schemaFor(String nodeType) async {
    final cached = _cache[nodeType];
    if (cached != null) return cached;

    final uri = endpoint.http('/object_info/$nodeType');
    http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw UnreachableError(
        'Could not reach ComfyUI to load "$nodeType" node info: $e',
        cause: e,
      );
    }
    if (response.statusCode != 200) {
      throw ServerError(
        'Failed to load node info for "$nodeType": HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (decoded[nodeType] as Map?)?.cast<String, dynamic>();
    final schema = raw == null
        ? ComfyNodeSchema.unknown(nodeType)
        : ComfyNodeSchema.fromObjectInfo(nodeType, raw);
    _cache[nodeType] = schema;
    return schema;
  }

  void clearCache() => _cache.clear();
}
