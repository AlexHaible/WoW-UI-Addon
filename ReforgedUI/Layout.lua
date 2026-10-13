-- Pure layout math, ported from the original addon's Align* functions.
-- No WoW API calls in this file so it can also run under plain
-- Lua (tools/dump_layout.lua uses it to render preview mockups).
--
-- The console is laid out in "console units": a screen 768 units tall, the
-- size the original addon was designed for, with the origin at the bottom-left corner.
-- `s` is the original addon's "UI scale" option (240-270), the height of the minimap and
-- portrait blocks; nearly every size and offset is a fraction of it, and the
-- odd pixel corrections per theme and per scale are the original addon's own.
--
-- The original addon anchors most pieces to each other; here every piece gets absolute
-- coordinates instead. The console is always laid out like the original addon's "Center
-- UI" option: the chat area takes the original addon's default width (or what is left of
-- a narrow screen) and the whole console is centred by building it twice.

local _, ns = ...
ns = ns or {}

local floor, max, min = math.floor, math.max, math.min

local Layout = {}
ns.Layout = Layout

local function rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end
Layout.rect = rect

local function right(r) return r.x + r.w end
local function top(r) return r.y + r.h end

----------------------------------------------------------------------------
-- Top bar (Reforged UI): the core aspect decides where the menu buttons and
-- the default data feeds go on wide screens.

Layout.PROFILES = {
	standard = { label = "16:9", coreAspect = 16 / 9 },
	wide = { label = "21:9", coreAspect = 21 / 9 },
	superwide = { label = "32:9", coreAspect = 21 / 9 },
}
Layout.PROFILE_ORDER = { "standard", "wide", "superwide" }

local TOP = {
	topH = 40, slotW = 120, slotGap = 8,
	dialR = 52, clockW = 176, clockH = 88,
	-- Width of the clock frame's art where it crosses the bar (the rest of
	-- the frame's width is transparent there, for every theme).
	clockArtW = 118,
	-- Blizzard's micro buttons either side of the clock: their height on the
	-- bar (shrunk down to microMinH on narrow screens), the gap between
	-- them and the gap to the clock's art.
	microH = 26, microMinH = 16, microGap = 1, microClockGap = 3,
}
Layout.TOP_SIZES = TOP

function Layout.DetectProfile(w, h)
	local aspect = w / h
	if aspect < 2.0 then
		return "standard"
	elseif aspect < 2.75 then
		return "wide"
	end
	return "superwide"
end

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
Layout.Overlaps = overlaps

-- The top bar in its own units (W x H, origin bottom-left). `micro` lists
-- the width/height ratio of each of Blizzard's micro buttons to place beside
-- the clock, in order: the first half go on the left, the rest on the right.
-- How far the inner edge of each top bar trim (Media/<folder>/edge.tga) is
-- see-through, in units: the bar's open band reaches that far into the trim.
local TRIM_OPEN = {
	Undead = 3.5, NightElf = 3, HighOrder = 3, Windshapers = 3,
	Orc = 2.5, Tauren = 2.5, Troll = 2.5, Forsaken = 0.5,
}

function Layout.ComputeTopBar(W, H, profile, micro, folder)
	if not Layout.PROFILES[profile] then
		profile = Layout.DetectProfile(W, H)
	end
	micro = micro or {}
	local P = Layout.PROFILES[profile]
	local T = { W = W, H = H, profile = profile }
	local coreW = min(W, floor(H * P.coreAspect + 0.5))
	local coreX = floor((W - coreW) / 2)
	T.coreX, T.coreW = coreX, coreW
	T.topBar = rect(0, H - TOP.topH, W, TOP.topH)
	local cx = floor(W / 2)
	-- The clock frame hangs from the top edge of the screen over the bar;
	-- the dial turns behind its window, centred just under the screen edge.
	local cy = H - 4
	T.clock = { cx = cx, cy = cy, radius = TOP.dialR }
	T.clockFrame = rect(cx - TOP.clockW / 2, H - TOP.clockH, TOP.clockW, TOP.clockH)
	T.clockArt = rect(cx - TOP.clockArtW / 2, H - TOP.topH, TOP.clockArtW, TOP.topH)
	-- Slots sit centred in the bar's open band, between the top of the
	-- screen and its trim (the bottom 16 units, less any see-through edge).
	local plateH = TOP.topH - 22
	local bandBottom = H - TOP.topH + 16 - (TRIM_OPEN[folder] or 0)
	local plateY = bandBottom + (H - bandBottom - plateH) / 2

	-- Micro buttons flank the clock's art, half on each side, centred on
	-- the slots. Both halves take the width of the wider one, the narrower
	-- centred in it, so the row is mirrored about the clock even when the
	-- halves differ by a button. Where the core's left edge (left) or the
	-- screen edge (right) leave too little room they shrink, down to
	-- microMinH.
	local n = #micro
	local nL = math.ceil(n / 2)
	local artL, artR = T.clockArt.x - TOP.microClockGap, right(T.clockArt) + TOP.microClockGap
	local function ratios(i0, i1)
		local sum = 0
		for i = i0, i1 do
			sum = sum + micro[i]
		end
		return sum, max(0, i1 - i0) * TOP.microGap
	end
	local sumL, gapsL = ratios(1, nL)
	local sumR, gapsR = ratios(nL + 1, n)
	local sum, gaps = max(sumL, sumR), max(gapsL, gapsR)
	local h = TOP.microH
	if sum > 0 then
		h = min(h, (artL - (coreX + 16 + TOP.slotGap) - gaps) / sum, (W - 8 - artR - gaps) / sum)
	end
	h = max(TOP.microMinH, h)
	local span = sum * h + gaps
	local my = plateY + plateH / 2 - h / 2
	T.micro = {}
	local mx = artL - span + (span - (sumL * h + gapsL)) / 2
	for i = 1, n do
		if i == nL + 1 then
			mx = artR + (span - (sumR * h + gapsR)) / 2
		end
		local w = micro[i] * h
		T.micro[i] = rect(mx, my, w, h)
		mx = mx + w + TOP.microGap
	end
	local microL, microR = artL, artR
	if n > 0 then
		microL, microR = artL - span, artR + span
	end
	T.microSpan = rect(microL, my, microR - microL, h)

	local clockL, clockR = T.clockFrame.x - 6, T.clockFrame.x + T.clockFrame.w + 6
	local innerL, innerR = clockL, clockR
	if n > 0 then
		innerL, innerR = microL - TOP.slotGap, microR + TOP.slotGap
	end

	-- Data feed slots, the same distance either side of the centre: clear
	-- of the wider of the micro button halves (or the clock), then outwards
	-- to the screen edges. The right side is numbered first, from the
	-- centre out (where Warcraft III shows its resources), then the left.
	local slots, step = {}, TOP.slotW + TOP.slotGap
	-- Both sides land on the same place in the bar's pattern, which repeats
	-- every slot plus gap (128 units) from the first right-hand slot.
	local d = max(cx - innerL, innerR - cx)
	local half, base = step / 2, TOP.slotGap / 2
	d = base + half * math.ceil((d - base) / half)
	T.topBar.originX = cx + d
	local sx = cx + d
	while sx + TOP.slotW <= W - 8 do
		slots[#slots + 1] = rect(sx, plateY, TOP.slotW, plateH)
		sx = sx + step
	end
	sx = cx - d - TOP.slotW
	while sx >= 8 do
		slots[#slots + 1] = rect(sx, plateY, TOP.slotW, plateH)
		sx = sx - step
	end
	T.topSlots = slots
	return T
end

----------------------------------------------------------------------------
-- Console

Layout.THEMES = { "human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll", "highorder", "windshapers", "forsaken" }
-- The race themes are the original faction art recoloured (tools/make_race_themes.py),
-- so their pieces have that faction's windows and take its layout corrections.
-- A theme with its own outline (wall tops, draw layers, hero wall) adds its own
-- entries to LEFT_WALL, RIGHT_WALL, HERO_WALL and LAYERS: those are looked up by
-- theme first, then by base faction.
Layout.BASE = {
	dwarf = "human", gnome = "human", tauren = "orc", troll = "orc", highorder = "nightelf", windshapers = "nightelf",
	forsaken = "undead",
}
Layout.SCALE_MIN, Layout.SCALE_MAX = 240, 270
-- Draw layers that the original addon's ChangeTheme gives the overlapping pieces.
local LAYERS = {
	human = {
		ext1 = { "OVERLAY", 0 }, ext2 = { "ARTWORK", 0 }, ext3 = { "BORDER", 0 }, right_left = { "BACKGROUND", 0 },
		lid = { "ARTWORK", 5 }, br_top = { "BORDER", 4 }, filler_top1 = { "BORDER", 0 },
	},
	orc = {
		ext1 = { "ARTWORK", 0 }, ext2 = { "OVERLAY", 0 }, ext3 = { "BORDER", 0 }, right_left = { "ARTWORK", 0 },
		lid = { "BORDER", 4 }, br_top = { "OVERLAY", 5 }, filler_top1 = { "BORDER", 0 },
	},
	undead = {
		ext1 = { "OVERLAY", 0 }, ext2 = { "ARTWORK", 0 }, ext3 = { "BORDER", 0 }, right_left = { "ARTWORK", 0 },
		lid = { "BORDER", 4 }, br_top = { "ARTWORK", 5 }, filler_top1 = { "OVERLAY", 0 },
	},
	nightelf = {
		ext1 = { "OVERLAY", 0 }, ext2 = { "ARTWORK", 0 }, ext3 = { "OVERLAY", 0 }, right_left = { "ARTWORK", 0 },
		lid = { "BORDER", 4 }, br_top = { "ARTWORK", 4 }, filler_top1 = { "OVERLAY", 0 },
	},
}

-- Columns and rows of the original addon's 2x3 inventory, in its slot order (slot 1 is
-- the bottom-left one).
local INVENTORY_CELLS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { 1, 2 }, { 0, 2 } }
-- Inventory slot for each bag, reading like a page: backpack top-left, then
-- bags 1-4, the reagent bag bottom-right.
local BAG_CELLS = { 6, 5, 4, 3, 1, 2 }

