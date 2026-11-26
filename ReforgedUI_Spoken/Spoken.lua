-- Reforged UI: Spoken. Adds a narrator style to Spoken (the addon that reads
-- the game aloud) through its Public API (Spoken:RegisterNarrator): a window
-- of our own in the current Reforged UI theme, the way Reforged UI: Damage
-- Meter dresses the meter. The theme's top bar trim goes around it (Reforged
-- UI's Trim.lua), with a dark inset inside, the theme's rail under the
-- speaker's name, the original addon's font and the theme's colours.
--
-- Spoken draws the parts it hands out (its captions, round controls, portrait
-- and the line's own buttons) and keeps them current; this file only places
-- them and paints the frame. While another narrator style is chosen, Spoken
-- never calls Update and nothing here shows.
--
-- With "Frame follows the speaker's race" ticked, a line spoken by an orc is
-- framed in the Orc theme, a night elf's in the Night Elf theme and so on
-- (Spoken:GetSpeaker), whatever theme the UI wears. Lines with no speaker
-- (places, books) keep the UI's theme.

local ADDON = ...
local NARRATOR = "reforgedui"
local ICON = "Interface\\AddOns\\ReforgedUI\\Media\\Common\\icon"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local Spoken = _G.Spoken
if not (Spoken and Spoken.IsCompatible and Spoken:IsCompatible(1) and Spoken.RegisterNarrator) then
	return
end

local WIDTH = 460
local PAD = 14 -- inside the trim
local PORTRAIT = 72
local GAP = 12 -- portrait to text
local RAIL_H = 3
local PROGRESS_H = 4
local CONTROL_GAP = 2
local CONTROLS = { "previous", "pause", "stop", "skip", "stopall" }
local NAME_SIZE, LABEL_SIZE, STATUS_SIZE = 15, 12, 11
local LABEL_COLOR = { 0.85, 0.85, 0.85 }
local STATUS_COLOR = { 0.65, 0.65, 0.65 }

local DEFAULTS = {
	followSpeaker = false,
	scale = 100,
	locked = false,
	point = { "BOTTOM", "BOTTOM", 0, 320 },
}

local db = {} -- ReforgedUISpokenDB once it is loaded; unset keys are DEFAULTS

local function setting(key)
	local v = db[key]
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

local window -- built on the first line shown
local shown -- the clip on screen, or nil

----------------------------------------------------------------------------
-- Theme

-- The theme a line is framed in: the speaker's race's, when asked for and
-- known, else the UI's.
local function themeFor(clip)
	local key, theme = ReforgedUI.GetTheme()
	if setting("followSpeaker") and clip and Spoken.GetSpeaker and ReforgedUI.ThemeForRace then
		local speaker = Spoken:GetSpeaker(clip)
		local k, t = ReforgedUI.ThemeForRace(speaker and speaker.race)
		if k then
			key, theme = k, t
		end
	end
	return key, theme
end

local function Paint()
	if not window then
		return
	end
	local key, theme = themeFor(shown)
	if not (key and theme) then
		return
	end
	local w = window
	local inset = theme.inset
	w.bg:SetColorTexture(inset[1], inset[2], inset[3], inset[4] or 0.9)
	local own = ReforgedUI.GetTheme()
	w.trim:SetThemeKey(key ~= own and key or nil)
	w.rail:SetTexture(ReforgedUI.TrimArt("rail", key))
	w.progressRail:SetTexture(ReforgedUI.TrimArt("rail", key))
	local title, accent = theme.title, theme.accent
	w.name:SetTextColor(title[1], title[2], title[3])
	w.progress:SetStatusBarColor(accent[1], accent[2], accent[3])
	w.portrait:SetRingColor(title[1], title[2], title[3])
end

----------------------------------------------------------------------------
-- The window

local function SavePosition(frame)
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then
		db.point = { point, relPoint, x, y }
	end
end

local function Place(frame)
	local p = setting("point")
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	frame:SetScale(setting("scale") / 100)
end

local function Build()
	local w = CreateFrame("Frame", "ReforgedUISpokenFrame", UIParent)
	window = w
	w:SetSize(WIDTH, PAD * 2 + PORTRAIT)
	w:SetFrameStrata("MEDIUM")
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	ReforgedUI.MakeDraggable(w, SavePosition, function()
		return not setting("locked")
	end)
	-- A line that ends mid-drag hides the window under the mouse.
	w:HookScript("OnHide", ReforgedUI.StopDrag)
	w:Hide()
	Place(w)

	w.bg = w:CreateTexture(nil, "BACKGROUND", nil, -8)
	w.bg:SetAllPoints()
	-- In the window's BORDER layer: over the background, under the text and
	-- Spoken's parts (child frames).
	w.trim = ReforgedUI.CreateTrim(w)

	w.portrait = Spoken:CreatePortrait(w, PORTRAIT)
	w.portrait:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -PAD)

	local textX = PAD + PORTRAIT + GAP
	local textW = WIDTH - textX - PAD
	w.textX, w.textW = textX, textW

	w.name = w:CreateFontString(nil, "ARTWORK")
	ReforgedUI.SetFont(w.name, NAME_SIZE, "OUTLINE")
	w.name:SetJustifyH("LEFT")
	w.name:SetWordWrap(false)
	w.name:SetWidth(textW)
	w.name:SetPoint("TOPLEFT", w, "TOPLEFT", textX, -PAD)

	w.label = w:CreateFontString(nil, "ARTWORK")
	ReforgedUI.SetFont(w.label, LABEL_SIZE)
	w.label:SetJustifyH("LEFT")
	w.label:SetWordWrap(false)
	w.label:SetWidth(textW)
	w.label:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3])
	w.label:SetPoint("TOPLEFT", w.name, "BOTTOMLEFT", 0, -2)

	w.rail = w:CreateTexture(nil, "ARTWORK")
	w.rail:SetHeight(RAIL_H)

	-- Spoken's captions are docked in here, from its top left.
	w.captions = CreateFrame("Frame", nil, w)
	w.captions:SetWidth(textW)

	w.progress = CreateFrame("StatusBar", nil, w)
	w.progress:SetStatusBarTexture(BAR_TEXTURE)
	w.progress:SetMinMaxValues(0, 1)
	w.progress:SetHeight(PROGRESS_H)
	w.progress:SetWidth(textW)
	w.progressBg = w.progress:CreateTexture(nil, "BACKGROUND")
	w.progressBg:SetAllPoints()
	w.progressBg:SetColorTexture(0, 0, 0, 0.6)
	w.progressRail = w.progress:CreateTexture(nil, "OVERLAY")
	w.progressRail:SetHeight(RAIL_H)
	w.progressRail:SetPoint("TOPLEFT", w.progress, "BOTTOMLEFT", 0, 1)
	w.progressRail:SetPoint("TOPRIGHT", w.progress, "BOTTOMRIGHT", 0, 1)

	-- Spoken's round controls, right to left from the window's right edge.
	-- Spoken shows and hides some of them (Pause, on a line it can't resume);
	-- the rest close up.
	w.controls = {}
	w.controlRow = CreateFrame("Frame", nil, w)
	w.controlRow:SetWidth(textW)
	w.status = w.controlRow:CreateFontString(nil, "ARTWORK")
	ReforgedUI.SetFont(w.status, STATUS_SIZE)
	w.status:SetJustifyH("LEFT")
	w.status:SetWordWrap(false)
	w.status:SetTextColor(STATUS_COLOR[1], STATUS_COLOR[2], STATUS_COLOR[3])
	local function Arrange()
		local prev
		for i = #w.controls, 1, -1 do
			local button = w.controls[i]
			if button:IsShown() then
				button:ClearAllPoints()
				if prev then
					button:SetPoint("RIGHT", prev, "LEFT", -CONTROL_GAP, 0)
				else
					button:SetPoint("RIGHT", w.controlRow, "RIGHT", 0, 0)
				end
				prev = button
			end
		end
		w.status:ClearAllPoints()
		w.status:SetPoint("LEFT", w.controlRow, "LEFT", 0, 0)
		if prev then
			w.status:SetPoint("RIGHT", prev, "LEFT", -6, 0)
		else
			w.status:SetPoint("RIGHT", w.controlRow, "RIGHT", 0, 0)
		end
	end
	for i, kind in ipairs(CONTROLS) do
		local button = Spoken:CreateControl(w.controlRow, kind)
		w.controls[i] = button
		button:HookScript("OnShow", Arrange)
		button:HookScript("OnHide", Arrange)
	end
	Arrange()

	-- The line's own buttons (Report, and the module's), under the portrait.
	w.actions = Spoken:CreateActions(w)
	w.actions:SetPoint("TOP", w.portrait, "BOTTOM", 0, -6)

	-- The reading position, every frame while a line shows.
	w:SetScript("OnUpdate", function(self)
		local caption = Spoken.GetCaption and Spoken:GetCaption()
		local progress = caption and caption.progress
		if type(progress) == "number" then
			self.progress:SetValue(progress)
		elseif not caption then
			self.progress:SetValue(0)
		end
	end)

	Paint()
	return w
