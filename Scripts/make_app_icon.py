"""Generates Crumbs' AppIcon.icon package (Icon Composer format).

Usage: python3 Scripts/make_app_icon.py [output.icon] [--variant white|ink] [--font NAME]

Design: a typographic mark. "CRUMBS*" is set in three tight rows (CR / UM / BS*)
in Geist Pixel on a warm yellow background, with the asterisk as its own layer
so it can carry an accent colour.

The letters are converted to vector paths by Scripts/text_paths.swift (CoreText),
so the icon doesn't depend on fonts being installed. Every SVG covers the full
1024x1024 canvas at scale 1. macOS applies the rounded-square mask, and Icon
Composer adds the shadows, and Liquid Glass highlights on the asterisk only.
"""
import argparse
import json
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 1024

parser = argparse.ArgumentParser(description="Generate Crumbs' AppIcon.icon package.")
parser.add_argument("output", nargs="?", default=os.path.join(HERE, "..", "Crumbs", "AppIcon.icon"),
                    help="where to write the .icon package (default: Crumbs/AppIcon.icon)")
parser.add_argument("--variant", choices=["ink", "white"], default="white",
                    help="white: white letters on golden yellow (default); ink: dark letters on yellow")
parser.add_argument("--stroke", type=float, default=None,
                    help="thicken the letters by this many points (pixel fonts default to 11)")
parser.add_argument("--font", default="pixel",
                    help="pixel (default), pixel-grid, pixel-circle, pixel-line, pixel-triangle, or sf")
options = parser.parse_args()
OUT = options.output
VARIANT = options.variant

# ---------------------------------------------------------------------------
# Palette (hex, Display P3)
# ---------------------------------------------------------------------------
VARIANTS = {
    # Dark ink letters on yellow, with an orange asterisk.
    "ink": dict(bg=("#FFD84D", "#FFB300"), text="#1D1A14", star="#FF5A1F"),
    # White letters on a deeper golden yellow, closest to the reference.
    "white": dict(bg=("#FFC530", "#FF9F0A"), text="#FFFFFF", star="#FFFFFF"),
}
PALETTE = VARIANTS[VARIANT]
# Dark mode flips it: yellow letters on warm black.
DARK = dict(bg=("#2A2416", "#100D07"), text="#FFC83D", star="#FF7A33")

# ---------------------------------------------------------------------------
# Type and layout
# ---------------------------------------------------------------------------
# name: (PostScript name or "system", weight, asterisk scale)
# Geist Pixel (OFL, github.com/vercel/geist-pixel-font) must be installed. Its
# asterisk keeps scale 1 so its pixels line up with the letters'.
FONTS = {
    "pixel": ("GeistPixel-Regular", 0, 1.0),
    "pixel-grid": ("GeistPixel-Regular_Grid", 0, 1.0),
    "pixel-circle": ("GeistPixel-Regular_Circle", 0, 1.0),
    "pixel-line": ("GeistPixel-Regular_Line", 0, 1.0),
    "pixel-triangle": ("GeistPixel-Regular_Triangle", 0, 1.0),
    "sf": ("system", 0.62, 1.25),  # SF Pro Black
}
if options.font not in FONTS:
    parser.error(f"unknown font {options.font!r}; choose from {', '.join(FONTS)}")
FONT, WEIGHT, STAR_SCALE = FONTS[options.font]
# Geist Pixel ships one weight with one-pixel strokes. A square-cornered outline in the
# same colour fattens every pixel so the mark has poster weight at icon size.
STROKE = options.stroke if options.stroke is not None else (11 if options.font.startswith("pixel") else 0)

ROWS = ["CR", "UM", "BS"]
CAP_HEIGHT = 202      # letter height on the 1024pt canvas
ROW_STEP_RATIO = 1.21  # baseline to baseline, relative to cap height: tight, like a poster
LEFT = 184            # left edge of the text block
RIGHT_LIMIT = 860     # nothing may extend past this x
STAR_GAP = 8          # space between "S" and the asterisk


def text_paths(font_size, *texts):
    out = subprocess.run(
        ["swift", os.path.join(HERE, "text_paths.swift"), FONT, str(WEIGHT), str(font_size), *texts],
        check=True, capture_output=True, text=True,
    ).stdout
    return {item["text"]: item for item in json.loads(out)}


