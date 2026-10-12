#!/usr/bin/env python3
"""Generate the procedural faction textures for Reforged UI.

These are original stand-ins for the Warcraft III: Reforged console art. Every
faction folder gets the same set of files, so extracted or hand-made art can be
dropped in later under the same names (.tga or .blp; the addon references them
without an extension).

    python3 tools/gen_textures.py            # fills in missing ReforgedUI/Media files
    python3 tools/gen_textures.py --force    # overwrites them all, extracted art included

Files per faction (all power-of-two, 32-bit TGA):
    panel.tga   256x256  tileable fill for console panels
    edge.tga    128x32   tileable trim, outer side at the top
    edgev.tga   32x128   the same trim rotated, outer side on the left
    corner.tga  64x64    corner ornament, oriented for the top-left corner
    well.tga    64x64    socket drawn behind every button slot
    crest.tga   256x256  faction emblem above the portrait
    clockframe.tga 256x128  frame around the day/night clock under the top bar
Common/bevel.tga 64x64  bevel laid over action button icons
Common/dial.tga 256x256  day/night disc (sun at the bottom, moon at the top)
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ReforgedUI", "Media")
SS = 4  # supersampling factor for vector shapes


# ---------------------------------------------------------------- helpers

def periodic_noise(w, h, fx, fy, seed, octaves=4):
    """Tileable fractal noise in [0, 1]. fx/fy are base frequencies (cycles per
    tile) which lets us stretch grain along one axis."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    ky = np.fft.fftfreq(h)[:, None] * h
    kx = np.fft.fftfreq(w)[None, :] * w
    for o in range(octaves):
        white = rng.standard_normal((h, w))
        sx, sy = fx * 2 ** o, fy * 2 ** o
        filt = np.exp(-((kx / sx) ** 2 + (ky / sy) ** 2))
        layer = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
        layer = (layer - layer.mean()) / (layer.std() + 1e-9)
        out += layer * amp
        total += amp
        amp *= 0.5
    out /= total
    out = (out - out.min()) / (out.max() - out.min())
    return out


def rgba(arr_rgb, alpha=None):
    arr_rgb = np.clip(arr_rgb, 0, 255).astype(np.uint8)
    h, w = arr_rgb.shape[:2]
    a = np.full((h, w), 255, np.uint8) if alpha is None else np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([arr_rgb, a]), "RGBA")


def colorize(t, dark, light):
    dark, light = np.array(dark, float), np.array(light, float)
    return dark[None, None, :] * (1 - t[..., None]) + light[None, None, :] * t[..., None]


FORCE = "--force" in sys.argv


def save(img, faction, name):
    folder = os.path.join(ROOT, faction)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    if os.path.exists(path) and not FORCE:
        print("skipping", os.path.relpath(path, ROOT), "(exists; use --force to overwrite)", file=sys.stderr)
        return
    img.save(path, format="TGA")


def canvas(w, h):
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def metal_profile(h, base, hi, lo, highlight_at=0.25):
    """Vertical shading for a bevelled metal bar of height h (top = outer)."""
    y = np.linspace(0, 1, h)
    shade = np.interp(y, [0, highlight_at, 0.55, 0.85, 1.0], [0.55, 1.0, 0.8, 0.55, 0.3])
    base, hi, lo = (np.array(c, float) for c in (base, hi, lo))
    col = np.where(shade[:, None] > 0.8,
                   base + (hi - base) * ((shade[:, None] - 0.8) / 0.2),
                   lo + (base - lo) * (shade[:, None] / 0.8))
    return col  # (h, 3)


def rivet(draw, cx, cy, r, base, hi, lo):
    s = SS
    draw.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], fill=lo)
    draw.ellipse([(cx - r * 0.85) * s, (cy - r * 0.85) * s, (cx + r * 0.7) * s, (cy + r * 0.7) * s], fill=base)
    draw.ellipse([(cx - r * 0.55) * s, (cy - r * 0.6) * s, (cx - r * 0.05) * s, (cy - r * 0.1) * s], fill=hi)



# ---------------------------------------------------------------- panels

