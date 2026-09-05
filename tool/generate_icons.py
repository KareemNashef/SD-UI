"""Generates Aperture's launcher icon and splash mark from the Desk palette.

Kept in the repo rather than hand-drawn once and forgotten, so the icon can
be regenerated when the palette moves - DESIGN.md is the source of truth for
those colours, and an icon that drifts from them is the one surface nobody
notices going stale.

The mark is a camera iris: a clay ring with a hexagonal opening and six blade
edges cut through it. It was chosen because it survives being 48px in a
launcher, which rules out anything with fine detail or text.

Run: python tool/generate_icons.py
"""

import math
import os

from PIL import Image, ImageDraw

# DESIGN.md section 2. Day values; the night desk is only needed for the
# splash background, which Android resolves from XML rather than from here.
DESK = (222, 210, 188)
DESK_GRAIN = (0, 0, 0)
PAPER = (251, 247, 239)
INK = (33, 28, 20)
CLAY = (196, 71, 47)

SIZE = 1024
OUT = "assets/icon"

# Supersampling factor. The blade cuts are thin wedges, and drawing them at
# final size leaves visibly stepped edges at launcher scale.
SS = 4


def _canvas(colour=None):
    mode = "RGB" if colour else "RGBA"
    fill = colour if colour else (0, 0, 0, 0)
    return Image.new(mode, (SIZE * SS, SIZE * SS), fill)


def _grain(image):
    """The desk's diagonal grain, matching `_GrainPainter` in desk_surface."""
    draw = ImageDraw.Draw(image, "RGBA")
    span = SIZE * SS
    spacing = 9 * SS
    slant = math.tan(math.radians(6)) * span
    for x in range(int(-abs(slant) - spacing), int(span + spacing), int(spacing)):
        draw.line(
            [(x, 0), (x + slant, span)],
            fill=DESK_GRAIN + (7,),
            width=2 * SS,
        )
    return image


def _iris(image, centre, radius, ring, opening, blades=PAPER, outline=INK):
    """Draws the aperture mark.

    A clay annulus with a hexagonal hole, then six wedges cut out of it to
    read as overlapping blades. Every cut is filled with the *surrounding*
    colour rather than punched to transparency, so the same routine works on
    an opaque background and on a transparent foreground layer.
    """
    draw = ImageDraw.Draw(image, "RGBA")
    cx, cy = centre

    # The clay body.
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=CLAY + (255,) if len(CLAY) == 3 else CLAY,
    )

    # Hexagonal opening.
    hexagon = [
        (
            cx + opening * math.cos(math.radians(60 * k - 90)),
            cy + opening * math.sin(math.radians(60 * k - 90)),
        )
        for k in range(6)
    ]
    draw.polygon(hexagon, fill=blades)

    # Blade edges: a thin wedge from each opening vertex out past the rim.
    for k in range(6):
        vertex = hexagon[k]
        angle = math.radians(60 * k - 90)
        # Tangential direction, so the cut leans the way a real blade does.
        lean = angle + math.radians(58)
        far = (
            vertex[0] + math.cos(lean) * radius * 1.6,
            vertex[1] + math.sin(lean) * radius * 1.6,
        )
        width = radius * 0.055
        normal = (math.cos(lean + math.pi / 2), math.sin(lean + math.pi / 2))
        draw.polygon(
            [
                (vertex[0] + normal[0] * width, vertex[1] + normal[1] * width),
                (vertex[0] - normal[0] * width, vertex[1] - normal[1] * width),
                (far[0] - normal[0] * width, far[1] - normal[1] * width),
                (far[0] + normal[0] * width, far[1] + normal[1] * width),
            ],
            fill=blades,
        )

    # Re-draw the opening on top: the wedges above cut across it.
    draw.polygon(hexagon, fill=blades)

    if outline is not None:
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            outline=outline,
            width=int(ring),
        )
        draw.polygon(hexagon, outline=outline, width=int(ring * 0.8))


def _mask_to_disc(image, centre, radius):
    """Clips an RGBA layer to the mark's own outline.

    The blade cuts are drawn as wedges running well past the rim, which is
    what gives them a straight edge across the ring. On the opaque legacy
    icon the overhang lands on desk colour and vanishes; on a transparent
    layer it survives as six sticks radiating out of the disc. Clipping is
    the fix, not shortening the wedges - a wedge that stops exactly at the
    rim leaves a visible seam where it meets the curve.
    """
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).ellipse(
        [centre[0] - radius, centre[1] - radius,
         centre[0] + radius, centre[1] + radius],
        fill=255,
    )
    clipped = image.copy()
    alpha = clipped.getchannel("A")
    alpha = Image.composite(alpha, Image.new("L", image.size, 0), mask)
    clipped.putalpha(alpha)
    return clipped


def _save(image, name):
    image.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name))
    print("wrote", os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)
    full = SIZE * SS
    centre = (full / 2, full / 2)

    # --- Legacy square icon: the mark on a grained desk ---
    legacy = _grain(_canvas(DESK))
    _iris(legacy, centre, full * 0.30, ring=full * 0.014,
          opening=full * 0.115, blades=DESK)
    _save(legacy, "icon.png")

    # --- Adaptive background: desk and grain only ---
    background = _grain(_canvas(DESK))
    _save(background, "icon_background.png")

    # --- Adaptive foreground ---
    # Android crops an adaptive layer hard: only the middle ~66% is
    # guaranteed visible, and every launcher mask cuts differently. The mark
    # is sized to sit inside that safe circle.
    fg_radius = full * 0.245
    fg_ring = full * 0.0105
    foreground = _canvas()
    _iris(foreground, centre, fg_radius, ring=fg_ring,
          opening=full * 0.094, blades=DESK)
    _save(_mask_to_disc(foreground, centre, fg_radius + fg_ring / 2),
          "icon_foreground.png")

    # --- Monochrome, for Android 13 themed icons ---
    # The system recolours this, so only the silhouette matters: solid mark,
    # transparent cuts.
    mono = _canvas()
    _iris(mono, centre, fg_radius, ring=0,
          opening=full * 0.094, blades=(0, 0, 0, 0), outline=None)
    mono = _mask_to_disc(mono, centre, fg_radius)
    black = Image.new("RGBA", mono.size, (0, 0, 0, 255))
    black.putalpha(mono.getchannel("A"))
    _save(black, "icon_monochrome.png")

    # --- Splash mark ---
    # No ink outline and no plate: ink on the night desk is nearly the same
    # colour, and any plate would reinstate exactly the white box this is
    # replacing. Clay alone reads on both desk tones, and the cuts are
    # transparent so the splash background shows through them.
    splash_radius = full * 0.30
    splash = _canvas()
    _iris(splash, centre, splash_radius, ring=0,
          opening=full * 0.115, blades=(0, 0, 0, 0), outline=None)
    _save(_mask_to_disc(splash, centre, splash_radius), "splash_icon.png")


if __name__ == "__main__":
    main()
