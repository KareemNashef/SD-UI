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
| 1.1 | Server connection & reachability | ✅ | 🟡 | `EngineEndpoint`, `ImageEngine.ping()`, `EngineStore`. UI only exists as a raw host/port form in the debug harness's Server drawer — no real settings screen, and Forge has never been exercised through it |
| 1.2 | Engine selection (exactly one active) | ✅ | ⬜ | `EngineKind`, `EngineRegistry`, `EngineCapabilities`. `generation_lab.dart` hardcodes ComfyUI; there is no Forge/Comfy switcher anywhere in the UI |
| 1.3 | Prompt entry | ✅ | 🟡 | `SessionStore.setPrompt`. `DeskField` works in the debug harness; not on a real screen with the rest of the layout around it |
| 1.4 | Generate (txt2img/img2img/inpaint) | ✅ | 🟡 | `ApertureRuntime.submit()`, both engines' `generate()`. Works end-to-end against a live ComfyUI server in the Run tab; only exercises text2img, no mode switch UI |
| 1.5 | Live progress & preview | ✅ | 🟡 | `RunProgress` stream from both engines. `DeskProgress` + preview render into the mounted sheet in the Run tab |
| 1.6 | Results accumulate | ✅ | 🟡 | `LibraryStore`. `PrintShelf` shows them with the new coverflow lift; only reachable from the debug tab |
| 1.7 | Cancel a running generation | ✅ | ✅ | `engine.cancel()`, `ApertureRuntime.cancelRun()`, wired to a Stop button |

**Tier 1 is the priority.** Everything in it has working logic; the task is
entirely "build the real front page" — tray, sheet, shelf, prompt, chips,
generate — per DESIGN.md, with a Forge/Comfy switcher and mode switch
(text2img / img2img / inpaint) added on top of what `generation_lab.dart`
already proves works.

---

## Tier 2 — Image input & the canvas

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 2.1 | Image upload | 🟡 | ⬜ | `SessionState.sourceImage` field exists; `image_picker` is still a dependency but nothing calls it. No pick-from-gallery flow anywhere |
| 2.2 | Mask painting (inpaint) | ✅ | ⬜ | `domain/drawing/` (stroke, canvas geometry) + `data/imaging/mask_generator.dart` ported intact. No canvas widget exists — `MountedSheet`'s mask area is currently just a placeholder comment in DESIGN.md |
| 2.3 | Outpainting | 🟡 | ⬜ | `data/imaging/image_processor.dart` has `generateOutpaintData()`. `MountedSheet`'s corner handles are purely decorative right now — dragging them calls nothing |
| 2.4 | Send a result back to the canvas | ⬜ | ⬜ | No `SessionStore` method to load a `GeneratedImage` back in as the source. Needs a small logic addition, not just UI |

**Nothing here has a UI yet.** This is the next tier after the front page
exists, since img2img/inpaint being the primary mode was explicit from the
start.

---

## Tier 3 — Steering the output

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 3.1 | Checkpoint selection & switching (Forge) | ✅ | ⬜ | `ForgeCatalogClient.fetchCheckpoints()`, `applyCheckpoint()`. `CatalogStore` holds them. No picker drawer |
| 3.2 | Workflow selection & switching (Comfy) | ✅ | ⬜ | `ComfyWorkflowService` fully implemented (import, select, rename, duplicate, delete). `generation_lab.dart` only ever imports one hardcoded debug workflow — no list, no picker |
| 3.3 | Generation parameters | 🟡 | 🟡 | `SamplingParams` covers steps/cfg/denoise/size/seed. The Settings drawer in the debug harness exposes steps, guidance, resolution, seed toggle — **missing sampler, scheduler, batch size, mask blur, mask fill** |
| 3.4 | Per-checkpoint remembered defaults | 🟡 | ⬜ | `Checkpoint.defaults` field exists; nothing in `CatalogStore` auto-applies it on switch yet |
| 3.5 | LoRA selection | 🟡 | ⬜ | `Lora`, `CatalogStore.buildPromptFragment()` exist and are tested. No picker, no weight sliders, no tag chips |

**Do 3.3 (finish the parameters drawer) alongside Tier 1** — it's the same
screen. The rest waits for a checkpoint/workflow picker, which is really
Tier 1's "engine selection" UI extended.

---

## Tier 4 — ComfyUI workflow system

| # | Feature | Logic | UI |
|---|---|:--:|:--:|
| 4.1 | Workflow import + type declaration | ✅ | ⬜ |
| 4.2 | Automatic setting detection | ✅ | n/a (headless) |
| 4.3 | Editing detected settings | ✅ | ⬜ |
| 4.4 | Graph → API conversion | ✅ | n/a (headless) |
| 4.5 | Workflow management (rename/duplicate/delete) | ✅ | ⬜ |

