-- The console art: a stone/wood/bone band across the bottom of the screen,
-- raised trimmed blocks for chat, the minimap, portrait, inventory and target,
-- recessed "screens", button sockets and the faction crest.

local _, ns = ...
local Console = ns:RegisterModule("console", {})

local EDGE = 16 -- trim thickness in console units
local EDGE_PERIOD = 128 -- edge.tga (256x32) repeats every 128 units at EDGE thickness
local PANEL_PERIOD = 256
local CORNER = 40

local function setTiled(tex, path, hwrap, vwrap)
	tex:SetTexture(path, hwrap, vwrap)
end

----------------------------------------------------------------------------
-- Trimmed panel

-- A normal panel stands on the bottom of the screen with its trim on top; a
-- hanging panel (the top bar) hangs from the top with its trim underneath.
local function CreatePanel(parent, level, hanging)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(level)
	f:EnableMouse(true) -- keep clicks on the console from reaching the world
	f.hanging = hanging
	local outer, inner = hanging and "BOTTOM" or "TOP", hanging and "TOP" or "BOTTOM"
	local dir = hanging and 1 or -1
	f.fill = f:CreateTexture(nil, "BACKGROUND")
	f.fill:SetPoint(outer .. "LEFT", 4, dir * 4)
	f.fill:SetPoint(inner .. "RIGHT", -4, 0)
	f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.shade:SetAllPoints(f.fill)
	f.shade:SetColorTexture(0, 0, 0, 1)
	f.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(0, 0, 0, 0))

	f.top = f:CreateTexture(nil, "BORDER")
	f.top:SetPoint(outer .. "LEFT")
	f.top:SetPoint(outer .. "RIGHT")
	f.top:SetHeight(EDGE)
	f.left = f:CreateTexture(nil, "BORDER")
	f.left:SetPoint(outer .. "LEFT", 0, dir * (EDGE - 2))
	f.left:SetPoint(inner .. "LEFT")
	f.left:SetWidth(EDGE)
	f.right = f:CreateTexture(nil, "BORDER")
	f.right:SetPoint(outer .. "RIGHT", 0, dir * (EDGE - 2))
	f.right:SetPoint(inner .. "RIGHT")
	f.right:SetWidth(EDGE)

	f.tl = f:CreateTexture(nil, "ARTWORK")
	f.tl:SetSize(CORNER, CORNER)
	f.tl:SetPoint(outer .. "LEFT", -6, -dir * 6)
	f.tr = f:CreateTexture(nil, "ARTWORK")
	f.tr:SetSize(CORNER, CORNER)
	f.tr:SetPoint(outer .. "RIGHT", 6, -dir * 6)
	return f
end

local function PaintPanel(f, theme)
	setTiled(f.fill, ns:Media("panel", theme), "REPEAT", "REPEAT")
	setTiled(f.top, ns:Media("edge", theme), "REPEAT", "CLAMP")
	setTiled(f.left, ns:Media("edgev", theme), "CLAMP", "REPEAT")
	setTiled(f.right, ns:Media("edgev", theme), "CLAMP", "REPEAT")
	f.tl:SetTexture(ns:Media("corner", theme))
	f.tr:SetTexture(ns:Media("corner", theme))
	-- corner.tga is drawn for the top-right corner; mirror it for the left.
	if f.hanging then
		f.tl:SetTexCoord(1, 0, 1, 0)
		f.tr:SetTexCoord(0, 1, 1, 0)
	else
		f.tl:SetTexCoord(1, 0, 0, 1)
		f.tr:SetTexCoord(0, 1, 0, 1)
	end
end

