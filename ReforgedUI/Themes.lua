-- Themes. The theme key is also the console's art folder (art/<key>);
-- `folder` is the top bar's folder in Media/ (see Media/README.md), and the
-- colours are used by the top bar's plates. `font` (optional) is a game font
-- for the top bar's menu buttons; without it they use GameFontNormalSmall.
--
-- Human, Orc, Undead and Night Elf are the original addon's Warcraft III art. The race
-- themes (Dwarf, Gnome, Tauren, Troll and the two Skyborne factions) are that
-- art recoloured by tools/make_race_themes.py: see Layout.BASE for which
-- faction each one is built from. Forsaken is Warcraft III's Forsaken console
-- cut like the original addon's Undead set (Undead keeps the Scourge console).

local _, ns = ...

local MEDIA = "Interface\\AddOns\\ReforgedUI\\Media\\"
local ART = "Interface\\AddOns\\ReforgedUI\\art\\"

ns.Themes = {
	human = {
		name = "Human",
		folder = "Human",
		title = { 1.0, 0.82, 0.0 },
		accent = { 0.45, 0.62, 1.0 },
		inset = { 0.02, 0.04, 0.10, 0.88 },
		insetLine = { 0.85, 0.68, 0.30, 0.9 },
		xp = { 0.58, 0.32, 0.86 },
		health = { 0.35, 1.0, 0.35 },
	},
	orc = {
		name = "Orc",
		folder = "Orc",
		title = { 1.0, 0.75, 0.25 },
		accent = { 0.95, 0.30, 0.15 },
		inset = { 0.08, 0.03, 0.02, 0.88 },
		insetLine = { 0.55, 0.50, 0.46, 0.9 },
		xp = { 0.80, 0.30, 0.12 },
		health = { 0.40, 1.0, 0.30 },
	},
	undead = {
		name = "Undead",
		folder = "Undead",
		title = { 0.85, 0.95, 0.80 },
		accent = { 0.35, 1.0, 0.65 },
		inset = { 0.04, 0.02, 0.07, 0.90 },
		insetLine = { 0.80, 0.77, 0.70, 0.9 },
		xp = { 0.30, 0.85, 0.55 },
		health = { 0.40, 1.0, 0.45 },
	},
	forsaken = {
		name = "Forsaken",
		folder = "Forsaken",
		title = { 0.82, 0.92, 0.70 },
		accent = { 0.62, 0.40, 0.85 },
		inset = { 0.05, 0.03, 0.07, 0.90 },
		insetLine = { 0.55, 0.45, 0.68, 0.9 },
		xp = { 0.55, 0.35, 0.80 },
		health = { 0.45, 1.0, 0.40 },
	},
	nightelf = {
		name = "Night Elf",
		folder = "NightElf",
		title = { 0.80, 0.92, 1.0 },
		accent = { 0.50, 0.92, 0.85 },
		inset = { 0.02, 0.05, 0.08, 0.88 },
		insetLine = { 0.55, 0.45, 0.33, 0.9 },
		xp = { 0.62, 0.45, 0.95 },
		health = { 0.40, 1.0, 0.55 },
	},
	dwarf = {
		name = "Dwarf",
		folder = "Dwarf",
		font = "Fonts\\SKURRI.TTF",
		title = { 1.0, 0.78, 0.45 },
		accent = { 0.88, 0.48, 0.16 },
		inset = { 0.07, 0.05, 0.04, 0.88 },
		insetLine = { 0.69, 0.48, 0.23, 0.9 },
		xp = { 0.88, 0.48, 0.16 },
		health = { 0.35, 1.0, 0.35 },
	},
	gnome = {
		name = "Gnome",
		folder = "Gnome",
		font = "Fonts\\ARIALN.TTF",
		title = { 0.75, 0.95, 1.0 },
		accent = { 0.37, 0.82, 0.88 },
		inset = { 0.04, 0.06, 0.08, 0.88 },
		insetLine = { 0.72, 0.42, 0.23, 0.9 },
		xp = { 0.88, 0.38, 0.62 },
		health = { 0.35, 1.0, 0.45 },
	},
	tauren = {
		name = "Tauren",
		folder = "Tauren",
		title = { 1.0, 0.86, 0.62 },
		accent = { 0.40, 0.70, 0.85 },
		inset = { 0.09, 0.06, 0.03, 0.88 },
		insetLine = { 0.79, 0.64, 0.48, 0.9 },
		xp = { 0.72, 0.27, 0.18 },
		health = { 0.40, 1.0, 0.30 },
	},
	troll = {
		name = "Troll",
		folder = "Troll",
		font = "Fonts\\SKURRI.TTF",
		title = { 0.90, 0.86, 0.72 },
		accent = { 0.18, 0.70, 0.68 },
		inset = { 0.05, 0.06, 0.05, 0.88 },
		insetLine = { 0.85, 0.80, 0.69, 0.9 },
		xp = { 0.55, 0.30, 0.65 },
		health = { 0.40, 1.0, 0.40 },
	},
	-- Skyborne, one theme per faction: powder-blue elven stone and twilight
	-- navy for both; High Order (Alliance) has silver trim and an arcane
	-- violet accent, Windshapers (Horde) gold trim and storm teal.
	highorder = {
		name = "Skyborne (High Order)",
		folder = "HighOrder",
		font = "Fonts\\MORPHEUS.TTF",
		title = { 0.90, 0.93, 0.97 },
		accent = { 0.55, 0.48, 0.88 },
		inset = { 0.06, 0.09, 0.16, 0.88 },
		insetLine = { 0.80, 0.85, 0.90, 0.9 },
		xp = { 0.55, 0.48, 0.88 },
		health = { 0.40, 1.0, 0.55 },
	},
	windshapers = {
		name = "Skyborne (Windshapers)",
		folder = "Windshapers",
		font = "Fonts\\MORPHEUS.TTF",
		title = { 0.88, 0.80, 0.54 },
		accent = { 0.18, 0.77, 0.70 },
		inset = { 0.06, 0.09, 0.16, 0.88 },
		insetLine = { 0.85, 0.78, 0.54, 0.9 },
		xp = { 0.18, 0.77, 0.70 },
		health = { 0.40, 1.0, 0.55 },
	},
}
ns.THEME_ORDER = { "human", "dwarf", "gnome", "nightelf", "highorder", "orc", "tauren", "troll", "forsaken", "undead", "windshapers" }

