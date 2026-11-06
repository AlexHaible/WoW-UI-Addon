#!/usr/bin/env python3
"""Make the post a BetterBags Next full panel stands its inner side against
(ReforgedUI/Media/Trim/<theme>/pillar.tga), and the leaf clusters that sway
on it (cluster.tga), for themes whose plain post is too thin for a panel the
height of the screen.

    python3 tools/make_next_pillar.py            # every theme it knows
    python3 tools/make_next_pillar.py nightelf

The pillar is 128 x 256, drawn 80 x 160 window units (ReforgedUI_Bags/
BetterBags.lua) and repeating down the panel's whole height, so everything
on it wraps from its bottom row to its top. The trunk runs down its middle
(the panel's edge); leaves cut from the theme's own top bar art spill out
over both sides, each with a soft shadow on the bark under it. Nothing
reaches the left or right edge (the script checks), so no leaf is cut off.

Night Elf: a trunk of the theme's bark (panel.tga), rounded with light from
the top left, a dark outline; leaf sprays from the top bar's beam
(edge.tga) and corner (corner.tga), turned to hang off each side.

The output is deterministic (a fixed seed).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.normpath(os.path.join(HERE, "..", "ReforgedUI", "Media"))
TRIM = os.path.join(MEDIA, "Trim")

W, H = 128, 256  # the pillar, in pixels
TRUNK = 40  # the trunk's width
MARGIN = 3  # nothing comes closer to the left or right edge


def load(path):
    return Image.open(path).convert("RGBA")


def leafy(img):
    """Keeps only an image's green, leafy pixels."""
    a = np.asarray(img).astype(np.float32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    keep = (g > r * 1.05) & (g > b * 1.05) & (al > 40)
    a[..., 3] = np.where(keep, al, 0)
    out = Image.fromarray(a.astype(np.uint8), "RGBA")
    # Drop specks: a pixel stays only where most of its neighbours do.
    alpha = out.split()[3].filter(ImageFilter.MedianFilter(3))
    out.putalpha(ImageChops.multiply(out.split()[3], alpha.point(lambda v: 255 if v > 0 else 0)))
    box = out.getbbox()
    return out.crop(box) if box else out


def sprays(folder):
    """Leaf sprays: the beam's leaves cut in pieces, and the corner's."""
    edge = load(os.path.join(MEDIA, folder, "edge.tga"))
    out = []
    for x in range(0, edge.width, 48):
        piece = leafy(edge.crop((x, 0, x + 56, 26)))
        if piece.width > 20:
            out.append(piece)
    corner = leafy(load(os.path.join(MEDIA, folder, "corner.tga")).crop((0, 0, 64, 46)))
    out.append(corner.resize((corner.width * 3 // 4, corner.height * 3 // 4), Image.LANCZOS))
    return out


def trunk(folder):
    """The bark, rounded: darker toward both sides, lit from the left."""
    bark = load(os.path.join(MEDIA, folder, "panel.tga"))
    col = bark.crop((96, 0, 96 + TRUNK, 256)).resize((TRUNK, H), Image.LANCZOS)
    a = np.asarray(col).astype(np.float32)
    x = (np.arange(TRUNK) + 0.5) / TRUNK * 2 - 1  # -1 .. 1 across
    shade = 0.55 + 0.6 * np.sqrt(np.clip(1 - x * x, 0, 1)) - 0.12 * x
    a[..., :3] *= shade[None, :, None]
    a[..., :3] = np.clip(a[..., :3], 0, 255)
    a[..., 3] = 255
    # A dark outline down both sides.
    a[:, :2, :3] *= 0.35
    a[:, -2:, :3] *= 0.35
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def paste_wrapped(canvas, img, x, y):
    for dy in (-H, 0, H):
        canvas.alpha_composite(img, (x, y + dy)) if -img.height < y + dy < H else None


def make_nightelf(key="nightelf", folder="NightElf"):
    rnd = random.Random(7)
    leaves = sprays(folder)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    left = (W - TRUNK) // 2
    canvas.alpha_composite(trunk(folder), (left, 0))

    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # Sprays down both sides in turn, each turned to hang outwards.
    y, side = 6, 0
    while y < H:
        leaf = rnd.choice(leaves)
        s = rnd.uniform(1.0, 1.4)
        leaf = leaf.resize((max(1, int(leaf.width * s)), max(1, int(leaf.height * s))), Image.LANCZOS)
        # The beam's sprays grow up: turn them out to the left or the right.
        angle = (90 if side == 0 else -90) + rnd.uniform(-25, 25)
        leaf = leaf.rotate(angle, resample=Image.BICUBIC, expand=True)
        if rnd.random() < 0.5:
            leaf = leaf.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        box = leaf.getbbox()
        leaf = leaf.crop(box)
        reach = W // 2 - MARGIN - 5  # from the middle out to the margin, the shadow's room kept
        if leaf.width > reach + TRUNK // 3:
            f = (reach + TRUNK // 3) / leaf.width
            leaf = leaf.resize((int(leaf.width * f), int(leaf.height * f)), Image.LANCZOS)
        # Grown from the trunk: each spray overlaps its side of the bark.
        overlap = rnd.randint(8, 16)
        if side == 0:
            x = max(MARGIN, left + overlap - leaf.width)
        else:
            x = min(W - MARGIN - 5 - leaf.width, left + TRUNK - overlap)
        paste_wrapped(layer, leaf, x, y)
        y += rnd.randint(16, 26)
        side = 1 - side

    # A soft shadow under the leaves, down and to the right.
    alpha = layer.split()[3]
    shadow_a = alpha.filter(ImageFilter.GaussianBlur(2.5)).point(lambda v: int(v * 0.65))
    shadow_a = ImageChops.offset(shadow_a, 2, 3)  # wraps down: the pillar repeats
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(shadow_a)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(layer)

    # Keep the left and right margins clear (a shadow's last wisp excepted).
    a = np.asarray(canvas)[..., 3]
    assert a[:, :MARGIN - 1].max() < 40 and a[:, W - MARGIN + 1:].max() < 40, "art reaches the pillar's side"
    out = os.path.join(TRIM, key, "pillar.tga")
    canvas.save(out, rle=True)
    print(out, canvas.size)

    # The swaying cluster: sprays fanned out from a stem on its right edge
    # (where it grows from the pillar) toward the left (out from the panel),
    # drooping, with the same soft shadow.
    C = 128
    fan = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    base = (C - 10, C // 2)
    beam = leaves[:-1]  # the beam's sprays (the corner's has a cut edge)
    for i, angle in enumerate((135, 165, 195, 225)):
        leaf = beam[(i * 3 + 1) % len(beam)]
        f = 1.6
        leaf = leaf.resize((int(leaf.width * f), int(leaf.height * f)), Image.LANCZOS)
        # A spray grows up (out of its bottom); point it along the angle.
        turned = leaf.rotate(angle - 90, resample=Image.BICUBIC, expand=True)
        turned = turned.crop(turned.getbbox())
        rad = math.radians(angle)
        reach = 18 + 0.5 * max(leaf.width, leaf.height)
        cx = base[0] + math.cos(rad) * reach
        cy = base[1] - math.sin(rad) * reach + 8  # drooping
        x = int(max(2, min(C - 2 - turned.width, cx - turned.width / 2)))
        y = int(max(2, min(C - 2 - turned.height, cy - turned.height / 2)))
        fan.alpha_composite(turned, (x, y))
    shadow = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    shadow.putalpha(ImageChops.offset(fan.split()[3].filter(ImageFilter.GaussianBlur(2.5)), 2, 3).point(
        lambda v: int(v * 0.6)))
    c = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    c.alpha_composite(shadow)
    c.alpha_composite(fan)
    out = os.path.join(TRIM, key, "cluster.tga")
    c.save(out, rle=True)
    print(out, c.size)


MAKERS = {"nightelf": make_nightelf}


def main():
    for key in sys.argv[1:] or sorted(MAKERS):
        MAKERS[key]()


if __name__ == "__main__":
    main()
