# Implement ComfyUI Support

## Mission

Upgrade this Flutter Android app so it supports exactly one active server type at a time:

- Forge Neo, using the existing checkpoint/API behavior.
- ComfyUI, using user-provided ComfyUI workflow JSON and ComfyUI's execution API.

The server type must be obvious throughout the UI. The app may use a distinct accent, iconography, labels, and settings layout for Forge versus ComfyUI, but the user must never be left guessing which backend is active.

The implementation agent has full authority over the codebase. It may add packages, introduce new models/services, replace the current global-state architecture, refactor or rename existing files, redesign screens, and modify Android configuration wherever required. Do not preserve an existing abstraction merely because it already exists if it prevents a clean and reliable implementation. Preserve user-facing Forge behavior unless a change is required for the shared architecture.

The repository currently has uncommitted Forge-related edits. Inspect them, preserve their useful behavior, and modify any file necessary to complete this feature. Do not reset or discard unrelated user work.

## Requirements already decided

These are product requirements, not open questions:

1. The user imports the same workflow JSON exported from ComfyUI's web UI. The app must accept the normal editor/workflow export format used by the attached example.
2. The favorite section uses this shape and exact property names:

   ```json
   "favoritedWidgets": {
     "favorites": [
       {
         "nodeLocatorId": "84",
         "widgetName": "prompt"
       },
       {
         "nodeLocatorId": "72",
         "widgetName": "image"
       }
     ]
   }
   ```

3. Prompt and input-image widgets are explicitly favorited by the user. The app must not silently guess them from node types when the favorites are absent.
4. Negative prompts are supported only when the workflow exposes/favorites the relevant prompt widget(s). They use the same prompt area the Forge experience already provides.
5. The attached workflow is the reference fixture for the import and binding implementation.
6. Use ComfyUI live preview events when available. If live previews are unavailable, use the normal completed output image flow without failing the generation.
7. Use output nodes when they exist. If there are multiple image-producing output nodes, collect their image outputs. If no explicit output node can be identified, fall back to image outputs found in the completed history response.
8. Assume the user has already tested the workflow in ComfyUI and that its custom nodes/workflow are valid. Do not build a broad custom-node compatibility catalog or reject a workflow simply because it contains custom nodes.
9. Authentication and Comfy Cloud are out of scope. Target local/self-hosted ComfyUI only.
10. Save ComfyUI workflows and their current values in `SharedPreferences`, like the existing checkpoint settings are saved between app instances.
11. Generated ComfyUI results should retain the workflow/value context needed to reuse or inspect them, using the same local persistence strategy where practical.
12. The active server must be clearly marked as Forge Neo or ComfyUI in the connection UI, settings, and relevant generation/progress surfaces.

## Reference workflow findings

The attached file is not an API prompt graph. It is a normal ComfyUI editor export with these root fields:

```text
id, revision, last_node_id, last_link_id, nodes, links, groups,
config, extra, version
```

The fixture includes, among others:

- `29` — `SaveImage` output node.
- `53` — `KSampler`.
- `54` — `VAEDecode`.
- `55` — `UNETLoader`.
- `56` — `CLIPLoader`.
- `57` — `VAELoader`.
- `71` — `LoraLoaderModelOnly`.
- `72` — active `LoadImage` node with `image` widget.
- `84` — `Krea2EditGroundedEncode` with a prompt widget.
- `85` — another prompt/negative-prompt-capable node.
- `90` — an optional/bypassed second `LoadImage` node.

The node records contain `id`, `type`, `mode`, `inputs`, `outputs`, and `widgets_values`; links are stored separately. The app must retain node IDs, links, bypass modes, widget values, groups, and custom-node data when importing and saving the document.

Because `POST /prompt` expects ComfyUI's API graph (`node_id -> {class_type, inputs}`), the implementation must convert the imported editor graph to an API graph at generation time. Do not require the user to manually export a separate API-format file. Accepting API-format JSON as an additional compatibility path is allowed, but the attached editor format is the primary required input.

## Current codebase constraints to address

The current app is Forge-coupled end to end:

