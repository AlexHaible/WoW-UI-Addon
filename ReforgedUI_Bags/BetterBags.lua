-- Reforged UI: Bags, the BetterBags theme. Adds "Reforged UI" to BetterBags'
-- theme list: its bag, bank and option windows in the current Reforged UI
-- theme, as Bags.lua dresses the game's own bags (trim all round, dark inset,
-- the theme's rail under the title, the bag icon in Warcraft III's steel
-- frame) and following it as the theme changes.
--
-- BetterBags draws every window through Sonata, its declarative theme engine
-- (BetterBags' sonata/README.md): a theme is data, the window and element
-- styles below, and BetterBags builds and releases every frame and texture
-- itself. The theme's art and colours are variables, read from Reforged UI
-- each time BetterBags applies the theme, so a Reforged UI theme change
-- applies it again. The trim is one nine-sliced texture per theme
-- (Media/Trim/<theme>/frame.tga, made by tools/make_bb_frame.py from the
-- pieces Trim.lua lays out).
--
-- BetterBags is only an optional dependency: without it (or with a version
-- from before Sonata) this file does nothing at all.

local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
local BetterBags = AceAddon and AceAddon:GetAddon("BetterBags", true)
if not BetterBags then
	return
end
local sonata = BetterBags:GetModule("Sonata", true)
local context = BetterBags:GetModule("Context", true)
if not (sonata and sonata.RegisterTheme and context) then
	return
end

local NAME = "ReforgedUI" -- the key BetterBags saves; kept from the old theme
local ICONFRAME = "Interface\\AddOns\\ReforgedUI\\Media\\Common\\iconframe"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local TITLE_H = 20 -- the title band; BetterBags' search box starts 30 down
local RAIL_H = 3
local ICON = 32
local EDGE = 14 -- the trim's thickness (Trim.lua), frame.tga's slice margins
local OUT = ReforgedUI.TRIM_OUT -- how far the trim reaches past the window

-- Before Reforged UI has a theme: Human's colours.
local DEFAULT_INSET = { 0.02, 0.04, 0.10 }
local DEFAULT_LINE = { 0.85, 0.68, 0.30 }

local function around(n)
	return { Left = n, Right = n, Top = n, Bottom = n }
end

local function themeColor(field, default)
	return function()
		local _, theme = ReforgedUI.GetTheme()
		local c = theme and theme[field] or default
		return { c[1], c[2], c[3], 1 }
	end
end

local FONT = { Object = "GameFontNormal", Path = ReforgedUI.FONT, Size = 12, Flags = "", Color = { 1, 0.82, 0, 1 },
	Shadow = { X = 0, Y = 0, Color = { 0, 0, 0, 0 } } }

-- The dark inset fills the window and fades with BetterBags' opacity.
local BACKGROUND = { Color = "$Inset" }
-- The trim around the window, overlapping its edge by Trim.lua's INSET.
local TRIM = {
	Name = "Trim",
	Texture = "$Frame",
	SliceMode = "Tiled",
	SliceMargins = around(EDGE),
	Layer = "BORDER",
	Inset = around(-OUT),
}
-- The theme's rail under the title band.
local RAIL = {
	Name = "Rail",
	Texture = "$Rail",
	Layer = "ARTWORK",
	Points = {
		{ Point = "TOPLEFT", X = 0, Y = -TITLE_H + 1 },
		{ Point = "TOPRIGHT", X = 0, Y = -TITLE_H + 1 },
	},
	Size = { Height = RAIL_H },
}
-- Warcraft III's steel command-button frame over the menu button, which
-- sits on the trim's top-left corner.
local ICON_X, ICON_Y = -OUT + 2, OUT - 2
local STEEL = {
	Name = "IconFrame",
	Texture = ICONFRAME,
	Above = true,
	Points = { { Point = "TOPLEFT", X = ICON_X, Y = ICON_Y } },
	Size = { Width = ICON, Height = ICON },
}
local TITLE = {
	Font = FONT,
	Points = { { Point = "TOPLEFT", X = 30, Y = 0 }, { Point = "TOPRIGHT", X = -30, Y = 0 } },
	Height = TITLE_H,
	Justify = "CENTER",
}
local CLOSE = { Template = "UIPanelCloseButtonNoScripts", Points = { { Point = "TOPRIGHT", X = 3, Y = 3 } } }

-- A window in the trim; titled ones get the rail under the title.
local function framed(titled, close)
	return {
		Background = BACKGROUND,
		Textures = titled and { TRIM, RAIL } or { TRIM },
		Title = titled and TITLE or nil,
		CloseButton = close and CLOSE or nil,
	}
end

local bag = framed(true, true)
bag.Textures = { TRIM, RAIL, STEEL }
bag.Layout = {
	MenuButton = { Points = { { Point = "TOPLEFT", X = ICON_X, Y = ICON_Y } } },
	-- The tabs hang below the trim.
	Tabs = { Offset = { X = 0, Y = 2 - OUT } },
}

-- The Show Bags and bank tab panels sit above their bag, the two trims
-- clear of each other.
local slots = framed(false, false)
slots.Layout = { Points = { { Point = "BOTTOMLEFT", RelativePoint = "TOPLEFT", X = 0, Y = 2 * OUT + 4 } } }

-- Flat tabs in the inset colour, edged in the theme's inset line; the
-- selected one lighter and edged in gold. Their art starts 2 into the tab.
local TAB_INSET = { Left = 0, Right = 0, Top = 2, Bottom = 0 }
local function tabFont(color)
	return { Object = "GameFontNormalSmall", Path = ReforgedUI.FONT, Size = 11, Flags = "", Color = color }
end

sonata:RegisterTheme({
	Name = NAME,
	DisplayName = "Reforged UI",
	Description = "Your Reforged UI theme: the race's top bar trim around every window, following it as you switch.",
	Variables = {
		Frame = function()
			return ReforgedUI.TrimArt("frame")
		end,
		Rail = function()
			return ReforgedUI.TrimArt("rail")
		end,
		Inset = themeColor("inset", DEFAULT_INSET),
		InsetLine = themeColor("insetLine", DEFAULT_LINE),
	},
	Windows = {
		Bag = bag,
		Panel = framed(true, true),
		Flat = framed(true, true),
		Dialog = framed(true, false),
		Slots = slots,
		Search = framed(false, false),
	},
	Elements = {
		-- BetterBags' menu button, as the bag's icon in the steel frame.
		BagButton = {
			Size = ICON,
			Portrait = { Texture = BAG_ICON, TexCoords = { 0.07, 0.93, 0.07, 0.93 }, Width = ICON, Height = ICON,
				Layer = "ARTWORK" },
			Highlight = { Texture = "Interface\\Buttons\\ButtonHilight-Square", BlendMode = "ADD", Width = ICON,
				Height = ICON, Layer = "OVERLAY" },
		},
		SectionHeader = { Font = FONT },
		Tab = {
			Art = "Flat",
			Height = 26,
			Background = { Color = "$Inset", Inset = TAB_INSET },
			Border = { Color = "$InsetLine", EdgeSize = 1, Inset = TAB_INSET },
			Hover = { Color = { 1, 1, 1, 0.08 }, Inset = TAB_INSET },
			Selected = {
				Background = { Color = { 1, 1, 1, 0.1 }, Inset = TAB_INSET },
				Border = { Color = { 1, 0.82, 0, 1 } },
			},
			Font = tabFont({ 0.8, 0.8, 0.8, 1 }),
			HighlightFont = tabFont({ 1, 1, 1, 1 }),
			SelectedFont = tabFont({ 1, 0.82, 0, 1 }),
			TextOffset = { X = 0, Y = -1 },
			SelectedTextOffset = { X = 0, Y = -1 },
		},
	},
})

-- The variables are read when BetterBags applies the theme, so a Reforged UI
-- theme change applies it again (unsaved: the saved choice is already ours).
ReforgedUI.RegisterThemeCallback(function()
	if sonata:GetCurrentThemeKey() == NAME then
		sonata:ApplyTheme(context:New("ReforgedUI_ThemeChanged"), NAME, false)
	end
end)