**This entire tier is logic-complete and tested** (`comfy_workflow_service`,
`workflow_auto_detector`, `comfy_node_schema`, `comfy_graph_converter`, all
carried over with their test suites green). The only work left is UI: a
workflow list drawer using `DeskDropdown`/a dedicated list, and a settings
screen that renders whatever `DetectedWorkflowSettings` hands back — which,
because 4.2 already groups fields by role, should fall out of the same
`DeskRuler`/`DeskDropdown`/`DeskToggle` components already built.

---

## Tier 5 — Post-generation tools

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 5.1 | Save to device | ⬜ | ⬜ | Not ported. Old code wrote directly to `/storage/emulated/0/Download`; nothing does this in the new architecture |
| 5.2 | Crop / Resize | ✅ | ⬜ | `data/imaging/image_processor.dart` ported. No UI |
| 5.3 | Upscale (SeedVR2) | ✅ | ⬜ | Both engines implement `UpscaleCapable.upscale()`. `DeskTool` icon exists in the tray as a placeholder only — tapping it does nothing |
| 5.4 | Image stitching (Forge) | ✅ | ⬜ | `GenerationSpec.stitchImages` → `ForgeEngine._generate()` handles `alwayson_scripts`. No multi-image attach UI |
| 5.5 | Metadata inspection | 🟡 | ⬜ | `ForgeCatalogClient.pngInfo()` exists; `ComfyOrigin` snapshots ride on `GeneratedImage`. No viewer |
| 5.6 | Compare against input image | ⬜ | ⬜ | No hold-to-compare gesture built. Note: **DESIGN.md's Seam-style comparison idea never shipped** — Desk's `MountedSheet`/`Print` don't currently support a side-by-side or overlay compare at all |

---

## Tier 6 — Prompt intelligence

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 6.1 | Prompt history & favourites | ✅ | ⬜ | `PromptBookStore` — history capped at 300, self-persisting, tested. No drawer |
| 6.2 | Prompt composition from fragments | ✅ | ⬜ | `PromptBookStore.fragments`, frequency-ranked, tested. No UI to insert one |
| 6.3 | Prompt optimization (Forge) | ✅ | ⬜ | `ForgeEngine.rewritePrompt()`. No "Enhance" button on the real prompt field yet |
| 6.4 | Prompt enhance (Comfy) | ✅ | ⬜ | `ComfyEngine.rewritePrompt()` (bundled QwenVL workflow). Same as above |
| 6.5 | Image → prompt / describe (Comfy) | ✅ | ⬜ | `ComfyEngine.describeImage()`. No "Describe Image" button |

**All logic-complete.** This is one drawer (history/favourites/fragments) and
two buttons (enhance, describe) once 2.1's image picker exists.

---

## Tier 7 — Power tools

| # | Feature | Logic | UI | Notes |
|---|---|:--:|:--:|---|
| 7.1 | Server gallery browser | ✅ | ⬜ | `ComfyGalleryClient` — date-grouped, isolate-parsed, cached, tested against 11,000+ images. `DeskTool` "Gallery" icon is a placeholder only |
| 7.2 | Checkpoint / sampler test lab | ⬜ | ⬜ | **Not ported.** `checkpoint_testing_service.dart` was deleted with the rest of `lib/logic/` and never rebuilt on the new architecture. Needs designing fresh, not just re-wiring |
| 7.3 | Checkpoint metadata editing | 🟡 | ⬜ | `Checkpoint.previewUrl`/`baseModel` fields exist; no edit flow or persistence path wired up |
| 7.4 | Forge module selection (VAE/text encoders) | ✅ | ⬜ | `ForgeCatalogClient.fetchModules()`. No UI |

---

## Suggested build order

1. **Front page** (Tier 1) — tray, mounted sheet, print shelf, prompt, value
   chips, generate, on a real `Stage`/`FrontPage` widget replacing the debug
   harness as `main.dart`'s home. Add the engine switcher and the txt2img /
   img2img / inpaint mode switch. This alone turns three debug tabs into an
   actual app.
2. **Finish the parameters drawer** (3.3) — sampler, scheduler, batch size,
   mask blur/fill alongside what already works.
3. **Image input + canvas** (Tier 2) — picker, paint-a-mask on the sheet,
   outpaint handles made to actually do something, send-a-result-back.
4. **Checkpoint/workflow pickers** (3.1, 3.2, 3.4, 4.1/4.3/4.5) — one drawer
   per engine, built on `DeskDropdown` + a settings list.
5. **LoRA picker** (3.5).
6. **Prompt intelligence drawer + buttons** (Tier 6) — cheap, everything is
   logic-complete.
7. **Post-generation tools** (Tier 5) — upscale modal first (logic is done
   for both engines), then save/crop/stitch/metadata/compare.
8. **Power tools** (Tier 7) — gallery browser first (logic is done); the
   test lab needs designing from scratch.
