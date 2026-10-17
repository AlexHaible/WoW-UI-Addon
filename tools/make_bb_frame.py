#!/usr/bin/env python3
"""Make the theme frame as one nine-sliced texture
(ReforgedUI/Media/Trim/<theme>/frame.tga), for the BetterBags theme
(ReforgedUI_Bags/BetterBags.lua).

    python3 tools/make_bb_frame.py            # every theme
    python3 tools/make_bb_frame.py orc troll

BetterBags draws its windows through Sonata, which takes a theme as data and
builds every texture itself: a theme cannot lay Trim.lua's twelve pieces out
around a window. It can draw one nine-sliced texture, so this script puts the
same pieces Trim.lua uses into one: join.tga in the four corners (mirrored as
Trim.lua mirrors it), one period of the beam along the top and, flipped, the
bottom, and one period of the post down the sides, after the part the join
took. BetterBags tiles the sides between the corners.

The pieces are composed at the art's own 32 px and scaled to EDGE (14) px a
side, so one texel is one window unit, the trim's size in Trim.lua. The
centre is clear: the theme draws the dark inset itself.

Run it after make_trim.py (and regrade_skyborne.py): it reads the joins and
edges those write. The output is deterministic.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI", "Media"))
TRIM = os.path.join(MEDIA, "Trim")

ART = 32  # the trim art's thickness in pixels
EDGE = 14  # its thickness in window units (Trim.lua)

# As in Trim.lua.
FOLDERS = {
    "human": "Human", "orc": "Orc", "undead": "Undead", "forsaken": "Forsaken",
    "nightelf": "NightElf", "dwarf": "Dwarf", "gnome": "Gnome", "tauren": "Tauren",
    "troll": "Troll", "highorder": "HighOrder", "windshapers": "Windshapers",
}
OWN_EDGEV = {"highorder", "windshapers", "undead", "gnome"}
OWN_EDGE = {"undead", "gnome"}


def load(path):
    return Image.open(path).convert("RGBA")


def make(key):
    folder = os.path.join(MEDIA, FOLDERS[key])
    own = os.path.join(TRIM, key)
    edge = load(os.path.join(own if key in OWN_EDGE else folder, "edge.tga"))
    post = load(os.path.join(own if key in OWN_EDGEV else folder, "edgev.tga"))
    join = load(os.path.join(own, "join.tga"))
    assert edge.size == (256, ART) and join.size == (ART, ART), key
    assert post.size[0] == ART, key

    # One period of each side, starting where the join's first ART px end.
    ew, ph = edge.size[0], post.size[1]
    beam = Image.new("RGBA", (ew, ART))
    beam.paste(edge.crop((ART, 0, ew, ART)), (0, 0))
    beam.paste(edge.crop((0, 0, ART, ART)), (ew - ART, 0))
    side = Image.new("RGBA", (ART, ph))
    side.paste(post.crop((0, ART, ART, ph)), (0, 0))
    side.paste(post.crop((0, 0, ART, ART)), (0, ph - ART))

    W, H = ew + 2 * ART, ph + 2 * ART
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    flip_h, flip_v = Image.Transpose.FLIP_LEFT_RIGHT, Image.Transpose.FLIP_TOP_BOTTOM
    img.paste(join, (0, 0))
    img.paste(join.transpose(flip_h), (W - ART, 0))
    img.paste(join.transpose(flip_v), (0, H - ART))
    img.paste(join.transpose(flip_h).transpose(flip_v), (W - ART, H - ART))
    img.paste(beam, (ART, 0))
    img.paste(beam.transpose(flip_v), (ART, H - ART))
    img.paste(side, (0, ART))
    img.paste(side.transpose(flip_h), (W - ART, ART))

    size = (W * EDGE // ART, H * EDGE // ART)
    assert size[0] * ART == W * EDGE and size[1] * ART == H * EDGE, key
    out = img.resize(size, Image.Resampling.LANCZOS)
    path = os.path.join(own, "frame.tga")
    out.save(path, rle=True)
    print(path, out.size)


def main():
    keys = sys.argv[1:] or sorted(FOLDERS)
    for key in keys:
        make(key)


if __name__ == "__main__":
    main()
