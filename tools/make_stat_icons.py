#!/usr/bin/env python3
"""Warcraft III's hero attribute and Critical Strike art for the stat icons.

    python3 tools/make_stat_icons.py <wc3-ui-extract png dir>

Takes the HD infocard attribute icons (Strength, Agility, Intelligence) and
the Blademaster's Critical Strike button from the extract's PNG tree and
saves them as 64x64 TGAs in ReforgedUI/art/other. Their own gold or steel
border is left on: Hero.lua crops 7% per side and lays golden_frame over it.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ReforgedUI", "art", "other")
SRC = {
    "attribute_str": "war3.w3mod/_hd.w3mod/ui/widgets/console/human/infocard-heroattributes-str.png",
    "attribute_agi": "war3.w3mod/_hd.w3mod/ui/widgets/console/human/infocard-heroattributes-agi.png",
    "attribute_int": "war3.w3mod/_hd.w3mod/ui/widgets/console/human/infocard-heroattributes-int.png",
    "critical_strike": "war3.w3mod/_hd.w3mod/replaceabletextures/commandbuttons/btncriticalstrike.png",
}


def main(png_dir):
    for name, rel in SRC.items():
        path = os.path.join(png_dir, rel)
        if not os.path.exists(path):
            print("missing", path)
            continue
        im = Image.open(path).convert("RGBA").resize((64, 64), Image.LANCZOS)
        im.save(os.path.join(OUT, name + ".tga"), compression="tga_rle")
        print("wrote", name)


if __name__ == "__main__":
    main(sys.argv[1])