end

-- What the line is waiting on, in a word or two: paused, held (combat and
-- the like, in the player's language from Spoken) or how many lines wait.
local function Status()
	if not (window and shown) then
		return
	end
	local text
	if Spoken.IsPaused and Spoken:IsPaused() then
		text = "Paused"
	end
	local held = Spoken.GetHeldReason and Spoken:GetHeldReason(shown)
	if type(held) == "string" and held ~= "" then
		text = text and (text .. " - " .. held) or held
	end
	local waiting = Spoken.GetWaitingCount and Spoken:GetWaitingCount() or 0
	if type(waiting) == "number" and waiting > 0 then
		local more = waiting == 1 and "1 more line" or (waiting .. " more lines")
		text = text and (text .. " - " .. more) or more
	end
	window.status:SetText(text or "")
end

-- Lays the window out for `clip`: the header, then the captions Spoken
-- docks in, the reading position and the controls, the window sized to fit.
local function Layout(clip)
	local w = window
	local present = clip.present or {}
	local header = present.header or (clip.source and clip.source.title) or ""
	w.name:SetText(header)
	local label = present.label
	w.label:SetText(label or "")
	w.label:SetShown(label ~= nil and label ~= "")
	local headerH = w.name:GetStringHeight()
	if w.label:IsShown() then
		headerH = headerH + 2 + w.label:GetStringHeight()
	end

	local y = PAD + headerH + 4
	w.rail:ClearAllPoints()
	w.rail:SetPoint("TOPLEFT", w, "TOPLEFT", w.textX, -y)
	w.rail:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, -y)
	y = y + RAIL_H + 6

	w.captions:ClearAllPoints()
	w.captions:SetPoint("TOPLEFT", w, "TOPLEFT", w.textX, -y)
	local captionsH = Spoken.ShowCaptions and Spoken:ShowCaptions(w.captions, w.textW) or 0
	w.captions:SetHeight(math.max(1, captionsH))
	if captionsH > 0 then
		y = y + captionsH + 6
	end

	-- A line with no length has no reading position.
	local hasLength = type(clip.length) == "number" and clip.length > 0
	w.progress:SetShown(hasLength)
	if hasLength then
		w.progress:ClearAllPoints()
		w.progress:SetPoint("TOPLEFT", w, "TOPLEFT", w.textX, -y)
		w.progress:SetValue(0)
		y = y + PROGRESS_H + RAIL_H + 6
	end

	local rowH = 0
	for _, button in ipairs(w.controls) do
		rowH = math.max(rowH, button:GetHeight() or 0)
	end
	rowH = math.max(rowH, 20)
	w.controlRow:SetHeight(rowH)
	w.controlRow:ClearAllPoints()
	w.controlRow:SetPoint("TOPLEFT", w, "TOPLEFT", w.textX, -y)
	y = y + rowH

	w.actions:SetClip(clip)
	local left = PAD + PORTRAIT + 6 + (w.actions:GetHeight() or 0)
	w:SetHeight(math.max(y, left) + PAD)
