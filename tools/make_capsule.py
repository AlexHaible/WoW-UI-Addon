#!/usr/bin/env python3
"""The time capsule under the top bar's clock (TopBar.lua).

    python3 tools/make_capsule.py

Saves two white pills, 128x32, to ReforgedUI/Media/Common: capsule.tga (the
fill) and capsule_rim.tga (its 2 pixel outline). TopBar.lua tints them with
the theme's inset and inset line colours, like the slot plates.
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ReforgedUI", "Media", "Common")
W, H, SS, RIM = 128, 32, 8, 2


def pill(inset):
    big = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(big)
    i = inset * SS
    d.rounded_rectangle((i, i, W * SS - 1 - i, H * SS - 1 - i), radius=(H * SS - 2 * i) // 2, fill=255)
    return big.resize((W, H), Image.LANCZOS)


def save(alpha, name):
    im = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    im.putalpha(alpha)
    im.save(os.path.join(OUT, name))


def main():
    outer, inner = pill(0), pill(RIM)
    save(outer, "capsule.tga")
    rim = Image.frombytes("L", (W, H), bytes(max(0, a - b) for a, b in zip(outer.tobytes(), inner.tobytes())))
    save(rim, "capsule_rim.tga")


if __name__ == "__main__":
    main()