- `lib/logic/globals.dart` owns a single concrete `A1111Backend`, checkpoint globals, LoRA globals, and Forge-shaped progress state.
- `lib/logic/backend/a1111_backend.dart` combines Forge health checks, checkpoints, Forge modules, LoRAs, A1111 `img2img`, PNG info, SeedVR2, and interrupt.
- `lib/main.dart` always probes `sdapi/v1/sd-models`, loads checkpoint/LoRA caches, and synchronizes Forge data before showing the app.
- `lib/elements/settings/checkpoint_settings.dart` assumes checkpoint selection, sampler/scheduler, dimensions, per-checkpoint defaults, Forge VAE/text-encoder modules, and checkpoint switching.
- `lib/logic/generation_logic.dart` builds Forge prompt text and `<lora:...>` additions before calling a Forge-shaped generator.
- `lib/elements/ui/image_upload_container.dart` creates a mask, starts Forge polling, injects LoRAs into prompt text, and submits a fixed A1111/Forge `img2img` request.
- `lib/logic/services/progress_service.dart` polls `/sdapi/v1/progress` and reads A1111 state fields.
- `lib/elements/ui/progress_overlay.dart` renders Forge-only progress fields and base64 preview assumptions.
- `lib/elements/ui/results_carousel.dart` calls Forge `/png-info` and stores result images as strings.
- `lib/logic/storage/storage_service.dart` uses global, non-server-scoped keys.
- `test/widget_test.dart` is still the default counter test.

Do not implement ComfyUI by adding a few `if (isComfy)` branches inside `A1111Backend`. Introduce a backend boundary and make generation/progress/results/storage backend-neutral.

## Target architecture

### 1. Backend and server identity

Create a backend-neutral layer, using names that communicate intent clearly. The exact file names are up to the agent; the responsibilities are not.

Required concepts:

- `BackendKind`: `forge` or `comfy`.
- `ServerProfile`: backend kind, scheme, host, port, optional base path, and normalized profile ID.
- `BackendCapabilities`: feature flags for checkpoints, workflows, LoRAs, prompt optimizer, metadata, image upload, masks, live preview, upscale, stitching, testing, and interrupt.
- `ImageBackend` or equivalent interface for health check, generation, progress, interrupt, input upload, output retrieval, and optional backend features.
- `ForgeBackend`: the existing Forge implementation behind the interface.
- `ComfyBackend`: ComfyUI-specific implementation.
- A single backend manager/provider that exposes the active backend to the rest of the app.

The base URL must not be hardcoded as `http://IP:port` everywhere. Support `http`/`https` and derive `ws`/`wss` for ComfyUI. Keep local HTTP/WS as the default, since authentication is not required.

### 2. Visible backend selection and theming

Update the connection flow and system settings so the user can select and identify the backend:

- Backend selector: `Forge Neo` or `ComfyUI`.
- Large, explicit identity label and icon in the connection card.
- Persistent backend badge in system/settings UI.
- Backend-appropriate accent color and copy in settings/progress.
- No Forge wording such as “checkpoint” or “Forge modules” in the ComfyUI settings surface.
- No ComfyUI wording such as “workflow” in a Forge-only control unless it is genuinely shared.

When the backend changes, reload the appropriate profile data and never display stale checkpoint/LoRA state as if it belonged to ComfyUI. The connection screen may preserve the last selected backend and endpoint, but connection status must be revalidated.

Startup must branch:

- Forge: load/sync checkpoint metadata, checkpoint settings, LoRAs, and Forge generation preferences.
- ComfyUI: load saved workflows and active workflow values; do not call Forge model or LoRA endpoints.

### 3. SharedPreferences storage and profile isolation

Use `SharedPreferences` for ComfyUI workflows, as requested. Store an index and JSON records rather than relying on a picked file path:

- active backend and active server profile;
- Comfy workflow index;
- each workflow's imported JSON document, including `favoritedWidgets`;
- active workflow ID per Comfy profile;
- current widget values/overrides per workflow;
- result metadata needed for workflow reuse, if result persistence is added.

Namespace keys by backend/profile so a Forge connection and a ComfyUI connection cannot overwrite each other. A reasonable shape is:

```text
serverProfiles
activeServerProfileId
comfy.<profileId>.workflowIndex
comfy.<profileId>.workflow.<workflowId>
comfy.<profileId>.activeWorkflowId
```

Use a storage schema version. Migrate existing Forge keys into a Forge profile without deleting the old values until the migrated data is safely written. Handle malformed JSON and missing fields without crashing startup.

