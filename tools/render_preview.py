#!/usr/bin/env python3
"""Render mockups of the console from the real layout code and art.

Runs ReforgedUI/Layout.lua through lua5.1 (tools/dump_layout.lua) and stacks
the original art the way Console.lua does (frame, draw layer, sublevel). Icons,
portrait, minimap terrain and chat lines are placeholders, so this shows
placement and art, not the game.

    python3 tools/render_preview.py            # writes docs/previews/*.png
    python3 tools/render_preview.py out.png 1365.33 orc 240 10 off
"""
import json
import math
import os
import random
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
ADDON = os.path.join(REPO, "ReforgedUI")
OUT = os.path.join(REPO, "docs", "previews")

FRAMES = {"bg": 0, "left": 1, "grid": 2, "right": 3}
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3}
TOPBAR = {  # mirrors Themes.lua
    "human": ("Human", (255, 209, 0), (5, 10, 26, 224), (217, 173, 77)),
    "orc": ("Orc", (255, 191, 64), (20, 8, 5, 224), (140, 128, 117)),
    "undead": ("Undead", (217, 242, 204), (10, 5, 18, 230), (204, 196, 179)),
    "nightelf": ("NightElf", (204, 235, 255), (5, 13, 20, 224), (140, 115, 84)),
    "dwarf": ("Dwarf", (255, 199, 115), (18, 13, 10, 224), (176, 122, 59)),
    "gnome": ("Gnome", (191, 242, 255), (10, 15, 20, 224), (184, 107, 59)),
    "tauren": ("Tauren", (255, 219, 158), (23, 15, 8, 224), (201, 163, 122)),
    "troll": ("Troll", (230, 219, 184), (13, 15, 13, 224), (217, 204, 176)),
    "highorder": ("HighOrder", (230, 237, 247), (15, 23, 41, 224), (204, 217, 230)),
    "windshapers": ("Windshapers", (224, 204, 138), (15, 23, 41, 224), (217, 199, 138)),
}
RACE_THEMES = ("dwarf", "gnome", "tauren", "troll", "highorder", "windshapers")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
_cache = {}


def font(size):
    try:
        return ImageFont.truetype(os.path.join(ADDON, "art", "other", "fonts", "blq55.TTF"), size)
    except OSError:
        try:
            return ImageFont.truetype(FONT, size)
        except OSError:
            return ImageFont.load_default()


def tex(path):
    if path not in _cache:
        _cache[path] = Image.open(path).convert("RGBA")
    return _cache[path]


def art(file):
    return tex(os.path.join(ADDON, "art", *file.split("\\")) + ".tga")


class Canvas:
    def __init__(self, W, H, world=True):
        self.W, self.H = int(round(W)), int(round(H))
        self.img = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        if world:
            rnd = random.Random(3)
            world = Image.new("RGBA", (self.W, self.H), (58, 74, 40, 255))
            d = ImageDraw.Draw(world)
            for _ in range(int(self.W * self.H / 900)):
                x, y, r = rnd.randrange(self.W), rnd.randrange(self.H), rnd.randrange(6, 40)
                c = rnd.choice([(70, 88, 46), (52, 66, 36), (88, 80, 52), (46, 60, 34)])
                d.ellipse([x - r, y - r, x + r, y + r], fill=c + (255,))
            self.img.alpha_composite(world)

    def box(self, x, y, w, h):
        return int(round(x)), int(round(self.H - y - h)), int(round(x + w)), int(round(self.H - y))

    def paste(self, im, x, y, w, h, tc=None):
        if w <= 0.5 or h <= 0.5:
            return
        if tc:
            l, r, t, b = tc
            W, H = im.size
            flipx, flipy = l > r, t > b
            l, r, t, b = min(l, r), max(l, r), min(t, b), max(t, b)
            im = im.crop((round(l * W), round(t * H), max(round(l * W) + 1, round(r * W)), max(round(t * H) + 1, round(b * H))))
            if flipx:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            if flipy:
                im = im.transpose(Image.FLIP_TOP_BOTTOM)
        x0, y0, x1, y1 = self.box(x, y, w, h)
        if x1 <= x0 or y1 <= y0:
            return
        im = im.resize((x1 - x0, y1 - y0), Image.LANCZOS)
        layer = Image.new("RGBA", self.img.size)
        layer.paste(im, (x0, y0))
        self.img.alpha_composite(layer)

    def rect(self, x, y, w, h, fill=None, outline=None):
        ImageDraw.Draw(self.img).rectangle(self.box(x, y, w, h), fill=fill, outline=outline)

    def text(self, x, y, w, h, s, size, color, align="center"):
        d = ImageDraw.Draw(self.img)
        f = font(size)
        x0, y0, x1, y1 = self.box(x, y, w, h)
        tw = d.textlength(s, font=f)
        tx = x0 + (x1 - x0 - tw) / 2 if align == "center" else x0
        ty = y0 + (y1 - y0 - size) / 2
        d.text((tx + 1, ty + 1), s, font=f, fill=(0, 0, 0, 255))
        d.text((tx, ty), s, font=f, fill=color)


