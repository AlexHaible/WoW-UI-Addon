#!/usr/bin/env python3
"""Tell the two Skyborne themes apart by their class colours.

    python3 tools/regrade_skyborne.py

High Order and Windshapers share one hand-built Night Elf console (teal
leaves, pink blossoms, grey-blue stone, brown wood) and differ only in their
emblems. This regrades each theme's copy so the whole frame reads as its
faction's class:

* High Order (mages): arcane. Leaves turn violet, blossoms frost-white with a
  cyan sheen, the stone cool silver-lilac and the wood pale silvered ash.
* Windshapers (shamans): storm. Leaves stay storm teal but deeper and bluer,
  blossoms turn ember amber (fire beside the wind), the stone slate and the
  wood a darker, warmer brown.

The source is always the shared art as it was before this regrade (commit
SOURCE_REV, read with git), so running the script again gives the same files.
Alpha is kept; only colour changes. It covers the console (art/<theme>), the
top bar (Media/<Folder>) and the damage meter's trim, wherever it now lives.
"""
import io
import os
import subprocess

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
SOURCE_REV = "b4b21c0"

# The damage meter's trim moved from ReforgedUI_DamageMeter/art/<theme> to
# ReforgedUI/Media/Trim/<theme>; write to whichever exists.
DM_OLD = "ReforgedUI_DamageMeter/art/%s"
DM_NEW = "ReforgedUI/Media/Trim/%s"

THEMES = {"highorder": "HighOrder", "windshapers": "Windshapers"}

# Per theme and material: hue shift (degrees) or absolute hue, saturation and
# value multipliers. A material with "hue" set takes that hue outright.
GRADES = {
    "highorder": {
        "leaf": {"hue": 268, "sat": 0.85, "val": 1.00},
        "bloom": {"hue": 195, "sat": 0.35, "val": 1.12},
        "stone": {"hue": 255, "tint": 0.10, "sat": 1.0, "val": 1.04},
        "wood": {"hue": 240, "tint": 0.06, "sat": 0.25, "val": 1.18},
        "dark": {"hue": 255, "tint": 0.10},
    },
    "windshapers": {
        "leaf": {"hue": 194, "sat": 1.20, "val": 0.84},
        "bloom": {"hue": 40, "sat": 1.15, "val": 1.25},
        "stone": {"hue": 212, "tint": 0.18, "sat": 1.0, "val": 0.80},
        "wood": {"hue": 20, "tint": 0.0, "sat": 1.20, "val": 0.80},
        "dark": {"hue": 205, "tint": 0.12},
    },
}


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hue_window(h, centre, half, feather=12.0):
    d = np.abs(((h - centre + 180.0) % 360.0) - 180.0)
    return 1.0 - smoothstep(half, half + feather, d)


def rgb2hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0.0)
    dd = np.maximum(d, 1e-9)
    h = np.zeros_like(mx)
    h = np.where(mx == r, ((g - b) / dd) % 6, h)
    h = np.where(mx == g, (b - r) / dd + 2, h)
    h = np.where(mx == b, (r - g) / dd + 4, h)
    return np.where(d == 0, 0.0, h) * 60.0, s, mx


def hsv2rgb(h, s, v):
    h = (h % 360.0) / 60.0
    c = v * s
    x = c * (1 - np.abs(h % 2 - 1))
    z = np.zeros_like(h)
    i = np.floor(h).astype(int) % 6
    r = np.choose(i, [c, x, z, z, x, c])
    g = np.choose(i, [x, c, c, x, z, z])
    b = np.choose(i, [z, z, x, c, c, x])
    m = v - c
    return np.dstack([r + m, g + m, b + m])


def masks(h, s, v):
    """Soft weights for the shared art's materials."""
    coloured = smoothstep(0.12, 0.25, s)
    leaf = hue_window(h, 172, 28) * coloured
    bloom = hue_window(h, 338, 22) * smoothstep(0.18, 0.32, s)
    wood = hue_window(h, 22, 22) * coloured * (1 - leaf) * (1 - bloom)
    dark = 1.0 - smoothstep(0.04, 0.12, v)
    stone = np.clip(1 - leaf - bloom - wood, 0, 1) * (1 - dark)
    return {"leaf": leaf, "bloom": bloom, "wood": wood, "stone": stone, "dark": dark * (1 - leaf - bloom - wood).clip(0, 1)}


def regrade(rgba, grade):
    rgb, alpha = rgba[..., :3], rgba[..., 3:]
    h, s, v = rgb2hsv(rgb)
    w = masks(h, s, v)
    out = rgb * (1 - sum(w.values()))[..., None]
    for name, g in grade.items():
        if "tint" in g:
            # Near-grey materials: blend in the target hue at a little
            # saturation, keeping brightness.
            nh = np.full_like(h, float(g["hue"]))
            ns = np.clip(s * g.get("sat", 1.0) * (1 - g["tint"]) + g["tint"] * (0.5 + 0.5 * s), 0, 1)
            nv = np.clip(v * g.get("val", 1.0), 0, 1)
        else:
            nh = np.full_like(h, float(g["hue"]))
            # Keep the original's hue variation around the leaf's centre.
            if name == "leaf":
                nh = nh + ((h - 172 + 180) % 360 - 180) * 0.6
            ns = np.clip(s * g.get("sat", 1.0), 0, 1)
            nv = np.clip(v * g.get("val", 1.0), 0, 1)
        out = out + hsv2rgb(nh, ns, nv) * w[name][..., None]
    return np.concatenate([np.clip(out, 0, 1), alpha], -1)


def git_files(path):
    out = subprocess.run(["git", "-C", REPO, "ls-tree", "-r", "--name-only", SOURCE_REV, path + "/"],
                         check=True, capture_output=True, text=True).stdout
    return [f for f in out.splitlines() if f.lower().endswith(".tga")]


def git_image(path):
    data = subprocess.run(["git", "-C", REPO, "show", "%s:%s" % (SOURCE_REV, path)],
                          check=True, capture_output=True).stdout
    return np.asarray(Image.open(io.BytesIO(data)).convert("RGBA"), dtype=np.float64) / 255.0


def write(arr, dst):
    Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA").save(dst, compression="tga_rle")


def main():
    for theme, folder in THEMES.items():
        jobs = []
        for src_dir, dst_dir in (("ReforgedUI/art/" + theme,) * 2, ("ReforgedUI/Media/" + folder,) * 2,
                                 (DM_OLD % theme, DM_NEW % theme if os.path.isdir(os.path.join(REPO, DM_NEW % theme)) else DM_OLD % theme)):
            for f in git_files(src_dir):
                jobs.append((f, os.path.join(dst_dir, os.path.relpath(f, src_dir))))
        for src, dst in jobs:
            write(regrade(git_image(src), GRADES[theme]), os.path.join(REPO, dst))
        print("regraded", theme, "(%d files)" % len(jobs))


if __name__ == "__main__":
    main()