The saved workflow JSON should remain the source of truth. If the UI uses a separate in-memory normalized model, serialize the user's current favorite values back into the workflow record when they change or when the workflow is saved.

### 4. Workflow import and document model

Implement workflow management for ComfyUI:

- Android system file picker for `.json` files.
- Import, parse, validate, name, select, replace, duplicate, and delete workflows.
- Persist imported JSON in SharedPreferences.
- Keep the original editor-format fields intact; do not flatten the document and lose custom node metadata.
- Show the active workflow and its saved values in settings.

Accept the editor format in the attached fixture. Validate the minimum required shape:

- root object;
- `nodes` array;
- stable node IDs;
- node `type` values;
- `links` when present;
- `widgets_values` when present;
- `favoritedWidgets.favorites` array;
- every `nodeLocatorId` points to an existing node;
- every `widgetName` can be resolved or is reported as pending resolution.

Do not reject custom node types merely because the app does not know them. The server is the authority for whether the tested workflow can execute. If a favorite cannot be resolved, block generation with a precise message such as `Node 84: widget "prompt" could not be resolved`.

The parser should also accept a ComfyUI API-format graph as a bonus, but it must preserve/normalize favorites if present. This is not a substitute for editor-format support.

### 5. Exact favorites behavior

Use the exact favorites location:

```text
workflowJson.favoritedWidgets.favorites[]
```

Each favorite is a reference, not necessarily a complete value descriptor:

```text
nodeLocatorId -> node.id
widgetName    -> the ComfyUI widget name
```

The app must show controls only for widgets in this array. Never expose every widget in a node and never invent controls from common node types.

Build a `FavoriteWidgetResolver` that resolves a favorite reference to:

- node;
- widget name;
- widget type;
- current widget value;
- allowed values/range/step when discoverable;
- whether the widget is linked, bypassed, or unavailable;
- semantic role: positive prompt, negative prompt, input image, mask, LoRA/model/value, or generic favorite.

The normal editor export stores widget values in `widgets_values`, while the favorite stores `widgetName`. Do not assume `widgetName` is an array index. Resolve widget names using ComfyUI node definitions/runtime metadata and the same widget ordering rules used by the ComfyUI frontend, accounting for linked inputs, hidden inputs, and special widgets such as `control_after_generate`.

Use `GET /object_info` as runtime metadata when needed, but do not use it as a custom-node allowlist. If its metadata is insufficient for a custom widget, either reuse/port the relevant ComfyUI frontend graph/widget serialization behavior or surface a targeted unsupported-widget error.

Favorite control rules:

- Prompt widgets are edited from the existing prompt experience.
- Input-image widgets are edited from the existing image area.
- Negative prompt widgets use the existing negative prompt area when their graph role is negative.
- Other favorites become generated controls in the ComfyUI workflow settings section.
- A favorite LoRA/model/strength widget is supported naturally if it exists and resolves; there is no separate ComfyUI LoRA inventory call.
- A widget value change updates the active workflow's saved JSON/value state and survives app restart.
- Provide reset-to-imported-value and save behavior.
- Do not modify non-favorited widgets.

### 6. Prompt, negative prompt, and image binding

Prompt and input image are required to be favorited in the workflow JSON. The app must not auto-select a prompt or image node just because it sees `CLIPTextEncode` or `LoadImage`.

For each favorite with `widgetName == "prompt"`:

1. Resolve its node/widget.
2. Analyze graph links to determine whether it feeds a sampler's positive or negative conditioning input when possible.
3. Bind the positive role to the existing main prompt field.
4. Bind the negative role to the existing negative prompt field.
5. If the role cannot be determined and multiple prompt favorites exist, show a one-time binding choice using the node title/ID and save the chosen role with the workflow.

For each favorite with `widgetName == "image"`:

1. Resolve the node/widget.
2. Treat the first active image favorite as the primary input image used by the existing canvas.
3. If additional active image favorites exist, expose additional named image slots in the same image/input area instead of silently ignoring them. This supports workflows such as the attached fixture, which contains an optional second `LoadImage` node.
4. Respect bypassed/disabled nodes according to ComfyUI behavior; an inactive optional slot should not be uploaded or injected unless it becomes active.