def panel_human(seed=1):
    n, fine = periodic_noise(256, 256, 6, 6, seed), periodic_noise(256, 256, 40, 40, seed + 1, 2)
    img = colorize(n * 0.6 + fine * 0.4, (58, 62, 74), (122, 128, 142))
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:256, 0:256]
    row = yy // 64
    offset = np.where(row % 2 == 1, 64, 0)
    bx = (xx + offset) % 128
    by = yy % 64
    # per-block tint
    block_id = row * 4 + ((xx + offset) % 256) // 128
    tints = rng.uniform(0.82, 1.1, 32)
    img *= tints[block_id][..., None]
    # bevel: light top-left, dark bottom-right, mortar gaps
    d_left, d_top, d_right, d_bot = bx, by, 127 - bx, 63 - by
    edge = np.minimum.reduce([d_left, d_top, d_right, d_bot])
    hi = np.clip(1 - np.minimum(d_left, d_top) / 6, 0, 1) * 0.25
    lo = np.clip(1 - np.minimum(d_right, d_bot) / 6, 0, 1) * 0.35
    img *= (1 + hi - lo)[..., None]
    mortar = edge < 2
    img[mortar] = img[mortar] * 0.25 + np.array([18, 18, 24]) * 0.75
    return rgba(img)


def panel_orc(seed=2):
    grain = periodic_noise(256, 256, 2, 24, seed)
    fine = periodic_noise(256, 256, 8, 64, seed + 1, 2)
    t = grain * 0.7 + fine * 0.3
    t = 0.5 + 0.5 * np.sin(t * 18)  # rings
    img = colorize(t * 0.6 + grain * 0.4, (64, 32, 18), (138, 78, 44))
    yy, xx = np.mgrid[0:256, 0:256]
    py = yy % 64
    shade = np.interp(py, [0, 3, 10, 54, 61, 63], [0.25, 0.9, 1.08, 0.95, 0.7, 0.25])
    img *= shade[..., None]
    out = rgba(img)
    # iron nails at plank ends (keep away from tile seams)
    d = ImageDraw.Draw(out)
    for i, py0 in enumerate(range(0, 256, 64)):
        for px0 in ((40 + i * 70) % 256, (170 + i * 70) % 256):
            if 8 < px0 < 248:
                for cy in (py0 + 16, py0 + 48):
                    d.ellipse([px0 - 4, cy - 4, px0 + 4, cy + 4], fill=(30, 26, 24, 255))
                    d.ellipse([px0 - 3, cy - 3, px0 + 2, cy + 2], fill=(92, 86, 80, 255))
                    d.ellipse([px0 - 2, cy - 2, px0, cy], fill=(150, 140, 130, 255))
    return out


def panel_undead(seed=3):
    n = periodic_noise(256, 256, 5, 5, seed)
    fine = periodic_noise(256, 256, 30, 30, seed + 1, 2)
    img = colorize(n * 0.7 + fine * 0.3, (26, 22, 36), (78, 66, 96))
    v = periodic_noise(256, 256, 4, 4, seed + 7, 3)
    ridge = (1 - np.abs(2 * v - 1)) ** 28
    img += ridge[..., None] * np.array([30, 120, 80])
    v2 = periodic_noise(256, 256, 7, 7, seed + 9, 2)
    ridge2 = (1 - np.abs(2 * v2 - 1)) ** 20
    img = img * (1 - 0.6 * ridge2[..., None])
    return rgba(img)


def panel_nightelf(seed=4):
    grain = periodic_noise(256, 256, 22, 2, seed)
    fine = periodic_noise(256, 256, 60, 6, seed + 1, 2)
    t = grain * 0.65 + fine * 0.35
    img = colorize(t, (20, 38, 38), (72, 104, 88))
    moon = periodic_noise(256, 256, 3, 3, seed + 5, 2)
    img += (moon[..., None] - 0.5) * np.array([40, 10, 60])
    cracks = (1 - np.abs(2 * periodic_noise(256, 256, 16, 1, seed + 3, 2) - 1)) ** 30
    img *= (1 - 0.7 * cracks[..., None])
    return rgba(img)


# ---------------------------------------------------------------- trims

