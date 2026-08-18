// ==================== Forge Engine ==================== //
//
// Forge Neo / A1111-compatible implementation of [ImageEngine].
//
// The HTTP behaviour is carried over unchanged from the old `ForgeBackend`,
// but the way it gets its inputs is completely different. The old one
// declared a `generate(GenerationRequest)` and then ignored most of the
// request, reading fifteen mutable globals for the prompt, sampler, size,
// steps, CFG, denoise, mask settings, batch size and active checkpoint. It
// could not be tested without arranging global state, and no call site could
// tell what a run would do. This one reads its arguments and its endpoint,
// and nothing else.
//
// Server inventory (checkpoints, LoRAs, VAE modules) is *not* here: that is
// catalogue work, not generation work, and lives in ForgeCatalogClient.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/data/engines/forge/forge_catalog_client.dart';
import 'package:sd_companion/domain/engine/engine_capabilities.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/engine/image_engine.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/generation_spec.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';

class ForgeEngine implements ImageEngine, PromptRewriteCapable, UpscaleCapable {
  @override
  final EngineEndpoint endpoint;

  /// Optional LLM model id for the Ollama/OpenRouter prompt optimizer.
  final String? Function()? routerModel;

  final http.Client _client;
  final bool _ownsClient;

  ForgeEngine({
    required this.endpoint,
    this.routerModel,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  @override
  EngineKind get kind => EngineKind.forge;

  @override
  EngineCapabilities get capabilities => EngineCapabilities.forge;

  late final ForgeCatalogClient catalog =
      ForgeCatalogClient(endpoint: endpoint, client: _client);

  // ===== Progress ===== //
  //
  // Forge has no push channel: `/sdapi/v1/progress` must be polled. The old
  // code made every caller own that timer (and ProgressService duplicated
  // it a second time). Here the engine owns exactly one poll loop, running
  // only while a run is in flight, and publishes into the same Stream the
  // ComfyUI engine publishes into - so the UI cannot tell them apart.

  final _progress = StreamController<RunProgress>.broadcast();
  Timer? _poll;

  @override
  Stream<RunProgress> get progress => _progress.stream;

  void _startPolling() {
    _poll?.cancel();
    _emit(const RunProgress(phase: RunPhase.queued));
    _poll = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      final snapshot = await _fetchProgress();
      if (snapshot != null) _emit(snapshot);
    });
  }

  void _stopPolling(RunProgress last) {
    _poll?.cancel();
    _poll = null;
    _emit(last);
  }