Masks are only injected when the workflow explicitly exposes a favorited mask/image binding or a supported explicit mask binding. Do not force Forge's inpainting payload assumptions onto a ComfyUI graph.

If required prompt/image favorites are missing, display an actionable workflow error and prevent generation until the user fixes/reimports the workflow.

### 7. Editor workflow to ComfyUI API graph conversion

Implement a dedicated conversion layer. It is the most technically important part of this feature.

Responsibilities:

1. Clone the saved editor workflow for every generation. Never mutate the stored document while preparing a request.
2. Preserve node IDs, class/type names, bypass modes, links, widget values, and custom-node fields.
3. Resolve every link into API input references of the form `[sourceNodeId, outputIndex]`.
4. Convert widget values into named API inputs using the node's runtime definition and ComfyUI frontend ordering rules.
5. Apply the current favorite values only to their resolved widget inputs.
6. Apply current positive/negative prompt values to their resolved prompt inputs.
7. Upload input images/masks first, then apply the returned ComfyUI filenames/subfolders/types to their resolved LoadImage/LoadMask inputs.
8. Omit or preserve bypassed nodes exactly as ComfyUI's frontend does.
9. Produce the API graph expected by `POST /prompt`.
10. Keep a debug representation of the transformed graph for error reporting, but do not log user images or unnecessarily dump large workflow JSON in production logs.

Use the ComfyUI frontend behavior or a well-tested equivalent as the reference implementation for graph serialization. Do not build a small hardcoded mapper for `KSampler`, `LoadImage`, and `CLIPTextEncode`; the attached workflow already demonstrates custom nodes (`Krea2EditGroundedEncode`, `Krea2EditModelPatch`, and others), and the stated requirement is to run user-tested workflows.

The conversion layer must have fixture tests using the attached workflow. It must prove that node `84`/`prompt` and node `72`/`image` resolve to the correct values and that the resulting API graph retains the graph connections and custom nodes.

### 8. ComfyUI HTTP execution

Implement the local ComfyUI lifecycle:

- health/status probe via a bounded read-only endpoint such as `/system_stats` or `/`;
- `POST /upload/image` for input images;
- `POST /upload/mask` when masks are explicitly used;
- `POST /prompt` to queue the transformed API graph with a generated `client_id` and prompt/job ID;
- `GET /history/{prompt_id}` after execution;
- `GET /view?filename=...&subfolder=...&type=...` to retrieve output images;
- `POST /interrupt` for cancellation.

Support HTTP status errors, Comfy validation errors, node errors, execution errors, timeouts, server disconnects, and duplicate/late events. Return typed backend errors to the UI instead of exposing raw JSON as the only explanation.

Use multipart upload correctly and respect Android cancellation/timeouts for large local-network images.

### 9. Live preview and progress

Replace the Forge-only progress map with a backend-neutral progress model:

- backend/server identity;
- prompt/job ID;
- queued/running/completed/failed/cancelled state;
- current node ID/title;
- current step/total when available;
- progress fraction when available;
- queue position when available;
- preview bytes when available;
- error message.

For ComfyUI:

- open `/ws?clientId=...` as `ws://` or `wss://` derived from the server URL;
- filter all messages by the active prompt ID;
- handle status, execution start, progress, executing, executed, cached, error, and completion messages;
- parse binary preview frames when the server sends them and display them in the existing progress overlay;
- if binary preview parsing is unsupported or no preview is sent, continue and display the final history output normally;
- close the WebSocket on completion, error, cancellation, app disposal, or backend switch;
- use bounded history/queue polling as a fallback when WebSocket is unavailable.

For Forge, preserve the current polling behavior behind the same progress interface. Update the overlay so it renders node/workflow execution for ComfyUI and checkpoint/model messages only for Forge.

### 10. Results and metadata

Replace the assumption that every result is just a string data URL with a `GeneratedImage` model containing at least:

- image bytes or retrievable local data;
- source/backend;
- prompt/job ID;
- workflow ID;
- output node ID/type;
- Comfy filename/subfolder/type metadata;
- snapshot of favorite values and prompt values;
- optional submitted API graph or workflow reference.

Output extraction rules:

- Prefer image outputs from active output nodes such as `SaveImage` and `PreviewImage`.
- Include all relevant image outputs when multiple output nodes exist.
- Ignore non-image outputs unless a future media model is added.
- If there are no identifiable output nodes, scan completed history output objects for image metadata and use those.

Keep Forge PNG info as an optional Forge capability. For ComfyUI, retain workflow/favorite/prompt metadata locally because `/png-info` is not a universal ComfyUI contract.

Ensure the existing edit/reuse flow can turn a Comfy result back into an input image without assuming Forge PNG metadata.

### 11. Capability-gated UI and feature behavior

Use backend capabilities to show, hide, or disable features intentionally:

| Feature | Forge | ComfyUI |
|---|---|---|
| Checkpoint browser/switching | Keep | Hide; checkpoint/model nodes belong to workflow |
| Forge VAE/text-encoder modules | Keep | Hide |
| Workflow import/selection | Optional | Required |
| Prompt and input image | Existing canvas | Existing canvas, bound through favorites |
| Negative prompt | Existing area | Existing area only when favorite/role exists |
| Steps/CFG/seed/size/sampler/LoRA/model controls | Existing Forge settings | Expose only when favorited |
| Separate Forge LoRA inventory | Keep | Do not call; favorite workflow widgets handle it |
| Checkpoint/sampler testing | Keep | Hide until a workflow-variation feature is deliberately added |
| SeedVR2 endpoint | Keep | Hide; no Forge endpoint calls |
| A1111 image-stitch script | Keep | Hide or implement as a workflow-based feature later |
| Forge prompt optimizer endpoint | Keep when available | Hide unless a generic endpoint is intentionally added |
| PNG info | Keep | Replace with local workflow metadata |
| Crop/resize/drawing | Reuse where input/output contract is generic | Reuse, with explicit workflow image-slot mapping |

Do not present a disabled Forge control without explaining why it is unavailable for ComfyUI. Do not let unsupported controls make network calls.

### 12. Android and networking

Verify on an Android release/profile build, not only in debug:

- local `http://` and `ws://` connections;
- optional `https://`/`wss://` reverse-proxy connections if supported by the chosen URL model;
- Android cleartext/network-security behavior;
- WebSocket behavior when the app backgrounds and resumes;
- file picker imports from Downloads/Files/shared providers;
- large JSON and image payloads;
- cancellation and reconnect behavior.

Use the Android system picker and app-owned data. Do not add broad storage permissions just for workflow import. Review the existing `MANAGE_EXTERNAL_STORAGE` permission and remove or narrow it if the rest of the app does not require it.

## Implementation sequence

The agent should execute these phases in order. Each phase must leave the project analyzable and should add tests for the new behavior before moving on.

### Phase 0 — Establish fixtures and understand the existing edits

1. Inspect the current dirty diff and existing Forge behavior.
2. Add the attached workflow JSON as a test fixture or a sanitized equivalent in the repository if licensing/size permits.
3. Add a small favorites fixture containing the exact `favoritedWidgets.favorites` shape.
4. Run formatting, static analysis, and the existing test suite to record the baseline.
5. Do not implement ComfyUI with assumptions that contradict the fixture.

### Phase 1 — Backend seam and server identity

1. Add backend kind/profile/capability models.
2. Introduce the backend interface/manager.
3. Move the current Forge backend behind it with regression coverage.
4. Refactor API helpers, globals/providers, startup, progress, interrupt, and settings to use the active backend.
5. Add server-type selection, persistence, clear visual identity, and profile-scoped storage.
6. Keep Forge behavior working before adding Comfy generation.

### Phase 2 — Workflow persistence and favorites

1. Implement workflow document/index models.
2. Implement SharedPreferences serialization and migration/versioning.
3. Implement Android JSON import/management.
4. Parse and validate `nodes`, `links`, `widgets_values`, and `favoritedWidgets.favorites`.
5. Implement favorite resolution from `nodeLocatorId` + `widgetName`.
6. Add generated Comfy settings controls for non-prompt/non-image favorites.
7. Bind prompt, negative prompt, and image favorites to the existing canvas/generation areas.
8. Persist changes and reload them after an app restart.

### Phase 3 — Graph conversion and Comfy execution