def edge_human():
    w, h = 128, 32
    prof = metal_profile(h, (196, 152, 62), (255, 228, 140), (92, 64, 24))
    img = np.repeat(prof[:, None, :], w, axis=1)
    img *= (0.92 + 0.12 * periodic_noise(w, h, 20, 4, 11, 2))[..., None]
    out = rgba(img)
    # inner dark lip so the trim reads against the stone
    d = ImageDraw.Draw(out)
    d.line([(0, h - 2), (w, h - 2)], fill=(30, 22, 10, 255), width=2)
    d.line([(0, 0), (w, 0)], fill=(60, 44, 16, 255), width=1)
    rv, rd = canvas(w, h)
    for cx in (32, 96):
        rivet(rd, cx, 13, 4.5, (205, 165, 80, 255), (255, 240, 180, 255), (70, 48, 16, 255))
    out.alpha_composite(finish(rv, w, h))
    return out


def edge_orc():
    w, h = 128, 32
    band_top = 11
    prof = metal_profile(h - band_top, (96, 88, 82), (170, 160, 150), (34, 30, 28))
    band = np.repeat(prof[:, None, :], w, axis=1)
    rust = periodic_noise(w, h - band_top, 16, 6, 21, 3)
    band = band * (1 - 0.35 * rust[..., None]) + rust[..., None] * np.array([70, 26, 8]) * 0.5
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(rgba(band), (0, band_top))
    sp, sd = canvas(w, h)
    # spikes along the outer side, tiled every 32px
    for cx in range(-16, w + 32, 32):
        cx += 16
        pts = [((cx - 7) * SS, (band_top + 1) * SS), (cx * SS, 0), ((cx + 7) * SS, (band_top + 1) * SS)]
        sd.polygon(pts, fill=(58, 52, 48, 255))
        sd.polygon([((cx - 2) * SS, (band_top - 1) * SS), (cx * SS, 2 * SS), ((cx + 1) * SS, (band_top - 1) * SS)],
                   fill=(176, 166, 154, 255))
    for cx in range(16, w, 32):
        rivet(sd, cx, band_top + 10, 3.5, (110, 100, 92, 255), (190, 180, 170, 255), (24, 20, 18, 255))
    sd.rectangle([0, (h - 4) * SS, w * SS, (h - 2) * SS], fill=(120, 24, 16, 255))  # red stripe
    out.alpha_composite(finish(sp, w, h))
    return out


def edge_undead():
    w, h = 128, 32
    img, d = canvas(w, h)
    d.rectangle([0, 8 * SS, w * SS, 26 * SS], fill=(34, 28, 44, 255))
    for cx in range(0, w + 32, 32):
        # vertebra: rounded bone segment with a notch
        x0, x1 = (cx - 13) * SS, (cx + 13) * SS
        d.rounded_rectangle([x0, 4 * SS, x1, 28 * SS], radius=9 * SS, fill=(150, 140, 124, 255))
        d.rounded_rectangle([x0 + 2 * SS, 6 * SS, x1 - 2 * SS, 22 * SS], radius=7 * SS, fill=(214, 206, 186, 255))
        d.ellipse([(cx - 3) * SS, 12 * SS, (cx + 3) * SS, 18 * SS], fill=(70, 60, 74, 255))
    out = finish(img, w, h)
    # bake a faint green glow beneath the bones
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rectangle([0, 26, w, 31], fill=(60, 220, 140, 140))
    glow = glow.filter(ImageFilter.GaussianBlur(2))
    glow.alpha_composite(out)
    return glow


def edge_nightelf():
    w, h = 128, 32
    prof = metal_profile(h - 6, (70, 52, 40), (130, 104, 78), (24, 18, 14), 0.3)
    band = np.repeat(prof[:, None, :], w, axis=1)
    band *= (0.85 + 0.3 * periodic_noise(w, h - 6, 24, 3, 31, 2))[..., None]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(rgba(band), (0, 3))
    vine, vd = canvas(w, h)
    for phase, col in ((0.0, (120, 230, 210, 255)), (math.pi, (176, 140, 236, 255))):
        pts = []
        for i in range(0, w * SS + 1, SS):
            x = i / SS
            y = 15 + 6 * math.sin(2 * math.pi * x / 64 + phase)
            pts.append((i, y * SS))
        vd.line(pts, fill=col, width=int(2.2 * SS))
    for cx in range(0, w, 32):  # leaves where the vines cross
        cx += 16
        vd.ellipse([(cx - 6) * SS, 11 * SS, (cx + 6) * SS, 19 * SS], fill=(60, 150, 110, 255))
        vd.line([((cx - 5) * SS, 15 * SS), ((cx + 5) * SS, 15 * SS)], fill=(30, 80, 60, 255), width=SS)
    out.alpha_composite(finish(vine, w, h))
    return out


