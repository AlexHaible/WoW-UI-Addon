#!/usr/bin/env python3
"""Make the race themes' art by recolouring the original addon's faction art.

    python3 tools/make_race_themes.py            # all recoloured race themes
    python3 tools/make_race_themes.py dwarf troll

Each race theme starts from the Warcraft III faction set whose shapes suit it
(see RACES) and is written to ReforgedUI/art/<race>/ (the console) and
ReforgedUI/Media/<Folder>/ (the top bar). Every texture of the base set is
recoloured; alpha is kept as it is, so the pieces line up exactly as the base
set's do and Layout.lua lays them out with the base faction's corrections.

The recolour is a gradient map per material, not a tint:

1. Each pixel is given soft weights for the materials of its base set
   (e.g. the Human set: grey stone, gold trim, blue enamel, red glow) from its
   hue, saturation and brightness. A "dark" weight covers the near-black
   fills (the action grid's cells, the chat background).
2. Each material has its own gradient (shadow -> base colour -> highlight),
   whose stops sit at that material's own 5th, 50th and 95th luminance
   percentiles across the whole base set. A pixel of median brightness gets
   the race's base colour exactly, and the stone's cracks and highlights keep
   their contrast.
3. The weighted gradients are mixed, plus a little of the original's colour
   variation (DETAIL) so the result still looks painted rather than flat.

Palettes come from the race briefs (Dwarf: granite, bronze, forge ember, ...).
The script is deterministic: running it again gives the same files.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI"))
ART = os.path.join(ADDON, "art")
MEDIA = os.path.join(ADDON, "Media")

# Files of a base art set that are not part of the theme (left-overs of
# The original addon's own art folders).
SKIP = {"tx6.tga"}
MEDIA_FILES = ("panel.tga", "edge.tga", "edgev.tga", "corner.tga", "clockframe.tga")
MEDIA_FOLDER = {"human": "Human", "orc": "Orc", "undead": "Undead", "nightelf": "NightElf"}

# How much of the original colour's deviation from its material's gradient is
# kept (0 = pure gradient map).
DETAIL = 0.18
# How much of the original's brightness a material keeps (0 = the gradient's
# own, 1 = the original's exactly); a material's "keep" overrides it.
KEEP = 0.5


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hue_window(h, centre, half, feather=12.0):
    """1 inside centre +- half degrees of hue, fading out over `feather`."""
    d = np.abs(((h - centre + 180.0) % 360.0) - 180.0)
    return 1.0 - smoothstep(half, half + feather, d)


# Materials of each base set. Each function gets hue (degrees), saturation
# and value (0-1) arrays and returns a weight; the first material listed is
# the default and takes whatever weight the others leave.
BASES = {
    "human": {
        "stone": None,
        "gold": lambda h, s, v: hue_window(h, 42, 20) * smoothstep(0.35, 0.55, s) * smoothstep(0.18, 0.35, v),
        "blue": lambda h, s, v: hue_window(h, 225, 40) * smoothstep(0.20, 0.40, s),
        "glow": lambda h, s, v: hue_window(h, 5, 18) * smoothstep(0.30, 0.55, s),
    },
    "orc": {
        "wood": None,
        "iron": lambda h, s, v: 1.0 - smoothstep(0.10, 0.22, s),
        "red": lambda h, s, v: hue_window(h, 0, 14, 8) * smoothstep(0.50, 0.70, s) * smoothstep(0.15, 0.30, v),
    },
    "nightelf": {
        "wood": None,
        "stone": lambda h, s, v: 1.0 - smoothstep(0.12, 0.24, s),
        "leaf": lambda h, s, v: hue_window(h, 105, 50, 15) * smoothstep(0.18, 0.32, s),
    },
}

# Race themes: base set, top bar folder, the dark fill and one gradient per
# material: base colour, plus optional explicit shadow and highlight.
RACES = {
    "dwarf": {
        "base": "human", "folder": "Dwarf", "dark": "#231C17",
        "materials": {
            "stone": {"mid": "#7A6C5C", "lo": "#22180F", "hi": "#D6C2A4"},
            "gold": {"mid": "#B07A3A", "lo": "#3A220E", "hi": "#F2C27A"},
            "blue": {"mid": "#E07A2A", "lo": "#4A1A06", "hi": "#FFD08A", "keep": 0.85},
            "glow": {"mid": "#E0662A", "lo": "#3A1206", "hi": "#FFB45A", "keep": 1.0},
        },
    },
    "gnome": {
        "base": "human", "folder": "Gnome", "dark": "#1C2228",
        "materials": {
            "stone": {"mid": "#76899C", "lo": "#121C28", "hi": "#E2F0FA"},
            "gold": {"mid": "#B86B3A", "lo": "#3A1A0C", "hi": "#F6BE8C"},
            "blue": {"mid": "#5FD0E0", "lo": "#0C3440", "hi": "#D8FAFF", "keep": 0.85},
            "glow": {"mid": "#E0609E", "lo": "#3A0C22", "hi": "#FFC0DC", "keep": 1.0},
        },
    },
    "tauren": {
        "base": "orc", "folder": "Tauren", "dark": "#2A1C12",
        "materials": {
            "wood": {"mid": "#9A6840", "lo": "#2A180C", "hi": "#F0DCB8", "keep": 0.35},
            "iron": {"mid": "#B8452E", "lo": "#2E0E08", "hi": "#E8B48E"},
            "red": {"mid": "#3E7FA0", "lo": "#0C2230", "hi": "#A8E0F4", "keep": 0.85},
        },
    },
    "troll": {
        "base": "orc", "folder": "Troll", "dark": "#1A1E1A",
        "materials": {
            "wood": {"mid": "#8E8044", "lo": "#1C1C10", "hi": "#E8E0C4", "keep": 0.35},
            "iron": {"mid": "#2E8A86", "lo": "#0A1E1E", "hi": "#A8E8DC"},
            "red": {"mid": "#8A44A2", "lo": "#22102A", "hi": "#E0B0F0", "keep": 0.85},
        },
    },
    # Skyborne: powder-blue elven stone, twilight navy fills; the faction
    # decides trim and accent (High Order: silver and arcane violet,
    # Windshapers: gold and storm teal).
    "highorder": {
        "base": "nightelf", "folder": "HighOrder", "dark": "#1B2A45",
        "materials": {
            "wood": {"mid": "#9DB8CE", "lo": "#1E2C46", "hi": "#F2F7FC"},
            "stone": {"mid": "#B8C4D0", "lo": "#1E2638", "hi": "#F4F8FC"},
            "leaf": {"mid": "#8C7BE0", "lo": "#1E1848", "hi": "#E8DEFF"},
        },
    },
    "windshapers": {
        "base": "nightelf", "folder": "Windshapers", "dark": "#1B2A45",
        "materials": {
            "wood": {"mid": "#9DB8CE", "lo": "#1E2C46", "hi": "#F2F7FC"},
            "stone": {"mid": "#C8B470", "lo": "#2A2010", "hi": "#FFF2C0"},
            "leaf": {"mid": "#2FC4B2", "lo": "#0A2E34", "hi": "#C8FFF2"},
        },
    },
}


def load(path):
    im = Image.open(path).convert("RGBA")
    return np.asarray(im, dtype=np.float64) / 255.0


def hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0.0)
    h = np.zeros_like(mx)
    dd = np.maximum(d, 1e-9)
    h = np.where(mx == r, ((g - b) / dd) % 6, h)
    h = np.where(mx == g, (b - r) / dd + 2, h)
    h = np.where(mx == b, (r - g) / dd + 4, h)
    h = np.where(d == 0, 0.0, h) * 60.0
    return h, s, mx


def luma(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def weights(base, rgb):
    """Soft material weights (dict of arrays summing to 1) and the dark weight."""
    h, s, v = hsv(rgb)
    mats = BASES[base]
    names = list(mats)
    w = {}
    rest = np.ones_like(v)
    for name in names[1:]:
        wi = np.clip(mats[name](h, s, v), 0.0, 1.0) * rest
        w[name] = wi
        rest = rest - wi
    w[names[0]] = rest
    dark = 1.0 - smoothstep(0.035, 0.10, v)
    return w, dark


def base_files(base):
    root = os.path.join(ART, base)
    out = []
    for d, _, files in os.walk(root):
        for f in sorted(files):
            if f.endswith(".tga") and f not in SKIP:
                out.append(os.path.relpath(os.path.join(d, f), root))
    return sorted(out)


def percentiles(base):
    """Per material: luminance at the 5th, 50th and 95th percentile across
    the base set's console and top bar art (weighted by alpha and material)."""
    paths = [os.path.join(ART, base, f) for f in base_files(base)]
    paths += [os.path.join(MEDIA, MEDIA_FOLDER[base], f) for f in MEDIA_FILES]
    lum, wts = [], {}
    for p in paths:
        a = load(p)
        rgb, alpha = a[..., :3], a[..., 3]
        w, dark = weights(base, rgb)
        keep = alpha > 0.5
        lum.append(luma(rgb)[keep])
        for k, wi in w.items():
            wts.setdefault(k, []).append((wi * (1 - dark))[keep])
    lum = np.concatenate(lum)
    out = {}
    for k, parts in wts.items():
        wk = np.concatenate(parts)
        order = np.argsort(lum)
        cum = np.cumsum(wk[order])
        if cum[-1] <= 0:
            out[k] = (0.1, 0.4, 0.8)
            continue
        cum /= cum[-1]
        out[k] = tuple(float(lum[order][np.searchsorted(cum, q)]) for q in (0.05, 0.5, 0.95))
    return out


