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
-- BetterBags Next (BetterBags' new full-height bags) has its own themes and
-- its own theme list: the second half of this file adds "Reforged UI" there
-- too, when the BetterBags in use has Next themes.
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

-- BetterBags Next ------------------------------------------------------------
--
-- Next draws its panels from Next themes (BetterBags' sonata/next.lua and
-- sonata/themes/next/): data only, no functions anywhere, every theme
-- inheriting what it leaves out from Next's Default. So the theme below holds
-- values, not variables: refresh() writes the current Reforged UI theme's
-- colours and art into it, and BetterBags reads them each time it applies the
-- theme (it resolves a new copy every time). A Reforged UI theme change
-- refreshes it and, while it is the Next theme in use, applies it again.
--
-- The look: the panel's body in the theme's dark inset, the trim all round
-- it as ornaments (Next's art pieces anchored to the body's sides and
-- corners, mirrored on the bank's left-hand panel): join.tga in the corners,
-- beam.tga tiled along the top and bottom and post.tga down the sides, both
-- from make_bb_frame.py. The trim sits inside the body, so the tabs down its
-- inner side stay clear of it; the fill stops under the trim as the windows'
-- does. The rail under the title, gold titles in our font, and Next's
-- sparkles, ribbon and title cloud left out.
--
-- Older BetterBags (no Next themes) just skips this.

local sonataNext = BetterBags:GetModule("SonataNext", true)
if not (sonataNext and sonataNext.RegisterTheme and sonataNext.ApplyTheme and sonata.RegisterNextTheme) then
	return
end

local TRIM_EDGE = ReforgedUI.TRIM_EDGE or EDGE
local BEAM_TILE = 256 / 32 * TRIM_EDGE -- beam.tga is 256 x 32
-- Our font is Latin only: elsewhere Next draws these roles in the client's.
local LATIN = { "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR" }

local function nextFont(size, color, shadow)
	return { File = ReforgedUI.FONT, Locales = LATIN, Size = size, Color = color, Shadow = shadow }
end

-- An ornament: art at a place on the body (Next's Panel.Ornaments).
local function piece(point, coords, size)
	local o = { Point = point, TexCoords = coords, Layer = "BORDER", SubLevel = 1 }
	for k, v in pairs(size) do
		o[k] = v
	end
	return o
end

-- The pieces drawn for the backpack, whose inner side is the left one; Next
-- mirrors them on panels whose inner side is the right one.
local CORNERS = {
	piece("TOPINNER", { 0, 1, 0, 1 }, { Width = TRIM_EDGE, Height = TRIM_EDGE }),
	piece("TOPOUTER", { 1, 0, 0, 1 }, { Width = TRIM_EDGE, Height = TRIM_EDGE }),
	piece("BOTTOMINNER", { 0, 1, 1, 0 }, { Width = TRIM_EDGE, Height = TRIM_EDGE }),
	piece("BOTTOMOUTER", { 1, 0, 1, 0 }, { Width = TRIM_EDGE, Height = TRIM_EDGE }),
}
local BEAMS = {
	piece("TOP", { 0, 1, 0, 1 }, { Height = TRIM_EDGE, Start = TRIM_EDGE, End = TRIM_EDGE, Tile = BEAM_TILE }),
	piece("BOTTOM", { 0, 1, 1, 0 }, { Height = TRIM_EDGE, Start = TRIM_EDGE, End = TRIM_EDGE, Tile = BEAM_TILE }),
}
-- post.tga has its outer side on the left.
local POSTS = {
	piece("INNER", { 0, 1, 0, 1 }, { Width = TRIM_EDGE, Start = TRIM_EDGE, End = TRIM_EDGE }),
	piece("OUTER", { 1, 0, 0, 1 }, { Width = TRIM_EDGE, Start = TRIM_EDGE, End = TRIM_EDGE }),
}
-- The rail under the title, between the title row and the search box.
local NEXT_RAIL = piece("TOP", nil, { Height = RAIL_H, Start = TRIM_EDGE + 4, End = TRIM_EDGE + 4, Y = 58 })

local ornaments = {}
for _, list in ipairs({ CORNERS, BEAMS, POSTS }) do
	for _, o in ipairs(list) do
		ornaments[#ornaments + 1] = o
	end
end
ornaments[#ornaments + 1] = NEXT_RAIL

local palette = {
	White = { 1, 1, 1, 1 },
	Text = { 0.95, 0.93, 0.88, 1 },
	Muted = { 0.68, 0.66, 0.6, 1 },
}

local nextTheme = {
	Name = NAME,
	DisplayName = "Reforged UI",
	Description = "Your Reforged UI theme: the race's trim around the bags, in its colours, following it as you switch.",

	Palette = palette,

	Fonts = {
		Title = nextFont(22, "Gold", true),
		Section = nextFont(13, "Gold", true),
		SectionRecent = nextFont(13, "White", true),
		Tab = nextFont(12, "Muted"),
		TabSelected = nextFont(12, "Gold", true),
		ConfirmTitle = nextFont(18, "Gold", true),
		DialogTitle = nextFont(16, "Gold", true),
		SettingsBrand = nextFont(20, "Gold", true),
		SettingsTitle = nextFont(24, "Gold", true),
	},

	-- Room for the trim: the footer's text up off the bottom beam.
	Layout = {
		Footer = 46,
		FooterText = 20,
		FooterMoney = 18,
	},

	-- No bounce as a panel opens or comes in: its outer side's trim would
	-- swing off the screen edge.
	Motion = { Ease = { Open = "outCubic", Enter = "outCubic" } },

	Panel = {
		-- The fill stops under the trim, as the windows' inset does.
		Fill = { Color = "Body", Inset = around(OUT) },
		Feather = false,
		Edge = false,
		Wash = { Height = 200, BlendMode = "ADD" },
		DropGlow = { Color = "Gold", Alpha = 0.12, BlendMode = "ADD" },
		Ornaments = ornaments,
	},

	Header = {
		Ribbon = false,
		Cloud = false,
		Spark = false,
		TitleGlow = { Texture = "Glow", Color = "Gold", Alpha = 0.2, X = 24, Y = 14, BlendMode = "ADD" },
		Buttons = { Color = "ButtonIcon", HoverColor = "White", ArtColor = "White", ArtHoverColor = "White" },
	},

	Sparkles = false,
	Chain = { Braid = false },

	-- Solid tabs edged in the inset line, the selected one in gold.
	Tabs = {
		Fade = 1,
		Glow = { Color = "Gold", BlendMode = "ADD", Drop = 0.3, Pulse = 0.8 },
		Edge = { Color = "Lavender", Alpha = 0.6, Size = 1 },
		SelectedEdge = { Color = "Gold", Alpha = 1, Size = 1 },
	},

	Search = {
		Icon = { Color = "Lavender", Idle = 0.85, Active = 1, FocusColor = "Gold" },
	},
}

local function shade(c, d, a)
	return {
		math.min(1, c[1] + d),
		math.min(1, c[2] + d),
		math.min(1, c[3] + d),
		a or 1,
	}
end

-- Writes the current Reforged UI theme into the Next theme: its colours, its
-- trim's art and the post's period.
local function refresh()
	local _, theme = ReforgedUI.GetTheme()
	local inset = theme and theme.inset or DEFAULT_INSET
	local line = theme and theme.insetLine or DEFAULT_LINE
	local title = theme and theme.title or { 1, 0.82, 0 }
	palette.Body = shade(inset, 0, 0.94)
	palette.Wash = shade(line, 0, 0.08)
	palette.Gold = shade(title, 0)
	-- Next's edges, lines and links are "Lavender": ours are the inset line.
	palette.Lavender = shade(line, 0)
	palette.ButtonIcon = shade(title, 0)
	palette.Bead = shade(title, 0)
	palette.Tab = shade(inset, 0.04, 0.94)
	palette.TabSelected = shade(inset, 0.12, 0.96)
	palette.Card = shade(inset, 0.04, 0.98)
	palette.SearchFill = shade(inset, 0.06)
	palette.SearchFillFocus = shade(inset, 0.1)
	palette.ControlFill = shade(inset, 0.06)
	palette.ControlHover = shade(inset, 0.1)
	palette.ControlPressed = shade(inset, 0.03)
	palette.Track = shade(inset, 0.14)

	local join, beam, post = ReforgedUI.TrimArt("join"), ReforgedUI.TrimArt("beam"), ReforgedUI.TrimArt("post")
	local period = ReforgedUI.TrimPostPeriod and ReforgedUI.TrimPostPeriod() or 4 * TRIM_EDGE
	for _, o in ipairs(CORNERS) do
		o.Texture = join
	end
	for _, o in ipairs(BEAMS) do
		o.Texture = beam
	end
	for _, o in ipairs(POSTS) do
		o.Texture = post
		o.Tile = period
	end
	NEXT_RAIL.Texture = ReforgedUI.TrimArt("rail")
end

refresh()
sonata:RegisterNextTheme(nextTheme)

-- Every theme change refreshes it (so it is right whenever BetterBags first
-- applies it), and applies it again, unsaved, while it is Next's theme.
ReforgedUI.RegisterThemeCallback(function()
	refresh()
	if sonataNext:GetCurrentThemeKey() == NAME then
		sonataNext:ApplyTheme(context:New("ReforgedUI_ThemeChanged"), NAME, false)
	end
end)
