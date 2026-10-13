-- Reforged UI's panel art, used by the top bar: a trimmed stone/wood/bone
-- panel (hanging from the top of the screen) and the recessed plates that
-- hold its buttons and data feeds.

local _, ns = ...

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
	-- continue the same pattern instead of restarting it; `originX` moves
	-- where the pattern starts (the top bar's slots sit on it).
	local ox = r.originX or 0
	local u0, v0 = (r.x + l - ox) / PANEL_PERIOD, r.y / PANEL_PERIOD
	f.fill:SetTexCoord(u0, u0 + (r.w - l - rt) / PANEL_PERIOD, v0 + (r.h - 4) / PANEL_PERIOD, v0)
	local vh = (r.h - EDGE + 2) / EDGE_PERIOD
	local e0 = (r.x - ox) / EDGE_PERIOD
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

ns.Art = {
	CreatePanel = CreatePanel, PaintPanel = PaintPanel, PlacePanel = PlacePanel,
	CreateInset = CreateInset, PaintInset = PaintInset,
}
