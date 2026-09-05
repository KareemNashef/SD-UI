// ==================== Model Library ==================== //
//
// One ComfyUI server's checkpoints and LoRAs, as the ComfyUI-Lora-Manager
// addon describes them, loaded once and shared.
//
// Three places want the same answer at the same time: the settings drawer
// showing "Realism Enhancer Krea2" instead of a filename, each LoRA row
// showing its own thumbnail, and the browser page showing the whole wall.
// Fetching independently would mean three round trips for one library that
// changes about as often as the user downloads a model - so this holds it,
// per endpoint, the same way workflows are held per endpoint.
//
// Everything is observable, and everything degrades: a server without the
// addon reports `unavailable` and every lookup returns null, which the UI
// reads as "just show the filename".

import 'package:flutter/foundation.dart';

import 'package:sd_companion/data/engines/comfy/lora_manager_client.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';

class ModelLibrary {
  final EngineEndpoint endpoint;
  final LoraManagerClient _client;

  ModelLibrary(this.endpoint, {LoraManagerClient? client})
      : _client = client ?? LoraManagerClient(endpoint);

  final ValueNotifier<List<ManagedModel>> loras = ValueNotifier(const []);
  final ValueNotifier<List<ManagedModel>> checkpoints = ValueNotifier(const []);

  /// True once a load has failed - the addon is not installed, or the
  /// server is not reachable. The UI falls back to plain names.
  final ValueNotifier<bool> unavailable = ValueNotifier(false);

  /// Bumped whenever anything at all changes, so a widget can listen to one
  /// thing rather than three.
  final ValueNotifier<int> revision = ValueNotifier(0);

  final Map<ManagedModelKind, Future<void>> _inFlight = {};
  final Map<String, ManagedModelDetail> _details = {};
  final Map<String, Future<ManagedModelDetail>> _detailsInFlight = {};

  ValueNotifier<List<ManagedModel>> notifierFor(ManagedModelKind kind) =>
      kind == ManagedModelKind.lora ? loras : checkpoints;

  List<ManagedModel> modelsFor(ManagedModelKind kind) =>
      notifierFor(kind).value;

  /// Loads [kind] once. Concurrent callers share the same request, and a
  /// completed load is never repeated - call [refresh] for that.
  Future<void> ensureLoaded(ManagedModelKind kind) {
    if (notifierFor(kind).value.isNotEmpty) return Future.value();
    return _inFlight.putIfAbsent(kind, () => _load(kind));
  }

  Future<void> refresh(ManagedModelKind kind) {
    _inFlight.remove(kind);
    notifierFor(kind).value = const [];
    return ensureLoaded(kind);
  }

  Future<void> _load(ManagedModelKind kind) async {
    try {
      final models = await _client.list(kind);
      notifierFor(kind).value = models;
      unavailable.value = false;
    } catch (_) {
      unavailable.value = true;
    } finally {
      _inFlight.remove(kind);
      revision.value++;
    }
  }

  /// The addon's record for a ComfyUI combo option, or null.
  ///
  /// ComfyUI reports `krea\file.safetensors` (relative to the model root,
  /// Windows-separated); the addon reports folder `krea` plus an absolute
  /// path. Matching folds both to `krea/file.safetensors`, falling back to
  /// the bare file name because the two roots are not always the same one.
  ManagedModel? resolve(ManagedModelKind kind, String option) {
    if (option.isEmpty) return null;
    final key = option.replaceAll('\\', '/').toLowerCase();
    final tail = key.contains('/') ? key.split('/').last : key;
    ManagedModel? byName;
    for (final model in modelsFor(kind)) {
      if (model.comfyKey == key) return model;
      if (byName == null && model.basename.toLowerCase() == tail) {
        byName = model;
      }
    }
    return byName;
  }

  /// The cached Civitai record for one model, fetched at most once.
  Future<ManagedModelDetail> detail(
      ManagedModelKind kind, ManagedModel model) {
    final cached = _details[model.filePath];
    if (cached != null) return Future.value(cached);
    return _detailsInFlight.putIfAbsent(model.filePath, () async {
      final detail = await _client.detail(kind, model);
      _details[model.filePath] = detail;
      _detailsInFlight.remove(model.filePath);
      return detail;
    });
  }

  /// A still to stand in for a video preview, or null when there is none.
  /// `.mp4` previews cannot be decoded here, but the addon has usually
  /// cached the same model's Civitai images alongside them.
  Future<String?> poster(ManagedModelKind kind, ManagedModel model) async {
    final detail = await this.detail(kind, model);
    return detail.posterUrl();
  }

  /// Already-fetched poster, for a synchronous build.
  String? cachedPoster(ManagedModel model) => _details[model.filePath]?.posterUrl();

  bool hasDetail(ManagedModel model) => _details.containsKey(model.filePath);

  void dispose() {
    _client.dispose();
    loras.dispose();
    checkpoints.dispose();
    unavailable.dispose();
    revision.dispose();
  }
}