local function PlacePanel(f, r, root, showCorners)
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", r.x, r.y)
	f:SetSize(r.w, r.h)
	-- Open sides (joined to a neighbouring panel) run the fill to the edge.
	local l, rt = r.openLeft and 0 or 4, r.openRight and 0 or 4
	local outer, inner = f.hanging and "BOTTOM" or "TOP", f.hanging and "TOP" or "BOTTOM"
	local dir = f.hanging and 1 or -1
	f.fill:ClearAllPoints()
	f.fill:SetPoint(outer .. "LEFT", l, dir * 4)
	f.fill:SetPoint(inner .. "RIGHT", -rt, 0)
	-- Offset texture coordinates by absolute position so neighbouring panels
	-- continue the same pattern instead of restarting it.
	local u0, v0 = (r.x + l) / PANEL_PERIOD, r.y / PANEL_PERIOD
	f.fill:SetTexCoord(u0, u0 + (r.w - l - rt) / PANEL_PERIOD, v0 + (r.h - 4) / PANEL_PERIOD, v0)
	local vh = (r.h - EDGE + 2) / EDGE_PERIOD
	local e0 = r.x / EDGE_PERIOD
	if f.hanging then
		f.top:SetTexCoord(e0, e0 + r.w / EDGE_PERIOD, 1, 0)
		f.left:SetTexCoord(0, 1, vh, 0)
		f.right:SetTexCoord(1, 0, vh, 0)
	else
		f.top:SetTexCoord(e0, e0 + r.w / EDGE_PERIOD, 0, 1)
		f.left:SetTexCoord(0, 1, 0, vh)
		f.right:SetTexCoord(1, 0, 0, vh)
	end
	f.left:SetShown(not r.openLeft)
	f.right:SetShown(not r.openRight)
	f.tl:SetShown(showCorners and not r.openLeft)
	f.tr:SetShown(showCorners and not r.openRight)
	f:Show()
end

----------------------------------------------------------------------------
-- Recessed screen

local function CreateInset(parent, level)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(level)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.glow:SetAllPoints()
	f.glow:SetColorTexture(1, 1, 1, 1)
	f.lines = {}
	for i, spec in ipairs({
		{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
	}) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetHeight(2) else t:SetWidth(2) end
		f.lines[i] = t
	end
	f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.shadow:SetPoint("TOPLEFT", 2, -2)
	f.shadow:SetPoint("TOPRIGHT", -2, -2)
	f.shadow:SetHeight(10)
	f.shadow:SetColorTexture(0, 0, 0, 1)
	f.shadow:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
	return f
end

local function PaintInset(f, theme)
	f.bg:SetColorTexture(unpack(theme.inset))
	local a = theme.accent
	f.glow:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 0.10), CreateColor(a[1], a[2], a[3], 0))
	local l = theme.insetLine
	-- darker on the top/left, lighter on the bottom/right: reads as recessed
	f.lines[1]:SetColorTexture(l[1] * 0.45, l[2] * 0.45, l[3] * 0.45, l[4])
	f.lines[3]:SetColorTexture(l[1] * 0.45, l[2] * 0.45, l[3] * 0.45, l[4])
	f.lines[2]:SetColorTexture(unpack(l))
	f.lines[4]:SetColorTexture(unpack(l))
end

-- Shared with the top bar.
ns.Art = {
	CreatePanel = CreatePanel, PaintPanel = PaintPanel, PlacePanel = PlacePanel,
	CreateInset = CreateInset, PaintInset = PaintInset,
}

----------------------------------------------------------------------------
-- Module

function Console:OnEnable()
	local root = ns.root
	self.base = CreatePanel(root, 2)
	self.panels = {}
	self.insets = {}
	self.wells = {}
	-- The original addon's whole console sections (minimap, portrait, inventory).
	self.sectionFrame = CreateFrame("Frame", nil, root)
	self.sectionFrame:SetFrameLevel(3)
	self.sectionFrame:SetAllPoints()
	self.sections = {}
	self.wellFrame = CreateFrame("Frame", nil, root)
	self.wellFrame:SetFrameLevel(20)
	self.wellFrame:SetAllPoints()
	self.crestFrame = CreateFrame("Frame", nil, root)
	self.crestFrame:SetFrameLevel(30)
	self.crest = self.crestFrame:CreateTexture(nil, "ARTWORK")
end

function Console:GetPanel(i)
	if not self.panels[i] then
		self.panels[i] = CreatePanel(ns.root, 4 + i)
		if ns.theme then PaintPanel(self.panels[i], ns.theme) end
	end
	return self.panels[i]
