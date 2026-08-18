# Aperture — Design System

> The reference this build follows. Every UI decision traces back to
> something in here. If a screen contradicts this document, the screen is
> wrong.

---

## 0. What went wrong last time

The previous attempt kept the old structure and changed the colors. It also
called flat translucent boxes with white borders "Liquid Glass," which they
were not. This document fixes both, and every claim in it is verified
against the actual toolchain before it is written down (see §8).

---

## 1. What this app actually is

**A remote control for a GPU that isn't in your hand.**

You are on a phone. The machine doing the work is across the room or across
the house. The loop is: *say what you want → watch it happen → look at it →
adjust → go again.* Everything else is setup.

Three consequences that drive the whole design:

1. **The image is the subject.** It is not a card inside a form. It is the
   application surface.
2. **Waiting is a first-class state.** A generation takes 10s to 3min. The
   waiting UI is not a spinner bolted on — it is one of the app's main
   screens.
3. **Iteration is the point.** Nobody generates once. Compare-and-adjust
   must cost zero navigation.

### The structural failure of the old app

The old app was **a scrolling form that happened to contain a picture**:

```
[ scroll view ]
  ├── canvas card (fixed 550px)
  ├── PROMPT section
  ├── stitch section
  ├── comfy extra-images section
  └── control bar  → tap Generate → NAVIGATES AWAY to Results tab
```

You scrolled a form to make art. Generating threw you to a different page,
so comparing your new result to your last one was a page transition, and
changing the checkpoint mid-flow meant a trip to a third tab.

**Aperture is not a set of pages. It is one surface with things floating
over it.**

---

## 2. The core idea: The Stage and the glass

### The Stage
One full-bleed, edge-to-edge surface that **never navigates**. It morphs
between states:

| State | What the Stage shows |
| --- | --- |
| Empty | An invitation. Nothing else. |
| Source | Your input image (img2img / inpaint) |
| Painting | Source + your mask strokes |
| Working | Live preview frames, sharpening as steps complete |
| Result | The finished image |
| Comparing | Result, wiped against the source under your thumb |

### The glass
Controls **float above** the Stage as refractive panes. This is the entire
reason to use this material: chrome that stays legible without hiding the
image underneath it. The image bends through the glass — which also means
**the chrome must stay achromatic**, or the refraction is invisible.

```
        ┌─────────────────────────────┐
        │  ▸ Rail   engine · model    │  ← thin glass, floats
        │                             │
        │                             │
        │        T H E   S T A G E    │  ← full bleed image
        │                             │
        │                             │
        │  ▸ Filmstrip  ▫ ▫ ▫ ▫ ▫    │  ← thin glass, recent results
        │  ▸ Prompt bar        ( ◎ )  │  ← regular glass + aperture
        └─────────────────────────────┘
                                   ↑ everything else arrives as a sheet
```

**There are no tabs.** Gallery and Settings are not destinations you travel
to; they are sheets that rise over the Stage and drop away again. The
Stage never unmounts, so your work is never lost behind a transition.

---

## 3. The material — real Liquid Glass

Three weights. All three are **shader-backed**, not opacity tricks.

| Weight | Blur | Refraction | Dispersion | Used for |
| --- | --- | --- | --- | --- |
| **Vapor** | 12 | — | — | inline chips, badges, labels |
| **Lens** | 24 | ✅ | slight | rail, prompt bar, filmstrip, buttons |
| **Prism** | 40 | ✅ | ✅ | sheets, dialogs, the parameter panel |

### What makes it real
`shaders/liquid_glass.frag` — **already written, already compiling** — does
actual optics:

- A **rounded-rect SDF** defines the pane.
- The **SDF gradient becomes a surface normal**, so light bends hard at the
  rim and passes straight through the middle. This is the single detail
  that separates glass from frosting: a real lens is only distorting near
  its edges.
- **Chromatic dispersion** samples R/G/B at slightly different offsets,
  producing the faint colour fringing at a real lens edge.
- A **specular band** appears where the normal faces the light — and the
  light direction is a uniform, so it **tracks your finger** on press.

