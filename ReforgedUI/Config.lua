-- The original addon's options menu, opened with the cogwheel in the bottom-right corner of
-- the chat area (or /rui config). The original addon's
-- "General" tab in its wording, kept minimal: the console is always laid out
-- like the original addon's "Center UI" with its chat area and inventory, so the centre
-- modes, chat width, chat placement and "Hide bags" options are gone.
-- The original addon's "Customize" tab is not ported (see README.md).

local _, ns = ...
local Config = ns:RegisterModule("config", {})

local W, H = 650, 530

-- Two rows: Alliance races, then Horde races. "Skyborne" picks the
-- character's faction's Skyborne theme; "Auto" the character's race's theme.
local THEME_BUTTONS = {
	{ "human", "Human" }, { "dwarf", "Dwarf" }, { "gnome", "Gnome" }, { "nightelf", "Night Elf" },
	{ "highorder", "High Order" }, { "skyborne", "Skyborne" },
	{ "orc", "Orc" }, { "tauren", "Tauren" }, { "troll", "Troll" }, { "undead", "Undead" },
	{ "windshapers", "Windshapers" }, { "auto", "Auto" },
}
local THEME_COLUMNS = 6
local RESTED_COLORS = {
	{ "Purple", { 0.5, 0, 0.5, 0.5 } },
	{ "Blue", { 0, 0, 1, 0.5 } },
	{ "None", { 0, 0, 0, 0 } },
}
local ICON_ROWS = { "Top left weapon icon", "Top right weapon icon", "Bottom right weapon icon" }
local ICON_BUTTONS = {
	{ "main", "Main" }, { "offhand", "Offhand" }, { "ranged", "Ranged" }, { "ammo", "Ammo" },
	{ "spell", "Spell" }, { "heal", "Heal" }, { "none", "None" },
}
local ZONE_TEXT = { "Zone text: bottom", "Zone text: top", "Zone text: hidden" }

local function relayout()
	if ns.ready then
		ns:Relayout()
	end
end

----------------------------------------------------------------------------
-- Widgets

