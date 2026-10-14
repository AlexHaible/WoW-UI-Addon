-- Reforged UI: Damage Meter. Dresses the game's own damage meter
-- (Blizzard_DamageMeter) in the current Reforged UI theme: each meter window
-- and its breakdown window get the theme's target plate frame around them
-- (art/<theme>/, cut by tools/make_damage_meter.py), a dark inset inside,
-- the theme's rail under the header and under every bar, Warcraft III bar
-- texture and the original addon's font.
--
-- The meter's numbers can be "secret" in combat, and Blizzard's code does
-- arithmetic on them that fails once addon code is on the call stack. So this
-- only ever changes art: it never reads or formats a value, never adds
-- callbacks to the meter's scroll lists and never moves a window (Edit Mode
-- owns where they are). Every change is made from hooksecurefunc post-hooks,
-- after Blizzard's own code has run.

local ADDON = ...
local ART = "Interface\\AddOns\\" .. ADDON .. "\\art\\"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FRAME_W, FRAME_H = 512, 256 -- frame.tga
local TILE = 256 -- top/bottom.tga width and side.tga height
local SCALE = 0.5 -- window units per plate pixel
local RAIL_H = 3

-- Each theme's window, in plate pixels: its size (w, h), border widths
-- (l, r, t, b) and the length of one repeat of the top, bottom and side
-- tiles. Printed by `python3 tools/make_damage_meter.py --margins`.
local FRAMES = {
	human = { w = 349, h = 235, l = 30, r = 30, t = 33, b = 7, top = 75, bottom = 75, side = 46 },
	gnome = { w = 359, h = 234, l = 32, r = 32, t = 28, b = 8, top = 76, bottom = 76, side = 48 },
	orc = { w = 347, h = 214, l = 50, r = 50, t = 22, b = 5, top = 62, bottom = 62, side = 44 },
	troll = { w = 317, h = 211, l = 35, r = 35, t = 31, b = 7, top = 62, bottom = 62, side = 40 },
	tauren = { w = 346, h = 226, l = 46, r = 46, t = 44, b = 4, top = 64, bottom = 64, side = 41 },
	undead = { w = 346, h = 255, l = 35, r = 35, t = 52, b = 7, top = 70, bottom = 70, side = 47 },
	nightelf = { w = 367, h = 251, l = 44, r = 44, t = 38, b = 9, top = 72, bottom = 72, side = 49 },
	highorder = { w = 367, h = 251, l = 44, r = 44, t = 42, b = 9, top = 72, bottom = 72, side = 48 },
	windshapers = { w = 367, h = 251, l = 44, r = 44, t = 42, b = 9, top = 72, bottom = 72, side = 48 },
	forsaken = { w = 344, h = 237, l = 65, r = 65, t = 53, b = 8, top = 52, bottom = 52, side = 40 },
	dwarf = { w = 351, h = 237, l = 30, r = 30, t = 32, b = 9, top = 76, bottom = 76, side = 47 },
}

local themeKey, theme

-- Our own pieces, kept off Blizzard's frames' tables (weak keys: a released
-- frame takes its pieces with it).
local borders = setmetatable({}, { __mode = "k" }) -- window -> border frame
local entries = setmetatable({}, { __mode = "k" }) -- entry -> { rail, size }
local hooked = setmetatable({}, { __mode = "k" })

local function pow2(n)
	local p = 1
	while p < n do
		p = p * 2
	end
	return p
end

local function forbidden(frame)
	return not frame or (frame.IsForbidden and frame:IsForbidden())
end

----------------------------------------------------------------------------
-- Window border: the plate's corners, with its beam, base and posts tiled
-- between them. It sits outside the window, so nothing of Blizzard's is
-- covered; `box` is the rect it goes around.

local function CreateBorder(window)
	local f = CreateFrame("Frame", nil, window)
	f:SetFrameLevel(window:GetFrameLevel() + 20)
	f.box = CreateFrame("Frame", nil, f)
	f.pieces = {}
	for _, key in ipairs({ "tl", "tr", "bl", "br", "top", "bottom", "left", "right" }) do
		f.pieces[key] = f:CreateTexture(nil, "ARTWORK")
	end
	f.header = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.header:SetHeight(RAIL_H)
	return f
end