  void _emit(RunProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  Future<RunProgress?> _fetchProgress() async {
    try {
      final response = await _client
          .get(endpoint.http('/sdapi/v1/progress'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final fraction = (data['progress'] as num?)?.toDouble() ?? 0.0;
      final state = data['state'] as Map<String, dynamic>? ?? const {};
      final job = (state['job'] as String? ?? '').toLowerCase();
      // Forge reports checkpoint swaps through the same progress endpoint,
      // with fraction pinned at 0 - without this the UI would sit at "0%"
      // for the ~30s a large model takes to load and look hung.
      final switching = job.contains('loading') ||
          job.contains('checkpoint') ||
          job.contains('weights');
      final preview = data['current_image'] as String?;

      return RunProgress(
        phase: fraction > 0 ? RunPhase.running : RunPhase.queued,
        fraction: fraction,
        stepCurrent: state['sampling_step'] as int?,
        stepTotal: state['sampling_steps'] as int?,
        stage: switching ? 'Loading checkpoint' : null,
        preview: preview != null ? base64Decode(preview) : null,
      );
    } catch (_) {
      return null;
    }
  }

  // ===== Lifecycle ===== //

  @override
  Future<bool> ping() async {
    try {
      final response = await _client
          .get(endpoint.http('/sdapi/v1/sd-models'))
          .timeout(const Duration(milliseconds: 500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Result<void>> cancel() => guard(() async {
        final response = await _client.post(endpoint.http('/sdapi/v1/interrupt'));
        if (response.statusCode != 200) {
          throw ServerError(
            'Failed to interrupt generation: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        _stopPolling(const RunProgress(phase: RunPhase.cancelled));
      });

  @override
  Future<Result<Uint8List>> fetchImageBytes(String url) => guard(() async {
        // Forge returns images inline as data URLs, so the common case never
        // touches the network at all.
        if (url.startsWith('data:image/')) {
          return base64Decode(url.substring(url.indexOf(',') + 1));
        }
        final response =
            await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw ServerError('Could not fetch image: HTTP ${response.statusCode}');
        }
        return response.bodyBytes;
      });

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    await _progress.close();
    if (_ownsClient) _client.close();
  }

  // ===== Generation ===== //

  @override
  Future<Result<List<GeneratedImage>>> generate(GenerationSpec spec) async {
    final result = await guard(() => _generate(spec));
    _stopPolling(
      result.fold(
        (_) => const RunProgress(phase: RunPhase.completed, fraction: 1),
        (e) => RunProgress(phase: RunPhase.failed, failureMessage: e.message),
      ),
    );
    return result;
  }

  Future<List<GeneratedImage>> _generate(GenerationSpec spec) async {
    final checkpoint = spec.checkpoint;
    if (checkpoint == null) {
      throw const ValidationError('Select a checkpoint before generating');
    }

    // Re-apply the saved VAE/text encoders before each generation so the
    // request stays correct after a server restart or a configuration edit.
    (await catalog.applyCheckpoint(checkpoint)).errorOrNull?.let((e) => throw e);

    _startPolling();

    // "Full image" checkpoints ignore the mask and regenerate the whole
    // frame, so the request must carry the image at its own dimensions
    // rather than the session's - snapped to a multiple of 16, which is
    // what the VAE's 8x downsample plus the UNet's own stride require.
    final fullImage = !checkpoint.inpaintMasked;
    var width = spec.sampling.width;
    var height = spec.sampling.height;
    var imageBytes = spec.sourceImage;

    if (fullImage && imageBytes != null) {
      final source = img.decodeImage(imageBytes);
      if (source == null) {
        throw const ValidationError('Unsupported input image');
      }
      width = _align16(source.width);
      height = _align16(source.height);
      if (width != source.width || height != source.height) {
        imageBytes = Uint8List.fromList(img.encodePng(img.copyResize(
          source,
          width: width,
          height: height,
          interpolation: img.Interpolation.cubic,
        )));
      }
    }

    final isImg2Img = imageBytes != null && imageBytes.isNotEmpty;
    final useMask = !fullImage && spec.hasMask;

    final body = <String, dynamic>{
      'prompt': spec.prompt,
      'negative_prompt': spec.negativePrompt,
      'sampler_name': spec.sampling.sampler,
      'scheduler': spec.sampling.scheduler,
      'width': width,
      'height': height,
      'n_iter': spec.sampling.batchSize,
      'steps': spec.sampling.steps,
      'cfg_scale': spec.sampling.cfgScale,
      'save_images': true,
      'send_images': true,
      if (spec.sampling.seed != null) 'seed': spec.sampling.seed,
      if (isImg2Img) ...{
        'denoising_strength': spec.sampling.denoise,
        'init_images': [base64Encode(imageBytes)],
        'resize_mode': 0,
      },
      if (useMask) ...{
        'mask': base64Encode(spec.mask!),
        'mask_blur': spec.sampling.maskBlur,
        'inpainting_fill': spec.sampling.maskFill.a1111Value,
        'inpaint_full_res_padding': 32,
        'inpaint_full_res': true,
        'inpainting_mask_invert': 0,
        'mask_round': true,
      },
      // The imagestitch integrated script composites extra references onto
      // the canvas server-side before sampling.
      if (spec.stitchImages.isNotEmpty)
        'alwayson_scripts': {
          'imagestitch integrated': {
            'args': [true, spec.stitchImages],
          },
        },
    };

    final response = await _client.post(
      endpoint.http(isImg2Img ? '/sdapi/v1/img2img' : '/sdapi/v1/txt2img'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ServerError(
        'Forge rejected the request: HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final images = decoded['images'] as List<dynamic>?;
    if (images == null || images.isEmpty) {
      throw const ServerError('Forge finished but returned no images');
    }

    // With a batch, A1111 prepends a contact-sheet grid that the user never
    // asked for; drop it.
    final start = images.length > 1 ? 1 : 0;
    return [
      for (var i = start; i < images.length; i++)
        GeneratedImage.fromRun(
          url: 'data:image/png;base64,${images[i]}',
          engine: EngineKind.forge,
          prompt: spec.prompt,
          negativePrompt: spec.negativePrompt,
        ),
    ];
  }

  int _align16(int value) {
    const alignment = 16;
    final lower = value - (value % alignment);
    final upper = lower + alignment;
    if (lower < alignment) return alignment;
    return value - lower < upper - value ? lower : upper;
  }

  // ===== Prompt rewriting ===== //

  @override
  Future<Result<String>> rewritePrompt(String prompt) => guard(() async {
        final model = routerModel?.call();
        final response = await _client.post(
          endpoint.http('/ollama_optimizer/optimize'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'prompt': prompt,
            if (model != null && model.isNotEmpty) 'openrouter_model': model,
          }),
        );
        if (response.statusCode != 200) {
          throw ServerError(
            'Failed to optimize prompt: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return decoded['optimizedPrompt'] as String;
      });

  // ===== SeedVR2 upscale ===== //
  //
  // Forge Neo exposes this as a blocking POST plus a separate progress
  // endpoint, so the two are run concurrently and joined at the end.

  @override
  Future<Result<String>> upscale({
    required Uint8List image,
    required int targetResolution,
    void Function(RunProgress progress)? onProgress,
  }) =>
      guard(() async {
        var done = false;
        final request = _client
            .post(
              endpoint.http('/seedvr2/upscale'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'image': base64Encode(image),
                'resolution': targetResolution,
              }),
            )
            .whenComplete(() => done = true);

        if (onProgress != null) {
          unawaited(() async {
            while (!done) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (done) break;
              try {
                final r = await _client
                    .get(endpoint.http('/seedvr2/progress'))
                    .timeout(const Duration(seconds: 2));
                if (r.statusCode != 200) continue;
                final d = jsonDecode(r.body) as Map<String, dynamic>;
                onProgress(RunProgress(
                  phase: RunPhase.running,
                  fraction: (d['progress'] as num?)?.toDouble(),
                  stage: d['status'] as String?,
                ));
              } catch (e) {
                debugPrint('SeedVR2 progress poll failed: $e');
              }
            }
          }());
        }

        final response = await request;
        if (response.statusCode != 200) {
          throw ServerError(
            'Upscaling failed: HTTP ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
          );
        }
        final upscaled =
            (jsonDecode(response.body) as Map<String, dynamic>)['image'] as String;
        return upscaled.startsWith('data:image/')
            ? upscaled
            : 'data:image/png;base64,$upscaled';
      });
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