def icon(seed):
    rnd = random.Random(seed)
    base = rnd.choice([(170, 60, 40), (60, 110, 200), (90, 160, 70), (180, 140, 50), (130, 70, 170), (60, 150, 160)])
    img = Image.new("RGBA", (64, 64), base + (255,))
    d = ImageDraw.Draw(img)
    for _ in range(5):
        x, y, r = rnd.randrange(64), rnd.randrange(64), rnd.randrange(8, 26)
        col = tuple(min(255, max(0, v + rnd.randrange(-70, 90))) for v in base)
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
    return img


def dump(w, theme, s, m, center):
    out = subprocess.check_output(["lua5.1", os.path.join(HERE, "dump_layout.lua"), str(w), theme, str(s), str(m), center])
    return json.loads(out)


def panel(c, folder, r):
    """The top bar: a hanging Reforged UI panel (see Art.lua)."""
    media = os.path.join(ADDON, "Media", folder)
    fill, edge = tex(os.path.join(media, "panel.tga")), tex(os.path.join(media, "edge.tga"))
    strip = Image.new("RGBA", (int(r["w"]), int(r["h"])))
    for x in range(0, strip.width, fill.width):
        strip.alpha_composite(fill, (x, 0))
    e = edge.resize((256, 32))
    e = e.resize((128, 16))
    for x in range(0, strip.width, e.width):
        strip.alpha_composite(e.transpose(Image.FLIP_TOP_BOTTOM), (x, strip.height - 16))
    c.paste(strip, r["x"], r["y"], r["w"], r["h"])


def top_bar(c, theme_key, T, hour=15):
    folder, title, inset, line = TOPBAR[theme_key]
    cl = T["clock"]
    dial = tex(os.path.join(ADDON, "Media", "Common", "dial.tga")).rotate(
        math.degrees((hour - 12) / 24 * 2 * math.pi), resample=Image.BICUBIC)
    c.paste(dial, cl["cx"] - cl["radius"], cl["cy"] - cl["radius"], 2 * cl["radius"], 2 * cl["radius"])
    panel(c, folder, T["topBar"])
    cf = T["clockFrame"]
    c.paste(tex(os.path.join(ADDON, "Media", folder, "clockframe.tga")), cf["x"], cf["y"], cf["w"], cf["h"])
    for b, label in zip(T["topButtons"], ["Quests", "Menu", "Allies", "Map"]):
        if b:
            c.rect(b["x"], b["y"], b["w"], b["h"], fill=inset, outline=line)
            c.text(b["x"], b["y"], b["w"], b["h"], label, 12, title)
    for i, b in enumerate(T["topSlots"]):
        c.rect(b["x"], b["y"], b["w"], b["h"], fill=inset, outline=line)
        if i < 3:
            c.text(b["x"], b["y"], b["w"], b["h"], ["87%", "34 / 80", "123"][i], 12, (255, 255, 255))


