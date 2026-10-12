#!/usr/bin/env python3
"""Render mockups of the console from the real layout code and textures.

Runs ReforgedUI/Layout.lua through lua5.1 (tools/dump_layout.lua) and draws the
console art the same way Console.lua does. Icons, portrait, minimap terrain and
chat lines are placeholders, so this shows placement and art, not the game.

    python3 tools/render_preview.py            # writes docs/previews/*.png
"""
import json
import os
import random
import subprocess

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
MEDIA = os.path.join(REPO, "ReforgedUI", "Media")
OUT = os.path.join(REPO, "docs", "previews")

THEMES = {  # mirrors Themes.lua
    "Human": dict(title=(255, 209, 0), inset=(5, 10, 26, 224), line=(217, 173, 77), xp=(148, 82, 219), accent=(115, 158, 255)),
    "Orc": dict(title=(255, 191, 64), inset=(20, 8, 5, 224), line=(140, 128, 117), xp=(204, 77, 31), accent=(242, 77, 38)),
    "Undead": dict(title=(217, 242, 204), inset=(10, 5, 18, 230), line=(204, 196, 179), xp=(77, 217, 140), accent=(89, 255, 166)),
    "NightElf": dict(title=(204, 235, 255), inset=(5, 13, 20, 224), line=(140, 115, 84), xp=(158, 115, 242), accent=(128, 235, 217)),
}

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
FONT_SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def font(size, sans=False):
    try:
        return ImageFont.truetype(FONT_SANS if sans else FONT, size)
    except OSError:
        return ImageFont.load_default()


def layout(w, h, profile):
    out = subprocess.check_output(["lua5.1", os.path.join(HERE, "dump_layout.lua"), str(w), str(h), profile])
    return json.loads(out)


class Canvas:
    def __init__(self, W, H, world=True):
        self.W, self.H = int(round(W)), int(round(H))
        self.img = Image.new("RGBA", (self.W, self.H))
        if world:
            self.draw_world()

    def box(self, x, y, w, h):
        """Console coordinates (origin bottom-left) to an image box."""
        x0, y1 = int(round(x)), int(round(self.H - y))
        return x0, int(round(self.H - y - h)), int(round(x + w)), y1

    def draw_world(self):
        rnd = random.Random(3)
        world = Image.new("RGBA", (self.W, self.H), (58, 74, 40, 255))
        d = ImageDraw.Draw(world)
        for _ in range(int(self.W * self.H / 900)):
            x, y = rnd.randrange(self.W), rnd.randrange(self.H)
            r = rnd.randrange(6, 40)
            c = rnd.choice([(70, 88, 46), (52, 66, 36), (88, 80, 52), (46, 60, 34)])
            d.ellipse([x - r, y - r, x + r, y + r], fill=c + (255,))
        self.img.alpha_composite(world)

    def tile(self, tex, x, y, w, h, period_w=None, period_h=None, ox=0, oy=0):
        if w <= 0 or h <= 0:
            return
        pw, ph = period_w or tex.width, period_h or tex.height
        if (pw, ph) != tex.size:
            tex = tex.resize((max(1, int(round(pw))), max(1, int(round(ph)))), Image.LANCZOS)
        x0, y0, x1, y1 = self.box(x, y, w, h)
        region = Image.new("RGBA", (x1 - x0, y1 - y0))
        sx = int(round(ox)) % tex.width
        for tx in range(-sx, region.width, tex.width):
            for ty in range(0, region.height, tex.height):
                region.alpha_composite(tex, (max(tx, 0), ty), (max(-tx, 0), 0))
        self.img.alpha_composite(region, (x0, y0))

    def paste(self, tex, x, y, w, h):
        x0, y0, x1, y1 = self.box(x, y, w, h)
        self.img.alpha_composite(tex.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))

    def rect(self, x, y, w, h, fill=None, outline=None, width=1):
        d = ImageDraw.Draw(self.img)
        d.rectangle(self.box(x, y, w, h), fill=fill, outline=outline, width=width)

    def text(self, x, y, w, h, s, size, color, align="center", sans=False):
        d = ImageDraw.Draw(self.img)
        f = font(size, sans)
        x0, y0, x1, y1 = self.box(x, y, w, h)
        tw = d.textlength(s, font=f)
        tx = x0 + (x1 - x0 - tw) / 2 if align == "center" else x0
        d.text((tx + 1, y0 + 1), s, font=f, fill=(0, 0, 0, 255))
        d.text((tx, y0), s, font=f, fill=color)


