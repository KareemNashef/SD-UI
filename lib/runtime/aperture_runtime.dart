// ==================== Aperture Runtime ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/data/persistence/preferences.dart';
import 'package:sd_companion/data/persistence/settings_repository.dart';
import 'package:sd_companion/state/catalog_store.dart';
import 'package:sd_companion/state/engine_store.dart';
import 'package:sd_companion/state/library_store.dart';
import 'package:sd_companion/state/prompt_book_store.dart';
import 'package:sd_companion/state/run_store.dart';
import 'package:sd_companion/state/session_store.dart';

/// Owns every store and service, and wires them together.
///
/// This replaces the previous arrangement of static singletons -
/// `BackendManager.instance`, `ComfyWorkflowService.instance`,
/// `ProgressService()`, and an all-static `StorageService`. Those could
/// never be substituted, so nothing that touched them was testable, and
/// their construction order was implicit in whichever file happened to
/// import them first.
///
/// Here construction is explicit and ordered, everything is an instance, and
/// a test can build a runtime against in-memory preferences.
class ApertureRuntime {
  final Preferences preferences;
  final SettingsRepository settings;

  final EngineStore engine;
  final SessionStore session;
  final RunStore run;
  final LibraryStore library;
  final CatalogStore catalog;
  final PromptBookStore promptBook;

  ApertureRuntime._({
    required this.preferences,
    required this.settings,
    required this.engine,
    required this.session,
    required this.run,
    required this.library,
    required this.catalog,
    required this.promptBook,
  });

  /// Builds a runtime and restores persisted state into it.
  ///
  /// Everything a store needs is passed in, so the order of construction is
  /// visible here rather than emerging from import side effects.
  static Future<ApertureRuntime> boot({Preferences? preferences}) async {
    final prefs = preferences ?? await Preferences.open();
    final settings = SettingsRepository(prefs);

    final engine = EngineStore(settings.loadEngineState());

    final session = SessionStore(SessionState(
      negativePrompt: settings.loadNegativePrompt(),
      sampling: settings.loadSampling(),
    ));

    // The prompt book persists itself whenever it changes, so no call site
    // has to remember to save after recording a prompt - which is exactly
    // the bug the old `saveInpaintHistory()`-by-hand pattern kept producing.
    late final PromptBookStore promptBook;
    promptBook = PromptBookStore(
      onChanged: () => settings.savePromptBook(promptBook.state),
    );
    promptBook.hydrate(settings.loadPromptBook());

    final runtime = ApertureRuntime._(
      preferences: prefs,
      settings: settings,
      engine: engine,
      session: session,
      run: RunStore(),
      library: LibraryStore(),
      catalog: CatalogStore(),
      promptBook: promptBook,
    );

    runtime._wire();
    return runtime;
  }

  /// Cross-store reactions live here, in one readable place, instead of
  /// being scattered as listeners attached from whichever widget noticed it
  /// needed them.
  void _wire() {
    // Persist engine selection and addresses whenever they change.
    engine.addListener(() => settings.saveEngineState(engine.state));

    // Persist the settings the user tunes in the session.
    session.addListener(() {
      settings.saveSampling(session.state.sampling);
      settings.saveNegativePrompt(session.state.negativePrompt);
    });
  }

  /// A runtime with no persistence, for tests and the dev harness.
  @visibleForTesting
  static ApertureRuntime forTesting({
    EngineState? engineState,
    SessionState? sessionState,
  }) {
    final prefs = _NullPreferences();
    final settings = SettingsRepository(prefs);
    return ApertureRuntime._(
      preferences: prefs,
      settings: settings,
      engine: EngineStore(engineState ?? EngineState.initial()),
      session: SessionStore(sessionState ?? const SessionState()),
      run: RunStore(),
      library: LibraryStore(),
      catalog: CatalogStore(),
      promptBook: PromptBookStore(),
    );
  }

  void dispose() {
    engine.dispose();
    session.dispose();
    run.dispose();
    library.dispose();
    catalog.dispose();
    promptBook.dispose();
  }
}

/// In-memory stand-in so a runtime can be built without touching the device.
class _NullPreferences implements Preferences {
  final Map<String, Object> _values = {};

  @override
  bool contains(String key) => _values.containsKey(key);

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  List<String>? getStringList(String key) => _values[key] as List<String>?;

  @override
  Map<String, dynamic>? getJson(String key) =>
      _values[key] as Map<String, dynamic>?;

  @override
  List<dynamic>? getJsonList(String key) => _values[key] as List<dynamic>?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _values[key] = value;

  @override
  Future<Result<void>> setJson(String key, Object value) async {
    _values[key] = value;
    return const Ok(null);
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
