# Aperture — Desk

The design system. Everything here is reproducible in Flutter with flat
fills, solid strokes and transforms. **No shaders, no backdrop filters, no
blurred shadows anywhere.** That constraint is not a compromise — it is what
makes the look coherent.

---

## 1. The idea

Aperture is a **desk you work at**, not a screen you operate.

Every element is a physical object lying on a warm work surface: the source
image is a mounted sheet, each result is a photographic print, the tools live
in a tray bolted to the left edge, and the model you have loaded is a labelled
card tucked at the top.

Three consequences follow, and they decide almost every question later:

1. **Objects cast hard shadows, never soft ones.** A solid offset in ink at
   zero blur. This is how the design gets depth for free.
2. **Paper is square. Tools are rounded.** Anything that represents a physical
   sheet has sharp corners. Anything you press has soft ones. You can tell what
   is content and what is control without reading a word.
3. **Prints are never perfectly aligned.** Results land on the desk at a slight
   angle, like photographs actually do. The angle is deterministic per image,
   never random per frame.

### What this replaces

The previous direction ("Liquid Glass") is dead. It required per-pixel
refraction over a full-screen backdrop every frame, which no phone should
spend its GPU on for chrome. Nothing in this document costs more than a
rounded rectangle.

---

## 2. Colour

One surface, one paper, one ink, one accent. That is the whole palette.
Resist adding a second accent — the design gets its energy from contrast and
shadow, not from hue.

### Day (default)

| Token | Hex | Use |
|---|---|---|
| `desk` | `#DED2BC` | The work surface. The app's background, always. |
| `deskGrain` | `#000000` @ 2.8% | Diagonal grain over `desk`. Texture only, never structural. |
| `paper` | `#FBF7EF` | Every object that sits on the desk: sheets, prints, fields, cards. |
| `paperEdge` | `#EFE8D9` | The mat inset inside a mounted sheet; disabled paper. |
| `ink` | `#211C14` | All borders, all shadows, primary text, the tool tray. |
| `inkMuted` | `#4C4536` | Secondary text on paper. |
| `inkFaint` | `#7A7364` | Labels, units, placeholder text. |
| `clay` | `#C4472F` | **The only accent.** Primary actions, active state, live handles. |
| `clayDeep` | `#A9331E` | The pressed/under-edge of a clay object. |

### Night

A desk lamp turned down, not an inversion. Same objects, less light. Paper
stays lighter than the desk; ink stays the darkest thing on screen.

| Token | Hex |
|---|---|
| `desk` | `#2A241B` |
| `deskGrain` | `#000000` @ 5% |
| `paper` | `#E4DAC4` |
| `paperEdge` | `#D5CAB2` |
| `ink` | `#14110C` |
| `inkMuted` | `#3E382C` |
| `inkFaint` | `#6A6252` |
| `clay` | `#D4573C` |
| `clayDeep` | `#B03B22` |

### Semantic

Used for meaning only, never for decoration. Each appears as a stamp — text
plus a 2px border, no fill — so they never compete with `clay`.

| Token | Hex | Meaning |
|---|---|---|
| `good` | `#4A7A46` | Connected, saved, complete |
| `caution` | `#C98A1E` | Queued, degraded, unverified |
| `alert` | `#A32B1C` | Failed, unreachable, destructive |

### Engine identity

Forge and ComfyUI are **not** distinguished by colour. They are distinguished
by what the card at the top of the screen says, and by which tools exist in
the tray. Introducing a per-engine hue would break the single-accent rule and
make the two engines look like two apps.

---

## 3. Type

Two families, both already bundled.

- **Geist** — everything a person reads.
- **Geist Mono** — everything a machine produced: values, units, counts,
  labels, IDs, timestamps.

The split is semantic, not decorative. If a number can change as a result of
something the server did, it is Mono with `FontFeature.tabularFigures()` so it
cannot reflow while it updates.

| Style | Family | Size | Weight | Tracking | Use |
|---|---|--:|--:|--:|---|
| `deskTitle` | Geist | 24 | 650 | -0.035em | Screen title, once per screen |
| `sheetTitle` | Geist | 19 | 650 | -0.025em | Drawer and modal headings |
| `body` | Geist | 13.5 | 400 | 0 | Prose, prompt text |
| `label` | Geist | 12 | 600 | -0.01em | Button and control labels |
| `value` | Geist | 20 | 650 | -0.03em | A parameter's current value, set large |
| `micro` | Mono | 8.5 | 400 | 0.16em | UPPERCASE captions on objects |
| `readout` | Mono | 12 | 500 | 0.02em | Live numbers, tabular |

Rules:

- Micro is **always uppercase** and always Mono. It is the label printed on a
  physical thing — a negative sleeve, a file tab.
- Never set body text below 12px. Micro is the only exception and it is never
  prose.