-- How far across each filler texture its art reaches (the rest is
-- transparent), and where the art of the BottomRight_Top corner starts.
local FILLER_ART = {
	human = { top = 162 / 256, bottom = 157 / 256, cornerTop = 0 },
	orc = { top = 162 / 256, bottom = 157 / 256, cornerTop = 0 },
	undead = { top = 160 / 256, bottom = 141 / 256, cornerTop = 0 },
	nightelf = { top = 214 / 256, bottom = 144 / 256, cornerTop = 76 / 512 },
}
Layout.FILLER_ART = FILLER_ART

----------------------------------------------------------------------------
-- End caps: the console is always centred, so both of its ends stand in
-- mid-screen; a pillar closes each end. Sizes are in units of the UI scale
-- `s`: `w` and `h` the cap's natural size, `overlap` how far it reaches over
-- the console's edge (the minimap block's left edge, the chat area's right
-- edge), `head` the share of its height at the top (the crown) that keeps its
-- proportions when the cap is stretched or squeezed to the wall's height,
-- `inset` (optional) the share of its width on either side that only the
-- crown reaches (the shaft below is that much narrower).
-- With `rise` the cap's top is fitted to `rise` above that end's wall top
-- (0: flush with it, so each cap ends its own wall);
-- without it the cap keeps its natural height (taller where the chat area
-- is raised above it). Files are under art/<theme>/.
--
-- Themes with real end cap art are listed in ENDCAP_ART; every other theme
-- uses the stand-in caps tools/make_endcaps.py builds from its own art
-- (ENDCAP_GEN), and a theme without those (Dwarf, whose hand-built art does
-- not go through that tool) borrows its base faction's.
Layout.ENDCAP_ART = {
	-- Warcraft III's own end pillars (humanuitile05/06), crown on the wall top.
	human = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0742, h = 0.6406, overlap = 0.002, head = 0.125, rise = 0 },
	-- Hand-built Gnomeregan ends on Human's shapes.
	gnome = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0742, h = 0.6406, overlap = 0.002, head = 0.125, rise = 0 },
	-- Each faction's own end pieces (tile05's left end, tile06's right end).
	orc = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0547, h = 0.75, overlap = 0.002, head = 0.125, rise = 0 },
	-- Hand-built Troll and Tauren ends on Orc's shapes.
	tauren = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0547, h = 0.75, overlap = 0.002, head = 0.125, rise = 0 },
	troll = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0547, h = 0.75, overlap = 0.002, head = 0.125, rise = 0 },
	undead = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0977, h = 0.9375, overlap = 0.002, head = 0.125, rise = 0 },
	nightelf = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.1895, h = 0.8594, overlap = 0.002, head = 0.125, rise = 0 },
	-- Skyborne: Night Elf's pieces re-graded, so Night Elf's cap spec.
	highorder = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.1895, h = 0.8594, overlap = 0.002, head = 0.125, rise = 0 },
	windshapers = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.1895, h = 0.8594, overlap = 0.002, head = 0.125, rise = 0 },
	forsaken = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.168, h = 0.8594, overlap = 0.002, head = 0.125, rise = 0 },
	-- Hand-built "Great Forge" versions of the same pillars.
	dwarf = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right",
		w = 0.0742, h = 0.6406, overlap = 0.002, head = 0.125, rise = 0 },
}
Layout.ENDCAP_GEN = {
	left = "endcaps\\endcap_left_gen", right = "endcaps\\endcap_right_gen",
	w = 0.26, h = 0.8125, overlap = 0.065, head = 0.25, inset = 0.2, rise = 0,
}
-- Themes tools/make_endcaps.py builds stand-in caps for.
Layout.ENDCAP_GEN_THEMES = {
	human = true, orc = true, undead = true, nightelf = true, dwarf = true, gnome = true, tauren = true, troll = true,
	highorder = true, windshapers = true, forsaken = true,
}
-- The chat area gives up width so the caps fit beside it, down to this
-- (times s); below that the caps go past the screen edges instead.
Layout.ENDCAP_CHAT_MIN = 1.6

