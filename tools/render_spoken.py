#!/usr/bin/env python3
"""Mock up the Spoken narrator style (ReforgedUI_Spoken) for every theme.

    python3 tools/render_spoken.py out.png

Lays the window out the way ReforgedUI_Spoken/Spoken.lua does (its sizes
read from the file), framed by the trim as tools/render_damage_meter.py
draws it. Spoken's own parts (portrait, captions, round controls) are
stand-ins: the mock-up shows the frame, the theme's colours and the fit.
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

import render_damage_meter as dm

SPOKEN_LUA = os.path.join(dm.REPO, "ReforgedUI_Spoken", "Spoken.lua")
PX = dm.PX
CAPTION = ["For the Horde! The humans have built their", "camps along the coast. Drive them back into the sea."]


def num(src, name):
    return int(re.search(r"local %s = (\d+)" % name, src).group(1))


def colours():
    src = open(dm.THEMES_LUA, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\t(\w+) = \{\n\t\tname = \"([^\"]+)\"(.*?)\n\t\},", src, re.S):
        body = m.group(3)
        get = lambda k: tuple(float(v) for v in re.search(k + r" = \{ ([\d., ]+) \}", body).group(1).split(","))
        out[m.group(1)] = (m.group(2), get("inset"), get("title"), get("accent"))
    return out


def render(theme, inset, title, accent, s):
    W, PAD, PORTRAIT, GAP = num(s, "WIDTH"), num(s, "PAD"), num(s, "PORTRAIT"), num(s, "GAP")
    font = ImageFont.truetype(dm.FONT, 15 * PX)
    small = ImageFont.truetype(dm.FONT, 12 * PX)
    tiny = ImageFont.truetype(dm.FONT, 11 * PX)
    capf = ImageFont.truetype(dm.FONT, 13 * PX)
    tx = PAD + PORTRAIT + GAP
    tw = W - tx - PAD
    y = PAD + 15 + 2 + 12 + 4
    rail_y = y
    y += 3 + 6
    cap_y = y
    y += 40 + 6
    prog_y = y
    y += 4 + 3 + 6
    row_y = y
    y += 24
    H = max(y, PAD + PORTRAIT + 6 + 20) + PAD
    w, h = W * PX, H * PX
    o = round((dm.EDGE - dm.INSET_U) * PX)
    back = Image.new("RGBA", (w + 2 * o, h + 2 * o))
    d = ImageDraw.Draw(back)
    c = tuple(int(v * 255) for v in inset[:3])
    d.rectangle((o, o, o + w - 1, o + h - 1), fill=c + (int(inset[3] * 255),))
    back = dm.border(back, theme, o, o, w, h)
    C = (back.width - (w + 2 * o)) // 2
    ox, oy = o + C, o + C
    img = back
    d = ImageDraw.Draw(img)
    P = lambda v: v * PX
    rail = dm.tex(theme, "rail")
    # Portrait stand-in: Spoken's round portrait, its ring tinted the title colour.
    gold = tuple(int(v * 255) for v in title)
    px0, py0 = ox + P(PAD), oy + P(PAD)
    d.ellipse((px0, py0, px0 + P(PORTRAIT), py0 + P(PORTRAIT)), fill=(40, 36, 30, 255), outline=gold, width=P(3))
    d.text((px0 + P(PORTRAIT) // 2, py0 + P(PORTRAIT) // 2), "?", font=font, fill=(120, 110, 90), anchor="mm")
    # The line's own buttons under it.
    d.rounded_rectangle((px0 + P(PORTRAIT) // 2 - P(10), py0 + P(PORTRAIT + 6), px0 + P(PORTRAIT) // 2 + P(10),
                         py0 + P(PORTRAIT + 26)), radius=P(4), fill=(60, 55, 50, 255))
    d.text((ox + P(tx), oy + P(PAD)), "Thrall", font=font, fill=gold, stroke_width=1, stroke_fill=(0, 0, 0))
    d.text((ox + P(tx), oy + P(PAD + 17)), "The Durotar Uprising", font=small, fill=(217, 217, 217))
    img.alpha_composite(rail.resize((P(tw), P(3))), (ox + P(tx), oy + P(rail_y)))
    for i, line in enumerate(CAPTION):
        d.text((ox + P(tx), oy + P(cap_y + i * 18)), line, font=capf, fill=(255, 255, 255) if i == 0 else (160, 160, 160))
    d.rectangle((ox + P(tx), oy + P(prog_y), ox + P(tx + tw), oy + P(prog_y + 4)), fill=(0, 0, 0, 160))
    acc = tuple(int(v * 255) for v in accent)
    d.rectangle((ox + P(tx), oy + P(prog_y), ox + P(tx) + int(P(tw) * 0.38), oy + P(prog_y + 4)), fill=acc)
    img.alpha_composite(rail.resize((P(tw), P(3))), (ox + P(tx), oy + P(prog_y + 3)))
    d.text((ox + P(tx), oy + P(row_y + 6)), "2 more lines", font=tiny, fill=(166, 166, 166))
    for i in range(5):
        bx = ox + P(tx + tw - 24 - i * 26)
        d.ellipse((bx, oy + P(row_y), bx + P(24), oy + P(row_y + 24)), fill=(30, 30, 30, 255), outline=(150, 140, 110), width=PX)
    return img


def main(args):
    out = args[0] if args else "spoken-themes.png"
    dm.trim_sizes()
    s = open(SPOKEN_LUA, encoding="utf-8").read()
    themes = colours()
    order = ["human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll",
             "highorder", "windshapers", "forsaken"]
    tiles = [(themes[t][0], render(t, *themes[t][1:], s)) for t in order]
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
