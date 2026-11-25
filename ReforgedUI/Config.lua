-- The options, as pages in the game's own options: Options > AddOns >
-- Reforged UI, a main page and one page per part of the UI (hero screen,
-- target, action bars, chat, top bar and minimap). The cogwheel in the
-- bottom-right corner of the chat area (which can be hidden) and /rui
-- config open them.
--
-- The original addon's "General" tab in its wording, kept minimal: the
-- console is always laid out like the original addon's "Center UI" with its
-- chat area and inventory, so the centre modes, chat placement and "Hide
-- bags" options are gone, and "Chat width" only matters where the screen is
-- too narrow for the original addon's chat area. The original addon's
-- "Customize" tab is not ported (see README.md).
--
-- Every option is a row of PAGES below: a new option is one more row on its
-- page (tools/smoke_test.lua checks that each is a known option, on one
-- page only, and that every row does what it says). The game's panel draws
-- them, lined up like its own options; each one is a proxy setting that
-- reads and writes db.consoleOpts (or db.theme) and runs the option's
-- `apply` when it changes.
--
-- Opening the panel goes through Settings.OpenToCategory, which hands it to
-- the game (C_SettingsUtil): addon code never calls the game's panel manager
-- (Show/HideUIPanel) itself, as that taints it, and Edit Mode, which the
-- panel manager opens and closes, then errors.

local _, ns = ...
local Config = ns:RegisterModule("config", {})

local PREFIX = "REFORGEDUI_" -- before every setting's variable name

local function relayout()
	if ns.ready then
		ns:Relayout()
	end
end

-- Edit Mode's places for the cast bar and the target's auras follow the
-- console's size, once a slider has settled (dragging one would otherwise
-- place them on every step).
local placeGen = 0
local function placeEditModeSoon(after)
	placeGen = placeGen + 1
	local gen = placeGen
	C_Timer.After(0.5, function()
		if gen == placeGen then
			ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
			if after then
				after()
			end
		end
	end)
end

-- The target's buffs follow the wall plate's size once its slider settles.
local plateGen = 0
local function plateAurasFollowSoon()
	plateGen = plateGen + 1
	local gen = plateGen
	C_Timer.After(0.5, function()
		if gen == plateGen then
			ns.modules.target:PlateAurasFollow()
		end
	end)
end

local function targetOn()
	return ns.modules.target.enabled and true or false
end

local function topBarOn()
	return ns.modules.topbar.enabled and true or false
end

----------------------------------------------------------------------------
-- The pages
--
-- Rows: { header = "..." } starts a section; options are
--   kind = "check" | "slider" | "choice" | "button"
--   key      the consoleOpts key (or get/set for anything else)
--   name, tip  label and tooltip
--   apply(v) runs after the value is saved
--   min, max, step, unit  (sliders; unit "%" by default, "" for none)
--   unset    (sliders) shown while the option is still false/unset
--   choices  (choice) { { value, label }, ... } or a function returning them
--   enabled  function: greyed out while it returns false
--   parent   key of the option this one hangs under (indented, greyed with it)
--   default  for the panel's Defaults button (else Core.lua's default)

local THEME_CHOICES = {
	{ "auto", "Auto (your race)" }, { "skyborne", "Skyborne (your faction)" },
	{ "human", "Human" }, { "dwarf", "Dwarf" }, { "gnome", "Gnome" }, { "nightelf", "Night Elf" },
	{ "highorder", "High Order" },
	{ "orc", "Orc" }, { "tauren", "Tauren" }, { "troll", "Troll" }, { "forsaken", "Forsaken" },
	{ "undead", "Scourge" }, { "windshapers", "Windshapers" },
}

