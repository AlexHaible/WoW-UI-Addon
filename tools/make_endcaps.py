#!/usr/bin/env python3
"""Make stand-in end caps for the console from each theme's own art.

    python3 tools/make_endcaps.py            # every theme but the hand-built ones
    python3 tools/make_endcaps.py orc troll

The console is always centred, so both of its ends stand in mid-screen. Each
end gets a pillar that closes it: Layout.ENDCAP_ART says which file each theme
uses. Themes with real end cap art list endcap_left/endcap_right there; the
others use the caps this script builds, written next to them under distinct
names so real art never gets overwritten:

    ReforgedUI/art/<theme>/endcaps/endcap_left_gen.tga
    ReforgedUI/art/<theme>/endcaps/endcap_right_gen.tga

A cap is the theme's inventory pillar (inventory/no_inventory.tga, the
decorated pillar with its crown that the original addon stands beside the inventory),
narrowed to a buttress: the pillar's finished left side (crown overhang,
frame and a strip of its face) and the same mirrored for the right side, so
both outer faces are finished. The crown keeps its proportions; the shaft
is stretched to the cap's height, and the crown is cut back to the shaft's
width (no overhang, so no T shape).

Themes in make_race_themes.HAND_BUILT (Dwarf) get theirs from their own
hand-built pillar too; only the *_gen files are written, never real art. Deterministic: running it again gives the same files.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ART = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI", "art"))
THEMES = ("human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll", "highorder", "windshapers")

OUT_W, OUT_H = 128, 512
# The cap's shape on screen (width / height); Layout.ENDCAP_ART's w and h
# for the generated caps keep this ratio.
ASPECT = 0.32
# How far into the pillar (source pixels past its left border's outer edge)
# each half of the cap reaches.
INTO = 64
# The crown is at most this many source rows tall.
CROWN_MAX = 80


def make(theme):
    src = Image.open(os.path.join(ART, theme, "inventory", "no_inventory.tga")).convert("RGBA")
    a = np.asarray(src.getchannel("A")) > 128
    rows = [y for y in range(src.height) if a[y].any()]
    top = rows[0]
    # The pillar's shaft: its left edge over the bottom third.
    lows = [int(np.nonzero(a[y])[0].min()) for y in range(src.height * 2 // 3, src.height) if a[y].any()]
    shaft = int(np.median(lows))
    # The crown: the rows reaching out past the shaft (plus a few rows of
    # shadow under it).
    # Only the top of the pillar counts (Night Elf's vines trail further).
    crown = [y for y in rows if y < top + CROWN_MAX and np.nonzero(a[y])[0].min() < shaft - 3]
    crown_end = min(src.height, (crown[-1] if crown else top) + 6)
    left = min(int(np.nonzero(a[y])[0].min()) for y in rows)
    half = src.crop((left, top, shaft + INTO, src.height))
    k = (OUT_W / 2) / half.width
    logical_h = round(OUT_W / ASPECT)
    crown_h = max(1, round((crown_end - top) * k))
    head = half.crop((0, 0, half.width, crown_end - top)).resize((OUT_W // 2, crown_h), Image.LANCZOS)
    body = half.crop((0, crown_end - top, half.width, half.height)).resize(
        (OUT_W // 2, logical_h - crown_h), Image.LANCZOS)
    halfimg = Image.new("RGBA", (OUT_W // 2, logical_h))
    halfimg.paste(body, (0, crown_h))
    halfimg.alpha_composite(head, (0, 0))
    cap = Image.new("RGBA", (OUT_W, logical_h))
    cap.paste(halfimg, (0, 0))
    cap.paste(halfimg.transpose(Image.FLIP_LEFT_RIGHT), (OUT_W // 2, 0))
    # The mirrored halves meet in the middle; soften that column so it reads
    # as a carved groove, not a cut.
    arr = np.asarray(cap).astype(np.float64)
    m = OUT_W // 2
    for d, f in ((0, 0.72), (1, 0.85), (2, 0.94)):
        arr[crown_h:, m - 1 - d, :3] *= f
        arr[crown_h:, m + d, :3] *= f
    # A darker foot where the pillar meets the floor.
    n = 18
    arr[-n:, :, :3] *= np.linspace(1.0, 0.65, n)[:, None, None]
    # No T: the crown's slab is cut back to the shaft's width, so the cap
    # stands as one straight pillar.
    body_a = arr[crown_h:, :, 3] > 128
    cols = np.nonzero(body_a.mean(axis=0) > 0.5)[0]
    if len(cols):
        arr[:crown_h, :cols[0], 3] = 0
        arr[:crown_h, cols[-1] + 1:, 3] = 0
    cap = Image.fromarray(arr.round().clip(0, 255).astype(np.uint8), "RGBA").resize((OUT_W, OUT_H), Image.LANCZOS)
    out = os.path.join(ART, theme, "endcaps")
    os.makedirs(out, exist_ok=True)
    cap.save(os.path.join(out, "endcap_right_gen.tga"))
    cap.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(out, "endcap_left_gen.tga"))
    print("wrote %s (crown %.3f of its height)" % (os.path.relpath(out, os.getcwd()), crown_h / logical_h))


def main(args):
    themes = args or list(THEMES)
    for t in themes:
        if not os.path.isdir(os.path.join(ART, t)):
            sys.exit("unknown theme %s" % t)
        make(t)


if __name__ == "__main__":
    main(sys.argv[1:])