-- Theme choices that are not a theme of their own: "auto" follows the
-- character's race, "skyborne" the character's faction.
ns.THEME_ALIASES = { auto = true, skyborne = true }

-- Default theme per player race (the second return of UnitRace) for "auto".
-- Races from later expansions take the theme closest to their looks.
local RACE_THEME = {
	Human = "human", Dwarf = "dwarf", Gnome = "gnome", NightElf = "nightelf",
	Orc = "orc", Tauren = "tauren", Troll = "troll", Scourge = "forsaken",
	Skyborne = "skyborne",
	KulTiran = "human", LightforgedDraenei = "human", Draenei = "nightelf", Worgen = "nightelf",
	VoidElf = "nightelf", DarkIronDwarf = "dwarf", Mechagnome = "gnome", EarthenDwarf = "dwarf",
	Goblin = "orc", MagharOrc = "orc", HighmountainTauren = "tauren", ZandalariTroll = "troll",
	Vulpera = "tauren", BloodElf = "undead", Nightborne = "undead",
}

local function isSkyborne(name, raceFile)
	for _, s in ipairs({ name, raceFile }) do
		if type(s) == "string" then
			local l = s:lower()
			if l:find("skyborne", 1, true) or l:find("shen'dorei", 1, true) or l:find("shendorei", 1, true) then
				return true
			end
		end
	end
	return false
end

-- Skyborne's two race ids on Forever (UnitRace's third return): the faction
-- comes with the race, and so does the theme.
local SKYBORNE_IDS = { [95] = "highorder", [96] = "windshapers" }

-- The theme for "auto": from the race (Skyborne by its race id, else by its
-- token or name, else by the faction), otherwise from the faction.
function ns:RaceThemeKey(name, raceFile, faction, raceID)
	if SKYBORNE_IDS[raceID] then
		return SKYBORNE_IDS[raceID]
	end
	if isSkyborne(name, raceFile) then
		local l = type(name) == "string" and name:lower() or ""
		if l:find("windshaper", 1, true) then
			return "windshapers"
		elseif l:find("high order", 1, true) then
			return "highorder"
		end
		return "skyborne"
	end
	return RACE_THEME[raceFile] or (faction == "Horde" and "orc" or "human")
end

-- The theme a saved choice stands for: a theme key as it is, "skyborne" the
-- character's faction's Skyborne theme, anything else ("auto", or a theme
-- that no longer exists) the race default.
function ns:ResolveThemeKey(key)
	if self.Themes[key] then
		return key
	end
	local faction = UnitFactionGroup("player")
	if key ~= "skyborne" then
		local name, raceFile, raceID = UnitRace("player")
		key = self:RaceThemeKey(name, raceFile, faction, raceID)
	end
	if key == "skyborne" then
		return faction == "Horde" and "windshapers" or "highorder"
	end
	return key
end

function ns:Media(file, theme)
	theme = theme or self.theme
	if theme then
		return MEDIA .. theme.folder .. "\\" .. file
	end
	return MEDIA .. file
end

ns.MEDIA = MEDIA
ns.ART = ART
-- The original addon's font.
ns.FONT = ART .. "other\\fonts\\blq55.TTF"

-- A file under art/, e.g. "orc\\inventory\\inventory".
function ns:ArtPath(file)
	return ART .. file
end