def load(faction, name):
    return Image.open(os.path.join(MEDIA, faction, name + ".tga")).convert("RGBA")


def panel(c, faction, r, corners):
    fill, edge, edgev, corner = (load(faction, n) for n in ("panel", "edge", "edgev", "corner"))
    ol, orr = r.get("openLeft", False), r.get("openRight", False)
    l, rt = (0 if ol else 4), (0 if orr else 4)
    c.tile(fill, r["x"] + l, r["y"], r["w"] - l - rt, r["h"] - 4, ox=r["x"] + l)
    # shade toward the bottom
    shade = Image.new("RGBA", (1, 64))
    for i in range(64):
        shade.putpixel((0, i), (0, 0, 0, int(90 * i / 63)))
    c.paste(shade, r["x"] + l, r["y"], r["w"] - l - rt, r["h"] - 4)
    c.tile(edge, r["x"], r["y"] + r["h"] - 16, r["w"], 16, 128, 16, ox=r["x"])
    if not ol:
        c.tile(edgev, r["x"], r["y"], 16, r["h"] - 14, 16, 64)
    if not orr:
        c.tile(edgev.transpose(Image.FLIP_LEFT_RIGHT), r["x"] + r["w"] - 16, r["y"], 16, r["h"] - 14, 16, 64)
    if corners and not ol:
        c.paste(corner.transpose(Image.FLIP_LEFT_RIGHT), r["x"] - 6, r["y"] + r["h"] - 34, 40, 40)
    if corners and not orr:
        c.paste(corner, r["x"] + r["w"] - 34, r["y"] + r["h"] - 34, 40, 40)


def top_bar(c, faction, theme, L, hour):
    cl = L["clock"]
    dial = Image.open(os.path.join(MEDIA, "Common", "dial.tga")).convert("RGBA")
    # Texture:SetRotation turns anticlockwise for positive angles, as PIL does.
    import math
    dial = dial.rotate(math.degrees((hour - 12) / 24 * 2 * math.pi), resample=Image.BICUBIC)
    r = cl["radius"]
    c.paste(dial, cl["cx"] - r, cl["cy"] - r, 2 * r, 2 * r)
    # The bar is a hanging panel: drawn as a normal one, then flipped.
    r = L["topBar"]
    strip = Canvas(r["w"], r["h"], world=False)
    panel(strip, faction, dict(x=0, y=0, w=r["w"], h=r["h"]), False)
    c.paste(strip.img.transpose(Image.FLIP_TOP_BOTTOM), r["x"], r["y"], r["w"], r["h"])
    cf = L["clockFrame"]
    c.paste(load(faction, "clockframe"), cf["x"], cf["y"], cf["w"], cf["h"])
    for b, label in zip(L["topButtons"], ["Quests", "Menu", "Allies", "Map"]):
        if b:
            inset(c, theme, b)
            c.text(b["x"], b["y"] + 3, b["w"], b["h"], label, 11, theme["title"])
    feeds = [("87%", (160, 160, 170, 255)), ("34 / 80", (150, 100, 60, 255)), ("123", (230, 190, 40, 255))]
    for i, b in enumerate(L["topSlots"]):
        inset(c, theme, b)
        if i < len(feeds):
            label, colour = feeds[i]
            c.text(b["x"] + 24, b["y"] + 3, b["w"] - 30, b["h"], label, 11, (255, 255, 255))
            c.rect(b["x"] + 6, b["y"] + 4, 12, 12, fill=colour)


