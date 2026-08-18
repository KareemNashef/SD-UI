# Aperture — Feature Inventory

Everything the app does, sorted by how fundamental it is. **Tier 1 is the
spine** — without it there is no app. Each tier down is progressively more
optional. This is the order the UI gets rebuilt in.

All logic listed here already lives in `lib/logic/` and is UI-free. The old
interface is preserved in `lib_OLD/` for reference only (excluded from
analysis, never compiled).

Legend: **F** = Forge Neo only · **C** = ComfyUI only · **F+C** = both

---

## Tier 1 — The spine
*Nothing works without these. Build first, in this order.*

### 1.1 Server connection & reachability — **F+C**
Point the app at a self-hosted server, verify it responds, remember the
address. Forge and ComfyUI addresses are stored **separately** so switching
engines never clobbers the other one's last-used address.
- `logic/backend/server_profile.dart` — scheme/host/port/basePath → URIs (`httpUri`, `wsUri`)
- `logic/api_calls.dart` → `checkServerStatus()`
- `logic/storage/storage_service.dart` — persists both addresses
- `logic/startup/backend_startup.dart` → `loadActiveBackendProfile()`
- State: `globalServerStatus`, `globalServerIP/Port`, `globalComfyServerIP/Port`

### 1.2 Engine selection (exactly one active) — **F+C**
Hard rule: one backend active at a time, and which one must never be
ambiguous. Switching clears stale connection state and reloads that
engine's profile data.
- `logic/backend/backend_kind.dart` — the `BackendKind` enum + display names
- `logic/backend/backend_manager.dart` → `switchTo()`, holds both instances
- `logic/backend/image_backend.dart` — the shared contract both implement
- `logic/backend/backend_capabilities.dart` — 15 feature flags; **the UI reads these, never `if (isComfy)`**
- State: `globalActiveBackendKind`

### 1.3 Prompt entry — **F+C**
Positive and negative prompt text. The single most-used input in the app.
- State: `globalPositivePrompt`, `globalNegativePrompt` (`logic/globals.dart`)

### 1.4 Generate — **F+C**
The core action. Routes to whichever engine is active, handles txt2img /
img2img / inpainting, returns results.
- `logic/generation_logic.dart` → `GenerationLogic.generate()` (the front door)
- `logic/backend/forge_backend.dart` → `generate()` — A1111 REST
- `logic/backend/comfy_backend.dart` → `generate()` — graph convert → `/prompt` → `/history`
- `logic/models/generation_models.dart` — `GenerationRequest`, `GenerationOutcome`, `GeneratedImage`, `BackendException`

### 1.5 Live progress & preview — **F+C**
Percent, step counts, current node, queue position, and streamed preview
frames mid-generation. Two very different transports behind one model.
- `logic/services/progress_service.dart` — **F**: polls `/sdapi/v1/progress`
- `logic/comfy/comfy_progress_service.dart` — **C**: WebSocket (`status`, `execution_start`, `executing`, `progress`, `execution_success`, binary PREVIEW_IMAGE frames) + forced-fresh reconnect per run
- `logic/models/generation_models.dart` → `GenerationProgress`, `GenerationState`
- State: `globalIsGenerating`, `globalProgressData`

### 1.6 Results — **F+C**
Generated images accumulate in a session list with enough metadata to
inspect or reuse them later.
- State: `globalResultImages` (`ValueNotifier<List<GeneratedImage>>`)
- `GeneratedImage` carries: backend, promptId, workflowId, output node, comfy filename/subfolder/type, prompt snapshots, createdAt

### 1.7 Cancel a running generation — **F+C**
- `logic/api_calls.dart` → `interruptGeneration()`; both backends implement `interruptGeneration()`

---

## Tier 2 — Image input & the canvas
*Required for img2img and inpainting, i.e. most real use.*

### 2.1 Image upload
Pick a source image from the device gallery.
- State: `globalInputImage` (`ValueNotifier<File?>`)

### 2.2 Mask painting (inpaint)
Brush/erase strokes over the image to mark the region to regenerate.
- `logic/models/drawing_models.dart` — `DrawingPath`, `DrawingPoint`, `DrawingMode`
- `logic/drawing/drawing_coordinates.dart` → screen↔image coordinate mapping
- `logic/drawing/mask_generator.dart` → `generateDrawingMask()` — strokes → black/white PNG mask
- Comfy note: `comfy_backend.dart` `_embedMaskAsAlpha()` bakes the mask into the uploaded PNG's alpha, since ComfyUI's `LoadImage` derives MASK from alpha