# ---------------------------------------------------------------- corners

def corner_human():
    img, d = canvas(64, 64)
    s = SS
    d.rounded_rectangle([2 * s, 2 * s, 46 * s, 46 * s], radius=6 * s, fill=(80, 56, 20, 255))
    d.rounded_rectangle([4 * s, 4 * s, 44 * s, 44 * s], radius=5 * s, fill=(214, 172, 80, 255))
    d.rounded_rectangle([8 * s, 8 * s, 40 * s, 40 * s], radius=4 * s, fill=(150, 112, 42, 255))
    d.polygon([(24 * s, 10 * s), (38 * s, 24 * s), (24 * s, 38 * s), (10 * s, 24 * s)], fill=(30, 50, 130, 255))
    d.polygon([(24 * s, 14 * s), (34 * s, 24 * s), (24 * s, 34 * s), (14 * s, 24 * s)], fill=(70, 120, 230, 255))
    d.ellipse([19 * s, 17 * s, 25 * s, 23 * s], fill=(200, 225, 255, 255))
    for cx, cy in ((8, 8), (40, 8), (8, 40), (40, 40)):
        rivet(d, cx, cy, 3, (220, 180, 90, 255), (255, 240, 190, 255), (70, 48, 16, 255))
    return finish(img, 64, 64)


def corner_orc():
    img, d = canvas(64, 64)
    s = SS
    d.polygon([(0, 0), (40 * s, 6 * s), (46 * s, 46 * s), (6 * s, 40 * s)], fill=(40, 34, 32, 255))
    d.polygon([(4 * s, 4 * s), (38 * s, 10 * s), (42 * s, 42 * s), (10 * s, 38 * s)], fill=(104, 94, 86, 255))
    d.polygon([(12 * s, 12 * s), (34 * s, 16 * s), (36 * s, 36 * s), (16 * s, 34 * s)], fill=(132, 26, 18, 255))
    d.polygon([(0, 0), (24 * s, 18 * s), (18 * s, 24 * s)], fill=(200, 190, 176, 255))  # spike
    d.line([(2 * s, 2 * s), (20 * s, 20 * s)], fill=(255, 250, 240, 255), width=s)
    for cx, cy in ((36, 12), (12, 36), (38, 38)):
        rivet(d, cx, cy, 3, (120, 110, 100, 255), (200, 190, 180, 255), (20, 16, 14, 255))
    return finish(img, 64, 64)


def corner_undead():
    img, d = canvas(64, 64)
    s = SS
    d.ellipse([2 * s, 2 * s, 50 * s, 50 * s], fill=(40, 30, 54, 255))
    d.ellipse([5 * s, 5 * s, 47 * s, 47 * s], fill=(70, 210, 140, 90))
    # skull
    d.ellipse([12 * s, 9 * s, 40 * s, 35 * s], fill=(222, 214, 194, 255))
    d.rounded_rectangle([17 * s, 28 * s, 35 * s, 42 * s], radius=3 * s, fill=(222, 214, 194, 255))
    d.ellipse([16 * s, 19 * s, 24 * s, 28 * s], fill=(20, 60, 40, 255))
    d.ellipse([28 * s, 19 * s, 36 * s, 28 * s], fill=(20, 60, 40, 255))
    d.ellipse([18 * s, 21 * s, 22 * s, 25 * s], fill=(110, 255, 170, 255))
    d.ellipse([30 * s, 21 * s, 34 * s, 25 * s], fill=(110, 255, 170, 255))
    d.polygon([(26 * s, 28 * s), (23 * s, 33 * s), (29 * s, 33 * s)], fill=(40, 30, 40, 255))
    for i in range(4):
        x = 19 + i * 4
        d.line([(x * s, 36 * s), (x * s, 42 * s)], fill=(90, 80, 80, 255), width=s)
    return finish(img, 64, 64)


