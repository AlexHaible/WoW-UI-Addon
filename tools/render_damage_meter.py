#!/usr/bin/env python3
"""Mock up the damage meter skin (ReforgedUI_DamageMeter) for every theme.

    python3 tools/render_damage_meter.py out.png [width height]

Lays the border out the way DamageMeter.lua does (its FRAMES table, read from
the file) around a window of the given size in window units (default
400x200, Blizzard's default), with placeholder bars in class colours. Shows
the art and its fit, not the game: Blizzard's dropdowns and icons are left
out.
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
DM = os.path.join(REPO, "ReforgedUI_DamageMeter")
THEMES_LUA = os.path.join(REPO, "ReforgedUI", "Themes.lua")
FONT = os.path.join(REPO, "ReforgedUI", "art", "other", "fonts", "blq55.TTF")
PX = 2  # output pixels per window unit
BARS = [("Thrall", (0.0, 0.44, 0.87), 1.0), ("Jaina", (0.25, 0.78, 0.92), 0.86),
        ("Uther", (0.96, 0.55, 0.73), 0.71), ("Tyrande", (1.0, 0.49, 0.04), 0.62),
        ("Sylvanas", (0.67, 0.83, 0.45), 0.55), ("Rexxar", (0.78, 0.61, 0.43), 0.40)]


FOLDERS = {"human": "Human", "orc": "Orc", "undead": "Undead", "nightelf": "NightElf", "dwarf": "Dwarf",
           "gnome": "Gnome", "tauren": "Tauren", "troll": "Troll", "highorder": "HighOrder",
           "windshapers": "Windshapers", "forsaken": "Forsaken"}


def lua_table(src, name):
    body = src[src.index("local %s = {" % name):]
    return {m.group(1): {k: int(v) for k, v in re.findall(r"(\w+) = (\d+)", m.group(2))}
            for m in re.finditer(r"\t(\w+) = \{ ([^}]*) \},", body[:body.index("\n}")])}


def insets():
    src = open(THEMES_LUA, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\t(\w+) = \{\n\t\tname = \"([^\"]+)\".*?inset = \{ ([\d., ]+) \}", src, re.S):
        out[m.group(1)] = (m.group(2), tuple(float(v) for v in m.group(3).split(",")))
    return out


def tex(theme, name):
    return Image.open(os.path.join(DM, "art", theme, name + ".tga")).convert("RGBA")


def tiled(img, w, h, u1, v1, axis):
    """img's (0..u1, 0..v1) texcoord window, repeated along `axis`, as w x h."""
    sw, sh = img.size
    if axis == 0:  # horizontal repeat, v clamped to 0..v1
        strip = img.crop((0, 0, sw, max(1, round(sh * v1))))
        period = max(1, round(w / u1))
        strip = strip.resize((period, h), Image.LANCZOS)
        out = Image.new("RGBA", (w, h))
        for x in range(0, w, period):
            out.alpha_composite(strip.crop((0, 0, min(period, w - x), h)), (x, 0))
    else:
        strip = img.crop((0, 0, max(1, round(sw * u1)), sh))
        period = max(1, round(h / v1))
        strip = strip.resize((w, period), Image.LANCZOS)
        out = Image.new("RGBA", (w, h))
        for y in range(0, h, period):
            out.alpha_composite(strip.crop((0, 0, w, min(period, h - y))), (0, y))
    return out


def kit(theme, name):
    folder = FOLDERS[theme]
    own = os.path.join(DM, "art", theme, name + ".tga")
    if os.path.exists(own):
        return Image.open(own).convert("RGBA")
    return Image.open(os.path.join(REPO, "ReforgedUI", "Media", folder, name + ".tga")).convert("RGBA")