### 2.3 Outpainting
Drag out from the edges to extend the canvas; generates the padded image
plus its matching mask.
- `logic/image/image_processor.dart` → `generateOutpaintData()`

### 2.4 Send an existing result back to the canvas
- State: `globalImageToEdit`

---

## Tier 3 — Steering the output
*What you reach for on almost every generation after the prompt.*

### 3.1 Checkpoint selection & switching — **F**
Browse installed models, switch the loaded one, grouped by base model.
- `logic/api_calls.dart` → `syncCheckpointDataFromServer()`, `setCheckpoint()`, `applyCheckpointConfiguration()`
- `logic/models/checkpoint_data.dart`, `logic/backend/checkpoint_utils.dart`
- `logic/utils/checkpoint_organizer.dart` → grouping/sorting by base model
- State: `globalCurrentCheckpointName`, `globalCheckpointDataMap`

### 3.2 Workflow selection & switching — **C**
The ComfyUI equivalent of picking a checkpoint.
- `logic/comfy/comfy_workflow_service.dart` → `selectWorkflow()`, `activeRecord`, `workflows`

### 3.3 Generation parameters — **F+C**
Steps, CFG, denoise, resolution, batch size, sampler, scheduler, mask blur,
mask fill. Which of these apply depends on backend and workflow type.
- State in `logic/globals.dart`; `syncActiveCheckpointSettings()` loads per-checkpoint defaults
- `logic/utils/sampler_names.dart`, `logic/utils/scheduler_names.dart`
- **C**: the same knobs come from `workflow_auto_detector.dart` instead

### 3.4 Per-checkpoint remembered defaults — **F**
Each checkpoint remembers its own steps/CFG/sampler/scheduler/resolution
and restores them on switch.
- `logic/models/checkpoint_data.dart`; persisted via `StorageService.saveCheckpointDataMap()`

### 3.5 LoRA selection — **F**
Browse LoRAs, set per-LoRA weights, pick trigger tags; compiled into the
prompt at generation time.
- `logic/models/lora_data.dart`, `logic/api_calls.dart` → `loadLoraDataFromServer()`
- `logic/generation_logic.dart` → `buildLoraPromptAddition()`
- State: `globalLoraDataMap`, `globalSelectedLoras`, `globalSelectedLoraTags`

---

## Tier 4 — ComfyUI workflow system
*The whole reason ComfyUI support exists. Self-contained subsystem.*

### 4.1 Workflow import + type declaration — **C**
Import an editor-exported JSON graph; user declares txt2img / img2img /
inpainting so the canvas knows what inputs to present.
- `logic/comfy/comfy_workflow.dart` — parse/validate/clone the editor document
- `logic/comfy/comfy_workflow_type.dart` — `needsInputImage`, `needsMask`
- `logic/comfy/comfy_workflow_service.dart` → `importWorkflow()`

### 4.2 Automatic setting detection — **C**
Walks the graph structurally (no per-node-type hardcoding) to find the
prompt, image, model/CLIP/VAE loaders, sampler params and latent size —
so any custom node pack works without special-casing.
- `logic/comfy/workflow_auto_detector.dart` — the big one: chain tracing, bypass resolution, resolution-selector unwrapping, zeroed-negative collapsing, seed `control_after_generate` handling
- `logic/comfy/comfy_node_schema.dart` — widget-slot alignment (incl. the name-convention seed rule)
- `logic/comfy/comfy_object_info_client.dart` — live `/object_info` schema fetch + cache

### 4.3 Editing detected settings — **C**
Change model/CLIP/VAE/sampler/latent values; toggle seed Fixed/Random.
- `logic/comfy/comfy_workflow_service.dart` → `updateDetectedSettingValue()`, `updateSeedRandomFlag()`

### 4.4 Graph → API conversion — **C**
Editor graph → ComfyUI `/prompt` API graph, resolving links, bypasses and
widget overrides.
- `logic/comfy/comfy_graph_converter.dart`

### 4.5 Workflow management — **C**
Rename, duplicate, delete, persist per server.
- `logic/comfy/comfy_workflow_service.dart`, `logic/storage/comfy_storage_service.dart`

---

## Tier 5 — Post-generation tools
*Acting on an image you already have.*

### 5.1 Save to device
Writes to `/storage/emulated/0/Download`.

### 5.2 Crop / Resize — **F+C**
Local image manipulation, no server involved.
- `logic/image/image_processor.dart`