def corner_nightelf():
    img, d = canvas(64, 64)
    s = SS
    d.ellipse([2 * s, 2 * s, 50 * s, 50 * s], fill=(44, 34, 26, 255))
    d.ellipse([5 * s, 5 * s, 47 * s, 47 * s], fill=(28, 44, 70, 255))
    d.ellipse([10 * s, 10 * s, 42 * s, 42 * s], fill=(214, 226, 255, 255))
    d.ellipse([17 * s, 7 * s, 47 * s, 37 * s], fill=(28, 44, 70, 255))  # crescent cut
    for cx, cy in ((36, 36), (40, 20)):
        d.polygon([(cx * s, (cy - 4) * s), ((cx + 1) * s, (cy - 1) * s), ((cx + 4) * s, cy * s),
                   ((cx + 1) * s, (cy + 1) * s), (cx * s, (cy + 4) * s), ((cx - 1) * s, (cy + 1) * s),
                   ((cx - 4) * s, cy * s), ((cx - 1) * s, (cy - 1) * s)], fill=(190, 255, 240, 255))
    return finish(img, 64, 64)


# ---------------------------------------------------------------- wells

def well(frame, frame_hi, frame_lo, inner, glow=None):
    img, d = canvas(64, 64)
    s = SS
    d.rectangle([0, 0, 64 * s, 64 * s], fill=frame_lo)
    d.polygon([(0, 0), (64 * s, 0), (58 * s, 6 * s), (6 * s, 6 * s), (6 * s, 58 * s), (0, 64 * s)], fill=frame_hi)
    d.rectangle([3 * s, 3 * s, 61 * s, 61 * s], outline=frame, width=2 * s)
    d.rectangle([6 * s, 6 * s, 58 * s, 58 * s], fill=(0, 0, 0, 255))
    d.rectangle([7 * s, 7 * s, 57 * s, 57 * s], fill=inner)
    out = finish(img, 64, 64)
    if glow:
        g = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        ImageDraw.Draw(g).rectangle([7, 7, 57, 57], outline=glow, width=3)
        out.alpha_composite(g.filter(ImageFilter.GaussianBlur(2)))
    return out


# ---------------------------------------------------------------- crests

def crest_human():
    img, d = canvas(256, 256)
    s = SS

    def shield(inset, fill):
        i = inset
        pts = [((40 + i) * s, (40 + i) * s), ((216 - i) * s, (40 + i) * s), ((216 - i) * s, (120) * s)]
        for k in range(1, 20):
            t = k / 20
            x = (216 - i) - (88 - i) * t
            y = 120 + (110 - i * 1.2) * math.sin(t * math.pi / 2)
            pts.append((x * s, y * s))
        for k in range(20, 0, -1):
            t = k / 20
            x = (40 + i) + (88 - i) * t
            y = 120 + (110 - i * 1.2) * math.sin(t * math.pi / 2)
            pts.append((x * s, y * s))
        pts.append(((40 + i) * s, 120 * s))
        d.polygon(pts, fill=fill)

    shield(0, (70, 48, 14, 255))
    shield(5, (226, 186, 90, 255))
    shield(14, (120, 86, 30, 255))
    shield(18, (34, 64, 150, 255))
    # chevron and crown
    d.polygon([(64 * s, 170 * s), (128 * s, 112 * s), (192 * s, 170 * s), (192 * s, 194 * s),
               (128 * s, 136 * s), (64 * s, 194 * s)], fill=(240, 205, 110, 255))
    d.polygon([(84 * s, 96 * s), (84 * s, 62 * s), (104 * s, 80 * s), (128 * s, 54 * s), (152 * s, 80 * s),
               (172 * s, 62 * s), (172 * s, 96 * s)], fill=(240, 205, 110, 255))
    d.rectangle([84 * s, 92 * s, 172 * s, 102 * s], fill=(200, 160, 70, 255))
    for cx in (100, 128, 156):
        d.ellipse([(cx - 4) * s, 92 * s, (cx + 4) * s, 100 * s], fill=(180, 30, 40, 255))
    return finish(img, 256, 256)