end

-- Spoken's Update: the line to show, or nil to show nothing.
local function Update(clip)
	shown = clip
	if not clip then
		if window then
			window:Hide()
		end
		return
	end
	local w = window or Build()
	w.portrait:SetClip(clip)
	Layout(clip)
	Paint()
	Status()
	w:Show()
end

----------------------------------------------------------------------------
-- Spoken's settings page: our rows, shown while this is the style.

local function Settings(layout)
	layout:Section("Reforged UI")
	layout:Checkbox("Frame follows the speaker's race",
		"Frame each line in the theme of the race speaking it (an orc's in the Orc theme, a night elf's in the Night Elf theme), "
			.. "instead of your Reforged UI theme. Lines with no speaker keep your theme.",
		function()
			return setting("followSpeaker")
		end,
		function(v)
			db.followSpeaker = v and true or false
		end,
		Paint)
	layout:Slider("Window size", 70, 150, 5,
		function()
			return setting("scale")
		end,
		function(v)
			db.scale = v
		end,
		function()
			if window then
				Place(window)
			end
		end)
	layout:Checkbox("Lock window", "Stop the narrator window from being dragged.",
		function()
			return setting("locked")
		end,
		function(v)
			db.locked = v and true or false
		end)
end

----------------------------------------------------------------------------
-- Startup

Spoken:RegisterNarrator(NARRATOR, {
	addon = ADDON,
	title = "Reforged UI",
	description = "The narrator in your Reforged UI theme: Warcraft III's trim around it, the console's font and colours, "
		.. "following your race's theme.",
	picture = ICON,
	Update = Update,
	settings = Settings,
})
if Spoken.SuggestNarrator then
	Spoken:SuggestNarrator(NARRATOR)
end

if Spoken.RegisterCallback then
	Spoken:RegisterCallback("AUDIO_CHANGED", Status)
	-- More is known of who speaks a line: its frame may be another race's.
	Spoken:RegisterCallback("SPEAKER_CHANGED", function(clip)
		if clip == shown and setting("followSpeaker") then
			Paint()
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	ReforgedUISpokenDB = ReforgedUISpokenDB or db
	db = ReforgedUISpokenDB
	if window then
		Place(window)
	end
end)

ReforgedUI.RegisterThemeCallback(function()
	Paint()
end)
