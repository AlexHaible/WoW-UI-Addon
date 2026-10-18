-- The original addon's console art: the minimap and portrait blocks, the wall over the
-- action grid, the grid itself, the inventory and the frame of the chat area
-- in the bottom-right corner, and the end caps that close the console at both
-- ends. Every piece is a texture on one of five frames that stack like
-- The original addon's: background < left part < grid < right part, with the end caps on
-- top, over the console's edges (levels 2 and 3, between the background and
-- the left part, hold the portrait: see Hero.lua).
-- Positions come from Layout.lua; all frames are our own and click-through,
-- as in the original addon.

local _, ns = ...
local Console = ns:RegisterModule("console", {})

-- The original addon's strata and stacking, kept below everything of Blizzard's (action
-- buttons, chat, minimap) so those always draw on top of the art.
local FRAMES = {
	{ key = "bg", level = 1 },
	{ key = "left", level = 4 },
	{ key = "grid", level = 5 },
	{ key = "right", level = 6 },
	{ key = "cap", level = 7 },
}

function Console:OnEnable()
	self.frames = {}
	for _, spec in ipairs(FRAMES) do
		local f = CreateFrame("Frame", nil, ns.root)
		f:SetFrameStrata("BACKGROUND")
		f:SetFrameLevel(spec.level)
		f:SetAllPoints(ns.root)
		self.frames[spec.key] = f
	end
	self.textures = {}
	-- backgroundMain: black behind the action grid.
	self.extBg = self.frames.bg:CreateTexture(nil, "BACKGROUND")
	self.extBg:SetTexture(ns:ArtPath("other\\black_background"))
end

local function place(region, r)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.x, r.y)
	region:SetSize(math.max(r.w, 0.01), math.max(r.h, 0.01))
end
Console.Place = place

function Console:Texture(piece)
	local t = self.textures[piece.key]
	if not t or t.frameKey ~= piece.frame then
		if t then
			t:Hide()
		end
		t = self.frames[piece.frame]:CreateTexture(nil, piece.layer)
		t.frameKey = piece.frame
		self.textures[piece.key] = t
	end
	return t
end

function Console:OnLayout(L)
	local used = {}
	for _, piece in ipairs(L.pieces) do
		local t = self:Texture(piece)
		used[piece.key] = true
		t:SetTexture(ns:ArtPath(piece.file))
		t:SetDrawLayer(piece.layer, piece.sub)
		local tc = piece.tc
		if tc then
			t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
		else
			t:SetTexCoord(0, 1, 0, 1)
		end
		place(t, piece.rect)
		t:SetShown(piece.shown)
	end
	for key, t in pairs(self.textures) do
		if not used[key] then
			t:Hide()
		end
	end
	place(self.extBg, L.extBg)
	self.extBg:SetShown(L.extBg.w > 0)
	-- "Hide actionbar grid texture".
	self.frames.grid:SetShown(not (ns.db.consoleOpts.hideGrid or ns.db.consoleOpts.editModeBars))
	self:ApplyTransparency()
end

-- "Console transparency": fades the art only. Buttons, icons, text and the
-- portrait are on frames of their own and stay opaque.
function Console:ApplyTransparency()
	local alpha = 1 - math.max(0, math.min(100, ns.db.consoleOpts.transparency or 0)) / 100
	for _, f in pairs(self.frames) do
		f:SetAlpha(alpha)
	end
end