- One `deskTitle` per screen. Two competing titles means the screen is two
  screens.

---

## 4. Space, borders, corners

### Spacing scale

`4 · 8 · 12 · 16 · 24 · 32 · 48`. Nothing between these values.

Screen gutter is **12** on the outer edges, **16** for content that sits
inside a paper object. The tool tray owns the left **44** and content starts
after it.

### Borders

| Weight | Use |
|---|---|
| `1px ink @ 20%` | Hairline divider inside a paper object |
| `2px ink` | **The default.** Every interactive paper object: buttons, fields, chips, dropdowns |
| `2.5px clay` | Live/draggable affordances only — outpaint handles, the active mask brush |
| `3px ink` | The mounted sheet's outer frame |

There is no such thing as a borderless control on paper. If it can be pressed
and it sits on the desk, it is outlined in ink.

### Corners

This is the rule that makes the design legible:

| Radius | Applies to |
|---|---|
| `0` | **Paper as content** — the mounted sheet, prints, the negative strip |
| `2` | Photographic edges where a hairline round reads better at small sizes |
| `10` | **Controls** — chips, fields, tool buttons, dropdown cards |
| `12` | Larger control surfaces — parameter slabs, drawer heads |
| `999` | Nothing. Aperture has no pill shapes. |

Pills are banned. A pill reads as a soft digital token and fights everything
else on the desk. Buttons are rounded rectangles.

---

## 5. Depth — the hard shadow

Depth is a **solid offset in ink at zero blur**, always down-right, always at
the same 3:4 ratio between x and y. Never a soft shadow. Never a gradient.

| Elevation | Offset | Opacity | Applies to |
|---|---|--:|---|
| `rest` | `2, 3` | 22% | Prints, chips, small cards |
| `raised` | `3, 4` | 22% | Buttons, fields, dropdowns at rest |
| `sheet` | `4, 6` | 22% | The mounted source sheet |
| `drawer` | `0, -6` | 28% | Modals rising from the bottom edge (shadow points **up**) |
| `lifted` | `6, 8` | 26% | An object being dragged |

The offset is what encodes height, so it must never be animated to a *different
direction* — only to a smaller or larger magnitude along the same diagonal.

---

## 6. Motion

Motion is spring-driven and physical. Objects have weight; they overshoot and
settle. Nothing fades in place — things arrive from somewhere.

### Springs

| Name | Stiffness | Damping | Use |
|---|--:|--:|---|
| `press` | 420 | 26 | Button down/up |
| `settle` | 300 | 22 | A print landing, a drawer opening |
| `snap` | 520 | 30 | Tool selection, toggle travel |
| `drift` | 140 | 18 | Idle hints, handle pulse |

Durations, where a spring is not appropriate: **90ms** press-in, **220ms**
cross-fade, **320ms** drawer, **420ms** print arrival.

### The five named motions

1. **Press-into-shadow.** On tap down, the object translates by exactly its
   shadow offset and its shadow shrinks to `1,1`. On release it springs back
   past rest by ~4% and settles. This is the app's signature interaction and
   every pressable thing does it — no ripples, no opacity changes.

2. **Print arrival.** A new result enters from beyond the right edge at
   `+20°` rotation, travels on the `settle` spring to its resting angle, and
   nudges its neighbours aside. Batches stagger by **80ms** per print.

3. **Handle pulse.** Outpaint handles scale `1.0 → 1.35 → 1.0` on the `drift`
   spring over 4.4s, forever, until touched. This is the only permanently
   animating element in the app and it exists to teach one non-obvious gesture.

4. **Drawer rise.** Modals translate up from the bottom edge on `settle`, with
   the desk behind them darkening to `ink @ 32%` — a flat scrim, never a blur.

5. **Tab slide.** The active fill in a tray or tab strip travels between
   positions on `snap` while the labels stay put.

### Reduced motion

When `MediaQuery.disableAnimations` is true: press-into-shadow becomes an
instant state change, print arrival becomes a 120ms fade, and the handle pulse
stops entirely. Layout never depends on an animation having run.

### Rotation is deterministic

A print's resting angle comes from its image id, not from `Random()`:

```dart
double restAngleFor(String id) => ((id.hashCode % 9) - 4) * 0.9 * pi / 180;
```

Range −3.6° to +3.6°. Computing it per build from a stable input means a print
never jitters when the list rebuilds — the single most common way this kind of
design goes wrong.

---

## 7. Components

### 7.1 Desk

The app background. `desk` fill plus a diagonal grain: repeating 96° lines,
2px on / 7px off, at `deskGrain`. Painted once by a `CustomPainter` in a
`RepaintBoundary` — it never animates and must never be rebuilt.

### 7.2 Mounted sheet — the source image

