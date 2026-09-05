# Aperture — Feature Checklist

Cross-referenced against [FEATURES.md](FEATURES.md), same tier order (most
fundamental first). Two columns per feature:

- **Logic** — does the new architecture (`domain/`, `data/`, `state/`,
  `runtime/`) actually do this. Almost everything here is done; the whole
  point of the migration was to get every feature's logic working headlessly
  before touching a pixel.
- **UI** — is there a real screen for it. Almost nothing here is done. The
  only screens that exist are the dev harness's three debug tabs
  (`ui/dev/desk_lab.dart`, `generation_lab.dart`, `state_inspector.dart`) —
  none of them is the actual app.

✅ done · 🟡 partial · ⬜ not started

---

## Tier 1 — The spine

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 1.1 | Server connection & reachability | ✅ | ✅ | `EngineEndpoint`, `ImageEngine.ping()`, `EngineStore`. Real Server drawer on the front page (engine dropdown + per-engine host/port + Connect); both engines go through the same flow |
| 1.2 | Engine selection (exactly one active) | ✅ | ✅ | `EngineKind`, `EngineRegistry`, `EngineCapabilities`. The engine badge (title row, left) plus the Server drawer's dropdown switch between Forge/Comfy, each keeping its own address |
| 1.3 | Prompt entry | ✅ | ✅ | `SessionStore.setPrompt`. `DeskField` on the real front page, live-bound |
| 1.4 | Generate (txt2img/img2img/inpaint) | ✅ | ✅ | `ApertureRuntime.submit()`, both engines' `generate()`. Mode is no longer a separate switch — for Comfy it follows the active workflow's declared type; the source image lives in its own input card, shown only when relevant |
| 1.5 | Live progress & preview | ✅ | 🟡 | Progress is confirmed working on device end-to-end (steps 1/8 → 8/8 tracked, bar + thumb + percentage). Two bugs found and fixed via device logs, both covered by `test/comfy/comfy_progress_service_test.dart`: Comfy reports steps per *node* and the previous node's counts leaked into the next, freezing the bar at 100%; and a `status` frame arriving before `beginTracking()` republished the previous run's terminal phase, which made `RunStore` drop every real frame afterwards. **Live preview is still unverified** — the server sends no binary frames at all, most likely `--preview-method none` (ComfyUI's default). Decoding is now signature-based so it handles both the classic and metadata-prefixed frame layouts |
| 1.6 | Results accumulate | ✅ | ✅ | `LibraryStore`. `PrintShelf` on the real front page, with the source image pinned left of a divider in the same row; tapping any card promotes it to the main display and swaps the tray to that card's tools |
| 1.7 | Cancel a running generation | ✅ | ✅ | `engine.cancel()`, `ApertureRuntime.cancelRun()`, wired to a Stop button |

**Tier 1 is done**, both logic and UI. The front page exists: tray, main
display + a separate fixed input card, shelf, prompt, generate, an engine
switcher, and a Workflows drawer replacing the old mode-switch idea (a
ComfyUI workflow already declares txt2img/img2img/inpaint, so the UI reads
that instead of asking again).

---

## Tier 2 — Image input & the canvas

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 2.1 | Image upload | ✅ | ✅ | `SessionState.sourceImage` + `SessionStore.setSourceImage()`. `image_picker` wired to the shelf's input card: tap to add, then Replace/Clear from the tray once it's the main display. No crop-before-attach or multi-image (stitch) picker yet |
| 2.2 | Mask painting (inpaint) | ✅ | ✅ | `ui/stage/mask_editor.dart`: full-screen painter with paint/erase, brush ruler, per-stroke undo, clear, and a loupe (a finger hides exactly the pixels being painted). Points are stored in **image** coordinates and brush width in display units, so a mask stays correct at any canvas size — pinned by `test/imaging/mask_geometry_test.dart` |
| 2.3 | Outpainting | ✅ | ✅ | `ui/stage/outpaint_editor.dart`: four edge handles drag the canvas outward, showing live dimensions. `generateOutpaintData()` seeds each new edge with a stretched, mosaicked copy of the adjacent strip (flat black makes samplers paint a vignette) and masks it with a 16px overlap so the seam blends. Result lands in the session as image + mask |
| 2.4 | Send a result back to the canvas | ✅ | ✅ | The result tray's **Edit** tool spools the image's bytes to a cache file and hands it to `SessionStore.setSourceImage`, then switches the view to the input card. Works for both engines (Comfy's `/view` URL and Forge's data URL) |

**Tier 2 is done.** Mask painting and outpainting both have full-screen
Desk editors reached from the tray; the only thing left unbuilt in this area
is cropping before attach (5.2), which is a Tier 5 tool rather than a canvas
one.

---

## Tier 3 — Steering the output

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 3.1 | Checkpoint selection & switching (Forge) | ✅ | ✅ | `ForgeCatalogClient.fetchCheckpoints()`, `selectCheckpointAndWait()`. Checkpoints drawer (title-row selector on Forge): grouped by base model, Refresh rescans, selecting applies server-side and reports when the swap lands |
| 3.2 | Workflow selection & switching (Comfy) | ✅ | 🟡 | `ComfyWorkflowService` fully implemented (import, select, rename, duplicate, delete). The Workflows drawer now lists every saved workflow, selects, and imports new ones (name + type) via `file_picker` — rename/duplicate/delete still have no UI |
| 3.3 | Generation parameters | ✅ | ✅ | **Forge**: steps, guidance, resolution, batch size, sampler, scheduler, seed, plus denoise / mask blur / masked content gated to the runs that use them. **ComfyUI**: settings come from the workflow graph instead (4.3), because that is what actually executes and what persists — a session-level `SamplingParams` drawer would have silently disagreed with the graph |
| 3.4 | Per-checkpoint remembered defaults | ✅ | ✅ | `Checkpoint.defaults` is applied to the session on switch, which is what the field was always for. Nothing writes *new* defaults back per checkpoint yet — that belongs with 7.3's metadata editing |
| 3.5 | LoRA selection | 🟡 | ⬜ | `Lora`, `CatalogStore.buildPromptFragment()` exist and are tested. No picker, no weight sliders, no tag chips |

**3.1–3.4 are done.** What remains in this tier is **3.5, the LoRA picker** —
the only piece with no UI at all, and the one that needs genuinely new
components (weight sliders per LoRA, trigger-tag chips) rather than another
list drawer.

---

## Tier 4 — ComfyUI workflow system

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 4.1 | Workflow import + type declaration | ✅ | ✅ | `file_picker` → name + type sheet → `importWorkflow`, from the Workflows drawer's Add action |
| 4.2 | Automatic setting detection | ✅ | n/a (headless) | |
| 4.3 | Editing detected settings | ✅ | ✅ | `ui/stage/workflow_settings.dart` renders `DetectedWorkflowSettings` **generically** — each widget drawn from its schema type and bounds, never from a hard-coded field list. Edits persist per workflow through `updateDetectedSettingValue` |
| 4.4 | Graph → API conversion | ✅ | n/a (headless) | |
| 4.5 | Workflow management (rename/duplicate/delete) | ✅ | ✅ | The ⋮ on each workflow row opens edit settings / rename / change type / duplicate / delete, all as Desk drawers |

**Resolution is deliberately not special-cased.** Workflows disagree about
how canvas size is expressed: a model trained on fixed buckets exposes
literal `width`/`height`, while a graph built around a resolution-selector
node exposes `megapixels` + `aspect_ratio` and derives the pixels itself.
Because the settings editor renders whatever widgets the detector found,
both work with no branch in the UI — the same approach the previous build
used, and the reason a hard-coded 512/768/1024 dropdown was wrong for
ComfyUI. That dropdown now only applies to Forge, which has no graph.

---

## Tier 5 — Post-generation tools

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 5.1 | Save to device | ✅ | ✅ | The result tray's Save tool publishes into the device photo library via `gal` (MediaStore on API 30+, legacy write below), into an "Aperture" album, requesting access first and reporting a decline honestly. Writing to a path directly stopped working under scoped storage — the previous version saved to the app's private directory, where the gallery never looks |
| 5.2 | Crop / Resize | ✅ | ✅ | **Crop**: full-screen editor with a draggable rect, aspect presets (free/1:1/4:3/3:4/16:9/9:16) and live output dimensions; the rect is held in image pixels so it survives rotation. **Resize**: drawer with a percentage ruler plus fit-longest-side presets. Both run `copyCrop`/`copyResize` on a background isolate — they are per-pixel work and freeze the UI otherwise. Available from both the result and input trays |
| 5.3 | Upscale (SeedVR2) | ✅ | ✅ | Both engines implement `UpscaleCapable.upscale()`. Upscale is now a drawer offering 1024/2048/3072/4096 targets, available from the result **and** input trays — a small source is exactly when upscaling before an img2img run is worth doing. An upscaled result becomes a new print; an upscaled source replaces the source |
| 5.4 | Image stitching (Forge) | ✅ | ⬜ | `GenerationSpec.stitchImages` → `ForgeEngine._generate()` handles `alwayson_scripts`. No multi-image attach UI |
| 5.5 | Metadata inspection | ✅ | ✅ | `data/imaging/png_metadata.dart` reads the PNG's own text chunks — **no API call needed**, since both generators embed everything at save time. Handles A1111's `parameters` block and ComfyUI's `prompt`/`workflow` graphs (tEXt, zTXt and iTXt), walking chunks directly rather than decoding megapixels to read a few hundred bytes. The ComfyUI summary is shape-driven: it finds the negative prompt by which node feeds the sampler's `negative` input, so it survives custom nodes. Details drawer shows prompts + settings, with copy-to-clipboard and the raw workflow JSON |
| 5.6 | Compare against input image | ✅ | ✅ | A momentary **Compare** tool in the result tray: hold to swap the stage to the input, release to go back. It fires on pointer-down (not tap or long-press) and only changes which child of the already-mounted `IndexedStack` paints, so there is no decode and no delay. Zoom and pan live on one shared `TransformationController`, so the input appears at exactly the same magnification and offset — without that, a close comparison tells you nothing |

---

## Tier 6 — Prompt intelligence

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 6.1 | Prompt history & favourites | ✅ | ✅ | Prompts drawer with Recent / Saved / Phrases tabs: tap to use, star to keep past the 300-entry cap, × to forget |
| 6.2 | Prompt composition from fragments | ✅ | ✅ | The Phrases tab lists frequency-ranked fragments with their use counts; tapping appends rather than replaces, since a fragment is a building block |
| 6.3 | Prompt optimization (Forge) | ✅ | ✅ | Shares the Enhance button with 6.4 — it is gated on the `promptRewrite` capability, which both engines declare, so no engine-specific branch exists. Untested against Forge |
| 6.4 | Prompt enhance (Comfy) | ✅ | ✅ | **Enhance** under the prompt field. The pre-enhancement text is recorded to the prompt book first, so a worse rewrite is one tap from being undone |
| 6.5 | Image → prompt / describe (Comfy) | ✅ | ✅ | **Describe** under the prompt field, shown only when `imageToText` is supported *and* a source image exists |

**Tier 6 is done.** One drawer and two buttons, all capability-gated. Only
exercised against ComfyUI — Forge's `rewritePrompt` goes through OpenRouter
rather than a bundled workflow and has not been run.

---

## Tier 7 — Power tools

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 7.1 | Server gallery browser | ✅ | ✅ | Ships its own ComfyUI addon (`comfy_addon/aperture_gallery`) rather than depending on a third-party one. It paginates, filters by date/filename **server-side**, and serves cached JPEG thumbnails — so a phone fetches ~60 small entries at a time instead of a tens-of-megabytes dump of the whole library. `ui/stage/gallery_page.dart` offers a day filter, search and infinite scroll; multi-select sends images to the shelf as ordinary `GeneratedImage`s. Falls back to the old ComfyUI-Gallery addon when the new routes are absent, so installing it is an upgrade, not a requirement |
| 7.2 | Checkpoint / sampler test lab | ⬜ | ⬜ | **Not ported.** `checkpoint_testing_service.dart` was deleted with the rest of `lib/logic/` and never rebuilt on the new architecture. Needs designing fresh, not just re-wiring |
| 7.3 | Checkpoint metadata editing | 🟡 | ⬜ | `Checkpoint.previewUrl`/`baseModel` fields exist; no edit flow or persistence path wired up |
| 7.4 | Forge module selection (VAE/text encoders) | ✅ | ⬜ | `ForgeCatalogClient.fetchModules()`. No UI |

---

## Beyond FEATURES.md

Things that were not in the original scope but earned their place.

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| X.1 | Civitai browser | ✅ | ✅ | `data/civitai/civitai_client.dart` + `ui/stage/civitai_page.dart`. Sort/period paging, **exclusive** rating filtering, tag-id filtering, local prompt search, and handing a prompt back to the prompt field. Three API findings drove the design: `withMeta=true` is mandatory (without it every image returns `meta: null`); the documented `nsfw` param is *cumulative*, so exclusivity needs the `browsingLevel` bitmask (1/2/4/8, 15 for all); and `tags` takes integer ids only — there is no public name→id lookup, so the field takes the number from a civitai.com URL. Restricted to `type=image`: the feed mixes in videos whose `.mp4` URLs would render as broken cells, and the CDN has no still-frame transform |

---

## Suggested build order

1. ~~**Front page** (Tier 1)~~ — done. `ui/stage/front_page.dart` is
   `main.dart`'s home: tray, input card, main display, print shelf, prompt,
   generate, engine switcher, Workflows drawer, live progress with a
   shimmering shelf placeholder, and a result tray (save/upscale/delete
   real; edit/crop listed but not built).
2. ~~**Parameters drawer** (3.3)~~ — done: sampler, scheduler, batch size,
   denoise and mask blur/fill, each gated to the runs they actually affect.
3. ~~**Checkpoint picker + remembered defaults** (3.1, 3.4)~~ — done.
4. ~~**Workflow management + settings editor** (3.2, 4.1/4.3/4.5)~~ — done.
5. ~~**Send a result back to the canvas** (2.4)~~ — done, via the result
   tray's Edit tool.
6. ~~**Mask painting and outpainting** (2.2, 2.3)~~ — done, which also makes
   3.3's mask blur / masked-content controls reachable at last.
7. **LoRA picker** (3.5) — deferred: the server has no LoRAs wired into its
   workflows yet, so there is nothing to test against.
9. **Post-generation tools** (Tier 5) — Save, Upscale and Edit (send back to
   input) are wired from the result tray; Crop, stitch, metadata and compare
   are not.
10. **Power tools** (Tier 7) — the gallery browser is done. What remains is
    checkpoint metadata editing (7.3), Forge module selection (7.4) and the
    **test lab** (7.2), which was never ported and needs designing fresh
    rather than re-wiring.