-- The cap spec for a theme, with `folder` the art folder its files are in
-- and `fallback` set when it is borrowed from the base faction.
function Layout.EndcapArt(theme)
	local real = Layout.ENDCAP_ART[theme]
	local spec, folder, fallback = real, theme, false
	if not real then
		spec = Layout.ENDCAP_GEN
		if not Layout.ENDCAP_GEN_THEMES[theme] then
			folder, fallback = Layout.BASE[theme] or "human", true
			if Layout.ENDCAP_ART[folder] then
				spec = Layout.ENDCAP_ART[folder]
			end
		end
	end
	local out = { folder = folder, fallback = fallback, real = real ~= nil }
	for k, v in pairs(spec) do
		out[k] = v
	end
	return out
end

-- Where each end's wall tops out: the minimap block's battlement (share of
-- s) and the BottomRight_Top piece's (share of its height from its top).
-- (Human's minimap art has a faint stray column above its wall; 0.639 is the
-- wall itself.)
-- These are the tops of the end pieces the caps continue: Orc's beam ends
-- below the fur tufts and palisade spikes, and Undead's minimap art has the
-- same stray column as Human's.
-- Keyed by faction, or by theme where a theme's art has its own ends.
local LEFT_WALL = {
	human = 0.639, orc = 0.6113, undead = 0.6816, nightelf = 0.693, forsaken = 0.709,
	troll = 0.627, tauren = 0.6797, gnome = 0.6758,
}
local RIGHT_WALL = {
	human = 73 / 128, orc = 81 / 128, undead = 52 / 128, nightelf = 48 / 128, forsaken = 57 / 128,
	troll = 96 / 128, tauren = 69 / 128,
}

----------------------------------------------------------------------------
-- Target display (Target.lua).

-- The target's wall plate: a miniature hero screen in one texture per theme,
-- a portrait arch with two bar slots on the left and an info window on the
-- right. Windows are pixel rects { x, y, w, h } of the texture, from its
-- top-left corner, so new art only needs its file and its rects here.
--
--  * themes: plates from the art pipeline, art/<theme>/targetplate.tga, with
--    their windows (portrait, health, power, info; optionally cast and combo
--    inside the info window, else they are laid out in it).
--  * Every other theme uses targetplate_gen.tga, composed from its own hero
--    screen art by tools/make_target_plate.py; the windows are those of its
--    faction's shapes (`gen`, printed by make_target_plate.py --windows).
--  * fallback: hand-built themes without a plate yet use another theme's.
Layout.TARGET_ART = {
	size = { 512, 256 },
	width = 0.85, -- in console scale units (s): ~204 units at s = 240
	file = "targetplate",
	genFile = "targetplate_gen",
	themes = {
		human = { portrait = { 46, 66, 123, 133 }, health = { 46, 203, 123, 20 }, power = { 46, 227, 123, 21 },
			info = { 187, 50, 293, 198 } },
		gnome = { portrait = { 46, 66, 123, 133 }, health = { 46, 203, 123, 20 }, power = { 46, 227, 123, 21 },
			info = { 187, 50, 293, 198 } },
		orc = { portrait = { 76, 89, 112, 120 }, health = { 76, 211, 112, 19 }, power = { 76, 233, 112, 17 },
			info = { 214, 76, 249, 173 } },
		troll = { portrait = { 76, 89, 112, 120 }, health = { 76, 211, 112, 19 }, power = { 76, 233, 112, 17 },
			info = { 214, 76, 249, 173 } },
		tauren = { portrait = { 76, 89, 112, 120 }, health = { 76, 211, 112, 19 }, power = { 76, 233, 112, 17 },
			info = { 214, 76, 249, 173 } },
		undead = { portrait = { 52, 67, 125, 131 }, health = { 57, 204, 116, 20 }, power = { 58, 226, 115, 23 },
			info = { 195, 56, 284, 193 } },
		nightelf = { portrait = { 39, 57, 121, 143 }, health = { 40, 205, 121, 20 }, power = { 41, 231, 120, 17 },
			info = { 187, 54, 281, 194 } },
		highorder = { portrait = { 39, 57, 121, 143 }, health = { 40, 205, 121, 20 }, power = { 41, 231, 120, 17 },
			info = { 187, 54, 281, 194 } },
		windshapers = { portrait = { 39, 57, 121, 143 }, health = { 40, 205, 121, 20 }, power = { 41, 231, 120, 17 },
			info = { 187, 54, 281, 194 } },
		forsaken = { portrait = { 87, 85, 104, 121 }, health = { 87, 207, 101, 21 }, power = { 87, 234, 104, 14 },
			info = { 218, 75, 212, 173 } },
		dwarf = { portrait = { 46, 66, 123, 133 }, health = { 46, 203, 123, 20 }, power = { 46, 227, 123, 21 },
			info = { 187, 50, 293, 198 } },
	},
	gen = {
		human = { portrait = { 44, 50, 120, 138 }, health = { 44, 193, 120, 22 }, power = { 44, 217, 120, 23 },
			info = { 186, 35, 311, 209 } },
		orc = { portrait = { 53, 55, 121, 134 }, health = { 53, 193, 121, 20 }, power = { 53, 217, 121, 18 },
			info = { 204, 33, 286, 212 } },
		undead = { portrait = { 53, 68, 108, 122 }, health = { 53, 196, 108, 20 }, power = { 53, 218, 108, 21 },
			info = { 189, 51, 302, 196 } },
		nightelf = { portrait = { 54, 64, 115, 126 }, health = { 54, 195, 115, 20 }, power = { 54, 220, 115, 18 },
			info = { 197, 52, 291, 191 } },
	},
	fallback = {},
}