The single most important object. A paper rectangle with a **3px ink** frame
and `sheet` elevation. The image sits inset by **12** on all sides, so the
paper reads as a mat board around a photograph.

- Corner radius `0`. It is paper.
- Micro caption `SOURCE` bottom-left, inside the image, in `paper` over the
  photograph.
- Four **outpaint handles** at the corners: 16×16, `paper` fill, `2.5px clay`
  border, pulsing on `drift`. Dragging one extends the canvas.
- Mask strokes are painted directly on the image area in `clay @ 45%`.

### 7.3 Print — a result

A small paper rectangle with **5px** padding on three sides and **14px** at
the bottom, exactly like a photographic print with a wide lower margin. Holds
the image at radius `0`, carries `rest` elevation, and sits at its
deterministic angle.

- Selected: the ink border thickens to 2px and elevation goes to `raised`.
- Prints overlap by about a third of their width along the shelf.
- Batch count appears as a micro stamp on the shelf's left end (`×4`).

### 7.4 Tool tray

A tray of `ink` bolted to the **left edge**, full height of the work area,
44 wide, radius `0` on the left and `16` on the right — because it is attached
to the frame, not lying on the desk.

- Tools are 30×30, radius `10`, icon in `paper @ 70%`.
- The active tool has a `clay` fill and `paper` icon; the fill slides between
  positions on `snap`.
- The tray is **capability-gated**: it holds only the tools the active engine
  actually supports, read from `EngineCapabilities` — never from an
  `if (isComfy)`. A missing tool leaves no gap; the tray is shorter.
- The tray is also **context-gated**, on top of capability-gating. Which
  tools appear depends on what's on the sheet right now: typing a fresh
  text2img prompt calls for workflow/checkpoint and LoRAs; an image loaded
  for img2img calls for the mask brush and the outpaint toggle; viewing a
  past result calls for upscale, save, compare-to-source, and send-back-to-
  source. The tray widget itself stays dumb — it just renders whatever tool
  list it's handed — the front page decides the list from
  `(engine, sessionMode, viewingResult)`.

### 7.5 Card — the loaded model

A small `ink` rectangle with `paper` micro text, radius `2`, tucked into the
top row. Shows the checkpoint (Forge) or the workflow (ComfyUI). A second card
in `clay` shows LoRA count when any are active. Tapping opens the picker
drawer.

### 7.6 Buttons

Rounded rectangle, radius `10`, **2px ink** border, `raised` elevation,
`label` type, minimum height **44**.

| Variant | Fill | Text |
|---|---|---|
| Primary | `clay` | `paper` |
| Secondary | `paper` | `ink` |
| Ghost | none | `ink`, border only |
| Destructive | `paper` | `alert`, border `alert` |

All four press into their shadow. Disabled: fill `paperEdge`, border and text
`inkFaint`, elevation removed, no press response.

### 7.7 Field — prompt and text entry

`paper` fill, **2px ink** border, radius `10`, padding `12×14`. Micro label
sits **above and outside** the field in `inkFaint`, never as a placeholder,
because a placeholder disappears exactly when you need it.

Focused: border becomes **2.5px clay**. No glow, no colour change to the fill.

### 7.8 Chip — a value at a glance

`paper` fill, **2px ink** border, radius `10`, `rest` elevation. Two lines:
micro unit label above in `inkFaint`, `value` type below in `ink`. Tapping
opens that parameter's control; dragging horizontally scrubs it in place.

### 7.9 Slider — the ruler

Sliders are **rulers**, because a desk has one.

- Track: `paperEdge` fill, `2px ink` border, height 26, radius `2`.
- Ticks: 1px ink lines at 10% intervals, taller at 50%.
- Fill: `clay` from the left up to the value, drawn **behind** the ticks.
- Thumb: a 22×34 `paper` tab with a 2px ink border and `rest` elevation — it
  sticks up above the track like a brass slide. It carries the value in
  `readout` type.
- Dragging lifts the thumb to `lifted` and it presses back down on release.

### 7.10 Dropdown — the index card

Never a native menu. Tapping the trigger drops a `paper` card with a **2px
ink** border, radius `10` and `raised` elevation, anchored under the trigger,
arriving on `settle` with a 4px overshoot.

- Rows are 44 tall, separated by hairlines.
- The selected row carries a `clay` left bar 3px wide and its label in `ink`
  at weight 600.
- Over 8 items, the card gets a fixed max height and scrolls; it never covers
  its own trigger.

### 7.11 Toggle — the tab in a slot

A 52×30 `paperEdge` slot with a 2px ink border and radius `10`, holding a
24×24 `paper` tab with a 2px ink border. The tab travels on `snap`. When on,
the **slot** fills `clay`; the tab itself never changes colour, because a
physical tab doesn't.

### 7.12 Tab strip — file tabs

