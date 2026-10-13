#!/usr/bin/env python3
"""Make the placeholder target plate textures (Target.lua's plate mode).

    python3 tools/make_target_plate.py            # every theme it can make
    python3 tools/make_target_plate.py orc troll

The plate is a miniature hero screen: a portrait arch with its two bar slots
on the left and an info window on the right, closed by a post at each end.
The real plate art comes from the art pipeline as art/<theme>/targetplate.tga;
until a theme has it, Layout.TARGET_ART uses the texture this script writes,
art/<theme>/targetplate_gen.tga, composed from the theme's own hero screen
art (minimap_portrait/minimap.tga and portrait.tga):

* the right half of the hero's arch (from its centre to the end of the
  column beside it) and its mirror image make a symmetric arch with its bar
  slots;
* a stretch of the info panel (with its top beam) follows;
* the panel's right-hand post closes the right end, and its mirror image the
  left end;
* the hero screen sits on the bottom of the screen, so the plate gets a base:
  the panel's top beam, flipped.

Seams are cross-faded over a few pixels. The script prints the windows it
finds (portrait opening, the two bar slots and the info window) as pixel
rects of the 512x256 texture, top-left origin; they are the `gen` entries of
Layout.TARGET_ART (`--windows` prints them). The output is deterministic.

Hand-built themes (make_race_themes.HAND_BUILT, Dwarf) get theirs from their
own hand-built art too; only targetplate_gen.tga is written, never real art.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_race_themes import RACES  # noqa: E402

ART = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI", "art"))
OUT_W, OUT_H = 512, 256
OUT_NAME = "targetplate_gen.tga"
THEMES = ("human", "orc", "undead", "nightelf") + tuple(RACES)

# Per faction shape, in "sheet" pixels: minimap.tga is x 0-511, portrait.tga
# x 512-1023, y from the top. c: the arch's centre line; a1: where the info
# panel starts (end of the column right of the arch); top: top of the art
# over the arch and panel; post: the panel's right-hand post (x0, x1); beam:
# the panel's top beam (y0, y1), for the base; base: base height.
SHAPES = {
    "human": {"c": 507, "a1": 607, "top": 232, "post": (996, 1024), "beam": (236, 272)},
    "orc": {"c": 505, "a1": 612, "top": 236, "post": (994, 1024), "beam": (242, 282)},
    "undead": {"c": 506, "a1": 614, "top": 212, "post": (992, 1024), "beam": (222, 266)},
    "nightelf": {"c": 507, "a1": 614, "top": 222, "post": (990, 1024), "beam": (248, 268)},
}
BASE_H = 16  # sheet pixels
FADE = 6


def sheet(theme):
    folder = os.path.join(ART, theme, "minimap_portrait")
    s = Image.new("RGBA", (1024, 512))
    s.paste(Image.open(os.path.join(folder, "minimap.tga")).convert("RGBA"), (0, 0))
    s.paste(Image.open(os.path.join(folder, "portrait.tga")).convert("RGBA"), (512, 0))
    return np.asarray(s).astype(np.float32) / 255.0


def join(parts):
    """Lay the strips side by side, cross-fading FADE pixels at each seam."""
    out = parts[0]
    for p in parts[1:]:
        f = min(FADE, out.shape[1], p.shape[1])
        w = np.linspace(0, 1, f)[None, :, None]
        mid = out[:, -f:] * (1 - w) + p[:, :f] * w
        out = np.concatenate([out[:, :-f], mid, p[:, f:]], axis=1)
    return out


def compose(theme):
    base = RACES.get(theme, {}).get("base", theme)
    sh = SHAPES[base]
    S = sheet(theme)
    top = sh["top"]
    body = S[top:512]
    h = body.shape[0] + BASE_H
    c, a1 = sh["c"], sh["a1"]
    p0, p1 = sh["post"]
    arch = body[:, c:a1]
    post = body[:, p0:p1]
    # Width for a 2:1 texture: whatever the arch and posts leave to the panel.
    panel_w = 2 * h - 2 * arch.shape[1] - 2 * post.shape[1] + 3 * FADE
    panel = body[:, a1:a1 + panel_w]
    row = join([post[:, ::-1], arch[:, ::-1], arch, panel, post])
    # Base: the top beam, flipped, under the whole plate.
    b0, b1 = sh["beam"]
    beam = S[b0:b1, a1:a1 + panel_w]
    beam = np.asarray(Image.fromarray((beam * 255).astype(np.uint8), "RGBA").resize(
        (row.shape[1], BASE_H), Image.LANCZOS)).astype(np.float32)[::-1] / 255.0
    img = np.concatenate([row, beam], axis=0)
    out = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    # The arch's centre line in the output.
    cx = (post.shape[1] + arch.shape[1] - FADE) * OUT_W / img.shape[1]
    return out.resize((OUT_W, OUT_H), Image.LANCZOS), cx


def windows(img, cx):
    """Portrait opening, bar slots and info window as (x, y, w, h). Found on
    the faction's own art: the race themes are recolours with its shapes."""
    a = np.asarray(img).astype(np.int32)
    opaque = a[..., 3] > 200
    dark = opaque & (a[..., :3].max(axis=2) < 40)
    clear = a[..., 3] < 40

    def grow(mask, x, y):
        x0 = x1 = x
        while x0 > 0 and mask[y, x0 - 1]:
            x0 -= 1
        while x1 < img.width - 1 and mask[y, x1 + 1]:
            x1 += 1
        y0 = y1 = y
        while y0 > 0 and mask[y0 - 1, x]:
            y0 -= 1
        while y1 < img.height - 1 and mask[y1 + 1, x]:
            y1 += 1
        return x0, y0, x1, y1

    # The portrait opening: transparent, in the arch, below its top.
    ax = int(round(cx))
    ys = [y for y in range(img.height // 3, img.height) if clear[y, ax]]
    x0, y0, x1, y1 = grow(clear, ax, ys[len(ys) // 2])
    portrait = (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    # The bar slots: dark runs under the opening.
    slots, y = [], y1 + 1
    while y < img.height and len(slots) < 2:
        if dark[y, ax]:
            _, sy0, _, sy1 = grow(dark, ax, y)
            # As wide as the opening: ropes and rivets break the dark run.
            slots.append((portrait[0], sy0, portrait[2], sy1 - sy0 + 1))
            y = sy1 + 1
        y += 1
    # The info window: the dark panel.
    px, py = int(img.width * 0.75), img.height // 2
    x0, y0, x1, y1 = grow(dark, px, py)
    info = (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    return {"portrait": portrait, "health": slots[0] if slots else None,
            "power": slots[1] if len(slots) > 1 else None, "info": info}


def make(theme):
    img, _ = compose(theme)
    dst = os.path.join(ART, theme, OUT_NAME)
    img.save(dst, compression="tga_rle")
    print("wrote", os.path.relpath(dst, os.path.join(ART, "..")))


def print_windows():
    for base in SHAPES:
        img, cx = compose(base)
        print(base, windows(img, cx))


def main(args):
    if args == ["--windows"]:
        print_windows()
        return
    themes = args or list(THEMES)
    for t in themes:
        if t not in THEMES:
            sys.exit("unknown theme %s" % t)
        make(t)


if __name__ == "__main__":
    main(sys.argv[1:])
