#!/usr/bin/env python3
"""Make the damage meter skin's own art (ReforgedUI_DamageMeter/art/<theme>/).

    python3 tools/make_damage_meter.py            # every theme
    python3 tools/make_damage_meter.py orc troll

The skin's border is the theme's top bar trim (ReforgedUI/Media/<Folder>:
edge, edgev, corner), which is made to repeat. This script makes the rest:

* rail.tga (128x8): the rail between the theme's target plate's health and
  power slots (gold for Human, wood for Orc, iron for Undead, ...), cut from
  art/<theme>/targetplate.tga at the slots in Layout.TARGET_ART and stretched
  along its length. It goes under the meter's header and under every bar.
* edgev.tga (32x256), only for themes whose top bar has no side posts of
  their own (Skyborne's edgev is empty): their edge stood upright, its top
  turned outwards. DamageMeter.lua's OWN_EDGEV lists them.

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
OUT = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI_DamageMeter", "art"))
RAIL_W, RAIL_H = 128, 8
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


def upright_edge(theme):
    """edge.tga (256x32) turned so its top faces left: the outer side of an
    edgev post."""
    return Image.open(os.path.join(MEDIA, FOLDERS[theme], "edge.tga")).convert("RGBA").rotate(90, expand=True)


def make(theme, rects):
    folder = os.path.join(OUT, theme)
    os.makedirs(folder, exist_ok=True)
    rail(theme, rects).save(os.path.join(folder, "rail.tga"), compression="tga_rle")
    made = ["rail"]
    if needs_edgev(theme):
        upright_edge(theme).save(os.path.join(folder, "edgev.tga"), compression="tga_rle")
        made.append("edgev")
    print("wrote", os.path.relpath(folder, os.path.join(HERE, "..")), ", ".join(made))


def main(args):
    rects = plate_rects()
    for t in args or list(FOLDERS):
        if t not in FOLDERS:
            sys.exit("unknown theme %s" % t)
        make(t, rects)


if __name__ == "__main__":
    main(sys.argv[1:])
