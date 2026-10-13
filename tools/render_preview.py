#!/usr/bin/env python3
"""Render mockups of the console from the real layout code and art.

Runs ReforgedUI/Layout.lua through lua5.1 (tools/dump_layout.lua) and stacks
the original art the way Console.lua does (frame, draw layer, sublevel). Icons,
portrait, minimap terrain and chat lines are placeholders, so this shows
placement and art, not the game.

    python3 tools/render_preview.py            # writes docs/previews/*.png
    python3 tools/render_preview.py out.png 1365.33 orc 240 10
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
        tx = x0 + (x1 - x0 - tw) / 2 if align == "center" else (x1 - tw if align == "right" else x0)
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


def dump(w, theme, s, m):
    out = subprocess.check_output(["lua5.1", os.path.join(HERE, "dump_layout.lua"), str(w), theme, str(s), str(m)])
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
    panel(c, folder, T["topBar"])
    c.paste(dial, cl["cx"] - cl["radius"], cl["cy"] - cl["radius"], 2 * cl["radius"], 2 * cl["radius"])
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


def face(skin, body):
    """Placeholder portrait."""
    port = Image.new("RGBA", (100, 100), (30, 30, 40, 255))
    d = ImageDraw.Draw(port)
    d.ellipse([28, 14, 72, 62], fill=skin + (255,))
    d.rectangle([18, 62, 82, 100], fill=body + (255,))
    return port


# The fake target: a hostile elite casting, three combo points on it, its
# target is you.
TARGET = {"name": "Hogger", "colour": (255, 51, 38), "info": "Level 11 Elite Humanoid",
          "health": (412, 666), "power": (30, 100), "powerColour": (255, 0, 0), "cast": ("Rabid Bite", 0.6), "combo": 3}


def bar(c, r, frac, colour, label=None, size=10):
    c.rect(r["x"], r["y"], r["w"], r["h"], fill=(0, 0, 0, 160))
    c.rect(r["x"], r["y"], r["w"] * frac, r["h"], fill=colour + (255,))
    if label:
        c.text(r["x"], r["y"], r["w"], r["h"], label, size, (255, 255, 255))


def pips(c, P, n):
    for i in range(5):
        x = P["x"] + i * P["step"]
        sz = P["size"]
        cx, cy = x + sz / 2, P["y"] + sz / 2
        x0, y0, x1, y1 = c.box(cx - sz / 2 - 1, cy - sz / 2 - 1, sz + 2, sz + 2)
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        rr = (x1 - x0) / 2 * 1.2
        d = ImageDraw.Draw(c.img)
        d.polygon([(mx, my - rr), (mx + rr, my), (mx, my + rr), (mx - rr, my)], fill=(0, 0, 0, 220))
        if i < n:
            rr = rr - 2
            d.polygon([(mx, my - rr), (mx + rr, my), (mx, my + rr), (mx - rr, my)], fill=(255, 199, 26, 255))


def target_bits(c, v, T, pair_text=True):
    """Health, power, combo points and cast bar of the target view `v`."""
    h, hm = T["health"]
    pw, pm = T["power"]
    bar(c, v["health"], h / hm, (26, 217, 26), "%d / %d" % (h, hm) if pair_text else None, 11)
    bar(c, v["power"], pw / pm, T["powerColour"], "%d / %d" % (pw, pm) if pair_text else None, 10)


def tot(c, L):
    t = L["tot"]
    i = t["icon"]
    c.rect(i["x"] - 2, i["y"] - 2, i["w"] + 4, i["h"] + 4, fill=(64, 140, 255, 255))  # it's you: blue
    c.paste(face((120, 150, 90), (90, 60, 40)), i["x"], i["y"], i["w"], i["h"])
    c.paste(art("other\\golden_frame"), i["x"], i["y"], i["w"], i["h"])
    bar(c, t["health"], 0.67, (26, 230, 26))


def render(path, w, theme, s=240, m=10, target=None):
    L = dump(w, theme, s, m)
    T = TARGET
    c = Canvas(L["W"], L["H"])
    # Black backgrounds (backgroundMain) and the portrait.
    eb = L["extBg"]
    c.rect(eb["x"], eb["y"], eb["w"], eb["h"], fill=(0, 0, 0, 255))
    pb = L["portraitBg"]
    c.rect(pb["x"], pb["y"], pb["w"], pb["h"], fill=(0, 0, 0, 255))
    p = L["portrait"]
    swap = target == "swap"
    port = face((150, 110, 70), (110, 40, 30)) if swap else face((120, 150, 90), (90, 60, 40))
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
    xbar = xp["bar"]
    if not swap:
        c.paste(art("other\\xpProgressBar"), xbar["x"], xbar["y"], xbar["w"] * 0.6, xbar["h"])
    for key, f in (("left", "xp1"), ("middle", "xp2"), ("right", "xp3")):
        r = xp[key]
        c.paste(art("other\\" + f), r["x"], r["y"], r["w"], r["h"])
    if swap:
        c.text(xp["cx"] - 100, xp["nameY"] - 10, 200, 20, T["name"], 16, T["colour"])
        c.text(xp["cx"] - 100, xp["levelY"] - 8, 200, 16, T["info"], 12, (255, 255, 255))
        S = L["targetSwap"]
        target_bits(c, S, T)
        pips(c, S["combo"], T["combo"])
        name, frac = T["cast"]
        bar(c, S["cast"], frac, (255, 179, 0), name, 9)
    else:
        c.text(xp["cx"] - 100, xp["nameY"] - 10, 200, 20, "Thrall", 16, (255, 209, 0))
        c.text(xp["cx"] - 100, xp["levelY"] - 8, 200, 16, "Level 12 Shaman", 12, (255, 255, 255))
    for i, (r, (lab, val)) in enumerate(zip(L["statIcons"], [("Damage:", "10 - 16"), ("Damage:", "N/A"), ("Spell:", "70"),
                                                              ("Armor:", "21.3%")])):
        if swap:
            break
        c.paste(icon(30 + i), r["x"], r["y"], r["w"], r["h"])
        c.paste(art("other\\golden_frame"), r["x"], r["y"], r["w"], r["h"])
        lr, vr = r["label"], r["value"]
        c.text(lr["x"], lr["y"], lr["w"], lr["h"], lab, 10, (255, 209, 0), "left")
        c.text(vr["x"], vr["y"] + vr["h"] - 15, vr["w"], 15, val, 10, (255, 255, 255), "left")
    if target == "plate":
        P = L["targetPlate"]
        r = P["portraitBg"]
        c.rect(r["x"], r["y"], r["w"], r["h"], fill=(0, 0, 0, 255))
        r = P["portrait"]
        c.paste(face((150, 110, 70), (110, 40, 30)), r["x"], r["y"], r["w"], r["h"])
        for pc in P["pieces"]:
            r = pc["rect"]
            c.paste(art(pc["file"]), r["x"], r["y"], r["w"], r["h"], pc["tc"])
        target_bits(c, P, T, pair_text=False)
        b = P["box"]
        folder, title, inset, line = TOPBAR[theme]
        c.rect(b["x"], b["y"], b["w"], b["h"], fill=inset, outline=line)
        c.text(P["name"]["x"], P["name"]["y"], P["name"]["w"], P["name"]["h"], T["name"], 13, T["colour"], "left")
        c.text(P["info"]["x"], P["info"]["y"], P["info"]["w"], P["info"]["h"], T["info"], 10, (255, 255, 255), "left")
        h, hm = T["health"]
        pw, pm = T["power"]
        r = P["healthText"]
        c.text(r["x"], r["y"], r["w"], r["h"], "%d / %d" % (h, hm), 10, (64, 255, 64), "left")
        r = P["powerText"]
        c.text(r["x"], r["y"], r["w"], r["h"], "%d / %d" % (pw, pm), 10, (255, 128, 128), "right")
        pips(c, P["combo"], T["combo"])
        name, frac = T["cast"]
        bar(c, P["cast"], frac, (255, 179, 0), name, 8)
    if target:
        tot(c, L)
    # Action bars 1-3.
    seed = 100
    for key in ("main", "bar2", "bar3"):
        row = L["bars"][key]
        for x in row["xs"]:
            seed += 1
            if random.Random(seed).random() < 0.8:
                c.paste(icon(seed), x, row["y"], row["size"], row["size"])
    # Bags in the inventory (no reagent bag slot here), the key ring beside it.
    for i, r in enumerate((L.get("bagSlots") or [])[:5]):
        c.paste(icon(300 + i), r["x"], r["y"], r["w"], r["h"])
    if L.get("keyRing"):
        k = L["keyRing"]
        c.rect(k["x"], k["y"], k["w"], k["h"], fill=(150, 120, 60, 255), outline=(60, 40, 20, 255))
    # Three stance (aura) buttons on the wall.
    st = L["stance"]
    for i in range(3):
        x = st["x"] + i * st["step"]
        c.paste(icon(400 + i), x, st["y"], st["size"], st["size"])
        c.rect(x, st["y"], st["size"], st["size"], outline=(200, 170, 90, 255))
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
        e = L["chatEdit"]
        c.rect(e["x"], e["y"] + 2, e["w"], e["h"] - 4, fill=(20, 20, 20, 255), outline=(110, 110, 110, 255))
    # Top bar, rendered at its own scale and laid over the console.
    T = L["topBar"]
    tc = Canvas(T["W"], T["H"], world=False)
    top_bar(tc, theme, T)
    c.img.alpha_composite(tc.img.resize((c.W, c.H), Image.LANCZOS))
    c.text(8, L["H"] - 70, 700, 20, "Reforged UI preview - %s, scale %s (placeholders)" % (theme, s),
           14, (255, 255, 255), "left")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    c.img.convert("RGB").save(path, optimize=True)
    print("wrote", path)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--target":
        # python3 tools/render_preview.py --target swap|plate out.png [width theme scale chatUp]
        a = sys.argv[2:]
        render(a[1], float(a[2]) if len(a) > 2 else 1365.33, a[3] if len(a) > 3 else "orc",
               int(a[4]) if len(a) > 4 else 240, int(a[5]) if len(a) > 5 else 10, target=a[0])
        return
    if len(sys.argv) > 2:
        a = sys.argv[1:]
        render(a[0], float(a[1]), a[2], int(a[3]) if len(a) > 3 else 240, int(a[4]) if len(a) > 4 else 10)
        return
    for theme in ("human", "orc", "undead", "nightelf") + RACE_THEMES:
        render(os.path.join(OUT, "16x9-%s.png" % theme), 1365.33, theme)
    render(os.path.join(OUT, "21x9-nightelf.png"), 1792, "nightelf", 250, 40)
    render(os.path.join(OUT, "32x9-orc.png"), 2730.67, "orc", 260, 30)
    render(os.path.join(OUT, "32x9-dwarf.png"), 2730.67, "dwarf", 240, 10)


if __name__ == "__main__":
    main()
