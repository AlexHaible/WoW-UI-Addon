-- Reforged UI: Damage Meter. Dresses the game's own damage meter
-- (Blizzard_DamageMeter) in the current Reforged UI theme: each meter window
-- and its breakdown window get the theme's top bar trim around them (beam
-- and posts, mitred at the corners: Reforged UI's Trim.lua), a dark inset
-- inside, the theme's rail under the header and under every bar, Warcraft
-- III bar texture and the original addon's font.
--
-- The meter's numbers can be "secret" in combat, and Blizzard's code does
-- arithmetic on them that fails once addon code is on the call stack. So this
-- only ever changes art: it never reads or formats a value, never adds
-- callbacks to the meter's scroll lists and never moves a window (Edit Mode
-- owns where they are). Every change is made from hooksecurefunc post-hooks,
-- after Blizzard's own code has run.

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local RAIL_H = 3

local themeKey, theme

-- Our own pieces, kept off Blizzard's frames' tables (weak keys: a released
-- frame takes its pieces with it).
local borders = setmetatable({}, { __mode = "k" }) -- window -> { trim, header }
local entries = setmetatable({}, { __mode = "k" }) -- entry -> { rail, size }
local hooked = setmetatable({}, { __mode = "k" })

local function forbidden(frame)
	return not frame or (frame.IsForbidden and frame:IsForbidden())
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
	own.rail:SetTexture(ReforgedUI.TrimArt("rail"))
	own.rail:ClearAllPoints()
	own.rail:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 1)
	own.rail:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 1)
	if own.nameSize then
		ReforgedUI.SetFont(bar.Name, own.nameSize, "OUTLINE")
	end
	if own.valueSize then
		ReforgedUI.SetFont(bar.Value, own.valueSize, "OUTLINE")
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
	local box = f.trim.box
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", window, "TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", bottom or window, "BOTTOMRIGHT")
end

local function PaintWindow(window)
	local f = borders[window]
	if not f or not themeKey then
		return
	end
	PlaceBox(window, f)
	f.trim:Paint()
	f.header:SetTexture(ReforgedUI.TrimArt("rail"))
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
	-- The trim (ReforgedUI's Trim.lua) is drawn in the window's own BORDER
	-- layer: over its header and background, under its text and buttons, so
	-- it never hides the timer or the dropdowns. Resizing and minimizing
	-- change its box; the tiles follow the box's size.
	local f = { trim = ReforgedUI.CreateTrim(window) }
	f.header = f.trim.box:CreateTexture(nil, "ARTWORK")
	f.header:SetHeight(RAIL_H)
	borders[window] = f
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
