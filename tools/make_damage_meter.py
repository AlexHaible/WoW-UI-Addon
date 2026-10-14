#!/usr/bin/env python3
"""Make the damage meter skin's art (ReforgedUI_DamageMeter) from each theme's kit.

    python3 tools/make_damage_meter.py            # every theme
    python3 tools/make_damage_meter.py orc troll
    python3 tools/make_damage_meter.py --margins  # print DamageMeter.lua's FRAMES table

Every theme's target plate (art/<theme>/targetplate.tga, Layout.TARGET_ART)
already has a framed window: its info panel, with the theme's beam on top,
its post on the right and its base underneath. These are cut from it and
written to ReforgedUI_DamageMeter/art/<theme>/:

* frame.tga (512x256): that window made symmetric, its right-hand post
  mirrored onto the left, with the dark inside cut out (transparent). Only
  its four corners are drawn; the window sits at the top-left of the texture
  and `--margins` prints its size, its border widths and the length of one
  repeat of each tile, in plate pixels (DamageMeter.lua's FRAMES).
* top.tga, bottom.tga (256 wide) and side.tga (256 tall): a stretch of the
  beam, the base and the right-hand post, cross-faded at the ends so they
  tile. The meter's border repeats them between the corners, so the beam's
  battlements, rivets and leaves keep their shape at any window size.
* rail.tga (128x8): the rail between the plate's health and power slots
  (gold for Human, wood for Orc, iron for Undead, ...), stretched under each
  bar of the meter and under its header.

The corners are not resampled, so they stay as sharp as the plate. Theme
rects come from ReforgedUI/Layout.lua, so the plates and this stay in step.
The output is deterministic.
"""
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI"))
ART = os.path.join(ADDON, "art")
OUT = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI_DamageMeter", "art"))
TILE = 256
FADE = 12
FRAME_W, FRAME_H = 512, 256
RAIL_W, RAIL_H = 128, 8


def plate_rects():
    """Layout.TARGET_ART.themes: {theme: {"info": (x, y, w, h), ...}}."""
    src = open(os.path.join(ADDON, "Layout.lua"), encoding="utf-8").read()
    block = src[src.index("Layout.TARGET_ART = {"):]
    block = block[block.index("themes = {"):block.index("gen = {")]
    out = {}
    for m in re.finditer(r"(\w+) = \{ (portrait = .*?info = \{[^}]*\}) \}", block, re.S):
        out[m.group(1)] = {k: tuple(int(n) for n in v.split(","))
                           for k, v in re.findall(r"(\w+) = \{ ([\d, ]+) \}", m.group(2))}
    return out


def load(theme):
    return np.asarray(Image.open(os.path.join(ART, theme, "targetplate.tga")).convert("RGBA"))


def dark_box(a, rect):
    """The dark inside of the plate's info window: grown from the middle of
    its rect over opaque, near-black pixels (the rect is where the hero text
    goes, not exactly the art's opening)."""
    x, y, w, h = rect
    dark = (a[..., 3] > 200) & (a[..., :3].max(axis=2) < 48)
    cx, cy = x + w // 2, y + h // 2
    H, W = dark.shape
    x0 = x1 = cx
    while x0 > 0 and dark[cy, x0 - 1]:
        x0 -= 1
    while x1 < W - 1 and dark[cy, x1 + 1]:
        x1 += 1
    y0 = y1 = cy
    while y0 > 0 and dark[y0 - 1, cx]:
        y0 -= 1
    while y1 < H - 1 and dark[y1 + 1, cx]:
        y1 += 1
    return x0, y0, x1 + 1, y1 + 1


def compose_frame(theme, rects):
    a = load(theme)
    x0, y0, x1, y1 = dark_box(a, rects[theme]["info"])
    opaque = a[..., 3] > 40
    # Right post: from the opening to the last opaque column beside it.
    cols = np.where(opaque[y0:y1, x1:].any(axis=0))[0]
    xr = x1 + (cols.max() + 1 if len(cols) else 0)
    # Beam and base: the opaque rows over and under the opening.
    rows = np.where(opaque[:, x0:x1].any(axis=1))[0]
    yt, yb = rows.min(), rows.max() + 1
    right = a[yt:yb, x1:xr].copy()
    middle = a[yt:yb, x0:x1].copy()
    # The opening itself is cut out.
    middle[y0 - yt:y1 - yt, :, 3] = 0
    left = right[:, ::-1]
    img = np.concatenate([left, middle, right], axis=1)
    h, w = img.shape[:2]
    if w > FRAME_W or h > FRAME_H:
        sys.exit("%s: frame %dx%d does not fit %dx%d" % (theme, w, h, FRAME_W, FRAME_H))
    out = np.zeros((FRAME_H, FRAME_W, 4), np.uint8)
    out[:h, :w] = img
    margins = {"w": w, "h": h, "l": int(xr - x1), "r": int(xr - x1), "t": int(y0 - yt), "b": int(yb - y1)}
    pieces = {"beam": middle[:y0 - yt], "base": middle[y1 - yt:], "post": right[y0 - yt:y1 - yt]}
    return Image.fromarray(out, "RGBA"), margins, pieces


def pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def seamless(strip, axis):
    """A stretch of `strip` along `axis` whose ends cross-fade into each other,
    so it repeats without a seam. Ornaments at the window's corners and centre
    (the troll's head, the forsaken's skulls) are left out: the stretch comes
    from between them."""
    n = strip.shape[axis]
    seg = np.take(strip, range(int(n * 0.12), int(n * 0.42)), axis=axis).astype(np.float32)
    f = min(FADE, seg.shape[axis] // 3)
    shape = [1, 1, 1]
    shape[axis] = f
    w = np.linspace(0, 1, f).reshape(shape)
    head = np.take(seg, range(f), axis=axis)
    tail = np.take(seg, range(seg.shape[axis] - f, seg.shape[axis]), axis=axis)
    body = np.take(seg, range(f, seg.shape[axis] - f), axis=axis)
    return np.concatenate([tail * (1 - w) + head * w, body], axis=axis)


def period(strip, axis):
    """Length in plate pixels of one repeat of tile(strip, axis)."""
    return seamless(strip, axis).shape[axis]


def tile(strip, axis):
    """`strip` made seamless along `axis`, resampled to TILE there, padded to
    a power of two across it (transparent, at the far side)."""
    seg = seamless(strip, axis)
    img = Image.fromarray(np.clip(seg + 0.5, 0, 255).astype(np.uint8), "RGBA")
    if axis == 1:
        img = img.resize((TILE, img.height), Image.LANCZOS)
        out = Image.new("RGBA", (TILE, pow2(img.height)))
    else:
        img = img.resize((img.width, TILE), Image.LANCZOS)
        out = Image.new("RGBA", (pow2(img.width), TILE))
    out.paste(img, (0, 0))
    return out


def compose_rail(theme, rects):
    """The rail between the plate's two bar slots, its middle stretched to
    RAIL_W (the slots' ends hold posts and rope)."""
    a = load(theme)
    hx, hy, hw, hh = rects[theme]["health"]
    _, py, _, _ = rects[theme]["power"]
    mx0, mx1 = hx + hw // 5, hx + hw * 4 // 5
    band = a[hy + hh - 3:py + 3, mx0:mx1]
    solid = np.where((band[..., 3] > 160).mean(axis=1) > 0.6)[0]
    if not len(solid):
        sys.exit("%s: no rail between the bar slots" % theme)
    # The longest run of solid rows is the rail.
    runs, start = [], solid[0]
    for i in range(1, len(solid) + 1):
        if i == len(solid) or solid[i] != solid[i - 1] + 1:
            runs.append((start, solid[i - 1] + 1))
            if i < len(solid):
                start = solid[i]
    r0, r1 = max(runs, key=lambda r: r[1] - r[0])
    rail = Image.fromarray(np.ascontiguousarray(band[r0:r1]), "RGBA")
    rail = rail.resize((RAIL_W, min(RAIL_H, rail.height)), Image.LANCZOS)
    out = Image.new("RGBA", (RAIL_W, RAIL_H))
    out.paste(rail, (0, (RAIL_H - rail.height) // 2))
    return out


def make(theme, rects):
    folder = os.path.join(OUT, theme)
    os.makedirs(folder, exist_ok=True)
    frame, margins, pieces = compose_frame(theme, rects)
    frame.save(os.path.join(folder, "frame.tga"), compression="tga_rle")
    tile(pieces["beam"], 1).save(os.path.join(folder, "top.tga"), compression="tga_rle")
    tile(pieces["base"], 1).save(os.path.join(folder, "bottom.tga"), compression="tga_rle")
    tile(pieces["post"], 0).save(os.path.join(folder, "side.tga"), compression="tga_rle")
    compose_rail(theme, rects).save(os.path.join(folder, "rail.tga"), compression="tga_rle")
    print("wrote", os.path.relpath(folder, os.path.join(HERE, "..")), margins)
    return margins


def main(args):
    rects = plate_rects()
    if args == ["--margins"]:
        for theme in rects:
            _, m, p = compose_frame(theme, rects)
            print("\t%s = { w = %d, h = %d, l = %d, r = %d, t = %d, b = %d, top = %d, bottom = %d, side = %d }," % (
                theme, m["w"], m["h"], m["l"], m["r"], m["t"], m["b"],
                period(p["beam"], 1), period(p["base"], 1), period(p["post"], 0)))
        return
    for t in args or list(rects):
        if t not in rects:
            sys.exit("unknown theme %s" % t)
        make(t, rects)


if __name__ == "__main__":
    main(sys.argv[1:])