-- Lays the border out around `box` for the current theme.
local function PaintBorder(f)
	local m = FRAMES[themeKey]
	f:SetShown(m ~= nil)
	if not m then
		return
	end
	local dir = ART .. themeKey .. "\\"
	local p, box = f.pieces, f.box
	local l, r, t, b = m.l * SCALE, m.r * SCALE, m.t * SCALE, m.b * SCALE

	local function corner(tex, point, rel, x0, y0, w, h)
		tex:SetTexture(dir .. "frame")
		tex:ClearAllPoints()
		tex:SetPoint(point, box, rel)
		tex:SetSize(w * SCALE, h * SCALE)
		tex:SetTexCoord(x0 / FRAME_W, (x0 + w) / FRAME_W, y0 / FRAME_H, (y0 + h) / FRAME_H)
	end
	corner(p.tl, "BOTTOMRIGHT", "TOPLEFT", 0, 0, m.l, m.t)
	corner(p.tr, "BOTTOMLEFT", "TOPRIGHT", m.w - m.r, 0, m.r, m.t)
	corner(p.bl, "TOPRIGHT", "BOTTOMLEFT", 0, m.h - m.b, m.l, m.b)
	corner(p.br, "TOPLEFT", "BOTTOMRIGHT", m.w - m.r, m.h - m.b, m.r, m.b)

	local W, H = box:GetWidth(), box:GetHeight()
	-- Beam and base repeat along the top and bottom.
	p.top:SetTexture(dir .. "top", "REPEAT", "CLAMP")
	p.top:ClearAllPoints()
	p.top:SetPoint("BOTTOMLEFT", box, "TOPLEFT")
	p.top:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT")
	p.top:SetHeight(t)
	p.top:SetTexCoord(0, W / (m.top * SCALE), 0, m.t / pow2(m.t))
	p.bottom:SetTexture(dir .. "bottom", "REPEAT", "CLAMP")
	p.bottom:ClearAllPoints()
	p.bottom:SetPoint("TOPLEFT", box, "BOTTOMLEFT")
	p.bottom:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT")
	p.bottom:SetHeight(b)
	p.bottom:SetTexCoord(0, W / (m.bottom * SCALE), 0, m.b / pow2(m.b))
	-- side.tga is the right-hand post; the left one is its mirror image.
	local v = H / (m.side * SCALE)
	local u = m.r / pow2(m.r)
	p.right:SetTexture(dir .. "side", "CLAMP", "REPEAT")
	p.right:ClearAllPoints()
	p.right:SetPoint("TOPLEFT", box, "TOPRIGHT")
	p.right:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT")
	p.right:SetWidth(r)
	p.right:SetTexCoord(0, u, 0, v)
	p.left:SetTexture(dir .. "side", "CLAMP", "REPEAT")
	p.left:ClearAllPoints()
	p.left:SetPoint("TOPRIGHT", box, "TOPLEFT")
	p.left:SetPoint("BOTTOMRIGHT", box, "BOTTOMLEFT")
	p.left:SetWidth(l)
	p.left:SetTexCoord(u, 0, 0, v)

	f.header:SetTexture(dir .. "rail")
end

----------------------------------------------------------------------------
-- Bars

local function SkinEntry(entry)
	if forbidden(entry) or not themeKey then
		return
	end
	local own = entries[entry]
	if not own then
		own = {}
		entries[entry] = own
		own.rail = entry:CreateTexture(nil, "OVERLAY", nil, -1)
		own.rail:SetHeight(RAIL_H)
		-- The fonts' sizes, before we touch them (SetTextScale scales on top).
		own.nameSize = select(2, entry.StatusBar.Name:GetFont())
		own.valueSize = select(2, entry.StatusBar.Value:GetFont())
	end
	local bar = entry.StatusBar
	bar:GetStatusBarTexture():SetTexture(BAR_TEXTURE)
	local inset = theme.inset
	bar.Background:SetColorTexture(inset[1], inset[2], inset[3], 0.75)
	bar.BackgroundEdge:SetColorTexture(0, 0, 0, 0)
	own.rail:SetTexture(ART .. themeKey .. "\\rail")
	own.rail:ClearAllPoints()
	own.rail:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 1)
	own.rail:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 1)
	local font = ReforgedUI.FONT
	if own.nameSize then
		bar.Name:SetFont(font, own.nameSize, "OUTLINE")
	end
	if own.valueSize then
		bar.Value:SetFont(font, own.valueSize, "OUTLINE")
	end