def render(path, w, theme, s=240, m=10, center="off"):
    L = dump(w, theme, s, m, center)
    c = Canvas(L["W"], L["H"])
    # Black backgrounds (backgroundMain) and the portrait.
    eb = L["extBg"]
    c.rect(eb["x"], eb["y"], eb["w"], eb["h"], fill=(0, 0, 0, 255))
    pb = L["portraitBg"]
    c.rect(pb["x"], pb["y"], pb["w"], pb["h"], fill=(0, 0, 0, 255))
    p = L["portrait"]
    port = Image.new("RGBA", (100, 100), (30, 30, 40, 255))
    d = ImageDraw.Draw(port)
    d.ellipse([28, 14, 72, 62], fill=(120, 150, 90, 255))
    d.rectangle([18, 62, 82, 100], fill=(90, 60, 40, 255))
    c.paste(port, p["x"], p["y"], p["w"], p["h"])
    pieces = sorted(enumerate(L["pieces"]), key=lambda ip: (FRAMES[ip[1]["frame"]], LAYERS[ip[1]["layer"]], ip[1]["sub"], ip[0]))
    for _, pc in pieces:
        if pc["shown"] and not (pc["frame"] == "grid" and False):
            r = pc["rect"]
            c.paste(art(pc["file"]), r["x"], r["y"], r["w"], r["h"], pc.get("tc"))
    # Minimap (Blizzard's, above the art).
    mm = L["minimap"]
    rnd = random.Random(7)
    terrain = Image.new("RGBA", (64, 64), (96, 120, 70, 255))
    d = ImageDraw.Draw(terrain)
    for _ in range(40):
        x, y, r = rnd.randrange(64), rnd.randrange(64), rnd.randrange(3, 10)
        d.ellipse([x - r, y - r, x + r, y + r], fill=rnd.choice([(120, 100, 70), (70, 100, 60), (60, 90, 140)]) + (255,))
    c.paste(terrain, mm["x"], mm["y"], mm["w"], mm["h"])
    if L.get("zoneText"):
        z = L["zoneText"]
        c.text(z["x"], z["y"], z["w"], z["h"], "Durotar", 11, (255, 209, 0))
    for i, r in enumerate(L["minimapSlots"]):
        c.paste(icon(10 + i), r["x"], r["y"], r["w"], r["h"])
    nm = L["noMail"]
    c.paste(icon(20), nm["x"], nm["y"], nm["w"], nm["h"])
    tr = L["tracking"]
    c.paste(icon(21), tr["cx"] - tr["size"] / 2, tr["cy"] - tr["size"] / 2, tr["size"], tr["size"])
    # Health and power.
    for key, colour, label in (("health", (0, 220, 0), "300 / 450"), ("power", (0, 0, 255), "120 / 200")):
        b = L[key]
        c.rect(b["x"], b["y"], b["w"], b["h"], fill=colour + (255,))
        c.text(b["x"], b["y"], b["w"], b["h"], label, 10, (255, 255, 255))
    # Experience bar.
    xp = L["xp"]
    bar = xp["bar"]
    c.paste(art("other\\xpProgressBar"), bar["x"], bar["y"], bar["w"] * 0.6, bar["h"])
    for key, f in (("left", "xp1"), ("middle", "xp2"), ("right", "xp3")):
        r = xp[key]
        c.paste(art("other\\" + f), r["x"], r["y"], r["w"], r["h"])
    c.text(xp["cx"] - 100, xp["nameY"] - 10, 200, 20, "Thrall", 16, (255, 209, 0))
    c.text(xp["cx"] - 100, xp["levelY"] - 8, 200, 16, "Level 12 Shaman", 12, (255, 255, 255))
    for i, (r, (lab, val)) in enumerate(zip(L["statIcons"], [("Damage:", "10 - 16"), ("Damage:", "N/A"), ("Spell:", "70"),
                                                              ("Armor:", "21.3%")])):
        c.paste(icon(30 + i), r["x"], r["y"], r["w"], r["h"])
        c.paste(art("other\\golden_frame"), r["x"], r["y"], r["w"], r["h"])
        lr, vr = r["label"], r["value"]
        c.text(lr["x"], lr["y"], lr["w"], lr["h"], lab, 10, (255, 209, 0), "left")
        c.text(vr["x"], vr["y"] + vr["h"] - 15, vr["w"], 15, val, 10, (255, 255, 255), "left")
    # Action bars 1-3.
    seed = 100
    for key in ("main", "bar2", "bar3"):
        row = L["bars"][key]
        for x in row["xs"]:
            seed += 1
            if random.Random(seed).random() < 0.8:
                c.paste(icon(seed), x, row["y"], row["size"], row["size"])
    for i, r in enumerate(L.get("inventory") or []):
        c.paste(icon(200 + i), r["x"], r["y"], r["w"], r["h"])
    if L.get("bags"):
        b = L["bags"]
        for i in range(6):
            x = b["right"] - b["size"] - i * b["step"]
            c.paste(icon(300 + i), x, b["top"] - b["size"], b["size"], b["size"])
    if L.get("chat"):
        ch = L["chat"]
        lines = ["[General] Grunt: Zug zug.", "[Guild] Rexxar: Anyone for Ragefire?",
                 "You receive loot: [Linen Cloth]x2.", "[Trade] Gazlowe: Selling bolts, cheap!"]
        for i, line in enumerate(reversed(lines)):
            y = ch["y"] + 2 + i * 15
            if y + 14 > ch["y"] + ch["h"]:
                break
            c.text(ch["x"], y, ch["w"], 14, line, 12, (255, 255, 255), "left")
        c.rect(ch["x"], ch["y"], ch["w"], ch["h"], outline=(255, 255, 0, 90))
    # Top bar, rendered at its own scale and laid over the console.
    T = L["topBar"]
    tc = Canvas(T["W"], T["H"], world=False)
    top_bar(tc, theme, T)
    c.img.alpha_composite(tc.img.resize((c.W, c.H), Image.LANCZOS))
    c.text(8, L["H"] - 70, 700, 20, "Reforged UI preview - %s, scale %s, %s (placeholders)" % (theme, s, center),
           14, (255, 255, 255), "left")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    c.img.convert("RGB").save(path, optimize=True)
    print("wrote", path)


def main():
    if len(sys.argv) > 2:
        a = sys.argv[1:]
        render(a[0], float(a[1]), a[2], int(a[3]) if len(a) > 3 else 240, int(a[4]) if len(a) > 4 else 10,
               a[5] if len(a) > 5 else "off")
        return
    for theme in ("human", "orc", "undead", "nightelf") + RACE_THEMES:
        render(os.path.join(OUT, "16x9-%s.png" % theme), 1365.33, theme)
    render(os.path.join(OUT, "21x9-nightelf-center.png"), 1792, "nightelf", 250, 40, "center")
    render(os.path.join(OUT, "32x9-orc.png"), 2730.67, "orc", 260, 30, "off")


if __name__ == "__main__":
    main()