def crest_orc():
    img, d = canvas(256, 256)
    s = SS
    # spiked iron ring
    for k in range(12):
        a = k * math.pi / 6
        tip = (128 + 122 * math.cos(a), 128 + 122 * math.sin(a))
        l = (128 + 92 * math.cos(a - 0.18), 128 + 92 * math.sin(a - 0.18))
        r = (128 + 92 * math.cos(a + 0.18), 128 + 92 * math.sin(a + 0.18))
        d.polygon([(l[0] * s, l[1] * s), (tip[0] * s, tip[1] * s), (r[0] * s, r[1] * s)], fill=(150, 140, 128, 255))
    d.ellipse([28 * s, 28 * s, 228 * s, 228 * s], fill=(44, 38, 34, 255))
    d.ellipse([38 * s, 38 * s, 218 * s, 218 * s], fill=(110, 100, 92, 255))
    d.ellipse([50 * s, 50 * s, 206 * s, 206 * s], fill=(140, 28, 18, 255))
    # crossed axes
    for sign in (1, -1):
        def p(x, y):
            return ((128 + sign * (x - 128)) * s, y * s)
        d.polygon([p(80, 70), p(90, 62), p(186, 180), p(176, 188)], fill=(80, 54, 30, 255))  # haft
        d.polygon([p(70, 60), p(108, 52), p(118, 70), p(102, 96), p(70, 104), p(60, 82)], fill=(200, 196, 188, 255))
        d.polygon([p(74, 66), p(104, 58), p(110, 70), p(98, 90), p(74, 96), p(66, 82)], fill=(150, 146, 140, 255))
    d.ellipse([112 * s, 112 * s, 144 * s, 144 * s], fill=(30, 24, 22, 255))
    rivet(d, 128, 128, 10, (120, 110, 100, 255), (220, 210, 200, 255), (20, 16, 14, 255))
    return finish(img, 256, 256)


def crest_undead():
    img, d = canvas(256, 256)
    s = SS
    hexagon = [(128 + 116 * math.cos(math.pi / 6 + k * math.pi / 3), 128 + 116 * math.sin(math.pi / 6 + k * math.pi / 3))
               for k in range(6)]
    d.polygon([(x * s, y * s) for x, y in hexagon], fill=(22, 16, 30, 255))
    inner = [(128 + 104 * math.cos(math.pi / 6 + k * math.pi / 3), 128 + 104 * math.sin(math.pi / 6 + k * math.pi / 3))
             for k in range(6)]
    d.polygon([(x * s, y * s) for x, y in inner], fill=(64, 46, 88, 255))
    d.ellipse([60 * s, 50 * s, 196 * s, 176 * s], fill=(70, 220, 150, 120))
    # skull
    d.ellipse([72 * s, 52 * s, 184 * s, 160 * s], fill=(228, 220, 200, 255))
    d.rounded_rectangle([92 * s, 140 * s, 164 * s, 196 * s], radius=10 * s, fill=(228, 220, 200, 255))
    d.ellipse([88 * s, 96 * s, 122 * s, 134 * s], fill=(18, 50, 34, 255))
    d.ellipse([134 * s, 96 * s, 168 * s, 134 * s], fill=(18, 50, 34, 255))
    d.ellipse([98 * s, 106 * s, 112 * s, 122 * s], fill=(120, 255, 180, 255))
    d.ellipse([144 * s, 106 * s, 158 * s, 122 * s], fill=(120, 255, 180, 255))
    d.polygon([(128 * s, 136 * s), (118 * s, 156 * s), (138 * s, 156 * s)], fill=(40, 28, 44, 255))
    for i in range(6):
        x = 100 + i * 11
        d.line([(x * s, 168 * s), (x * s, 194 * s)], fill=(110, 100, 96, 255), width=2 * s)
    return finish(img, 256, 256)


