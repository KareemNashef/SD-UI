// ==================== Forge Catalog Client ==================== //
//
// Everything about *what the server has installed*: checkpoints, their VAE
// and text-encoder modules, and LoRAs with their Civitai metadata.
//
// This used to be five methods on ForgeBackend that each wrote straight into
// `globalCheckpointDataMap` / `globalLoraDataMap` and then called
// `StorageService.save...()` as a side effect. That meant refreshing the
// inventory silently mutated the user's selections, and no caller could
// refresh without also persisting. Here every method is a pure query that
// returns domain values; deciding what to keep, merge or persist is the
// CatalogStore's job.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/domain/catalog/checkpoint.dart';
import 'package:sd_companion/domain/catalog/lora.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';

class ForgeCatalogClient {
  final EngineEndpoint endpoint;
  final http.Client _client;

  ForgeCatalogClient({required this.endpoint, http.Client? client})
      : _client = client ?? http.Client();

  /// Models installed on the server. [force] asks Forge to rescan its disk
  /// first, which is slow enough that it is not the default.
  Future<Result<List<Checkpoint>>> fetchCheckpoints({bool force = false}) =>
      guard(() async {
        if (force) {
          // Best-effort: a refresh failure just means a slightly stale list,
          // which is far better than failing the whole fetch.
          try {
            await _client
                .post(endpoint.http('/sdapi/v1/refresh-checkpoints'))
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
        }

        final response = await _client.get(endpoint.http('/sdapi/v1/sd-models'));
        if (response.statusCode != 200) {
          throw ServerError(
            'Failed to load checkpoints: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }

        return [
          for (final raw in jsonDecode(response.body) as List)
            if (raw is Map<String, dynamic> && raw['model_name'] is String)
              Checkpoint(
                name: raw['model_name'] as String,
                title: raw['title'] as String?,
              ),
        ];
      });

  /// VAE and text-encoder files Forge Neo can attach to a checkpoint.
  Future<Result<List<String>>> fetchModules() => guard(() async {
        final response = await _client.get(endpoint.http('/sdapi/v1/sd-modules'));
        if (response.statusCode != 200) {
          throw ServerError(
            'Failed to load VAE and text encoders: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        final modules = (jsonDecode(response.body) as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => item['model_name']?.toString().trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return modules;
      });

  /// Selects [checkpoint] server-side, together with its saved modules.
  Future<Result<void>> applyCheckpoint(Checkpoint checkpoint) => guard(() async {
        final response = await _client.post(
          endpoint.http('/sdapi/v1/options'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sd_model_checkpoint': checkpoint.selector,
            'forge_additional_modules': checkpoint.modules,
          }),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ServerError(
            'Failed to apply checkpoint configuration: '
            'HTTP ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
          );
        }
      });

  /// Selects [checkpoint] and waits for the weights to finish loading.
  ///
  /// Forge only starts a swap when something actually needs the model, so a
  /// throwaway 10x10 render is what forces it; then `/progress` going idle
  /// is what tells us the load finished.
  Future<Result<void>> selectCheckpointAndWait(
    Checkpoint checkpoint, {
    Duration timeout = const Duration(minutes: 5),
  }) =>
      guard(() async {
        (await applyCheckpoint(checkpoint)).errorOrNull?.let((e) => throw e);

        await _client.post(
          endpoint.http('/sdapi/v1/txt2img'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'prompt': '',
            'steps': 1,
            'width': 10,
            'height': 10,
            'sampler_name': 'Euler a',
            'cfg_scale': 1.0,
            'save_images': false,
          }),
        );

        final deadline = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 500));
          final response = await _client.get(endpoint.http('/sdapi/v1/progress'));
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final job = data['state']?['job'] as String?;
          if (data['progress'] == 0 && (job == null || job.isEmpty)) return;
        }
        throw const TimeoutError('Timed out waiting for the checkpoint to load');
      });

  /// LoRAs installed on the server, with Civitai metadata where available.
  ///
  /// [known] lets a caller skip the per-LoRA metadata fetch for entries it
  /// already has - with a few hundred LoRAs that is a few hundred HTTP round
  /// trips, which is why the old version quietly did nothing on refresh.
  Future<Result<List<Lora>>> fetchLoras({
    Set<String> known = const {},
    bool force = false,
  }) =>
      guard(() async {
        try {
          await _client.post(endpoint.http('/sdapi/v1/refresh-loras'));
        } catch (_) {}

        final response = await _client.get(endpoint.http('/sdapi/v1/loras'));
        if (response.statusCode != 200) {
          throw ServerError(
            'Failed to load LoRAs: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }

        final result = <Lora>[];
        for (final raw in jsonDecode(response.body) as List) {
          final name = (raw is Map ? raw['name'] as String? : null) ?? '';
          if (name.isEmpty) continue;

          final preview = endpoint.http('/file=models/Lora/$name.preview.png').toString();
          if (!force && known.contains(name)) {
            // Caller already holds the full record; report existence only.
            result.add(Lora(name: name, previewUrl: preview));
            continue;
          }
          result.add(await _withMetadata(name, preview));
        }
        return result;
      });

  Future<Lora> _withMetadata(String name, String previewUrl) async {
    try {
      final response = await _client
          .get(endpoint.http('/file=models/Lora/$name.civitai.info'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final meta = jsonDecode(response.body) as Map<String, dynamic>;
        return Lora(
          name: name,
          alias: meta['model']?['name'] as String?,
          baseModel: meta['baseModel'] as String?,
          tags: (meta['trainedWords'] as List?)?.cast<String>() ?? const [],
          previewUrl: previewUrl,
        );
      }
    } catch (e) {
      debugPrint('Could not fetch metadata for LoRA $name: $e');
    }
    return Lora(name: name, previewUrl: previewUrl);
  }

  /// Reads the generation parameters embedded in a PNG.
  Future<Result<Map<String, dynamic>>> pngInfo(String base64Image) =>
      guard(() async {
        final response = await _client.post(
          endpoint.http('/sdapi/v1/png-info'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image': base64Image}),
        );
        if (response.statusCode != 200) {
          throw ServerError(
            'Failed to read PNG info: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      });
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