### Degradation, honestly
`ImageFilter.shader` requires Impeller. Impeller is default on Android 10+
and iOS. On anything older, `LiquidGlass` falls back to
`BackdropFilter(blur)` + gradient border — visually simpler, structurally
identical, never broken. This is a runtime check
(`ImageFilter.isShaderFilterSupported`), not a build flag.

### Performance rule
Refraction is a per-pixel backdrop sample. **Never put Lens or Prism inside
a scrolling list.** Repeating surfaces (gallery cells, list rows) use
Vapor or plain fills. The persistent chrome — rail, prompt bar, filmstrip,
one sheet at a time — is a fixed, small number of panes.

---

## 4. Colour — the image is the palette

The chrome is **achromatic on purpose**. Colour enters the interface from
exactly two places: the user's image showing through the glass, and a
single engine accent used sparingly.

### Ground
| Token | Value | Use |
| --- | --- | --- |
| `void` | `#06060A` | behind everything; the Stage's empty state |
| `well` | `#0E0F16` | sheet floor, inert wells |
| `chalk` | `#F2F3F7` | primary text |
| `chalk70` | 70% chalk | secondary text |
| `chalk40` | 40% chalk | tertiary, placeholders |
| `chalk15` | 15% chalk | hairlines, dividers |

### Engine identity — a signal, not a paint job
The old app flooded every border, icon and glow with the engine colour.
Aperture uses it in **exactly three places**: the status dot, the active
selection ring, and the aperture button's fill.

| Engine | Token | Value |
| --- | --- | --- |
| Forge Neo | `ember` | `#FF8A4C` |
| ComfyUI | `iris` | `#8B7CFF` |

Warm vs cool, distinguishable at a glance and for the ~8% of men with a
red-green colour deficiency, and neither collides with the semantic red.

### Semantic
| Token | Value | Use |
| --- | --- | --- |
| `alert` | `#FF5C7A` | errors, destructive actions |
| `caution` | `#FFC24B` | warnings, the compare state |

There is deliberately **no semantic green**. "Connected" is shown by the
engine dot being lit, not by a green light — the old app's green/violet
collision is exactly what this avoids.

---

## 5. Type — an instrument, not a magazine

One family, plus a mono for every number.

- **Geist** (SIL OFL, already downloaded) — all UI text.
- **Geist Mono** (SIL OFL, already downloaded) — **every numeral**: steps,
  CFG, denoise, resolution, seeds, percentages, queue position, file sizes.

This is not decoration. This app displays a *lot* of numbers, and they sit
in columns that must line up and in live counters that must not jitter as
they tick. Tabular mono figures fix both. The previous attempt reached for
a display serif, which is a magazine choice, not an instrument choice.

| Role | Face | Size | Weight | Notes |
| --- | --- | --- | --- | --- |
| `stageTitle` | Geist | 28 | 700 | empty-state invitation only |
| `sheetTitle` | Geist | 20 | 700 | sheet headers |
| `body` | Geist | 15 | 400 | prompt text, descriptions |
| `label` | Geist | 13 | 600 | controls, buttons |
| `micro` | Geist | 11 | 700 | uppercase, `0.12em` tracking, section eyebrows |
| `readout` | Geist Mono | 13 | 500 | **all** parameter values |
| `readoutLarge` | Geist Mono | 32 | 500 | the progress percentage |

---

## 6. Geometry & motion

**Radii** — glass panes are generously rounded, because the corner radius
is what the refraction reads along.
`pane 28` · `sheet 32` · `chip 999` · `well 14`

**Spacing** — 4pt base: `4 · 8 · 12 · 16 · 24 · 32 · 48`

**Touch targets** — 44pt minimum, no exceptions.

**Motion**
| Move | Duration | Curve |
| --- | --- | --- |
| press feedback | 120ms | `easeOutCubic` |
| pane state | 260ms | `easeOutCubic` |
| sheet rise | 380ms | `easeOutQuint` |
| Stage cross-fade | 450ms | `easeInOutCubic` |

Motion rules:
1. **The glass reacts.** Press a pane, the specular highlight moves toward
   your finger. This is the shader's light-angle uniform, not a fake.
2. **Sheets thicken as they rise** — blur and refraction animate up from
   Lens to Prism during the transition.
3. **Nothing bounces.** This is an instrument.
4. `MediaQuery.disableAnimations` freezes ambient motion and shortens
   transitions. Respected everywhere.