def crest_nightelf():
    img, d = canvas(256, 256)
    s = SS
    # leaves around a moon disc
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        cx, cy = 128 + 96 * math.cos(a), 128 + 96 * math.sin(a)
        pts = []
        for t in np.linspace(0, 2 * math.pi, 40):
            lx, ly = 30 * math.cos(t), 12 * math.sin(t)
            pts.append(((cx + lx * math.cos(a) - ly * math.sin(a)) * s, (cy + lx * math.sin(a) + ly * math.cos(a)) * s))
        d.polygon(pts, fill=(52, 140, 100, 255))
        d.line([((cx - 26 * math.cos(a)) * s, (cy - 26 * math.sin(a)) * s),
                ((cx + 26 * math.cos(a)) * s, (cy + 26 * math.sin(a)) * s)], fill=(24, 70, 50, 255), width=2 * s)
    d.ellipse([34 * s, 34 * s, 222 * s, 222 * s], fill=(60, 44, 32, 255))
    d.ellipse([42 * s, 42 * s, 214 * s, 214 * s], fill=(30, 26, 70, 255))
    d.ellipse([64 * s, 60 * s, 184 * s, 180 * s], fill=(222, 232, 255, 255))
    d.ellipse([92 * s, 48 * s, 206 * s, 162 * s], fill=(30, 26, 70, 255))
    for cx, cy, r in ((170, 158, 9), (184, 112, 6), (150, 186, 5)):
        d.polygon([(cx * s, (cy - r * 2) * s), ((cx + r * 0.4) * s, (cy - r * 0.4) * s), ((cx + r * 2) * s, cy * s),
                   ((cx + r * 0.4) * s, (cy + r * 0.4) * s), (cx * s, (cy + r * 2) * s),
                   ((cx - r * 0.4) * s, (cy + r * 0.4) * s), ((cx - r * 2) * s, cy * s),
                   ((cx - r * 0.4) * s, (cy - r * 0.4) * s)], fill=(180, 255, 236, 255))
    return finish(img, 256, 256)


def bevel():
    a = np.zeros((64, 64, 4), np.uint8)
    for i in range(5):
        alpha = int(150 * (1 - i / 5))
        a[i, i:64 - i] = (255, 255, 255, alpha)
        a[i:64 - i, i] = (255, 255, 255, alpha)
        a[63 - i, i:64 - i] = (0, 0, 0, int(alpha * 1.4))
        a[i:64 - i, 63 - i] = (0, 0, 0, int(alpha * 1.4))
    return Image.fromarray(a, "RGBA")


def dial():
    size = 256
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    cx = cy = (size - 1) / 2
    r = np.hypot(xx - cx, yy - cy)
    t = (yy - cy) / cx  # -1 top .. 1 bottom
    day = colorize(np.clip(t, 0, 1), (250, 170, 90), (90, 160, 235))  # horizon to sky
    night = colorize(np.clip(-t, 0, 1), (60, 50, 110), (8, 12, 40))
    img = np.where((t >= 0)[..., None], day, night)
    rng = np.random.default_rng(5)
    for _ in range(70):  # stars on the night half
        x, y = rng.integers(20, 236), rng.integers(10, 120)
        if np.hypot(x - cx, y - cy) < 118:
            img[y, x] = (230, 235, 255)
    alpha = np.clip((124 - r) * 64, 0, 255)
    out = rgba(img, alpha)
    d = ImageDraw.Draw(out)
    sx, sy = 128, 210  # sun
    for k in range(12):
        a = k * math.pi / 6
        d.line([(sx + 22 * math.cos(a), sy + 22 * math.sin(a)), (sx + 32 * math.cos(a), sy + 32 * math.sin(a))],
               fill=(255, 230, 120, 255), width=4)
    d.ellipse([sx - 18, sy - 18, sx + 18, sy + 18], fill=(255, 220, 90, 255))
    d.ellipse([sx - 12, sy - 12, sx + 10, sy + 10], fill=(255, 245, 190, 255))
    mx, my = 128, 46  # moon
    d.ellipse([mx - 20, my - 20, mx + 20, my + 20], fill=(225, 230, 250, 255))
    d.ellipse([mx - 8, my - 26, mx + 28, my + 12], fill=(30, 30, 80, 255))
    return out


