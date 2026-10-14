#!/usr/bin/env python3
"""Cut the console trim from the original addon's art into our per-faction textures.

    python3 tools/import_console_art.py <path to the console art source>

The original addon cuts its pieces from the Warcraft III
console. We take three of them and turn them into our generic panel pieces:

- edge   (256x32): the wall top from actionbar/ext1, tiled along the top of
  every panel (every 128 units at 16 thick), so it must repeat without a cut
- edgev  (32x128): the side post from bottom right/BottomRight_Middle, tiled
  down the sides, outer side on the left
- corner (64x64):  the end of the wall top from bottom right/BottomRight_Top,
  drawn where the console outline steps

ext1 and BottomRight_Middle do not tile as they are (Undead's ext1 starts on a
skull, Human's ends block against block, Night Elf's bar stops short of its
ends, and the posts' first and last rows differ), so each is cut to repeat.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "ReforgedUI", "Media")
FACTIONS = {"Human": "human", "Orc": "orc", "Undead": "undead", "NightElf": "nightelf"}


def crop_alpha(im):
    return im.crop(im.split()[3].getbbox())


def wrap(im, axis, frac=0.15):
    """Cross-fade the far end into the start so the image repeats along one axis."""
    w, h = im.size
    n = int((w if axis == "x" else h) * frac)
    body = im.crop((0, 0, w - n, h) if axis == "x" else (0, 0, w, h - n))
    tail = im.crop((w - n, 0, w, h) if axis == "x" else (0, h - n, w, h))
    for i in range(n):
        a = i / n
        if axis == "x":
            body.paste(Image.blend(tail.crop((i, 0, i + 1, h)), body.crop((i, 0, i + 1, h)), a), (i, 0))
        else:
            body.paste(Image.blend(tail.crop((0, i, w, i + 1)), body.crop((0, i, w, i + 1)), a), (0, i))
    return body


def rows(im):
    b = im.getchannel("A").getbbox()
    return b[1], b[3]


def is_leaf(r, g, b):
    return g > r + 8 and g >= b


def edge_strip(faction, ext):
    if faction == "undead":
        # Plain bone right of the skull, repeated with a cross-fade.
        y0, y1 = rows(ext)
        return wrap(ext.crop((50, y0, 285, y1)), "x")
    if faction == "human":
        # Block, low wall, block, ...: add one low-wall run after the last block so
        # two blocks never meet at the repeat.
        x0, y0, x1, y1 = ext.getchannel("A").getbbox()
        body, gap = ext.crop((x0, y0, x1, y1)), ext.crop((137, y0, 181, y1))
        strip = Image.new("RGBA", (body.width + gap.width, body.height))
        strip.paste(body, (0, 0))
        strip.paste(gap, (body.width, 0))
        return strip
    if faction == "nightelf":
        # The bar under the leaves stops at x 48 and 472: lay a continuous bar (two
        # almost leaf-free runs of it, cross-faded) under the whole width, and fade the
        # original bar's end caps into it, keeping every leaf.
        W, H = ext.size
        runs, F = [ext.crop((80, 0, 104, H)), ext.crop((416, 0, 440, H))], 6
        under = Image.new("RGBA", (W + 64, H))
        x, i = 0, 0
        while x < W + 64:
            r = runs[i % 2]
            for j in range(r.width):
                col = r.crop((j, 0, j + 1, H))
                if x > 0 and j < F:
                    col = Image.blend(under.crop((x + j - F, 0, x + j - F + 1, H)), col, (j + 0.5) / F)
                under.paste(col, (x + j - (F if x > 0 else 0), 0))
            x += r.width - (F if x > 0 else 0)
            i += 1
        under = under.crop((0, 0, W, H))
        up = under.load()
        for yy in range(H):
            for xx in range(W):
                r, g, b, _ = up[xx, yy]
                if is_leaf(r, g, b):
                    up[xx, yy] = (0, 0, 0, 0)
        orig = ext.copy()
        op = orig.load()
        for yy in range(H):
            for xx in list(range(40, 64)) + list(range(456, 480)):
                r, g, b, a = op[xx, yy]
                if a and not is_leaf(r, g, b):
                    d = (xx - 48) if xx < 256 else (472 - xx)
                    op[xx, yy] = (r, g, b, round(a * max(0.0, min(1.0, d / 16))))
        y0, y1 = rows(ext)
        return Image.alpha_composite(under, orig).crop((0, y0, W, y1))
    # Orc: each repeat starts on a whole clamp.
    return crop_alpha(ext)


def edgev_strip(faction, mid):
    if faction == "nightelf":
        # The trunk is the right half; take a fully opaque run and flip it so its
        # outer side is on the left.
        a = mid.getchannel("A")
        opaque = [sum(1 for x in range(40, 60) if a.getpixel((x, y)) > 200) for y in range(mid.height)]
        y0 = max(range(mid.height - 150), key=lambda y: min(opaque[y:y + 150]))
        return wrap(mid.crop((32, y0, 64, y0 + 150)).transpose(Image.FLIP_LEFT_RIGHT), "y")
    return wrap(mid.crop((0, 0, 32, 150)), "y")


def main(src):
    for ours, theirs in FACTIONS.items():
        art = os.path.join(src, "art", theirs)
        out = os.path.join(MEDIA, ours)

        ext = Image.open(os.path.join(art, "actionbar", "ext1.tga")).convert("RGBA")
        edge_strip(theirs, ext).resize((256, 32), Image.LANCZOS).save(os.path.join(out, "edge.tga"), compression=None)

        mid = Image.open(os.path.join(art, "bottom right", "BottomRight_Middle.tga")).convert("RGBA")
        edgev_strip(theirs, mid).resize((32, 128), Image.LANCZOS).save(os.path.join(out, "edgev.tga"), compression=None)

        top = crop_alpha(Image.open(os.path.join(art, "bottom right", "BottomRight_Top.tga")).convert("RGBA"))
        h = top.height
        corner = top.crop((top.width - h, 0, top.width, h)).resize((64, 64), Image.LANCZOS)
        corner.save(os.path.join(out, "corner.tga"), compression=None)
        print("wrote", ours, "edge/edgev/corner from", theirs)


if __name__ == "__main__":
    main(sys.argv[1])