-- Theme folder, file and windows of `art`'s plate.
function Layout.TargetPlateArt(art)
	local A = Layout.TARGET_ART
	local real = A.themes[art]
	if real then
		return art .. "\\" .. A.file, real
	end
	local from = A.fallback[art] or art
	return from .. "\\" .. A.genFile, A.gen[Layout.BASE[from] or from]
end

-- The original addon's experience bar: three caps around a bar, the name over it and the
-- level line on it. `s` sets its size (the hero's uses the console's scale;
-- the target plate's a smaller one).
local function levelPlate(x, y, s)
	local xs = 0.375
	local capW, capH = 0.05924 * s * xs, 0.2370 * s * xs
	local midW = 1.70 * s * xs
	local total = 2 * capW + midW
	return {
		left = rect(x, y, capW, capH),
		middle = rect(x + capW, y, midW, capH),
		right = rect(x + capW + midW, y, capW, capH),
		bar = rect(x, y, 0.6814 * s, 0.083 * s), -- at 100%
		hover = rect(x + capW, y, total, 0.08 * s),
		nameY = y + capH / 2 + 0.080 * s,
		levelY = y + capH / 2,
		cx = x + capW + midW / 2,
		width = total,
	}
end
Layout.LevelPlate = levelPlate
-- Width of a level plate per unit of its `s`.
local LEVEL_PLATE_W = 2 * 0.05924 * 0.375 + 1.70 * 0.375

-- Top of the portrait block's wall above the stats panel, per faction art.
local HERO_WALL = { human = 0.543, orc = 0.53, undead = 0.578, nightelf = 0.56, troll = 0.5176, tauren = 0.570 }

local function buildTarget(L, s, t, MT, xp)
	-- Swap mode (Warcraft III): the hero screen shows the target. Its name and
	-- level take the experience bar's place; its health and power bars,
	-- combo points and cast bar take the stat icons'.
	do
		local x0, w = xp.left.x + 1, xp.width - 2
		local hh, ph, pip = 0.055 * s, 0.042 * s, 0.04 * s
		local hy = xp.left.y - 0.02 * s - hh
		local py = hy - 0.012 * s - ph
		local gap = 0.03 * s
		local rowW = 5 * pip + 4 * gap
		L.targetSwap = {
			health = rect(x0, hy, w, hh),
			power = rect(x0, py, w, ph),
			combo = { x = x0 + (w - rowW) / 2, y = py - 0.02 * s - pip, size = pip, step = pip + gap },
			cast = rect(x0, 0.04 * s, w, 0.045 * s),
		}
	end

	local wall = (HERO_WALL[L.theme] or HERO_WALL[t] or 0.54) * s
	L.heroWallTop = wall

	-- Target of target: a small unit icon standing on the wall above the
	-- hero's portrait, its health bar underneath.
	do
		local size = 0.13 * s
		local cx = MT.x + 0.995 * s
		local x = cx - size / 2
		L.tot = {
			frame = rect(x - 3, wall - 3, size + 6, size + 12),
			icon = rect(x, wall + 6, size, size),
			health = rect(x, wall - 1, size, 5),
		}
	end

	-- Wall plate: a miniature hero screen standing on the wall above the stats
	-- panel, between the target of target and the stance row.
	do
		local A = Layout.TARGET_ART
		local file, win = Layout.TargetPlateArt(L.theme)
		local w = A.width * s
		local k = w / A.size[1]
		local h = A.size[2] * k
		local left, stop = right(L.tot.frame), L.stance.x
		local x0, y0 = left + max(2, (stop - left - w) / 2), wall - 3
		local function px(r)
			return rect(x0 + r[1] * k, y0 + (A.size[2] - r[2] - r[4]) * k, r[3] * k, r[4] * k)
		end
		local P = {
			file = file,
			frame = rect(x0, y0, w, h),
			portrait = px(win.portrait),
			health = px(win.health),
			power = px(win.power),
			info = px(win.info),
			top = y0 + h,
		}
		P.portraitBg = P.portrait
		-- Inside the info window: name and level line on a small level
		-- plate, then the combo points and the cast bar where the hero's stat
		-- icons are.
		local I, pad = P.info, 0.025 * s
		local ls = (I.w - 2 * pad) / LEVEL_PLATE_W
		local nameH = 0.065 * s
		local nameC = top(I) - pad - nameH / 2
		-- The level line a little lower than the hero's, for the name's
		-- larger share of the small plate.
		local capH = levelPlate(0, 0, ls).left.h
		local lv = levelPlate(I.x + pad, nameC - 0.075 * s - capH / 2, ls)
		lv.nameY = nameC
		P.level = lv
		P.name = rect(I.x + pad, nameC - nameH / 2, I.w - 2 * pad, nameH)
		local castH = 0.045 * s
		P.cast = win.cast and px(win.cast) or rect(I.x + pad, I.y + 0.035 * s, I.w - 2 * pad, castH)
		local pip = 0.03 * s
		local step = pip + 0.03 * s
		local rowW = 4 * step + pip
		local comboY = (lv.left.y + P.cast.y + P.cast.h) / 2 - pip / 2
		P.combo = win.combo and { x = px(win.combo).x, y = px(win.combo).y, size = pip, step = step }
			or { x = I.x + (I.w - rowW) / 2, y = comboY, size = pip, step = step }
		L.targetPlate = P
	end

	-- The target's buffs and debuffs: rows of small icons standing on the
	-- wall between the target of target and the stance row (above the plate
	-- in plate mode), debuffs nearest the wall.
	do
		local size, gap = 0.085 * s, 0.01 * s
		local x0, x1 = right(L.tot.frame) + 4, L.stance.x - 4
		L.targetAuras = {
			size = size, gap = gap,
			swap = { x0 = x0, x1 = x1, y = wall + 6 }, -- level with the target of target
			plate = { x0 = x0, x1 = x1, y = L.targetPlate.top + 4 },
		}
	end
end

local function buildRight(L, o, W, g, add, themed, themedLayer, chatW)
	local s, m, t = o.s, o.m, Layout.BASE[o.theme] or o.theme
	local d1 = ({ human = 2, orc = 1, undead = 1 })[t] or 0
	local d2 = ({ human = 2, orc = 1 })[t] or 0
	local RM = rect(right(g[4]) - 0.2479 * s - d1, 0, s + 0.01851 * s, s)
	local RL = rect(RM.x + 0.35 * s - d2 - s / 2, 0, s / 2, s)
	L.inventoryArt, L.noInventoryArt = RM, RL
	local rlLayer, rlSub = themedLayer("right_left")
	add("right_left", "left", themed("inventory\\no_inventory"), rlLayer, rlSub, RL)
	add("right_middle", "right", themed("inventory\\inventory"), "OVERLAY", 0, RM)

	local brTop = rect(W - 0.7259 * s, 0.5208 * s + m, s, s / 4)
	local extraHeight = (t == "human" or t == "undead") and 0.022222 * s or 0
	local brMid = rect(W - 0.0625 * s, 0, s / 16,
		0.5 * s + m + extraHeight + (t == "human" and 0 or 0.0208333 * s))
	local brMidTc
	local brBot = rect(W - 0.7259 * s, 0, s, s / 8)
	local shiftWidth = t == "undead" and 0.0185185 * s or 0
	local lid = rect(RM.x + 0.2833333333 * s - shiftWidth, -0.3166 * s + m, s, s)
	local lidTc
	local bg = rect(right(RL) + 3, 0, 0, 0.5578 * s + m)
	-- The original addon's default width, or up to the screen edge where that is less
	-- (Compute narrows it further to make room for the end caps).
	bg.w = chatW or max(0, min(2.2 * s, W - bg.x))

	local aeh = 0
	if s >= 250 and s <= 259 then aeh = -3 elseif s > 259 then aeh = -6 end
	local RMr = right(RM)
	local fT, fB, tcT = {}, {}, {}
	fT[1] = rect(RMr - 0.09 * s + aeh, 0.5206 * s + m, s / 2, s / 4)
	fB[1] = rect(RMr - 0.03703 * s, 0, s / 2, s / 16)
	fT[2] = rect(fB[1].x + 0.2291 * s + aeh, 0.5206 * s + m, s / 2, s / 4)
	fB[2] = rect(fB[1].x + 0.2768 * s, 0, s / 2, s / 16)
	fT[3] = rect(fB[2].x + 0.2291 * s + aeh, 0.5206 * s + m, s / 2, s / 4)
	fB[3] = rect(fB[2].x + 0.2768 * s, 0, s / 2, s / 16)
	local showT = { not (s >= 269 and (t == "human" or t == "undead")), s < 258, s <= 245 }
	local showB = { true, s < 258, s <= 245 }

	if t == "undead" then
		local offset, offset2 = 15, 0
		local shiftExtra = 270 - s
		showT = { false, false, false }
		local a1, a2 = 0, 0
		local OFFSETS = { [270] = 0, [269] = 17, [268] = 23, [267] = 27, [266] = 33, [265] = 40, [264] = 45,
			[263] = 51, [262] = 59, [261] = 68, [260] = 77 }
		if OFFSETS[s] then
			offset = OFFSETS[s]
			if s <= 267 then
				offset2 = s * 0.014981 - 2
			end
		elseif s >= 257 then
			showT[1] = true
			shiftExtra = 261 - s
			a1 = 25
			fT[1].w = s / 2
		elseif s <= 256 then
			showT[1] = true
			shiftExtra = 258 - s
			offset = 25
			offset2 = s * 0.014981 - 2
			a1 = 40
			fT[1].w = s / 2 - (10 - (shiftExtra * 2 + 5))
			if s == 253 then
				offset = 28
			elseif s >= 250 and s <= 252 then
				offset = 40
				fT[1].w = s / 2 + 35
			elseif s <= 249 then
				offset, a1 = 53, 53
				if s == 249 then
					fT[1].w = s / 2 + 35
				elseif s >= 247 and s <= 248 then
					fT[1].w = s / 2 + 45
				elseif s == 246 then
					offset, a1 = 65, 60
					fT[1].w = s / 2 + 45
				elseif s == 245 then
					offset, a1 = 65, 61
					fT[1].w = s / 2 + 52
				else
					showT[2] = true
					shiftExtra, offset = 0, 0
					a1, a2 = 20, 87
					fT[1].w = s / 2
					fT[2].w = s / 2 + 25
					if s >= 242 and s <= 243 then
						fT[2].w = s / 2 + 38
					elseif s <= 241 then
						a1, a2 = 23, 102
						fT[1].w = s / 2 + 25
						fT[2].w = s / 2 + 35
					end
				end
			end
		end
		fT[1].x, fT[1].y = RMr - 0.09 * s + a1, 0.5206 * s + m + 1
		fT[2].x, fT[2].y = RMr - 0.09 * s + a2, 0.5206 * s + m + 1
		lid.w = s + offset
		lid.x = RM.x + 0.2833333333 * s - shiftWidth - shiftExtra
		brTop.w = s + offset2
		brTop.x = W - 0.7259 * s - offset2
	elseif t == "nightelf" then
		if s >= 267 then
			lid.w = 0.7890625 * s + (s == 267 and 3 or 0)
			lidTc = { 0, 0.7890625, 0, 1 }
		end
		brTop = rect(W - 0.7259 * s - 0.17037037 * s, 0.5208 * s + m, s + 0.088888 * s, s / 4 + 0.088888 * s / 4)
		local makeSmaller = 0
		if s > 252 and s <= 260 then
			makeSmaller = 1
		elseif s > 250 and s <= 252 then
			makeSmaller = 2
		elseif s == 250 then
			makeSmaller = 3
		elseif s <= 249 then
			makeSmaller = 4
		end
		brMid.w = 270 / 8 + 0.088888 * s / 8 - makeSmaller
		brMid.h = 0.5 * s + m + 0.022222 * s + 1
		local cut = 0
		if m > 90 and m < 100 then
			cut = 0.05
		elseif m > 70 and m <= 90 then
			cut = 0.1
		elseif m > 40 and m <= 70 then
			cut = 0.25
		elseif m > 30 and m <= 40 then
			cut = 0.38
		elseif m >= 0 and m <= 30 then
			cut = 0.475
		end
		brMidTc = { 0, 1, 0.04296875 + cut, 1 }
		brMid.x = W - 37 + makeSmaller
		lid.x, lid.y = RM.x + 0.2833333333 * s - 6, -0.3166 * s + m + 6
		showT = { false, false, false }
		if s <= 260 then
			showT[1] = true
			local a = 35
			if s >= 250 then
				a = 50
			elseif s >= 247 and s <= 249 then
				a = 60
			else
				showT[2] = true
				fT[2].x, fT[2].y = fB[1].x + 0.2291 * s + 5, 0.5206 * s + m
				tcT[2] = { 1, 0, 0, 1 }
			end
			fT[1].x, fT[1].y = RMr - 0.09 * s + a, 0.5206 * s + m
		end
	end

	-- "Center UI": the bottom-right pieces follow the chat area instead of
	-- the screen edge.
	do
		local bgR, bgT = right(bg), top(bg)
		if t == "nightelf" then
			brTop.x = bgR - 0.9 * s
		elseif t == "undead" then
			brTop.x = bgR - 0.734615 * s
		else
			brTop.x = bgR - 0.725833 * s
		end
		brTop.y = bgT - 0.03846153 * s
		brBot.x = bgR - 0.725833 * s
		-- Night Elf's middle piece keeps its offset from the edge (it is
		-- narrowed at lower scales), so it reaches the chat area's edge and
		-- tucks half a unit under the end cap: no black strip between them.
		brMid.x = t == "nightelf" and (bgR + brMid.x - W + 0.5) or (bgR - 0.0625 * s)
	end

	-- The original addon's frame pieces only reach across a 16:9 screen; on wider screens
	-- (or a wider chat area) repeat the filler pieces until they meet the
	-- bottom-right corner.
	-- Coverage is measured to where each texture's art ends (the filler
	-- textures are partly transparent on the right), and each new piece
	-- overlaps the last, so the wall has no notch where the pieces meet.
	do
		local fill = FILLER_ART[t]
		local function artEnd(r, vis, tc)
			if tc and tc[1] > tc[2] then
				return right(r) -- mirrored: the art reaches the right edge
			end
			return r.x + r.w * vis
		end
		-- The original addon's own pieces can fall a unit short of each other (Undead's
		-- floor): close those joints too.
		for i = 2, 3 do
			if showT[i] and showT[i - 1] and not tcT[i] and not tcT[i - 1] then
				fT[i].x = min(fT[i].x, artEnd(fT[i - 1], fill.top) - 1)
			end
			if showB[i] and showB[i - 1] then
				fB[i].x = min(fB[i].x, artEnd(fB[i - 1], fill.bottom) - 1)
			end
		end
		local topCover = right(lid) - 0.6 * s
		for i = 1, 3 do
			if showT[i] then topCover = max(topCover, artEnd(fT[i], fill.top, tcT[i])) end
		end
		local topStart = brTop.x + brTop.w * fill.cornerTop
		local n = 3
		while topCover < topStart + 2 do
			n = n + 1
			fT[n] = rect(topCover - 0.085 * s, 0.5206 * s + m, s / 2, s / 4)
			showT[n] = true
			topCover = artEnd(fT[n], fill.top)
		end
		local botCover = RMr
		for i = 1, 3 do
			if showB[i] then botCover = max(botCover, artEnd(fB[i], fill.bottom)) end
		end
		n = 3
		while botCover < brBot.x + 2 do
			n = n + 1
			fB[n] = rect(botCover - 0.03 * s, 0, s / 2, s / 16)
			showB[n] = true
			botCover = artEnd(fB[n], fill.bottom)
		end
	end

	add("chat_bg", "right", "other\\black_background", "BACKGROUND", 0, bg)
	local lidLayer, lidSub = themedLayer("lid")
	add("lid", "right", themed("bottom right\\right_part_lid"), lidLayer, lidSub, lid, lidTc)
	local topLayer, topSub = themedLayer("br_top")
	add("br_top", "right", themed("bottom right\\BottomRight_Top"), topLayer, topSub, brTop)
	add("br_middle", "right", themed("bottom right\\BottomRight_Middle"), "BORDER", 0, brMid, brMidTc)
	add("br_bottom", "right", themed("bottom right\\BottomRight_Bottom"), "BORDER", 0, brBot)
	for i = 1, max(#fT, #fB) do
		if fT[i] then
			local layer, sub = "ARTWORK", 0
			if i == 1 then
				layer, sub = themedLayer("filler_top1")
			end
			local p = add("filler_top" .. i, "right", themed("bottom right\\BottomRightFillerTop"), layer, sub, fT[i], tcT[i])
			p.shown = showT[i] and true or false
		end
		if fB[i] then
			local p = add("filler_bottom" .. i, "right", themed("bottom right\\BottomRightFillerBottom"),
				i == 1 and "BORDER" or "ARTWORK", 0, fB[i])
			p.shown = showB[i] and true or false
		end
	end

	-- The 2x3 inventory: slot 1 bottom-left, then right, and up.
	local slotX, slotY = RM.x + 0.02 * s + 0.5, 0.016 * s + 0.5
	L.inventory = {}
	for n, cell in ipairs(INVENTORY_CELLS) do
		local col, rowN = cell[1], cell[2]
		local sz = 0.1185185 * s
		L.inventory[n] = rect(slotX + col * 0.156 * s - (1 - col), slotY + rowN * 0.148 * s, sz, sz)
	end

	L.rightPoint = right(bg)
	L.chatBgX = bg.x
	L.rightWallTop = brTop.y + brTop.h * (1 - (RIGHT_WALL[o.theme] or RIGHT_WALL[t]))

	-- Chat window: inside the black area, clear of the frame pieces, down to
	-- the floor trim (the bottom pieces' art is about 0.03s tall) and up to
	-- just under the wall (its art reaches the bottom of the top piece).
	do
		local x0 = right(RL) + 0.08 * s
		local x1 = min(right(bg), brMid.x) - 6
		local y0 = brBot.y + 0.03 * s + 1
		local y1 = brTop.y - 2
		local edit = 26
		-- The options cogwheel stands in the bottom-right corner of the chat
		-- area; an input box along the bottom stops short of it.
		local cog = 22
		L.cogwheel = rect(x1 + 4 - cog, y0 + 1, cog, cog)
		if o.chatInputAbove then
			L.chat = rect(x0, y0, x1 - x0, y1 - y0 - edit)
			L.chatEdit = rect(x0 - 4, y1 - edit + 2, x1 - x0 + 8, edit - 2)
		else
			L.chat = rect(x0, y0 + edit, x1 - x0, y1 - y0 - edit)
			L.chatEdit = rect(x0 - 4, y0, x1 - x0 + 8 - cog - 4, edit - 2)
		end
	end
	-- Bags in the 2x3 inventory, the key ring standing to its left.
	do
		L.bagSlots = {}
		for bag, cell in ipairs(BAG_CELLS) do
			L.bagSlots[bag] = L.inventory[cell]
		end
		local first, mid = L.inventory[1], L.inventory[4]
		local kw, kh = 0.07 * s, 0.16 * s
		L.keyRing = rect(first.x - kw - 0.012 * s, mid.y + mid.h / 2 - kh / 2, kw, kh)
	end

	-- Everything we put on the screen stays below this height (bag windows
	-- and the issue reporter are lifted above it).
	L.consoleTop = max(top(brTop), L.stanceTop) + 4
end

-- The end caps: a pillar at each end of the console, its crown (`head`)
-- kept in proportion and its shaft fitted to the height.
local function buildCaps(L, W, add)
	local s, t = L.s, L.base
	local C = Layout.EndcapArt(L.theme)
	local w, ov = C.w * s, C.overlap * s
	local headH = C.head * C.h * s
	local function capTop(wall)
		if C.rise then
			return wall + C.rise * s
		end
		return max(C.h * s, wall + 0.02 * s)
	end
	local leftX = L.minimapArt.x + ov - w
	local rightX = L.rightPoint - ov
	L.endcaps = {
		fallback = C.fallback, real = C.real, overlap = ov,
		left = rect(leftX, 0, w, capTop((LEFT_WALL[L.theme] or LEFT_WALL[t]) * s)),
		right = rect(rightX, 0, w, capTop(L.rightWallTop)),
	}
	-- The shafts (below the crowns), which must stay clear of the content.
	local inset = (C.inset or 0) * w
	for _, side in ipairs({ "left", "right" }) do
		local r = L.endcaps[side]
		L.endcaps[side .. "Shaft"] = rect(r.x + inset, 0, w - 2 * inset, r.h - min(headH, r.h) * 0.5)
	end
	for _, side in ipairs({ "left", "right" }) do
		local r = L.endcaps[side]
		local file = C.folder .. "\\" .. C[side]
		local hh = min(headH, r.h)
		local shown = right(r) > 0 and r.x < W
		local shaft = add("endcap_" .. side, "cap", file, "ARTWORK", 0, rect(r.x, 0, w, r.h - hh), { 0, 1, C.head, 1 })
		local head = add("endcap_" .. side .. "_head", "cap", file, "OVERLAY", 0, rect(r.x, r.h - hh, w, hh),
			{ 0, 1, 0, C.head })
		shaft.shown, head.shown = shown, shown
	end
end

local function build(W, H, o, X0, chatW)
	-- `art` is the theme's art folder, `t` the faction whose shapes it has.
	local s, m, art = o.s, o.m, o.theme
	local t = Layout.BASE[art] or art
	local layers = LAYERS[art] or LAYERS[t]
	local L = { W = W, H = H, s = s, m = m, theme = art, base = t, pieces = {}, byKey = {} }

	-- Art pieces. `frame` says which of the original addon's frames the piece belongs to,
	-- which decides the stacking: bg < left < grid < right.
	local function add(key, frame, file, layer, sub, r, tc)
		local p = { key = key, frame = frame, file = file, layer = layer, sub = sub or 0, rect = r, tc = tc, shown = true }
		L.pieces[#L.pieces + 1] = p
		L.byKey[key] = p
		return p
	end
	local function themed(file)
		return art .. "\\" .. file
	end
	local function themedLayer(key)
		local spec = layers[key]
		return spec[1], spec[2]
	end

	-- Left part: minimap block and portrait block.
	local MT = rect(X0, 0, s, s)
	local PT = rect(X0 + s, 0, s, s)
	L.minimapArt, L.portraitArt = MT, PT
	add("minimap", "left", themed("minimap_portrait\\minimap"), "ARTWORK", 0, MT)
	add("portrait", "left", themed("minimap_portrait\\portrait"), "BORDER", 0, PT)

	-- Blizzard's minimap: centred 0.189s left of and 0.2s below the block's
	-- centre, 0.55s square.
	local mm = rect(MT.x + 0.5 * s - 0.189 * s - 0.275 * s, 0.5 * s - 0.2 * s - 0.275 * s, 0.55 * s, 0.55 * s)
	L.minimap = mm
	local mmR, mmB = right(mm), mm.y
	-- Column beside the minimap: three action slots, the mail slot and the
	-- round tracking slot.
	L.noMail = rect(mmR + 0.01851 * s, mmB + 0.19259 * s, 0.085 * s, 0.085 * s)
	local resize, addW, addH = 4, 2, 2
	if t == "orc" then
		resize, addW, addH = 3, 2, 1
	end
	L.minimapSlots = {}
	for n = 1, 3 do
		local size = 0.08518 * s - resize
		L.minimapSlots[n] = rect(mmR + 0.01851 * s + addW,
			mmB + 0.455555 * s - (n - 1) * 0.08518 * s - floor(n * 0.34) + addH, size, size)
	end
	L.tracking = { cx = MT.x + 0.64 * s, cy = 0.16 * s, size = 0.09 * s }
	if o.zoneTextPos ~= 3 then
		L.zoneText = rect(mm.x, mm.y + 1 + (o.zoneTextPos == 2 and 0.5 * s or 0), mm.w, 12)
	end
	-- Other minimap buttons (calendar, addon buttons, ...) along the top
	-- edge of the map.
	L.minimapButtons = { x = mm.x + 2, y = top(mm) - 2, size = 0.07 * s, maxW = mm.w - 4 }

	-- Portrait.
	local px, py = o.portraitX or 100, o.portraitY or 100
	local ps = 0.27 * s + (o.portraitScale or 0)
	L.portrait = rect(MT.x + 0.86 * s - (100 - px), 0.10 * s - (100 - py), ps, ps)
	local pcx, pcy = MT.x + 0.86 * s + 0.135 * s, 0.10 * s + 0.135 * s
	L.portraitBg = rect(pcx - 0.175 * s, pcy - (0.35 * s + 20) / 2, 0.35 * s, 0.35 * s + 20)
	L.health = rect(right(MT) - 0.147 * s, 0.07 * s, 0.27 * s, 0.03 * s)
	L.power = rect(right(MT) - 0.147 * s, 0.02 * s, 0.27 * s, 0.03 * s)
	-- Status icons (the original addon moves Blizzard's; we draw our own in their places).
	L.leaderIcon = rect(PT.x + 0.0784313 * s, 0.368627 * s, 16, 16)
	L.pvpIcon = rect(PT.x - 0.2307692 * s, 0, 64, 64)
	L.restIcon = rect(PT.x - 0.188235 * s, 0.32941 * s, 31, 31)

	-- Hero screen: experience bar and the four stat icons.
	local xpX, xpY = PT.x + 0.23 * s, 0.3 * s
	L.xp = levelPlate(xpX, xpY, s)
	local total = L.xp.width
	local iconSize = total * 0.17
	local extraSpace = s <= 250 and 1 or 0
	local function statIcon(dx, dy, labelX, valueY, valueH)
		local r = rect(xpX + 1 + dx, xpY - 0.14 * s + dy, iconSize, iconSize)
		local iconTop = top(r)
		r.label = rect(r.x + labelX, iconTop - 0.065 * s, 100, 15)
		r.value = rect(r.x + labelX, iconTop + valueY, 100, valueH)
		return r
	end
	local valueY = -0.1667 * s - extraSpace
	L.statIcons = {
		statIcon(0, 0, 0.1294 * s, valueY, 30),
		statIcon(0.3607 * s, 0, 0.1294 * s, valueY, 30),
		statIcon(0.3607 * s, -0.1412 * s, 0.1294 * s, valueY, 30),
		statIcon(0, -0.14 * s, 0.14 * s, -0.1111111111111 * s, 15), -- armour
	}

	-- Black background behind the action grid.
	L.extBg = rect(right(PT) - 0.18 * s, 0, 2.1 * s, 0.5 * s)

	-- Action slot grid: four copies of a 4x3 grid overlapping into 12x3.
	local gs = 0.91851 * s
	local g = { rect(L.extBg.x + 0.2 * s - 0.01666666667 * s, 1, gs, gs) }
	g[2] = rect(right(g[1]) - 0.4518 * s, 1, gs, gs)
	g[3] = rect(right(g[2]) - 0.4518 * s, 1, gs, gs)
	g[4] = rect(right(g[3]) - 0.6115 * s + 2, 1, gs, gs)
	L.grid = g
	for i, layer in ipairs({ "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }) do
		add("grid" .. i, "grid", themed("actionbar\\actionslots_grid"), layer, 0, g[i])
	end

	-- Action bars 1-3, the original addon's spacing with its pixel corrections.
	local barX, barY = g[1].x + 0.037037 * s, g[1].y - 1
	local size = 0.11111 * s
	local spacing = 0.159259 * s
	local function row(y)
		local list, x, extra = {}, barX - 6, 0
		for k = 1, 12 do
			if k == 4 then
				extra = extra - 3
			elseif k == 5 then
				extra = extra + 2
			elseif k == 10 then
				extra = extra + 1
			elseif k == 12 and s >= 240 and s <= 260 then
				extra = extra + 1
			end
			if k > 1 then
				x = x + spacing + extra
			end
			list[k] = x
		end
		return { xs = list, y = y, size = size }
	end
	local row2 = barY + size + 0.0667 * s
	L.bars = { main = row(barY + 5), bar2 = row(row2), bar3 = row(row2 + size + 0.04444 * s) }

	-- Stance (aura, form) buttons on top of the wall over the action grid,
	-- from its left end, as Warcraft III and WoW 1.12 put them; the pet bar
	-- follows on the same row.
	local barSize = 0.1 * s
	local barStep = barSize + 3
	local wallTop = (t == "nightelf" and 0.6 or 0.55) * s
	L.stance = { x = g[1].x + 0.04 * s, y = wallTop, size = barSize, step = barStep }
	L.pet = { x = L.stance.x + 10 * barStep + 0.1 * s, y = wallTop, size = barSize, step = barStep }
	L.stanceTop = wallTop + barSize
	buildTarget(L, s, t, MT, L.xp)

	-- Extensions: the wall above the action grid.
	local ext1 = rect(right(PT) - 0.15 * s, 0.45 * s, s, 0.12592 * s)
	local ext2 = rect(0, ext1.y, s, 0.12592 * s)
	local ext3 = rect(0, 0, 0.9481 * s, 0.12592 * s)
	local tc2, tc3
	if s >= 260 then
		ext2.x = right(ext1) - 0.17 * s
		ext3.x, ext3.y = right(ext1) + 0.15 * s, ext1.y + 0.013 * s
	elseif s >= 240 then
		ext2.x = right(ext1) - 0.40 * s
		ext3.x, ext3.y = right(ext2) - 0.50 * s, ext2.y + 0.013 * s
	else
		ext2.x = right(ext1) - 0.05 * s
		ext3.x, ext3.y = right(ext2) - 0.55 * s, ext2.y + 0.013 * s
	end
	if t == "human" then
		tc2 = { 0.265625, 1, 0, 1 }
		ext2.w = 0.8148148 * s
		ext2.x = right(ext1)
		ext3.x, ext3.y = right(ext1) + 0.73333 * s, ext1.y + 0.01481481 * s
		ext3.w, ext3.h = 0.26667 * s, 0.13333334 * s
		tc3 = { 0.5, 1, 0, 1 }
	elseif t == "undead" then
		ext1.x = right(PT) - 0.15 * s + 0.083333333 * s
		ext3.w, ext3.h = s, s / 8
		ext3.x, ext3.y = right(ext1) - 0.088888888 * s + 2, ext1.y + 2
		ext2.w = s <= 255 and (s + 145) or (s + 0.54166666 * s)
		ext2.h = 0.12592 * s - 1
		ext2.x = right(ext1) - 125
		tc2 = { 0.09, 1, 0, 1 }
	elseif t == "nightelf" then
		ext1 = rect(right(PT) - 0.096296 * s, 0.43333 * s, s, s / 4)
		ext2 = rect(right(PT) + 0.685185 * s - 5, 0.43333 * s, s, s / 4)
		ext3 = rect(right(ext2) - 0.296296 * s, ext2.y, s / 2, s / 4)
	end
	local l1, s1 = themedLayer("ext1")
	local l2, s2 = themedLayer("ext2")
	local l3, s3 = themedLayer("ext3")
	add("ext1", "left", themed("actionbar\\ext1"), l1, s1, ext1)
	add("ext2", "left", themed("actionbar\\ext1"), l2, s2, ext2, tc2)
	add("ext3", "left", themed("actionbar\\ext2"), l3, s3, ext3, tc3)

	buildRight(L, o, W, g, add, themed, themedLayer, chatW)
	buildCaps(L, W, add)
	return L
end

-- o: s (240-270), m (raise the chat area, 0-150), theme, zoneTextPos (1-3), portraitX/Y (100 = default), portraitScale (0-35),
-- chatInputAbove.
--
-- The whole console, end caps included, is centred: with the original addon's chat
-- width where it fits, else the chat area narrows to make room for the caps
-- (down to ENDCAP_CHAT_MIN), else (16:9) the chat area reaches the screen
-- edge as in the original addon and the caps go past the screen edges.
function Layout.Compute(W, H, o)
	local s = o.s
	local fixed = build(W, H, o, 0).chatBgX -- everything left of the chat area
	local C = Layout.EndcapArt(o.theme)
	local room = (C.w - C.overlap) * s -- what each cap adds outside the console
	local full = 2.2 * s
	local dx, chatW
	if W >= fixed + full + 2 * room then
		chatW = full
		dx = floor((W - fixed - full) / 2)
	elseif W - 2 * math.ceil(room) - fixed >= Layout.ENDCAP_CHAT_MIN * s then
		dx = math.ceil(room)
		chatW = W - 2 * dx - fixed
	else
		chatW = max(0, min(full, W - fixed))
		dx = max(0, floor((W - fixed - chatW) / 2))
	end
	local L = build(W, H, o, dx, chatW)
	L.shift = dx
	return L
end

return Layout
