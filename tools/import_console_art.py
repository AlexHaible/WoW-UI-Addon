#!/usr/bin/env python3
"""Cut the console trim from the original addon's art into our per-faction textures.

    python3 tools/import_console_art.py <path to the console art source>

The original addon cuts its pieces from the Warcraft III
console. We take three of them and turn them into our generic panel pieces:

- edge   (256x32): the crenellated wall top from actionbar/ext1, tiled along
  the top of every panel
- edgev  (32x128): the stone side post from bottom right/BottomRight_Middle
- corner (64x64):  the end of the wall top from bottom right/BottomRight_Top,
  drawn where the console outline steps
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "ReforgedUI", "Media")
FACTIONS = {"Human": "human", "Orc": "orc", "Undead": "undead", "NightElf": "nightelf"}


def crop_alpha(im):
    return im.crop(im.split()[3].getbbox())


def main(src):
    for ours, theirs in FACTIONS.items():
        art = os.path.join(src, "art", theirs)
        out = os.path.join(MEDIA, ours)

        ext = crop_alpha(Image.open(os.path.join(art, "actionbar", "ext1.tga")).convert("RGBA"))
        # Start the tile on a whole block so the repeat seam falls between blocks.
        edge = ext.resize((256, 32), Image.LANCZOS)
        edge.save(os.path.join(out, "edge.tga"))

        mid = Image.open(os.path.join(art, "bottom right", "BottomRight_Middle.tga")).convert("RGBA")
        mid.crop((0, 0, 32, 128)).save(os.path.join(out, "edgev.tga"))

        top = crop_alpha(Image.open(os.path.join(art, "bottom right", "BottomRight_Top.tga")).convert("RGBA"))
        h = top.height
        corner = top.crop((top.width - h, 0, top.width, h)).resize((64, 64), Image.LANCZOS)
        corner.save(os.path.join(out, "corner.tga"))
        print("wrote", ours, "edge/edgev/corner from", theirs, "(ext1 %dx%d)" % ext.size)


if __name__ == "__main__":
    main(sys.argv[1])
