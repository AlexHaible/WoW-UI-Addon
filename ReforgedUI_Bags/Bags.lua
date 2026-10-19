-- Reforged UI: Bags. Dresses the game's own bag windows (each bag on its
-- own, and the combined backpack) in the current Reforged UI theme, the way
-- Reforged UI: Damage Meter dresses the meter: the theme's top bar trim
-- around each window (Reforged UI's Trim.lua), a dark inset inside, the
-- theme's rail under the title, the bag's icon in Warcraft III's steel
-- command-button frame on the top-left corner and the original addon's font.
-- BetterBags gets its own theme from BetterBags.lua.
--
-- Only art changes: Blizzard's background and border are made invisible
-- (never hidden or moved, so its code finds them as it left them), and every
-- change is made from post-hooks, after Blizzard's own code has run. The
-- items, the money frame, the search box and the portrait's menu are
-- Blizzard's, untouched.

local ICONFRAME = "Interface\\AddOns\\ReforgedUI\\Media\\Common\\iconframe"
local BACKPACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03"
-- Blizzard's title bar: the flat panel's background starts this far below
-- the window's top.
local TITLE_H = 20
local RAIL_H = 3
local ICON = 32 -- the bag icon, over the trim's top-left corner
local FONT_SIZE = 12

local theme

-- window -> our pieces (weak keys, kept off Blizzard's frames' tables)
local skins = setmetatable({}, { __mode = "k" })

local function forbidden(frame)
	return not frame or (frame.IsForbidden and frame:IsForbidden())
end

-- The icon of the bag a window shows: Blizzard's own portrait is round, so
-- ours is the bag's inventory icon, square.
local function bagIcon(window)
	local id = window.GetBagID and window:GetBagID()
	if window == _G.ContainerFrameCombinedBags or not id or id == 0 then
		return BACKPACK_ICON
	end
	if id == (_G.KEYRING_CONTAINER or -2) then
		return KEYRING_ICON
	end
	local toInv = C_Container and C_Container.ContainerIDToInventoryID
	if toInv then
		local ok, inv = pcall(toInv, id)
		local tex = ok and inv and GetInventoryItemTexture("player", inv)
		if tex then
			return tex
		end
	end
	return BACKPACK_ICON
end

local function Paint(window)
	local s = skins[window]
	if not (s and theme) then
		return
	end
	local inset = theme.inset
	s.bg:SetColorTexture(inset[1], inset[2], inset[3], inset[4])
	s.rail:SetTexture(ReforgedUI.TrimArt("rail"))
	s.trim:Paint()
	s.icon:SetTexture(bagIcon(window))
	local title = window.TitleContainer and window.TitleContainer.TitleText
	if title then
		local _, size = title:GetFont()
		ReforgedUI.SetFont(title, size or FONT_SIZE)
	end
end

local function Skin(window)
	if forbidden(window) or skins[window] or not window.NineSlice then
		return
	end
	local s = {}
	skins[window] = s
	-- Blizzard's border and background, made invisible.
	window.NineSlice:SetAlpha(0)
	if window.Bg then
		window.Bg:SetAlpha(0)
	end
	s.bg = window:CreateTexture(nil, "BACKGROUND", nil, -8)
	s.bg:SetAllPoints()
	-- In the window's BORDER layer: over the background, under the items.
	s.trim = ReforgedUI.CreateTrim(window)
	s.rail = window:CreateTexture(nil, "ARTWORK")
	s.rail:SetHeight(RAIL_H)
	s.rail:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -TITLE_H + 1)
	s.rail:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -TITLE_H + 1)

	-- The round portrait gives way to a square icon in the steel frame. Its
	-- dropdown button (Blizzard's PortraitButton) stays where it was, over it.
	local holder = window.PortraitContainer or window
	local portrait = holder.portrait or (window.GetPortrait and window:GetPortrait())
	if portrait then
		portrait:SetAlpha(0)
	end
	s.icon = holder:CreateTexture(nil, "ARTWORK")
	s.icon:SetSize(ICON, ICON)
	s.icon:SetPoint("TOPLEFT", window, "TOPLEFT", -ReforgedUI.TRIM_OUT + 2, ReforgedUI.TRIM_OUT - 2)
	s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	s.frame = holder:CreateTexture(nil, "OVERLAY", nil, 7)
	s.frame:SetAllPoints(s.icon)
	s.frame:SetTexture(ICONFRAME)

	-- Blizzard sets the portrait (and so which bag this is) each time the
	-- window is filled.
	if window.UpdateMiscellaneousFrames then
		hooksecurefunc(window, "UpdateMiscellaneousFrames", Paint)
	end
	window:HookScript("OnShow", Paint)
	Paint(window)
end

local function SkinAll()
	Skin(_G.ContainerFrameCombinedBags)
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		Skin(_G["ContainerFrame" .. i])
	end
end

local function RepaintAll()
	for window in pairs(skins) do
		Paint(window)
	end
end

ReforgedUI.RegisterThemeCallback(function(_, t)
	theme = t
	SkinAll()
	RepaintAll()
end)