def gradient(L, stops):
    """Piecewise-linear colour gradient: stops is [(pos, rgb), ...]."""
    pos = np.array([p for p, _ in stops])
    cols = np.array([c for _, c in stops])
    out = np.empty(L.shape + (3,))
    for i in range(3):
        out[..., i] = np.interp(L, pos, cols[:, i])
    return out


def recolour(base, spec, pct, src, dst):
    a = load(src)
    rgb, alpha = a[..., :3], a[..., 3]
    L = luma(rgb)
    w, dark = weights(base, rgb)
    darkc = hexrgb(spec["dark"])
    out = np.zeros_like(rgb)
    for name, m in spec["materials"].items():
        p5, p50, p95 = pct[name]
        lo, mid, hi = hexrgb(m["lo"]), hexrgb(m["mid"]), hexrgb(m["hi"])
        g = gradient(L, [(0.0, darkc * 0.6), (p5, lo), (p50, mid), (p95, hi), (1.0, np.minimum(hi * 1.08, 1.0))])
        # Pull the gradient's brightness back towards the original's, as much
        # as the material asks (accents keep the original's light exactly).
        keep = m.get("keep", KEEP)
        ratio = (L + 0.01) / (luma(g) + 0.01)
        g = g * (ratio ** keep)[..., None]
        out += g * w[name][..., None]
    # Keep a little of the original's colour variation around its own grey.
    detail = rgb - L[..., None]
    out = out + DETAIL * detail
    # Near-black fills become the race's dark fill, keeping their texture.
    fill = darkc * (0.75 + 2.5 * L[..., None])
    out = out * (1 - dark[..., None]) + fill * dark[..., None]
    res = np.dstack([np.clip(out, 0, 1), alpha])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    # RLE, like the base art (the game reads RLE TGA).
    Image.fromarray((res * 255.0 + 0.5).astype(np.uint8), "RGBA").save(dst, compression="tga_rle")


