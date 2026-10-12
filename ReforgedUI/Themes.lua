-- Faction themes. Each theme points at a folder in Media/ that holds the same
-- set of files (see Media/README.md), plus the colours used for text, bars and
-- the recessed "screens" of the console.

local _, ns = ...

local MEDIA = "Interface\\AddOns\\ReforgedUI\\Media\\"

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
}
ns.THEME_ORDER = { "human", "orc", "undead", "nightelf" }

-- Default theme per player race (the second return of UnitRace) for "auto".
local RACE_THEME = {
	Human = "human", Dwarf = "human", Gnome = "human", KulTiran = "human",
	DarkIronDwarf = "human", Mechagnome = "human", LightforgedDraenei = "human",
	NightElf = "nightelf", Draenei = "nightelf", Worgen = "nightelf", VoidElf = "nightelf",
	Orc = "orc", Troll = "orc", Tauren = "orc", Goblin = "orc", MagharOrc = "orc",
	HighmountainTauren = "orc", ZandalariTroll = "orc", Vulpera = "orc",
	Scourge = "undead", BloodElf = "undead", Nightborne = "undead",
}

function ns:ResolveThemeKey(key)
	if self.Themes[key] then
		return key
	end
	local _, race = UnitRace("player")
	if race and RACE_THEME[race] then
		return RACE_THEME[race]
	end
	return UnitFactionGroup("player") == "Horde" and "orc" or "human"
end

function ns:Media(file, theme)
	theme = theme or self.theme
	if theme then
		return MEDIA .. theme.folder .. "\\" .. file
	end
	return MEDIA .. file
end

ns.MEDIA = MEDIA
