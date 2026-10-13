"""Generate the amber dithered cloud background for the Crumbs site.

Usage: python3 scripts/gen-dither.py OUT.png [variant] [cols] [rows]   (needs Pillow)
The site uses the defaults (320x272 cells) and a narrow variant at 160x200 cells.

Output: a palette PNG where every dither cell is CELL x CELL image pixels, shown
at 1 image px = 1 CSS px with image-rendering: pixelated.
"""
import math, random, sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "public/images/dither-cloud.png"
VARIANT = sys.argv[2] if len(sys.argv) > 2 else "gap"

CELL = 3
CW = int(sys.argv[3]) if len(sys.argv) > 3 else 320
CH = int(sys.argv[4]) if len(sys.argv) > 4 else 272
random.seed(7)

# Ramp from paper to deepest tint. Index 0 is transparent so the layer sits on any white.
RAMP = [
    (255, 255, 255, 0),
    (255, 247, 222, 255),  # cream
    (255, 239, 169, 255),  # hl-yellow
    (255, 211, 148, 255),  # hl-amber
    (255, 197, 49, 255),  # yellow
    (255, 178, 31, 255),  # amber-bright
]

BAYER = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
]


def smooth(t):
    return t * t * (3 - 2 * t)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return smooth(t)


class Noise:
    def __init__(self, seed):
        r = random.Random(seed)
        self.p = [r.random() for _ in range(256 * 256)]

    def v(self, x, y):
        xi, yi = math.floor(x), math.floor(y)
        xf, yf = x - xi, y - yi
        def g(i, j):
            return self.p[((xi + i) & 255) * 256 + ((yi + j) & 255)]
        u, w = smooth(xf), smooth(yf)
        a = g(0, 0) + (g(1, 0) - g(0, 0)) * u
        b = g(0, 1) + (g(1, 1) - g(0, 1)) * u
        return a + (b - a) * w

    def fbm(self, x, y, oct=5):
        s, amp, tot = 0.0, 0.5, 0.0
        for _ in range(oct):
            s += amp * self.v(x, y)
            tot += amp
            x, y, amp = x * 2.03, y * 2.03, amp * 0.5
        return s / tot


n1, n2, n3 = Noise(1), Noise(2), Noise(3)

# Cumulus clusters (u, v, rx, ry, weight). Kept off-center so they peek out around
# whatever sits on top of the layer.
BLOBS = [
    (0.22, 0.28, 0.30, 0.20, 0.8),
    (0.78, 0.22, 0.30, 0.18, 0.8),
    (0.50, 0.48, 0.42, 0.26, 0.6),
    (0.08, 0.58, 0.20, 0.20, 0.7),
    (0.92, 0.56, 0.20, 0.20, 0.7),
]

if CW < CH:
    BLOBS = [
        (0.28, 0.16, 0.36, 0.13, 0.8),
        (0.82, 0.30, 0.30, 0.15, 0.8),
        (0.12, 0.50, 0.26, 0.16, 0.7),
        (0.88, 0.62, 0.24, 0.12, 0.6),
        (0.50, 0.40, 0.40, 0.20, 0.35),
    ]

HORIZON = 0.72


def field(u, v):
    # Noise is sampled in absolute cell units so features keep their size in every variant.
    nu, nv = u * CW / 320, v * CH / 272
    # Sky: faint warm wash that thickens toward the horizon.
    sky = 0.06 + 0.16 * smoothstep(0.0, HORIZON, v)

    d = 0.0
    for bu, bv, rx, ry, w in BLOBS:
        q = ((u - bu) / rx) ** 2 + ((v - bv) / ry) ** 2
        d += w * math.exp(-q)
    d = min(1.0, d)
    # Domain-warped fbm gives billowy cumulus edges instead of smooth blobs.
    wx = n2.fbm(nu * 3.0 + 5.2, nv * 3.0 + 1.3, 3) - 0.5
    wy = n2.fbm(nu * 3.0 + 9.7, nv * 3.0 + 4.1, 3) - 0.5
    billow = n1.fbm(nu * 4.2 + wx * 1.4, nv * 5.2 + wy * 1.4, 6)
    c = smoothstep(0.40, 0.68, billow * 0.75 + d * 0.38)
    # Inner texture: denser pockets read as shaded undersides.
    shade = n3.fbm(nu * 9.0 + 3.1, nv * 11.0 + 1.7, 4)
    cloud = c * (0.20 + 0.38 * smoothstep(0.35, 0.75, shade) + 0.14 * smoothstep(0.15, 0.7, v))

    # Ground band below the horizon: long horizontal streaks, like a blurred field.
    g = smoothstep(HORIZON - 0.03, HORIZON + 0.04, v)
    streak = n3.fbm(nu * 2.5 + 7.0, nv * 30.0, 4)
    ground = g * (0.46 + 0.44 * streak) * (1 - 0.35 * smoothstep(HORIZON + 0.08, 1.0, v))
    # A slightly brighter line right on the horizon.
    rim = 0.10 * math.exp(-(((v - HORIZON) / 0.012) ** 2))

    val = max(sky + cloud * (1 - g), ground) + rim

    # Soft elliptical vignette so the layer fades to white on every side.
    r = math.sqrt(((u - 0.5) / 0.54) ** 2 + ((v - 0.5) / 0.62) ** 2)
    vig = (1 - smoothstep(0.55, 1.0, r)) * (1 - smoothstep(0.86, 1.0, v))
    return max(0.0, min(0.999, val * vig))


def main():
    W, H = CW * CELL, CH * CELL
    img = Image.new("P", (W, H), 0)
    pal = []
    for c in RAMP:
        pal += list(c[:3])
    img.putpalette(pal)
    px = img.load()
    levels = len(RAMP) - 1
    for cy in range(CH):
        for cx in range(CW):
            val = field((cx + 0.5) / CW, (cy + 0.5) / CH) * levels
            lo = int(val)
            frac = val - lo
            t = (BAYER[cy % 8][cx % 8] + 0.5) / 64
            hi = min(levels, lo + 1)
            idx = hi if frac > t else lo
            x0, y0 = cx * CELL, cy * CELL
            if VARIANT == "gap":
                # Square dot with a one pixel gutter in the lower tone.
                for yy in range(CELL):
                    for xx in range(CELL):
                        dot = xx < CELL - 1 and yy < CELL - 1
                        px[x0 + xx, y0 + yy] = idx if dot else max(0, lo - 1) if lo > 1 else 0
            else:
                for yy in range(CELL):
                    for xx in range(CELL):
                        px[x0 + xx, y0 + yy] = idx
    img.info["transparency"] = 0
    img.save(OUT, optimize=True, transparency=0)
    print(OUT, W, H)


main()