# Size the type from the font's own proportions, shrinking it if a row would run too wide.
probe = text_paths(100, *ROWS, "*")
cap_ratio = probe["BS"]["capHeight"] / 100
widest = max(probe[row]["width"] for row in ROWS[:-1])
last_row = probe[ROWS[-1]]["width"] + STAR_GAP / 100 + probe["*"]["width"] * STAR_SCALE
FONT_SIZE = min(CAP_HEIGHT / cap_ratio, (RIGHT_LIMIT - LEFT) / (max(widest, last_row) / 100))
cap = cap_ratio * FONT_SIZE
ROW_STEP = cap * ROW_STEP_RATIO
block_height = ROW_STEP * (len(ROWS) - 1) + cap
FIRST_BASELINE = (SIZE - block_height) / 2 + cap


def svg(body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
        f'viewBox="0 0 {SIZE} {SIZE}">\n{body}\n</svg>\n'
    )


def p3(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},1.00000"


def gradient(top, bottom):
    return {
        "linear-gradient": [p3(top), p3(bottom)],
        "orientation": {"start": {"x": 0.5, "y": 0.0}, "stop": {"x": 0.5, "y": 1.0}},
    }


glyphs = text_paths(FONT_SIZE, *ROWS, "*")


def paint(color, scale=1.0):
    """Fill, plus the thickening outline when STROKE is set."""
    attrs = f'fill="{color}"'
    if STROKE:
        attrs += f' stroke="{color}" stroke-width="{STROKE / scale:.2f}" stroke-linejoin="miter"'
    return attrs

letters = []
for i, row in enumerate(ROWS):
    baseline = FIRST_BASELINE + i * ROW_STEP
    letters.append(
        f'<path transform="translate({LEFT},{baseline:.1f})" d="{glyphs[row]["d"]}" {paint(PALETTE["text"])}/>'
    )

last_baseline = FIRST_BASELINE + (len(ROWS) - 1) * ROW_STEP
star_x = LEFT + glyphs[ROWS[-1]]["width"] + STAR_GAP
# Scale the asterisk, then pin its top to the cap height so it sits like a footnote mark.
star_box = glyphs["*"]["bounds"]
cap_top = last_baseline - glyphs["BS"]["capHeight"]
star_y = cap_top - star_box["y"] * STAR_SCALE
star_x -= star_box["x"] * STAR_SCALE
star = (
    f'<path transform="translate({star_x:.1f},{star_y:.1f}) scale({STAR_SCALE})" '
    f'd="{glyphs["*"]["d"]}" {paint(PALETTE["star"], STAR_SCALE)}/>'
)

if os.path.exists(OUT):
    shutil.rmtree(OUT)
assets = os.path.join(OUT, "Assets")
os.makedirs(assets)
with open(os.path.join(assets, "Letters.svg"), "w") as f:
    f.write(svg("\n".join(letters)))
with open(os.path.join(assets, "Asterisk.svg"), "w") as f:
    f.write(svg(star))


def fills(light, dark):
    return [{"value": {"solid": p3(light)}}, {"appearance": "dark", "value": {"solid": p3(dark)}}]


icon = {
    "fill-specializations": [
        {"value": gradient(*PALETTE["bg"])},
        {"appearance": "dark", "value": gradient(*DARK["bg"])},
    ],
    "groups": [
        {
            "name": "Asterisk",
            "layers": [{
                "name": "Asterisk", "image-name": "Asterisk.svg", "hidden": False,
                "fill-specializations": fills(PALETTE["star"], DARK["star"]),
                "position": {"scale": 1, "translation-in-points": [0, 0]},
            }],
            "specular": True,
            "shadow": {"kind": "layer-color", "opacity": 0.5},
            "translucency": {"enabled": False, "value": 0},
        },
        {
            "name": "Letters",
            "layers": [{
                "name": "Letters", "image-name": "Letters.svg", "hidden": False,
                # Flat, solid ink like printed type. Glass would make the letters see-through.
                "glass": False,
                "fill-specializations": fills(PALETTE["text"], DARK["text"]),
                "position": {"scale": 1, "translation-in-points": [0, 0]},
            }],
            "specular": False,
            "shadow": {"kind": "neutral", "opacity": 0.25},
            "translucency": {"enabled": False, "value": 0},
        },
    ],
    "supported-platforms": {"squares": "shared"},
}

with open(os.path.join(OUT, "icon.json"), "w") as f:
    json.dump(icon, f, indent=2)
print("wrote", os.path.normpath(OUT), f"({VARIANT}, {options.font})")