### 5.3 Upscale (SeedVR2) — **F+C**
Same UI contract (image + target resolution) via two very different paths.
- **F**: `forge_backend.dart` → `upscaleSeedVR2()` — dedicated endpoint + progress poll
- **C**: `comfy_backend.dart` → `upscaleSeedVR2()` — bundled `assets/comfy/seedvr2_upscale.json`

### 5.4 Image stitching — **F**
Composite extra images via the A1111 alwayson script.
- `forge_backend.dart` generate path, `stitchImagesBase64`

### 5.5 Metadata inspection — **F+C**
- **F**: `logic/api_calls.dart` → `postPngInfo()` + `logic/utils/image_metadata_parser.dart`
- **C**: locally-retained snapshots on `GeneratedImage` (no universal PNG-info contract)

### 5.6 Compare against the input image
Hold-to-compare the result with the source. State already present via `globalInputImage`.

---

## Tier 6 — Prompt intelligence
*Quality-of-life around writing prompts.*

### 6.1 Prompt history & favorites — **F+C**
- `logic/prompt/prompt_intelligence.dart` → frequency analysis of prompt fragments
- State: `globalInpaintHistory`, `globalFavoritePrompts`; persisted via `StorageService.saveInpaintHistory()`

### 6.2 Prompt composition from known elements
Build a prompt from previously-used comma-separated fragments, ranked by
how often you've used them.
- `PromptIntelligence.analyzeHistory()`, `getFrequentElements()`

### 6.3 Prompt optimization — **F**
Rewrite via OpenRouter (user-configurable model).
- `forge_backend.dart` → `optimizePrompt()`; state `globalRouterModel`

### 6.4 Prompt enhance — **C**
Rewrite via a bundled QwenVL GGUF workflow.
- `comfy_backend.dart` → `enhancePrompt()`, `assets/comfy/prompt_enhance.json`

### 6.5 Image → prompt (describe) — **C**
Caption any picked image into the prompt field.
- `comfy_backend.dart` → `describeImage()`, `assets/comfy/img2prompt.json`

---

## Tier 7 — Power tools
*Rarely used, but valuable when needed.*

### 7.1 Server gallery browser — **C**
Browse the server's whole output folder (tested against 11,000+ images):
date-grouped, searchable, jump-to-date, multi-select to pull images back
into the local results list.
- `logic/comfy/comfy_gallery_client.dart` — ComfyUI-Gallery addon API, isolate-parsed, cached per server

### 7.2 Checkpoint / sampler test lab — **F**
Batch-generate the same prompt across many checkpoints or samplers to
compare them.
- `logic/services/checkpoint_testing_service.dart`, `logic/utils/test_mode.dart`
- State: `globalIsCheckpointTesting`, `globalCurrentTestingCheckpoint`, `globalCurrentCheckpointTestIndex`, `globalTotalCheckpointsToTest`

### 7.3 Checkpoint metadata editing — **F**
Attach a preview image URL and base-model label to a checkpoint.

### 7.4 Forge module selection (VAE / text encoders) — **F**
- `logic/api_calls.dart` → `fetchForgeModules()`, `applyCheckpointConfiguration()`

---

## Capability matrix

`BackendCapabilities` (`logic/backend/backend_capabilities.dart`) is the
**single source of truth** for what shows up. The UI must gate on these
flags, never on the backend enum.

| Flag | Forge | Comfy |
|---|:--:|:--:|
| `checkpoints` | ✅ | — |
| `workflows` | — | ✅ |
| `loras` | ✅ | — |
| `promptOptimizer` | ✅ | — |
| `metadata` | ✅ | — |
| `imageUpload` | ✅ | ✅ |
| `masks` | ✅ | ✅ |
| `livePreview` | — | ✅ |
| `upscale` | ✅ | ✅ |
| `stitching` | ✅ | — |
| `testing` | ✅ | — |
| `interrupt` | ✅ | ✅ |
| `serverLibrary` | — | ✅ |
| `promptEnhance` | — | ✅ |
| `imageToText` | — | ✅ |

---

## Known debt to fix during the rebuild

1. **`globals.dart` is a 200-line grab bag** of loose mutable globals and
   `ValueNotifier`s. It works, but it's the reason state changes need
   whole-subtree remounts. Worth replacing with scoped controllers as each
   feature's UI is built — incrementally, not as a big bang.
2. **Plain mutable globals** (`globalCurrentSamplingSteps` and friends) are
   not observable, so the UI can't react to them; today that's papered over
   with manual `setState`.
3. **No UI-layer tests.** The 36 existing tests all cover the logic layer.
   Worth adding widget tests as components land.
