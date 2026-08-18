# Aperture — Architecture

The framework the rebuilt UI is built on. This document is the map: what
each folder is for, what lives in it, and how the UI will attach to it.

---

## The diagnosis

The old logic layer began as a handful of globals for a single-feature app
and accreted from there. Measured before the rewrite:

| Problem | Evidence |
| --- | --- |
| **A god module** | `globals.dart` held 43 top-level symbols and was imported by 11 of 38 files |
| **Half-observable state** | 20 values were plain mutable globals the UI *could not* react to; ~15 were `ValueNotifier`s it could. The split was arbitrary |
| **Engines read ambient state** | `ForgeBackend.generate()` ignored most of its argument and reached into **15 globals** for prompt, sampler, size, steps, CFG, denoise, mask settings, batch size |
| **No error model** | Failures arrived as `Exception` (12), `BackendException` (16), `StateError` (3), plus two bespoke types. Callers guessed |
| **Untestable singletons** | `BackendManager.instance`, `ComfyWorkflowService.instance`, `ProgressService()`, all-static `StorageService` — none substitutable |
| **Save-by-remembering** | Persistence fired only when a call site remembered to call `saveInpaintHistory()` afterwards |

The third row is the one that caused real damage: because the engine read
globals rather than its argument, a run could not be reproduced, an engine
could not be unit-tested, and no call site could tell what a generation
would actually do.

---

## The shape

Dependencies point **downward only**. Nothing below knows about anything
above it.

```
        ui/          Flutter widgets. Knows about state + domain.
         │
      runtime/       Owns and wires everything. Knows about all layers.
         │
       state/        Observable app state. Knows domain + core.
         │
        data/        I/O: engines, persistence. Knows domain + core.
         │
      domain/        Pure models + contracts. Knows core only.
         │
        core/        Framework primitives. Knows nothing.
```

---

## `lib/core/` — framework primitives

Feature-agnostic. No app knowledge at all.

| File | What it is |
| --- | --- |
| `app_error.dart` | Sealed `AppError` taxonomy: `UnreachableError`, `TimeoutError`, `ServerError`, `ValidationError`, `ExecutionError`, `CapabilityError`, `StorageError`, `CancelledError`, `UnknownError`. Plus `describeError()`, which maps a thrown object onto the taxonomy at an I/O boundary |
| `result.dart` | `Result<T>` = `Ok<T>` \| `Err<T>`, with `fold`/`map`/`flatMap`/`orElse`. `guard()` and `guardSync()` convert throwing code into Results in one place |
| `store.dart` | `Store<S>` — immutable state + `ChangeNotifier` + `ValueListenable`. Equality-guarded `emit()`. Also `ValueStore<T>` for scalars and `StoreGroup` for watching several at once |

**Why `Store` implements `ValueListenable`:** it drops straight into
`ValueListenableBuilder` with no adapter and no third-party state package.
Zero new dependencies.

**Why equality-guarded:** without it, every emit rebuilds every listener.
The guard is also why *every field must appear in a state class's `==`* — a
field left out of equality is a field whose changes get silently swallowed.
A test caught exactly this in `CatalogState.loraTags` during the build.

---

## `lib/domain/` — pure models and contracts

No I/O, no widgets. Safe to unit-test with no setup.

### `domain/engine/`
| File | What it is |
| --- | --- |
| `engine_kind.dart` | `EngineKind.forge` / `.comfy`, with label, storage key, default port |
| `engine_capabilities.dart` | 14 feature flags. **The UI gates on these, never on `EngineKind`** |
| `engine_endpoint.dart` | Where an engine lives. Builds `http`/`ws` URIs. Each engine keeps its own, so switching never loses the other address |
| `image_engine.dart` | The `ImageEngine` contract + optional capability interfaces (`PromptRewriteCapable`, `ImageToTextCapable`, `UpscaleCapable`) |

### `domain/generation/`
| File | What it is |
| --- | --- |
| `generation_spec.dart` | **The central fix.** A complete, self-contained description of one run. Engines read nothing else |
| `sampling_params.dart` | The nine loose globals, as one immutable value. Plus `MaskFill` |
| `run_progress.dart` | `RunProgress` + `RunPhase`. One shape both transports report into |
| `generated_image.dart` | A produced image. Engine-specific provenance grouped into `ComfyOrigin` rather than loose on the class |

### `domain/catalog/`
| File | What it is |
| --- | --- |
| `checkpoint.dart` | A model, with its remembered `SamplingParams` defaults |
| `lora.dart` | A LoRA. Deliberately holds **no selection state** — that is session state |

