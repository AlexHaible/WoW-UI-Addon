#!/usr/bin/env python3
"""Make the theme frame's own art (ReforgedUI/Media/Trim/<theme>/), which
Trim.lua puts around the windows the companion addons skin (damage meter,
bags).

    python3 tools/make_trim.py            # every theme
    python3 tools/make_trim.py orc troll

The frame is the theme's top bar trim (ReforgedUI/Media/<Folder>: edge,
edgev, corner), which is made to repeat. This script makes the rest:

* rail.tga (128x8): the rail between the theme's target plate's health and
  power slots (gold for Human, wood for Orc, iron for Undead, ...), cut from
  art/<theme>/targetplate.tga at the slots in Layout.TARGET_ART and stretched
  along its length. It goes under window headers and the meter's bars.
* edge.tga (256x32), only for the themes in THICK, whose top bar edge is
  a thin beam with clear rows on its inner side (Scourge's bone, which the
  top bar's panel fills behind): the beam's rows stretched to the full 32,
  so it meets the window. Their posts are this edge stood upright too
  (Scourge's own edgev is wood and iron, not bone), so the frame is one
  piece all round. Trim.lua's OWN_EDGE lists them.
* edge.tga (256x32) for the themes in DECOR as well: their top bar edge
  with fittings from the theme's own console art set into it at fixed
  points (Gnome's plain copper and brass pipes get a valve wheel and a
  signal lamp from its portrait frame), so a long window side isn't one
  unbroken run of the same pipe. Their posts are that edge stood upright,
  and their corner joins get a piece of their own over the mitre (Gnome's
  pressure gauge from its target plate). Trim.lua's OWN_EDGE lists them.
* edgev.tga (32x256), only for themes whose top bar has no side posts of
  their own (Skyborne's edgev is empty): their edge stood upright, its top
  turned outwards. Trim.lua's OWN_EDGEV lists them.
* join.tga (32x32): the top-left corner, where the beam (the first 32 px of
  edge.tga) and the post (the first 32 px of edgev.tga) meet in a mitre along
  the diagonal, as on a picture frame. Trim.lua mirrors it for the
  other corners and runs each side out from it.

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
MEDIA = os.path.join(ADDON, "Media")
OUT = os.path.join(MEDIA, "Trim")
RAIL_W, RAIL_H = 128, 8
THICK = {"undead"}
# Fittings cut from art/<theme>/<file>: a circle of radius r around (cx, cy),
# or, with "mask", only that circle's pixels the mask keeps (the valve wheel,
# without the pipe behind it). "at" places each on edge.tga (its centre; x
# along the beam, y across it, 0 being the outer side) and "corner" on the
# join.
DECOR = {
    "gnome": {
        "fittings": {
            "valve": {"file": "minimap_portrait/portrait.tga", "c": (107.5, 244), "r": 16, "mask": "red"},
            "lamp": {"file": "minimap_portrait/portrait.tga", "c": (249.5, 220.5), "r": 10.5},
            "gauge": {"file": "targetplate.tga", "c": (20, 150), "r": 15.5},
        },
        "at": [("lamp", 30, 16), ("valve", 158, 16)],
        "corner": ("gauge", 16, 16),
    },
}
FOLDERS = {"human": "Human", "orc": "Orc", "undead": "Undead", "nightelf": "NightElf", "dwarf": "Dwarf",
           "gnome": "Gnome", "tauren": "Tauren", "troll": "Troll", "highorder": "HighOrder",
           "windshapers": "Windshapers", "forsaken": "Forsaken"}


def plate_rects():
    """Layout.TARGET_ART.themes: {theme: {"health": (x, y, w, h), ...}}."""
    src = open(os.path.join(ADDON, "Layout.lua"), encoding="utf-8").read()
    block = src[src.index("Layout.TARGET_ART = {"):]
    block = block[block.index("themes = {"):block.index("gen = {")]
    out = {}
    for m in re.finditer(r"(\w+) = \{ (portrait = .*?info = \{[^}]*\}) \}", block, re.S):
        out[m.group(1)] = {k: tuple(int(n) for n in v.split(","))
                           for k, v in re.findall(r"(\w+) = \{ ([\d, ]+) \}", m.group(2))}
    return out


def rail(theme, rects):
    """The rail between the plate's two bar slots, its middle stretched to
    RAIL_W (the slots' ends hold posts and rope)."""
    a = np.asarray(Image.open(os.path.join(ART, theme, "targetplate.tga")).convert("RGBA"))
    hx, hy, hw, hh = rects[theme]["health"]
    py = rects[theme]["power"][1]
    band = a[hy + hh - 3:py + 3, hx + hw // 5:hx + hw * 4 // 5]
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
    img = Image.fromarray(np.ascontiguousarray(band[r0:r1]), "RGBA")
    img = img.resize((RAIL_W, min(RAIL_H, img.height)), Image.LANCZOS)
    out = Image.new("RGBA", (RAIL_W, RAIL_H))
    out.paste(img, (0, (RAIL_H - img.height) // 2))
    return out


def needs_edgev(theme):
    a = np.asarray(Image.open(os.path.join(MEDIA, FOLDERS[theme], "edgev.tga")).convert("RGBA"))
    return (a[..., 3] > 40).mean() < 0.2


def thick_edge(theme):
    """edge.tga's beam alone (its rows with any opaque pixels), stretched to
    the texture's full height."""
    img = Image.open(os.path.join(MEDIA, FOLDERS[theme], "edge.tga")).convert("RGBA")
    rows = np.where((np.asarray(img)[..., 3] > 128).any(axis=1))[0]
    return img.crop((0, rows[0], img.width, rows[-1] + 1)).resize(img.size, Image.LANCZOS)


def fitting(theme, spec):
    """A fitting from the theme's console art: its circle, feathered over a
    pixel, as a square RGBA image."""
    a = np.asarray(Image.open(os.path.join(ART, theme, spec["file"])).convert("RGBA")).astype(np.float32)
    (cx, cy), r = spec["c"], spec["r"]
    x0, y0, n = int(cx - r), int(cy - r), int(2 * r + 1)
    a = a[y0:y0 + n, x0:x0 + n].copy()
    y, x = np.mgrid[0:n, 0:n]
    d = np.hypot(x + x0 + 0.5 - cx, y + y0 + 0.5 - cy)
    keep = np.clip(r - d + 0.5, 0, 1)
    if spec.get("mask") == "red":
        # The wheel is red and its hub gold; the pipe behind it is copper,
        # which is redder than it is green but far less than the paint.
        rr, gg, bb = a[..., 0], a[..., 1], a[..., 2]
        red = (rr > 1.6 * gg + 8) & (rr > 60)
        hub = (rr > 150) & (gg > 120) & (bb < 90)
        dark = (rr + gg + bb < 90) & (d < r - 4)  # the shadow between the spokes
        keep = keep * (red | hub | dark)
    a[..., 3] *= keep
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), "RGBA")


def decorated_edge(theme):
    """The top bar's edge with the theme's fittings set into it."""
    spec = DECOR[theme]
    img = Image.open(os.path.join(MEDIA, FOLDERS[theme], "edge.tga")).convert("RGBA")
    pieces = {k: fitting(theme, v) for k, v in spec["fittings"].items()}
    for name, cx, cy in spec["at"]:
        place_clipped(img, pieces[name], cx, cy)
    return img, pieces


def place_clipped(img, piece, cx, cy):
    """place(), clipped to the image (Image.alpha_composite will not take
    negative offsets)."""
    x, y = int(round(cx - piece.width / 2)), int(round(cy - piece.height / 2))
    for dx in (-img.width, 0, img.width):
        px = x + dx
        if px + piece.width <= 0 or px >= img.width:
            continue
        sx, sy = max(0, -px), max(0, -y)
        crop = piece.crop((sx, sy, min(piece.width, img.width - px), min(piece.height, img.height - y)))
        img.alpha_composite(crop, (px + sx, y + sy))


def upright_edge(edge):
    """An edge (256x32) turned so its top faces left: the outer side of an
    edgev post."""
    return edge.convert("RGBA").rotate(90, expand=True)


def join(beam, post):
    """Top-left mitre: the beam above the diagonal from the outer corner,
    the post below it, blended over a pixel either side."""
    b = np.asarray(beam.convert("RGBA").crop((0, 0, 32, 32))).astype(np.float32)
    p = np.asarray(post.convert("RGBA").crop((0, 0, 32, 32))).astype(np.float32)
    y, x = np.mgrid[0:32, 0:32]
    w = np.clip((x - y) / 2.0 + 0.5, 0, 1)[..., None]  # 1 above the diagonal
    out = b * w + p * (1 - w)
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


def make(theme, rects):
    folder = os.path.join(OUT, theme)
    os.makedirs(folder, exist_ok=True)
    rail(theme, rects).save(os.path.join(folder, "rail.tga"), compression="tga_rle")
    made = ["rail", "join"]
    edge = Image.open(os.path.join(MEDIA, FOLDERS[theme], "edge.tga"))
    own_edge = theme in THICK or theme in DECOR
    pieces = None
    if theme in THICK:
        edge = thick_edge(theme)
    elif theme in DECOR:
        edge, pieces = decorated_edge(theme)
    if own_edge:
        edge.save(os.path.join(folder, "edge.tga"), compression="tga_rle")
        made.append("edge")
    if own_edge or needs_edgev(theme):
        post = upright_edge(edge)
        post.save(os.path.join(folder, "edgev.tga"), compression="tga_rle")
        made.append("edgev")
    else:
        post = Image.open(os.path.join(MEDIA, FOLDERS[theme], "edgev.tga"))
    corner = join(edge, post)
    if pieces and DECOR[theme].get("corner"):
        name, cx, cy = DECOR[theme]["corner"]
        place_clipped(corner, pieces[name], cx, cy)
    corner.save(os.path.join(folder, "join.tga"), compression="tga_rle")
    print("wrote", os.path.relpath(folder, os.path.join(HERE, "..")), ", ".join(made))


def main(args):
    rects = plate_rects()
    for t in args or list(FOLDERS):
        if t not in FOLDERS:
            sys.exit("unknown theme %s" % t)
        make(t, rects)


if __name__ == "__main__":
    main(sys.argv[1:])
