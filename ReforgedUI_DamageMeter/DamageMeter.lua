-- Reforged UI: Damage Meter. Dresses the game's own damage meter
-- (Blizzard_DamageMeter) in the current Reforged UI theme: each meter window
-- and its breakdown window get the theme's top bar trim around them (beam,
-- posts and corners, as on the top bar), a dark inset inside, the theme's
-- rail under the header and under every bar (art/<theme>/, cut by
-- tools/make_damage_meter.py), Warcraft III bar texture and the original
-- addon's font.
--
-- The meter's numbers can be "secret" in combat, and Blizzard's code does
-- arithmetic on them that fails once addon code is on the call stack. So this
-- only ever changes art: it never reads or formats a value, never adds
-- callbacks to the meter's scroll lists and never moves a window (Edit Mode
-- owns where they are). Every change is made from hooksecurefunc post-hooks,
-- after Blizzard's own code has run.

local ADDON = ...
local ART = "Interface\\AddOns\\" .. ADDON .. "\\art\\"
local MEDIA = "Interface\\AddOns\\ReforgedUI\\Media\\"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local RAIL_H = 3
-- The border is the top bar's trim (Art.lua): edge.tga (256x32) along the
-- top and, flipped, the bottom; edgev.tga (32x128, outer side on the left)
-- down the sides; corner.tga (64x64, drawn for the top-right) at each corner.
-- In window units:
local EDGE = 14 -- trim thickness
local CORNER = 24 -- corner size
local CORNER_OUT = 10 -- how far a corner sticks out past the trim (it reaches INSET into the window, as the trim does)
local INSET = 4 -- how far the trim overlaps the window's edge

-- Themes whose top bar has no side posts of their own (Skyborne's are
-- empty) get a post from make_damage_meter.py: their edge, upright. The
-- value is that file's height (its width is 32).
local OWN_EDGEV = { highorder = 256, windshapers = 256 }

local themeKey, theme

-- Our own pieces, kept off Blizzard's frames' tables (weak keys: a released
-- frame takes its pieces with it).
local borders = setmetatable({}, { __mode = "k" }) -- window -> border frame
local entries = setmetatable({}, { __mode = "k" }) -- entry -> { rail, size }
local hooked = setmetatable({}, { __mode = "k" })

local function forbidden(frame)
	return not frame or (frame.IsForbidden and frame:IsForbidden())
end

----------------------------------------------------------------------------
-- Window border: the theme's trim around the outside of the window,
-- overlapping it by INSET. Nothing of Blizzard's moves; `box` is the rect it
-- goes around.

local function CreateBorder(window)
	local f = CreateFrame("Frame", nil, window)
	f:SetFrameLevel(window:GetFrameLevel() + 20)
	f.box = CreateFrame("Frame", nil, f)
	f.pieces = {}
	-- Corners above the trim, so they cover its ends.
	for _, key in ipairs({ "top", "bottom", "left", "right" }) do
		f.pieces[key] = f:CreateTexture(nil, "ARTWORK")
	end
	for _, key in ipairs({ "tl", "tr", "bl", "br" }) do
		f.pieces[key] = f:CreateTexture(nil, "ARTWORK", nil, 1)
		f.pieces[key]:SetSize(CORNER, CORNER)
	end
	f.header = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.header:SetHeight(RAIL_H)
	return f
end

-- Lays the border out around `box` for the current theme.
local function PaintBorder(f)
	if not theme then
		return
	end
	local p, box = f.pieces, f.box
	local media = MEDIA .. theme.folder .. "\\"
	local out = EDGE - INSET -- how far the trim reaches past the window
	local W, H = box:GetWidth() + 2 * out, box:GetHeight() + 2 * out

	-- edge.tga repeats every 256 / 32 * EDGE units.
	local u = W / (8 * EDGE)
	p.top:SetTexture(media .. "edge", "REPEAT", "CLAMP")
	p.top:ClearAllPoints()
	p.top:SetPoint("TOPLEFT", box, "TOPLEFT", -out, out)
	p.top:SetPoint("TOPRIGHT", box, "TOPRIGHT", out, out)
	p.top:SetHeight(EDGE)
	p.top:SetTexCoord(0, u, 0, 1)
	p.bottom:SetTexture(media .. "edge", "REPEAT", "CLAMP")
	p.bottom:ClearAllPoints()
	p.bottom:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -out, -out)
	p.bottom:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", out, -out)
	p.bottom:SetHeight(EDGE)
	p.bottom:SetTexCoord(0, u, 1, 0)

	-- The posts run between the top and bottom trim, under their ends.
	local own = OWN_EDGEV[themeKey]
	local post = own and (ART .. themeKey .. "\\edgev") or (media .. "edgev")
	local v = (H - 2 * EDGE + 4) / ((own or 128) / 32 * EDGE)
	p.left:SetTexture(post, "CLAMP", "REPEAT")
	p.left:ClearAllPoints()
	p.left:SetPoint("TOPLEFT", box, "TOPLEFT", -out, out - EDGE + 2)
	p.left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -out, -out + EDGE - 2)
	p.left:SetWidth(EDGE)
	p.left:SetTexCoord(0, 1, 0, v)
	p.right:SetTexture(post, "CLAMP", "REPEAT")
	p.right:ClearAllPoints()
	p.right:SetPoint("TOPRIGHT", box, "TOPRIGHT", out, out - EDGE + 2)
	p.right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", out, -out + EDGE - 2)
	p.right:SetWidth(EDGE)
	p.right:SetTexCoord(1, 0, 0, v)

	-- corner.tga is drawn for the top-right corner; mirrored for the rest.
	local c = out + CORNER_OUT
	for key, spec in pairs({
		tr = { "TOPRIGHT", c, c, 0, 1, 0, 1 }, tl = { "TOPLEFT", -c, c, 1, 0, 0, 1 },
		br = { "BOTTOMRIGHT", c, -c, 0, 1, 1, 0 }, bl = { "BOTTOMLEFT", -c, -c, 1, 0, 1, 0 },
	}) do
		local tex = p[key]
		tex:SetTexture(media .. "corner")
		tex:ClearAllPoints()
		tex:SetPoint(spec[1], box, spec[1], spec[2], spec[3])
		tex:SetTexCoord(spec[4], spec[5], spec[6], spec[7])
	end

	f.header:SetTexture(ART .. themeKey .. "\\rail")
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