1. Implement editor-format graph cloning and conversion to API format.
2. Use runtime node metadata/frontend serialization rules for widget mapping.
3. Implement image/mask upload and filename injection.
4. Implement prompt submission, history retrieval, output extraction, and `/view` downloads.
5. Add typed validation and execution error handling.
6. Prove the attached custom-node workflow can be transformed and queued against a real test server.

### Phase 4 — WebSocket progress, previews, and results

1. Implement Comfy WebSocket lifecycle and prompt-ID filtering.
2. Map text/binary events to the shared progress model.
3. Render live previews when available and fall back to final outputs otherwise.
4. Add cancellation, disconnect, reconnect, and app-background handling.
5. Migrate results to `GeneratedImage` metadata while preserving Forge results/actions.

### Phase 5 — Capability-gated UI and hardening

1. Replace/hide Forge-only Comfy controls.
2. Add explicit workflow status, active workflow, favorite count, and backend identity surfaces.
3. Test multiple image favorites, bypassed nodes, negative prompts, LoRA/model favorites, multiple output nodes, and absent output nodes.
4. Test Android release behavior and network security.
5. Update README/user-facing setup instructions for both server types.

## Required tests

### Workflow and favorites unit tests

- Parse the attached editor workflow format.
- Parse the exact `favoritedWidgets.favorites` structure.
- Resolve node `84`/`prompt` and node `72`/`image`.
- Resolve multiple prompt/image favorites and save their semantic roles.
- Handle missing node IDs, unknown widgets, duplicate favorites, bypassed nodes, and malformed JSON.
- Confirm only favorites are editable.
- Confirm favorite changes persist in SharedPreferences and survive a fresh app process.
- Confirm cloning/preparation never mutates the saved source workflow.

### Graph conversion tests

- Convert links into API input references.
- Map widget names to values without assuming raw array indexes.
- Preserve custom node types, node IDs, disabled/bypassed state, and widget values.
- Apply favorite, prompt, negative prompt, and uploaded-image overrides.
- Verify the attached workflow produces an API graph with its `SaveImage`, KSampler, custom Krea nodes, and links intact.

### Backend contract tests

Use fake HTTP/WebSocket transports and fixtures for:

- status probe;
- image/mask upload;
- prompt acceptance and validation failure;
- queue/status/progress/executing/executed/error/completion events;
- binary preview and no-preview paths;
- history output extraction;
- `/view` image download;
- interrupt, timeout, disconnect, reconnect, and late events;
- Forge adapter regression behavior.

### Widget/integration tests

- Backend selector changes the visible settings and theme/identity.
- Comfy settings show workflow controls and only favorite widget controls.
- Prompt/image favorites remain in the existing input area.
- Missing required favorites block generation with a useful error.
- Generation reaches Results and displays final images with no live preview.
- Generation displays live previews when the fake server supplies them.
- Forge startup, checkpoint switching, LoRA flow, and inpaint generation continue to work.

## Definition of done

The feature is complete when a user can:

1. Select ComfyUI and see an unmistakable ComfyUI identity.
2. Connect to a local ComfyUI server without authentication.
3. Import the attached style of editor-exported workflow JSON.
4. Select the workflow and see only its favorited widgets as editable settings.
5. Use the existing prompt and image areas for the workflow's favorited prompt/image widgets.
6. Persist the workflow and changed values in SharedPreferences and recover them after restart.
7. Generate by converting the editor graph into a valid ComfyUI API graph, uploading required inputs, and queueing it.
8. See live node/progress previews when the server provides them, or receive the final output normally when it does not.
9. Retrieve images from output nodes when present, with a history fallback otherwise.
10. Interrupt/fail/reconnect without leaving the UI stuck in a generating state.
11. Use Forge Neo exactly as before, with Forge-only features isolated from ComfyUI.

## Implementation references

The ComfyUI lifecycle should follow the self-hosted server routes and official example:

- [ComfyUI server routes](https://docs.comfy.org/development/comfyui-server/comms_routes)
- [ComfyUI official WebSocket API example](https://github.com/comfyanonymous/ComfyUI/blob/master/script_examples/websockets_api_example.py)

Use those references for `/prompt`, `/ws`, `/history`, `/view`, `/upload/image`, `/upload/mask`, `/system_stats`, and `/interrupt`, but treat the tested local ComfyUI server and attached workflow as the final compatibility authority.