end

-- Bars made before Start have their own unhooked copy of UpdateStyle; later
-- ones copied the hooked one from the mixin.
local function HookEntry(entry)
	if forbidden(entry) or hooked[entry] then
		return
	end
	hooked[entry] = true
	if entry.UpdateStyle ~= DamageMeterEntryMixin.UpdateStyle then
		hooksecurefunc(entry, "UpdateStyle", SkinEntry)
	end
	SkinEntry(entry)
end

-- The bars a scroll box shows now; later ones come with the hooked mixin.
local function HookScrollBox(scrollBox)
	if forbidden(scrollBox) or not scrollBox.GetFrames then
		return
	end
	for _, entry in ipairs(scrollBox:GetFrames()) do
		HookEntry(entry)
	end
end

----------------------------------------------------------------------------
-- Windows

-- The box a border goes around: the whole window, or only its header while
-- the window is minimized.
local function PlaceBox(window, f)
	local bottom = window.MinimizeContainer
	if window.isMinimized or not (bottom and bottom:IsShown()) then
		bottom = window.Header
	end
	f.box:ClearAllPoints()
	f.box:SetPoint("TOPLEFT", window, "TOPLEFT")
	f.box:SetPoint("BOTTOMRIGHT", bottom or window, "BOTTOMRIGHT")
end

local function PaintWindow(window)
	local f = borders[window]
	if not f or not themeKey then
		return
	end
	PlaceBox(window, f)
	PaintBorder(f)
	local inset = theme.inset
	if window.Header then
		-- Blizzard only ever anchors this texture, so swapping its art is safe.
		window.Header:SetColorTexture(inset[1], inset[2], inset[3], 1)
		f.header:ClearAllPoints()
		f.header:SetPoint("TOPLEFT", window.Header, "BOTTOMLEFT", 0, 1)
		f.header:SetPoint("TOPRIGHT", window.Header, "BOTTOMRIGHT", 0, 1)
		f.header:Show()
	else
		f.header:Hide()
	end
	-- The meter's opacity setting still drives this texture's alpha.
	local bg = window.MinimizeContainer and window.MinimizeContainer.Background or window.Background
	if bg then
		bg:SetColorTexture(inset[1], inset[2], inset[3], 1)
	end
end

local function SkinWindow(window)
	if forbidden(window) or borders[window] then
		return
	end
	local f = CreateBorder(window)
	borders[window] = f
	-- Resizing and minimizing change the box; the tiles follow its size.
	f.box:SetScript("OnSizeChanged", function()
		PaintBorder(f)
	end)
	if window.SetMinimized then
		hooksecurefunc(window, "SetMinimized", function(w)
			PlaceBox(w, f)
		end)
	end
	PaintWindow(window)

	local c = window.MinimizeContainer
	if c then
		HookScrollBox(c.ScrollBox)
		HookEntry(c.LocalPlayerEntry)
		-- The breakdown of one source, opened by clicking its bar.
		if c.SourceWindow then
			SkinWindow(c.SourceWindow)
		end
	else
		HookScrollBox(window.ScrollBox)
	end
end

local function SkinAllWindows()
	for i = 1, 10 do
		local window = _G["DamageMeterSessionWindow" .. i]
		if window then
			SkinWindow(window)
		end
	end
end

local function RepaintAll()
	for window in pairs(borders) do
		PaintWindow(window)
	end
	for entry in pairs(entries) do
		SkinEntry(entry)
	end
end

----------------------------------------------------------------------------
-- Startup

local started

local function Start()
	if started or not (DamageMeter and DamageMeterEntryMixin) then
		return
	end
	started = true
	-- Bars made from now on carry the hook in their copy of the mixin.
	hooksecurefunc(DamageMeterEntryMixin, "UpdateStyle", SkinEntry)
	hooksecurefunc(DamageMeter, "SetupSessionWindow", SkinAllWindows)
	SkinAllWindows()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
-- In case the client loads the meter after us.
events:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_DamageMeter" and themeKey then
		Start()
	end
end)

ReforgedUI.RegisterThemeCallback(function(key, t)
	themeKey, theme = key, t
	Start()
	RepaintAll()
end)