def clockframe(name, metal, metal_hi, metal_lo):
    w, h = 256, 128
    k = w / 176  # pixels per console unit
    cx, cy = w / 2, 4 * k
    img, d = canvas(w, h)
    s = SS
    ro, ri = 64 * k, 52 * k
    # wing plates either side of the dial, flush with the top bar
    d.rounded_rectangle([4 * s, 0, (w - 4) * s, 18 * s], radius=6 * s, fill=metal_lo)
    d.rounded_rectangle([6 * s, 0, (w - 6) * s, 15 * s], radius=5 * s, fill=metal)
    # ring around the lower half of the dial
    d.ellipse([(cx - ro - 3) * s, (cy - ro - 3) * s, (cx + ro + 3) * s, (cy + ro + 3) * s], fill=metal_lo)
    d.ellipse([(cx - ro) * s, (cy - ro) * s, (cx + ro) * s, (cy + ro) * s], fill=metal)
    d.ellipse([(cx - ro + 4) * s, (cy - ro + 4) * s, (cx + ro - 4) * s, (cy + ro - 4) * s], fill=metal_hi)
    d.ellipse([(cx - ri - 2) * s, (cy - ri - 2) * s, (cx + ri + 2) * s, (cy + ri + 2) * s], fill=metal_lo)
    d.ellipse([(cx - ri) * s, (cy - ri) * s, (cx + ri) * s, (cy + ri) * s], fill=(0, 0, 0, 0))
    out = finish(img, w, h)
    # faction ornament at the bottom of the ring
    orn = load_corner(name).resize((44, 44), Image.LANCZOS)
    out.alpha_composite(orn, (int(cx - 22), int(cy + ro - 30)))
    return out


def load_corner(name):
    return Image.open(os.path.join(ROOT, name, "corner.tga")).convert("RGBA")


CLOCK_METAL = {
    "Human": ((196, 152, 62, 255), (255, 226, 140, 255), (80, 56, 18, 255)),
    "Orc": ((96, 88, 82, 255), (160, 150, 140, 255), (30, 26, 24, 255)),
    "Undead": ((150, 140, 124, 255), (214, 206, 186, 255), (40, 32, 48, 255)),
    "NightElf": ((84, 64, 46, 255), (140, 112, 84, 255), (22, 16, 12, 255)),
}


FACTIONS = {
    "Human": dict(
        panel=panel_human, edge=edge_human, corner=corner_human, crest=crest_human,
        well=((140, 104, 40, 255), (240, 204, 120, 255), (70, 48, 16, 255), (10, 16, 34, 255), (90, 140, 255, 120)),
    ),
    "Orc": dict(
        panel=panel_orc, edge=edge_orc, corner=corner_orc, crest=crest_orc,
        well=((70, 62, 58, 255), (160, 150, 140, 255), (24, 20, 18, 255), (30, 10, 6, 255), (220, 60, 30, 110)),
    ),
    "Undead": dict(
        panel=panel_undead, edge=edge_undead, corner=corner_undead, crest=crest_undead,
        well=((120, 110, 100, 255), (214, 206, 186, 255), (30, 24, 36, 255), (12, 8, 20, 255), (80, 240, 160, 110)),
    ),
    "NightElf": dict(
        panel=panel_nightelf, edge=edge_nightelf, corner=corner_nightelf, crest=crest_nightelf,
        well=((70, 54, 40, 255), (140, 112, 84, 255), (20, 14, 10, 255), (8, 16, 24, 255), (120, 230, 210, 110)),
    ),
}


def main():
    for name, spec in FACTIONS.items():
        save(spec["panel"](), name, "panel.tga")
        e = spec["edge"]()
        save(e, name, "edge.tga")
        save(e.rotate(90, expand=True), name, "edgev.tga")
        save(spec["corner"](), name, "corner.tga")
        save(well(*spec["well"]), name, "well.tga")
        save(spec["crest"](), name, "crest.tga")
        save(clockframe(name, *CLOCK_METAL[name]), name, "clockframe.tga")
    save(bevel(), "Common", "bevel.tga")
    save(dial(), "Common", "dial.tga")
    print("textures written to", os.path.normpath(ROOT), file=sys.stderr)


if __name__ == "__main__":
    main()