def repeat(img, w, h, period, axis):
    """img scaled so one repeat is `period` px along `axis`, tiled to w x h."""
    if axis == 0:
        piece = img.resize((period, h), Image.LANCZOS)
    else:
        piece = img.resize((w, period), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    step = period
    for i in range(0, w if axis == 0 else h, step):
        out.alpha_composite(piece, (i, 0) if axis == 0 else (0, i))
    return out.crop((0, 0, w, h))


def border(img, theme, ox, oy, w, h):
    E, C, OUT, INSET = (round(v * PX) for v in (EDGE, CORNER, CORNER_OUT, INSET_U))
    x0, y0 = ox - E + INSET, oy - E + INSET
    x1, y1 = ox + w + E - INSET, oy + h + E - INSET
    canvas = Image.new("RGBA", (img.width + 2 * C, img.height + 2 * C))
    canvas.alpha_composite(img, (C, C))
    x0, y0, x1, y1 = x0 + C, y0 + C, x1 + C, y1 + C
    edge, edgev, corner = kit(theme, "edge"), kit(theme, "edgev"), kit(theme, "corner")
    ep = round(edge.width * E / edge.height)
    vp = round(edgev.height * E / edgev.width)
    top = repeat(edge, x1 - x0, E, ep, 0)
    canvas.alpha_composite(top, (x0, y0))
    canvas.alpha_composite(top.transpose(Image.FLIP_TOP_BOTTOM), (x0, y1 - E))
    side = repeat(edgev, E, y1 - y0 - 2 * E + 4, vp, 1)
    canvas.alpha_composite(side.transpose(Image.FLIP_LEFT_RIGHT), (x1 - E, y0 + E - 2))
    canvas.alpha_composite(side, (x0, y0 + E - 2))
    c = corner.resize((C, C), Image.LANCZOS)
    canvas.alpha_composite(c, (x1 - C + OUT, y0 - OUT))
    canvas.alpha_composite(c.transpose(Image.FLIP_LEFT_RIGHT), (x0 - OUT, y0 - OUT))
    cb = c.transpose(Image.FLIP_TOP_BOTTOM)
    canvas.alpha_composite(cb, (x1 - C + OUT, y1 - C + OUT))
    canvas.alpha_composite(cb.transpose(Image.FLIP_LEFT_RIGHT), (x0 - OUT, y1 - C + OUT))
    return canvas


def render(theme, m, inset, scale, W, H):
    l = r = t = b = round((EDGE - INSET_U) * PX)
    w, h = W * PX, H * PX
    img = Image.new("RGBA", (w + l + r, h + t + b))
    ox, oy = l, t
    # Inside: Blizzard's background and header, recoloured.
    c = tuple(int(v * 255) for v in inset[:3])
    d = ImageDraw.Draw(img)
    d.rectangle((ox, oy, ox + w - 1, oy + h - 1), fill=c + (int(0.85 * 255),))
    d.rectangle((ox, oy, ox + w - 1, oy + 32 * PX - 1), fill=c + (255,))
    rail = tex(theme, "rail")
    img.alpha_composite(rail.resize((w, 3 * PX)), (ox, oy + 32 * PX - PX))
    font = ImageFont.truetype(FONT, 11 * PX)
    d.text((ox + 4 * PX, oy + 9 * PX), "0:42  Damage Done", font=font, fill=(255, 209, 0))
    y = oy + 34 * PX
    bh, gap = 24 * PX, 2 * PX
    for name, col, frac in BARS:
        if y + bh > oy + h:
            break
        d.rectangle((ox + 2 * PX, y, ox + w - 4 * PX, y + bh - 1), fill=c + (190,))
        bw = int((w - 6 * PX) * frac)
        top = tuple(int(v * 255) for v in col)
        for yy in range(bh):  # UI-StatusBar: a soft vertical sheen
            f = 0.75 + 0.35 * (1 - abs(yy - bh * 0.35) / bh)
            d.line((ox + 2 * PX, y + yy, ox + 2 * PX + bw, y + yy),
                   fill=tuple(min(255, int(v * f)) for v in top) + (255,))
        img.alpha_composite(rail.resize((w - 6 * PX, 3 * PX)), (ox + 2 * PX, y + bh - PX))
        d.text((ox + 6 * PX, y + 5 * PX), name, font=font, fill=(255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0))
        val = "%.1fK" % (frac * 812.4)
        d.text((ox + w - 8 * PX - d.textlength(val, font=font), y + 5 * PX), val, font=font,
               fill=(255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0))
        y += bh + gap
    # Border, as PaintBorder lays it out: the theme's top bar trim (edge,
    # edgev, corner from ReforgedUI/Media) around the outside of the window,
    # overlapping it by INSET.
    img = border(img, theme, ox, oy, w, h)
    return img


def main(args):
    out = args[0] if args else "damage-meter.png"
    W, H = (int(args[1]), int(args[2])) if len(args) > 2 else (400, 200)
    src = open(os.path.join(DM, "DamageMeter.lua"), encoding="utf-8").read()
    global EDGE, CORNER, CORNER_OUT, INSET_U
    num = lambda n: float(re.search(r"local %s = ([\d.]+)" % n, src).group(1))
    EDGE, CORNER, CORNER_OUT, INSET_U = num("EDGE"), num("CORNER"), num("CORNER_OUT"), num("INSET")
    frames = {t: None for t in FOLDERS}
    scale = 1
    names = insets()
    order = ["human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll",
             "highorder", "windshapers", "forsaken"]
    tiles = [(names[t][0], render(t, frames[t], names[t][1], scale, W, H)) for t in order]
    cw = max(i.width for _, i in tiles) + 40
    ch = max(i.height for _, i in tiles) + 60
    cols = 3
    sheet = Image.new("RGBA", (cw * cols, ch * ((len(tiles) + cols - 1) // cols)), (58, 66, 54, 255))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 28)
    for i, (name, img) in enumerate(tiles):
        x, y = (i % cols) * cw + 20, (i // cols) * ch + 10
        d.text((x, y), name, font=font, fill=(255, 230, 160))
        sheet.alpha_composite(img, (x, y + 42))
    sheet.convert("RGB").save(out)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1:])
