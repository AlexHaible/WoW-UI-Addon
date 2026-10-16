#!/usr/bin/env python3
"""Mock up the bags skin (ReforgedUI_Bags) for every theme.

    python3 tools/render_bags.py out.png

Each tile shows Blizzard's backpack (16 slots, 178 units wide, its title band
20 tall) as Bags.lua dresses it, and a BetterBags backpack in the Reforged UI
theme (BetterBags.lua). The frame is laid out as Trim.lua does it, with
render_damage_meter.py's border(). Items are placeholders and Blizzard's
money frame, search box and buttons are left out: this shows the art and its
fit, not the game.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

import render_damage_meter as dm

ICON = os.path.join(dm.REPO, "ReforgedUI", "Media", "Common", "icon.tga")
ICONFRAME = os.path.join(dm.REPO, "ReforgedUI", "Media", "Common", "iconframe.tga")
PX = dm.PX
TITLE_H, RAIL_H, ICON_U = 20, 3, 32
SLOT, GAP = 37, 5
QUALITY = [None, (0.12, 1.0, 0.0), None, (0.0, 0.44, 0.87), None, None, (0.64, 0.21, 0.93), None,
           None, None, (0.12, 1.0, 0.0), None, None, (1.0, 0.5, 0.0), None, None]


def slot(d, x, y, n, fill):
    s = SLOT * PX
    d.rectangle((x, y, x + s - 1, y + s - 1), fill=(14, 12, 10, 255), outline=(70, 64, 56, 255), width=PX)
    if fill:
        r, g, b = [int(40 + 60 * ((n * k) % 7) / 7) for k in (3, 5, 2)]
        d.rectangle((x + 3 * PX, y + 3 * PX, x + s - 3 * PX - 1, y + s - 3 * PX - 1), fill=(r, g, b, 255))
    q = QUALITY[n % len(QUALITY)]
    if fill and q:
        d.rectangle((x + PX, y + PX, x + s - PX - 1, y + s - PX - 1), outline=tuple(int(v * 255) for v in q) + (255,),
                    width=PX)


def bag_icon(size):
    icon = Image.open(ICON).convert("RGBA")
    w, h = icon.size
    icon = icon.crop((int(w * 0.07), int(h * 0.07), int(w * 0.93), int(h * 0.93))).resize((size, size), Image.LANCZOS)
    icon.alpha_composite(Image.open(ICONFRAME).convert("RGBA").resize((size, size), Image.LANCZOS))
    return icon


def window(theme, inset, W, H, title, body):
    """One dressed window W x H units: inset, rail under the title band,
    trim around it, the bag icon on the top-left corner; body(draw, img, ox,
    oy) draws the contents."""
    out = round((dm.EDGE - dm.INSET_U) * PX)
    w, h = W * PX, H * PX
    back = Image.new("RGBA", (w + 2 * out, h + 2 * out))
    c = tuple(int(v * 255) for v in inset[:3])
    ImageDraw.Draw(back).rectangle((out, out, out + w - 1, out + h - 1), fill=c + (int(inset[3] * 255),))
    back = dm.border(back, theme, out, out, w, h)
    C = (back.width - w) // 2 - out
    ox, oy = C + out, C + out
    back.alpha_composite(dm.tex(theme, "rail").resize((w, RAIL_H * PX)), (ox, oy + (TITLE_H - 1) * PX))
    d = ImageDraw.Draw(back)
    font = ImageFont.truetype(dm.FONT, 12 * PX)
    tw = d.textlength(title, font=font)
    d.text((ox + (w - tw) / 2, oy + 4 * PX), title, font=font, fill=(255, 209, 0))
    body(d, back, ox, oy)
    s = ICON_U * PX
    back.alpha_composite(bag_icon(s), (ox - (out - 2 * PX), oy - (out - 2 * PX)))
    return back


def blizzard(theme, inset):
    cols, rows = 4, 4
    W = 178
    H = rows * SLOT + (rows - 1) * GAP + 9 + 48

    def body(d, img, ox, oy):
        n = 0
        for r in range(rows):
            for col in range(cols):
                x = ox + (W - 7 - (cols - col) * SLOT - (cols - 1 - col) * GAP) * PX
                y = oy + (H - 9 - (rows - r) * SLOT - (rows - 1 - r) * GAP) * PX
                slot(d, x, y, n, n % 5 != 4)
                n += 1
    return window(theme, inset, W, H, "Backpack", body)


def betterbags(theme, inset):
    cols, W = 7, 7 * SLOT + 6 * 4 + 12
    sections = [("Recent Items", 3), ("Consumables", 9), ("Trade Goods", 5)]
    H = 62 + sum(18 + ((n + cols - 1) // cols) * (SLOT + 4) for _, n in sections) + 6

    def body(d, img, ox, oy):
        font = ImageFont.truetype(dm.FONT, 12 * PX)
        # The search box (BetterBags' own, 30 to 50 down).
        d.rectangle((ox + 20 * PX, oy + 30 * PX, ox + (W - 10) * PX, oy + 50 * PX), fill=(0, 0, 0, 160),
                    outline=(110, 100, 80, 255), width=PX)
        d.text((ox + 26 * PX, oy + 33 * PX), "Search Backpack", font=font, fill=(140, 140, 140))
        y, n = 58, 0
        for name, count in sections:
            d.text((ox + 6 * PX, oy + y * PX), name, font=font, fill=(255, 209, 0))
            y += 18
            for i in range(count):
                x = 6 + (i % cols) * (SLOT + 4)
                slot(d, ox + x * PX, oy + (y + (i // cols) * (SLOT + 4)) * PX, n, True)
                n += 1
            y += ((count + cols - 1) // cols) * (SLOT + 4)
    return window(theme, inset, W, H, "Backpack", body)


def main(args):
    out = args[0] if args else "bags.png"
    dm.trim_sizes()
    names = dm.insets()
    order = ["human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll",
             "highorder", "windshapers", "forsaken"]
    tiles = []
    for t in order:
        a, b = blizzard(t, names[t][1]), betterbags(t, names[t][1])
        tile = Image.new("RGBA", (a.width + b.width + 30, max(a.height, b.height)))
        tile.alpha_composite(a, (0, 0))
        tile.alpha_composite(b, (a.width + 30, 0))
        tiles.append((names[t][0], tile))
    cw = max(i.width for _, i in tiles) + 40
    ch = max(i.height for _, i in tiles) + 60
    cols = 3
    sheet = Image.new("RGBA", (cw * cols, ch * ((len(tiles) + cols - 1) // cols)), (58, 66, 54, 255))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(dm.FONT, 28)
    for i, (name, img) in enumerate(tiles):
        x, y = (i % cols) * cw + 20, (i // cols) * ch + 10
        d.text((x, y), name, font=font, fill=(255, 230, 160))
        sheet.alpha_composite(img, (x, y + 42))
    sheet.convert("RGB").save(out)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1:])