local function iconChoices()
	local hero, list = ns.modules.hero, {}
	for _, kind in ipairs(hero.ICON_KINDS) do
		list[#list + 1] = { kind, hero.ICON_NAMES[kind] or kind }
	end
	return list
end

-- One stat icon (1-4) of this class's four on the hero screen.
local function statIcon(i)
	local DEFAULT_ICONS = { "main", "none", "none", "armor" }
	return {
		kind = "choice", id = "statIcon" .. i, name = ns.modules.hero.ICON_TITLES[i], choices = iconChoices,
		tip = "What this stat icon on the hero screen shows, for this class. Right-clicking the icon itself changes it too.",
		get = function() return ns.modules.hero:IconChoices()[i] or "none" end,
		set = function(v) ns.modules.hero:SetIconChoice(i, v) end,
		default = DEFAULT_ICONS[i],
	}
end

-- The gold tooltip's saved characters, to forget one: pick it, then the
-- button. The one logged in isn't offered (it would come straight back).
local NO_CHARACTER = ""
local goldPick = NO_CHARACTER

local function goldEntries()
	local list = {}
	for _, c in ipairs(ns.modules.topbar:SavedCharacters()) do
		if not c.current then
			list[#list + 1] = c
		end
	end
	return list
end

local function goldValue(c)
	return c.key
end

local function goldChoices()
	local entries = goldEntries()
	local list = { { NO_CHARACTER, #entries > 0 and "Pick a character" or "No other characters saved" } }
	for _, c in ipairs(entries) do
		list[#list + 1] = { goldValue(c), ("%s (%s)"):format(c.name, c.faction) }
	end
	return list
end

local function goldPicked()
	for _, c in ipairs(goldEntries()) do
		if goldValue(c) == goldPick then
			return c
		end
	end
end

Config.PAGES = {
	{
		name = "Reforged UI", -- the main page
		{ header = "Theme" },
		{
			kind = "choice", id = "theme", name = "Theme", choices = THEME_CHOICES, default = "auto",
			tip = "The race whose art the console wears. Auto follows your character's race, Skyborne your faction.",
			get = function() return ns.db.theme end,
			set = function(v)
				ns.db.theme = v
				ns:ApplyTheme()
			end,
		},
		{ header = "Size and look" },
		{
			kind = "slider", key = "uiSize", name = "UI size", min = ns.UI_SIZE_MIN, max = ns.UI_SIZE_MAX,
			tip = "The console and the top bar, smaller than their usual size.",
			apply = function()
				relayout()
				placeEditModeSoon()
			end,
		},
		{
			kind = "slider", key = "uiScale", name = "UI scale", min = ns.Layout.SCALE_MIN, max = ns.Layout.SCALE_MAX,
			unit = "", tip = "The original addon's UI scale (240-270).", apply = relayout,
		},
		{
			kind = "slider", key = "transparency", name = "Console transparency", min = 0, max = 100,
			tip = "See-through console art; buttons, icons and text stay opaque.",
			apply = function() ns.modules.console:ApplyTransparency() end,
		},
		{
			kind = "check", key = "themeTooltips", name = "Themed tooltips",
			tip = "The game's tooltips in the theme's frame, like the damage meter.",
			apply = function(on) ns.modules.tooltip:SetEnabled(on) end,
		},
		{
			kind = "check", key = "hideCog", name = "Hide options cogwheel",
			tip = "No cogwheel in the chat area; these options still open with /rui config or Options > AddOns.",
			set = function(on) Config:SetCogShown(not on) end,
		},
		{ header = "More" },
		{
			kind = "button", name = "Reload the UI", text = "Reload UI", click = function() ReloadUI() end,
			tip = "Some options (marked \"reload\") take effect after a reload.",
		},
	},
	{
		name = "Hero screen",
		{ header = "Health and power" },
		{
			kind = "check", key = "healthPercent", name = "Show HP as %",
			apply = function() ns.modules.hero:Update() end,
		},
		{
			kind = "check", key = "powerPercent", name = "Show power as %",
			apply = function() ns.modules.hero:Update() end,
		},
		{
			kind = "slider", key = "hpWarning", name = "HP warning threshold", min = 0, max = 100,
			tip = "Below this share of your health the console warns you.", apply = relayout,
		},
		{ header = "Portrait" },
		{
			kind = "check", key = "stopAnimation", name = "Stop portrait animation (reload)",
			apply = function(on)
				ns:AskReload(on and "the portrait stops moving." or "the portrait moves again.")
			end,
		},
		{
			kind = "slider", key = "portraitX", name = "Portrait position X", min = 0, max = 300, unit = "",
			tip = "100 is where the original addon puts it.", apply = relayout,
		},
		{
			kind = "slider", key = "portraitY", name = "Portrait position Y", min = 0, max = 300, unit = "",
			tip = "100 is where the original addon puts it.", apply = relayout,
		},
		{
			kind = "slider", key = "portraitScale", name = "Portrait zoom", min = 0, max = 35, unit = "",
			tip = "The original addon's portrait scale (0-35).", apply = relayout,
		},
		{ header = "Stat icons (this class)" },
		statIcon(1), statIcon(2), statIcon(3), statIcon(4),
		{ header = "Experience bar" },
		{
			kind = "check", key = "repBar", name = "Reputation bar",
			tip = "The watched faction's strip under the experience bar. Right-click the experience bar for its rested colour.",
			apply = relayout,
		},
	},
	{
		name = "Target",
		{ header = "Target display" },
		{
			kind = "choice", key = "targetMode", name = "Show the target", enabled = targetOn,
			choices = { { "swap", "On the hero screen" }, { "plate", "On a plate on the wall" } },
			tip = "On the hero screen (Warcraft III's swap) or on a plate on the wall above the stats.",
			get = function() return ns.modules.target:Mode() end,
			set = function(v) ns.modules.target:SetMode(v) end,
		},
		{
			kind = "slider", key = "targetAuraSize", name = "Target aura size", enabled = targetOn,
			min = ns.TARGET_AURA_SIZE_MIN, max = ns.TARGET_AURA_SIZE_MAX, step = 5, unset = ns.TARGET_AURA_SIZE_MIN,
			tip = "Bigger buff and debuff icons for your target on the wall (Edit Mode's Frame Size for the Target Frame).",
			apply = function() placeEditModeSoon(function() ns:SayTargetAuraSize() end) end,
		},
		{
			kind = "check", key = "targetBuffsFirst", name = "Target buffs first", enabled = targetOn,
			tip = "Your target's buffs on the bottom rows, nearest its portrait, and its debuffs after them.",
			apply = function(on) ns.modules.target:SetBuffsFirst(on) end,
		},
		{
			kind = "check", key = "targetThreat", name = "Show threat on target", enabled = targetOn,
			tip = "Your threat on the target (as in its tooltip) over its portrait and on the target bar.",
			set = function(on) ns.modules.target:SetThreatShown(on) end,
		},
		{ header = "Wall plate" },
		{
			kind = "slider", key = "targetPlateSize", name = "Wall plate size", enabled = targetOn,
			min = ns.TARGET_PLATE_SIZE_MIN, max = ns.TARGET_PLATE_SIZE_MAX, step = 5,
			tip = "The target plate on the wall, bigger or smaller. The target's buffs follow once the slider settles.",
			set = function(v) ns.modules.target:SetPlateSize(v, true) end,
			apply = function() plateAurasFollowSoon() end,
		},
		{
			kind = "check", key = "targetPlateMirror", name = "Mirror wall plate", enabled = targetOn,
			tip = "The plate turned the other way round.",
			set = function(on) ns.modules.target:SetPlateMirrored(on) end,
		},
		{
			kind = "button", name = "Wall plate position", text = "Back on the wall",
			tip = "Puts the wall plate back after moving it (Shift-drag, or in Edit Mode).",
			click = function() ns.modules.target:ResetPlateSpot() end,
		},
		{
			kind = "check", key = "targetToT", name = "Show target of target", enabled = targetOn,
			tip = "The target of target icon beside the target display. Turn it off if it gets in the way;"
				.. " the target of target bar below can take its place. Changes once out of combat.",
			get = function() return ns.modules.target:ToTShown() end,
			set = function(on) ns.modules.target:SetToTShown(on) end,
		},
		{ header = "Target bars" },
		{
			kind = "check", key = "targetBar", name = "Target bar", enabled = targetOn,
			tip = "A free-standing target health and power bar: hold Shift and drag it, or move it in Edit Mode.",
			apply = function(on)
				ns.modules.target:SetBarEnabled(on)
				if on then
					ns:Print("target bar on: hold Shift and drag it where you want it, or move it in Edit Mode.")
				end
			end,
		},
		{
			kind = "check", key = "totBar", name = "Target of target bar", enabled = targetOn,
			tip = "The same for your target's target.",
			apply = function(on)
				local target = ns.modules.target
				target:SetBarEnabled(on, target.totBar)
				if on then
					ns:Print("target of target bar on: hold Shift and drag it where you want it, or move it in Edit Mode.")
				end
			end,
		},
		{
			kind = "slider", key = "targetBarSize", name = "Target bar size", enabled = targetOn,
			min = ns.TARGET_BAR_SIZE_MIN, max = ns.TARGET_BAR_SIZE_MAX, tip = "Both target bars.",
			set = function(v) ns.modules.target:SetBarSize(v) end,
		},
	},
	{
		name = "Action bars",
		{ header = "Action bars" },
		{
			kind = "check", key = "hideGrid", name = "Hide actionbar grid texture", apply = relayout,
		},
		{
			kind = "check", key = "editModeBars", name = "Let Edit Mode place action bars 1-3",
			tip = "Bars 1-3 stay on their own Edit Mode bars instead of the console's grid (reload).",
			apply = function(on)
				ns.db.consoleOpts.barsPlaced = false
				if on then
					ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
				end
				ns:AskReload(on and "action bars 1-3 now stay on their Edit Mode bars (grid art hidden)."
					or "action bars 1-3 go back into the console's grid.")
			end,
		},
		{ header = "Stance buttons" },
		{
			kind = "check", key = "hideStance", name = "Hide stance buttons",
			tip = "Hidden on the console; their key bindings still work. Move them in Edit Mode.",
			apply = function(on) ns.modules.actionbars:SetStanceShown(not on) end,
		},
		{
			kind = "check", key = "leaveStance", name = "Leave stance buttons to my bar addon (reload)",
			tip = "Leave them where Blizzard's stance bar or another bar addon puts them.",
			apply = function(on)
				ns:AskReload(on and "the stance buttons are left to Blizzard or your bar addon."
					or "the stance buttons go back on the console's wall.")
			end,
		},
	},
	{
		name = "Chat",
		{ header = "Chat area" },
		{
			kind = "slider", key = "chatWiden", name = "Chat width", min = 0, max = 100,
			tip = "A wider chat area on screens narrower than 16:9: the console shrinks to make room.",
			apply = function()
				relayout()
				placeEditModeSoon()
			end,
		},
		{
			kind = "slider", key = "chatUp", name = "Chat height", min = 0, max = 150, unit = "",
			tip = "Raises the chat area (and the cast bar above it), in console units.",
			apply = function()
				relayout()
				placeEditModeSoon()
			end,
		},
		{ header = "Chat window" },
		{
			kind = "check", key = "chatInputAbove", name = "Chat input above chat", apply = relayout,
		},
		{
			kind = "check", key = "freeChat", name = "Let me move and resize the chat window",
			apply = function(on)
				ns.db.consoleOpts.chatPlaced = false
				relayout()
				if on then
					ns:Print("the chat window is yours to move and resize: unlock it from its tab's menu, or use Edit Mode.")
				end
			end,
		},
		{
			kind = "check", key = "hideChatIcons", name = "Hide chat icons (reload)",
			apply = function(on)
				ns:AskReload(on and "the chat window's buttons are hidden." or "the chat window's buttons come back.")
			end,
		},
	},
	{
		name = "Top bar and minimap",
		{ header = "Top bar" },
		{
			kind = "check", key = "hideTopBar", name = "Hide top bar",
			tip = "Without it, the menu buttons and the time stand above the minimap.",
			set = function(on) ns:SetTopBarShown(not on) end,
		},
		{ header = "Clock" },
		{
			kind = "choice", key = "clockTime", name = "Time under the clock", enabled = topBarOn,
			choices = { { "server", "Server time" }, { "local", "Local time" }, { "off", "Hidden" } },
			get = function() return ns.modules.topbar:TimeMode() end,
			set = function(v) ns.modules.topbar:SetTimeMode(v) end,
		},
		{
			kind = "choice", key = "clockHours", name = "Clock", parent = "clockTime",
			enabled = function() return topBarOn() and ns.modules.topbar:TimeMode() ~= "off" end,
			choices = { { 24, "24-hour" }, { 12, "12-hour" } },
			get = function() return ns.modules.topbar:TimeHours() end,
			set = function(v) ns.modules.topbar:SetTimeHours(v) end,
		},
		{ header = "Gold tooltip" },
		{
			kind = "choice", id = "goldCharacter", name = "Saved character", choices = goldChoices,
			tip = "A character whose gold the gold feed's tooltip lists. Pick an old one, then Forget.",
			get = function() return goldPicked() and goldPick or NO_CHARACTER end,
			set = function(v) goldPick = v end,
			default = NO_CHARACTER,
		},
		{
			kind = "button", name = "Forget saved character", text = "Forget",
			tip = "Takes the character picked above out of the gold tooltip. It comes back if you log it in.",
			click = function()
				local c = goldPicked()
				if not c then
					ns:Print("pick a saved character first.")
					return
				end
				ns.modules.topbar:ConfirmForget(c, function()
					goldPick = NO_CHARACTER
					Config:Refresh()
				end)
			end,
		},
		{ header = "Minimap" },
		{
			kind = "choice", key = "zoneText", name = "Zone text",
			choices = { { 1, "Below the minimap" }, { 2, "Above the minimap" }, { 3, "Hidden" } },
			get = function() return ns.db.consoleOpts.zoneText or 1 end,
			apply = relayout,
		},
	},
}

----------------------------------------------------------------------------
-- Building the pages

local function round(v, step)
	step = step or 1
	return math.floor(v / step + 0.5) * step
end

-- The option's current value, as the panel shows it.
local function getter(spec)
	if spec.get then
		return spec.get
	end
	local key = spec.key
	if spec.kind == "check" then
		return function() return ns.db.consoleOpts[key] and true or false end
	elseif spec.kind == "slider" then
		return function()
			local v = ns.db.consoleOpts[key]
			return type(v) == "number" and v or spec.unset or spec.min
		end
	end
	return function() return ns.db.consoleOpts[key] end
end

-- Saves a new value from the panel and applies it.
function Config:Set(spec, v)
	if spec.kind == "slider" then
		v = math.max(spec.min, math.min(spec.max, round(v, spec.step)))
	elseif spec.kind == "check" then
		v = v and true or false
	end
	if spec.set then
		spec.set(v)
	else
		ns.db.consoleOpts[spec.key] = v
	end
	if spec.apply then
		spec.apply(v)
	end
end

local function defaultOf(spec, get)
	local v = spec.default
	if v == nil and spec.key then
		v = ns:OptionDefault(spec.key)
	end
	if spec.kind == "slider" and type(v) ~= "number" then
		v = spec.unset or spec.min
	elseif spec.kind == "check" then
		v = v and true or false
	elseif v == nil then
		v = get()
	end
	return v
end

local function choiceOptions(spec)
	return function()
		local container = Settings.CreateControlTextContainer()
		local list = type(spec.choices) == "function" and spec.choices() or spec.choices
		for _, c in ipairs(list) do
			container:Add(c[1], c[2])
		end
		return container:GetData()
	end
end

local function sliderOptions(spec)
	local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
	local unit = spec.unit or "%"
	local label = _G.MinimalSliderWithSteppersMixin and _G.MinimalSliderWithSteppersMixin.Label
	if label and options.SetLabelFormatter then
		options:SetLabelFormatter(label.Right, function(v) return round(v, spec.step) .. unit end)
	end
	return options
end

function Config:AddRow(category, layout, spec)
	if spec.header then
		local header = _G.CreateSettingsListSectionHeaderInitializer
		if header then
			layout:AddInitializer(header(spec.header))
		end
		return
	end
	if spec.kind == "button" then
		local button = _G.CreateSettingsButtonInitializer
		if button then
			layout:AddInitializer(button(spec.name, spec.text, spec.click, spec.tip, true))
		end
		return
	end
	local id = spec.id or spec.key
	assert(not self.specs[id], "option " .. id .. " is on one page only")
	local get = getter(spec)
	local vartype = spec.kind == "check" and "boolean" or spec.kind == "slider" and "number" or type(defaultOf(spec, get))
	local setting = Settings.RegisterProxySetting(category, PREFIX .. id, vartype, spec.name, defaultOf(spec, get), get,
		function(v) self:Set(spec, v) end)
	local init
	if spec.kind == "check" then
		init = Settings.CreateCheckbox(category, setting, spec.tip)
	elseif spec.kind == "slider" then
		init = Settings.CreateSlider(category, setting, sliderOptions(spec), spec.tip)
	else
		init = Settings.CreateDropdown(category, setting, choiceOptions(spec), spec.tip)
	end
	if spec.parent and self.initializers[spec.parent] and init.SetParentInitializer then
		init:SetParentInitializer(self.initializers[spec.parent], spec.enabled)
	elseif spec.enabled and init.AddModifyPredicate then
		init:AddModifyPredicate(spec.enabled)
	end
	self.specs[id], self.settings[id], self.initializers[id] = spec, setting, init
end

-- Options > AddOns > Reforged UI, a page under it for each part of the UI.
function Config:RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
		return
	end
	self.specs, self.settings, self.initializers, self.pages = {}, {}, {}, {}
	local main
	for i, page in ipairs(self.PAGES) do
		local category, layout
		if i == 1 then
			category, layout = Settings.RegisterVerticalLayoutCategory(page.name)
			main = category
		else
			category, layout = Settings.RegisterVerticalLayoutSubcategory(main, page.name)
		end
		self.pages[i] = category
		for _, spec in ipairs(page) do
			self:AddRow(category, layout, spec)
		end
	end
	Settings.RegisterAddOnCategory(main)
	self.category = main
end

-- Shows what the options are now (after a /rui command, a right-click menu
-- or a module changed one).
function Config:Refresh()
	if not self.settings then
		return
	end
	for _, setting in pairs(self.settings) do
		if setting.NotifyUpdate then
			setting:NotifyUpdate()
		end
	end
end

-- The game's options, on our main page.
function Config:Open()
	if self.category then
		Settings.OpenToCategory(self.category:GetID())
	else
		ns:Print("this client has no options pages for addons; type /rui for the commands.")
	end
end

----------------------------------------------------------------------------
-- The cogwheel: in the bottom-right corner of the chat area (Layout.lua
-- leaves room for it beside the input box), dimmed until the mouse is over
-- it.

local COG_IDLE = 0.55

function Config:BuildCogwheel()
	local hover = CreateFrame("Button", "ReforgedUICogwheel", UIParent)
	hover:SetSize(30, 30)
	hover:SetPoint("BOTTOMRIGHT", 7, -6)
	hover:SetFrameStrata("HIGH") -- above the chat frame
	local icon = hover:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	icon:SetTexture(ns:ArtPath("other\\cogwheel"))
	icon:SetAlpha(COG_IDLE)
	hover:SetScript("OnEnter", function() icon:SetAlpha(1) end)
	hover:SetScript("OnLeave", function() icon:SetAlpha(COG_IDLE) end)
	hover:SetScript("OnMouseDown", function() icon:SetVertexColor(0.75, 0.75, 0.75, 1) end)
	hover:SetScript("OnMouseUp", function() icon:SetVertexColor(1, 1, 1, 1) end)
	hover:SetScript("OnClick", function() self:Open() end)
	self.cogwheel = hover
	hover:SetShown(not ns.db.consoleOpts.hideCog)
end

function Config:OnLayout(L)
	if self.cogwheel and L.cogwheel then
		ns:PlaceRect(self.cogwheel, L.cogwheel)
		self.cogwheel:SetShown(not ns.db.consoleOpts.hideCog)
	end
end

-- Hides or shows the cogwheel (the chat input box takes its room).
function Config:SetCogShown(on)
	ns.db.consoleOpts.hideCog = not on
	if self.cogwheel then
		self.cogwheel:SetShown(on)
	end
	ns:Relayout()
	self:Refresh()
	ns:Print(on and "options cogwheel shown in the chat area."
		or "options cogwheel hidden: open the options with /rui config or Options > AddOns > Reforged UI (/rui cog on brings it back).")
end

function Config:OnEnable()
	self:RegisterSettings()
	self:BuildCogwheel()
end
