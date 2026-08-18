// ==================== Settings Repository ==================== //

import 'package:sd_companion/data/persistence/preferences.dart';
import 'package:sd_companion/domain/engine/engine_endpoint.dart';
import 'package:sd_companion/domain/engine/engine_kind.dart';
import 'package:sd_companion/domain/generation/sampling_params.dart';
import 'package:sd_companion/state/engine_store.dart';
import 'package:sd_companion/state/prompt_book_store.dart';

/// Loads and saves the app's durable settings.
///
/// Deliberately talks in domain types, not in preference keys - a caller
/// asks for "the engine state" and gets one, rather than remembering to read
/// five separate strings and assemble them correctly. That assembly was
/// previously duplicated across startup, the settings screen and the
/// connection screen, and they had drifted.
class SettingsRepository {
  final Preferences _prefs;

  SettingsRepository(this._prefs);

  // ===== Engine + endpoints ===== //

  EngineState loadEngineState() {
    final active = EngineKind.fromStorageKey(_prefs.getString(PrefKeys.activeEngine));

    return EngineState(
      active: active,
      endpoints: {
        EngineKind.forge: EngineEndpoint(
          kind: EngineKind.forge,
          host: _prefs.getString(PrefKeys.forgeHost) ?? '127.0.0.1',
          port: _prefs.getString(PrefKeys.forgePort) ?? EngineKind.forge.defaultPort,
        ),
        EngineKind.comfy: EngineEndpoint(
          kind: EngineKind.comfy,
          host: _prefs.getString(PrefKeys.comfyHost) ?? '127.0.0.1',
          port: _prefs.getString(PrefKeys.comfyPort) ?? EngineKind.comfy.defaultPort,
        ),
      },
    );
  }

  Future<void> saveEngineState(EngineState state) async {
    await _prefs.setString(PrefKeys.activeEngine, state.active.storageKey);

    final forge = state.endpoints[EngineKind.forge];
    if (forge != null) {
      await _prefs.setString(PrefKeys.forgeHost, forge.host);
      await _prefs.setString(PrefKeys.forgePort, forge.port);
    }

    final comfy = state.endpoints[EngineKind.comfy];
    if (comfy != null) {
      await _prefs.setString(PrefKeys.comfyHost, comfy.host);
      await _prefs.setString(PrefKeys.comfyPort, comfy.port);
    }
  }

  // ===== Sampling ===== //

  /// Reads the sampling defaults. Falls back to the individual legacy keys
  /// the old build wrote, so an existing install keeps its settings on first
  /// launch after the rebuild instead of silently resetting to defaults.
  SamplingParams loadSampling() {
    return SamplingParams(
      maskBlur: _prefs.getInt(PrefKeys.maskBlur) ?? 8,
      maskFill: _maskFillFromLegacy(_prefs.getString(PrefKeys.maskFill)),
      batchSize: _prefs.getInt(PrefKeys.batchSize) ?? 1,
    );
  }

  Future<void> saveSampling(SamplingParams params) async {
    await _prefs.setInt(PrefKeys.maskBlur, params.maskBlur);
    await _prefs.setString(PrefKeys.maskFill, params.maskFill.name);
    await _prefs.setInt(PrefKeys.batchSize, params.batchSize);
  }

  /// The old build stored this as A1111's own wording.
  static MaskFill _maskFillFromLegacy(String? value) => switch (value) {
        'original' => MaskFill.original,
        'latent noise' || 'latentNoise' => MaskFill.latentNoise,
        'latent nothing' || 'latentNothing' => MaskFill.latentNothing,
        _ => MaskFill.fill,
      };

  // ===== Prompts ===== //

  String loadNegativePrompt() => _prefs.getString(PrefKeys.negativePrompt) ?? '';

  Future<void> saveNegativePrompt(String value) =>
      _prefs.setString(PrefKeys.negativePrompt, value);

  String loadRewriteModel() =>
      _prefs.getString(PrefKeys.routerModel) ??
      'arcee-ai/trinity-large-preview:free';

  Future<void> saveRewriteModel(String value) =>
      _prefs.setString(PrefKeys.routerModel, value);

  // ===== Prompt book ===== //

  PromptBookState loadPromptBook() => PromptBookState(
        history: _prefs.getStringList(PrefKeys.promptHistory) ?? const [],
        favourites:
            (_prefs.getStringList(PrefKeys.promptFavourites) ?? const []).toSet(),
      );

  Future<void> savePromptBook(PromptBookState state) async {
    await _prefs.setStringList(PrefKeys.promptHistory, state.history);
    await _prefs.setStringList(
        PrefKeys.promptFavourites, state.favourites.toList());
  }
}
