-- The original addon's options menu, opened with the cogwheel in the bottom-right corner of
-- the chat area (or /rui config). The original addon's
-- "General" tab in its wording, kept minimal: the console is always laid out
-- like the original addon's "Center UI" with its chat area and inventory, so the centre
-- modes, chat placement and "Hide bags" options are gone, and "Chat width" only
-- matters where the screen is too narrow for the original addon's chat area.
-- The original addon's "Customize" tab is not ported (see README.md).

local _, ns = ...
local Config = ns:RegisterModule("config", {})

local W, H = 650, 542

-- Two rows: Alliance races, then Horde races. "Skyborne" picks the
-- character's faction's Skyborne theme; "Auto" the character's race's theme.
local THEME_BUTTONS = {
	{ "human", "Human" }, { "dwarf", "Dwarf" }, { "gnome", "Gnome" }, { "nightelf", "Night Elf" },
	{ "highorder", "High Order" }, { "skyborne", "Skyborne" }, { "auto", "Auto" },
	{ "orc", "Orc" }, { "tauren", "Tauren" }, { "troll", "Troll" }, { "forsaken", "Forsaken" },
	{ "undead", "Scourge" }, { "windshapers", "Windshapers" },
}
local THEME_COLUMNS = 7
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

-- Slider bound to db.consoleOpts[key] (lo-hi, whole steps, its value shown
-- with `unit`, "%" by default); `after` runs as it moves. No template: the
-- game's slider templates differ between clients.
function Config:Slider(text, key, lo, hi, x, y, w, after, unit)
	unit = unit or "%"
	label(self.frame, text, x, y)
	local s = CreateFrame("Slider", nil, self.frame, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(w, 17)
	s:SetPoint("TOPLEFT", x + 170, y + 1)
	s:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(1)
	s:SetObeyStepOnDrag(true)
	s:EnableMouseWheel(true)
	local value = label(self.frame, "", x + 178 + w, y, "GameFontHighlight")
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v + 0.5)
		value:SetText(v .. unit)
		if ns.db.consoleOpts[key] ~= v then
			ns.db.consoleOpts[key] = v
			if after then
				after(v)
			end
		end
	end)
	s:SetScript("OnMouseWheel", function(slider, delta)
		slider:SetValue(slider:GetValue() + delta)
	end)
	s.key, s.value, s.unit = key, value, unit
	self.sliders[#self.sliders + 1] = s
	return s
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
	f:SetScript("OnDragStart", function(frame)
		if not self.embedded then
			frame:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnShow", function() self:Refresh() end)
	f:Hide()
	tinsert(UISpecialFrames, "ReforgedUIConfig")
	self.frame = f
	self.checks, self.edits, self.sliders = {}, {}, {}

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	self.closeButton = close
	label(f, "Reforged UI", 20, -18, "GameFontNormalLarge")

	-- Themes.
	self.themeButtons = {}
	for i, spec in ipairs(THEME_BUTTONS) do
		local col, row = (i - 1) % THEME_COLUMNS, math.floor((i - 1) / THEME_COLUMNS)
		self.themeButtons[i] = button(f, spec[2], 86, 20 + col * 88, -44 - row * 26, function()
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

	-- Bars 1-3 on their own Edit Mode bars instead of in the grid.
	self:Check("Let Edit Mode place action bars 1-3", "editModeBars", x, -336, function(on)
		ns.db.consoleOpts.barsPlaced = false
		if on then
			ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
		end
		ns:AskReload(on and "action bars 1-3 now stay on their Edit Mode bars (grid art hidden)."
			or "action bars 1-3 go back into the console's grid.")
	end)

	-- The chat window: held in the chat area, or free to move and resize.
	self:Check("Let me move and resize the chat window", "freeChat", x, -362, function(on)
		ns.db.consoleOpts.chatPlaced = false
		relayout()
		if not on then
			return
		end
		ns:Print("the chat window is yours to move and resize: unlock it from its tab's menu, or use Edit Mode.")
	end)

	-- Number boxes, right column.
	x, y = 340, -108
	self:Edit("UI scale (240-270)", "uiScale", x, y)
	self:Edit("HP Warning Threshold %", "hpWarning", x, y - 42)
	label(f, "Portrait position (Base 100, 100) X: and Y:", x, y - 84)
	self:Edit("", "portraitX", x, y - 84)
	self:Edit("", "portraitY", x + 70, y - 84)
	self:Edit("Portrait scale (0-35)", "portraitScale", x, y - 126)

	-- The four stat icons on the hero screen (this class's choice); the
	-- same menu opens when they are right-clicked on the console.
	label(f, "Stat icons (this class)", x, -318)
	self.iconButtons = {}
	for i = 1, 4 do
		local b = button(f, "", 72, x + (i - 1) * 73, -336, nil)
		b:SetScript("OnClick", function(owner) ns.modules.hero:OpenIconMenu(i, owner) end)
		b.index = i
		self.iconButtons[i] = b
	end

	label(f, "Right-click a stat icon on the console to change it too, or the experience bar for its rested colour.",
		20, -388, "GameFontNormalSmall")

	-- See-through console art (buttons, icons and text stay opaque).
	self:Slider("Console transparency", "transparency", 0, 100, 20, -418, 300, function()
		ns.modules.console:ApplyTransparency()
	end)

	-- A wider chat area on screens too narrow for the original addon's: the
	-- console scales down to make room. Edit Mode's places for the target's
	-- auras and the cast bar follow when the slider is let go.
	local function placeEditMode()
		ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
	end
	local chat = self:Slider("Chat width", "chatWiden", 0, 100, 20, -444, 300, relayout)
	chat:SetScript("OnMouseUp", placeEditMode)
	-- The original addon's "Extend bottom right upwards": raises the chat
	-- area (and the cast bar above it, when let go), in console units.
	local height = self:Slider("Chat height", "chatUp", 0, 150, 20, -470, 300, relayout, "")
	height:SetScript("OnMouseUp", placeEditMode)

	button(f, "Apply", 120, 20, -502, function() self:Apply() end)
	button(f, "Reload UI", 120, 150, -502, ReloadUI)
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
	num("hpWarning", 0, 100)
	num("portraitX", 0, 300)
	num("portraitY", 0, 300)
	num("portraitScale", 0, 35)
	relayout()
	self:Refresh()
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
	for _, s in ipairs(self.sliders) do
		s:SetValue(o[s.key] or 0)
		s.value:SetText((o[s.key] or 0) .. s.unit)
	end
	for _, b in ipairs(self.themeButtons) do
		b:SetEnabled(ns.db.theme ~= b.key)
	end
	local target = ns.modules.target
	for _, b in ipairs(self.targetButtons) do
		b:SetEnabled(target.enabled and target:Mode() ~= b.mode)
	end
	self.zoneButton:SetText(ZONE_TEXT[o.zoneText] or ZONE_TEXT[1])
	local hero = ns.modules.hero
	local choices = hero:IconChoices()
	for i, b in ipairs(self.iconButtons) do
		b:SetText(hero.ICON_NAMES[choices[i] or "none"] or "None")
	end
end

function Config:Toggle()
	if self.embedded then
		self:Unembed()
	end
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

-- A page in the game's options (AddOns tab) that shows the menu inside it.
-- The menu moves into the page while the page is shown and back out when it
-- closes, so closing the game's options never leaves it behind or takes it
-- away. Nothing here calls the game's panel manager (Show/HideUIPanel):
-- doing that from addon code taints it, and Edit Mode, which the panel
-- manager opens and closes, then errors.
function Config:EmbedIn(panel)
	local f = self.frame
	self.embedded = panel
	f:SetParent(panel)
	f:SetFrameStrata(panel:GetFrameStrata())
	f:SetFrameLevel(panel:GetFrameLevel() + 1)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	local width = panel:GetWidth()
	f:SetScale(width and width > 0 and math.min(1, width / W) or 1)
	f:SetMovable(false)
	self.closeButton:Hide()
	f:Show()
end

function Config:Unembed()
	local f = self.frame
	self.embedded = nil
	f:Hide()
	f:SetParent(UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetScale(1)
	f:ClearAllPoints()
	f:SetPoint("LEFT", 200, 0)
	f:SetMovable(true)
	self.closeButton:Show()
end

function Config:RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	panel:SetScript("OnShow", function(p) self:EmbedIn(p) end)
	panel:SetScript("OnHide", function() self:Unembed() end)
	pcall(function()
		local category = Settings.RegisterCanvasLayoutCategory(panel, "Reforged UI")
		Settings.RegisterAddOnCategory(category)
	end)
	self.settingsPanel = panel
end

function Config:OnEnable()
	self:Build()
	self:BuildCogwheel()
	self:RegisterSettings()
end