def inset(c, theme, r):
    c.rect(r["x"], r["y"], r["w"], r["h"], fill=theme["inset"])
    line = theme["line"]
    dark = tuple(int(v * 0.45) for v in line)
    x, y, w, h = r["x"], r["y"], r["w"], r["h"]
    c.rect(x, y + h - 2, w, 2, fill=dark + (255,))
    c.rect(x, y, 2, h, fill=dark + (255,))
    c.rect(x, y, w, 2, fill=line + (255,))
    c.rect(x + w - 2, y, 2, h, fill=line + (255,))


def grid_cells(g):
    for i in range(int(g["cols"] * g["rows"])):
        col, row = i % int(g["cols"]), i // int(g["cols"])
        x = g["x"] + col * (g["size"] + g["gap"])
        y = g["y"] + g["h"] - g["size"] - row * (g["size"] + g.get("rowGap", g["gap"]))
        yield i, x, y


def icon(seed, size):
    rnd = random.Random(seed)
    base = rnd.choice([(170, 60, 40), (60, 110, 200), (90, 160, 70), (180, 140, 50), (130, 70, 170), (60, 150, 160)])
    img = Image.new("RGBA", (64, 64), base + (255,))
    d = ImageDraw.Draw(img)
    for _ in range(5):
        x, y, r = rnd.randrange(64), rnd.randrange(64), rnd.randrange(8, 26)
        col = tuple(min(255, max(0, v + rnd.randrange(-70, 90))) for v in base)
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
    bev = Image.open(os.path.join(MEDIA, "Common", "bevel.tga")).convert("RGBA")
    img.alpha_composite(bev)
    return img