---

## `lib/data/` — I/O

| Folder | What it is |
| --- | --- |
| `persistence/preferences.dart` | Typed `SharedPreferences` wrapper, an ordinary object so tests can substitute it. All keys in `PrefKeys`, **verified against the strings already on users' devices** so the rebuild doesn't orphan saved data |
| `persistence/settings_repository.dart` | Talks in domain types: "give me the engine state", not "read five strings". Includes fallbacks that read the old build's individual keys |
| `persistence/comfy_workflow_storage.dart` | Saved ComfyUI workflows, namespaced by endpoint id so two servers can't see each other's |
| `engines/forge/forge_engine.dart` | A1111/Forge Neo `ImageEngine`. Owns **one** progress poll loop and publishes into the same `Stream` ComfyUI does |
| `engines/forge/forge_catalog_client.dart` | Checkpoints, LoRAs, VAE modules, PNG info. Pure queries returning domain values — it never writes to a store or persists |
| `engines/comfy/comfy_engine.dart` | ComfyUI `ImageEngine`, plus the three optional capability mixins (rewrite, describe, upscale) |
| `engines/comfy/*` | Graph converter, auto-detector, node schema, gallery client, WebSocket progress. Pure and well-tested; moved unchanged |
| `imaging/` | Mask generation, image processing, PNG metadata parsing |

---

## `lib/state/` — observable app state

One store per concern. This is what replaces `globals.dart`.

| Store | Owns | Replaces |
| --- | --- | --- |
| `EngineStore` | Active engine, both endpoints, connection status. **Capabilities are derived, never stored**, so they cannot drift | `globalActiveBackendKind`, `globalServerIP/Port`, `globalComfyServerIP/Port`, `globalServerStatus` |
| `SessionStore` | Prompt, source image, mask, sampling params, engine extras. Can produce a `GenerationSpec` | 12 globals incl. `globalPositivePrompt`, `globalCurrentSamplingSteps`, `globalMaskBlur` |
| `RunStore` | The run in flight: phase, progress, the spec that started it, failure | `globalIsGenerating`, `globalProgressData`, and two separate progress services |
| `LibraryStore` | Results + which one is selected | `globalResultImages` + selection that lived in widget State |
| `CatalogStore` | Checkpoints, LoRAs, selections. Builds the `<lora:…>` prompt fragment | `globalCheckpointDataMap`, `globalCurrentCheckpointName`, `globalLoraDataMap`, `globalSelectedLoras`, `globalSelectedLoraTags` |
| `PromptBookStore` | History + favourites + ranked fragments. Self-persists via `onChanged` | `globalInpaintHistory`, `globalFavoritePrompts` |

### Invariants the stores enforce that globals could not

- Switching engines **clears connection status** — no stale "connected" badge
- Each engine **keeps its own address** across a switch
- Dropping the source image **also drops the mask** — no mismatched pairs
- A finished run **ignores late progress frames** — this was the direct cause of the "stuck on STARTING" bug
- Removing the selected image **moves selection to a neighbour**, never dangles
- A vanished checkpoint **falls back** instead of leaving a dangling name
- Prompt history is **capped at 300** — the old `Set` grew without bound

---

## `lib/runtime/` — wiring

| File | What it is |
| --- | --- |
| `aperture_runtime.dart` | Owns every store, the registry and the repository. Explicit, ordered construction. `boot()` restores persisted state; `forTesting()` builds one against in-memory preferences. Also owns `submit()` and `cancelRun()` |
| `engine_registry.dart` | One live engine per endpoint, rebuilt on address change. Not a singleton — the runtime owns it, so a test can inject fakes |
| `runtime_scope.dart` | `InheritedWidget` exposing the runtime. `RuntimeScope.of(context)` |
| `app_navigation.dart` | UI-agnostic navigation intent bus |

### `submit()` — the one place a run is orchestrated

Build spec → `run.begin` → subscribe to engine progress → `generate` →
append to library, record the prompt, `run.succeed` / `run.fail`.

Previously this sequence was open-coded inside the generate button's
`onPressed`, which is why a thrown error left the UI stuck "generating"
forever. Here the run cannot end without `RunStore` being told how it ended,
because that is the only path out of the function.

Cross-store reactions live in `_wire()` — one readable place, rather than
listeners attached from whichever widget happened to notice it needed one.

---

## `lib/ui/` — the interface