---

## 7. The components

### 7.1 Rail *(Lens)*
Top, floating, always visible. `[engine dot] Model/workflow name  ⌄`
Tap → **Context sheet**. This is how you change checkpoint or workflow —
one tap from the Stage, not a trip to a settings tab.

### 7.2 Prompt Bar *(Lens)*
Bottom. Collapsed: one line + the aperture. Focused: expands to 4 lines,
reveals negative-prompt toggle and the AI actions (Enhance / Describe /
Optimize — gated by `BackendCapabilities`). Filmstrip and rail fade back.

### 7.3 The Aperture *(the generate control)*
A circular iris — the app's namesake and its icon. **One element, three
states**, never a separate progress bar:

- **Idle** — engine-tinted fill, iris glyph
- **Working** — the ring *is* the progress; iris blades close as steps
  complete; centre shows `readoutLarge` percent. Tap = cancel.
- **Done** — blades snap open, result lands on the Stage

### 7.4 Filmstrip *(Vapor)*
Above the prompt bar. Recent results, newest first. Tap → that image takes
the Stage. **This is what kills the separate Results page** for the
iterate loop. Swipe up on it → the full Gallery sheet.

### 7.5 Sheets *(Prism)*
Everything not on the Stage arrives here: Context (model/workflow +
parameters), Gallery, Tools, Settings, Server Library, Test Lab. They rise
over the Stage, which stays mounted underneath.

### 7.6 Parameter Row
The workhorse of the Context sheet. `label — [ control ] — readout`, where
readout is always Geist Mono. One row type serves sliders, steppers,
pickers and toggles, so 30+ parameters across two backends stay visually
uniform.

---

## 8. Verified, not assumed

Everything load-bearing in this document was checked against the real
toolchain **before** being written down:

| Claim | Verification | Result |
| --- | --- | --- |
| Fragment shaders supported | `flutter --version` | 3.41.1 stable |
| `ImageFilter.shader` exists | read `sky_engine/lib/ui/painting.dart:4386` | present, Impeller-only |
| Runtime capability check | same file | `ImageFilter.isShaderFilterSupported` |
| The glass shader compiles | `flutter build apk --debug` | **passes** |
| Compiled shader ships | `unzip -l app-debug.apk` | `liquid_glass.frag`, 13,496b IPLR |
| Impeller default on Android | Flutter docs | default on Vulkan devices (Android 10+) |
| Geist / Geist Mono obtainable | downloaded from Google Fonts | OFL, in `assets/fonts/` |

**Nothing in this document is aspirational.** The shader in
`shaders/liquid_glass.frag` is real, compiles today, and is already bundled
into the APK.

---

## 9. Build order

Follows `FEATURES.md` tiers. Each step ends compiling, testing and
runnable — no big-bang integration.

| # | Step | Delivers |
| --- | --- | --- |
| 0 | `LiquidGlass` widget + design tokens | the material, on-device |
| 1 | Stage shell + Rail + connection | app boots, shows engine, connects |
| 2 | Prompt Bar + Aperture + generate | **end-to-end generation** |
| 3 | Working state + live preview | the waiting experience |
| 4 | Filmstrip + Stage result states | the iterate loop closes |
| 5 | Context sheet | checkpoint/workflow + parameters |
| 6 | Image input + mask painting | img2img and inpainting |
| 7 | Gallery sheet | browse, save, send-to |
| 8 | Tools sheet | crop / resize / upscale / stitch |
| 9 | Comfy workflow sheet | import, auto-detect, edit |
| 10 | Prompt intelligence | history, favourites, AI actions |
| 11 | Power tools | server library, test lab |

---

## 10. Rules

1. **The Stage never navigates.** If a thing needs the whole screen, it is
   a sheet over the Stage.
2. **Gate on `BackendCapabilities`,** never `if (backend == comfy)`.
3. **Every number is Geist Mono.**
4. **Colour is earned.** Chrome is achromatic; the accent appears in three
   places only.
5. **No Lens/Prism inside a scrolling list.**
6. **Every control is ≥44pt.**
7. **Degrade, never break** — no-Impeller devices get plain blur and lose
   nothing functional.