def render(faction, w, h, profile, path, hour=15):
    L = layout(w, h, profile)
    theme = THEMES[faction]
    c = Canvas(L["W"], L["H"])
    panel(c, faction, L["base"], False)
    for p in L["panels"]:
        panel(c, faction, p, True)
    for sec in L.get("sections", []):
        tex = load(faction, "sections/" + sec["key"])
        u1 = sec.get("u1", 1)
        tex = tex.crop((0, 0, round(tex.width * u1), tex.height))
        c.paste(tex, sec["x"], sec["y"], sec["w"], sec["h"])
    m = L["minimap"]
    for r in L["insets"]:
        inset(c, theme, r)

    # minimap terrain placeholder
    rnd = random.Random(7)
    mm = Image.new("RGBA", (64, 64), (96, 120, 70, 255))
    d = ImageDraw.Draw(mm)
    for _ in range(40):
        x, y, r = rnd.randrange(64), rnd.randrange(64), rnd.randrange(3, 10)
        d.ellipse([x - r, y - r, x + r, y + r], fill=rnd.choice([(120, 100, 70), (70, 100, 60), (60, 90, 140)]) + (255,))
    mm = mm.resize((256, 256), Image.BICUBIC)
    ImageDraw.Draw(mm).polygon([(128, 116), (138, 142), (128, 136), (118, 142)], fill=(255, 255, 255, 255))
    c.paste(mm, m["x"], m["y"], m["w"], m["h"])
    z = L["zoneText"]
    c.text(z["x"], z["y"], z["w"], z["h"], "Durotar", 11, (255, 209, 0))
    col = L["minimapButtons"]
    for i in range(5):
        y = col["y"] + col["h"] - (i + 1) * col["w"] - i * 4
        c.paste(icon(100 + i, 28), col["x"], y, col["w"], col["w"])

    well = load(faction, "well")
    seed = 0
    for key in ("main", "bar2", "bar3", "bar4", "bar5"):
        g = L["bars"][key]
        pad = round(g["size"] * 0.12)
        for i, x, y in grid_cells(g):
            c.paste(well, x - pad, y - pad, g["size"] + 2 * pad, g["size"] + 2 * pad)
            seed += 1
            if (key in ("main", "bar2") and i < 10) or random.Random(seed).random() < 0.4:
                c.paste(icon(seed, g["size"]), x, y, g["size"], g["size"])
                if key == "main":
                    c.text(x + 2, y + g["size"] - 14, 12, 12, str((i + 1) % 10 if i < 10 else "-"), 10,
                           (230, 230, 230), "left", True)
    k = L["keyring"]
    c.paste(icon(77, 32), k["x"], k["y"], k["w"], k["h"])
    g = L["inventory"]
    pad = round(g["size"] * 0.12)
    for i, x, y in grid_cells(g):
        if i < 5:
            c.paste(icon(500 + i, g["size"]), x, y, g["size"], g["size"])
            c.text(x + g["size"] - 14, y + 2, 12, 11, str(4 + i * 3), 9, (255, 255, 255), "left", True)

    # portrait placeholder
    p = L["portrait"]
    port = Image.new("RGBA", (100, 100), (30, 30, 40, 255))
    d = ImageDraw.Draw(port)
    d.ellipse([28, 14, 72, 62], fill=(120, 150, 90, 255))
    d.rectangle([18, 62, 82, 100], fill=(90, 60, 40, 255))
    c.paste(port, p["x"], p["y"], p["w"], p["h"])
    r = L["healthText"]
    c.text(r["x"], r["y"], r["w"], r["h"], "300 / 450", 13, (90, 255, 90))
    r = L["powerText"]
    c.text(r["x"], r["y"], r["w"], r["h"], "120 / 200", 13, (80, 140, 255))

    r = L["nameText"]
    c.text(r["x"], r["y"], r["w"], r["h"], "Thrall", 15, theme["title"])
    r = L["xpBar"]
    c.rect(r["x"] - 2, r["y"] - 2, r["w"] + 4, r["h"] + 4, fill=theme["title"] + (255,))
    c.rect(r["x"] - 1, r["y"] - 1, r["w"] + 2, r["h"] + 2, fill=(0, 0, 0, 255))
    c.rect(r["x"], r["y"], r["w"] * 0.375, r["h"], fill=theme["xp"] + (110,))
    c.rect(r["x"], r["y"], r["w"] * 0.25, r["h"], fill=theme["xp"] + (255,))
    c.text(r["x"], r["y"] + 2, r["w"], r["h"], "Level 12 Shaman", 11, (255, 255, 255), sans=True)
    for i, (cell, (lab, val)) in enumerate(zip(L["stats"], [("Damage:", "10 - 16"), ("Spell:", "70"),
                                                             ("Armor:", "21.3%"), ("Healing:", "207")])):
        ic = cell["icon"]
        c.paste(icon(700 + i, ic["w"]), ic["x"], ic["y"], ic["w"], ic["h"])
        t = cell["text"]
        c.text(t["x"], t["y"] + t["h"] / 2, t["w"], t["h"] / 2, lab, 11, (255, 209, 0), "left", True)
        c.text(t["x"], t["y"], t["w"], t["h"] / 2, val, 11, (255, 255, 255), "left", True)

    # target panel placeholder
    T, Q = L["target"], L["tot"]
    p = T["portrait"]
    c.rect(p["x"], p["y"], p["w"], p["h"], fill=(60, 40, 30, 255))
    c.paste(icon(42, 64), p["x"] + 4, p["y"] + 4, p["w"] - 8, p["h"] - 8)
    c.text(T["name"]["x"], T["name"]["y"], T["name"]["w"], T["name"]["h"], "Bristleback Quilboar", 12,
           (255, 80, 0), "left", True)
    c.text(T["info"]["x"], T["info"]["y"], T["info"]["w"], T["info"]["h"], "Level 9 Elite Humanoid", 10,
           (220, 220, 220), "left", True)
    for key, colour, frac, label in (("health", (25, 200, 25), 0.7, "214 / 305"), ("power", (50, 100, 255), 1, "")):
        b = T[key]
        c.rect(b["x"] - 1, b["y"] - 1, b["w"] + 2, b["h"] + 2, fill=(0, 0, 0, 220))
        c.rect(b["x"], b["y"], b["w"] * frac, b["h"], fill=colour + (255,))
        if label:
            c.text(b["x"], b["y"] + 1, b["w"], b["h"], label, 10, (255, 255, 255), sans=True)
    cb = T["combo"]
    for i in range(3):
        c.rect(cb["x"] + i * (cb["h"] + 4), cb["y"], cb["h"], cb["h"], fill=(255, 210, 40, 255))
    p = Q["portrait"]
    c.paste(icon(43, 36), p["x"], p["y"], p["w"], p["h"])
    c.text(Q["name"]["x"], Q["name"]["y"], Q["name"]["w"], Q["name"]["h"], "Thrall", 11, (60, 160, 255), "left", True)
    b = Q["health"]
    c.rect(b["x"] - 1, b["y"] - 1, b["w"] + 2, b["h"] + 2, fill=(0, 0, 0, 220))
    c.rect(b["x"], b["y"], b["w"] * 0.66, b["h"], fill=(25, 200, 25, 255))

    cr = L["crest"]
    c.paste(load(faction, "crest"), cr["x"], cr["y"], cr["w"], cr["h"])

    # chat placeholder
    ch = L["chat"]
    lines = ["[General] Grunt: Zug zug.", "[Guild] Rexxar: Anyone for Ragefire?", "You receive loot: [Linen Cloth]x2.",
             "[Trade] Gazlowe: Selling bolts, cheap!", "Experience gained: 135."]
    for i, line in enumerate(reversed(lines)):
        y = ch["y"] + 4 + i * 16
        if y + 14 > ch["y"] + ch["h"]:
            break
        c.text(ch["x"], y, ch["w"], 14, line, 12, (255, 255, 255) if i else (255, 255, 0), "left", True)
    c.rect(ch["x"], ch["y"] + ch["h"], 60, 20, fill=(0, 0, 0, 140))
    c.text(ch["x"] + 6, ch["y"] + ch["h"] + 3, 60, 16, "General", 11, (255, 209, 0), "left", True)

    # micro menu placeholder
    mi = L["micro"]
    n, bw = 9, 22
    for i in range(n):
        x = mi["right"] - (n - i) * (bw + 2)
        c.paste(icon(900 + i, bw), x, mi["bottom"], bw, bw * 1.3)

    top_bar(c, faction, theme, L, hour)
    c.text(8, L["H"] - 60, 600, 20, "Reforged UI preview - %s, %s layout (placeholder icons)" % (faction, L["profile"]),
           14, (255, 255, 255), "left", True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = c.img.convert("RGB")
    # Rendered at the default console scale (1024 units tall), saved 768 tall.
    img = img.resize((round(img.width * 768 / img.height), 768), Image.LANCZOS)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, REPO))


def main():
    jobs = [
        # console units at the default scale: 1024 tall
        ("Human", 1820.44, 1024, "auto", "16x9-human"),
        ("Orc", 1820.44, 1024, "auto", "16x9-orc"),
        ("Undead", 1820.44, 1024, "auto", "16x9-undead"),
        ("NightElf", 1820.44, 1024, "auto", "16x9-nightelf"),
        ("NightElf", 2389.33, 1024, "auto", "21x9-nightelf"),
        ("Orc", 3640.89, 1024, "auto", "32x9-orc", 23),
    ]
    for faction, w, h, profile, name, *hour in jobs:
        render(faction, w, h, profile, os.path.join(OUT, name + ".png"), *hour)


if __name__ == "__main__":
    main()