Tabs are folder tabs: `paper` with a 2px ink border, radius `10` on the top
corners only and `0` on the bottom, sitting flush on the surface they label.
The active tab fills `clay`, sits 2px higher, and its bottom border is removed
so it joins the panel below.

### 7.13 Drawer — the modal

Every modal is a drawer pulled up from the bottom edge. Full width, `paper`
fill, **3px ink** top border, radius `12` on the top corners only, `drawer`
elevation. A 40×4 ink handle sits centred at the top.

- Rises on `settle` over 320ms; the desk behind darkens to a flat `ink @ 32%`.
- Drag down to dismiss, with velocity carried.
- Maximum height 88% of the screen. A drawer that would exceed it scrolls
  internally, keeping its head and its primary action pinned.

Drawers hold: model/workflow picker, LoRA picker, prompt history, generation
settings, the server gallery, upscale, crop.

### 7.14 Progress — the filling ruler

Generation progress reuses the ruler: the same track, filling in `clay`, with
the `readout` percentage on the thumb. Indeterminate progress shows a 25%
segment travelling the track on a 1.4s loop.

Live preview frames from ComfyUI render **into the print that is being
generated** — the print exists on the shelf from the moment the run is queued,
starting as `paperEdge` and filling in as frames arrive. A batch shows all its
empty prints immediately, so you can see how many are coming.

### 7.15 Sticky note — the toast

Transient messages are sticky notes: `paper` fill, no border, `rest`
elevation, rotated by −2°, arriving from the top-right on `settle`. Errors use
an `alert` 2px border and `alert` text. Auto-dismiss at 4s, or swipe away.

---

## 8. Layout

The front page, top to bottom:

```
┌────────────────────────────────────────┐
│  Aperture        [MODEL CARD] [LORA]   │  56  title row
│ ┌──┐ ┌──────────────────────────────┐  │
│ │T │ │                              │  │
│ │o │ │      MOUNTED SHEET           │  │  flexible
│ │o │ │      (source + mask)         │  │
│ │l │ │                              │  │
│ │s │ └──────────────────────────────┘  │
│ │  │   ▟ ▟ ▟ ▟   the print shelf      │  110
│ └──┘                                   │
│  ┌──────────────────────────────────┐  │
│  │ prompt field                     │  │  ~44
│  └──────────────────────────────────┘  │
│  [.62] [28] [×4]          [ GENERATE ] │  48  chip row
└────────────────────────────────────────┘
```

Rules:

- The **sheet is always the largest object on screen.** If a feature needs
  more room than is left, it goes in a drawer.
- The **tray is always present** and always on the left. It is the only
  persistent navigation; there is no bottom bar.
- The **print shelf never scrolls the page.** It scrolls horizontally within
  its own band, and it is always visible, because comparing a result to the
  source is the app's core act.
- The **generate button is always bottom-right**, always `clay`, always the
  same size. It is the one control whose position never changes.

### Capability gating

The screen's shape is driven entirely by `EngineCapabilities`:

| Flag off | Effect |
|---|---|
| `loras` | The LoRA card disappears from the title row |
| `checkpoints` | The model card shows the workflow instead |
| `masks` | The brush tool leaves the tray; handles stay for outpaint |
| `livePreview` | Prints appear filled on completion rather than progressively |
| `serverLibrary` | The gallery tool leaves the tray |
| `stitching` | The stitch tool leaves the tray |

No screen may branch on the engine enum. Every branch reads a flag.

---

## 9. Rules

**Always**

- Shadows are solid ink, offset down-right, zero blur.
- Paper content is square; controls are radius 10.
- Every pressable object presses into its own shadow.
- Machine-produced numbers are Mono with tabular figures.
- Print angles are derived from the image id.
- Touch targets are at least 44×44.
- Capability flags decide what exists, never the engine enum.

**Never**

- No blurred shadows, no gradients on chrome, no glass, no shaders.
- No pill shapes.
- No second accent colour. `clay` is it.
- No placeholder-as-label.
- No native Material dropdowns, switches or dialogs — every one is replaced.
- No ripple effects. The press-into-shadow is the feedback.
- No permanently animating element except the outpaint handles.
- No bottom navigation bar.

---

## 10. Build order

1. `ui/desk/desk_tokens.dart` — colour, type, space, elevation, motion
2. `ui/desk/desk_surface.dart` — desk, grain painter, paper, sheet, print
3. `ui/desk/desk_controls.dart` — button, field, chip, ruler, toggle, tabs
4. `ui/desk/desk_overlays.dart` — dropdown, drawer, sticky note
5. Front page — tray, title row, sheet, shelf, prompt, chips, generate
6. Drawers — model picker, LoRA picker, parameters, prompt history
7. Server gallery, upscale, crop
8. Test lab