end

function Console:GetInset(i)
	if not self.insets[i] then
		self.insets[i] = CreateInset(ns.root, 14)
		if ns.theme then PaintInset(self.insets[i], ns.theme) end
	end
	return self.insets[i]
end

function Console:GetWell(i)
	if not self.wells[i] then
		local t = self.wellFrame:CreateTexture(nil, "ARTWORK")
		if ns.theme then t:SetTexture(ns:Media("well", ns.theme)) end
		self.wells[i] = t
	end
	return self.wells[i]
end

-- Sockets behind each slot of a grid (action bars, inventory).
function Console:AddWells(grid, n)
	local Layout = ns.Layout
	local pad = math.floor(grid.size * 0.12 + 0.5)
	for i = 1, grid.cols * grid.rows do
		n = n + 1
		local x, y = Layout.GridCell(grid, i)
		local t = self:GetWell(n)
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", x - pad, y - pad)
		t:SetSize(grid.size + 2 * pad, grid.size + 2 * pad)
		t:Show()
	end
	return n
end

function Console:OnLayout(L)
	local root = ns.root
	PlacePanel(self.base, L.base, root, false)

	for i, p in ipairs(L.panels) do
		PlacePanel(self:GetPanel(i), p, root, true)
	end
	for i = #L.panels + 1, #self.panels do
		self.panels[i]:Hide()
	end

	self:PlaceSections(L)

	local insets = {}
	for _, r in ipairs(L.insets) do insets[#insets + 1] = r end
	for i, r in ipairs(insets) do
		local f = self:GetInset(i)
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", r.x, r.y)
		f:SetSize(r.w, r.h)
		f:Show()
	end
	for i = #insets + 1, #self.insets do
		self.insets[i]:Hide()
	end

	local n = 0
	for _, key in ipairs({ "main", "bar2", "bar3", "bar4", "bar5" }) do
		if L.bars[key] then
			n = self:AddWells(L.bars[key], n)
		end
	end
	-- (the inventory section paints its own bag sockets)
	for i = n + 1, #self.wells do
		self.wells[i]:Hide()
	end

	local c = L.crest
	self.crest:ClearAllPoints()
	self.crest:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", c.x, c.y)
	self.crest:SetSize(c.w, c.h)
end

-- Sections are drawn at their layout size; `u1` crops a section to the left
-- part of its texture. Clicks on them stop at the console like panels'.
function Console:PlaceSections(L)
	local root = ns.root
	for i, sec in ipairs(L.sections or {}) do
		local f = self.sections[i]
		if not f then
			f = CreateFrame("Frame", nil, self.sectionFrame)
			f:SetFrameLevel(3)
			f.tex = f:CreateTexture(nil, "BACKGROUND")
			f.tex:SetAllPoints()
			self.sections[i] = f
		end
		f.key = sec.key
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", sec.x, sec.y)
		f:SetSize(sec.w, sec.h)
		-- Only the wall itself (not the transparent sky above it) takes clicks.
		f:EnableMouse(true)
		f:SetHitRectInsets(0, 0, sec.h - (sec.wall or sec.h), 0)
		f.tex:SetTexture(ns:Media("sections\\" .. sec.key, ns.theme))
		f.tex:SetTexCoord(0, sec.u1 or 1, 0, 1)
		f:Show()
	end
	for i = #(L.sections or {}) + 1, #self.sections do
		self.sections[i]:Hide()
	end
end

function Console:OnTheme(theme)
	PaintPanel(self.base, theme)
	for _, p in ipairs(self.panels) do PaintPanel(p, theme) end
	for _, f in ipairs(self.insets) do PaintInset(f, theme) end
	for _, t in ipairs(self.wells) do t:SetTexture(ns:Media("well", theme)) end
	self.crest:SetTexture(ns:Media("crest", theme))
	-- Re-apply texture coordinates (SetTexture with wrap modes can reset them).
	if ns.layout then self:OnLayout(ns.layout) end
end
