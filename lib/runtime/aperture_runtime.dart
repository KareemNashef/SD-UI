// ==================== Aperture Runtime ==================== //

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/diagnostics.dart';
import 'package:sd_companion/core/result.dart';
import 'package:sd_companion/domain/engine/image_engine.dart';
import 'package:sd_companion/domain/generation/generated_image.dart';
import 'package:sd_companion/domain/generation/run_progress.dart';
import 'package:sd_companion/runtime/engine_registry.dart';
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

  final EngineRegistry engines;

  final EngineStore engine;
  final SessionStore session;
  final RunStore run;
  final LibraryStore library;
  final CatalogStore catalog;
  final PromptBookStore promptBook;

  ApertureRuntime._({
    required this.preferences,
    required this.settings,
    required this.engines,
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
      engines: EngineRegistry(),
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

  // ===== Generation ===== //

  /// The engine backing whichever kind is currently selected.
  ImageEngine get activeEngine => engines.of(engine.state.endpoint);

  /// Runs one generation, start to finish, keeping every store in step.
  ///
  /// This is the single place a run is orchestrated. Previously the same
  /// sequence - build the request, flip the busy flag, poll progress, append
  /// results, record the prompt, clear the flag - was open-coded in the
  /// generate button's `onPressed`, which is why a thrown error left the UI
  /// stuck "generating" forever. Here the store transitions are structural:
  /// the run cannot end without [RunStore] being told how it ended.
  Future<Result<List<GeneratedImage>>> submit() async {
    // Claimed synchronously, before the first await. Checking
    // `run.state.isActive` instead would leave a window: building the spec
    // is async, so a double-tap on Generate gets through the check twice
    // before either run has begun, and fires two generations.
    if (_submitting) {
      return const Err(ValidationError('A generation is already running'));
    }
    _submitting = true;
    try {
      return await _submit();
    } finally {
      _submitting = false;
    }
  }

  bool _submitting = false;

  Future<Result<List<GeneratedImage>>> _submit() async {
    final spec = (await session.toSpec()).copyWith(
      prompt: [session.state.prompt, catalog.buildPromptFragment()]
          .where((part) => part.isNotEmpty)
          .join(''),
      checkpoint: catalog.state.active,
    );

    trace('submit', 'BEGIN $spec');
    run.begin(spec);
    final engineInstance = activeEngine;

    // Mirror engine progress into the store for as long as this run lasts,
    // but only the *in-flight* frames. How a run ends is decided here, from
    // generate()'s Result - never by a stream frame. Letting terminal
    // phases through meant any stray `completed`/`idle` frame (e.g. a
    // stale one emitted as the socket opened) flipped the store inactive
    // mid-run, after which RunStore's late-frame guard correctly - and
    // permanently - dropped every real update that followed.
    final subscription = engineInstance.progress.listen((progress) {
      if (progress.isFinished) {
        trace('submit', 'ignoring terminal ${progress.phase.name} from stream');
        return;
      }
      run.report(progress);
    });

    final result = await engineInstance.generate(spec);
    await subscription.cancel();
    trace('submit', 'generate() returned ok=${result.isOk}');

    return result.fold(
      (images) {
        library.add(images);
        promptBook.record(spec.prompt);
        run.succeed();
        return Ok(images);
      },
      (error) {
        run.fail(error);
        return Err(error);
      },
    );
  }

  /// Interrupts the run in flight.
  Future<Result<void>> cancelRun() async {
    final result = await activeEngine.cancel();
    run.report(const RunProgress(phase: RunPhase.cancelled));
    return result;
  }

  /// A runtime with no persistence, for tests and the dev harness.
  @visibleForTesting
  static ApertureRuntime forTesting({
    EngineState? engineState,
    SessionState? sessionState,
    EngineRegistry? engines,
  }) {
    final prefs = _NullPreferences();
    final settings = SettingsRepository(prefs);
    final runtime = ApertureRuntime._(
      preferences: prefs,
      settings: settings,
      engines: engines ?? EngineRegistry(),
      engine: EngineStore(engineState ?? EngineState.initial()),
      session: SessionStore(sessionState ?? const SessionState()),
      run: RunStore(),
      library: LibraryStore(),
      catalog: CatalogStore(),
      promptBook: PromptBookStore(),
    );
    runtime._wire();
    return runtime;
  }

  Future<void> dispose() async {
    await engines.dispose();
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
