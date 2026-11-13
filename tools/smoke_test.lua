-- Smoke test: loads the addon against a stubbed WoW API under plain Lua 5.1
-- and drives login, layout changes, theme changes and the common events.
-- It catches typos, nil indexing and layout regressions; it is not a substitute
-- for testing in the game client.
--
--   lua5.1 tools/smoke_test.lua

local here = (arg[0]:match("^(.*)[/\\]") or ".")
local ADDON = here .. "/../ReforgedUI/"

local screenW, screenH = 1365.33, 768

----------------------------------------------------------------------------
-- Stub objects: unknown methods are no-ops; a few return useful values.

local Object = {}
allFrames = {}
local function new(kind, name, parent)
	local o = setmetatable({
		_kind = kind, _name = name, _parent = parent, _w = 0, _h = 0, _scale = 1,
		_shown = true, _points = {}, _scripts = {}, _attrs = {}, _level = 1,
	}, Object)
	if name then _G[name] = o end
	allFrames[#allFrames + 1] = o
	return o
end

local methods = {}
local noop = function() end
local VERBS = { "Set", "Enable", "Register", "Unregister", "Hide", "Show", "Remove", "Clear", "Raise", "Lower", "Hook" }
-- Unknown setters are no-ops; unknown fields and getters are nil, so missing
-- stubs fail loudly instead of hiding bugs.
Object.__index = function(t, k)
	if methods[k] then return methods[k] end
	if type(k) == "string" then
		for _, verb in ipairs(VERBS) do
			if k:sub(1, #verb) == verb then return noop end
		end
	end
	return nil
end

function methods:GetName() return self._name end
function methods:SetFont(path, size, flags)
	self._font, self._size, self._flags, self._fontSetDirectly = path, size, flags, true
	return true
end
function methods:GetFont() return self._font or "Fonts\\FRIZQT__.TTF", self._size or 12, self._flags or "" end
-- A font family: a font string given one reports its first (roman) member.
fontFamilies = {}
function CreateFontFamily(name, members)
	assert(not fontFamilies[name], "font family " .. name .. " made twice")
	local f = new("font", name)
	f._members = members
	fontFamilies[name] = f
	return f
end
function methods:SetFontObject(obj)
	if type(obj) == "table" and obj._members then
		local m = obj._members[1]
		self._fontObject, self._font, self._size, self._flags = obj, m.file, m.height, m.flags
	end
end
-- Roughly half an em per character.
function methods:GetStringWidth() return #(self._text or "") * (self._size or 12) * 0.5 end
function methods:SetSize(w, h) self._w, self._h = w, h end
function methods:SetWidth(w) self._w = w end
function methods:SetHeight(h) self._h = h end
function methods:GetWidth() return self._w end
function methods:GetHeight() return self._h end
function methods:GetSize() return self._w, self._h end
function methods:SetScale(s) assert(type(s) == "number" and s > 0, "bad scale " .. tostring(s)); self._scale = s end
function methods:GetScale() return self._scale end
function methods:GetEffectiveScale()
	return self._scale * (self._parent and self._parent:GetEffectiveScale() or 1)
end
function methods:SetParent(p) self._parent = p end
function methods:GetParent() return self._parent end
function methods:SetPoint(point, rel, relPoint, x, y)
	assert(type(point) == "string", "SetPoint needs a point")
	if x ~= nil then assert(type(x) == "number" and x == x, "bad x offset") end
	if y ~= nil then assert(type(y) == "number" and y == y, "bad y offset") end
	for i, p in ipairs(self._points) do
		if p[1] == point then
			self._points[i] = { point, rel, relPoint, x, y }
			return
		end
	end
	self._points[#self._points + 1] = { point, rel, relPoint, x, y }
end
function methods:ClearAllPoints() self._points = {} end
function methods:GetPoint(i) local p = self._points[i or 1]; if p then return unpack(p) end end
function methods:GetTop() return 100 end
function methods:GetBottom() return 10 end
function methods:GetLeft() return 20 end
function methods:StartMoving() self._moving = true end
function methods:StopMovingOrSizing() self._moving = false end
function methods:SetFrameStrata(s) self._strata = s end
function methods:GetFrameStrata() return self._strata or "MEDIUM" end
function methods:SetBlendMode() end
function methods:HookScript(k, fn)
	-- Hooks chain, as in the game: each runs after the ones before it.
	self._hooks = self._hooks or {}
	local prev = self._hooks[k]
	self._hooks[k] = prev and function(...) prev(...); fn(...) end or fn
end
function methods:SetShown(v) self._shown = not not v end
function methods:Show() self._shown = true end
function methods:Hide() self._shown = false end
function methods:IsShown() return self._shown end
function methods:IsOwned(f) return self._owner == f end
function methods:GetRegions()
	local out = {}
	for _, f in ipairs(allFrames) do
		if rawget(f, "_parent") == self and f._kind == "texture" then out[#out + 1] = f end
	end
	return unpack(out)
end
function methods:GetAtlas() return self._atlas end
function methods:SetAtlas(a) self._atlas = a end
function methods:GetTexture() return self._tex end
function methods:GetDrawLayer() return "ARTWORK", 0 end
function methods:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function methods:GetVertexColor() return 1, 1, 1, 1 end
function methods:GetBlendMode() return "BLEND" end
function methods:IsVisible()
	local p = rawget(self, "_parent")
	return self._shown and (p == nil or p:IsVisible())
end
function methods:IsProtected() return self._kind == "secure" end
function methods:SetAttribute(k, v) self._attrs[k] = v end
function methods:GetAttribute(k) return self._attrs[k] end
function methods:SetID(id) self._id = id end
function methods:GetID() return self._id or 0 end
function methods:SetFrameLevel(l) self._level = l end
function methods:GetFrameLevel() return self._level end
function methods:SetScript(k, fn) self._scripts[k] = fn end
function methods:GetScript(k) return self._scripts[k] end
function methods:CreateTexture() return new("texture", nil, self) end
function methods:CreateFontString() return new("fontstring", nil, self) end
function methods:GetNormalTexture() return new("texture", nil, self) end
function methods:SetNormalTexture(t) self._normal = t end
function methods:SetChecked(v) self._checked = v end
function methods:GetChecked() return self._checked end
methods.GetPushedTexture = methods.GetNormalTexture
methods.GetHighlightTexture = methods.GetNormalTexture
function methods:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function methods:SetText(t) self._text = t end
function methods:GetNumPoints() return #self._points end
function methods:GetObjectType()
	return self._kind == "button" and "Button" or self._kind == "texture" and "Texture" or "Frame"
end
function methods:GetChildren()
	local out = {}
	for _, f in ipairs(allFrames) do
		if rawget(f, "_parent") == self then out[#out + 1] = f end
	end
	return unpack(out)
end
function methods:SetRotation(r) assert(type(r) == "number" and r == r, "bad rotation"); self._rotation = r end
function methods:GetZoom() return 2 end
function methods:GetZoomLevels() return 6 end
function methods:SetTexture(path) if path then assert(type(path) == "string" or type(path) == "number") end self._tex = path end
function methods:SetTexCoord(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		assert(type(v) == "number" and v == v, "bad texcoord")
	end
end
function methods:RegisterEvent(e)
	assert(not e:find("BOGUS"), "unknown event")
	self._events = self._events or {}
	self._events[e] = true
end
function methods:SetAlpha(a) self._alpha = a end
function methods:GetAlpha() return self._alpha or 1 end
function methods:EnableMouse(v) self._mouse = v end
function methods:IsForbidden() return self._forbidden or false end
function methods:SetColorTexture(r, g, b) assert(r and g and b, "colour needs rgb") end
function methods:SetTextColor(r, g, b) assert(r and g and b, "colour needs rgb"); self._textColor = { r, g, b } end
function methods:GetTextColor() local c = self._textColor or { 1, 0.82, 0 }; return c[1], c[2], c[3], 1 end
function methods:SetStatusBarColor(r, g, b) assert(r and g and b, "colour needs rgb"); self._color = { r, g, b } end
function methods:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function methods:SetValue(v)
	local old = self._value
	self._value = v
	if old ~= v and self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
end
function methods:GetValue() return self._value end
function methods:GetStatusBarTexture()
	self._fill = self._fill or new("texture", nil, self)
	return self._fill
end
function methods:GetStringHeight() return 12 end
function methods:SetEnabled(v) self._enabled = v end
function methods:Click() self._clicks = (self._clicks or 0) + 1 end
function methods:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function methods:SetReverseFill(v) self._reverse = v end

----------------------------------------------------------------------------
-- Globals the addon touches

local eventFrames = {}
function CreateFrame(kind, name, parent, template)
	assert(template ~= "ActionBarButtonTemplate", "action buttons must be Blizzard's own")
	local secure = template and template:find("Secure")
	local f = new(secure and "secure" or kind, name, parent)
	eventFrames[#eventFrames + 1] = f
	return f
end

UIParent = new("frame", "UIParent")
UIParent._w, UIParent._h = screenW, screenH
EditModeManagerFrame = new("frame", "EditModeManagerFrame", UIParent)
EditModeManagerFrame._shown = false
Minimap = new("frame", "Minimap", UIParent)
Minimap.ZoomIn = new("button", nil, Minimap)
MinimapCluster = new("frame", "MinimapCluster", UIParent)
MinimapCluster.Tracking = new("button", nil, MinimapCluster)
MinimapCluster.Tracking._w, MinimapCluster.Tracking._h = 32, 32
MinimapCluster.IndicatorFrame = new("frame", nil, MinimapCluster)
GameTimeFrame = new("button", "GameTimeFrame", MinimapCluster)
GameTimeFrame._w, GameTimeFrame._h = 40, 40
-- Forever's day/night moon: a keyless child of the cluster.
MinimapCluster.DielFrame = new("frame", nil, MinimapCluster)
TimeManagerClockButton = new("button", "TimeManagerClockButton", MinimapCluster)
-- The calendar: today is Tuesday 10 November 2026, 14:30 realm time. A
-- holiday runs from the 8th to the 16th, a raid waits for an answer at 19:00
-- today, a raid lockout (left out), a declined event (left out) and an event
-- on the 20th (past the week).
local calNow = { year = 2026, month = 11, monthDay = 10, weekday = 3, hour = 14, minute = 30 }
C_DateAndTime = { GetCurrentCalendarTime = function() return calNow end }
local calPending, calendarToggles, calendarRequested = 1, 0, false
local calEvents = {}
local function calTime(d, h, m) return { year = 2026, month = 11, monthDay = d, hour = h, minute = m } end
for d = 8, 16 do
	calEvents["0:" .. d] = { { eventID = 7, title = "Hallow's End", calendarType = "HOLIDAY",
		sequenceType = d == 8 and "START" or d == 16 and "END" or "ONGOING", inviteStatus = 0,
		startTime = calTime(8, 10, 0), endTime = calTime(16, 10, 0), dontDisplayEnd = false } }
end
table.insert(calEvents["0:10"], { eventID = 50, title = "Raid night", calendarType = "GUILD_EVENT", inviteStatus = 0,
	startTime = calTime(10, 19, 0), endTime = calTime(10, 19, 0) })
table.insert(calEvents["0:10"], { eventID = 51, title = "Molten Core", calendarType = "RAID_LOCKOUT", inviteStatus = 0,
	startTime = calTime(10, 9, 0), endTime = calTime(10, 9, 0) })
table.insert(calEvents["0:12"], { eventID = 52, title = "Declined thing", calendarType = "PLAYER", inviteStatus = 2,
	startTime = calTime(12, 20, 0), endTime = calTime(12, 20, 0) })
calEvents["0:20"] = { { eventID = 53, title = "Too far", calendarType = "PLAYER", inviteStatus = 3,
	startTime = calTime(20, 20, 0), endTime = calTime(20, 20, 0) } }
C_Calendar = {
	OpenCalendar = function() calendarRequested = true end,
	GetMonthInfo = function() return { year = 2026, month = 11, numDays = 30, firstWeekday = 1 } end,
	GetNumPendingInvites = function() return calPending end,
	GetNumDayEvents = function(offset, day) local l = calEvents[offset .. ":" .. day]; return l and #l or 0 end,
	GetDayEvent = function(offset, day, i) return calEvents[offset .. ":" .. day][i] end,
}
function ToggleCalendar() calendarToggles = calendarToggles + 1 end
-- Reputation: the watched faction (absolute standing values, as the
-- client gives them), and a paragon one for later.
local watchedFaction = { factionID = 2600, name = "Nightclaw Druids", description = "Secretive druids.",
	reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 5300,
	atWarWith = false }
local paragonFactions = {}
C_Reputation = {
	GetWatchedFactionData = function() return watchedFaction end,
	IsFactionParagon = function(id) return paragonFactions[id] ~= nil end,
	GetFactionParagonInfo = function(id) local p = paragonFactions[id]; return p[1], p[2], 0, p[3] end,
}
-- A forbidden frame among UIParent's children: touching it is an error.
local forbiddenFrame = new("frame", nil, UIParent)
forbiddenFrame._forbidden = true
function forbiddenFrame:GetName() error("Attempt to access forbidden object") end
local strayButton = new("button", "ForeverMinimapThing", Minimap)
strayButton._w, strayButton._h = 24, 24
-- The group finder's eye, hidden until queued, on the map.
QueueStatusButton = new("button", "QueueStatusButton", Minimap)
QueueStatusButton._w, QueueStatusButton._h, QueueStatusButton._shown = 45, 45, false
-- The leave vehicle button: an Edit Mode frame.
MainMenuBarVehicleLeaveButton = new("button", "MainMenuBarVehicleLeaveButton", UIParent)
MainMenuBarVehicleLeaveButton._w, MainMenuBarVehicleLeaveButton._h = 32, 32
-- Another addon's minimap button (LibDBIcon): it goes in the drawer.
local addonButton = new("button", "LibDBIcon10_SomeAddon", Minimap)
addonButton._w, addonButton._h = 31, 31
-- LibDBIcon pins its buttons at MEDIUM, level 8; a pinned level ignores SetFrameLevel.
addonButton._level, addonButton._fixedLevel, addonButton._fixedStrata = 8, true, true
function addonButton:SetFrameLevel(l) if not self._fixedLevel then self._level = l end end
function addonButton:SetFrameStrata(st) if not self._fixedStrata then self._strata = st end end
function addonButton:IsFixedFrameLevel() return self._fixedLevel end
function addonButton:SetFixedFrameLevel(on) self._fixedLevel = on end
function addonButton:IsFixedFrameStrata() return self._fixedStrata end
function addonButton:SetFixedFrameStrata(on) self._fixedStrata = on end
function issecurevariable(name) return not name:find("^LibDBIcon") end
IssueReporterButton = new("button", "IssueReporterButton", UIParent)
IssueReporterButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 10)
function IssueReporterButton:GetBottom() local _, _, _, _, y = self:GetPoint(1); return y end
ChatFrame1 = new("frame", "ChatFrame1", UIParent)
ChatFrame1.ButtonFrame = new("frame", "ChatFrame1ButtonFrame", ChatFrame1)
QuickJoinToastButton = new("button", "QuickJoinToastButton", UIParent)
ChatFrameChannelButton = new("button", "ChatFrameChannelButton", ChatFrame1.ButtonFrame)
ChatFrameMenuButton = new("button", "ChatFrameMenuButton", ChatFrame1.ButtonFrame)
ChatFrameToggleVoiceDeafenButton = new("button", "ChatFrameToggleVoiceDeafenButton", ChatFrame1.ButtonFrame)
ChatFrameToggleVoiceDeafenButton:Hide()
QuickJoinToastButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 600)
ChatFrame1EditBox = new("editbox", "ChatFrame1EditBox", UIParent)
MainMenuBar = new("frame", "MainMenuBar", UIParent)
MainActionBar = new("frame", "MainActionBar", UIParent)
MainActionBar.EndCaps = new("frame", nil, MainActionBar)
MainActionBar.BorderArt = new("texture", nil, MainActionBar)
for _, spec in ipairs({ { "ActionButton", MainActionBar }, { "MultiBarBottomLeftButton" },
	{ "MultiBarBottomRightButton" }, { "MultiBarRightButton" }, { "MultiBarLeftButton" }, { "MultiBar7Button" } }) do
	local bar = spec[2] or new("frame", spec[1]:gsub("Button$", ""), UIParent)
	for i = 1, 12 do
		local b = new("secure", spec[1] .. i, bar)
		b._w, b._h = 45, 45
		b.icon = new("texture", nil, b)
		b.IconMask = new("texture", nil, b)
	end
end
BuffFrame = new("frame", "BuffFrame", UIParent)
DebuffFrame = new("frame", "DebuffFrame", UIParent)
local settingValues = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = true, PROXY_SHOW_ACTIONBAR_8 = false }
Settings = { GetSetting = function(name)
	if settingValues[name] == nil then return nil end
	return { GetValue = function() return settingValues[name] end, SetValue = function(_, v) settingValues[name] = v end }
end }
Settings.RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end
Settings.RegisterAddOnCategory = function() end
-- Dividers between buttons: per button, and from a pool on the main bar that
-- Blizzard's UpdateDividers refills.
ActionButton7.RightDivider = new("texture", nil, ActionButton7)
local dividerPool = {}
local function newDivider()
	local d = new("texture", nil, MainActionBar)
	d._atlas = "UI-HUD-ActionBar-Divider-Vertical"
	dividerPool[#dividerPool + 1] = d
	return d
end
newDivider()
MainActionBar.HorizontalDividersPool = { EnumerateActive = function()
	local i = 0
	return function() i = i + 1; return dividerPool[i] end
end }
function MainActionBar:UpdateDividers()
	for _, d in ipairs(dividerPool) do d:SetAlpha(1) end
	newDivider():SetAlpha(1)
end
MainMenuBarBackpackButton = new("button", "MainMenuBarBackpackButton", UIParent)
for i = 0, 3 do new("button", "CharacterBag" .. i .. "Slot", UIParent) end
TargetFrame = new("secure", "TargetFrame", UIParent)
TargetFrameToT = new("secure", "TargetFrameToT", TargetFrame)
-- Blizzard's aura container (modern clients): the target counts as
-- friendly or not, which decides whether buffs or debuffs come first.
local targetAuraContainer = { friendly = false }
function targetAuraContainer:SetTargetIsFriendly(v) self.friendly = v == true end
function targetAuraContainer:IsTargetFriendly() return self.friendly end
function TargetFrame:GetAuraContainer() return targetAuraContainer end
function TargetFrame:ConfigureAuraContainer() targetAuraContainer:SetTargetIsFriendly(false) end
TargetFrame.TargetFrameContainer = new("frame", nil, TargetFrame)
TargetFrame.TargetFrameContent = new("frame", nil, TargetFrame)
local targetHealthArt = new("texture", nil, TargetFrame.TargetFrameContent)
TargetFrame.TargetFrameContent.TargetFrameContentMain = new("frame", nil, TargetFrame.TargetFrameContent)
local targetRepColor = new("texture", nil, TargetFrame.TargetFrameContent.TargetFrameContentMain)
TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor = targetRepColor
local targetName = new("fontstring", nil, TargetFrame.TargetFrameContent.TargetFrameContentMain)
TargetFrame.TargetFrameContent.TargetFrameContentMain.Name = targetName
TargetFrameSpellBar = new("frame", "TargetFrameSpellBar", TargetFrame)
TargetFrameBuff1 = new("button", "TargetFrameBuff1", TargetFrame)
local targetFrameArt = new("texture", nil, TargetFrame)
StanceBar = new("secure", "StanceBar", UIParent)
PetActionBar = new("secure", "PetActionBar", UIParent)
for i = 1, 10 do
	new("secure", "StanceButton" .. i, StanceBar)._w = 30
	new("secure", "PetActionButton" .. i, PetActionBar)._w = 30
end
PlayerCastingBarFrame = new("frame", "PlayerCastingBarFrame", UIParent)
ObjectiveTrackerFrame = new("frame", "ObjectiveTrackerFrame", UIParent)
ObjectiveTrackerFrame._h = 400
-- The micro menu (Edit Mode's container, its buttons inside), scaled by
-- Edit Mode's size setting.
MicroMenuContainer = new("frame", "MicroMenuContainer", UIParent)
MicroMenu = new("frame", "MicroMenu", MicroMenuContainer)
MicroMenu._scale = 0.9
for _, name in ipairs({ "CharacterMicroButton", "PlayerSpellsMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
	"GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton",
	"MainMenuMicroButton", "SocialsMicroButton", "WorldMapMicroButton" }) do
	local b = new("button", name, MicroMenu)
	b._w, b._h = 32, 40
end
-- A feature Forever doesn't have, the container's own border, and a stray
-- frame left in the container.
HousingMicroButton = new("button", "HousingMicroButton", MicroMenu)
-- Forever's classic talent and spellbook buttons, next to the newer one.
for _, name in ipairs({ "TalentMicroButton", "SpellbookMicroButton", "LegacyMicroButton" }) do
	local b = new("button", name, MicroMenu)
	b._w, b._h = 32, 40
end
HousingMicroButton._w, HousingMicroButton._h = 32, 40
local microBorder = new("texture", nil, MicroMenuContainer)
local microStray = new("frame", nil, MicroMenuContainer)
-- The shop is hidden until Blizzard shows it; one micro button we have no
-- name for, and a forbidden child.
StoreMicroButton._shown = false
local unnamedMicro = new("button", nil, MicroMenu)
unnamedMicro._w, unnamedMicro._h = 32, 40
function unnamedMicro:GetName() return "FancyMicroButton" end
local forbiddenMicro = new("button", nil, MicroMenu)
forbiddenMicro._forbidden = true
function forbiddenMicro:GetName() error("Attempt to access forbidden object") end
GameTooltip = new("frame", "GameTooltip", UIParent)
-- Blizzard's border and the unit health bar under it (SharedTooltipTemplates.xml).
GameTooltip.NineSlice = new("frame", nil, GameTooltip)
GameTooltip.StatusBar = new("frame", "GameTooltipStatusBar", GameTooltip)
GameTooltip.StatusBar._shown = false
ItemRefTooltip = new("frame", "ItemRefTooltip", UIParent)
ItemRefTooltip.NineSlice = new("frame", nil, ItemRefTooltip)
function methods:SetClampRectInsets(l, r, t, b) self._clamp = { l, r, t, b } end
function SharedTooltip_SetBackdropStyle(tip) if tip.NineSlice then tip.NineSlice:SetAlpha(1) end end
PlayerFrame = new("secure", "PlayerFrame", UIParent)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4)
function PlayerFrame:GetTop() local _, _, _, _, y = self:GetPoint(1); return 768 + y end
local gameHour = 0
function GetGameTime() return gameHour, 0 end
local localClock = { hour = 21, min = 7 }
function date(fmt) assert(fmt == "*t"); return { hour = localClock.hour, min = localClock.min } end
function GetMoney() return 1234567 end
function GetInventoryItemDurability(slot) if slot == 5 then return 20, 100 end end
ContainerFrame1 = new("frame", "ContainerFrame1", UIParent)
ContainerFrame1:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 60)

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flushTimers()
	local list = timers
	timers = {}
	for _, fn in ipairs(list) do fn() end
end
function securecallfunction(fn, ...) return fn(...) end
function RegisterUnitWatch() end
-- No target until the target display tests pick one.
local hasTarget, totIsPlayer, hasPet = false, false, false
function UnitExists(u) if u == "pet" then return hasPet end return u == "player" or hasTarget end
function UnitIsUnit(a, b) return a == b or (a == "targettarget" and b == "player" and totIsPlayer) end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function GetTime() return 100 end
function GetNetStats() return 1.5, 0.5, 40, 180 end
function GetFramerate() return 59.6 end
function UnitIsPlayer() return false end
function UnitReaction() return 2 end
function UnitClassification() return "elite" end
function UnitCreatureType() return "Beast" end
function GetComboPoints() return 3 end
function SetPortraitTexture() end
function IsAltKeyDown() return false end
function UnitDamage() return 10.4, 15.6, 5, 8 end
function UnitRangedDamage() return 2.8, 20, 30 end
function UnitArmor() return 900, 1000 end
function GetInventoryItemID(_, slot) if slot == 17 then return 1201 end if slot == 0 then return 2512 end end
function GetInventoryItemCount(_, slot) return slot == 0 and 350 or 1 end
function GetItemInfoInstant(id) if id == 1201 then return id, "Armor", "Shields", "INVTYPE_SHIELD" end end
function GetBlockChance() return 13.4 end
function GetShieldBlock() return 10 end
function GetSpellBonusDamage(school) return school * 10 end
function GetSpellBonusHealing() return 207 end
local secret = false
function issecretvalue() return secret end
function UnitAffectingCombat() return false end
function IsResting() return true end
function UnitIsPVP() return true end
function UnitIsPVPFreeForAll() return false end
function HasNewMail() return false end
function UnitAttackSpeed() return 2.0, nil end
C_PaperDollInfo = { OffhandHasShield = function() return true end }
local placed
-- The client reports action range per slot once asked (EnableActionRangeCheck).
local rangeChecked = {}
C_ActionBar = { EnableActionRangeCheck = function(slot, on) rangeChecked[slot] = on end }
-- Action slots: one spell left on Action Bar 8's second button (slot 170)
-- from before the minimap bar had its own slots.
local actions, cursorAction = { [170] = "Lightning Bolt" }, nil
function GetCursorInfo() return placed == "cursor" and "item" or nil end
function HasAction(slot) return actions[slot] ~= nil end
function PickupAction(slot) cursorAction, actions[slot] = actions[slot], nil end
function PlaceAction(slot)
	placed = slot
	if cursorAction then actions[slot], cursorAction = cursorAction, nil end
end
function ClearCursor() cursorAction = nil end
C_Item = { GetItemCount = function() return 1 end, PickupItem = function() placed, cursorAction = "cursor", "Hearthstone" end }
function GetRealmName() return "Forever" end
UISpecialFrames = {}
tinsert = table.insert
function ReloadUI() end
StaticPopupDialogs = {}
local popups = {}
function StaticPopup_Show(which, text)
	popups[#popups + 1] = { which = which, text = text }
end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
FACTION_BAR_COLORS = { [2] = { r = 1, g = 0.3, b = 0 } }

local savedLayouts
Enum = Enum or {}
Enum.EditModeSystem = { ActionBar = 0, CastBar = 1, UnitFrame = 3, AuraFrame = 6, VehicleLeaveButton = 9 }
Enum.EditModeAuraFrameSystemIndices = { BuffFrame = 1, DebuffFrame = 2 }
Enum.EditModeCastBarSetting = { LockToPlayerFrame = 0 }
Enum.EditModeUnitFrameSystemIndices = { Target = 1, Party = 2 }
Enum.EditModeUnitFrameSetting = { BuffsOnTop = 2, UseRaidStylePartyFrames = 4, FrameSize = 16 }
Enum.EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, PetActionBar = 13 }
Enum.EditModeActionBarSetting = { IconSize = 3, IconPadding = 4, HideBarArt = 6, HideBarScrolling = 7,
	AlwaysShowButtons = 8 }
Enum.EditModeLayoutType = { Account = 1 }
-- Loot rules: solo until a test puts us in a group.
Enum.LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 }
local loot = { inGroup = false, leader = false, method = 3, threshold = 2, sets = {} }
function IsInGroup() return loot.inGroup end
function IsInRaid() return false end
function UnitIsGroupLeader(u) return u == "player" and loot.leader end
function GetLootThreshold() return loot.threshold end
function SetLootThreshold(q) loot.sets[#loot.sets + 1] = "threshold " .. q; loot.threshold = q end
C_PartyInfo = {
	GetLootMethod = function() return loot.method, loot.partyID, loot.raidID end,
	IsLootMethodAvailable = function(m) return m ~= 5 end,
	SetLootMethod = function(m, who) loot.sets[#loot.sets + 1] = "method " .. m .. " " .. tostring(who) end,
}
local cvars = { raidFramesDisplayClassColor = "0", raidFramesDisplayPowerBars = "0" }
C_CVar = { GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = v end }
local activeLayout
C_EditMode = {
	GetLayouts = function()
		if savedLayouts then
			return savedLayouts
		end
		return { activeLayout = 3, layouts = { { layoutName = "Mine", systems = {
			{ system = 12, anchorInfo = { point = "TOPRIGHT", relativeTo = "ReforgedUIConsole", relativePoint = "BOTTOMLEFT",
				offsetX = 1000, offsetY = 600 }, isInDefaultPosition = false },
			{ system = 0, systemIndex = 1, anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM" },
				settings = { { setting = 3, value = 5 } } },
			{ system = 1, anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetY = 120 },
				isInDefaultPosition = true },
			{ system = 3, systemIndex = 2, settings = { { setting = 4, value = 0 } } },
			{ system = 3, systemIndex = 1, isInDefaultPosition = true, settings = { { setting = 2, value = 0 } } },
			{ system = 0, systemIndex = 2, settings = { { setting = 3, value = 100 } } },
			{ system = 6, systemIndex = 1, isInDefaultPosition = true },
			{ system = 6, systemIndex = 2, isInDefaultPosition = true },
			{ system = 0, systemIndex = 13, isInDefaultPosition = true },
			{ system = 9, isInDefaultPosition = true },
		} }, { layoutName = "Locked", systems = {
			{ system = 1, isInDefaultPosition = true, settings = { { setting = 0, value = 1 } } },
			{ system = 6, systemIndex = 1, isInDefaultPosition = false, anchorInfo = { point = "TOPLEFT",
				relativeTo = "UIParent", relativePoint = "TOPLEFT", offsetX = 300, offsetY = -200 } },
			{ system = 0, systemIndex = 13, isInDefaultPosition = false, anchorInfo = { point = "CENTER",
				relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } },
			{ system = 9, isInDefaultPosition = false, anchorInfo = { point = "TOP",
				relativeTo = "UIParent", relativePoint = "TOP", offsetX = 0, offsetY = -100 } },
		} } } }
	end,
	SaveLayouts = function(info) savedLayouts = info end,
	SetActiveLayout = function(i) activeLayout = i end,
}

local inCombat = false
function InCombatLockdown() return inCombat end
local hooks = {}
function hooksecurefunc(a, b, c)
	if type(a) == "string" then
		local orig = _G[a]
		_G[a] = function(...) orig(...); b(...) end
		hooks[a] = true
	else
		local orig = a[b]
		a[b] = function(...) orig(...); c(...) end
	end
end
function updateContainerFrameAnchors() end
stateDrivers = {}
function RegisterStateDriver(f, _, v) stateDrivers[f] = v end
function geterrorhandler() return function(err) error(err, 0) end end
-- Keys: Action Bar 8's second button had F2 (the old minimap slot 2).
local bindings = { ACTIONBUTTON1 = { "1", "SHIFT-1" }, MULTIACTIONBAR7BUTTON2 = { "F2" } }
local bindingsSaved = 0
function GetBindingKey(cmd) return unpack(bindings[cmd] or {}) end
function SetBinding(key, cmd)
	for _, keys in pairs(bindings) do
		for i = #keys, 1, -1 do
			if keys[i] == key then table.remove(keys, i) end
		end
	end
	bindings[cmd] = bindings[cmd] or {}
	table.insert(bindings[cmd], key)
end
function SaveBindings() bindingsSaved = bindingsSaved + 1 end
function GetCurrentBindingSet() return 2 end
local overrides = 0
function SetOverrideBindingClick(_, _, key, name) assert(_G[name], "binding target missing"); overrides = overrides + 1 end
function ClearOverrideBindings() overrides = 0 end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
playerRace, playerRaceFile, playerFaction, playerRaceID = "Orc", "Orc", "Horde", nil
function UnitRace() return playerRace, playerRaceFile, playerRaceID end
function UnitFactionGroup() return playerFaction end
function UnitName() return "Thrall" end
-- Forever returns a character's surname where the realm would be.
function GetUnitName(unit, full)
	local name = UnitName(unit)
	if full and unit == "player" then return name .. " Son of Durotan" end
	return name
end
function UnitLevel() return 12 end
function UnitClass() return "Shaman", "SHAMAN" end
-- One totem down (Searing Totem in the fire slot), the others empty.
function GetTotemInfo(slot)
	if slot == 1 then return true, "Searing Totem", 100, 55, 135825 end
	return false, "", 0, 0, 0
end
function GetTotemTimeLeft(slot) return slot == 1 and 42.3 or 0 end
function UnitHealth() return 300 end
function UnitHealthMax() return 450 end
function UnitPower() return 120 end
function UnitPowerMax() return 200 end
function UnitPowerType() return 0, "MANA" end
function UnitXP() return 1000 end
function UnitXPMax() return 4000 end
function GetXPExhaustion() return 500 end
function GetMaxPlayerLevel() return 60 end
function GetMinimapZoneText() return "Durotar" end
function GetZonePVPInfo() return "contested" end
C_Container = {
	ContainerIDToInventoryID = function(bag) if bag >= 1 and bag <= 4 then return 19 + bag end error("bad bag") end,
	GetContainerNumFreeSlots = function() return 5 end,
	GetContainerNumSlots = function() return 16 end,
}
function GetInventoryItemTexture() return nil end
RAID_CLASS_COLORS = { SHAMAN = { WrapTextInColorCode = function(_, s) return s end } }
PowerBarColor = { MANA = { r = 0, g = 0.5, b = 1 } }
NUM_CHAT_WINDOWS = 10
function FCF_SavePositionAndDimensions() end
function GameTooltip_Hide() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
	local out = {}
	for piece in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = piece end
	if n and #out > n then
		local rest = table.concat(out, sep, n)
		for i = #out, n, -1 do out[i] = nil end
		out[n] = rest
	end
	return unpack(out)
end
SlashCmdList = {}
local printed = {}
function print(...)
	local parts = { ... }
	for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
	printed[#printed + 1] = table.concat(parts, " ")
end

----------------------------------------------------------------------------
-- Load the addon in TOC order

local ns = {}
local files = {}
for line in io.lines(ADDON .. "ReforgedUI.toc") do
	if line:match("^[%w_\\%.%-]+%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
end
assert(#files >= 10, "TOC lists too few files")
for _, file in ipairs(files) do
	assert(loadfile(ADDON .. file))("ReforgedUI", ns)
end

-- Secret values go through Core.lua's helpers, which say what the code may
-- do with a value; no other file asks the game itself (each used to have a
-- helper of its own, no two meaning quite the same).
do
	for _, file in ipairs(files) do
		if file ~= "Core.lua" and not file:find("^Libs/") then
			local f = assert(io.open(ADDON .. file))
			local n = 0
			for line in f:lines() do
				n = n + 1
				assert(not line:gsub("%-%-.*", ""):find("issecretvalue"),
					("%s:%d calls issecretvalue: use ns.IsSecret, ns.IsKnown or ns.IsNumber"):format(file, n))
			end
			f:close()
		end
	end
	local hidden = newproxy(true)
	local mt = getmetatable(hidden)
	mt.__eq = function() error("compared a secret value") end
	mt.__lt, mt.__le = mt.__eq, mt.__eq
	local was = issecretvalue
	issecretvalue = function(v) return rawequal(v, hidden) end
	assert(ns.IsSecret(hidden) == true and ns.IsSecret(nil) == false and ns.IsSecret(5) == false, "IsSecret")
	assert(not ns.IsKnown(hidden) and not ns.IsKnown(nil) and ns.IsKnown(false) and ns.IsKnown(0), "IsKnown")
	assert(not ns.IsNumber(hidden) and not ns.IsNumber(nil) and not ns.IsNumber("5") and ns.IsNumber(5), "IsNumber")
	-- A client without secret values: nothing is.
	issecretvalue = nil
	assert(ns.IsSecret(hidden) == false and ns.IsKnown(1) and ns.IsNumber(1), "no secret values on older clients")
	issecretvalue = was
end

-- The game's damage meter (Blizzard_DamageMeter), as far as Reforged UI:
-- Damage Meter touches it: one window with a bar in its list, its own bar for
-- the player and a breakdown window with a bar.
local function newEntry(parent)
	local e = new("button", nil, parent)
	e.StatusBar = new("statusbar", nil, e)
	local barTex = new("texture", nil, e.StatusBar)
	e.StatusBar.GetStatusBarTexture = function() return barTex end
	e.StatusBar.Name = new("fontstring", nil, e.StatusBar)
	e.StatusBar.Value = new("fontstring", nil, e.StatusBar)
	e.StatusBar.Background = new("texture", nil, e.StatusBar)
	e.StatusBar.BackgroundEdge = new("texture", nil, e.StatusBar)
	for k, v in pairs(DamageMeterEntryMixin) do e[k] = v end
	return e
end
local function newList(parent)
	local list = new("frame", nil, parent)
	list._frames = { newEntry(list) }
	list.GetFrames = function(self) return self._frames end
	return list
end
DamageMeterEntryMixin = { UpdateStyle = function(self) self._styled = (self._styled or 0) + 1 end }
local dmEarlyEntry = newEntry(UIParent) -- made before the skin loads
DamageMeter = new("frame", "DamageMeter", UIParent)
function DamageMeter:SetupSessionWindow() end
do
	local w = new("frame", "DamageMeterSessionWindow1", DamageMeter)
	w.Header = new("texture", nil, w)
	w.SetMinimized = function(self, m) self.isMinimized = m; self.MinimizeContainer:SetShown(not m) end
	local c = new("frame", nil, w)
	w.MinimizeContainer = c
	c.Background = new("texture", nil, c)
	c.ScrollBox = newList(c)
	c.ScrollBox._frames[2] = dmEarlyEntry
	c.LocalPlayerEntry = newEntry(c)
	local s = new("frame", nil, c)
	c.SourceWindow = s
	s.Background = new("texture", nil, s)
	s.ScrollBox = newList(s)
end
function methods:SetColorTexture(r, g, b, a) assert(r and g and b, "colour needs rgb"); self._color = { r, g, b, a }; self._tex = nil end

-- Reforged UI: Damage Meter, a separate addon that needs Reforged UI.
local DM_ADDON = ADDON .. "../ReforgedUI_DamageMeter/"
do
	local dmFiles = {}
	for line in io.lines(DM_ADDON .. "ReforgedUI_DamageMeter.toc") do
		if line:match("^## Dependencies:") then
			assert(line:find("ReforgedUI", 1, true), "the damage meter skin needs Reforged UI")
		end
		if line:match("^[%w_\\%.%-]+%.lua$") then dmFiles[#dmFiles + 1] = (line:gsub("\\", "/")) end
	end
	assert(#dmFiles >= 1, "the damage meter skin's TOC lists no files")
	for _, file in ipairs(dmFiles) do
		assert(loadfile(DM_ADDON .. file))("ReforgedUI_DamageMeter", {})
	end
end

-- The game's bag windows, as far as Reforged UI: Bags touches them.
local function newBagWindow(name, bagID)
	local w = _G[name] or new("frame", name, UIParent)
	w.NineSlice = new("frame", nil, w)
	w.Bg = new("frame", nil, w)
	w.PortraitContainer = new("frame", nil, w)
	w.PortraitContainer.portrait = new("texture", nil, w.PortraitContainer)
	w.TitleContainer = new("frame", nil, w)
	w.TitleContainer.TitleText = new("fontstring", nil, w.TitleContainer)
	w.GetBagID = function() return bagID end
	w.UpdateMiscellaneousFrames = function(self) self._misc = (self._misc or 0) + 1 end
	return w
end
newBagWindow("ContainerFrame1", 0)
newBagWindow("ContainerFrame2", 1)
newBagWindow("ContainerFrameCombinedBags", 0)

-- Reforged UI: Bags, a separate addon that needs Reforged UI. BetterBags.lua
-- is loaded first without BetterBags (it must do nothing), then with a
-- stand-in for BetterBags' theme module.
local BAGS_ADDON = ADDON .. "../ReforgedUI_Bags/"
local bagFiles = {}
for line in io.lines(BAGS_ADDON .. "ReforgedUI_Bags.toc") do
	if line:match("^## Dependencies:") then
		assert(line:find("ReforgedUI", 1, true), "the bags skin needs Reforged UI")
	end
	if line:match("^## OptionalDeps:") then
		assert(line:find("BetterBags", 1, true), "BetterBags loads before the bags skin")
	end
	if line:match("^[%w_\\%.%-]+%.lua$") then bagFiles[#bagFiles + 1] = (line:gsub("\\", "/")) end
end
assert(#bagFiles >= 2, "the bags skin's TOC lists its files")
for _, file in ipairs(bagFiles) do
	assert(loadfile(BAGS_ADDON .. file))("ReforgedUI_Bags", {})
end
assert(not LibStub("AceAddon-3.0", true), "no AceAddon without BetterBags")
-- A stand-in for BetterBags' Sonata: it keeps the registered theme, says which
-- theme is applied, and records each apply.
local sonata = { themes = {}, applies = {} }
function sonata:RegisterTheme(t) self.themes[t.Name] = t end
function sonata:GetCurrentThemeKey() return self.current end
function sonata:ApplyTheme(ctx, key, save)
	assert(ctx and ctx.event, "applied with a context")
	self.applies[#self.applies + 1] = { key = key, save = save }
end
-- Sonata's resolution of variables: every "$Name" string becomes the
-- variable's value; a function is called each time the theme is applied.
local function resolveTheme(t)
	local vars = {}
	for k, v in pairs(t.Variables or {}) do
		if type(v) == "function" then v = v() end
		assert(v ~= nil, "variable " .. k .. " has a value")
		vars[k] = v
	end
	local function sub(v)
		if type(v) == "string" and v:match("^%$") then
			local name = v:sub(2)
			assert(vars[name] ~= nil, "unknown variable " .. v)
			return vars[name]
		elseif type(v) == "table" then
			local out = {}
			for k, x in pairs(v) do out[k] = sub(x) end
			return out
		end
		return v
	end
	return { Windows = sub(t.Windows), Elements = sub(t.Elements) }
end
-- And for BetterBags Next's (SonataNext): its own registry, the same
-- registration path through Sonata, data only (no function anywhere).
local sonataNext = { themes = {}, applies = {} }
local function dataOnly(v, path)
	assert(type(v) ~= "function" and type(v) ~= "userdata", path .. " is data")
	if type(v) == "table" then
		assert(getmetatable(v) == nil, path .. " is plain data")
		for k, x in pairs(v) do dataOnly(x, path .. "." .. tostring(k)) end
	end
end
function sonataNext:RegisterTheme(t)
	assert(not self.themes[t.Name], "one Next theme per name")
	dataOnly(t, t.Name)
	self.themes[t.Name] = t
end
function sonataNext:GetCurrentThemeKey() return self.current end
function sonataNext:ApplyTheme(ctx, key, save)
	assert(ctx and ctx.event, "applied with a context")
	self.applies[#self.applies + 1] = { key = key, save = save }
end
function sonata:RegisterNextTheme(t) sonataNext:RegisterTheme(t) end
do
	local ace = LibStub:NewLibrary("AceAddon-3.0", 1)
	local bbContext = { New = function(_, event) return { event = event } end }
	local bb = {}
	function bb:GetModule(name) return ({ Sonata = sonata, SonataNext = sonataNext, Context = bbContext })[name] end
	function ace:GetAddon(name) return name == "BetterBags" and bb or nil end
	assert(loadfile(BAGS_ADDON .. "BetterBags.lua"))("ReforgedUI_Bags", {})
end
assert(sonata.themes.ReforgedUI, "the BetterBags theme is registered")
assert(sonata.themes.ReforgedUI.DisplayName == "Reforged UI", "listed as Reforged UI")
assert(sonataNext.themes.ReforgedUI, "the BetterBags Next theme is registered")
assert(sonataNext.themes.ReforgedUI.DisplayName == "Reforged UI", "listed in Next as Reforged UI")

local function fire(event, ...)
	for _, f in ipairs(eventFrames) do
		local ev = f._events
		if ev and ev[event] then
			f._scripts.OnEvent(f, event, ...)
		end
	end
end

-- Settings from version 1 had a scale of 1, now far too big; versions before
-- 4 had options for the centre modes, chat width and placement and hiding
-- the bags, all gone now. The console's options were saved under an older
-- key then.
ReforgedUIDB = { scale = 1, theme = "auto",
	wiii = { center = "noinv", hideBags = true, chatWidth = 900, placeChat = false, uiScale = 240, hideMicro = true,
		targetMode = "plate", addonDrawerOpen = true } }
fire("PLAYER_LOGIN")

-- From here on every option read or set must be one Core.lua lists (with its
-- default, or among the unset ones): checked at the end.
local strayOptions = {}
do
	local function note(key)
		if not ns:KnownOption(key) and not strayOptions[key] then
			local where = debug.traceback("", 3):match("\n%s*([^\n]-:%d+):") or "?"
			strayOptions[key] = where:find("smoke_test", 1, true) and "?" or where
		end
	end
	setmetatable(ReforgedUIDB.consoleOpts, {
		__index = function(_, key) note(key) end,
		__newindex = function(t, key, value) note(key); rawset(t, key, value) end,
	})
	for key in pairs(ReforgedUIDB.consoleOpts) do
		note(key)
	end
	assert(ns:KnownOption("uiScale") and ns:KnownOption("targetAuraLast") and not ns:KnownOption("noSuchOption"),
		"options are known by their defaults")
	assert(ReforgedUIDB.consoleOpts.clockTime == "server" and ReforgedUIDB.consoleOpts.clockHours == 24,
		"the time capsule's options have their defaults")
end
assert(ns.ready, "init did not finish")
assert(ReforgedUIDB.scale == 0.75 and ReforgedUIDB.version == 5, "old default scale not migrated")
assert(ReforgedUIDB.consoleOpts.uiScale == 240 and ReforgedUIDB.consoleOpts.zoneText == 1, "console option defaults")
assert(ReforgedUIDB.wiii == nil and ReforgedUIDB.consoleOpts.targetMode == "plate", "options under the old key are kept")
ReforgedUIDB.consoleOpts.targetMode = "swap"
do
	local o = ReforgedUIDB.consoleOpts
	assert(o.center == nil and o.hideBags == nil and o.chatWidth == nil and o.placeChat == nil and o.hideMicro == nil,
		"removed options should be dropped from saved settings")
end
fire("PLAYER_ENTERING_WORLD")
flushTimers()
local repaired = savedLayouts and savedLayouts.layouts[1].systems[1]
assert(repaired and repaired.anchorInfo.relativeTo == "UIParent" and repaired.isInDefaultPosition,
	"Edit Mode anchors to our frames should be repaired")
do
	-- A "Reforged UI" layout is made from the active one (and switched to
	-- once): cast bar above the console, raid-style party frames, raid frame
	-- options on. Other layouts' default cast bars are raised too, not one
	-- locked to the player frame.
	local L = savedLayouts.layouts
	local ours = L[3]
	assert(#L == 3 and ours.layoutName == ns.EDIT_LAYOUT and ours.layoutType == 1, "Edit Mode layout made")
	assert(activeLayout == 2 + 3, "switched to the Reforged UI layout")
	-- Blizzard applies layout changes made from addon code as tainted code,
	-- so a reload is offered after them.
	local last = popups[#popups]
	assert(last and StaticPopupDialogs[last.which].OnAccept and last.text:find("switched"),
		"a reload is offered after setting up Edit Mode")
	local top = ns.layout.consoleTop * ns:ConsoleScale()
	for _, layout in ipairs({ L[1], ours }) do
		local cast = layout.systems[3]
		assert(not cast.isInDefaultPosition and cast.anchorInfo.relativeTo == "UIParent"
			and cast.anchorInfo.offsetY > top, "cast bar raised above the console")
	end
	assert(ours.systems[4].settings[1].value == 1 and L[1].systems[4].settings[1].value == 0,
		"raid-style party frames in our layout only")
	assert(ours.systems[1].anchorInfo.relativeTo == "UIParent", "the copy is of the repaired layout")
	-- Buffs start just below the top bar, debuffs under them, in the layout
	-- (so Edit Mode can still move them); a player's own place is kept.
	for _, layout in ipairs({ L[1], ours }) do
		local buffs, debuffs = layout.systems[7].anchorInfo, layout.systems[8].anchorInfo
		assert(not layout.systems[7].isInDefaultPosition and buffs.point == "TOPRIGHT"
			and buffs.relativeTo == "UIParent" and buffs.offsetX < 0 and buffs.offsetY < 0, "buffs below the top bar")
		assert(debuffs.relativeTo == "BuffFrame" and debuffs.point == "TOPRIGHT", "debuffs under the buffs")
	end
	assert(L[2].systems[2].anchorInfo.offsetX == 300, "buffs the player moved stay put")
	assert(ns.db.consoleOpts.buffSpot and ns.db.consoleOpts.buffSpot.y == ours.systems[7].anchorInfo.offsetY,
		"the buffs' place is remembered")
	-- The pet bar starts just above the stance row in the layouts (Edit Mode
	-- moves it from there); a player's own place is kept.
	local petSpot = ns:PetBarSpot()
	for _, layout in ipairs({ L[1], ours }) do
		local pet = layout.systems[9]
		assert(pet.systemIndex == 13 and not pet.isInDefaultPosition and pet.anchorInfo.point == "BOTTOMLEFT"
			and pet.anchorInfo.relativeTo == "UIParent" and pet.anchorInfo.offsetX == petSpot.x
			and pet.anchorInfo.offsetY == petSpot.y, "pet bar placed above the stance row")
	end
	assert(L[2].systems[3].anchorInfo.point == "CENTER", "a pet bar the player moved stays put")
	assert(ns.db.consoleOpts.petSpot and ns.db.consoleOpts.petSpot.y == petSpot.y, "the pet bar's place is remembered")
	-- It starts at about the stance buttons' size (in 10% steps), padding
	-- at least 2.
	local petSettings = {}
	for _, entry in ipairs(L[1].systems[9].settings or {}) do
		petSettings[entry.setting] = entry.value
	end
	local petPct = math.floor(petSpot.size / 30 * 10 + 0.5) * 10
	assert(petSettings[3] == math.max(50, math.min(200, petPct)) and petSettings[4] >= 2, "pet bar icon size")
	-- Without stance buttons the pet bar takes the stance row.
	assert(ns:PetRow() == ns.layout.pet, "pet row above the stance row")
	GetNumShapeshiftForms = function() return 0 end
	assert(ns:PetRow() == ns.layout.stance and ns:PetBarSpot().y < petSpot.y, "pet bar on the stance row")
	GetNumShapeshiftForms = nil
	-- The leave vehicle (flight stop) button starts just above the minimap's
	-- top-left corner, clear of the top bar; a player's own place is kept.
	local leaveSpot = ns:LeaveButtonSpot()
	local mmTop = ns.layout.minimap.y + ns.layout.minimap.h
	assert(leaveSpot and leaveSpot.y >= mmTop and math.abs(leaveSpot.x - ns.layout.minimap.x) < 1,
		"leave button spot above the map's top-left corner")
	for _, layout in ipairs({ L[1], ours }) do
		local leave = layout.systems[10]
		assert(leave.system == 9 and not leave.isInDefaultPosition and leave.anchorInfo.point == "BOTTOMLEFT"
			and leave.anchorInfo.relativeTo == "UIParent" and leave.anchorInfo.offsetX == leaveSpot.x
			and leave.anchorInfo.offsetY == leaveSpot.y, "leave button placed above the minimap")
	end
	assert(L[2].systems[4].anchorInfo.point == "TOP", "a leave button the player moved stays put")
	assert(ns.db.consoleOpts.leaveSpot and ns.db.consoleOpts.leaveSpot.y == leaveSpot.y,
		"the leave button's place is remembered")
	assert(#MainMenuBarVehicleLeaveButton._points == 0, "the leave button is only moved through Edit Mode")
	-- Blizzard's target frame, buffs on top, puts its first aura icon at the
	-- target aura spot: above the plate (the mode at login), then beside the
	-- target of target once swap mode is picked.
	local k = ns:ConsoleScale()
	local function auraAt(spot, what)
		local tf = savedLayouts.layouts[3].systems[5]
		assert(not tf.isInDefaultPosition and tf.settings[1].value == 1, "target frame placed, buffs on top")
		assert(math.abs(tf.anchorInfo.offsetX + 5 - spot.x0 * k) <= 1
			and math.abs(tf.anchorInfo.offsetY - 15 - spot.y * k) <= 1, "target auras " .. what)
	end
	auraAt(ns.layout.targetAuras.plate, "above the plate")
	ns.modules.target:SetMode("swap")
	auraAt(ns.layout.targetAuras.swap, "beside the target of target")
	-- The game only takes the layout in at a reload, and only the active
	-- layout counts: the login check says so in chat when the icons are off.
	do
		local T, tf = ns.modules.target, savedLayouts.layouts[3].systems[5]
		local oldLeft, oldTop, oldScale, oldActive = TargetFrame.GetLeft, TargetFrame.GetTop, TargetFrame._scale,
			savedLayouts.activeLayout
		local dy = 0
		TargetFrame._scale = 1
		TargetFrame.GetLeft = function() return tf.anchorInfo.offsetX end
		TargetFrame.GetTop = function() return tf.anchorInfo.offsetY + dy end
		savedLayouts.activeLayout = 2 + 3
		local said = #printed
		T:CheckAuraSpot()
		assert(#printed == said, "icons in place: nothing said")
		dy = 100
		T:CheckAuraSpot()
		assert(#printed == said + 1 and printed[#printed]:find("/reload"), "icons off in our layout: reload hint")
		ns:SayOtherEditLayout() -- on our layout: forgets what it said
		savedLayouts.activeLayout = 3
		local mine = 'on the "Mine" Edit Mode layout, not "Reforged UI"'
		T:CheckAuraSpot()
		assert(printed[#printed]:find(mine, 1, true) and printed[#printed]:find("move them yourself", 1, true),
			"icons off in another layout: names it, and that its frames are the player's to move")
		said = #printed
		ns:SayOtherEditLayout()
		assert(#printed == said, "said once per layout and session")
		EditModeManagerFrame._hooks.OnHide()
		flushTimers()
		assert(#printed == said, "closing Edit Mode on the same layout: nothing new")
		local offered = #popups
		T:SetMode("plate")
		assert(#popups == offered + 1 and popups[#popups].text:find("above the wall plate"),
			"switching to the plate says the icons move at a reload")
		assert(printed[#printed]:find(mine, 1, true), "and that another layout is active")
		savedLayouts.activeLayout = 2 + 3
		said = #printed
		ns:SayOtherEditLayout()
		assert(#printed == said, "nothing said on our own layout")
		savedLayouts.activeLayout = 3
		local now
		for _, line in ipairs(T:DescribeAuras()) do
			now = now or line:find("^now: first icon at %d+,%d+ %(%d+ off%)")
		end
		assert(now, "/rui auras shows where they are")
		T:SetMode("swap")
		auraAt(ns.layout.targetAuras.swap, "back beside the target of target")
		TargetFrame.GetLeft, TargetFrame.GetTop, TargetFrame._scale = oldLeft, oldTop, oldScale
		savedLayouts.activeLayout = oldActive
	end
	assert(L[1].systems[5].isInDefaultPosition, "other layouts keep their target frame")
	assert(L[2].systems[1].isInDefaultPosition, "a cast bar locked to the player frame stays")
	assert(cvars.raidFramesDisplayClassColor == "1" and cvars.raidFramesDisplayPowerBars == "1"
		and cvars.raidFramesHealthText == nil, "raid frame options on (only those the client has)")
	-- Once: a second login neither copies again nor switches back.
	activeLayout, cvars.raidFramesDisplayClassColor = nil, "0"
	local offered = #popups
	ns:SetupEditMode()
	assert(#popups == offered, "no reload offered when nothing changed")
	-- The game hands offsets back rounded its own way: still no reload.
	for _, layout in ipairs(savedLayouts.layouts) do
		if layout.layoutName == ns.EDIT_LAYOUT then
			for _, sys in ipairs(layout.systems) do
				if sys.anchorInfo and sys.anchorInfo.point == "TOPLEFT" and sys.anchorInfo.relativePoint == "BOTTOMLEFT" then
					sys.anchorInfo.offsetX = sys.anchorInfo.offsetX + 0.6
					sys.anchorInfo.offsetY = sys.anchorInfo.offsetY - 1
				end
			end
		end
	end
	ns:SetupEditMode()
	assert(#popups == offered, "no reload offered for offsets the game rounded")
	-- Target aura size: unset, Edit Mode's own Frame Size is left alone; set,
	-- it goes in as Edit Mode's slider step and the frame is placed for that
	-- scale, kept to what fits on the wall.
	do
		local tf = savedLayouts.layouts[3].systems[5]
		local function frameSize()
			for _, e in ipairs(tf.settings or {}) do
				if e.setting == 16 then return e.value end
			end
		end
		local spot = ns.modules.target:AuraSpot()
		assert(frameSize() == nil and ns:TargetAuraSize(spot) == nil, "no target frame size until the option is set")
		local function placedAt(size)
			local scale = size / 100
			assert(frameSize() == (size - 100) / 5, "target frame size saved as a slider step: " .. tostring(frameSize()))
			-- Edit Mode keeps offsets in UIParent units (ApplySystemAnchor
			-- divides them by the frame's scale): only the icon's place inside
			-- the frame scales.
			assert(math.abs(tf.anchorInfo.offsetX + 5 * scale - spot.x0 * k) <= 2
				and math.abs(tf.anchorInfo.offsetY - 15 * scale - spot.y * k) <= 2,
				"target auras placed for their size " .. size)
		end
		SlashCmdList.REFORGEDUI("aurasize 123")
		assert(ns.db.consoleOpts.targetAuraSize == 125, "aura size in steps of 5")
		placedAt(125)
		assert(#popups == offered + 1 and popups[#popups].text:find("size"), "reload offered for the new size")
		ns:SetupEditMode()
		assert(#popups == offered + 1, "no reload offered when the size is in place")
		SlashCmdList.REFORGEDUI("aurasize 500")
		local want, fit = ns:TargetAuraSize(spot)
		assert(want == 200 and fit >= 100 and fit <= 200 and fit % 5 == 0, "aura size clamped")
		assert(fit == 100 or 122 * fit / 100 <= (spot.x1 - spot.x0) * k, "the aura rows fit on the wall")
		placedAt(fit)
		SlashCmdList.REFORGEDUI("aurasize 100")
		placedAt(100)
		-- Handed back by the game at a place we used before: still ours.
		local back = ns.db.consoleOpts.targetAuraLast[2]
		tf.anchorInfo.offsetX, tf.anchorInfo.offsetY = back.x, back.y
		ns:SetupEditMode()
		assert(not ns.db.consoleOpts.targetAuraOwn, "an earlier place of ours is not the player's")
		placedAt(100)
		-- Re-anchored by a click in Edit Mode (another point, a few units
		-- off) without being moved: still ours.
		local oldW, oldH, oldTS = TargetFrame._w, TargetFrame._h, TargetFrame._scale
		TargetFrame._w, TargetFrame._h, TargetFrame._scale = 200, 80, 1
		local here = tf.anchorInfo
		tf.anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
			offsetX = here.offsetX + 100 + 3, offsetY = here.offsetY - 40 - 2 }
		ns:SetupEditMode()
		assert(not ns.db.consoleOpts.targetAuraOwn, "a target frame re-anchored in place is still ours")
		placedAt(100)
		-- Moved in Edit Mode: the player's from then on (size still applies),
		-- until /rui auras reset.
		tf.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
			offsetX = 700, offsetY = 300 }
		offered = #popups
		ns:SetupEditMode()
		assert(ns.db.consoleOpts.targetAuraOwn and tf.anchorInfo.offsetX == 700 and #popups == offered,
			"a target frame moved in Edit Mode stays put")
		local said = #printed
		ns.modules.target:CheckAuraSpot()
		assert(#printed == said, "no login hint for a frame the player placed")
		SlashCmdList.REFORGEDUI("aurasize 125")
		assert(frameSize() == 5 and tf.anchorInfo.offsetX == 700, "the size still applies where the player put it")
		SlashCmdList.REFORGEDUI("aurasize 100")
		-- A target display switch takes a frame the player placed along: it
		-- was placed for the other display.
		local before = #printed
		ns.modules.target:SetMode("plate")
		local told = false
		for i = before + 1, #printed do
			told = told or printed[i]:find("goes with the target display", 1, true) ~= nil
		end
		assert(not ns.db.consoleOpts.targetAuraOwn and tf.anchorInfo.offsetX ~= 700 and told,
			"a mode switch moves a placed frame")
		spot = ns.modules.target:AuraSpot()
		placedAt(100)
		ns.modules.target:SetMode("swap")
		spot = ns.modules.target:AuraSpot()
		placedAt(100)
		tf.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
			offsetX = 700, offsetY = 300 }
		ns:SetupEditMode()
		assert(ns.db.consoleOpts.targetAuraOwn, "moved again")
		offered = #popups
		SlashCmdList.REFORGEDUI("auras reset")
		assert(not ns.db.consoleOpts.targetAuraOwn and #popups == offered + 1
			and popups[#popups].text:find("go back"), "/rui auras reset puts them back")
		placedAt(100)
		TargetFrame._w, TargetFrame._h, TargetFrame._scale = oldW, oldH, oldTS
		offered = #popups
	end
	-- Buffs still where we put them follow a new top bar scale; moved ones don't.
	local ourBuffs, mineBuffs = savedLayouts.layouts[3].systems[7], savedLayouts.layouts[1].systems[7]
	mineBuffs.anchorInfo.offsetX = -400
	local oldY = ourBuffs.anchorInfo.offsetY
	local oldSpot = ns.BuffSpot
	ns.BuffSpot = function() return { x = -24, y = oldY * 2 } end
	-- (Only after a shared setting changes: another character's or login's
	-- spot alone leaves them be.)
	ns:SetupEditMode()
	assert(ourBuffs.anchorInfo.offsetY == oldY and #popups == offered, "buffs stay for another login's spot")
	ns.db.consoleOpts.spotKey = "an older top bar scale"
	ns:SetupEditMode()
	assert(ourBuffs.anchorInfo.offsetY == oldY * 2 and mineBuffs.anchorInfo.offsetX == -400,
		"our buffs follow the top bar, moved buffs stay")
	assert(popups[#popups].text:find("buffs"), "reload offered after moving buffs")
	ns.BuffSpot = oldSpot
	ns.db.consoleOpts.spotKey = "an older top bar scale"
	ns:SetupEditMode()
	assert(ourBuffs.anchorInfo.offsetY == oldY, "and back")
	offered = #popups
	-- "Let Edit Mode place action bars 1-3": the bars are placed in our
	-- layout once over the grid rows, at a grid-like icon size in whichever
	-- form the layout stores it, and then left to the player.
	ns.db.consoleOpts.editModeBars, ns.db.consoleOpts.barsPlaced = true, false
	ns:SetupEditMode()
	local main, bar2
	for _, sys in ipairs(savedLayouts.layouts[3].systems) do
		if sys.system == 0 then
			if sys.systemIndex == 1 then main = sys elseif sys.systemIndex == 2 then bar2 = sys end
		end
	end
	local function size(sys) return sys.settings[1].value end
	assert(main and not main.isInDefaultPosition and main.anchorInfo.point == "BOTTOMLEFT"
		and main.anchorInfo.relativeTo == "UIParent" and bar2.anchorInfo.offsetY > main.anchorInfo.offsetY,
		"bars placed over the grid rows")
	assert(size(main) >= 0 and size(main) <= 15 and size(bar2) >= 50 and (size(bar2) - 50) / 10 == size(main),
		"icon size set in the layout's own form")
	local function setting(sys, id)
		for _, entry in ipairs(sys.settings) do
			if entry.setting == id then return entry.value end
		end
	end
	assert(setting(main, 4) == 6 and setting(bar2, 4) == 8 and setting(main, 6) == 1 and setting(bar2, 7) == 1
		and setting(main, 8) == 1, "padding 8, bar art and scrolling hidden, all slots shown")
	assert(ns.db.consoleOpts.barsPlaced and popups[#popups].text:find("action bars"), "placed once, reload offered")
	main.anchorInfo.offsetX = 7
	ns:SetupEditMode()
	assert(main.anchorInfo.offsetX == 7, "the player's own placement is kept")
	ns.db.consoleOpts.editModeBars = false
	-- Some players' games hand a layout back with the cast bar (or buffs, pet
	-- bar, leave button) in its default place again: moved once, then left,
	-- so a login doesn't save layouts and ask for a reload every time.
	local cast = savedLayouts.layouts[1].systems[3]
	assert(cast.system == 1 and not cast.isInDefaultPosition, "the cast bar was raised")
	cast.isInDefaultPosition = true
	savedLayouts.layouts[1].systems[9].isInDefaultPosition = true
	offered = #popups
	ns:SetupEditMode()
	assert(#popups == offered and cast.isInDefaultPosition, "a layout is only moved out of its defaults once")
	savedLayouts.layouts[#savedLayouts.layouts + 1] = { layoutName = "Fresh", systems = {
		{ system = 1, isInDefaultPosition = true } } }
	ns:SetupEditMode()
	assert(not savedLayouts.layouts[4].systems[1].isInDefaultPosition, "a new layout still gets its cast bar raised")
	table.remove(savedLayouts.layouts)
	assert(#savedLayouts.layouts == 3 and activeLayout == nil and cvars.raidFramesDisplayClassColor == "0",
		"the layout is set up once")

	-- The pet bar's layout is shared: a character without stance buttons (or
	-- one whose forms aren't known yet at login) finds the bar on the other
	-- row and leaves it there, with no reload asked, both ways round.
	local petAt = savedLayouts.layouts[1].systems[9].anchorInfo.offsetY
	local asked = #popups
	GetNumShapeshiftForms = function() return 0 end
	ns:SetupEditMode()
	GetNumShapeshiftForms = nil
	ns:SetupEditMode()
	assert(#popups == asked and savedLayouts.layouts[1].systems[9].anchorInfo.offsetY == petAt
		and ns.db.consoleOpts.petSpot.y == petAt, "a pet bar on either row stays put")
	-- Night elf themes have both rows 12 units higher than the others: a
	-- character on one of those leaves the bar where another race put it.
	local realSpots, realPetSpot = ns.PetBarSpots, ns.PetBarSpot
	ns.PetBarSpot = function(self, row)
		local spot = realPetSpot(self, row)
		return spot and { x = spot.x, y = spot.y + 12, size = spot.size, padding = spot.padding }
	end
	ns.PetBarSpots = function(self)
		local list = realSpots(self)
		for i, spot in ipairs(list) do
			list[i] = { x = spot.x, y = spot.y + 12 }
		end
		return list
	end
	ns:SetupEditMode()
	ns.PetBarSpots, ns.PetBarSpot = realSpots, realPetSpot
	assert(#popups == asked and savedLayouts.layouts[1].systems[9].anchorInfo.offsetY == petAt
		and ns.db.consoleOpts.petSpot.y == petAt, "a pet bar on another race's row stays put")

	-- The leave button's spot differs a little between characters and
	-- logins (theme, menu buttons, the button's scale), but the layout is
	-- shared: it stays where it is, with no reload asked, both ways round.
	-- Only a shared setting changing carries it along.
	local leave = savedLayouts.layouts[1].systems[10].anchorInfo
	local leaveAt, leaveSpotAt = leave.offsetY, ns.db.consoleOpts.leaveSpot
	assert(ns.db.consoleOpts.spotKey == ns:EditSpotKey(), "the shared settings it was placed for are kept")
	local realSpot = ns.LeaveButtonSpot
	ns.LeaveButtonSpot = function(self)
		local spot = realSpot(self)
		return { x = spot.x, y = spot.y + 12 }
	end
	ns:SetupEditMode()
	ns.LeaveButtonSpot = realSpot
	ns:SetupEditMode()
	assert(#popups == asked and leave.offsetY == leaveAt and ns.db.consoleOpts.leaveSpot == leaveSpotAt,
		"a leave button at another login's spot stays put")
	ns.db.consoleOpts.spotKey = "an older screen"
	ns.LeaveButtonSpot = function(self)
		local spot = realSpot(self)
		return { x = spot.x, y = spot.y + 12 }
	end
	ns:SetupEditMode()
	ns.LeaveButtonSpot = realSpot
	assert(savedLayouts.layouts[1].systems[10].anchorInfo.offsetY == leaveAt + 12
		and ns.db.consoleOpts.leaveSpot.y == leaveAt + 12 and #popups == asked + 1
		and popups[#popups].text:find("leave vehicle"), "a shared setting changing carries it along")
	-- Back where it was (as a new console size would), for the tests below.
	ns.db.consoleOpts.spotKey = "an older screen"
	ns:SetupEditMode()
	assert(savedLayouts.layouts[1].systems[10].anchorInfo.offsetY == leaveAt, "and back")
	asked = #popups

	-- Until Blizzard's Edit Mode has its layouts, the game's list may be
	-- incomplete: nothing is made or saved before then. Our layout goes
	-- after the account layouts, before the character's own, and the
	-- character's active layout stays the active one.
	local before, keptSwitched = savedLayouts, ns.db.consoleOpts.editLayout
	Enum.EditModeLayoutType.Character = 2
	savedLayouts = { activeLayout = 4, layouts = { { layoutName = "Shared", layoutType = 1, systems = {} },
		{ layoutName = "Mine here", layoutType = 2, systems = {} } } }
	local mineHere = savedLayouts.layouts[2]
	ns.db.consoleOpts.editLayout = { [(UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")] = true }
	local ready, wasInit = false, EditModeManagerFrame.IsInitialized
	EditModeManagerFrame.IsInitialized = function() return ready end
	ns:SetupEditMode()
	ns:SetupEditMode()
	assert(#savedLayouts.layouts == 2, "waits for Blizzard's layouts")
	ready = true
	fire("EDIT_MODE_LAYOUTS_UPDATED")
	fire("EDIT_MODE_LAYOUTS_UPDATED")
	assert(#savedLayouts.layouts == 2, "and for its own handler to finish")
	flushTimers()
	local made = savedLayouts.layouts
	assert(#made == 3 and made[2].layoutName == ns.EDIT_LAYOUT and made[3] == mineHere,
		"made once, between the account and the character layouts")
	assert(savedLayouts.activeLayout == 5, "the character's active layout stays active")
	-- Two with our name (from an older version): the first is used, no third.
	table.insert(made, 3, { layoutName = ns.EDIT_LAYOUT, layoutType = 1, systems = {} })
	ns:SetupEditMode()
	assert(#savedLayouts.layouts == 4, "no layout made while one has our name")
	assert(made[2].layoutName == ns.EDIT_LAYOUT and made[3].layoutName == ns.EDIT_LAYOUT .. " 2",
		"the extra one is renamed")
	assert(popups[#popups].text:find("renamed 1 extra"), "reload offered after the rename")
	EditModeManagerFrame.IsInitialized = wasInit
	savedLayouts, ns.db.consoleOpts.editLayout = before, keptSwitched
	Enum.EditModeLayoutType.Character = nil

	-- Every frame placed in all layouts (ns.EditPlacements) has a name and
	-- a saved spot of its own: two sharing one would each take the other's
	-- last place for theirs.
	local keys, spotKeys = {}, {}
	for _, p in ipairs(ns.EditPlacements) do
		assert(type(p.key) == "string" and not keys[p.key], "placement names differ: " .. tostring(p.key))
		keys[p.key] = true
		assert(type(p.spot) == "function" and type(p.place) == "function" and type(p.message) == "function",
			p.key .. " has its spot, place and message")
		assert(type(p.message(1, setmetatable({}, { __index = function() return 0 end }))) == "string", p.key .. " says what it did")
		if p.saved then
			assert(not spotKeys[p.saved], p.key .. " shares its saved spot " .. p.saved)
			spotKeys[p.saved] = true
		end
	end
	-- And placing settles: at a relog the game hands the layouts back as
	-- new tables, offsets rounded its own way (a unit either way). Nothing
	-- is saved then and no reload offered, whichever target display is on.
	local function handedBack(t, jitter)
		local out = {}
		for k, v in pairs(t) do
			if type(v) == "table" then
				out[k] = handedBack(v, jitter)
			elseif (k == "offsetX" or k == "offsetY") and type(v) == "number" then
				out[k] = v + jitter
			else
				out[k] = v
			end
		end
		return out
	end
	local settled = savedLayouts
	local saves, save = 0, C_EditMode.SaveLayouts
	C_EditMode.SaveLayouts = function(info) saves = saves + 1; save(info) end
	ns:SetupEditMode()
	saves, offered = 0, #popups
	for _, jitter in ipairs({ 0, 1, -1 }) do
		savedLayouts = handedBack(settled, jitter)
		ns:SetupEditMode()
		assert(saves == 0 and #popups == offered,
			("a relog saves no Edit Mode layout and offers no reload (offsets %+d)"):format(jitter))
	end
	-- (The check itself: a frame back in its default place in a layout not
	-- placed before is placed, and saved.)
	savedLayouts = handedBack(settled, 0)
	savedLayouts.layouts[1].layoutName = "Another"
	savedLayouts.layouts[1].systems[#savedLayouts.layouts[1].systems + 1] = { system = 1, isInDefaultPosition = true }
	ns.db.consoleOpts.editPlaced["Another"] = nil
	ns:SetupEditMode()
	assert(saves == 1 and #popups == offered + 1 and popups[#popups].text:find("cast bar"), "a new layout's cast bar is raised")
	ns.db.consoleOpts.editPlaced["Another"] = nil
	C_EditMode.SaveLayouts = save
	savedLayouts = settled
end
-- Frames of ours the player moves all drag through Core.lua (ns:StartDrag,
-- ns:StopDrag, ns:MakeDraggable), so each drag ends the same way; the
-- options window is the one exception.
do
	for _, file in ipairs(files) do
		if file ~= "Core.lua" and file ~= "Config.lua" and not file:find("^Libs/") then
			local f = assert(io.open(ADDON .. file))
			local n = 0
			for line in f:lines() do
				n = n + 1
				local code = line:gsub("%-%-.*", "")
				assert(not code:find("StartMoving", 1, true) and not code:find("StopMovingOrSizing", 1, true),
					("%s:%d moves a frame itself: use ns:MakeDraggable, ns:StartDrag and ns:StopDrag"):format(file, n))
				assert(not (code:find("EditModeManagerFrame", 1, true) and code:find("HookScript", 1, true)),
					("%s:%d hooks Edit Mode itself: use ns:OnEditMode"):format(file, n))
			end
			f:close()
		end
	end
	local may, drops = false, 0
	local f = CreateFrame("Frame", nil, UIParent)
	local userPlaced
	f.SetUserPlaced = function(_, on) userPlaced = on end
	ns:MakeDraggable(f, function(frame) assert(frame == f and not frame.dragging); drops = drops + 1 end,
		function() return may end)
	f._scripts.OnDragStart(f)
	assert(not f.dragging and not f._moving, "no drag while it may not move")
	f._scripts.OnDragStop(f)
	assert(drops == 0 and not ns:StopDrag(f), "nothing to save without a drag")
	may = true
	f._scripts.OnDragStart(f)
	assert(f.dragging and f._moving, "dragged while it may move")
	f._scripts.OnDragStop(f)
	assert(not f.dragging and not f._moving and drops == 1 and userPlaced == false,
		"let go: saved once, its place left to us")
	-- Cut short (hidden, Edit Mode closed): let go and saved all the same.
	f._scripts.OnDragStart(f)
	assert(ns:StopDrag(f) and not f._moving and drops == 2 and not ns:StopDrag(f), "a drag cut short is let go and saved")
	-- Edit Mode opening and closing reaches every listener, also after one fails.
	local heard = {}
	local handler = geterrorhandler
	local failed = 0
	geterrorhandler = function() return function() failed = failed + 1 end end
	local failing = true
	ns:OnEditMode(function() if failing then error("a listener that fails") end end)
	ns:OnEditMode(function(open) heard[#heard + 1] = open end)
	EditModeManagerFrame._hooks.OnShow()
	EditModeManagerFrame._hooks.OnHide()
	geterrorhandler, failing = handler, false
	assert(#heard == 2 and heard[1] == true and heard[2] == false and failed == 2, "Edit Mode tells every listener")
end
assert(ns.themeKey == "orc", "orc race should pick the orc theme")
for key, mod in pairs(ns.modules) do
	assert(mod.enabled, key .. " failed to enable")
end

-- Nothing of Blizzard's may be anchored to our frames (Edit Mode saves anchors).
local function checkAnchors()
	for _, f in ipairs(allFrames) do
		local name = rawget(f, "_name")
		if name and not name:find("^ReforgedUI") and issecurevariable(name) then
			for _, p in ipairs(f._points) do
				local rel = p[2]
				local relName = type(rel) == "table" and rawget(rel, "_name")
				assert(not (relName and relName:find("^ReforgedUI")), name .. " is anchored to " .. tostring(relName))
			end
			local parent = rawget(f, "_parent")
			assert(not (parent and (rawget(parent, "_name") or ""):find("^ReforgedUI")), name .. " was reparented")
		end
	end
end
checkAnchors()

-- Replaced Blizzard frames are made invisible, never reparented or moved;
-- the rest are left alone.
assert(PlayerFrame:GetParent() == UIParent and PlayerFrame._alpha == 0 and PlayerFrame._mouse == false,
	"the player frame should be invisible and click-through")
local _, _, _, _, py = PlayerFrame:GetPoint(1)
assert(py == -4, "the player frame must not be moved")
-- Our target display replaces Blizzard's target frame and its target of
-- target: invisible and click-through, never moved or reparented, all but
-- the target frame's own aura icons (only Blizzard's code may read them in
-- combat).
for _, f in ipairs({ TargetFrameToT, TargetFrameSpellBar, targetHealthArt }) do
	assert(f._alpha == 0 and #f._points == 0, tostring(f._name) .. " should be concealed, not moved")
end
-- Its unnamed inner frames hold the aura icons on modern clients: what is
-- in them is hidden, not they themselves.
assert(TargetFrame.TargetFrameContent._alpha ~= 0 and TargetFrame.TargetFrameContent._mouse == false,
	"the target frame's inner frames stay visible, click-through")
assert(TargetFrame._alpha ~= 0 and TargetFrame._mouse == false and #TargetFrame._points == 0,
	"the target frame stays visible for its auras, click-through and not moved")
assert(targetFrameArt._alpha == 0 and TargetFrameBuff1._alpha ~= 0, "only the target frame's aura icons show")
-- An aura button made later inside an inner frame shows, and is found.
local lateAura = new("button", nil, TargetFrame.TargetFrameContent)
lateAura.Icon, lateAura.Cooldown = {}, {}
-- The reaction-tinted strip behind the name stays hidden when Blizzard
-- shows it again, and parts made later are hidden on the next target.
targetRepColor:Show()
-- The target's name too, even when its alpha comes back some other way.
targetName._alpha = 1
targetName:SetShown(true)
local lateArt = new("texture", nil, TargetFrame.TargetFrameContent)
fire("PLAYER_TARGET_CHANGED")
assert(not targetRepColor:IsShown() and targetRepColor._alpha == 0, "the name strip stays hidden")
assert(not targetName:IsShown(), "Blizzard's target name stays hidden")
assert(lateArt._alpha == 0 and lateAura._alpha ~= 0, "later target frame art hides, later auras show")
do
	local lines = ns.modules.target:DescribeAuras()
	local all = table.concat(lines, "\n")
	assert(all:find("\nTargetFrame: ") and all:find("aura icons shown: 2") and all:find("TargetFrameBuff1, ")
		and all:find("TargetFrameSpellBar %(hidden by us%)") and all:find("%(parts hidden%)")
		and all:find("still drawn %(0%)"), "/rui auras")
	SlashCmdList.REFORGEDUI("auras")
end
assert(TargetFrame:GetParent() == UIParent and TargetFrameToT:GetParent() == TargetFrame, "target frames keep their parents")
-- "Target buffs first": off, the game's order stays; on, every target
-- counts as friendly to the aura container after each of Blizzard's updates.
TargetFrame:ConfigureAuraContainer()
assert(targetAuraContainer.friendly == false, "the game's aura order by default")
SlashCmdList.REFORGEDUI("buffsfirst on")
assert(ReforgedUIDB.consoleOpts.targetBuffsFirst == true and targetAuraContainer.friendly == true, "buffs first at once")
TargetFrame:ConfigureAuraContainer()
assert(targetAuraContainer.friendly == true, "buffs first after Blizzard's aura update")
assert(table.concat(ns.modules.target:DescribeAuras(), "\n"):find("aura order: buffs first"), "/rui auras shows the order")
SlashCmdList.REFORGEDUI("buffsfirst off")
TargetFrame:ConfigureAuraContainer()
assert(ReforgedUIDB.consoleOpts.targetBuffsFirst == false and targetAuraContainer.friendly == false,
	"the game's order again when off")
assert(MinimapCluster:GetParent() == UIParent and MinimapCluster._alpha == nil and #MinimapCluster._points == 0,
	"the minimap cluster must be left alone")
assert(Minimap:GetParent() == UIParent, "the minimap keeps its parent")
assert(#StanceBar._points == 0 and #ObjectiveTrackerFrame._points == 0, "Edit Mode frames must stay put")
assert(MainActionBar.EndCaps._alpha == 0 and MainActionBar._alpha == nil, "main bar art should hide, not its buttons")
assert(MainActionBar._mouse == false, "empty bar frames should be click-through")
assert(MultiBar7._mouse == nil and #MultiBar7Button1._points == 0 and not MultiBar7Button1.reforgedFrame,
	"Action Bar 8 is the player's: untouched")

local L = ns.layout
local unit = function(f) return f:GetEffectiveScale() / ns.root:GetEffectiveScale() end
local function at(f, x, y, what)
	local p = f._points[1]
	assert(p and p[2] == UIParent, what .. " not anchored to UIParent")
	assert(math.abs(p[4] * unit(f) - x) < 0.01 and math.abs(p[5] * unit(f) - y) < 0.01, what .. " in the wrong place")
end
at(Minimap, L.minimap.x, L.minimap.y, "minimap")
assert(QueueStatusButton._points[1][1] == "BOTTOMLEFT", "the queue eye sits in the corner")
at(QueueStatusButton, L.queueEye.x, L.queueEye.y, "queue eye")
assert(L.queueEye.x < L.minimap.x and L.queueEye.y < L.minimap.y, "the eye starts on the frame, left of and below the map")
assert(QueueStatusButton._w * QueueStatusButton:GetEffectiveScale() / ns.root:GetEffectiveScale()
	- L.queueEye.w < 0.01, "the eye is fitted to its corner")
assert(strayButton._points[1][2] == UIParent and strayButton:GetParent() == Minimap,
	"stray minimap buttons should line up along the map")
assert(MinimapCluster.Tracking._points[1][1] == "CENTER", "tracking button should sit in its slot")
-- Blizzard sizes the cluster around its children; with the tracking button on
-- the console that reached the screen's bottom (and Edit Mode then scaled the
-- right action bars below zero). It keeps its own size.
MinimapCluster:SetSize(256, 1200)
MinimapCluster:SetHeight(900)
assert(MinimapCluster._w == ns.modules.minimap.clusterSize.w and MinimapCluster._h == ns.modules.minimap.clusterSize.h
	and MinimapCluster._h <= 400, "the minimap cluster keeps its size")
do
	local mm = ns.modules.minimap
	assert(addonButton:GetParent() == mm.drawer and addonButton._points[1][2] == UIParent,
		"addon buttons go in the compartment's drawer")
	assert(addonButton:GetFrameLevel() > mm.drawer:GetFrameLevel() and addonButton._fixedLevel,
		"addon buttons draw above the drawer, even when pinned")
	local strata = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4 }
	assert(strata[mm.drawer.bg:GetFrameStrata()] < strata[addonButton:GetFrameStrata()],
		"the drawer's background sits a strata below its buttons")
	assert(mm.toggle:IsShown() and not mm.drawer:IsShown(), "the compartment starts closed, even if it was left open")
	local toggleTop = mm.toggle._points[1][5] * unit(mm.toggle) + L.addonCompartment.h
	assert(mm.drawer._points[1][5] * unit(mm.drawer) > toggleTop and addonButton._points[1][5] * unit(addonButton) > toggleTop,
		"the flyout opens upwards from its button")
	assert(L.addonCompartment.y >= L.minimap.y + L.minimap.h, "the compartment's button sits above the map")
	mm.toggle:GetScript("OnClick")(mm.toggle)
	assert(mm.drawer:IsShown(), "clicking opens the drawer")
	mm.toggle:GetScript("OnClick")(mm.toggle)
	assert(not mm.drawer:IsShown(), "and closes it")
	for _, b in ipairs(mm.buttons) do
		assert(b ~= addonButton, "addon buttons leave the row")
	end
end
do
	-- The calendar button leads the row on the map's top edge, with today's
	-- date and a pulsing letter for the waiting invitation.
	local mm, cal = ns.modules.minimap, ns.modules.calendar
	local b = mm.calendar
	assert(b and b:GetName() == "ReforgedUICalendarButton" and b._shown ~= false, "the calendar button is made")
	assert(GameTimeFrame._alpha == 0, "Blizzard's calendar button stays hidden")
	local row = L.minimapButtons
	assert(b._points[1][1] == "TOPLEFT" and math.abs(b._points[1][4] * unit(b) - row.x) < 0.01,
		"the calendar button comes first in the row")
	assert(math.abs(b._w * unit(b) - math.min(row.size, (row.maxW - #mm.buttons * 2) / (#mm.buttons + 1))) < 0.01,
		"and is sized like the row's buttons")
	assert(b.day._text == 10, "it shows the day of the month")
	assert(b.invite._shown and b.glow._shown and b:GetScript("OnUpdate"), "a waiting invitation pulses")
	assert(calendarRequested, "the calendar's events are asked for")
	local feed = LibStub("LibDataBroker-1.1"):GetDataObjectByName(cal.FEED)
	assert(feed and feed.text:find("1 invitation", 1, true) and feed.text:find("Hallow's End", 1, true),
		"the feed shows the invitation and the holiday on now: " .. tostring(feed and feed.text))
	local lines = {}
	local tip = {
		AddLine = function(_, t) lines[#lines + 1] = t end,
		AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
	}
	feed.OnTooltipShow(tip)
	local text = table.concat(lines, "\n")
	assert(text:find("Now\nHallow's End=until Mon", 1, true), "the holiday is on until Monday: " .. text)
	assert(text:find("Coming up\nRaid night=Today 19:00", 1, true), "the raid is coming up today")
	assert(not text:find("Molten Core", 1, true) and not text:find("Declined", 1, true) and not text:find("Too far", 1, true),
		"no lockouts, declined events or events past the week")
	assert(#cal:Events() == 2, "the holiday comes once")
	-- Clicking opens the calendar and stops the pulse; the letter stays
	-- while the invitation waits.
	b._scripts.OnClick(b)
	assert(calendarToggles == 1 and not b.glow._shown and b.invite._shown and not b:GetScript("OnUpdate"),
		"a click opens the calendar and stops the pulse")
	feed.OnClick()
	assert(calendarToggles == 2, "so does a click on the feed")
	calPending = 0
	fire("CALENDAR_UPDATE_PENDING_INVITES")
	flushTimers()
	assert(not b.invite._shown and not feed.text:find("invitation", 1, true), "answered: no letter")
	-- Later in the evening: the raid is on, the holiday too.
	calNow = { year = 2026, month = 11, monthDay = 10, weekday = 3, hour = 19, minute = 20 }
	assert(cal:FeedText() == "Raid night +1", "the event ending first leads: " .. cal:FeedText())
	-- After the holiday: the next thing, by its day.
	calNow = { year = 2026, month = 11, monthDay = 17, weekday = 3, hour = 12, minute = 0 }
	assert(cal:FeedText() == "Too far Fri 20:00", "the next event and when: " .. cal:FeedText())
	calNow = { year = 2026, month = 11, monthDay = 20, weekday = 6, hour = 19, minute = 30 }
	assert(cal:FeedText() == "Too far in 30 min", "soon: " .. cal:FeedText())
	calNow = { year = 2026, month = 11, monthDay = 25, weekday = 4, hour = 12, minute = 0 }
	assert(cal:FeedText() == "No events", "nothing left")
	-- Day numbers run across months and years.
	local y, m, d = cal.CivilFromDays(cal.DaysFromCivil(2026, 12, 31) + 1)
	assert(y == 2027 and m == 1 and d == 1, "a day after New Year's Eve")
	y, m, d = cal.CivilFromDays(cal.DaysFromCivil(2028, 2, 28) + 1)
	assert(y == 2028 and m == 2 and d == 29, "leap years")
	calNow = { year = 2026, month = 11, monthDay = 10, weekday = 3, hour = 14, minute = 30 }
end
do
	-- The reputation feed: the watched faction's progress, details in the
	-- tooltip.
	local rep = ns.modules.reputation
	local feed = LibStub("LibDataBroker-1.1"):GetDataObjectByName(rep.FEED)
	-- Progress by default; a right-click steps through the name, the
	-- standing, what's left to the next standing and back, and is saved.
	assert(feed and feed.text == "2300 / 6000", "the feed: " .. tostring(feed and feed.text))
	local views = {}
	for i = 1, 4 do
		feed.OnClick(nil, "RightButton")
		views[i] = feed.text
	end
	assert(views[1] == "3700 to Honored", "next: " .. views[1])
	assert(views[2]:find("Nightclaw Druids|r", 1, true), "name: " .. views[2])
	assert(views[3]:find("Friendly|r", 1, true), "standing: " .. views[3])
	assert(views[4] == "2300 / 6000" and ns.db.consoleOpts.repFeed == "progress", "and back to progress")
	local function tooltip()
		local lines = {}
		feed.OnTooltipShow({
			AddLine = function(_, t) lines[#lines + 1] = t end,
			AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
		})
		return table.concat(lines, "\n")
	end
	local text = tooltip()
	assert(text:find("Standing=Friendly", 1, true) and text:find("Progress=2300 / 6000 (38.3 %)", 1, true)
		and text:find("To next standing=3700", 1, true), "the tooltip: " .. text)
	assert(not text:find("This session", 1, true), "nothing gained yet")
	-- The strip under the experience bar: between the plate and the stat
	-- icons, filled to the same 38 %.
	local hero, RL = ns.modules.hero, ns.layout
	assert(RL.rep.y + RL.rep.h <= RL.xp.middle.y and RL.rep.y >= RL.statIcons[1].y + RL.statIcons[1].h,
		"the rep strip sits between the experience bar and the stat icons")
	assert(hero.rep.fill:IsShown() and math.abs(hero.rep.fill._w - RL.rep.w * 2300 / 6000) < 0.01,
		"the strip at 38%")
	hero.rep.hover:GetScript("OnEnter")(hero.rep.hover)
	assert(hero.xp.level._text == "Nightclaw Druids 2300 / 6000", "hovering the strip: " .. tostring(hero.xp.level._text))
	assert(ns.modules.reputation:InfoText():find("Until next standing:|r 3700", 1, true), "the strip's info box")
	hero.rep.hover:GetScript("OnLeave")(hero.rep.hover)
	assert(not hero.xp.level._text:find("Nightclaw", 1, true), "and back to the level line")
	-- The level line in the middle of the plate's window (below the
	-- plate's own middle: the art's rim is lower at the top).
	local X = RL.xp
	assert(X.levelY < X.left.y + X.left.h / 2 and X.levelY > X.left.y + X.left.h * 0.4, "level line centred")
	-- It can be turned off: the bar is as tall as ever and the strip gone.
	local flatH = X.left.h
	SlashCmdList.REFORGEDUI("repbar off")
	assert(ns.db.consoleOpts.repBar == false and not ns.layout.rep, "the strip is off")
	assert(not hero.rep.fill:IsShown() and not hero.rep.hover:IsShown(), "and hidden")
	assert(ns.layout.xp.left.h > flatH * 1.2, "the experience bar gets its height back")
	assert(ns.layout.xp.nameY == X.nameY, "the name stays put")
	SlashCmdList.REFORGEDUI("repbar on")
	assert(ns.layout.rep and hero.rep.fill:IsShown(), "and on again")
	watchedFaction.currentStanding = 5550
	fire("UPDATE_FACTION")
	flushTimers()
	assert(tooltip():find("This session=+250", 1, true), "the session's gain")
	-- Exalted: the standing's name; with a paragon level, its progress.
	watchedFaction = { factionID = 2601, name = "Argent Dawn", description = "", reaction = 8,
		currentReactionThreshold = 42000, nextReactionThreshold = 42000, currentStanding = 42000 }
	fire("UPDATE_FACTION")
	flushTimers()
	assert(feed.text:find("Exalted|r", 1, true), "exalted: " .. feed.text)
	assert(tooltip():find("Highest standing reached", 1, true), "nothing left to gain")
	paragonFactions[2601] = { 12500, 10000, true }
	fire("UPDATE_FACTION")
	flushTimers()
	assert(feed.text == "2500 / 10000", "paragon: " .. feed.text)
	assert(rep:FeedText(nil, "next") == "7500 to reward", "paragon, next: " .. rep:FeedText(nil, "next"))
	assert(tooltip():find("A paragon reward is waiting", 1, true), "the reward")
	-- No watched faction.
	watchedFaction = nil
	fire("UPDATE_FACTION")
	flushTimers()
	assert(feed.text == "No faction" and tooltip():find("Show as Experience Bar", 1, true), "none watched")
	assert(not hero.rep.fill:IsShown() and not hero.rep.hover:IsShown(), "no faction, no strip")
	local opened
	local toggle = ToggleCharacter
	ToggleCharacter = function(tab) opened = tab end
	feed.OnClick()
	ToggleCharacter = toggle
	assert(opened == "ReputationFrame", "a click opens the reputation panel")
end
do
	-- The loot feed: "Solo" out of a group; in one, the method with the
	-- threshold in its colour, details in the tooltip.
	local lootMod = ns.modules.loot
	local feed = LibStub("LibDataBroker-1.1"):GetDataObjectByName(lootMod.FEED)
	assert(feed and feed.text:find("Solo", 1, true), "the loot feed solo: " .. tostring(feed and feed.text))
	local function tooltip()
		local lines = {}
		feed.OnTooltipShow({
			AddLine = function(_, t) lines[#lines + 1] = t end,
			AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
		})
		return table.concat(lines, "\n")
	end
	assert(tooltip():find("not in a group", 1, true), "solo tooltip")
	local printedBefore = #printed
	feed.OnClick(nil, "RightButton")
	assert(#printed == printedBefore + 1 and printed[#printed]:find("not in a group", 1, true), "no menu solo")
	loot.inGroup = true
	fire("GROUP_ROSTER_UPDATE")
	flushTimers()
	assert(feed.text == "Group Loot |cff1eff00Uncommon|r", "group loot: " .. feed.text)
	local text = tooltip()
	assert(text:find("Method=Group Loot", 1, true) and text:find("Loot threshold=Uncommon", 1, true)
		and text:find("Only the group leader", 1, true), "group loot tooltip: " .. text)
	feed.OnClick(nil, "RightButton")
	assert(printed[#printed]:find("only the group leader", 1, true), "no menu for others")
	-- Free for All has no threshold to show; Master Looter names who.
	loot.method = 0
	assert(lootMod:FeedText() == "Free for All", "ffa: " .. lootMod:FeedText())
	loot.method, loot.partyID = 2, 0
	assert(lootMod:FeedText():find("^Master Looter "), "master: " .. lootMod:FeedText())
	assert(tooltip():find("Master looter=Thrall", 1, true), "the master looter: " .. tooltip())
	-- The leader's menu: the methods the client offers (no personal here),
	-- the group under Master Looter, and the thresholds.
	loot.leader = true
	local function newDesc(text)
		local d = { text = text, children = {} }
		function d:CreateTitle(t) local c = newDesc(t); c.title = true; self.children[#self.children + 1] = c; return c end
		function d:CreateRadio(t, sel, fn)
			local c = newDesc(t); c.selected, c.fn = sel, fn; self.children[#self.children + 1] = c; return c
		end
		function d:SetTooltip(fn) self.tip = fn end
		return d
	end
	local menuRoot
	local oldMenu, oldExists = MenuUtil, UnitExists
	MenuUtil = { CreateContextMenu = function(_, gen) menuRoot = newDesc(); gen(nil, menuRoot) end }
	UnitExists = function(u) return u == "player" or u == "party1" end
	feed.OnClick(nil, "RightButton")
	MenuUtil = oldMenu
	assert(menuRoot, "the leader gets a menu")
	local labels, byText = {}, {}
	for _, c in ipairs(menuRoot.children) do
		labels[#labels + 1] = c.text
		byText[c.text] = c
	end
	assert(table.concat(labels, ",") == "Loot Method,Free for All,Round Robin,Master Looter,Group Loot,"
		.. "Need before Greed,Loot Threshold,|cff1eff00Uncommon|r,|cff0070ddRare|r,|cffa335eeEpic|r",
		"the menu: " .. table.concat(labels, ","))
	local master = byText["Master Looter"]
	assert(master.selected() and #master.children == 2, "master looter is on, with two members")
	master.children[2].fn()
	assert(loot.sets[#loot.sets] == "method 2 Thrall", "set the master looter: " .. loot.sets[#loot.sets])
	byText["Need before Greed"].fn()
	assert(loot.sets[#loot.sets] == "method 4 nil", "set need before greed")
	byText["|cff0070ddRare|r"].fn()
	assert(loot.threshold == 3 and byText["|cff0070ddRare|r"].selected(), "set the threshold to rare")
	UnitExists = oldExists
	loot.inGroup, loot.leader, loot.method = false, false, 3
	fire("GROUP_ROSTER_UPDATE")
	flushTimers()
end
local _, _, _, _, iy = IssueReporterButton:GetPoint(1)
assert(iy > 100, "the issue reporter should sit above the console")
-- Blizzard's micro buttons live in the top bar, either side of the clock:
-- still Blizzard's (same parent, visible), anchored to UIParent, scaled to
-- the bar. The quest log, social and map buttons stay hidden.
local function microAt(b, r, what, root)
	local p = b._points[1]
	assert(p and #b._points == 1 and p[2] == UIParent and p[1] == "BOTTOMLEFT", what .. " should be anchored to UIParent")
	local k = b:GetEffectiveScale() / (root or ns.topRoot):GetEffectiveScale()
	assert(math.abs(p[4] * k - r.x) < 0.01 and math.abs(p[5] * k - r.y) < 0.01, what .. " in the wrong place")
	assert(math.abs(b._h * k - r.h) < 0.01 and math.abs(b._w * k - r.w) < 0.01, what .. " has the wrong size")
	assert(b:GetParent() == MicroMenu, what .. " keeps its parent")
	assert(b:GetAlpha() == 1 and b._shown and b._mouse ~= false, what .. " should be visible and clickable")
end
local function checkMicro(expected)
	local T, tb = ns.topLayout, ns.modules.topbar
	assert(#tb.microShown == #expected and #T.micro == #expected, "every shown micro button gets a place")
	local nL = math.ceil(#expected / 2)
	for i, b in ipairs(expected) do
		assert(tb.microShown[i] == b, "micro buttons in Blizzard's order")
		local r = T.micro[i]
		microAt(b, r, b:GetName())
		-- The clock frame's art: its texture is transparent beyond that
		-- where it crosses the bar.
		assert(not ns.Layout.Overlaps(r, T.clockArt), b:GetName() .. " overlaps the clock")
		if i <= nL then
			assert(r.x + r.w <= T.clockArt.x, b:GetName() .. " belongs left of the clock")
		else
			assert(r.x >= T.clockArt.x + T.clockArt.w, b:GetName() .. " belongs right of the clock")
		end
		for _, slot in ipairs(T.topSlots) do
			assert(not ns.Layout.Overlaps(slot, r), "a feed slot overlaps " .. b:GetName())
		end
	end
	-- Close to the clock, the two halves mirrored about it (the narrower
	-- half centred in the wider one's width).
	local n, cx = #T.micro, T.clock.cx
	assert(math.min(T.clockArt.x - (T.micro[nL].x + T.micro[nL].w), T.micro[nL + 1].x - (T.clockArt.x + T.clockArt.w)) < 5,
		"micro buttons should hug the clock")
	local midL = (T.micro[1].x + T.micro[nL].x + T.micro[nL].w) / 2
	local midR = (T.micro[nL + 1].x + T.micro[n].x + T.micro[n].w) / 2
	assert(math.abs((cx - midL) - (midR - cx)) < 1, "micro button halves not mirrored about the clock")
	assert(math.abs((cx - T.microSpan.x) - (T.microSpan.x + T.microSpan.w - cx)) < 1, "micro span not centred on the clock")
end
-- The Adventure Guide and shop are left out; Legacy and the game menu
-- button close the row.
local MOVED = { CharacterMicroButton, SpellbookMicroButton, TalentMicroButton, GuildMicroButton,
	LFDMicroButton, CollectionsMicroButton, unnamedMicro, LegacyMicroButton, MainMenuMicroButton }
checkMicro(MOVED)
assert(#StoreMicroButton._points == 0 and StoreMicroButton._alpha == 0, "the shop button is hidden, not placed")
assert(#EJMicroButton._points == 0 and EJMicroButton._alpha == 0, "the Adventure Guide button is hidden, not placed")
for _, b in ipairs({ WorldMapMicroButton, QuestLogMicroButton, SocialsMicroButton }) do
	assert(b._alpha == 0 and #b._points == 0, b:GetName() .. " stays hidden, not placed")
end
assert(MicroMenuContainer._alpha == nil and MicroMenu._alpha == nil and #MicroMenuContainer._points == 0,
	"the micro menu stays where Edit Mode puts it, alpha untouched")
assert(MicroMenuContainer._mouse == false and MicroMenu._mouse == false, "the empty micro menu lets clicks through")
-- Blizzard laying the menu out again, or resizing it, changes nothing.
CharacterMicroButton:ClearAllPoints()
CharacterMicroButton:SetPoint("TOPLEFT", MicroMenu, "TOPLEFT", 0, 0)
MicroMenu:SetScale(0.6)
checkMicro(MOVED)
-- A micro button Blizzard hides: its room goes.
unnamedMicro._shown = false
unnamedMicro._hooks.OnShow(unnamedMicro)
flushTimers()
checkMicro({ CharacterMicroButton, SpellbookMicroButton, TalentMicroButton, GuildMicroButton,
	LFDMicroButton, CollectionsMicroButton, LegacyMicroButton, MainMenuMicroButton })
unnamedMicro._shown = true
unnamedMicro._hooks.OnShow(unnamedMicro)
flushTimers()
checkMicro(MOVED)
-- The shop button shown by Blizzard stays out of the bar.
StoreMicroButton._shown = true
flushTimers()
checkMicro(MOVED)
do
	-- With the top bar hidden (clock, slots and all), the micro buttons
	-- stand on the minimap block's wall, between the left end cap and the
	-- addon compartment, clear of the map and the target of target; buffs
	-- still where we put them move up to the screen's top edge.
	local buffY = savedLayouts.layouts[3].systems[7].anchorInfo.offsetY
	ns:SetTopBarShown(false)
	flushTimers()
	assert(stateDrivers[ns.topRoot] == "hide", "the top bar is hidden")
	local L, tb = ns.layout, ns.modules.topbar
	assert(#L.micro == #MOVED, "every micro button gets a place on the console")
	local cap = L.endcaps.left
	for i, b in ipairs(MOVED) do
		local r = L.micro[i]
		microAt(b, r, b:GetName() .. " (no top bar)", ns.root)
		assert(r.x >= cap.x + cap.w and r.x + r.w <= L.addonCompartment.x, b:GetName() .. " beside the compartment")
		assert(r.y >= L.minimap.y + L.minimap.h, b:GetName() .. " above the map")
		for _, other in ipairs({ L.addonCompartment, L.tot.frame, L.petIcon and L.petIcon.frame or L.tot.frame }) do
			assert(not ns.Layout.Overlaps(r, other), b:GetName() .. " collides")
		end
		for j = i + 1, #MOVED do
			assert(not ns.Layout.Overlaps(r, L.micro[j]), "micro buttons overlap")
		end
	end
	for _, slot in ipairs(tb.slots) do
		assert(not slot._shown and not (slot.secure and slot.secure._shown), "no slots without the top bar")
	end
	-- The time capsule stays: on the console, over the micro buttons.
	local cap, ct = tb.capsule, L.clockTime
	assert(ct and cap._parent == ns.root, "the time capsule moves to the console")
	local _, rel, _, cx, cy = cap:GetPoint(1)
	assert(rel == ns.root and cx == ct.x and cy == ct.y, "the time capsule at its console spot")
	assert(ct.y >= L.microSpan.y + L.microSpan.h, "the time capsule above the micro buttons")
	for _, other in ipairs({ L.addonCompartment, L.tot.frame, L.petIcon and L.petIcon.frame or L.tot.frame }) do
		assert(not ns.Layout.Overlaps(ct, other), "the time capsule collides")
	end
	-- It can be moved there: in Edit Mode (blue while it is open), and kept
	-- from the console's centre; /rui clock reset puts it back.
	assert(not cap.highlight:IsShown(), "no Edit Mode blue outside Edit Mode")
	cap._scripts.OnDragStart(cap)
	assert(not cap.dragging, "the time capsule stays put without Edit Mode or Shift")
	EditModeManagerFrame._hooks.OnShow()
	assert(cap.highlight:IsShown(), "Edit Mode shows the time capsule can move")
	cap.GetCenter = function() return 500, 300 end
	ns.root.GetCenter = function() return 400, 384 end
	cap._scripts.OnDragStart(cap)
	assert(cap.dragging and cap._moving, "Edit Mode lets the time capsule be dragged")
	cap._scripts.OnDragStop(cap)
	local spot = ReforgedUIDB.consoleOpts.clockSpot
	assert(spot and spot.x == 100 and spot.y == -84, "the time capsule's new place is saved")
	local p = cap._points[1]
	assert(p[1] == "CENTER" and p[2] == ns.root and p[4] == 100 and p[5] == -84, "the time capsule stays where it was dragged")
	-- Edit Mode closed mid-drag lets go.
	cap._scripts.OnDragStart(cap)
	EditModeManagerFrame._hooks.OnHide()
	assert(not cap.dragging and not cap._moving and not cap.highlight:IsShown(), "closing Edit Mode ends the drag")
	ns:Relayout()
	flushTimers()
	assert(cap._points[1][1] == "CENTER", "the dragged place survives a relayout")
	SlashCmdList.REFORGEDUI("clock reset")
	local _, _, _, rx, ry = cap:GetPoint(1)
	assert(not ReforgedUIDB.consoleOpts.clockSpot and rx == ct.x and ry == ct.y, "/rui clock reset")
	cap.GetCenter, ns.root.GetCenter = nil, nil
	local y = savedLayouts.layouts[3].systems[7].anchorInfo.offsetY
	assert(y > buffY and y < 0, "buffs move up with the top bar hidden")
	ns:SetTopBarShown(true)
	flushTimers()
	assert(stateDrivers[ns.topRoot] == "[petbattle] hide; show", "the top bar is back")
	assert(tb.capsule._parent == ns.topRoot, "the time capsule goes back under the clock")
	checkMicro(MOVED)
	assert(savedLayouts.layouts[3].systems[7].anchorInfo.offsetY == buffY, "and the buffs under it")
end
-- Bars 1-3 in the grid, Action Bar 8 beside the minimap.
for key, prefix in pairs({ main = "ActionButton", bar2 = "MultiBarBottomLeftButton", bar3 = "MultiBarBottomRightButton" }) do
	local row = L.bars[key]
	for _, i in ipairs({ 1, 7, 12 }) do
		local btn = _G[prefix .. i]
		at(btn, row.xs[i], row.y, prefix .. i)
		assert(math.abs(btn._w * unit(btn) - row.size) < 0.01, prefix .. i .. " has the wrong size")
	end
end
-- The minimap slots: our own secure action buttons on the moonkin page
-- (109-111; a druid gets Action Bar 8's last three, 178-180), over the slots
-- beside the minimap.
for i = 1, 3 do
	local r, b = L.minimapSlots[i], _G["ReforgedUIMinimapButton" .. i]
	local p, sc = b._points[1], b._scale
	assert(b._kind == "secure" and p[2] == ns.root and math.abs(p[4] * sc - r.x) < 0.01 and math.abs(p[5] * sc - r.y) < 0.01
		and b._w == 45 and math.abs(b._w * sc - r.w) < 0.01, "minimap slot " .. i .. " placed")
	assert(b:GetAttribute("type") == "action" and b:GetAttribute("action") == 108 + i, "minimap slot " .. i .. " action")
end
do
	local shaman = UnitClass
	UnitClass = function() return "Druid", "DRUID" end
	assert(ns:MinimapSlot(1) == 178 and ns:MinimapSlot(3) == 180, "druids use Action Bar 8's last three slots")
	for i = 1, 3 do
		local slot = ns:MinimapSlot(i)
		assert(slot < 133 or slot > 144, "never the shaman totem slots (they only take totems)")
	end
	UnitClass = shaman
end
-- The gold dividers between buttons stay invisible, even after Blizzard
-- updates them.
assert(ActionButton7.RightDivider._alpha == 0, "button dividers hidden")
for _, b in ipairs({ ActionButton1, ReforgedUIMinimapButton1, ReforgedUIBagSlot1 }) do
	assert(b.reforgedFrame and b.reforgedFrame._tex:find("iconframe"), b:GetName() .. " has the steel icon frame")
end
assert(not ReforgedUIKeyRing.reforgedFrame and ReforgedUIKeyRing._normal:find("UI%-Button%-KeyRing"),
	"the key ring keeps Blizzard's own key ring button art")
ActionButton7.RightDivider:SetAlpha(1)
assert(ActionButton7.RightDivider._alpha == 0, "button dividers stay hidden")
MainActionBar:UpdateDividers()
for _, d in ipairs(dividerPool) do
	assert(d._alpha == 0 and d._shown, "bar dividers hidden by alpha, never Hide()")
end
-- An empty minimap slot says what it is for.
local tip
local oldSetText = methods.SetText
function GameTooltip:SetText(t) tip = t end
ReforgedUIMinimapButton3._scripts.OnEnter(ReforgedUIMinimapButton3)
assert(tip == "Empty slot: drag a spell, item or macro here.", "empty minimap slot tooltip")
GameTooltip.SetText = nil
methods.SetText = oldSetText
-- Stance (aura) buttons: Blizzard's, on the wall over the grid, anchored to
-- UIParent; their Edit Mode bar stays put. The pet buttons stay on their
-- Edit Mode bar, which the layout places (see above) so it can be moved.
for i = 1, 10 do
	at(_G["StanceButton" .. i], L.stance.x + (i - 1) * L.stance.step, L.stance.y, "stance button " .. i)
	assert(_G["StanceButton" .. i]:GetParent() == StanceBar, "stance buttons keep their parent")
	assert(#_G["PetActionButton" .. i]._points == 0 and _G["PetActionButton" .. i]:GetParent() == PetActionBar,
		"pet buttons stay on their Edit Mode bar")
end
-- The pet row (the pet bar's first place) clears the stance row and ends
-- before the inventory and chat area.
assert(L.pet.y >= L.stanceTop and L.pet.x + 9 * L.pet.step + L.pet.size < L.inventory[1].x
	and L.pet.y + L.pet.size <= L.consoleTop, "pet row over the grid, clear of the chat area")
assert(math.abs(StanceButton1._w * unit(StanceButton1) - L.stance.size) < 0.01, "stance button size")
assert(L.stance.y >= 0.55 * L.s and L.stance.x > L.portraitArt.x + L.portraitArt.w - 0.2 * L.s,
	"stance row sits on the wall over the grid")
assert(StanceBar._mouse == false and PetActionBar._mouse == false and StanceBar._alpha == nil,
	"stance and pet bar frames are click-through, not hidden")
-- The stance row moves by its outline while Edit Mode is open (a drag on a
-- stance button picks up its spell); /rui stance reset puts it back.
do
	local bars = ns.modules.actionbars
	local h = bars.stanceHolder
	assert(h == ReforgedUIStance and not h._shown and h._mouse == false, "the stance outline hides outside Edit Mode")
	h._scripts.OnDragStart(h)
	assert(not h._moving, "no moving the stance row outside Edit Mode")
	EditModeManagerFrame._hooks.OnShow()
	assert(h._shown and h._mouse ~= false, "Edit Mode shows the stance outline")
	inCombat = true
	h._scripts.OnDragStart(h)
	assert(not h._moving, "no moving the stance row in combat")
	inCombat = false
	h._scripts.OnDragStart(h)
	assert(h._moving, "Edit Mode drags the stance row")
	h._scripts.OnDragStop(h)
	assert(not h._moving and type(ns.db.consoleOpts.stanceSpot) == "table", "the stance row's spot is saved")
	EditModeManagerFrame._hooks.OnHide()
	assert(not h._shown and h._mouse == false, "the stance outline goes with Edit Mode")
	ns.db.consoleOpts.stanceSpot = { 300, 200 }
	bars:PlaceStance()
	for i = 1, 10 do
		at(_G["StanceButton" .. i], 300 + (i - 1) * L.stance.step, 200, "moved stance button " .. i)
	end
	ns:Relayout()
	at(StanceButton2, 300 + L.stance.step, 200, "the moved stance row stays after a relayout")
	-- Hidden (a warrior on key bindings): invisible and click-through, no
	-- outline in Edit Mode; shown again as it was.
	SlashCmdList.REFORGEDUI("stance hide")
	assert(ns.db.consoleOpts.hideStance == true, "/rui stance hide")
	for i = 1, 10 do
		local b = _G["StanceButton" .. i]
		assert(b._alpha == 0 and b._mouse == false, "hidden stance button " .. i)
	end
	StanceButton1:SetAlpha(1)
	assert(StanceButton1._alpha == 0, "the stance buttons stay hidden when Blizzard sets their alpha")
	ns:Relayout()
	assert(StanceButton3._alpha == 0, "the stance buttons stay hidden after a relayout")
	EditModeManagerFrame._hooks.OnShow()
	assert(not h._shown, "no stance outline in Edit Mode while hidden")
	EditModeManagerFrame._hooks.OnHide()
	SlashCmdList.REFORGEDUI("stance show")
	assert(ns.db.consoleOpts.hideStance == false, "/rui stance show")
	for i = 1, 10 do
		local b = _G["StanceButton" .. i]
		assert(b._alpha == 1 and b._mouse == true, "shown stance button " .. i)
	end
	StanceButton1:SetAlpha(0.5)
	assert(StanceButton1._alpha == 0.5, "shown stance buttons take Blizzard's alpha again")
	StanceButton1:SetAlpha(1)
	SlashCmdList.REFORGEDUI("stance reset")
	assert(ns.db.consoleOpts.stanceSpot == false, "/rui stance reset")
	at(StanceButton1, L.stance.x, L.stance.y, "stance row back on the wall")
	-- Left to another bar addon: the player's choice, or Dominos loaded.
	assert(not bars:LeavesStance(), "the stance buttons are ours by default")
	C_AddOns = { IsAddOnLoaded = function(name) return name == "Dominos" end }
	assert(bars:LeavesStance(), "Dominos gets the stance buttons")
	C_AddOns = nil
	ns.db.consoleOpts.leaveStance = true
	assert(bars:LeavesStance(), "the player can leave the stance buttons to their bar addon")
	ns.db.consoleOpts.leaveStance = false
end
-- The day/night indicator is hidden, not moved.
assert(GameTimeFrame._alpha == 0 and #GameTimeFrame._points == 0, "GameTimeFrame should be concealed, not moved")
assert(MinimapCluster.DielFrame._alpha == 0 and #MinimapCluster.DielFrame._points == 0,
	"Forever's DielFrame (the moon) should be concealed, not moved")
for _, b in ipairs(ns.modules.minimap.buttons) do
	assert(b ~= GameTimeFrame, "GameTimeFrame must not join the minimap button row")
end
assert(placed == 109, "the hearthstone should go into the first slot beside the minimap")
-- Up to 1.11 the slots were Action Bar 8's: its actions and keys moved over once.
assert(actions[110] == "Lightning Bolt" and not actions[170], "Action Bar 8's second action moved to minimap slot 2")
assert(GetBindingKey("CLICK ReforgedUIMinimapButton2:LeftButton") == "F2" and not GetBindingKey("MULTIACTIONBAR7BUTTON2")
	and bindingsSaved == 1, "Action Bar 8's key moved to the minimap slot binding")
assert(ReforgedUIMinimapButton2.hotkey._text == "F2", "the minimap slot shows its key")
-- Out of range: the key turns red, never the icon; no range to check: back to normal.
do
	local b = ReforgedUIMinimapButton2
	assert(rangeChecked[110] and rangeChecked[109] and rangeChecked[111], "range checks asked for the minimap slots")
	local normal = b.hotkey._textColor and b.hotkey._textColor[1]
	fire("ACTION_RANGE_CHECK_UPDATE", 110, false, true)
	assert(b.hotkey._textColor[1] == 1 and b.hotkey._textColor[2] < 0.2, "out of range: red key")
	assert(not (b.icon._vertex and b.icon._vertex[2] < 0.5 and b.icon._vertex[1] > 0.5), "out of range: icon not tinted red")
	fire("ACTION_RANGE_CHECK_UPDATE", 110, false, false)
	assert(b.hotkey._textColor[2] > 0.2 and (normal == nil or b.hotkey._textColor[1] == normal), "no target: key colour back")
end
-- Cooldown numbers follow the game's option.
do
	local mb, b = ns.modules.minimapbar, ReforgedUIMinimapButton1
	local hidden
	function b.cooldown:SetHideCountdownNumbers(h) hidden = h end
	local cvarOn = false
	GetCVarBool = function(name) return name == "countdownForCooldowns" and cvarOn end
	fire("CVAR_UPDATE", "countdownForCooldowns")
	assert(hidden == true, "cooldown numbers hidden while the option is off")
	cvarOn = true
	fire("CVAR_UPDATE", "countdownForCooldowns")
	assert(hidden == false, "cooldown numbers shown with the option on")
	GetCVarBool = nil
end
assert(ReforgedUIDB.consoleOpts.minimapBarMoved["Thrall-Forever"], "moved once per character")
actions[171] = "Earth Shock"
ns.modules.minimapbar:MoveFromBar8()
assert(actions[171] and not actions[111], "the move happens only once")
assert(ReforgedUIDB.consoleOpts.hearthstone["Thrall-Forever"], "the hearthstone is placed once per character")
assert(actions[109] == "Hearthstone", "the hearthstone is in the first minimap slot")
-- A druid placed on the shaman totem slots up to 1.15 (refused there) gets
-- one more try on the new slots, and a slot that refuses an action leaves it
-- where it was.
do
	local mb, opts, class = ns.modules.minimapbar, ReforgedUIDB.consoleOpts, UnitClass
	UnitClass = function() return "Druid", "DRUID" end
	mb:PlaceHearthstone()
	assert(actions[178] == "Hearthstone" and opts.hearthstone["Thrall-Forever"]
		and opts.druidSlotsMoved["Thrall-Forever"], "a druid's hearthstone retried on the new slots")
	actions[178] = nil
	opts.hearthstone["Thrall-Forever"] = nil
	mb:PlaceHearthstone()
	assert(actions[178] == "Hearthstone", "until it is placed")
	actions[178] = nil
	mb:PlaceHearthstone()
	assert(not actions[178], "then once per character")
	UnitClass = class
	local place = PlaceAction
	PlaceAction = function(slot)
		if slot == 109 then
			placed = "cursor" -- refused: still on the cursor
			return
		end
		place(slot)
	end
	actions[109], actions[169] = nil, "Moonfire"
	opts.minimapBarMoved["Thrall-Forever"] = nil
	mb:MoveFromBar8()
	assert(actions[169] == "Moonfire" and not actions[109], "a refused action goes back to its old slot")
	PlaceAction = place
	placed, actions[169] = nil, nil
	actions[109] = "Hearthstone"
end

-- Console art: all pieces placed with the original addon's files.
local console = ns.modules.console
for _, piece in ipairs(L.pieces) do
	local t = console.textures[piece.key]
	assert(t and t._tex == ns.ART .. piece.file, "art piece " .. piece.key .. " not drawn")
end
assert(console.textures.minimap._tex:find("art\\orc\\minimap_portrait\\minimap", 1, true), "orc minimap art")

-- Hero screen.
local hero = ns.modules.hero
assert(hero.health.text._text == "300 / 450" and hero.health._value == 300, "health")
assert(hero.power.text._text == "120 / 200", "power")
assert(hero.power._color[3] == 1 and hero.power._color[1] == 0, "mana is blue")
assert(hero.xp.level._text == "Level 12 Shaman" and hero.xp.name._text == "Thrall Son of Durotan", "name and level")
-- Long names shrink to fit the name plate, and short ones get the full size back.
do
	local fs = hero.xp.name
	local base = fs.fitSize
	ns:FitText(fs, string.rep("W", 60))
	assert(fs._size < base and fs:GetStringWidth() <= fs:GetWidth() or fs._size == 7, "a long name shrinks to fit")
	ns:FitText(fs, "Thrall")
	assert(fs._size == base, "a short name gets its full size back")
	-- Our font lacks Korean, Chinese and Cyrillic letters: the family behind
	-- every size hands them to the game's fonts.
	local members = {}
	for _, m in ipairs(fs._fontObject._members) do members[m.alphabet] = m end
	assert(members.roman.file == ns.FONT and members.roman.height == base, "names use our font")
	for _, alphabet in ipairs({ "korean", "simplifiedchinese", "traditionalchinese", "russian" }) do
		assert(members[alphabet] and members[alphabet].height == base, "names fall back for " .. alphabet)
	end
	-- A font set on the string directly would win over the family.
	assert(not fs._fontSetDirectly, "the name's font comes only from the family")
	SlashCmdList.REFORGEDUI("font")
	ns:FitText(fs, ns:FullName("player"))
end
assert(math.abs(hero.xp.bar._w - L.xp.bar.w / 4) < 0.01, "XP bar at 25%")
assert(math.abs(hero.xp.rested._w - L.xp.bar.w * 1500 / 4000) < 0.01, "rested XP")
assert(hero.stats[1].value._text == "10 - 16", "main hand damage")
assert(hero.stats[2]:IsShown() and not hero.stats[2].value:IsShown(), "second stat icon is an empty socket by default")
assert(hero.stats[2]:GetScript("OnMouseUp"), "an empty icon can still be right-clicked")
assert(hero.stats[4].value._text:find("%%"), "armour reduction")
hero:SetIconChoice(2, "offhand")
assert(hero.stats[2].value._text == "13.4%\n (10)", "a shield shows block chance and value")
hero.stats[2]:GetScript("OnEnter")(hero.stats[2])
assert(hero.infoBox.text._text:find("Block chance") and not hero.infoBox.text._text:find("Main Hand"),
	"the block icon's tooltip is about blocking")
hero.stats[1]:GetScript("OnEnter")(hero.stats[1])
assert(hero.infoBox.text._text:find("Main Hand Damage"), "the main hand tooltip")
hero:SetIconChoice(3, "ammo")
assert(hero.stats[3].value._text:find("No ammo"), "no ammo equipped")
local oldTexture = GetInventoryItemTexture
GetInventoryItemTexture = function(_, slot) if slot == 0 then return "Interface\\Icons\\INV_Ammo_Arrow_02" end end
hero:UpdateStats()
assert(hero.stats[3].value._text:find("350") and hero.stats[3].value._text:find("ffff00"), "ammo under 400 is yellow")
GetInventoryItemTexture = oldTexture
hero:SetIconChoice(3, "spell")
assert(hero.stats[3].value._text == "70", "spell power should be the best school")
hero:SetIconChoice(3, "heal")
assert(hero.stats[3].value._text == "207", "healing")
-- In combat the player's own stats can be secret: the icons keep their
-- picture and last value instead of blanking to a bare fist.
do
	local secretNum = setmetatable({}, { __lt = function() error("compared a secret value") end,
		__le = function() error("compared a secret value") end })
	local oldDamage, oldArmor, oldHeal, oldTex = UnitDamage, UnitArmor, GetSpellBonusHealing, GetInventoryItemTexture
	GetInventoryItemTexture = function(_, slot) if slot == 16 then return "Interface\\Icons\\INV_Hammer_01" end end
	hero:UpdateStats()
	UnitDamage = function() return secretNum, secretNum, secretNum, secretNum end
	UnitArmor = function() return secretNum, secretNum end
	GetSpellBonusHealing = function() return secretNum end
	secret = true
	hero:UpdateStats()
	secret = false
	assert(hero.stats[1].value._text == "10 - 16" and hero.stats[1].label._text:find("Damage"),
		"secret damage keeps the last value")
	assert(hero.stats[1].icon._tex == "Interface\\Icons\\INV_Hammer_01", "secret damage keeps the weapon icon")
	assert(hero.stats[4].value._text:find("%%") and hero.stats[4].label._text:find("Armor"), "secret armour keeps the last value")
	assert(hero.stats[3].value._text == "207" and hero.stats[3].icon._tex:find("Holy_Heal"), "secret healing keeps its icon")
	UnitDamage, UnitArmor, GetSpellBonusHealing, GetInventoryItemTexture = oldDamage, oldArmor, oldHeal, oldTex
	hero:UpdateStats()
end
assert(ReforgedUIDB.consoleOpts.icons.SHAMAN[3] == "heal", "icon choices are kept per class")
-- The defensive and attribute choices read their own stats, secret or not.
do
	local saved = { UnitAttackPower, UnitRangedAttackPower, GetDodgeChance, GetParryChance, UnitResistance, UnitStat }
	UnitAttackPower = function() return 300, 50, -10 end
	UnitRangedAttackPower = function() return 120, 0, 0 end
	GetDodgeChance = function() return 5.25 end
	GetParryChance = function() return 6.5 end
	UnitResistance = function(_, school) return 0, school * 10, 0, 0 end
	UnitStat = function(_, index) return 0, 40 + index, 0, 0 end
	local choices = hero:IconChoices()
	local old = { choices[1], choices[2], choices[3], choices[4] }
	local expect = {
		ap = { "Attack", "340" }, dodge = { "Dodge", "5.25%" }, parry = { "Parry", "6.50%" },
		sta = { "Stamina", "43" }, spi = { "Spirit", "45" },
	}
	for kind, want in pairs(expect) do
		choices[1] = kind
		hero:UpdateStats()
		assert(hero.stats[1].label._text:find(want[1]) and hero.stats[1].value._text == want[2], kind .. " icon value")
		assert(hero.stats[1].icon._tex and hero.stats[1].icon._tex:find("Interface\\Icons\\"), kind .. " icon picture")
	end
	choices[1] = "resist"
	hero:UpdateStats()
	local digits = hero.stats[1].value._text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	assert(digits == "20 30 40\n 50 60", "resistances show fire, nature, frost / shadow, arcane: " .. digits)
	-- A secret attack power keeps the last value.
	choices[1] = "ap"
	hero:UpdateStats()
	UnitAttackPower = function() return 999, 0, 0 end
	secret = true
	hero:UpdateStats()
	secret = false
	assert(hero.stats[1].value._text == "340", "secret attack power keeps the last value")
	for i = 1, 4 do
		choices[i] = old[i]
	end
	UnitAttackPower, UnitRangedAttackPower, GetDodgeChance, GetParryChance, UnitResistance, UnitStat = unpack(saved)
	hero:UpdateStats()
end
-- A right-click on a weapon icon opens its menu (or steps on without one).
local menuOpened
local oldMenu = ns.ShowMenu
ns.ShowMenu = function(_, owner, title, items)
	menuOpened = { owner = owner, title = title, items = items }
	return true
end
hero.stats[1]:GetScript("OnMouseUp")(hero.stats[1], "RightButton")
assert(menuOpened and menuOpened.owner == hero.stats[1] and #menuOpened.items == #hero.ICON_KINDS,
	"weapon icon right-click menu")
menuOpened.items[2].func()
assert(ReforgedUIDB.consoleOpts.icons.SHAMAN[1] == "offhand", "menu choice sets the icon")
ns.ShowMenu = function() return false end
hero.stats[1]:GetScript("OnMouseUp")(hero.stats[1], "RightButton")
assert(ReforgedUIDB.consoleOpts.icons.SHAMAN[1] == "ranged", "without menus a right-click steps on")
-- A right-click on the experience bar picks the rested colour.
ns.ShowMenu = function(_, owner, title, items)
	menuOpened = { owner = owner, title = title, items = items }
	return true
end
hero.xp.hover:GetScript("OnMouseUp")(hero.xp.hover, "RightButton")
assert(menuOpened.owner == hero.xp.hover and #menuOpened.items == 3, "rested colour menu: Purple, Blue, None")
assert(menuOpened.items[2].checked and not menuOpened.items[1].checked, "the default blue is ticked")
menuOpened.items[1].func()
assert(ReforgedUIDB.consoleOpts.restedColor[1] == 0.5 and ReforgedUIDB.consoleOpts.restedColor[3] == 0.5, "purple chosen")
ns.ShowMenu = function() return false end
hero.xp.hover:GetScript("OnMouseUp")(hero.xp.hover, "RightButton")
assert(ReforgedUIDB.consoleOpts.restedColor[3] == 1, "without menus a right-click steps to the next colour")
hero:SetRestedColor({ 0, 0, 1, 0.5 })
ns.ShowMenu = oldMenu
-- The options menu has a button per weapon icon that opens the same menu.
local config = ns.modules.config
config:Refresh()
assert(config.iconButtons[1]._text == "Ranged" and config.iconButtons[2]._text == "Off hand", "icon buttons name the choice")
ns.ShowMenu = function(_, owner, title, items)
	menuOpened = { owner = owner, title = title, items = items }
	return true
end
config.iconButtons[3]:GetScript("OnClick")(config.iconButtons[3])
assert(menuOpened.owner == config.iconButtons[3], "options button opens the icon menu")
menuOpened.items[#menuOpened.items].func()
assert(ReforgedUIDB.consoleOpts.icons.SHAMAN[3] == "none", "options menu sets the icon")
ns.ShowMenu = oldMenu
hero:SetIconChoice(1, "main")
assert(hero.stats[4].kind == "armor" and hero.stats[4].label._text:find("Armor"), "the fourth icon defaults to armour")
assert(config.iconButtons[4]._text == "Armor", "options menu shows the armour icon")
hero:SetIconChoice(4, "spell")
assert(hero.stats[4].value._text == "70", "the armour icon can show something else")
hero:SetIconChoice(4, "none")
assert(not hero.stats[4].value:IsShown() and hero.stats[4]:GetScript("OnMouseUp"), "an empty armour icon stays clickable")
hero:SetIconChoice(4, "armor")
ReforgedUIDB.consoleOpts.healthPercent = true
hero:UpdateHealth()
assert(hero.health.text._text == "67%", "health as a percentage")
local oldHealth = UnitHealth
UnitHealth = function() return 100 end
hero:UpdateHealth()
assert(hero.warning, "low health warning below 25%")
-- Secret values: no comparisons, no gradient, no warning.
secret = true
hero:UpdateHealth()
assert(not hero.warning and hero.health._value == 100, "secret health still reaches the bar")
secret = false
UnitHealth = oldHealth
ReforgedUIDB.consoleOpts.healthPercent = false
hero:UpdateHealth()
assert(hero.icons.rest:IsShown() and hero.icons.pvp._tex:find("Horde"), "status icons")

-- Bags: our own buttons that click Blizzard's, in the 2x3 inventory
-- (backpack top-left), the key ring beside it.
local inv = ns.modules.inventory
for i = 1, 5 do
	local p = inv.buttons[i]._points[1]
	local r = L.bagSlots[i]
	assert(p and p[2] == ns.root and math.abs(p[4] - r.x) < 0.01 and math.abs(p[5] - r.y) < 0.01,
		"bag " .. (i - 1) .. " should sit in the inventory")
	assert(inv.buttons[i]:IsShown(), "bag " .. (i - 1) .. " shown")
end
assert(L.bagSlots[1] == L.inventory[6] and L.bagSlots[6] == L.inventory[2], "backpack top-left, reagent bag bottom-right")
assert(not inv.buttons[6]:IsShown(), "no reagent bag slot on this client")
assert(inv.holder:IsShown() and inv.holder._alpha == nil, "bags always show")
assert(L.keyRing.x >= L.inventory[2].x + L.inventory[2].w and L.keyRing.x + L.keyRing.w <= L.chat.x,
	"the key ring stands between the inventory and the chat area")
inv.buttons[1]._scripts.OnClick(inv.buttons[1])
inv.buttons[3]._scripts.OnClick(inv.buttons[3])
assert(MainMenuBarBackpackButton._clicks == 1 and CharacterBag1Slot._clicks == 1, "bag clicks go to Blizzard's buttons")

-- Top bar: clock, and our own data feeds in the first slots.
local tb = ns.modules.topbar
do
	-- Money reads as coins, without empty leading units.
	local function plain(text) return (text:gsub("|T.-|t", "")) end
	assert(plain(tb.FormatMoney(222)) == "2 22" and select(2, tb.FormatMoney(222):gsub("|T", "")) == 2, "2s 22c")
	assert(plain(tb.FormatMoney(1234567)) == "123 45 67" and plain(tb.FormatMoney(0)) == "0", "gold, silver, copper")
	assert(tb.FormatMoney(222):find("SilverIcon") and not tb.FormatMoney(222):find("GoldIcon"), "no 0g")
end
assert(math.abs(tb.dial._rotation + math.pi) < 1e-6, "midnight should turn the moon to the window")
gameHour = 12
tb:UpdateClock()
assert(math.abs(tb.dial._rotation) < 1e-6, "noon should put the sun in the window")
assert(tb.slots[1].text._text == tb.FormatMoney(1234567), "slot 1 should show the money")
-- The gold tooltip lists every character's saved gold, richest first, under
-- its faction (this one first), with a total per faction and none across them.
local thrall = ReforgedUIDB.money.Forever["Thrall Son of Durotan"]
assert(thrall and thrall.money == 1234567, "this character's money is saved, under the full name")
assert(thrall.name == "Thrall Son of Durotan", "with the full name")
assert(thrall.faction == "Horde", "and the faction")
ReforgedUIDB.money.Forever.Garrosh = { money = 5000000, class = "WARRIOR", faction = "Horde" }
ReforgedUIDB.money.Forever.Jaina = { money = 7000000, class = "MAGE", faction = "Alliance", name = "Jaina Proudmoore" }
ReforgedUIDB.money.Forever.Anduin = { money = 300, class = "PRIEST", faction = "Alliance" }
ReforgedUIDB.money.Elsewhere = { Rexxar = { money = 100, class = "HUNTER", faction = "Horde" } }
ReforgedUIDB.money.Forever.Old = { money = 42, class = "ROGUE" } -- saved before factions were
do
	local lines = {}
	local fake = {
		AddLine = function(_, text) lines[#lines + 1] = text end,
		AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
	}
	tb.feeds.gold.OnTooltipShow(fake)
	local text = table.concat(lines, "\n")
	local function at(s) return assert(text:find(s, 1, true), s .. " missing from the gold tooltip") end
	assert(at("Horde") < at("Garrosh=") and at("Garrosh=") < at("Thrall Son of Durotan="), "richest first")
	assert(at("Thrall Son of Durotan=") < at("Elsewhere") and at("Elsewhere") < at("Rexxar="), "this realm first")
	assert(at("Rexxar=") < at("Alliance") and at("Alliance") < at("Jaina Proudmoore="), "this faction first")
	assert(at("Jaina Proudmoore=") < at("Anduin="), "Alliance richest first")
	assert(at("Total=" .. tb.FormatMoney(5000000 + 1234567 + 100)) < at("Alliance"), "Horde total")
	assert(text:find("Total=" .. tb.FormatMoney(7000000 + 300), 1, true), "Alliance total")
	assert(at("Anduin=") < at("not known") and at("not known") < at("Old="), "unknown faction last")
	assert(not text:find(tb.FormatMoney(5000000 + 1234567 + 100 + 7000000 + 300), 1, true), "no total across factions")
end
-- Forever: realm names are servers behind a ruleset; the tooltip groups
-- them by ruleset under its clean name, this character's first.
do
	local R = tb.Ruleset
	assert(R("CAMWOW EU5 Realm 1 PvE") == "Normal" and R("CAMWOW EU5 Realm 7 PvE") == "Normal", "PvE is Normal")
	assert(R("Realm 2 PvP") == "PvP" and R("Realm 3 RP") == "RP", "PvP, RP")
	assert(R("Realm 4 RP-PvP") == "RP-PvP" and R("Realm 4 RPPvP") == "RP-PvP", "RP-PvP")
	assert(R("Realm 5 Hardcore") == "Hardcore", "Hardcore")
	assert(R("Forever") == nil and R("Stormrage") == nil and R("Skarp") == nil, "real realm names stay")
	local realGetRealmName = GetRealmName
	GetRealmName = function() return "CAMWOW EU5 Realm 1 PvE" end
	ReforgedUIDB.money = {
		["CAMWOW EU5 Realm 1 PvE"] = {
			-- saved by older versions under the first name: this character
			Thrall = { money = 1, class = "SHAMAN", faction = "Horde", name = "Thrall Son of Durotan" },
			Jane = { money = 500, class = "SHAMAN", faction = "Horde", name = "Jane Shimsham" },
		},
		["CAMWOW EU5 Realm 7 PvE"] = {
			["Jane Darnassus"] = { money = 85, class = "ROGUE", faction = "Horde" },
			["Thrall Son of Durotan"] = { money = 2, class = "SHAMAN", faction = "Horde", name = "Thrall Son of Durotan" },
		},
		["CAMWOW EU5 Realm 2 PvP"] = { ["Jane Skywall"] = { money = 7, class = "MAGE", faction = "Horde" } },
	}
	local lines = {}
	local fake = {
		AddLine = function(_, text) lines[#lines + 1] = text end,
		AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
	}
	tb.feeds.gold.OnTooltipShow(fake)
	local text = table.concat(lines, "\n")
	local function at(s) return assert(text:find(s, 1, true), s .. " missing from the gold tooltip") end
	local realm1 = ReforgedUIDB.money["CAMWOW EU5 Realm 1 PvE"]
	assert(realm1.Thrall == nil and realm1["Thrall Son of Durotan"].money == 1234567, "old first-name entry replaced")
	assert(ReforgedUIDB.money["CAMWOW EU5 Realm 7 PvE"]["Thrall Son of Durotan"] == nil, "stale copy on the same ruleset goes")
	assert(not text:find("CAMWOW", 1, true), "no server names")
	local _, normals = text:gsub("\nNormal\n", "")
	assert(normals == 1, "both PvE servers under one Normal header")
	assert(at("Normal") < at("Thrall Son of Durotan=") and at("Jane Darnassus=") < at("PvP\n"), "Normal (this ruleset) first")
	assert(at("PvP\n") < at("Jane Skywall="), "then PvP")
	assert(text:find("Total=" .. tb.FormatMoney(1234567 + 500 + 85 + 7), 1, true), "faction total")
	GetRealmName = realGetRealmName
end
ReforgedUIDB.money = { Forever = { ["Thrall Son of Durotan"] = thrall } }
assert(tb.slots[2].text._text == "25 / 80", "slot 2 should show bag space")
assert(tb.slots[3].text._text:find("20%%"), "slot 3 should show durability")
assert(tb.slots[4].text._text == "", "slot 4 should start empty")
local ldb = LibStub("LibDataBroker-1.1")
local feed = ldb:NewDataObject("Test Feed", { type = "data source", text = "hello" })
assert(SlashCmdList.REFORGEDUI and true)
SlashCmdList.REFORGEDUI("slot 4 test feed")
assert(tb.slots[4].text._text == "hello", "slot 4 should show the chosen feed")
feed.text = "updated"
assert(tb.slots[4].text._text == "updated", "feed changes should reach the slot")
SlashCmdList.REFORGEDUI("slot 5 test feed")
assert(tb.slots[4].text._text == "" and tb.slots[5].text._text == "updated", "a feed should move, not duplicate")
do
	-- Ping and framerate: world latency on the left of the slot, fps on the right.
	tb.pingTimer._scripts.OnUpdate(tb.pingTimer, 1)
	SlashCmdList.REFORGEDUI("slot 6 ping")
	local slot = tb.slots[6]
	assert(slot.left._shown and slot.left._text:find("180 ms", 1, true) and slot.left._text:find("ffd100"),
		"world ping on the left, in yellow")
	assert(slot.text._text == "60 fps", "fps on the right")
	assert(tb.feeds.ping.text:find("180 ms", 1, true) and tb.feeds.ping.text:find("60 fps", 1, true),
		"other displays get both")
	GetNetStats = function() return 1, 1, 30, 45 end
	GetFramerate = function() return 120 end
	tb.pingTimer._scripts.OnUpdate(tb.pingTimer, 0.5)
	assert(slot.text._text == "60 fps", "updates once a second")
	tb.pingTimer._scripts.OnUpdate(tb.pingTimer, 0.5)
	assert(slot.text._text == "120 fps" and slot.left._text:find("45 ms", 1, true) and slot.left._text:find("33ff33"),
		"a second later, the new values")
	local lines = {}
	tb.feeds.ping.OnTooltipShow({
		AddLine = function(_, t) lines[#lines + 1] = t end,
		AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
	})
	local text = table.concat(lines, "\n")
	assert(text:find("World latency", 1, true) and text:find("Home latency", 1, true) and text:find("120 fps", 1, true),
		"ping tooltip")
	SlashCmdList.REFORGEDUI("slot 6 none")
	assert(not slot.left._shown and slot.text._text == "", "an emptied slot drops the ping")
end
do
	-- The time capsule under the clock: server time on a 24 hour clock by
	-- default; the options switch it to local time, 12 hours, or hide it.
	local cap = tb.capsule
	gameHour = 0
	tb:UpdateClock()
	assert(cap._shown ~= false and cap.text._text == "00:00", "server time, 24 hours, by default")
	local clock = ns.topLayout.clockFrame
	local _, _, _, cx = cap:GetPoint(1)
	assert(math.abs(cx + cap._w / 2 - (clock.x + clock.w / 2)) < 0.01, "the capsule is centred under the clock")
	assert(cap:GetFrameLevel() > tb.clockFrame:GetFrameLevel(), "the capsule's top draws over the clock frame's ring")
	local cfg = ns.modules.config
	cfg.clockHoursButton._scripts.OnClick(cfg.clockHoursButton)
	assert(cap.text._text == "12:00 AM" and ReforgedUIDB.consoleOpts.clockHours == 12, "12 hours")
	cfg.clockTimeButton._scripts.OnClick(cfg.clockTimeButton)
	assert(cap.text._text == "9:07 PM" and ReforgedUIDB.consoleOpts.clockTime == "local", "local time")
	gameHour, localClock.hour, localClock.min = 12, 9, 30
	tb.ticker._scripts.OnUpdate(tb.ticker, 1)
	assert(cap.text._text == "9:30 AM", "the capsule keeps time")
	cfg.clockTimeButton._scripts.OnClick(cfg.clockTimeButton)
	assert(cap._shown == false and ReforgedUIDB.consoleOpts.clockTime == "off", "hidden")
	cfg.clockTimeButton._scripts.OnClick(cfg.clockTimeButton)
	cfg.clockHoursButton._scripts.OnClick(cfg.clockHoursButton)
	assert(cap._shown and cap.text._text == "12:00", "back to server time, 24 hours")
	assert(tb.FormatTime(13, 5, 12) == "1:05 PM" and tb.FormatTime(12, 0, 12) == "12:00 PM" and tb.FormatTime(9, 5, 24) == "09:05",
		"time formats")
	gameHour = 0
	tb:UpdateClock()
	-- The zone, coloured like the minimap's.
	SlashCmdList.REFORGEDUI("slot 8 zone")
	assert(tb.slots[8].text._text:find("Durotar", 1, true), "zone feed shows the zone")
	SlashCmdList.REFORGEDUI("slot 8 none")
end
do
	-- Game panels go in slots too: opened by a secure click on Blizzard's
	-- micro button for them (hidden ones included), set up out of combat.
	local panels = {}
	for _, p in ipairs(tb:PanelList()) do panels[p.key] = p end
	assert(panels.quests and panels.map and panels.menu and panels.talents and panels.character, "panels with micro buttons")
	assert(not panels.skills and not panels.professions, "no panel without a way to open it")
	SlashCmdList.REFORGEDUI("slot 4 quests")
	local slot = tb.slots[4]
	assert(slot.text._text == panels.quests.label and not slot.icon._shown, "slot 4 shows the quest log, without an icon")
	local title = ns.theme.title
	assert(slot.text._textColor and slot.text._textColor[1] == title[1] and slot.text._textColor[3] == title[3],
		"in the theme's menu colour")
	local f = slot.secure
	assert(f and f:IsProtected() and f:IsShown() and f:GetParent() == UIParent, "a secure button over the slot")
	assert(f:GetAttribute("type1") == "click" and f:GetAttribute("clickbutton") == QuestLogMicroButton,
		"which clicks the quest log's micro button")
	assert(f._points[1][2] == UIParent and f._w > 0 and f._h > 0, "hanging from UIParent, not our frames")
	local clicks = QuestLogMicroButton._clicks or 0
	slot._scripts.OnClick(slot, "LeftButton")
	assert(QuestLogMicroButton._clicks == clicks + 1, "the slot's own click opens it too")
	f._scripts.PostClick(f, "LeftButton")
	assert(QuestLogMicroButton._clicks == clicks + 1, "no second click after the secure one")
	inCombat = true
	SlashCmdList.REFORGEDUI("slot 4 map")
	assert(slot.text._text == panels.map.label and f:GetAttribute("clickbutton") == QuestLogMicroButton,
		"the secure button waits for the end of combat")
	inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	assert(f:GetAttribute("clickbutton") == WorldMapMicroButton, "and changes after it")
	SlashCmdList.REFORGEDUI("slot 4 game menu")
	assert(f:GetAttribute("clickbutton") == MainMenuMicroButton, "panels by their name")
	-- Classic's skills: a tab of the character window, opened from our code.
	local opened
	SkillFrame = new("frame", "SkillFrame", UIParent)
	ToggleCharacter = function(tab) opened = tab end
	SlashCmdList.REFORGEDUI("slot 4 skills")
	assert(slot.text._text == tb.PANELS[5].label and not f:IsShown(), "skills, with no secure button")
	slot._scripts.OnClick(slot, "LeftButton")
	assert(opened == "SkillFrame", "skills open the character window's skill tab")
	SkillFrame, ToggleCharacter = nil, nil
	SlashCmdList.REFORGEDUI("slot 4 none")
	assert(slot.text._text == "" and not f:IsShown(), "an emptied slot drops the secure button")
	assert(slot.text._textColor[1] == 1 and slot.text._textColor[2] == 1 and slot.text._textColor[3] == 1, "and goes back to white")
end
assert(tb.panel and ns.topRoot and tb.holder:GetParent() == ns.topRoot, "top bar lives on its own root")
do
	-- The clock hangs from the screen's top edge over the bar; the dial turns
	-- between the bar and the clock frame. The whole top bar stays in the
	-- BACKGROUND strata, below Blizzard's buffs.
	local T = ns.topLayout
	assert(math.abs(T.clockFrame.y + T.clockFrame.h - T.H) < 0.01, "clock frame flush with the top of the screen")
	assert(T.clockFrame.y >= T.topBar.y - 50, "clock frame should hang less far below the bar")
	assert(tb.dialFrame:GetFrameLevel() > tb.panel:GetFrameLevel()
		and tb.clockFrame:GetFrameLevel() > tb.dialFrame:GetFrameLevel(), "bar < dial < clock frame")
	assert(tb.holder._strata == "BACKGROUND", "top bar below Blizzard's buff frames")
end

-- Something else moving a locked frame snaps it back.
ChatFrame1:ClearAllPoints()
ChatFrame1:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
assert(ChatFrame1._points[1][1] == "BOTTOMLEFT" and ChatFrame1._points[1][2] == UIParent, "chat lock failed")
at(ChatFrame1, L.chat.x, L.chat.y, "chat window")
assert(L.chat.y + L.chat.h < L.byKey.br_top.rect.y, "the chat's top line stays under the wall")
-- The social button sits on the chat buttons' column, not up in the world.
QuickJoinToastButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 600)
assert(QuickJoinToastButton._points[1][2] == ChatFrame1.ButtonFrame
	and QuickJoinToastButton._points[1][3] == "TOPLEFT", "social button over the chat buttons")
assert(ChatFrameMenuButton._points[1][2] == ChatFrameChannelButton, "chat menu button under the channel button")
ChatFrameToggleVoiceDeafenButton:Show()
ChatFrameToggleVoiceDeafenButton._hooks.OnShow(ChatFrameToggleVoiceDeafenButton)
assert(ChatFrameMenuButton._points[1][2] == ChatFrameToggleVoiceDeafenButton, "and under the voice buttons while they show")
ChatFrameToggleVoiceDeafenButton:Hide()

-- Protected frames moved in combat are queued until combat ends.
inCombat = true
ActionButton1:SetPoint("CENTER", UIParent, "CENTER", 5, 5)
assert(ActionButton1._points[#ActionButton1._points][1] == "CENTER", "protected frame moved in combat")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(ActionButton1._points[1][1] == "BOTTOMLEFT", "queued relock did not run")

-- The options menu.
local config = ns.modules.config
-- Every option has room of its own: no two overlap (two changes made apart
-- once put a checkbox each on the same spot), and none leaves the menu.
do
	local MARGIN = 10 -- the menu's border
	local function clash(claims)
		for i, a in ipairs(claims) do
			if a.x < MARGIN or a.x + a.w > 650 - MARGIN or a.y > -MARGIN or a.y - a.h < MARGIN - config.height then
				return a.name .. " leaves the menu"
			end
			for j = i + 1, #claims do
				local c = claims[j]
				if a.x < c.x + c.w and c.x < a.x + a.w and a.y > c.y - c.h and c.y > a.y - a.h then
					return a.name .. " overlaps " .. c.name
				end
			end
		end
	end
	local claims = config.claims
	assert(#claims >= #config.checks + #config.edits + #config.sliders * 2 + #config.themeButtons, "every option claims its room")
	assert(ReforgedUIConfig:GetHeight() == config.height and config.height > 0, "the menu is as tall as its rows")
	local why = clash(claims)
	assert(not why, "options menu: " .. tostring(why))
	-- The check itself: an option put on another's spot, or past the edge, is caught.
	local first = claims[1]
	claims[#claims + 1] = { name = "copy", x = first.x + 2, y = first.y - 2, w = first.w, h = first.h }
	assert(clash(claims), "an overlapping option is caught")
	claims[#claims] = { name = "low", x = 20, y = 5 - config.height, w = 100, h = 24 }
	assert(clash(claims) == "low leaves the menu", "an option under the menu is caught")
	claims[#claims] = nil
end
-- "Let me move and resize the chat window" lets go of the chat window and
-- puts the input box back on it; turning it off holds it again.
do
	local check
	for _, cb in ipairs(config.checks) do
		if cb.key == "freeChat" then check = cb end
	end
	assert(check, "chat window option")
	check:SetChecked(true)
	check:GetScript("OnClick")(check)
	ChatFrame1:ClearAllPoints()
	ChatFrame1:SetPoint("CENTER", UIParent, "CENTER", 123, 45)
	assert(ChatFrame1._points[1][4] == 123, "a free chat window stays where it is moved")
	assert(ChatFrame1EditBox._points[1][2] == ChatFrame1, "the input box follows its window")
	check:SetChecked(false)
	check:GetScript("OnClick")(check)
	assert(ChatFrame1._points[1][2] == UIParent and ChatFrame1._points[1][1] == "BOTTOMLEFT", "the chat window is held again")
	assert(not ReforgedUIDB.consoleOpts.freeChat, "option off")
end
-- In the game's options it sits inside the AddOns page, and leaves with it.
assert(config.settingsPanel, "options page registered")
config.settingsPanel:Show()
config.settingsPanel:GetScript("OnShow")(config.settingsPanel)
assert(ReforgedUIConfig:IsShown() and ReforgedUIConfig:GetParent() == config.settingsPanel, "menu shown inside the options page")
config.settingsPanel:Hide()
config.settingsPanel:GetScript("OnHide")(config.settingsPanel)
assert(not ReforgedUIConfig:IsShown() and ReforgedUIConfig:GetParent() == UIParent, "menu leaves with the options page")
SlashCmdList.REFORGEDUI("config")
assert(ReforgedUIConfig:IsShown(), "/rui config opens the menu")
for _, eb in ipairs(config.edits) do
	if eb.key == "uiScale" then eb._text = "999" end
end
function methods:GetText() return self._text end
config:Apply()
assert(ReforgedUIDB.consoleOpts.uiScale == 270 and ns.layout.s == 270, "UI scale is clamped to 240-270")
for _, cb in ipairs(config.checks) do
	assert(not tContains({ "hideBags", "placeChat", "hideMicro" }, cb.key), "no " .. tostring(cb.key) .. " option")
	assert(cb.key, "every checkbox is a plain option (no centre mode boxes)")
end
-- The transparency slider fades the console's art, saved, and nothing else.
local slider = config.sliders[1]
assert(slider and slider.key == "transparency", "transparency slider")
assert(ReforgedUIDB.consoleOpts.transparency == 0 and ns.modules.console.frames.bg:GetAlpha() == 1, "opaque by default")
slider:SetValue(10)
assert(ReforgedUIDB.consoleOpts.transparency == 10, "transparency saved")
for key, f in pairs(ns.modules.console.frames) do
	assert(math.abs(f:GetAlpha() - 0.9) < 1e-6, key .. " art faded")
end
assert(config.cogwheel:GetAlpha() == 1, "the cogwheel stays opaque")
ns:Relayout()
assert(math.abs(ns.modules.console.frames.grid:GetAlpha() - 0.9) < 1e-6, "transparency survives a relayout")
slider:SetValue(0)
assert(ns.modules.console.frames.cap:GetAlpha() == 1, "back to opaque")
-- The target aura size slider: shown at 100 % while unset, and left unset
-- until moved (then saved, in steps of 5).
do
	local auras
	for _, sl in ipairs(config.sliders) do
		if sl.key == "targetAuraSize" then auras = sl end
	end
	assert(auras, "target aura size slider")
	local was = ReforgedUIDB.consoleOpts.targetAuraSize
	ReforgedUIDB.consoleOpts.targetAuraSize = false
	auras:SetValue(130)
	ReforgedUIDB.consoleOpts.targetAuraSize = false
	config:Refresh()
	assert(auras:GetValue() == 100 and ReforgedUIDB.consoleOpts.targetAuraSize == false,
		"an unset aura size stays unset when the menu is shown")
	auras:SetValue(150)
	assert(ReforgedUIDB.consoleOpts.targetAuraSize == 150, "aura size saved when moved")
	ReforgedUIDB.consoleOpts.targetAuraSize = was
	config:Refresh()
end
-- The chat width slider: on a screen too narrow for the original addon's
-- chat area (16:10 here), the console scales down to make room for it; 0 %
-- keeps a 16:9 screen's width. Wider screens are left alone.
do
	local chat = config.sliders[2]
	assert(chat and chat.key == "chatWiden", "chat width slider")
	local w, h, uiScale = UIParent._w, UIParent._h, ReforgedUIDB.consoleOpts.uiScale
	ReforgedUIDB.consoleOpts.uiScale = 240
	UIParent._w, UIParent._h = 1920, 1200
	assert(ReforgedUIDB.consoleOpts.chatWiden == 0, "16:9 width by default")
	ns:Relayout()
	local narrow = ns.layout.byKey.chat_bg.rect.w
	assert(math.abs(ns.layout.W - 1365.33) < 0.01, "16:9 width at 0 %")
	chat:SetValue(100)
	assert(ReforgedUIDB.consoleOpts.chatWiden == 100, "chat width saved")
	local wide = ns.layout.byKey.chat_bg.rect.w
	assert(wide > narrow + 150 and wide >= ns.Layout.ENDCAP_CHAT_MIN * 240, ("the chat area widens: %s to %s"):format(narrow, wide))
	assert(ns.layout.byKey.chat_bg.rect.x + wide <= ns.layout.W + 0.01, "and stays on screen")
	assert(ns.layout.byKey.chat_bg.rect.x + wide >= ns.layout.W - 2,
		"and reaches the screen edge, the end caps past it")
	chat._scripts.OnMouseUp(chat)
	UIParent._w, UIParent._h = 1792, 768
	ns:Relayout()
	assert(ns.layout.W == 1792, "21:9 is wide enough already")
	chat:SetValue(0)
	UIParent._w, UIParent._h, ReforgedUIDB.consoleOpts.uiScale = w, h, uiScale
	ns:Relayout()
end
-- The chat height slider raises the chat area, saved, shown in units.
do
	local height = config.sliders[3]
	assert(height and height.key == "chatUp", "chat height slider")
	for _, eb in ipairs(config.edits) do
		assert(eb.key ~= "chatUp", "chat height is a slider, not a number box")
	end
	local before = ReforgedUIDB.consoleOpts.chatUp
	ns:Relayout()
	local low = ns.layout.byKey.chat_bg.rect.h
	height:SetValue(before + 60)
	assert(ReforgedUIDB.consoleOpts.chatUp == before + 60, "chat height saved")
	assert(math.abs(ns.layout.byKey.chat_bg.rect.h - (low + 60)) < 0.01, "the chat area grows by the slider's units")
	assert(height.value._text == tostring(before + 60), "shown without a % sign")
	height._scripts.OnMouseUp(height)
	height:SetValue(before)
end
-- Everything left of the chat area fits ns.Layout.CONSOLE_FIXED on every theme.
for _, theme in ipairs(ns.Layout.THEMES) do
	for _, s in ipairs({ 240, 255, 270 }) do
		local LT = ns.Layout.Compute(5000, 768, { s = s, m = 10, theme = theme, zoneTextPos = 1 })
		assert(LT.chatBgX - LT.shift <= ns.Layout.CONSOLE_FIXED * s, theme .. " fits CONSOLE_FIXED")
	end
end
config.cogwheel._scripts.OnClick()
assert(not ReforgedUIConfig:IsShown(), "the cogwheel toggles the menu")

-- The top bar's pieces never collide: micro buttons, clock and feed slots
-- (slots give way first), the clock centred.
local function checkTopBar()
	local T, O = ns.topLayout, ns.Layout.Overlaps
	assert(math.abs(T.clock.cx - T.W / 2) <= 1, "the clock stays centred")
	checkMicro(MOVED)
	local pieces = {}
	for _, r in ipairs(T.micro) do
		assert(r.x >= 0 and r.x + r.w <= T.W and r.y >= T.topBar.y and r.y + r.h <= T.H + 0.01, "micro button off the bar")
		assert(r.h >= ns.Layout.TOP_SIZES.microMinH - 0.01, "micro buttons shrink only so far")
		pieces[#pieces + 1] = r
	end
	-- Slots: the first on each side the same distance from the centre, all
	-- on the bar's pattern (which starts at the first right-hand slot), and
	-- centred in the band above the trim.
	local cx, nearL, nearR = T.clock.cx
	local period = ns.Layout.TOP_SIZES.slotW + ns.Layout.TOP_SIZES.slotGap
	for _, r in ipairs(T.topSlots) do
		if r.x >= cx then
			nearR = math.min(nearR or math.huge, r.x - cx)
		else
			nearL = math.min(nearL or math.huge, cx - (r.x + r.w))
		end
		local phase = (r.x - T.topBar.originX) % period
		assert(phase < 0.01 or period - phase < 0.01, "a slot off the bar's pattern")
	end
	assert(not (nearL and nearR) or math.abs(nearL - nearR) < 0.01, "slots either side of the centre at different distances")
	for _, r in ipairs(T.topSlots) do
		assert(not O(r, T.clockArt) and r.x >= 0 and r.x + r.w <= T.W, "a slot overlaps the clock or leaves the screen")
		pieces[#pieces + 1] = r
	end
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			assert(not O(pieces[i], pieces[j]), ("top bar pieces %d and %d overlap at %.0fx%.0f"):format(i, j, T.W, T.H))
		end
	end
end

-- Every theme, UI scale and screen shape lays out, centred with the chat
-- area and inventory.
local slash = SlashCmdList.REFORGEDUI
for _, size in ipairs({ { 1365.33, 768, "standard" }, { 1792, 768, "wide" }, { 2730.67, 768, "superwide" },
	{ 1024, 768, "standard" }, { 1920, 1080, "standard" }, { 1920, 1200, "standard" }, { 4266.67, 1200, "superwide" } }) do
	UIParent._w, UIParent._h = size[1], size[2]
	slash("layout auto")
	assert(math.abs(ns.topLayout.H - 768 / ns.db.scale) < 0.01, "the top bar should keep its share of the screen")
	assert(ns.topLayout.profile == size[3],
		("expected %s at %sx%s, got %s"):format(size[3], size[1], size[2], ns.topLayout.profile))
	assert(ns.layout.H == 768, "the console is 768 units tall")
	-- Narrower than 16:9 (16:10, 4:3), the console scales down to a 16:9
	-- screen's width, so the chat area keeps its 16:9 width.
	assert(ns.layout.W >= 1365.33 - 0.01, "the console is never narrower than 16:9")
	assert(math.abs(ns.root._h * ns:ConsoleScale() - size[2]) < 0.01, "the console's root fills the screen's height")
	-- The target's aura icons are placed through the Edit Mode layout all
	-- characters share: the same spot on every theme, else each login on
	-- another race asks for a reload.
	local auraSpot = {}
	for _, theme in ipairs({ "human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll",
		"highorder", "windshapers", "forsaken", "skyborne", "auto" }) do
		slash("theme " .. theme)
		for _, s in ipairs({ 240, 245, 250, 255, 260, 266, 270 }) do
			ReforgedUIDB.consoleOpts.uiScale = s
			ns:Relayout()
			local LL = ns.layout
			assert(LL.s == s, "options reach the layout")
			assert(LL.chat and LL.inventory and LL.bagSlots, "chat area and inventory always there")
			local bg = LL.byKey.chat_bg.rect
			assert(LL.W < 1365 or bg.x + bg.w <= LL.W + 0.01, "the chat area stays on screen")
			assert(LL.shift == 0 or math.abs((LL.W - LL.rightPoint) - LL.shift) <= 2, ("the console is centred: W %s s %s shift %s right %s"):format(LL.W, s, LL.shift, LL.rightPoint))
			for _, mode in ipairs({ "swap", "plate" }) do
				local spot = LL.targetAuras[mode]
				local key = s .. mode
				auraSpot[key] = auraSpot[key] or spot
				assert(math.abs(spot.x0 - auraSpot[key].x0) < 1e-6 and math.abs(spot.y - auraSpot[key].y) < 1e-6,
					("the target's auras stay put on every theme: %s %s at W %s s %s (%s,%s, not %s,%s)"):format(
						theme, mode, LL.W, s, spot.x0, spot.y, auraSpot[key].x0, auraSpot[key].y))
			end
		end
	end
	checkTopBar()
	for _, p in ipairs({ "16:9", "21:9", "32:9" }) do
		slash("layout " .. p)
		for _, k in ipairs({ "1.5", "1", "0.5", "0.75" }) do
			slash("scale " .. k)
			checkTopBar()
		end
	end
end
checkAnchors()

-- 32:9 (5120x1440) and 21:9: centred with the original addon's chat width; 16:9: the
-- chat area reaches the screen edge.
UIParent._w, UIParent._h = 5120 * 768 / 1440, 768
ReforgedUIDB.consoleOpts.uiScale = 240
ns:Relayout()
do
	local LL = ns.layout
	local bg = LL.byKey.chat_bg.rect
	assert(LL.shift > 400, "32:9 should centre the console")
	assert(math.abs(bg.w - 2.2 * LL.s) < 0.01, "32:9 chat area should take the original addon's default width")
	assert(LL.rightPoint < LL.W - 400, "the console should leave screen free on the right")
	at(ChatFrame1, LL.chat.x, LL.chat.y, "centred chat window")
	at(StanceButton1, LL.stance.x, LL.stance.y, "centred stance button")
	-- The chat window and its input box fill the area down to the floor trim.
	assert(LL.chatEdit.y <= 0.03 * LL.s + 2 and LL.chat.y == LL.chatEdit.y + 26,
		"no empty band under the chat input box")
	UIParent._w = 3440 * 768 / 1440
	ns:Relayout()
	assert(ns.layout.shift > 0 and math.abs(ns.layout.byKey.chat_bg.rect.w - 2.2 * 240) < 0.01, "21:9 is centred")
	UIParent._w = screenW
	ns:Relayout()
	bg = ns.layout.byKey.chat_bg.rect
	assert(ns.layout.shift == 0 and math.abs(bg.x + bg.w - screenW) < 0.01, "16:9: the chat area reaches the edge")
end
checkAnchors()

-- Race themes: the default ("auto") follows the race, Skyborne by its token or
-- its name, with the faction picking the variant; other races fall back by
-- faction; a chosen theme overrides the race.
local function themeFor(race, raceFile, faction, saved, raceID)
	playerRace, playerRaceFile, playerFaction, playerRaceID = race, raceFile, faction, raceID
	return ns:ResolveThemeKey(saved or "auto")
end
for _, c in ipairs({
	{ "Human", "Human", "Alliance", "human" }, { "Dwarf", "Dwarf", "Alliance", "dwarf" },
	{ "Gnome", "Gnome", "Alliance", "gnome" }, { "Night Elf", "NightElf", "Alliance", "nightelf" },
	{ "Orc", "Orc", "Horde", "orc" }, { "Tauren", "Tauren", "Horde", "tauren" },
	{ "Troll", "Troll", "Horde", "troll" }, { "Undead", "Scourge", "Horde", "forsaken" },
	{ "Skyborne", "Skyborne", "Alliance", "highorder" }, { "Skyborne", "Skyborne", "Horde", "windshapers" },
	-- Skyborne by name only (the token is undocumented), in either faction.
	{ "Skyborne", "SkyElf", "Alliance", "highorder" }, { "Shen'dorei", "Shendorei", "Horde", "windshapers" },
	{ "SKYBORNE (Windshapers)", "Unknown", "Horde", "windshapers" },
	-- What the client really returns: the race id decides, then the name.
	{ "High Order Skyborne", "Skyborne", "Alliance", "highorder", 95 },
	{ "Windshaper Skyborne", "Skyborne", "Horde", "windshapers", 96 },
	{ "Windshaper Skyborne", "Skyborne", nil, "windshapers", 96 },
	{ "High Order Skyborne", "Skyborne", "Horde", "highorder" },
	{ "Pandaren", "Pandaren", "Alliance", "human" }, { "Pandaren", "Pandaren", "Horde", "orc" },
	{ nil, nil, nil, "human" },
}) do
	local got = themeFor(c[1], c[2], c[3], nil, c[5])
	assert(got == c[4], ("%s/%s/%s should pick %s, got %s"):format(tostring(c[1]), tostring(c[2]),
		tostring(c[3]), c[4], got))
end
assert(themeFor("Dwarf", "Dwarf", "Alliance", "troll") == "troll", "a chosen theme overrides the race")
assert(themeFor("Dwarf", "Dwarf", "Alliance", "undead") == "undead", "old saved themes keep working")
assert(themeFor("Dwarf", "Dwarf", "Alliance", "skyborne") == "highorder", "skyborne follows the faction")
assert(themeFor("Orc", "Orc", "Horde", "skyborne") == "windshapers", "skyborne follows the faction")
assert(themeFor("Gnome", "Gnome", "Alliance", "gone") == "gnome", "an unknown saved theme falls back to the race")
playerRace, playerRaceFile, playerFaction = "Skyborne", "Skyborne", "Horde"
slash("theme auto")
assert(ns.themeKey == "windshapers" and ns.layout.theme == "windshapers" and ns.layout.base == "nightelf",
	"Skyborne Horde: windshapers art with night elf shapes")
assert(console.textures.minimap._tex:find("art\\windshapers\\", 1, true), "windshapers art is drawn")
playerRace, playerRaceFile, playerFaction, playerRaceID = "Orc", "Orc", "Horde", nil
slash("theme auto")

-- Every theme is complete: listed in order and in the layout, and every
-- texture the console or the top bar can load exists.
local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() end
	return f ~= nil
end
local Layout = ns.Layout
local seen = {}
for _, key in ipairs(ns.THEME_ORDER) do
	local theme = assert(ns.Themes[key], "THEME_ORDER lists unknown theme " .. key)
	seen[key] = true
	assert(tContains(Layout.THEMES, key), key .. " missing from Layout.THEMES")
	local base = Layout.BASE[key] or key
	assert(tContains({ "human", "orc", "undead", "nightelf" }, base), key .. " has no faction layout")
	for _, file in ipairs({ "panel", "edge", "edgev", "corner", "clockframe" }) do
		local path = ADDON .. "Media/" .. theme.folder .. "/" .. file .. ".tga"
		assert(exists(path), "missing " .. path)
	end
	local files, borrowed = {}, {}
	for _, s in ipairs({ 240, 250, 270 }) do
		local LL = Layout.Compute(1792, 768, { s = s, m = 10, theme = key, zoneTextPos = 1 })
		for _, piece in ipairs(LL.pieces) do
			files[piece.file] = true
			-- A theme without end caps of its own borrows its base faction's.
			if LL.endcaps.fallback and piece.key:find("^endcap_") then
				borrowed[piece.file] = true
			end
		end
	end
	for file in pairs(files) do
		local folder = borrowed[file] and base or key
		assert(file:sub(1, #folder + 1) == folder .. "\\" or file:sub(1, 6) == "other\\",
			file .. " is not in " .. folder .. "'s folder")
		local path = ADDON .. "art/" .. file:gsub("\\", "/") .. ".tga"
		assert(exists(path), "missing " .. path)
	end
end
for key in pairs(ns.Themes) do
	assert(seen[key], key .. " missing from THEME_ORDER")
end

-- The chat area's wall (filler pieces up to the corner piece) has no notch:
-- the art of the shown pieces covers every unit in between.
local function covered(L, prefix, corner, vis, cornerStart)
	local spans = {}
	for _, p in ipairs(L.pieces) do
		if p.shown and p.key:find("^" .. prefix) then
			local r = p.rect
			local mirrored = p.tc and p.tc[1] > p.tc[2]
			spans[#spans + 1] = { r.x, mirrored and (r.x + r.w) or (r.x + r.w * vis) }
		end
	end
	table.sort(spans, function(a, b) return a[1] < b[1] end)
	local c = L.byKey[corner].rect
	local goal = c.x + c.w * cornerStart
	if #spans == 0 then return true end
	local reach = spans[1][2]
	for i = 2, #spans do
		if spans[i][1] > reach + 0.01 then return false end
		reach = math.max(reach, spans[i][2])
	end
	return reach >= goal
end
for _, key in ipairs(ns.THEME_ORDER) do
	local fill = Layout.FILLER_ART[Layout.BASE[key] or key]
	for _, W in ipairs({ 1365.33, 1792, 2730.67 }) do
		for s = 240, 270 do
			local LL = Layout.Compute(W, 768, { s = s, m = 10, theme = key, zoneTextPos = 1 })
			local where = ("%s %s %d"):format(key, W, s)
			assert(covered(LL, "filler_top", "br_top", fill.top, fill.cornerTop), "notch in the chat wall: " .. where)
			assert(covered(LL, "filler_bottom", "br_bottom", fill.bottom, 0), "notch in the chat floor: " .. where)
			assert(LL.pet.y >= LL.stanceTop and LL.pet.x + 9 * LL.pet.step + LL.pet.size < LL.inventory[1].x
				and LL.pet.y + LL.pet.size <= LL.consoleTop, "pet row clear of the chat area: " .. where)
		end
	end
end
-- End caps: every theme has a pillar at each end of the console (its own,
-- or its base faction's while its art is missing), standing outside the
-- console's content; on 21:9 and 32:9 both are on screen and the whole
-- console, caps included, is centred.
do
	local O = Layout.Overlaps
	for _, key in ipairs(ns.THEME_ORDER) do
		local C = Layout.EndcapArt(key)
		assert(not C.fallback, key .. ": every theme has end caps of its own")
		for _, side in ipairs({ "left", "right" }) do
			local path = ADDON .. "art/" .. C.folder .. "/" .. C[side]:gsub("\\", "/") .. ".tga"
			assert(exists(path), "missing end cap " .. path)
		end
		for _, W in ipairs({ 1792, 1834.67, 2730.67, 1365.33 }) do
			for _, s in ipairs({ 240, 250, 260, 270 }) do
				for _, m in ipairs({ 0, 10, 150 }) do
					for _, above in ipairs({ false, true }) do
						local LL = Layout.Compute(W, 768, { s = s, m = m, theme = key, zoneTextPos = 1, chatInputAbove = above })
						local where = ("%s W %s s %d m %d"):format(key, W, s, m)
						local E = LL.endcaps
						local l, r = E.left, E.right
						assert(LL.byKey.endcap_left and LL.byKey.endcap_right_head, "end cap pieces missing: " .. where)
						assert(l.x + l.w > LL.minimapArt.x and l.x + l.w <= LL.minimapArt.x + E.overlap + 0.01
							and l.x < LL.minimapArt.x, "left cap not at the console's left end: " .. where)
						assert(r.x < LL.rightPoint and r.x >= LL.rightPoint - E.overlap - 0.01
							and r.x + r.w > LL.rightPoint, "right cap not at the console's right end: " .. where)
						local mid = LL.byKey.br_middle.rect
						assert(mid.x + mid.w >= r.x, "a gap between the right wall and its end cap: " .. where)
						for _, cap in ipairs({ E.leftShaft, E.rightShaft }) do
							for _, what in ipairs({ "minimap", "chat", "chatEdit", "cogwheel" }) do
								assert(not O(cap, LL[what]), "end cap over the " .. what .. ": " .. where)
							end
							for _, b in ipairs(LL.minimapSlots) do
								assert(not O(cap, b), "end cap over a minimap slot: " .. where)
							end
						end
						for _, cap in ipairs({ l, r }) do
							assert(cap.h > LL.s * 0.5 and cap.y == 0, "end caps stand on the floor: " .. where)
						end
						-- Each cap ends its own wall: flush with its top.
						if not LL.endcaps.real then
							assert(math.abs(r.y + r.h - LL.rightWallTop) < 0.01, "right cap not flush with the chat wall: " .. where)
						end
						-- The cogwheel: in the chat area's bottom-right corner, inside
						-- its frame, clear of the chat input box.
						local g, bg = LL.cogwheel, LL.byKey.chat_bg.rect
						assert(g.x + g.w <= LL.byKey.br_middle.rect.x and g.x + g.w > LL.chat.x + LL.chat.w - 30
							and g.y < LL.chat.y + 30 and g.y >= bg.y, "cogwheel not in the chat area's corner: " .. where)
						assert(not O(g, LL.chatEdit) and g.x + g.w <= bg.x + bg.w, "cogwheel over the input box: " .. where)
						if W >= 1792 then
							assert(l.x >= -0.01 and r.x + r.w <= W + 0.01, "end caps off screen: " .. where)
							local gapL, gapR = l.x, W - (r.x + r.w)
							assert(math.abs(gapL - gapR) <= 2, ("console with caps not centred (%.1f vs %.1f): %s"):format(gapL, gapR, where))
							assert(LL.byKey.endcap_left.shown and LL.byKey.endcap_right.shown, "end caps hidden: " .. where)
							if W >= 2730 then
								assert(math.abs(LL.byKey.chat_bg.rect.w - 2.2 * s) < 0.01, "32:9 keeps the original addon's chat width: " .. where)
							end
						else
							-- 16:9 as in the original addon: the chat area reaches the screen edge,
							-- the caps go past the edges.
							assert(LL.shift == 0 and math.abs(LL.rightPoint - W) < 0.01, "16:9 layout changed: " .. where)
						end
					end
				end
			end
		end
	end
	-- A theme listed with real end cap art uses it.
	Layout.ENDCAP_ART.orc = { left = "endcaps\\endcap_left", right = "endcaps\\endcap_right", w = 0.3, h = 0.9, overlap = 0.05, head = 0.2 }
	local LL = Layout.Compute(2730.67, 768, { s = 240, m = 10, theme = "orc", zoneTextPos = 1 })
	assert(LL.byKey.endcap_left.file == "orc\\endcaps\\endcap_left" and LL.endcaps.real, "real end cap art is preferred")
	assert(math.abs(LL.endcaps.left.w - 72) < 0.01 and math.abs(LL.endcaps.left.h - 216) < 0.01, "real caps keep their size")
	Layout.ENDCAP_ART.orc = nil
	-- In the game: the cogwheel follows the layout and stays above the chat.
	local cog = ns.modules.config.cogwheel
	at(cog, ns.layout.cogwheel.x, ns.layout.cogwheel.y, "cogwheel")
	assert(cog._strata == "HIGH", "the cogwheel stays clickable above the chat frame")
end

updateContainerFrameAnchors()
slash("status")
slash("bogus")
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_POWER_UPDATE", "PLAYER_XP_UPDATE", "BAG_UPDATE_DELAYED",
	"UPDATE_BINDINGS", "ZONE_CHANGED_NEW_AREA", "ACTIONBAR_PAGE_CHANGED", "DISPLAY_SIZE_CHANGED",
	"PLAYER_TARGET_CHANGED", "UNIT_DAMAGE", "PLAYER_MONEY", "UNIT_AURA", "UPDATE_SHAPESHIFT_FORM",
	"PLAYER_REGEN_DISABLED", "UPDATE_PENDING_MAIL", "UNIT_MODEL_CHANGED", "PLAYER_DEAD" }) do
	fire(e, "player")
	fire(e, "target")
end
flushTimers()
slash("feeds")
-- Buffs are left to Edit Mode: moving them sticks.
BuffFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
assert(BuffFrame:GetPoint(1) == "CENTER", "buffs can be moved")
-- Bars 2 and 3 are turned on once per character; Action Bar 8 is left alone.
assert(settingValues.PROXY_SHOW_ACTIONBAR_2 and settingValues.PROXY_SHOW_ACTIONBAR_3
	and settingValues.PROXY_SHOW_ACTIONBAR_8 == false, "bars 2 and 3 turned on, not bar 8")
settingValues.PROXY_SHOW_ACTIONBAR_3 = false
ns.modules.actionbars:EnableBars()
assert(settingValues.PROXY_SHOW_ACTIONBAR_3 == false, "bars are only turned on once; the player's choice stands")
-- A character whose Action Bar 8 the addon had turned on (up to 1.11) gets it
-- turned off again when its slots move.
do
	local mb = ns.modules.minimapbar
	settingValues.PROXY_SHOW_ACTIONBAR_8 = true
	ReforgedUIDB.consoleOpts.minimapBarMoved["Thrall-Forever"] = nil
	mb.addonBar8 = true
	mb:MoveFromBar8()
	assert(settingValues.PROXY_SHOW_ACTIONBAR_8 == false, "Action Bar 8 back to off")
end
-- Target display.
do
	local target, hero = ns.modules.target, ns.modules.hero
	assert(target.enabled and ReforgedUIDB.consoleOpts.targetMode == "swap", "swap is the default target display")
	assert(hero.viewUnit == "player" and not target.swap.frame:IsShown() and not target.plate.frame:IsShown(),
		"no target: the hero screen is the player's")
	-- A hostile elite targeted in combat: the hero screen swaps without
	-- touching a secure frame.
	local orig = {}
	for _, fn in ipairs({ "UnitName", "UnitLevel", "UnitClass", "UnitHealth", "UnitHealthMax", "UnitPower",
		"UnitPowerMax", "UnitPowerType", "UnitReaction", "UnitIsPlayer" }) do
		orig[fn] = _G[fn]
	end
	local reaction, totReaction = 2, 5
	local secretTarget = false
	UnitName = function(u) if u == "target" then return "Hogger" elseif u == "targettarget" then return "Thrall" end return "Thrall" end
	UnitLevel = function(u) return u == "target" and 11 or 12 end
	UnitHealth = function(u)
		if u == "target" then
			if secretTarget then return setmetatable({}, { __lt = function() error("compared a secret value") end,
				__le = function() error("compared a secret value") end, __tostring = function() return "secret" end }) end
			return 412
		end
		return 300
	end
	UnitHealthMax = function(u) return u == "target" and 666 or 450 end
	UnitPowerType = function(u) if u == "target" then return 1, "RAGE" end return 0, "MANA" end
	UnitPower = function(u) return u == "target" and 30 or 120 end
	UnitPowerMax = function(u) return u == "target" and 100 or 200 end
	UnitReaction = function(u) if u == "targettarget" then return totReaction end return reaction end
	PowerBarColor.RAGE = { r = 1, g = 0, b = 0 }

	local guarded = {}
	for _, m in ipairs({ "SetPoint", "ClearAllPoints", "Show", "Hide", "SetShown", "SetAttribute", "SetSize", "SetParent" }) do
		guarded[m] = methods[m]
		methods[m] = function(self, ...)
			assert(not (inCombat and self._kind == "secure"), m .. " on a secure frame in combat")
			return guarded[m](self, ...)
		end
	end
	inCombat = true
	hasTarget = true
	fire("PLAYER_TARGET_CHANGED")
	assert(hero.viewUnit == "target", "swap: the hero screen shows the target")
	assert(hero.xp.name._text == "Hogger" and hero.xp.level._text == "Level 11 |cffffd100Elite|r Beast", "swap: target name and level")
	assert(target.swap.tag:IsShown() and target.swap.tag.text._text == "Elite", "swap: the elite tag over the portrait")
	assert(not hero.xp.bar:IsShown() and not hero.stats[1]:IsShown() and not hero.stats[4]:IsShown(),
		"swap: no experience fill and no stat icons")
	assert(target.swap.frame:IsShown() and target.swap.health._value == 412 and target.swap.health.text._text == "412 / 666",
		"swap: target health with numbers")
	assert(target.swap.power.text._text == "30 / 100" and target.swap.power._color[1] == 1, "swap: target rage")
	assert(hero.health._value == 300 and hero.health.text._text == "300 / 450", "the small bars stay the player's")
	for i, pip in ipairs(target.swap.combo) do
		assert(pip.gem:IsShown() == (i <= 3) and pip.socket:IsShown(), "three combo points lit")
	end
	-- Secret health: still reaches the bar, never compared, text left empty.
	secretTarget = true
	fire("UNIT_HEALTH", "target")
	assert(type(target.swap.health._value) == "table", "secret health reaches the bar")
	-- Incoming heals: the player's own and everyone else's, after the fill.
	do
		local heals = target.swap.health.heals
		assert(heals and heals.top and target.swap.health.text:GetParent() == heals.top,
			"heals under the health text")
		assert(select(2, heals.mine:GetPoint(1)) == target.swap.health:GetStatusBarTexture()
			and select(2, heals.others:GetPoint(1)) == heals.mine:GetStatusBarTexture(), "heals chain on from the fill")
		local all, mine = 80, 30
		UnitGetIncomingHeals = function(u, healer)
			if u ~= "target" then return nil end
			return healer and mine or all
		end
		fire("UNIT_HEAL_PREDICTION", "target")
		assert(heals.mine._value == 30 and heals.others._value == 50 and heals.mine._max == 666, "incoming heals split")
		mine = 120
		fire("UNIT_HEAL_PREDICTION", "target")
		assert(heals.mine._value == 80 and heals.others._value == 0, "own heals never above all heals")
		-- Secret amounts (in instances): reach the bar, never compared.
		local secretHeal = newproxy(true)
		getmetatable(secretHeal).__lt = function() error("compared a secret heal") end
		getmetatable(secretHeal).__le = getmetatable(secretHeal).__lt
		getmetatable(secretHeal).__eq = getmetatable(secretHeal).__lt
		local oldIsSecret = issecretvalue
		issecretvalue = function(v) return v == secretHeal or oldIsSecret(v) end
		UnitGetIncomingHeals = function() return secretHeal end
		fire("UNIT_HEAL_PREDICTION", "target")
		assert(heals.others._value == secretHeal and heals.mine._value == 0, "secret heals reach the bar")
		-- The client's calculator, when it has one.
		local calc = { GetIncomingHeals = function() return 70, 40, 30, false end }
		CreateUnitHealPredictionCalculator = function() return calc end
		UnitGetDetailedHealPrediction = function(u, healer, c) assert(c == calc and healer == "player") end
		fire("UNIT_HEAL_PREDICTION", "target")
		assert(heals.others._value == secretHeal, "calculator looked up once, at the first update")
		issecretvalue, UnitGetIncomingHeals = oldIsSecret, nil
		CreateUnitHealPredictionCalculator, UnitGetDetailedHealPrediction = nil, nil
		fire("UNIT_HEAL_PREDICTION", "target")
		assert(heals.mine._value == 0 and heals.others._value == 0, "no heal prediction API: empty")
		assert(ns.modules.hero.health.heals and ns.modules.pet.button.health.heals
			and target.plate.health.heals and target.tot.health.heals, "every health bar has heals")
	end
	secretTarget = false
	fire("UNIT_HEALTH", "target")
	-- Secret name (in instances): shown as it is, never compared or measured.
	do
		local secretName = newproxy(true)
		local mt = getmetatable(secretName)
		mt.__len = function() error("measured a secret name") end
		mt.__tostring = function() return "secret name" end
		local oldFull, oldIsSecret = GetUnitName, issecretvalue
		GetUnitName = function(u, full) if u == "target" then return secretName end return oldFull(u, full) end
		issecretvalue = function(v) return v == secretName or oldIsSecret(v) end
		-- The string's width turns secret along with its text.
		local oldWidth = methods.GetWidth
		methods.GetWidth = function(self, ...)
			assert(self._text ~= secretName, "read the width of a secret name")
			return oldWidth(self, ...)
		end
		fire("UNIT_NAME_UPDATE", "target")
		assert(hero.xp.name._text == secretName, "a secret target name is shown untouched")
		GetUnitName, issecretvalue, methods.GetWidth = oldFull, oldIsSecret, oldWidth
		fire("UNIT_NAME_UPDATE", "target")
		assert(hero.xp.name._text == "Hogger", "the plain name comes back")
	end
	-- The target's cast bar. Cast info of any unit but you and your pet is
	-- secret: name, start and end reach the bar untouched, never compared or
	-- added up; the stop events hide it.
	do
		local function secretValue()
			local v = newproxy(true)
			local mt = getmetatable(v)
			mt.__lt = function() error("compared a secret cast value") end
			mt.__le, mt.__eq = mt.__lt, mt.__lt
			mt.__add = function() error("did sums with a secret cast value") end
			mt.__sub, mt.__mul, mt.__div, mt.__unm = mt.__add, mt.__add, mt.__add, mt.__add
			return v
		end
		local sName, sStart, sEnd = secretValue(), secretValue(), secretValue()
		local oldCast, oldChannel = UnitCastingInfo, UnitChannelInfo
		secret = true
		local casting = true
		UnitCastingInfo = function(u)
			if u == "target" and casting then return sName, sName, 136, sStart, sEnd end
		end
		local cast = target:View().cast
		assert(not cast:IsShown(), "no cast, no cast bar")
		fire("UNIT_SPELLCAST_START", "target")
		assert(cast:IsShown() and cast.text._text == sName, "a secret cast shows, its name untouched")
		assert(cast._min == sStart and cast._max == sEnd and cast._value == 100000, "the bar runs from start to end")
		cast._scripts.OnUpdate(cast)
		assert(cast:IsShown() and cast._value == 100000 and not cast._reverse, "a secret end is never waited for")
		fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
		assert(cast:IsShown(), "a channel's stop leaves a cast")
		casting = false
		fire("UNIT_SPELLCAST_STOP", "target")
		assert(not cast:IsShown(), "the cast's stop hides it")
		-- A plain channel drains, and ends by itself at its end.
		secret, UnitCastingInfo = false, function() return nil end
		UnitChannelInfo = function(u)
			if u == "target" then return "Drain Life", "Drain Life", 136, 99000, 103000 end
		end
		fire("UNIT_SPELLCAST_CHANNEL_START", "target")
		assert(cast:IsShown() and cast.text._text == "Drain Life" and cast._reverse, "a channel drains")
		fire("UNIT_SPELLCAST_FAILED", "target")
		assert(cast:IsShown(), "a failed cast leaves a channel")
		local oldTime = GetTime
		GetTime = function() return 104 end
		cast._scripts.OnUpdate(cast)
		assert(not cast:IsShown(), "a channel past its end goes")
		GetTime = oldTime
		-- An API that errors hides it rather than breaking.
		UnitChannelInfo = function() error("cast info refused") end
		fire("UNIT_SPELLCAST_CHANNEL_START", "target")
		assert(not cast:IsShown(), "unreadable cast info: no bar")
		UnitCastingInfo, UnitChannelInfo = oldCast, oldChannel
	end
	-- Reaction colours: hostile red, neutral yellow, friendly green.
	local function nameRGB() local fs = hero.xp.name; return fs._r, fs._g, fs._b end
	local oldColor = methods.SetTextColor
	methods.SetTextColor = function(self, r, g, b) oldColor(self, r, g, b); self._r, self._g, self._b = r, g, b end
	for r, want in pairs({ [2] = "hostile", [4] = "neutral", [6] = "friendly" }) do
		reaction = r
		fire("UNIT_FACTION", "target")
		local cr, cg = nameRGB()
		assert(target.ReactionKind("target") == want, "reaction " .. r)
		assert((want == "hostile" and cr == 1 and cg < 0.5) or (want == "neutral" and cr == 1 and cg > 0.8)
			or (want == "friendly" and cr < 0.5 and cg == 1), "name colour for " .. want)
	end
	reaction = 2
	-- Target of target: its gem says who it is.
	totIsPlayer = true
	target:UpdateToT()
	assert(target.tot.kind == "player" and target.tot.reaction.stone._vertex[3] == 1, "ToT: your gem is blue")
	local gem = target.tot.reaction
	assert(gem.swords:IsShown() and not gem.stone:IsShown(), "an enemy targeting you shows crossed swords")
	reaction = 6
	target:UpdateToT()
	assert(not gem.swords:IsShown() and gem.stone:IsShown(), "a friend targeting you shows the blue gem")
	reaction = 2
	totIsPlayer = false
	target:UpdateToT()
	assert(not gem.swords:IsShown(), "no swords when it isn't you")
	for r, want in pairs({ [2] = "hostile", [6] = "friendly" }) do
		totReaction = r
		target:UpdateToT()
		assert(target.tot.kind == want, "ToT tint " .. want)
	end
	assert(target.tot.reaction.stone._vertex[2] == 1 and target.tot.reaction.stone._vertex[1] < 0.5, "a friendly ToT's gem is green")
	-- In instances "is it me" can be secret: never tested, tinted by reaction.
	do
		local secretBool = {}
		local oldIsUnit = UnitIsUnit
		UnitIsUnit = function(a, b) if a == "targettarget" then return secretBool end return oldIsUnit(a, b) end
		secret = true
		target:UpdateToT()
		secret = false
		assert(target.tot.kind == "friendly", "a secret ToT is tinted by reaction")
		UnitIsUnit = oldIsUnit
	end
	-- Clearing the target restores the player, in combat.
	hasTarget = false
	fire("PLAYER_TARGET_CHANGED")
	assert(hero.viewUnit == "player" and hero.xp.name._text == "Thrall Son of Durotan" and hero.xp.level._text == "Level 12 Shaman",
		"clearing the target restores the player's name and level")
	assert(hero.xp.name._r == 1 and hero.xp.name._g == 1, "the player's name colour is restored")
	assert(hero.stats[1]:IsShown() and hero.stats[4]:IsShown() and hero.xp.bar:IsShown(), "stat icons come back")
	assert(not target.swap.frame:IsShown(), "the target bars go away")
	-- Switching the mode in combat: visuals now, the click area after combat.
	SlashCmdList.REFORGEDUI("target plate")
	assert(ReforgedUIDB.consoleOpts.targetMode == "plate", "/rui target plate")
	hasTarget = true
	fire("PLAYER_TARGET_CHANGED")
	assert(hero.viewUnit == "player" and hero.xp.name._text == "Thrall Son of Durotan", "plate mode: the hero screen stays the player's")
	assert(target.plate.frame:IsShown() and not target.swap.frame:IsShown(), "plate mode shows the plate")
	local pl = target.plate
	assert(pl.name._text == "Hogger" and pl.info._text == "Level 11 |cffffd100Elite|r Beast", "plate: name and level line")
	assert(pl.tag:IsShown() and pl.tag.text._text == "Elite", "plate: the elite tag over the portrait")
	-- A rare one gets a silver tag, a rare elite a silver one with a gold edge,
	-- and a normal one none.
	do
		local oldClass = UnitClassification
		local class = "rare"
		UnitClassification = function() return class end
		fire("UNIT_CLASSIFICATION_CHANGED", "target")
		assert(pl.tag:IsShown() and pl.tag.text._text == "Rare" and pl.info._text:find("Rare|r", 1, true),
			"plate: a rare target is marked")
		class = "rareelite"
		fire("UNIT_CLASSIFICATION_CHANGED", "target")
		assert(pl.tag.text._text == "Rare Elite" and pl.tag:GetWidth() > 0, "plate: a rare elite is marked")
		class = "normal"
		fire("UNIT_CLASSIFICATION_CHANGED", "target")
		assert(not pl.tag:IsShown() and pl.info._text == "Level 11 Beast", "plate: a normal target has no tag")
		UnitClassification = oldClass
		fire("UNIT_CLASSIFICATION_CHANGED", "target")
	end
	assert(pl.name == pl.plate.name and pl.info == pl.plate.level and not pl.plate.bar:IsShown(),
		"plate: the hero's level plate, without an experience fill")
	assert(pl.healthText._text == "412 / 666" and pl.powerText._text == "30 / 100" and pl.power:IsShown(),
		"plate: health and power numbers")
	-- In instances an enemy's 3D model can stay empty: its flat portrait shows
	-- behind it until the model has one.
	do
		local fileID
		methods.GetModelFileID = function() return fileID end
		target:UpdateModel()
		assert(pl.flatPortrait:IsShown(), "no model: the flat portrait shows")
		fileID = 123
		target:UpdateModel()
		assert(not pl.flatPortrait:IsShown(), "a model hides the flat portrait")
		methods.GetModelFileID = nil
	end
	-- A secret level reads "??", the rest of the line still shows.
	do
		local oldLevel = UnitLevel
		local secretLevel = setmetatable({}, { __lt = function() error("compared a secret value") end,
			__le = function() error("compared a secret value") end })
		UnitLevel = function(u) if u == "target" then return secretLevel end return oldLevel(u) end
		secret = true
		fire("UNIT_LEVEL", "target")
		secret = false
		-- (Everything reads as secret here, the classification too: it's left out.)
		assert(pl.info._text == "Level ?? Beast", "secret level: " .. tostring(pl.info._text))
		UnitLevel = oldLevel
		fire("UNIT_LEVEL", "target")
	end
	-- Long numbers are abbreviated and shrink to fit: never cut off.
	local oldH, oldHM = UnitHealth, UnitHealthMax
	UnitHealth = function(u) return u == "target" and 123456 or 300 end
	UnitHealthMax = function(u) return u == "target" and 123456 or 450 end
	fire("UNIT_HEALTH", "target")
	local ht = pl.healthText
	assert(ht._text == "123k / 123k" and ht:GetStringWidth() <= ht:GetWidth() and not ht._text:find("%.%.%."),
		"plate: a long health value fits its bar")
	UnitHealth = function(u) return u == "target" and 1234567 or 300 end
	UnitHealthMax = function(u) return u == "target" and 12345678 or 450 end
	fire("UNIT_HEALTH", "target")
	assert(ht._text == "1.2m / 12.3m" and ht:GetStringWidth() <= ht:GetWidth(), "plate: millions fit too")
	UnitHealth, UnitHealthMax = oldH, oldHM
	fire("UNIT_HEALTH", "target")
	-- No power: its slot stays empty; secret power counts as some.
	local oldPM = UnitPowerMax
	UnitPowerMax = function(u) return u == "target" and 0 or 200 end
	fire("UNIT_MAXPOWER", "target")
	assert(not pl.power:IsShown(), "plate: no power bar for a unit without power")
	secret = true
	fire("UNIT_MAXPOWER", "target")
	assert(pl.power:IsShown(), "plate: secret power keeps the bar")
	secret = false
	UnitPowerMax = oldPM
	fire("UNIT_MAXPOWER", "target")
	assert(pl.power:IsShown(), "plate: the power bar comes back")
	-- The target bar: off by default, turned on in combat (not secure), with
	-- the target's name, level, health and power; click-through until Shift
	-- is held out of combat or Edit Mode is open, then dragged anywhere.
	do
		local bar = target.bar
		assert(bar and not bar.frame:IsShown(), "the target bar is off by default")
		assert(bar.frame._kind ~= "secure" and bar.frame:GetParent() == UIParent, "the target bar is a plain frame")
		SlashCmdList.REFORGEDUI("targetbar on")
		assert(ReforgedUIDB.consoleOpts.targetBar and bar.frame:IsShown(), "/rui targetbar on shows it, in combat")
		assert(bar.name._text == "Hogger" and bar.level._text == "11|cffffd100+|r" and bar.tag:IsShown(),
			"target bar: name, level and elite")
		assert(bar.health._value == 412 and bar.health.text._text == "412 / 666", "target bar: health")
		assert(bar.health._color[1] < 0.5 and bar.health._color[2] > 0.5, "target bar: green above the HP warning")
		local oldH = UnitHealth
		UnitHealth = function(u) return u == "target" and 100 or 300 end
		fire("UNIT_HEALTH", "target")
		assert(bar.health._color[1] > 0.5 and bar.health._color[2] < 0.5, "target bar: red at the HP warning")
		UnitHealth = oldH
		fire("UNIT_HEALTH", "target")
		assert(bar.power.text._text == "30 / 100" and bar.power._color[1] == 1 and bar.power:IsShown(), "target bar: rage")
		-- The target's cast hangs under it, beside the console's.
		local oldCast = UnitCastingInfo
		UnitCastingInfo = function(u) if u == "target" then return "Fireball", "Fireball", 135, 99500, 102500 end end
		fire("UNIT_SPELLCAST_START", "target")
		assert(bar.cast:IsShown() and bar.cast.text._text == "Fireball" and bar.cast:GetParent() == bar.frame,
			"target bar: the target's cast")
		assert(target:View().cast:IsShown(), "the console shows it too")
		UnitCastingInfo = oldCast
		fire("UNIT_SPELLCAST_STOP", "target")
		assert(not bar.cast:IsShown() and not target:View().cast:IsShown(), "target bar: the cast ends")
		assert(bar.name._fontObject or bar.name._font, "target bar text goes through our font")
		assert(not bar.frame._mouse, "the target bar is click-through")
		local p0 = bar.frame._points[1]
		assert(p0[1] == "CENTER" and p0[2] == UIParent and p0[5] < 0, "the target bar starts below the screen's centre")
		-- Secret health and level: still on the bar, never compared.
		secretTarget = true
		fire("UNIT_HEALTH", "target")
		assert(type(bar.health._value) == "table" and bar.health._color[2] > 0.5,
			"target bar: secret health reaches the bar, never compared")
		secretTarget = false
		fire("UNIT_HEALTH", "target")
		local oldLevel = UnitLevel
		local secretLevel = setmetatable({}, { __lt = function() error("compared a secret value") end,
			__le = function() error("compared a secret value") end })
		UnitLevel = function(u) if u == "target" then return secretLevel end return oldLevel(u) end
		secret = true
		fire("UNIT_LEVEL", "target")
		secret = false
		assert(bar.level._text == "??" and not bar.tag:IsShown(), "target bar: a secret level reads ?? (and the all-secret classification is left out)")
		UnitLevel = oldLevel
		fire("UNIT_LEVEL", "target")
		-- Shift makes it draggable; its new place is saved from the centre.
		local shift = false
		IsShiftKeyDown = function() return shift end
		shift = true
		fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		assert(not bar.frame._mouse, "in combat Shift leaves the target bar click-through")
		inCombat = false
		fire("PLAYER_REGEN_ENABLED")
		assert(bar.frame._mouse and not bar.highlight:IsShown(), "Shift out of combat makes the target bar draggable")
		bar.frame.GetCenter = function() return screenW / 2 + 40, screenH / 2 + 100 end
		UIParent.GetCenter = function() return screenW / 2, screenH / 2 end
		bar.frame._scripts.OnDragStart(bar.frame)
		shift = false
		fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
		assert(bar.frame._mouse, "letting go of Shift mid-drag keeps the drag")
		inCombat = true
		fire("PLAYER_REGEN_DISABLED")
		assert(bar.frame._mouse, "nor does combat end a drag")
		bar.frame._scripts.OnDragStop(bar.frame)
		fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
		assert(not bar.frame._mouse, "click-through again after the drag")
		local spot = ReforgedUIDB.consoleOpts.targetBarPos
		assert(spot and spot.x == 40 and spot.y == 100, "the dragged place is saved")
		local p1 = bar.frame._points[1]
		assert(p1[1] == "CENTER" and p1[4] == 40 and p1[5] == 100, "the target bar stays where it was dragged")
		-- Its place is its own: the Edit Mode target frame doesn't follow.
		assert(ns.layout.targetAuras.plate and not ns.layout.targetBar, "the target bar stays out of the layout")
		-- No target: hidden, unless Edit Mode is open (a stand-in to place).
		hasTarget = false
		fire("PLAYER_TARGET_CHANGED")
		assert(not bar.frame:IsShown(), "no target, no target bar")
		EditModeManagerFrame._hooks.OnShow()
		assert(bar.frame:IsShown() and bar.name._text == "Target" and bar.frame._mouse and bar.highlight:IsShown(),
			"Edit Mode shows a movable stand-in")
		EditModeManagerFrame._hooks.OnHide()
		assert(not bar.frame:IsShown() and not bar.frame._mouse, "closing Edit Mode hides it again")
		-- Edit Mode closed mid-drag: the drag ends with the bar, never stuck.
		EditModeManagerFrame._hooks.OnShow()
		bar.frame._scripts.OnDragStart(bar.frame)
		EditModeManagerFrame._hooks.OnHide()
		bar.frame._scripts.OnHide(bar.frame) -- the stubs don't fire OnHide
		assert(not bar.frame.dragging and not bar.frame._mouse, "hidden mid-drag, the drag ends")
		hasTarget = true
		fire("PLAYER_TARGET_CHANGED")
		assert(bar.frame:IsShown() and bar.name._text == "Hogger", "back with the target")
		SlashCmdList.REFORGEDUI("targetbar reset")
		local p2 = bar.frame._points[1]
		assert(not ReforgedUIDB.consoleOpts.targetBarPos and p2[4] == p0[4] and p2[5] == p0[5], "/rui targetbar reset")
		SlashCmdList.REFORGEDUI("targetbar off")
		assert(not bar.frame:IsShown() and not ReforgedUIDB.consoleOpts.targetBar, "/rui targetbar off")
		-- The options menu's checkbox does the same.
		local box
		for _, cb in ipairs(config.checks) do
			if cb.key == "targetBar" then box = cb end
		end
		assert(box, "the options menu has a target bar checkbox")
		box._checked = true
		box._scripts.OnClick(box)
		assert(ReforgedUIDB.consoleOpts.targetBar and bar.frame:IsShown(), "the checkbox turns the target bar on")
		box._checked = false
		box._scripts.OnClick(box)
		assert(not bar.frame:IsShown(), "and off")
		assert(box._enabled and box.label._textColor[1] == 1, "the checkbox is live while the target module is on")
		target.enabled = false
		config:Refresh()
		assert(not box._enabled and box.label._textColor[1] < 1, "and greyed out while it is off")
		target.enabled = true
		config:Refresh()
		-- The target of target bar: the same window for the target's target,
		-- placed on its own, right of the target bar; both share a size.
		local tb = target.totBar
		assert(tb and tb.frame ~= bar.frame and not tb.frame:IsShown() and not tb.cast,
			"the target of target bar is off by default, without a cast bar")
		assert(tb.frame._kind ~= "secure" and tb.frame:GetParent() == UIParent, "it is a plain frame too")
		SlashCmdList.REFORGEDUI("totbar on")
		assert(ReforgedUIDB.consoleOpts.totBar and tb.frame:IsShown() and tb.name._text == "Thrall",
			"/rui totbar on shows the target's target")
		assert(tb.health.text._text and tb.health.text._text ~= "", "target of target bar: health")
		assert(not bar.frame:IsShown() and not tb.frame._mouse, "the target bar stays off; click-through")
		local t0 = tb.frame._points[1]
		assert(t0[1] == "CENTER" and t0[2] == UIParent and t0[4] > 0 and t0[5] == p0[5],
			"it starts right of the target bar's place")
		-- The target loses its target: hidden; and back.
		local oldExists = UnitExists
		UnitExists = function(u) if u == "targettarget" then return false end return oldExists(u) end
		fire("UNIT_TARGET", "target")
		assert(not tb.frame:IsShown(), "no target of target, no bar")
		UnitExists = oldExists
		fire("UNIT_TARGET", "target")
		assert(tb.frame:IsShown(), "back with the target's target")
		-- Moved in Edit Mode, its own place.
		EditModeManagerFrame._hooks.OnShow()
		assert(tb.frame._mouse and tb.highlight:IsShown(), "movable in Edit Mode")
		UIParent.GetCenter = function() return screenW / 2, screenH / 2 end
		tb.frame.GetCenter = function() return screenW / 2 + 300, screenH / 2 - 200 end
		tb.frame._scripts.OnDragStart(tb.frame)
		tb.frame._scripts.OnDragStop(tb.frame)
		EditModeManagerFrame._hooks.OnHide()
		local ts = ReforgedUIDB.consoleOpts.totBarPos
		assert(ts and ts.x == 300 and ts.y == -200 and tb.frame._points[1][4] == 300, "its dragged place is saved")
		assert(ReforgedUIDB.consoleOpts.targetBarPos == false, "the target bar's place is left alone")
		-- Bigger, both, each kept in its place on the screen.
		SlashCmdList.REFORGEDUI("barsize 150")
		assert(ReforgedUIDB.consoleOpts.targetBarSize == 150 and tb.frame._scale == 1.5 and bar.frame._scale == 1.5,
			"/rui barsize scales both bars")
		local t1 = tb.frame._points[1]
		assert(t1[4] == 200 and math.abs(t1[5] + 200 / 1.5) < 0.01, "a bigger bar keeps its place")
		SlashCmdList.REFORGEDUI("barsize 999")
		assert(ReforgedUIDB.consoleOpts.targetBarSize == 200 and tb.frame._scale == 2, "at most 200 %")
		local slider
		for _, sl in ipairs(config.sliders) do
			if sl.key == "targetBarSize" then slider = sl end
		end
		assert(slider, "the options menu has a target bar size slider")
		slider._scripts.OnValueChanged(slider, 100)
		assert(ReforgedUIDB.consoleOpts.targetBarSize == 100 and tb.frame._scale == 1, "the slider sets it")
		SlashCmdList.REFORGEDUI("totbar reset")
		assert(not ReforgedUIDB.consoleOpts.totBarPos and tb.frame._points[1][4] == t0[4], "/rui totbar reset")
		local totBox
		for _, cb in ipairs(config.checks) do
			if cb.key == "totBar" then totBox = cb end
		end
		assert(totBox, "the options menu has a target of target bar checkbox")
		totBox._checked = false
		totBox._scripts.OnClick(totBox)
		assert(not tb.frame:IsShown() and not ReforgedUIDB.consoleOpts.totBar, "the checkbox turns it off")
		SlashCmdList.REFORGEDUI("totbar on")
		SlashCmdList.REFORGEDUI("totbar off")
		assert(not tb.frame:IsShown(), "/rui totbar off")
		tb.frame.GetCenter = nil
		IsShiftKeyDown = nil
		bar.frame.GetCenter, UIParent.GetCenter = nil, nil
	end
	methods.SetTextColor = oldColor
	inCombat = false
	for m, fn in pairs(guarded) do methods[m] = fn end
	fire("PLAYER_REGEN_ENABLED")
	-- The plate stands on the wall above the stats panel, left of the stance row.
	local LL, P = ns.layout, ns.layout.targetPlate
	local function R(r) return r.x + r.w end
	local function T(r) return r.y + r.h end
	local function inside(a, b)
		return a.x >= b.x - 0.01 and a.y >= b.y - 0.01 and R(a) <= R(b) + 0.01 and T(a) <= T(b) + 0.01
	end
	assert(math.abs(P.frame.y - (LL.heroWallTop - 3)) < 0.01, "the plate stands on the wall")
	assert(P.frame.x >= R(LL.tot.frame) and R(P.frame) <= LL.stance.x, "the plate sits between the ToT icon and the stance row")
	local TA = ns.Layout.TARGET_ART
	assert(P.file == LL.theme .. "\\" .. (TA.themes[LL.theme] and TA.file or TA.genFile),
		"the plate uses the theme's own plate art (real where there is some)")
	-- A miniature hero screen: bars under the portrait, info window beside it.
	assert(inside(P.portrait, P.frame) and inside(P.info, P.frame), "plate windows inside the plate")
	assert(T(P.health) <= P.portrait.y + 0.01 and T(P.power) <= P.health.y + 0.01, "health and power under the portrait")
	assert(P.health.x < R(P.portrait) and R(P.health) > P.portrait.x, "the bars stand in the arch's foot")
	assert(P.info.x >= R(P.portrait), "the info window is right of the portrait")
	assert(inside(P.name, P.info) and inside(P.level.left, P.info) and inside(P.level.right, P.info)
		and inside(P.cast, P.info), "name, level plate and cast bar inside the info window")
	assert(P.combo.y > T(P.cast) and P.combo.y + P.combo.size < P.level.left.y, "combo points between level plate and cast bar")
	assert(P.level.width < LL.xp.width * 0.8, "the level plate is a smaller copy of the hero's")
	local p = ReforgedUITargetButton._points[1]
	assert(p and p[2] == ns.root and math.abs(p[4] - P.frame.x) < 0.01, "the target button moved onto the plate after combat")
	-- Swap mode puts the target button over the hero's portrait.
	SlashCmdList.REFORGEDUI("target swap")
	p = ReforgedUITargetButton._points[1]
	assert(math.abs(p[4] - LL.portrait.x) < 0.01 and ReforgedUITargetButton:GetFrameLevel() > 1, "target button over the portrait")
	assert(ReforgedUITargetButton:GetAttribute("unit") == "target" and ReforgedUIPortraitButton:GetAttribute("unit") == "player"
		and ReforgedUITargetTarget:GetAttribute("unit") == "targettarget", "secure unit buttons")
	assert(hero.viewUnit == "target", "back to swap with a target")
	-- The setting persists and the options menu shows it.
	assert(ReforgedUIDB.consoleOpts.targetMode == "swap", "the target mode is saved")
	config:Refresh()
	assert(not config.targetButtons[1]._enabled and config.targetButtons[2]._enabled, "options show the target mode")
	config.targetButtons[2]._scripts.OnClick()
	assert(ReforgedUIDB.consoleOpts.targetMode == "plate", "the options button switches to the plate")
	config.targetButtons[1]._scripts.OnClick()
	-- Every theme's plate art exists, with its windows, beside the stance row.
	for _, key in ipairs(ns.THEME_ORDER) do
		for _, sc in ipairs({ 240, 270 }) do
			local LT = Layout.Compute(1365.33, 768, { s = sc, m = 10, theme = key, zoneTextPos = 1 })
			local PL = LT.targetPlate
			assert(exists(ADDON .. "art/" .. PL.file:gsub("\\", "/") .. ".tga"), "missing plate art " .. PL.file)
			assert(PL.portrait and PL.health and PL.power and PL.info, "plate windows for " .. key)
			assert(PL.frame.x >= LT.tot.frame.x + LT.tot.frame.w and PL.frame.x + PL.frame.w <= LT.stance.x,
				"plate fits beside the stance row for " .. key)
		end
	end
	hasTarget = false
	fire("PLAYER_TARGET_CHANGED")
	for fn, f in pairs(orig) do _G[fn] = f end
	checkAnchors()
end
-- The micro menu's leftovers are invisible; Housing is left out of the bar.
assert(microBorder._alpha == 0, "the micro menu's border is hidden")
microBorder:SetAlpha(1)
assert(microBorder._alpha == 0, "the micro menu's border stays hidden")
assert(microStray._alpha == 0, "stray frames in the micro menu are hidden")
assert(HousingMicroButton._alpha == 0 and #HousingMicroButton._points == 0, "Housing is hidden, not placed")
assert(PlayerSpellsMicroButton._alpha == 0, "only one talent button: the newer one is hidden")
assert(AchievementMicroButton._alpha == 0, "Legacy replaces the achievement button")
local hasTalent = false
for _, b in ipairs(ns.microButtons) do hasTalent = hasTalent or b == TalentMicroButton end
assert(hasTalent, "the classic talent button is in the bar")
for _, b in ipairs(ns.microButtons) do
	assert(b ~= HousingMicroButton, "Housing is not in the bar")
	assert(b._alpha ~= 0, b:GetName() .. " stays visible")
end
-- The damage meter skin: every window, bar and breakdown is dressed in the
-- theme, and follows a change of theme.
do
	local w = DamageMeterSessionWindow1
	local c = w.MinimizeContainer
	local function checkSkin(key)
		local rail = "ReforgedUI\\Media\\Trim\\" .. key .. "\\rail"
		for _, e in ipairs({ c.ScrollBox._frames[1], dmEarlyEntry, c.LocalPlayerEntry, c.SourceWindow.ScrollBox._frames[1] }) do
			assert(e.StatusBar:GetStatusBarTexture()._tex == "Interface\\TargetingFrame\\UI-StatusBar", "bar texture")
			assert(e.StatusBar.Name._font == ReforgedUI.FONT, "bar font")
			local found
			for _, f in ipairs(allFrames) do
				if rawget(f, "_parent") == e and f._tex and f._tex:find(rail, 1, true) then found = true end
			end
			assert(found, "every bar has the " .. key .. " rail")
		end
		assert(w.Header._color and c.Background._color and c.SourceWindow.Background._color, "insets are coloured")
		local corners = 0
		local corner = "ReforgedUI\\Media\\Trim\\" .. key .. "\\join"
		for _, f in ipairs(allFrames) do
			local under = rawget(f, "_parent")
			while under and under ~= w do under = rawget(under, "_parent") end
			if under and f._kind == "texture" and type(f._tex) == "string" and f._tex:sub(-#corner) == corner then
				corners = corners + 1
			end
		end
		assert(corners == 8, "four corners around the window and four around its breakdown, got " .. corners)
	end
	checkSkin(ns.themeKey)
	-- Bars made later carry the hooked mixin: styling one skins it.
	local late = newEntry(c.ScrollBox)
	late:UpdateStyle()
	assert(late.StatusBar.Name._font == ReforgedUI.FONT, "bars made later are skinned when styled")
	assert(dmEarlyEntry._styled == nil, "the skin only post-hooks")
	dmEarlyEntry:UpdateStyle()
	assert(dmEarlyEntry._styled == 1, "Blizzard's own UpdateStyle still runs once")
	slash("theme troll")
	checkSkin("troll")
	w:SetMinimized(true)
	slash("theme auto")
	checkSkin(ns.themeKey)

	-- Every theme has its frame art.
	for _, key in ipairs(ns.THEME_ORDER) do
		for _, file in ipairs({ "rail", "join", "frame", "beam", "post" }) do
			local path = ADDON .. "Media/Trim/" .. key .. "/" .. file .. ".tga"
			assert(exists(path), "missing " .. path)
		end
	end
end
-- The bags skin: Blizzard's bag windows and the BetterBags theme wear the
-- theme's frame and follow a change of theme.
do
	local function corners(root, key)
		local n, corner = 0, "ReforgedUI\\Media\\Trim\\" .. key .. "\\join"
		for _, f in ipairs(allFrames) do
			local under = rawget(f, "_parent")
			while under and under ~= root do under = rawget(under, "_parent") end
			if under and f._kind == "texture" and type(f._tex) == "string" and f._tex:sub(-#corner) == corner then
				n = n + 1
			end
		end
		return n
	end
	local function hasRail(root, key)
		local rail = "ReforgedUI\\Media\\Trim\\" .. key .. "\\rail"
		for _, f in ipairs(allFrames) do
			if rawget(f, "_parent") == root and type(f._tex) == "string" and f._tex:sub(-#rail) == rail then return true end
		end
	end
	local function checkBags(key)
		for _, w in ipairs({ ContainerFrame1, ContainerFrame2, ContainerFrameCombinedBags }) do
			assert(w.NineSlice._alpha == 0 and w.Bg._alpha == 0, "Blizzard's border and background are invisible")
			assert(w.PortraitContainer.portrait._alpha == 0, "the round portrait gives way")
			assert(corners(w, key) == 4, "four " .. key .. " corners around " .. w:GetName())
			assert(hasRail(w, key), "the " .. key .. " rail under the title")
			assert(w.TitleContainer.TitleText._font == ReforgedUI.FONT, "title font")
		end
	end
	checkBags(ns.themeKey)
	-- The bag's own icon, square, from its inventory slot.
	local oldTexture = GetInventoryItemTexture
	GetInventoryItemTexture = function(_, slot) if slot == 20 then return "Interface\\Icons\\INV_Misc_Bag_10" end end
	ContainerFrame2:UpdateMiscellaneousFrames()
	assert(ContainerFrame2._misc == 1, "Blizzard's own update still runs once")
	local found
	for _, f in ipairs(allFrames) do
		if rawget(f, "_parent") == ContainerFrame2.PortraitContainer and f._tex == "Interface\\Icons\\INV_Misc_Bag_10" then found = true end
	end
	assert(found, "bag 1 shows its own icon")
	GetInventoryItemTexture = oldTexture

	-- BetterBags: every window kind in the theme's trim, its art and colours
	-- read from the Reforged UI theme each time BetterBags applies it.
	local function checkBB(key)
		local r = resolveTheme(sonata.themes.ReforgedUI)
		local frame = "ReforgedUI\\Media\\Trim\\" .. key .. "\\frame"
		local rail = "ReforgedUI\\Media\\Trim\\" .. key .. "\\rail"
		for _, kind in ipairs({ "Bag", "Panel", "Flat", "Dialog", "Slots", "Search" }) do
			local w = r.Windows[kind]
			assert(w, "the theme styles " .. kind .. " windows")
			local trim = w.Textures[1]
			assert(trim.Texture:sub(-#frame) == frame, kind .. ": the " .. key .. " trim")
			assert(trim.SliceMode == "Tiled" and trim.SliceMargins.Left == 14, kind .. ": nine-sliced, 14 a side")
			assert(trim.Inset.Left == -ReforgedUI.TRIM_OUT, kind .. ": the trim reaches past the window")
			local inset = ns.Themes[key].inset
			local c = w.Background.Color
			assert(c[1] == inset[1] and c[2] == inset[2] and c[3] == inset[3], kind .. ": the " .. key .. " inset")
			if w.Title then
				assert(w.Title.Font.Path == ReforgedUI.FONT, kind .. ": title font")
				assert(w.Textures[2].Texture:sub(-#rail) == rail, kind .. ": the " .. key .. " rail under the title")
			end
		end
		assert(r.Windows.Bag.CloseButton and r.Windows.Panel.CloseButton, "bags and panels close")
		assert(not r.Windows.Dialog.CloseButton, "dialogs have no close button")
		assert(r.Windows.Bag.Textures[3].Above, "the steel frame over the menu button")
		assert(r.Windows.Bag.Layout.MenuButton.Points[1].X == r.Windows.Bag.Textures[3].Points[1].X, "menu button in the frame")
		assert(r.Windows.Slots.Layout.Points[1].RelativePoint == "TOPLEFT", "the slots panels sit above their bag")
		assert(r.Elements.Tab.Background.Color[1] == ns.Themes[key].inset[1], "tabs in the inset colour")
	end
	checkBB(ns.themeKey)
	-- BetterBags Next: the body in the inset, the trim as ornaments (all
	-- round a small panel, only a post down a full one's inner side), the
	-- rail, the theme's art and particles, data only.
	local function checkNext(key)
		local t = sonataNext.themes.ReforgedUI
		dataOnly(t, "ReforgedUI")
		local inset = ns.Themes[key].inset
		local body = t.Palette.Body
		assert(body[1] == inset[1] and body[2] == inset[2] and body[3] == inset[3], "Next: the " .. key .. " inset")
		assert(t.Panel.Fill.Color == "Body", "Next: the body filled")
		assert(t.Panel.Feather.Color == "Body" and t.Panel.Edge == false, "Next: a feather, the trim instead of a border")
		local trim = "ReforgedUI\\Media\\Trim\\" .. key .. "\\"
		local seen = {}
		for _, o in ipairs(t.Panel.Ornaments) do
			assert(type(o.Texture) == "string" and o.Texture:find(trim, 1, true), "Next: " .. o.Point .. " in " .. key .. "'s art")
			local file = o.Texture:match("([^\\\\]+)$")
			assert(exists(ADDON .. "Media/Trim/" .. key .. "/" .. file .. ".tga"), "Next: " .. file .. " is shipped")
			seen[o.Point .. ":" .. file .. ":" .. tostring(o.Sizes)] = o
		end
		for _, c in ipairs({ "TOPINNER", "TOPOUTER", "BOTTOMINNER", "BOTTOMOUTER" }) do
			assert(seen[c .. ":join:Small"], "Next: the " .. c .. " corner on a small panel")
		end
		assert(seen["TOP:beam:Small"] and seen["BOTTOM:beam:Small"] and seen["TOP:beam:Small"].Tile, "Next: beams tiled along")
		assert(seen["INNER:post:Small"] and seen["OUTER:post:Small"], "Next: posts down both sides of a small panel")
		assert(seen["INNER:post:Small"].Tile == ReforgedUI.TrimPostPeriod(), "Next: the post tiled by its period")
		if key == "nightelf" then
			-- Its own pillar, leafy, and leaf clusters swaying on it.
			local pillar = seen["INNER:pillar:Full"]
			assert(pillar and pillar.X == -pillar.Width / 2 and pillar.Width > 28, "Next: night elf's own pillar, astride the edge")
			local clusters = 0
			for _, o in ipairs(t.Panel.Ornaments) do
				if o.Texture:match("cluster$") then
					clusters = clusters + 1
					assert(o.Sizes == "Full" and o.Motion and o.Motion.Sway, "Next: a cluster sways, on a full panel")
				end
			end
			assert(clusters > 0, "Next: night elf's leaf clusters")
		else
			local pillar = seen["INNER:post:Full"]
			assert(pillar and pillar.X == -pillar.Width / 2 and pillar.Tile == 2 * ReforgedUI.TrimPostPeriod(),
				"Next: a full panel's post, astride its edge")
			for _, o in ipairs(t.Panel.Ornaments) do
				assert(not o.Texture:match("cluster$"), "Next: clusters only where a theme has them")
			end
		end
		for k, o in pairs(seen) do
			assert(o.Sizes or k:match("^TOP:rail"), "Next: only the rail and the inner post on a full panel: " .. k)
		end
		assert(seen["TOP:rail:nil"], "Next: the rail under the title")
		local S = t.Sparkles
		assert(S and S.Edge and S.Cloud and S.Ribbon == false, "Next: particles off the inner side and round the title")
		for i, name in ipairs(S.Colors) do
			assert(t.Palette[name], "Next: particle colour " .. i .. " in the palette")
		end
		assert(t.Fonts.Title.File == ReforgedUI.FONT and t.Fonts.Title.Locales, "Next: our font, Latin locales only")
	end
	checkNext(ns.themeKey)
	-- A theme change applies the theme again, unsaved, only while it is the
	-- applied one.
	sonata.current = "Default"
	sonataNext.current = "Default"
	slash("theme orc")
	assert(#sonata.applies == 0, "another BetterBags theme is left alone")
	assert(#sonataNext.applies == 0, "another BetterBags Next theme is left alone")
	checkNext("orc")
	sonata.current = "ReforgedUI"
	sonataNext.current = "ReforgedUI"
	slash("theme nightelf")
	checkBags("nightelf")
	checkBB("nightelf")
	checkNext("nightelf")
	assert(#sonata.applies == 1 and sonata.applies[1].key == "ReforgedUI", "applied again on a theme change")
	assert(sonata.applies[1].save == false, "without saving")
	assert(#sonataNext.applies == 1 and sonataNext.applies[1].key == "ReforgedUI", "Next: applied again")
	assert(sonataNext.applies[1].save == false, "Next: without saving")
	slash("theme gnome")
	checkNext("gnome")
	slash("theme auto")
	checkBags(ns.themeKey)
end
-- Pet icon: beside the target of target, in the theme's trim, with its
-- happiness (hunters) and auras; Shift-drag moves it.
do
	local pet, target = ns.modules.pet, ns.modules.target
	local b = pet.button
	assert(b == ReforgedUIPet and b:GetAttribute("unit") == "pet", "pet unit button")
	local L = ns.layout
	local P, T = L.petIcon, L.tot
	assert(P.frame.x + P.frame.w <= T.frame.x and P.frame.x >= 0, "the pet icon stands left of the target of target")
	assert(P.power and P.box.h > T.box.h, "the pet icon has a power bar")
	assert(target.tot.trim and b.trim and b.trim.pieces.tl._tex, "both icons wear the theme's trim")
	hasPet = true
	local happiness = 3
	C_PetInfo = { GetPetHappiness = function() return happiness, 100, 0 end }
	local auras = { HARMFUL = 2, HELPFUL = 4 }
	local secretAuras = false
	local oldAuras = C_UnitAuras
	C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
		assert(unit == "pet")
		if secretAuras then error("cannot be accessed when secret") end
		if i <= auras[filter] then
			return { icon = 136000 + i, applications = i, duration = 10, expirationTime = 105 }
		end
	end }
	fire("UNIT_PET", "player")
	assert(b.happiness:IsShown(), "a hunter's pet shows its happiness")
	assert(b.name._text and b.name._text ~= "", "the pet's name over its icon")
	do
		local lines = {}
		GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
		C_PetInfo.GetPetHappiness = function() return happiness, 125, -1 end
		GetPetFoodTypes = function() return "Meat", "Fish" end
		PET_DAMAGE_PERCENTAGE = "Causes %d%% of normal damage"
		b.happiness._scripts.OnEnter(b.happiness)
		assert(lines[1] == "Causes 125% of normal damage" and lines[2] == "Losing Loyalty"
			and lines[3] == "Diet: Meat, Fish", "the happiness tooltip: damage, loyalty and diet")
		GameTooltip.AddLine, GetPetFoodTypes, PET_DAMAGE_PERCENTAGE = nil, nil, nil
		C_PetInfo.GetPetHappiness = function() return happiness, 100, 0 end
	end
	local function shown(filter)
		local n = 0
		for _, f in ipairs(b.auras[filter]) do
			if f:IsShown() then n = n + 1 end
		end
		return n
	end
	assert(shown("HARMFUL") == 2 and shown("HELPFUL") == 4, "pet auras shown")
	assert(b.auras.HARMFUL[2].count._text == 2 and b.auras.HARMFUL[1].count._text == "", "stack counts over 1 only")
	secretAuras = true
	fire("UNIT_AURA", "pet")
	assert(shown("HARMFUL") == 0 and shown("HELPFUL") == 0, "unreadable auras leave the rows empty")
	secretAuras = false
	happiness = nil
	fire("UNIT_HAPPINESS", "pet")
	assert(not b.happiness:IsShown(), "no happiness for other pets")
	C_UnitAuras = oldAuras
	C_PetInfo = nil
	-- Shift-drag saves the spot; in combat it doesn't move; reset puts it back.
	IsShiftKeyDown = function() return true end
	local barSpot = ReforgedUIDB.consoleOpts.petSpot
	b._scripts.OnDragStart(b)
	b._scripts.OnDragStop(b)
	assert(type(ReforgedUIDB.consoleOpts.petIconSpot) == "table", "a Shift-drag saves the pet's spot")
	assert(ReforgedUIDB.consoleOpts.petSpot == barSpot, "and leaves the pet bar's spot alone")
	slash("theme orc")
	slash("pet reset")
	assert(ReforgedUIDB.consoleOpts.petIconSpot == false, "/rui pet reset")
	inCombat = true
	ReforgedUIDB.consoleOpts.petIconSpot = false
	b._scripts.OnDragStart(b)
	b._scripts.OnDragStop(b)
	assert(ReforgedUIDB.consoleOpts.petIconSpot == false, "no moving in combat")
	inCombat = false
	IsShiftKeyDown = nil
	slash("theme auto")
	hasPet = false
end

-- Totem timers: secure buttons at the right end of the stance row, a
-- shaman's always there, right-click cancels its slot's totem.
do
	local mod = ns.modules.totems
	local T = ns.layout.totems
	assert(#mod.buttons == 4 and ReforgedUITotem1, "four totem buttons")
	for i, b in ipairs(mod.buttons) do
		assert(b._shown, "a shaman's totem buttons stay shown")
		assert(b:GetAttribute("type2") == "destroytotem" and b:GetAttribute("totem-slot") == b.slot,
			"totem button " .. i .. " cancels its slot")
	end
	local fire = mod.buttons[2]
	assert(fire.slot == 1 and fire.active and fire.face:GetAlpha() == 1, "the fire totem shows")
	assert(fire.face.time._text == "43", "the fire totem's time left: " .. tostring(fire.face.time._text))
	assert(not mod.buttons[1].active and mod.buttons[1].face:GetAlpha() == 0, "an empty slot draws nothing")
	assert(T.right - 4 * T.step > ns.layout.stance.x + 4 * T.step, "totems clear of the stance row's start")
	-- A secret answer (in combat) still shows the icon, and the time left as
	-- whole seconds through the font string, never compared.
	local oldInfo, oldSecret, oldLeft = GetTotemInfo, issecretvalue, GetTotemTimeLeft
	local SECRET, secretLeft = {}, 117.4
	issecretvalue = function(v) return v == SECRET or v == secretLeft end
	GetTotemInfo = function() return SECRET, SECRET, SECRET, SECRET, 135825 end
	GetTotemTimeLeft = function() return secretLeft end
	mod:Update()
	assert(fire.secret and fire.face.time._text == "117", "secret totems show seconds left: " .. tostring(fire.face.time._text))
	GetTotemTimeLeft = function() return SECRET end
	mod:UpdateTimes()
	assert(fire.face.time._text == "", "a time left the client won't format shows nothing")
	-- Then the client's own countdown text takes over, once per totem update.
	local bindings = {}
	C_DurationUtil = { CreateDurationTextBinding = function()
		local bind = {}
		function bind:SetFontString(fs) self.fs = fs end
		function bind:SetFormatter(f) self.formatter = f end
		function bind:SetDuration(d) self.duration = d end
		function bind:SetEnabled(on) self.enabled = on; if on then self.fs:SetText("2m") end end
		bindings[#bindings + 1] = bind
		return bind
	end }
	C_StringUtil = { CreateSecondsFormatter = function() return {} end }
	GetTotemDuration = function(slot) return { slot = slot } end
	mod:Update()
	local bind = fire.binding
	assert(bind and bind.enabled and bind.fs == fire.face.time and bind.duration.slot == 1 and fire.bound,
		"the client's countdown shows a time it won't format for us")
	assert(fire.face.time._text == "2m" and fire.howTime == "client countdown", "countdown text: " .. tostring(fire.face.time._text))
	mod:UpdateTimes()
	assert(fire.face.time._text == "2m" and #bindings == 4, "the ticker leaves the countdown alone")
	local lines = mod:Describe()
	assert(#lines == 5 and lines[2]:find("slot 1: have secret") and lines[2]:find("client countdown"),
		"/rui totems describes each slot: " .. tostring(lines[2]))
	-- An empty slot answering nothing at all is no totem, not a secret one.
	GetTotemInfo = function(slot) if slot == 1 then return SECRET, SECRET, SECRET, SECRET, 135825 end end
	mod:Update()
	assert(not mod.buttons[1].active and mod.buttons[1].face:GetAlpha() == 0, "a slot answering nothing draws nothing")
	assert(fire.secret, "the secret totem stays")
	C_DurationUtil, C_StringUtil, GetTotemDuration = nil, nil, nil
	GetTotemInfo, issecretvalue, GetTotemTimeLeft = oldInfo, oldSecret, oldLeft
	mod:Update()
	assert(not fire.secret and fire.face.time._text == "43", "back to plain totem info")
	-- Moving: the buttons hang from one holder; Shift-drag or Edit Mode
	-- moves it out of combat, the spot is saved, /rui totems reset clears it.
	local h = mod.holder
	assert(fire:GetParent() == h and h == ReforgedUITotems, "totem buttons hang from the holder")
	local wall = mod:Spot()
	assert(wall.x == T.right - wall.w and wall.y == T.y, "the row starts on the wall")
	IsShiftKeyDown = function() return false end
	fire._scripts.OnDragStart(fire)
	assert(not h._moving, "a plain drag doesn't move the totems")
	IsShiftKeyDown = function() return true end
	inCombat = true
	fire._scripts.OnDragStart(fire)
	assert(not h._moving, "no moving the totems in combat")
	inCombat = false
	fire._scripts.OnDragStart(fire)
	assert(h._moving, "Shift-drag moves the totems")
	fire._scripts.OnDragStop(fire)
	IsShiftKeyDown = nil
	assert(not h._moving and type(ns.db.consoleOpts.totemSpot) == "table", "the totems' spot is saved")
	local moved = mod:Spot()
	assert(moved.x == ns.db.consoleOpts.totemSpot[1] and moved.w == wall.w, "the row goes where it was dragged")
	EditModeManagerFrame._hooks.OnShow()
	assert(h.outline._shown and h._mouse ~= false, "Edit Mode shows the totems' outline")
	h._scripts.OnDragStart(h)
	assert(h._moving, "Edit Mode drags the totems without Shift")
	h._scripts.OnDragStop(h)
	EditModeManagerFrame._hooks.OnHide()
	assert(not h.outline._shown and h._mouse == false, "the outline goes with Edit Mode")
	SlashCmdList.REFORGEDUI("totems reset")
	assert(ns.db.consoleOpts.totemSpot == false and mod:Spot().x == wall.x, "/rui totems reset")
end

-- Every option the run so far read or set is one Core.lua lists.
do
	local stray = {}
	for key, where in pairs(strayOptions) do
		if where ~= "?" then -- ("?": looked at by this test, not the addon)
			stray[#stray + 1] = ("consoleOpts.%s (%s)"):format(tostring(key), where)
		end
	end
	table.sort(stray)
	assert(#stray == 0, "options without a default in Core.lua: " .. table.concat(stray, ", "))
	-- (The check itself.)
	local _ = ReforgedUIDB.consoleOpts.noSuchOption
	assert(strayOptions.noSuchOption, "an option without a default is noticed")
	setmetatable(ReforgedUIDB.consoleOpts, nil)
end

-- Tooltips in the theme's frame, like the damage meter; off brings
-- Blizzard's border back.
do
	local mod = ns.modules.tooltip
	assert(mod.enabled, "the tooltip module runs")
	for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
		assert(tip.NineSlice:GetAlpha() == 0, tip:GetName() .. ": Blizzard's border is invisible")
		assert(tip._clamp[1] == -ReforgedUI.TRIM_OUT and tip._clamp[3] == 25, tip:GetName() .. ": the frame stays on screen")
	end
	SharedTooltip_SetBackdropStyle(GameTooltip)
	assert(GameTooltip.NineSlice:GetAlpha() == 0, "a style change doesn't bring the border back")
	-- The health bar goes inside the frame.
	local trimBox
	for _, f in ipairs(allFrames) do
		if f._parent == GameTooltip and f._scripts.OnSizeChanged then trimBox = f end
	end
	assert(trimBox, "the tooltip has a trim")
	GameTooltip.StatusBar:Show()
	GameTooltip.StatusBar._hooks.OnShow(GameTooltip.StatusBar)
	local bottom
	for _, pt in ipairs(trimBox._points) do
		if pt[1] == "BOTTOM" then bottom = pt end
	end
	assert(bottom and bottom[2] == GameTooltip.StatusBar, "the frame takes in the health bar")
	GameTooltip.StatusBar:Hide()
	-- A size made secret by secret text: no arithmetic on it.
	local oldSecret, oldWidth = issecretvalue, methods.GetWidth
	local SECRET = {}
	issecretvalue = function(v) return v == SECRET end
	trimBox.GetWidth = function() return SECRET end
	trimBox._scripts.OnSizeChanged(trimBox)
	trimBox.GetWidth, issecretvalue, methods.GetWidth = nil, oldSecret, oldWidth
	SlashCmdList.REFORGEDUI("tooltips off")
	assert(ns.db.consoleOpts.themeTooltips == false, "/rui tooltips off is saved")
	assert(GameTooltip.NineSlice:GetAlpha() == 1 and GameTooltip._clamp[1] == 0, "off: Blizzard's border and clamp back")
	SharedTooltip_SetBackdropStyle(GameTooltip)
	assert(GameTooltip.NineSlice:GetAlpha() == 1, "off: the border stays")
	SlashCmdList.REFORGEDUI("tooltips on")
	assert(ns.db.consoleOpts.themeTooltips == true and GameTooltip.NineSlice:GetAlpha() == 0, "/rui tooltips on")
end

-- In an instance, all at once: everything the game tells about other units
-- is secret (one value that fails on any comparison, sum, length or lookup),
-- with a target, its target, a pet and totems out, in both target displays
-- and with the free-standing bars on. No module may trip over it on any of
-- the usual events. (What each then shows is checked feature by feature
-- above; this pass is for a feature added later that reads a unit and
-- forgets ns.IsSecret.)
do
	local SECRET = newproxy(true)
	local mt = getmetatable(SECRET)
	local function fail() error("looked at a secret value", 2) end
	for _, op in ipairs({ "__eq", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__concat",
		"__len", "__index", "__newindex", "__call" }) do
		mt[op] = fail
	end
	mt.__tostring = function() return "secret" end
	local saved = {}
	local function swap(name, fn)
		saved[name] = _G[name]
		_G[name] = fn
	end
	local function others(name, ...)
		local old, n, answer = _G[name], select("#", ...), { ... }
		swap(name, function(unit, ...)
			if unit == "player" or unit == "vehicle" or old == nil then
				if old then return old(unit, ...) end
				return nil
			end
			return unpack(answer, 1, n)
		end)
	end
	swap("issecretvalue", function(v) return rawequal(v, SECRET) end)
	for _, name in ipairs({ "UnitName", "GetUnitName", "UnitLevel", "UnitHealth", "UnitHealthMax", "UnitPower",
		"UnitPowerMax", "UnitIsTapDenied", "UnitClassification", "UnitCreatureType", "UnitGetIncomingHeals",
		"GetComboPoints" }) do
		others(name, SECRET)
	end
	others("UnitCastingInfo", SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET)
	others("UnitChannelInfo", SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET)
	swap("UnitIsUnit", function() return SECRET end)
	swap("GetTotemInfo", function() return SECRET, SECRET, SECRET, SECRET, 135825 end)
	swap("GetTotemTimeLeft", function() return SECRET end)
	swap("C_UnitAuras", { GetAuraDataByIndex = function(_, i)
		if i <= 2 then
			return { icon = 136000 + i, applications = SECRET, duration = SECRET, expirationTime = SECRET }
		end
	end })
	swap("C_PetInfo", { GetPetHappiness = function() return SECRET, SECRET, SECRET end })
	local wasTarget, wasPet, wasCombat = hasTarget, hasPet, inCombat
	local target, o = ns.modules.target, ns.db.consoleOpts
	local wasMode, wasBar, wasToT = target:Mode(), o.targetBar, o.totBar
	local EVENTS = {
		{ "PLAYER_TARGET_CHANGED" }, { "UNIT_TARGET", "target" }, { "UNIT_PET", "player" },
		{ "UNIT_HEALTH", "target" }, { "UNIT_HEALTH", "targettarget" }, { "UNIT_HEALTH", "pet" },
		{ "UNIT_MAXHEALTH", "target" }, { "UNIT_POWER_UPDATE", "target" }, { "UNIT_POWER_UPDATE", "pet" },
		{ "UNIT_MAXPOWER", "target" }, { "UNIT_DISPLAYPOWER", "target" }, { "UNIT_NAME_UPDATE", "target" },
		{ "UNIT_LEVEL", "target" }, { "UNIT_FACTION", "target" }, { "UNIT_AURA", "target" }, { "UNIT_AURA", "pet" },
		{ "UNIT_HEAL_PREDICTION", "target" }, { "UNIT_HAPPINESS", "pet" }, { "UNIT_COMBO_POINTS", "player" },
		{ "UNIT_SPELLCAST_START", "target" }, { "UNIT_SPELLCAST_CHANNEL_START", "target" },
		{ "UNIT_SPELLCAST_STOP", "target" }, { "PLAYER_TOTEM_UPDATE", 1 }, { "UPDATE_MOUSEOVER_UNIT" },
		{ "PLAYER_REGEN_DISABLED" }, { "PLAYER_REGEN_ENABLED" }, { "PLAYER_ENTERING_WORLD" },
	}
	hasTarget, hasPet = true, true
	target:SetBarEnabled(true)
	target:SetBarEnabled(true, target.totBar)
	local function pass()
		for _, mode in ipairs({ "swap", "plate" }) do
			inCombat = false
			target:SetMode(mode)
			for _, combat in ipairs({ false, true }) do
				inCombat = combat
				for _, event in ipairs(EVENTS) do
					local ok, err = pcall(fire, unpack(event))
					if not ok then
						return ("in an instance (%s, %s): %s%s: %s"):format(mode, combat and "in combat" or "out of combat",
							event[1], event[2] and " " .. tostring(event[2]) or "", tostring(err))
					end
				end
				-- Frames that update on a timer do so with the same values.
				for _, f in ipairs(allFrames) do
					local update = f._scripts.OnUpdate
					if update and f:IsShown() then
						local ok, err = pcall(update, f, 0.5)
						if not ok then
							return ("in an instance (%s): an OnUpdate of %s: %s"):format(mode, tostring(f:GetName()),
								tostring(err))
						end
					end
				end
				flushTimers()
			end
		end
	end
	local why = pass()
	assert(not why, why)
	-- The check itself: a feature that compares what it reads is caught.
	local careless = true
	ns:On("UNIT_HEALTH", function(_, unit)
		if careless and unit == "target" then
			return UnitHealth(unit) > 0
		end
	end)
	why = pass()
	assert(why and why:find("UNIT_HEALTH target"), "a careless comparison is caught")
	careless = false
	-- Back out of it: everything plain again.
	inCombat = false
	for name, fn in pairs(saved) do
		_G[name] = fn
	end
	for _, name in ipairs({ "UnitGetIncomingHeals", "UnitCastingInfo", "UnitChannelInfo", "UnitClassification",
		"UnitCreatureType", "GetComboPoints", "UnitIsTapDenied", "GetTotemTimeLeft", "C_PetInfo", "C_UnitAuras" }) do
		if saved[name] == nil then _G[name] = nil end
	end
	target:SetBarEnabled(wasBar and true or false)
	target:SetBarEnabled(wasToT and true or false, target.totBar)
	target:SetMode(wasMode)
	hasTarget, hasPet, inCombat = wasTarget, wasPet, wasCombat
	fire("PLAYER_TARGET_CHANGED")
	fire("UNIT_PET", "player")
end

print("smoke test passed")
io.stdout:write("smoke test passed (" .. #files .. " files)\n")