| Folder | What it is |
| --- | --- |
| `glass/glass_tokens.dart` | `Palette`, `Radii`, `Space`, `Motion`, `Type`, `GlassWeight` — DESIGN.md as code. All `const`; **no mutable theme statics**, so nothing needs remounting on engine change |
| `glass/glass_shader.dart` | Loads and caches the compiled fragment program. `isAvailable` is the honest capability gate |
| `glass/liquid_glass.dart` | The material. Real `ImageFilter.shader` refraction when Impeller is present; plain blur fallback when it isn't |
| `dev/dev_harness.dart` | On-device test surface. **Debug builds only** |
| `dev/glass_lab.dart` | Every glass weight over live moving colour |
| `dev/state_inspector.dart` | Live readouts of every store, with controls that mutate them |

---

## How the UI attaches

The pattern is the same everywhere, and it is the whole point of the
rewrite — a widget subscribes to a store and calls a method. No globals, no
`setState` for app state, no remounting.

```dart
// Read + rebuild on change
ValueListenableBuilder<SessionState>(
  valueListenable: RuntimeScope.of(context).session,
  builder: (context, session, _) => Text(session.prompt),
)

// Write
RuntimeScope.read(context).session.setPrompt('golden hour');

// Gate on capability, never on engine kind
if (RuntimeScope.of(context).engine.capabilities.loras) ...
```

Mapping to the screens in DESIGN.md:

| Surface | Reads | Writes |
| --- | --- | --- |
| **Rail** | `EngineStore`, `CatalogStore` | opens Context sheet |
| **Stage** | `LibraryStore.selected`, `RunStore.progress`, `SessionStore.sourceImage` | — |
| **Prompt bar** | `SessionStore.prompt`, capabilities | `setPrompt`, `record` |
| **Aperture** | `RunStore.phase` / `.progress` | `begin`, `cancel` |
| **Filmstrip** | `LibraryStore.images` | `select` |
| **Context sheet** | `CatalogStore`, `SessionStore.sampling` | `selectCheckpoint`, `tuneSampling` |
| **Gallery sheet** | `LibraryStore` | `select`, `remove` |

---

## Testing

102 tests, all passing.

| Suite | Covers |
| --- | --- |
| `test/core/result_test.dart` | Result algebra, `guard`, error mapping |
| `test/core/store_test.dart` | Store notification, **equality guard**, disposal safety, `StoreGroup` |
| `test/state/stores_test.dart` | Every store's invariants — the bug-shaped ones listed above |
| `test/runtime/runtime_test.dart` | Engine registry lifetime; `submit()` success, failure, progress mirroring and the double-tap guard |
| `test/domain/engine_endpoint_test.dart` | URL building, ws/wss derivation, endpoint identity, capability flags |
| `test/comfy/*` | The existing engine/graph/detector suites, still green |
| `test/widget_test.dart` | App boots; runtime reachable through the scope |

Three real defects were caught by these tests while writing them:

1. `CatalogState.loraTags` was missing from `==`, so the store's equality
   guard silently swallowed every tag change.
2. `LiquidGlass`'s interactive branch captured a mutable local in a closure,
   so an interactive pane rendered itself forever (stack overflow).
3. `submit()` checked `run.state.isActive` *after* awaiting spec construction,
   so a double-tap on Generate slipped two runs through the guard. Fixed with
   a claim taken before the first `await`.

None would have been obvious by reading the code.

---

## What is done, and what is next

**Done**
- `core/`, `domain/`, `state/`, `runtime/`, `data/` — every layer
- Both engines ported onto `ImageEngine`; **`lib/logic/` is gone entirely**,
  along with `globals.dart`, `api_calls.dart`, `generation_logic.dart`,
  `backend_manager.dart`, `storage_service.dart`, `image_backend.dart`,
  `server_profile.dart`, `backend_kind.dart` and the old `models/`
- `ui/glass/` — the material, on `liquid_glass_renderer`
- `ui/dev/` — three-tab on-device harness: Glass, Run (a real generation
  against a live ComfyUI server through the new architecture), State
- 102 tests green; debug APK builds

**Next**
Build the Stage, per the DESIGN.md build order. Every screen now has a store
to read from and a runtime method to call; no screen needs new plumbing.

Not yet ported, because no UI calls them today: the checkpoint-testing sweep
and the LoRA browser's grouping helpers. Both were thin wrappers over state
that `CatalogStore` now holds, so they get rebuilt with their screens rather
than carried across.
