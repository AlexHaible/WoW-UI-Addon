-- The original addon's options menu, opened with the cogwheel in the bottom-right corner of
-- the chat area (or /rui config). The original addon's
-- "General" tab in its wording, kept minimal: the console is always laid out
-- like the original addon's "Center UI" with its chat area and inventory, so the centre
-- modes, chat placement and "Hide bags" options are gone, and "Chat width" only
-- matters where the screen is too narrow for the original addon's chat area.
-- The original addon's "Customize" tab is not ported (see README.md).

local _, ns = ...
local Config = ns:RegisterModule("config", {})

-- The menu's width; its height follows its last row (see Build).
local W = 650
local ROW = 26 -- from one row of options to the next
local BOTTOM = 14 -- under the last row

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
local CLOCK_TIME = { server = "Time: server", ["local"] = "Time: local", off = "Time: hidden" }

local function relayout()
	if ns.ready then
		ns:Relayout()
	end
end

----------------------------------------------------------------------------
-- Placing options
--
-- Options go on rows handed out one after the other, never at a y picked
-- by hand: a new option takes the next row of its column (or of the list
-- at the bottom, which the menu grows with), so two changes made apart
-- can't land on the same spot. Every widget also notes the room it takes
-- (Config.claims: x and y from the menu's top left, y downwards negative),
-- and tools/smoke_test.lua fails when two of them overlap or one leaves
-- the menu.

-- Rows from `y` down: each call returns the next row's y, after `gap`
-- more room above it; rows.y is where the next one would go.
local function rows(y)
	local list = { y = y }
	return setmetatable(list, { __call = function(_, gap)
		local at = list.y - (gap or 0)
		list.y = at - ROW
		return at
	end })
end

function Config:Claim(name, x, y, w, h)
	if w > 0 and h > 0 then
		self.claims[#self.claims + 1] = { name = name, x = x, y = y, w = w, h = h }
	end
end

----------------------------------------------------------------------------
-- Widgets

local LABEL_H = 12

local function button(parent, text, w, x, y, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	Config:Claim("button " .. text, x, y, w, 22)
	return b
end

local function label(parent, text, x, y, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	Config:Claim("label " .. text, x, y, fs:GetStringWidth() or 0, LABEL_H)
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
	cb.label = fs
	self:Claim("checkbox " .. text, x, y, 26 + (fs:GetStringWidth() or 0), 24)
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
	self:Claim("box " .. key, x + 6, y - 16, w or 60, 20)
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
	self:Claim("slider " .. key, x + 170, y + 1, w, 17)
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
		-- Refresh showing a setting that is still unset (s.default) leaves it unset.
		if ns.db.consoleOpts[key] ~= v and not self.refreshing then
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
	f:SetWidth(W) -- its height is set below, once the rows are counted
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
	self.checks, self.edits, self.sliders, self.claims = {}, {}, {}, {}

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
	local x, left = 20, rows(-104)
	self:Check("Hide actionbar grid texture", "hideGrid", x, left(), relayout)
	self:Check("Show HP as %", "healthPercent", x, left(), function() ns.modules.hero:Update() end)
	self:Check("Show power as %", "powerPercent", x, left(), function() ns.modules.hero:Update() end)
	self:Check("Hide chat icons (reload)", "hideChatIcons", x, left())
	self:Check("Stop portrait animation (reload)", "stopAnimation", x, left())
	self:Check("Chat input above chat", "chatInputAbove", x, left(), relayout)
	self.zoneButton = button(f, ZONE_TEXT[1], 180, x, left(6), function()
		ns.db.consoleOpts.zoneText = (ns.db.consoleOpts.zoneText or 1) % 3 + 1
		relayout()
		self:Refresh()
	end)

	-- Target display: on the hero screen (Warcraft III) or a plate on the wall.
	local y = left(14)
	label(f, "Target display", x, y)
	self.targetButtons = {}
	for i, spec in ipairs({ { "swap", "Swap" }, { "plate", "Wall plate" } }) do
		local b = button(f, spec[2], 90, x + 112 + (i - 1) * 94, y + 4, function()
			ns.modules.target:SetMode(spec[1])
			self:Refresh()
		end)
		b.mode = spec[1]
		self.targetButtons[i] = b
	end

	-- Bars 1-3 on their own Edit Mode bars instead of in the grid.
	self:Check("Let Edit Mode place action bars 1-3", "editModeBars", x, left(4), function(on)
		ns.db.consoleOpts.barsPlaced = false
		if on then
			ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
		end
		ns:AskReload(on and "action bars 1-3 now stay on their Edit Mode bars (grid art hidden)."
			or "action bars 1-3 go back into the console's grid.")
	end)

	-- The chat window: held in the chat area, or free to move and resize.
	self:Check("Let me move and resize the chat window", "freeChat", x, left(), function(on)
		ns.db.consoleOpts.chatPlaced = false
		relayout()
		if not on then
			return
		end
		ns:Print("the chat window is yours to move and resize: unlock it from its tab's menu, or use Edit Mode.")
	end)

	-- Number boxes, right column: the original addon's, each with its
	-- label above it, so they keep their own spacing down to the rows the
	-- two columns share at the end.
	x, y = 340, -108
	self:Edit("UI scale (240-270)", "uiScale", x, y)
	-- The game's tooltips in the theme's frame, like the damage meter.
	self:Check("Themed tooltips", "themeTooltips", x + 116, y - 14, function(on)
		ns.modules.tooltip:SetEnabled(on)
	end)
	self:Edit("HP Warning Threshold %", "hpWarning", x, y - 42)
	label(f, "Portrait position (Base 100, 100) X: and Y:", x, y - 84)
	self:Edit("", "portraitX", x, y - 84)
	self:Edit("", "portraitY", x + 70, y - 84)
	self:Edit("Portrait scale (0-35)", "portraitScale", x, y - 126)
	-- The watched faction's strip under the experience bar.
	self:Check("Reputation bar", "repBar", x + 116, y - 140, relayout)

	-- No top bar: the menu buttons stand above the minimap instead.
	self:Check("Hide top bar", "hideTopBar", x, y - 178, function(on) ns:SetTopBarShown(not on) end)
	-- On the same row, the time in the capsule under the top bar's clock
	-- (above the minimap without the bar): server, local or none, on a 24
	-- or 12 hour clock.
	local topbar = ns.modules.topbar
	self.clockTimeButton = button(f, CLOCK_TIME.server, 110, x + 116, y - 179, function()
		local modes, mode = topbar.TIME_MODES, topbar:TimeMode()
		for i, m in ipairs(modes) do
			if m == mode then
				topbar:SetTimeMode(modes[i % #modes + 1])
				break
			end
		end
		self:Refresh()
	end)
	self.clockHoursButton = button(f, "24-hour", 64, x + 230, y - 179, function()
		topbar:SetTimeHours(topbar:TimeHours() == 12 and 24 or 12)
		self:Refresh()
	end)

	-- The four stat icons on the hero screen (this class's choice); the
	-- same menu opens when they are right-clicked on the console.
	local right = rows(-318)
	label(f, "Stat icons (this class)", x, right())
	self.iconButtons = {}
	y = right(-8)
	for i = 1, 4 do
		local b = button(f, "", 72, x + (i - 1) * 73, y, nil)
		b:SetScript("OnClick", function(owner) ns.modules.hero:OpenIconMenu(i, owner) end)
		b.index = i
		self.iconButtons[i] = b
	end

	-- Free-standing target and target of target windows, to put anywhere
	-- (Shift-drag, or in Edit Mode).
	y = right()
	assert(right.y == left.y, "the two columns end on the same row")
	self.targetBarCheck = self:Check("Target bar", "targetBar", x, y, function(on)
		ns.modules.target:SetBarEnabled(on)
		if on then
			ns:Print("target bar on: hold Shift and drag it where you want it, or move it in Edit Mode.")
		end
	end)
	self.totBarCheck = self:Check("Target of target bar", "totBar", x + 100, y, function(on)
		local target = ns.modules.target
		target:SetBarEnabled(on, target.totBar)
		if on then
			ns:Print("target of target bar on: hold Shift and drag it where you want it, or move it in Edit Mode.")
		end
	end)

	label(f, "Right-click a stat icon on the console to change it too, or the experience bar for its rested colour.",
		20, left.y, "GameFontNormalSmall")

	-- The list at the bottom, over the menu's whole width: new options
	-- go at its end, each on list() (several can share a row, side by side).
	local list = rows(left.y - 30)

	-- See-through console art (buttons, icons and text stay opaque).
	self:Slider("Console transparency", "transparency", 0, 100, 20, list(), 300, function()
		ns.modules.console:ApplyTransparency()
	end)

	-- A wider chat area on screens too narrow for the original addon's: the
	-- console scales down to make room. Edit Mode's places for the target's
	-- auras and the cast bar follow when the slider is let go.
	local function placeEditMode()
		ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
	end
	local chat = self:Slider("Chat width", "chatWiden", 0, 100, 20, list(), 300, relayout)
	chat:SetScript("OnMouseUp", placeEditMode)
	-- The original addon's "Extend bottom right upwards": raises the chat
	-- area (and the cast bar above it, when let go), in console units.
	local height = self:Slider("Chat height", "chatUp", 0, 150, 20, list(), 300, relayout, "")
	height:SetScript("OnMouseUp", placeEditMode)
	-- A smaller console and top bar; Edit Mode's places follow when let go.
	local size = self:Slider("UI size", "uiSize", ns.UI_SIZE_MIN, ns.UI_SIZE_MAX, 20, list(), 300, relayout)
	size:SetScript("OnMouseUp", placeEditMode)
	-- Bigger target buff and debuff icons on the wall: Edit Mode's Frame
	-- Size for the target frame (its icons are all we leave of it), in
	-- steps of 5 %, placed when let go. Until moved it stays unset, and Edit
	-- Mode's own size is kept.
	local auras = self:Slider("Target aura size", "targetAuraSize", ns.TARGET_AURA_SIZE_MIN,
		ns.TARGET_AURA_SIZE_MAX, 20, list(), 300)
	auras:SetValueStep(5)
	auras.default = ns.TARGET_AURA_SIZE_MIN
	local function placeAuras()
		placeEditMode()
		ns:SayTargetAuraSize()
	end
	auras:SetScript("OnMouseUp", placeAuras)
	auras:SetScript("OnMouseWheel", function(slider, delta)
		slider:SetValue(slider:GetValue() + delta * 5)
		placeAuras()
	end)
	-- Bigger target and target of target bars.
	self:Slider("Target bar size", "targetBarSize", ns.TARGET_BAR_SIZE_MIN, ns.TARGET_BAR_SIZE_MAX, 20, list(), 300,
		function(v) ns.modules.target:SetBarSize(v) end)
	-- Under it, beside the buttons: the target's buffs on the bottom rows,
	-- nearest its portrait, and its debuffs after them (the game puts a
	-- hostile target's debuffs first). (A checkbox is two taller than a
	-- button, hence the one up.)
	y = list(6)
	button(f, "Apply", 120, 20, y, function() self:Apply() end)
	button(f, "Reload UI", 120, 150, y, ReloadUI)
	self:Check("Target buffs first", "targetBuffsFirst", 290, y + 1, function(on)
		ns.modules.target:SetBuffsFirst(on)
	end)
	-- Stance buttons hidden altogether (their key bindings still work),
	-- or left to Blizzard's stance bar or another bar addon (moving them
	-- on the console is done in Edit Mode).
	y = list() + 1
	self:Check("Hide stance buttons", "hideStance", 20, y, function(on)
		ns.modules.actionbars:SetStanceShown(not on)
	end)
	self:Check("Leave stance buttons to my bar addon", "leaveStance", 290, y, function(on)
		ns:AskReload(on and "the stance buttons are left to Blizzard or your bar addon."
			or "the stance buttons go back on the console's wall.")
	end)

	self.height = BOTTOM - list.y
	f:SetHeight(self.height)
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
	self.refreshing = true
	for _, s in ipairs(self.sliders) do
		local v = o[s.key] or s.default or 0
		s:SetValue(v)
		s.value:SetText(v .. s.unit)
	end
	self.refreshing = false
	for _, b in ipairs(self.themeButtons) do
		b:SetEnabled(ns.db.theme ~= b.key)
	end
	local target = ns.modules.target
	for _, b in ipairs(self.targetButtons) do
		b:SetEnabled(target.enabled and target:Mode() ~= b.mode)
	end
	-- Greyed out like the buttons above while the target module is off.
	local shade = target.enabled and 1 or 0.5
	for _, cb in ipairs({ self.targetBarCheck, self.totBarCheck }) do
		cb:SetEnabled(target.enabled and true or false)
		cb.label:SetTextColor(shade, shade, shade)
	end
	self.zoneButton:SetText(ZONE_TEXT[o.zoneText] or ZONE_TEXT[1])
	local topbar = ns.modules.topbar
	self.clockTimeButton:SetText(CLOCK_TIME[topbar:TimeMode()])
	self.clockTimeButton:SetEnabled(topbar.enabled or false)
	self.clockHoursButton:SetText(topbar:TimeHours() == 12 and "12-hour" or "24-hour")
	self.clockHoursButton:SetEnabled(topbar.enabled and topbar:TimeMode() ~= "off" or false)
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