def make(race):
    spec = RACES[race]
    base = spec["base"]
    pct = percentiles(base)
    out_art = os.path.join(ART, race)
    if os.path.isdir(out_art):
        shutil.rmtree(out_art)
    for f in base_files(base):
        recolour(base, spec, pct, os.path.join(ART, base, f), os.path.join(out_art, f))
    out_media = os.path.join(MEDIA, spec["folder"])
    for f in MEDIA_FILES:
        recolour(base, spec, pct, os.path.join(MEDIA, MEDIA_FOLDER[base], f), os.path.join(out_media, f))
    print("wrote", race, "from", base, "(art/%s, Media/%s)" % (race, spec["folder"]))
    # The target plate placeholder is composed from the theme's own art.
    import make_target_plate
    make_target_plate.make(race)


# Races whose console is hand-built from Warcraft III art instead of
# recoloured; never overwrite them. Their RACES entries stay as a record of
# the recolour they replaced.
HAND_BUILT = {"dwarf", "highorder", "windshapers", "troll", "tauren", "gnome"}


def main(args):
    races = args or [r for r in RACES if r not in HAND_BUILT]
    for r in races:
        if r not in RACES:
            sys.exit("unknown race theme %s (one of: %s)" % (r, ", ".join(RACES)))
        if r in HAND_BUILT:
            sys.exit("%s has hand-built art; refusing to overwrite it with a recolour" % r)
        make(r)


if __name__ == "__main__":
    main(sys.argv[1:])