local function button(parent, text, w, x, y, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function label(parent, text, x, y, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- Checkbox bound to db.consoleOpts[key]; `after` runs when it changes.
function Config:Check(text, key, x, y, after)
	local cb = CreateFrame("CheckButton", nil, self.frame, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", x, y)
	local fs = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetText(text)
	cb:SetScript("OnClick", function(b)
		if key then
			ns.db.consoleOpts[key] = b:GetChecked() and true or false
		end
		if after then
			after(b:GetChecked())
		end
		self:Refresh()
	end)
	cb.key = key
	self.checks[#self.checks + 1] = cb
	return cb
end

-- Number box bound to db.consoleOpts[key]; applied with Enter or the Apply button.
function Config:Edit(text, key, x, y, w)
	label(self.frame, text, x, y)
	local eb = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
	eb:SetSize(w or 60, 20)
	eb:SetPoint("TOPLEFT", x + 6, y - 16)
	eb:SetAutoFocus(false)
	eb:SetScript("OnEnterPressed", function(e)
		e:ClearFocus()
		self:Apply()
	end)
	eb:SetScript("OnEscapePressed", function(e)
		e:ClearFocus()
		self:Refresh()
	end)
	eb.key = key
	self.edits[#self.edits + 1] = eb
	return eb
end

----------------------------------------------------------------------------

function Config:Build()
	local f = CreateFrame("Frame", "ReforgedUIConfig", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetPoint("LEFT", 200, 0)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 32, insets = { left = 10, right = 10, top = 10, bottom = 10 },
	})
	f:SetBackdropColor(0, 0, 0, 0.75)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnShow", function() self:Refresh() end)
	f:Hide()
	tinsert(UISpecialFrames, "ReforgedUIConfig")
	self.frame = f
	self.checks, self.edits = {}, {}

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	label(f, "Reforged UI", 20, -18, "GameFontNormalLarge")

	-- Themes.
	self.themeButtons = {}
	for i, spec in ipairs(THEME_BUTTONS) do
		local col, row = (i - 1) % THEME_COLUMNS, math.floor((i - 1) / THEME_COLUMNS)
		self.themeButtons[i] = button(f, spec[2], 100, 20 + col * 102, -44 - row * 26, function()
			ns.db.theme = spec[1]
			ns:ApplyTheme()
			self:Refresh()
		end)
		self.themeButtons[i].key = spec[1]
	end

	-- Checkboxes, left column.
	local x, y = 20, -104
	local function nextY()
		y = y - 26
		return y + 26
	end
	self:Check("Hide actionbar grid texture", "hideGrid", x, nextY(), relayout)
	self:Check("Show HP as %", "healthPercent", x, nextY(), function() ns.modules.hero:Update() end)
	self:Check("Show power as %", "powerPercent", x, nextY(), function() ns.modules.hero:Update() end)
	self:Check("Hide chat icons (reload)", "hideChatIcons", x, nextY())
	self:Check("Stop portrait animation (reload)", "stopAnimation", x, nextY())
	self:Check("Chat input above chat", "chatInputAbove", x, nextY(), relayout)
	self.zoneButton = button(f, ZONE_TEXT[1], 180, x, y - 6, function()
		ns.db.consoleOpts.zoneText = (ns.db.consoleOpts.zoneText or 1) % 3 + 1
		relayout()
		self:Refresh()
	end)

	-- Target display: on the hero screen (Warcraft III) or a plate on the wall.
	label(f, "Target display", x, -306)
	self.targetButtons = {}
	for i, spec in ipairs({ { "swap", "Swap" }, { "plate", "Wall plate" } }) do
		local b = button(f, spec[2], 90, x + 112 + (i - 1) * 94, -302, function()
			ns.modules.target:SetMode(spec[1])
			self:Refresh()
		end)
		b.mode = spec[1]
		self.targetButtons[i] = b
	end

	-- Number boxes, right column.
	x, y = 340, -108
	self:Edit("UI scale (240-270)", "uiScale", x, y)
	self:Edit("Extend bottom right upwards (0-150)", "chatUp", x, y - 42)
	self:Edit("HP Warning Threshold %", "hpWarning", x, y - 84)
	label(f, "Portrait position (Base 100, 100) X: and Y:", x, y - 126)
	self:Edit("", "portraitX", x, y - 126)
	self:Edit("", "portraitY", x + 70, y - 126)
	self:Edit("Portrait scale (0-35)", "portraitScale", x, y - 168)

	-- Rested experience colour.
	label(f, "Rested XP colors", x, y - 214)
	for i, spec in ipairs(RESTED_COLORS) do
		button(f, spec[1], 64, x + (i - 1) * 68, y - 232, function()
			ns.db.consoleOpts.restedColor = { unpack(spec[2]) }
			ns.modules.hero:UpdateXP()
		end)
	end
	button(f, "Custom", 64, x + 3 * 68, y - 232, function() self:PickRestedColor() end)

	-- Stat icons.
	y = -384
	self.iconButtons = {}
	for row, text in ipairs(ICON_ROWS) do
		label(f, text, 20, y - (row - 1) * 30 - 4, "GameFontNormalSmall")
		self.iconButtons[row] = {}
		for i, spec in ipairs(ICON_BUTTONS) do
			local b = button(f, spec[2], 62, 170 + (i - 1) * 64, y - (row - 1) * 30, function()
				ns.modules.hero:SetIconChoice(row, spec[1])
				self:Refresh()
			end)
			b.kind = spec[1]
			self.iconButtons[row][i] = b
		end
	end

	button(f, "Apply", 120, 20, -490, function() self:Apply() end)
	button(f, "Reload UI", 120, 150, -490, ReloadUI)
end

-- Reads the number boxes into the settings (clamped to the original addon's ranges).
function Config:Apply()
	local o = ns.db.consoleOpts
	local function num(key, lo, hi)
		for _, eb in ipairs(self.edits) do
			if eb.key == key then
				local v = tonumber(eb:GetText())
				if v then
					o[key] = math.max(lo, math.min(hi, math.floor(v)))
				end
			end
		end
	end
	num("uiScale", ns.Layout.SCALE_MIN, ns.Layout.SCALE_MAX)
	num("chatUp", 0, 150)
	num("hpWarning", 0, 100)
	num("portraitX", 0, 300)
	num("portraitY", 0, 300)
	num("portraitScale", 0, 35)
	relayout()
	self:Refresh()
end

function Config:PickRestedColor()
	local c = ns.db.consoleOpts.restedColor
	local function set()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 0.5
		ns.db.consoleOpts.restedColor = { r, g, b, a }
		ns.modules.hero:UpdateXP()
	end
	local previous = { unpack(c) }
	pcall(ColorPickerFrame.SetupColorPickerAndShow, ColorPickerFrame, {
		r = c[1], g = c[2], b = c[3], opacity = c[4], hasOpacity = true,
		swatchFunc = set, opacityFunc = set,
		cancelFunc = function()
			ns.db.consoleOpts.restedColor = previous
			ns.modules.hero:UpdateXP()
		end,
	})
end

function Config:Refresh()
	local o = ns.db.consoleOpts
	for _, cb in ipairs(self.checks) do
		if cb.key then
			cb:SetChecked(o[cb.key] and true or false)
		end
	end
	for _, eb in ipairs(self.edits) do
		local v = o[eb.key]
		eb:SetText(v and tostring(v) or "")
		eb:SetCursorPosition(0)
	end
	for _, b in ipairs(self.themeButtons) do
		b:SetEnabled(ns.db.theme ~= b.key)
	end
	local choices = ns.modules.hero.enabled and ns.modules.hero:IconChoices() or {}
	for row, list in ipairs(self.iconButtons) do
		for _, b in ipairs(list) do
			b:SetEnabled(choices[row] ~= b.kind)
		end
	end
	local target = ns.modules.target
	for _, b in ipairs(self.targetButtons) do
		b:SetEnabled(target.enabled and target:Mode() ~= b.mode)
	end
	self.zoneButton:SetText(ZONE_TEXT[o.zoneText] or ZONE_TEXT[1])
end

function Config:Toggle()
	self.frame:SetShown(not self.frame:IsShown())
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
	hover:SetScript("OnClick", function() self:Toggle() end)
	self.cogwheel = hover
end

function Config:OnLayout(L)
	if self.cogwheel and L.cogwheel then
		ns:PlaceRect(self.cogwheel, L.cogwheel)
	end
end

-- A page in the game's options (AddOns tab) that opens the menu.
function Config:RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	label(panel, "Reforged UI", 16, -16, "GameFontNormalLarge")
	label(panel, "The Warcraft III console, with Reforged UI's top bar.", 16, -44, "GameFontHighlight")
	button(panel, "Open the console menu", 200, 16, -72, function()
		self.frame:Show()
	end)
	pcall(function()
		local category = Settings.RegisterCanvasLayoutCategory(panel, "Reforged UI")
		Settings.RegisterAddOnCategory(category)
	end)
end

function Config:OnEnable()
	self:Build()
	self:BuildCogwheel()
	self:RegisterSettings()
end
