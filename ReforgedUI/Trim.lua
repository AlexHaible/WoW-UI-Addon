-- The theme frame the companion addons put around Blizzard's windows (the
-- damage meter, the bags): the top bar's trim (Art.lua) all round, mitred at
-- the corners like a picture frame, and the theme's rail for lines inside.
-- Its own art is in Media/Trim/<theme>/, cut by tools/make_trim.py.
--
--   local trim = ReforgedUI.CreateTrim(window)
--   trim.box:SetPoint(...)   -- the rect the trim goes around (all of window by default)
--   trim:Paint()             -- after every theme change
--   ReforgedUI.TrimArt("rail")
local _, ns = ...

local MEDIA = "Interface\\AddOns\\ReforgedUI\\Media\\"
local TRIM = MEDIA .. "Trim\\"

-- The border is edge.tga (256x32) along the top and, flipped, the bottom;
-- edgev.tga (32x128, outer side on the left) down the sides. The two meet in
-- mitred corners (join.tga, made by make_trim.py from the same two
-- textures). Each side runs out from its two corners and is mirrored at its
-- middle, so all four corners are the same join and the pattern always
-- meets it the same way. In window units:
local EDGE = 14 -- trim thickness (32 px of the art)
local INSET = 4 -- how far the trim overlaps the window's edge

-- Themes whose top bar has no side posts of their own (Skyborne's are
-- empty) get a post from make_trim.py: their edge, upright. The value is
-- that file's height (its width is 32).
local OWN_EDGEV = { highorder = 256, windshapers = 256, undead = 256 }
-- Themes whose top bar edge is a thin beam with nothing under it (Scourge's
-- bone) get a thicker one from make_trim.py, and its posts too.
local OWN_EDGE = { undead = true }

local PIECES = { "topL", "topR", "bottomL", "bottomR", "leftT", "leftB", "rightT", "rightB", "tl", "tr", "bl", "br" }

-- The current theme's file `name` from Media/Trim.
function ReforgedUI.TrimArt(name)
	return TRIM .. (ns.themeKey or "human") .. "\\" .. name
end

-- How far the trim reaches past the box it goes around.
ReforgedUI.TRIM_OUT = EDGE - INSET

-- One half of a side: from the corner at `point` of `box` (pushed `dx`, `dy`
-- outwards), `w` x `h`, with the texture's repeat coords.
local function half(tex, file, box, point, dx, dy, w, h, l, r, t, b)
	tex:SetTexture(file, "REPEAT", "REPEAT")
	tex:ClearAllPoints()
	tex:SetPoint(point, box, point, dx, dy)
	tex:SetSize(w, h)
	tex:SetTexCoord(l, r, t, b)
end

local Trim = {}

-- Lays the trim out around its box for the current theme.
function Trim:Paint()
	local key, theme = ns.themeKey, ns.theme
	if not (key and theme) then
		return
	end
	local p, box = self.pieces, self.box
	local media = MEDIA .. theme.folder .. "\\"
	local out = EDGE - INSET
	local W, H = box:GetWidth() + 2 * out, box:GetHeight() + 2 * out
	local own = OWN_EDGEV[key]
	local edge = OWN_EDGE[key] and (TRIM .. key .. "\\edge") or (media .. "edge")
	local post = own and (TRIM .. key .. "\\edgev") or (media .. "edgev")

	-- Beam halves: edge.tga repeats every 8 EDGE; the join took its first
	-- EDGE (u 0 to 1/8), so each half carries on from there.
	local hw = math.max(0, W / 2 - EDGE)
	local u0, u1 = 1 / 8, 1 / 8 + hw / (8 * EDGE)
	half(p.topL, edge, box, "TOPLEFT", -out + EDGE, out, hw, EDGE, u0, u1, 0, 1)
	half(p.topR, edge, box, "TOPRIGHT", out - EDGE, out, hw, EDGE, u1, u0, 0, 1)
	half(p.bottomL, edge, box, "BOTTOMLEFT", -out + EDGE, -out, hw, EDGE, u0, u1, 1, 0)
	half(p.bottomR, edge, box, "BOTTOMRIGHT", out - EDGE, -out, hw, EDGE, u1, u0, 1, 0)

	-- Post halves: edgev.tga repeats every (its height / 32) EDGE.
	local period = (own or 128) / 32
	local hh = math.max(0, H / 2 - EDGE)
	local v0, v1 = 1 / period, 1 / period + hh / (period * EDGE)
	half(p.leftT, post, box, "TOPLEFT", -out, out - EDGE, EDGE, hh, 0, 1, v0, v1)
	half(p.leftB, post, box, "BOTTOMLEFT", -out, -out + EDGE, EDGE, hh, 0, 1, v1, v0)
	half(p.rightT, post, box, "TOPRIGHT", out, out - EDGE, EDGE, hh, 1, 0, v0, v1)
	half(p.rightB, post, box, "BOTTOMRIGHT", out, -out + EDGE, EDGE, hh, 1, 0, v1, v0)

	-- join.tga is the top-left corner; mirrored for the rest.
	local join = TRIM .. key .. "\\join"
	half(p.tl, join, box, "TOPLEFT", -out, out, EDGE, EDGE, 0, 1, 0, 1)
	half(p.tr, join, box, "TOPRIGHT", out, out, EDGE, EDGE, 1, 0, 0, 1)
	half(p.bl, join, box, "BOTTOMLEFT", -out, -out, EDGE, EDGE, 0, 1, 1, 0)
	half(p.br, join, box, "BOTTOMRIGHT", out, -out, EDGE, EDGE, 1, 0, 1, 0)
end

function Trim:SetShown(shown)
	for _, tex in pairs(self.pieces) do
		tex:SetShown(shown)
	end
end

-- A trim around `window`, overlapping its edge by INSET. The pieces are
-- textures of `window` itself, in `layer` (default BORDER): over its own
-- background, under its text and its child frames. Nothing of the window's
-- moves; resizing it (or the box) repaints the trim.
function ReforgedUI.CreateTrim(window, layer)
	local trim = setmetatable({ pieces = {} }, { __index = Trim })
	trim.box = CreateFrame("Frame", nil, window)
	trim.box:SetAllPoints(window)
	for _, key in ipairs(PIECES) do
		trim.pieces[key] = window:CreateTexture(nil, layer or "BORDER")
	end
	trim.box:SetScript("OnSizeChanged", function()
		trim:Paint()
	end)
	trim:Paint()
	return trim
end
