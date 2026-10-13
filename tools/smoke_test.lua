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
function methods:SetFont(path, size, flags) self._font, self._size, self._flags = path, size, flags; return true end
function methods:GetFont() return self._font or "Fonts\\FRIZQT__.TTF", self._size or 12, self._flags or "" end
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
function methods:SetFrameStrata(s) self._strata = s end
function methods:SetBlendMode() end
function methods:HookScript(k, fn) self._hooks = self._hooks or {}; self._hooks[k] = fn end
function methods:SetShown(v) self._shown = not not v end
function methods:Show() self._shown = true end
function methods:Hide() self._shown = false end
function methods:IsShown() return self._shown end
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
function methods:SetTexture(path) if path then assert(type(path) == "string") end self._tex = path end
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
function methods:SetTextColor(r, g, b) assert(r and g and b, "colour needs rgb") end
function methods:SetStatusBarColor(r, g, b) assert(r and g and b, "colour needs rgb"); self._color = { r, g, b } end
function methods:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function methods:SetValue(v) self._value = v end
function methods:GetStringHeight() return 12 end
function methods:SetEnabled(v) self._enabled = v end
function methods:Click() self._clicks = (self._clicks or 0) + 1 end
function methods:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end

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
-- A forbidden frame among UIParent's children: touching it is an error.
local forbiddenFrame = new("frame", nil, UIParent)
forbiddenFrame._forbidden = true
function forbiddenFrame:GetName() error("Attempt to access forbidden object") end
local strayButton = new("button", "ForeverMinimapThing", Minimap)
strayButton._w, strayButton._h = 24, 24
IssueReporterButton = new("button", "IssueReporterButton", UIParent)
IssueReporterButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 10)
function IssueReporterButton:GetBottom() local _, _, _, _, y = self:GetPoint(1); return y end
ChatFrame1 = new("frame", "ChatFrame1", UIParent)
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
MultiBar7Button1.action = 145
BuffFrame = new("frame", "BuffFrame", UIParent)
DebuffFrame = new("frame", "DebuffFrame", UIParent)
local settingValues = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = true, PROXY_SHOW_ACTIONBAR_8 = false }
Settings = { GetSetting = function(name)
	if settingValues[name] == nil then return nil end
	return { GetValue = function() return settingValues[name] end, SetValue = function(_, v) settingValues[name] = v end }
end }
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
PlayerFrame = new("secure", "PlayerFrame", UIParent)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4)
function PlayerFrame:GetTop() local _, _, _, _, y = self:GetPoint(1); return 768 + y end
local gameHour = 0
function GetGameTime() return gameHour, 0 end
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
local hasTarget, totIsPlayer = false, false
function UnitExists(u) return u == "player" or hasTarget end
function UnitIsUnit(a, b) return a == b or (a == "targettarget" and b == "player" and totIsPlayer) end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function GetTime() return 100 end
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
function GetCursorInfo() return placed == "cursor" and "item" or nil end
function HasAction() return false end
function PlaceAction(slot) placed = slot end
function ClearCursor() end
C_Item = { GetItemCount = function() return 1 end, PickupItem = function() placed = "cursor" end }
function GetRealmName() return "Forever" end
UISpecialFrames = {}
tinsert = table.insert
function ReloadUI() end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
FACTION_BAR_COLORS = { [2] = { r = 1, g = 0.3, b = 0 } }

local savedLayouts
C_EditMode = {
	GetLayouts = function()
		return { activeLayout = 3, layouts = { { layoutName = "Mine", systems = {
			{ system = 12, anchorInfo = { point = "TOPRIGHT", relativeTo = "ReforgedUIConsole", relativePoint = "BOTTOMLEFT",
				offsetX = 1000, offsetY = 600 }, isInDefaultPosition = false },
			{ system = 0, anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM" } },
		} } } }
	end,
	SaveLayouts = function(info) savedLayouts = info end,
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
function RegisterStateDriver() end
function geterrorhandler() return function(err) error(err, 0) end end
function GetBindingKey(cmd) if cmd == "ACTIONBUTTON1" then return "1", "SHIFT-1" end end
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
function print(...) printed[#printed + 1] = table.concat({ tostringall and tostringall(...) or ... }, " ") end

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
-- the bags, all gone now.
ReforgedUIDB = { scale = 1, theme = "auto",
	consoleOpts = { center = "noinv", hideBags = true, chatWidth = 900, placeChat = false, uiScale = 240, hideMicro = true } }
fire("PLAYER_LOGIN")
assert(ns.ready, "init did not finish")
assert(ReforgedUIDB.scale == 0.75 and ReforgedUIDB.version == 5, "old default scale not migrated")
assert(ReforgedUIDB.consoleOpts.uiScale == 240 and ReforgedUIDB.consoleOpts.zoneText == 1, "console option defaults")
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
assert(ns.themeKey == "orc", "orc race should pick the orc theme")
for key, mod in pairs(ns.modules) do
	assert(mod.enabled, key .. " failed to enable")
end

-- Nothing of Blizzard's may be anchored to our frames (Edit Mode saves anchors).
local function checkAnchors()
	for _, f in ipairs(allFrames) do
		local name = rawget(f, "_name")
		if name and not name:find("^ReforgedUI") then
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
-- target: invisible and click-through, never moved or reparented.
for _, f in ipairs({ TargetFrame, TargetFrameToT }) do
	assert(f._alpha == 0 and f._mouse == false and #f._points == 0, f._name .. " should be concealed, not moved")
end
assert(TargetFrame:GetParent() == UIParent and TargetFrameToT:GetParent() == TargetFrame, "target frames keep their parents")
assert(MinimapCluster:GetParent() == UIParent and MinimapCluster._alpha == nil and #MinimapCluster._points == 0,
	"the minimap cluster must be left alone")
assert(Minimap:GetParent() == UIParent, "the minimap keeps its parent")
assert(#StanceBar._points == 0 and #ObjectiveTrackerFrame._points == 0, "Edit Mode frames must stay put")
assert(MainActionBar.EndCaps._alpha == 0 and MainActionBar._alpha == nil, "main bar art should hide, not its buttons")
assert(MainActionBar._mouse == false and MultiBar7._mouse == false, "empty bar frames should be click-through")

local L = ns.layout
local unit = function(f) return f:GetEffectiveScale() / ns.root:GetEffectiveScale() end
local function at(f, x, y, what)
	local p = f._points[1]
	assert(p and p[2] == UIParent, what .. " not anchored to UIParent")
	assert(math.abs(p[4] * unit(f) - x) < 0.01 and math.abs(p[5] * unit(f) - y) < 0.01, what .. " in the wrong place")
end
at(Minimap, L.minimap.x, L.minimap.y, "minimap")
assert(strayButton._points[1][2] == UIParent and strayButton:GetParent() == Minimap,
	"stray minimap buttons should line up along the map")
assert(MinimapCluster.Tracking._points[1][1] == "CENTER", "tracking button should sit in its slot")
local _, _, _, _, iy = IssueReporterButton:GetPoint(1)
assert(iy > 100, "the issue reporter should sit above the console")
-- Blizzard's micro buttons live in the top bar, either side of the clock:
-- still Blizzard's (same parent, visible), anchored to UIParent, scaled to
-- the bar. The plates' own buttons stay invisible.
local function microAt(b, r, what)
	local p = b._points[1]
	assert(p and #b._points == 1 and p[2] == UIParent and p[1] == "BOTTOMLEFT", what .. " should be anchored to UIParent")
	local k = b:GetEffectiveScale() / ns.topRoot:GetEffectiveScale()
	assert(math.abs(p[4] * k - r.x) < 0.01 and math.abs(p[5] * k - r.y) < 0.01, what .. " in the wrong place")
	assert(math.abs(b._h * k - r.h) < 0.01 and math.abs(b._w * k - r.w) < 0.01, what .. " has the wrong size")
	assert(b:GetParent() == (b == ns.modules.topbar.menuMicro and UIParent or MicroMenu), what .. " keeps its parent")
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
	-- Hugging the clock.
	assert(T.clockArt.x - (T.micro[nL].x + T.micro[nL].w) < 5 and T.micro[nL + 1].x - (T.clockArt.x + T.clockArt.w) < 5,
		"micro buttons should hug the clock")
end
-- The Adventure Guide and shop are left out; Legacy and a game menu button
-- of our own close the row.
local menuMicro = ns.modules.topbar.menuMicro
assert(menuMicro, "a game menu button at the end of the micro row")
local MOVED = { CharacterMicroButton, SpellbookMicroButton, TalentMicroButton, GuildMicroButton,
	LFDMicroButton, CollectionsMicroButton, unnamedMicro, LegacyMicroButton, menuMicro }
checkMicro(MOVED)
assert(#StoreMicroButton._points == 0 and StoreMicroButton._alpha == 0, "the shop button is hidden, not placed")
assert(#EJMicroButton._points == 0 and EJMicroButton._alpha == 0, "the Adventure Guide button is hidden, not placed")
assert(WorldMapMicroButton._alpha == 0 and #WorldMapMicroButton._points == 0, "the Map plate's micro button stays invisible")
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
	LFDMicroButton, CollectionsMicroButton, LegacyMicroButton, menuMicro })
unnamedMicro._shown = true
unnamedMicro._hooks.OnShow(unnamedMicro)
flushTimers()
checkMicro(MOVED)
-- The shop button shown by Blizzard stays out of the bar.
StoreMicroButton._shown = true
flushTimers()
checkMicro(MOVED)
-- The game menu button covers whichever of its two buttons the mouse enters.
do
	local b, plate = MainMenuMicroButton
	for _, p in ipairs(ns.modules.topbar.buttons) do
		if p.cover == b then plate = p end
	end
	local moves = 0
	local orig = b.SetPoint
	b.SetPoint = function(...) moves = moves + 1; return orig(...) end
	menuMicro._scripts.OnEnter(menuMicro)
	assert(plate.coverAt == menuMicro and moves > 0, "the game menu button moves over the micro row's menu button")
	local _, rel = b:GetPoint(1)
	assert(rel == UIParent and b:GetAlpha() == 0 and b._mouse == true, "still invisible, clickable, on UIParent")
	moves = 0
	plate._hooks.OnEnter(plate)
	assert(plate.coverAt == nil and moves > 0, "and back over the Menu plate")
	b.SetPoint = nil
end
-- Quests, Menu and Allies are Blizzard's own micro buttons, laid invisible
-- over the top bar's plates and clicked directly.
for _, b in ipairs({ QuestLogMicroButton, MainMenuMicroButton, SocialsMicroButton }) do
	local _, rel = b:GetPoint(1)
	assert(rel == UIParent and b:GetAlpha() == 0 and b._mouse == true, b:GetName() .. " should cover its top bar plate")
	assert(b:GetParent() == MicroMenu, b:GetName() .. " keeps its parent")
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
for i = 1, 3 do
	local r = L.minimapSlots[i]
	at(_G["MultiBar7Button" .. i], r.x, r.y, "Action Bar 8 button " .. i)
	local b = _G["MultiBar7Button" .. i]
	assert(math.abs(b._w * unit(b) - r.w) < 0.01, "Action Bar 8 button " .. i .. " has the wrong size")
end
for _, i in ipairs({ 4, 9, 12 }) do
	local _, _, _, _, y = _G["MultiBar7Button" .. i]:GetPoint(1)
	assert(y < 0, "Action Bar 8 button " .. i .. " should be parked below the screen")
end
-- The gold dividers between buttons stay invisible, even after Blizzard
-- updates them.
assert(ActionButton7.RightDivider._alpha == 0, "button dividers hidden")
ActionButton7.RightDivider:SetAlpha(1)
assert(ActionButton7.RightDivider._alpha == 0, "button dividers stay hidden")
MainActionBar:UpdateDividers()
for _, d in ipairs(dividerPool) do
	assert(d._alpha == 0 and d._shown, "bar dividers hidden by alpha, never Hide()")
end
-- Empty sockets explain Action Bar 8 while it is off.
local bars = ns.modules.actionbars
assert(not ReforgedUIBar8Socket1:IsShown(), "no socket over a shown Action Bar 8 button")
MultiBar7:Hide()
MultiBar7._hooks.OnHide()
assert(ReforgedUIBar8Socket1:IsShown() and ReforgedUIBar8Socket3:IsShown(), "sockets show while Action Bar 8 is off")
local p1 = ReforgedUIBar8Socket1._points[1]
assert(p1[2] == ns.root and math.abs(p1[4] - L.minimapSlots[1].x) < 0.01, "socket over the first minimap slot")
local tip
local oldSetText = methods.SetText
function GameTooltip:SetText(t) tip = t end
ReforgedUIBar8Socket1._scripts.OnEnter(ReforgedUIBar8Socket1)
assert(tip == "Turn on Action Bar 8 in Edit Mode to use these slots", "socket tooltip")
GameTooltip.SetText = nil
methods.SetText = oldSetText
MultiBar7:Show()
bars:UpdateSockets()
assert(not ReforgedUIBar8Socket1:IsShown(), "sockets hide again when Action Bar 8 is on")
-- Stance (aura) and pet buttons: Blizzard's, on the wall over the grid,
-- anchored to UIParent; their Edit Mode bars stay put.
for i = 1, 10 do
	at(_G["StanceButton" .. i], L.stance.x + (i - 1) * L.stance.step, L.stance.y, "stance button " .. i)
	at(_G["PetActionButton" .. i], L.pet.x + (i - 1) * L.pet.step, L.pet.y, "pet button " .. i)
	assert(_G["StanceButton" .. i]:GetParent() == StanceBar, "stance buttons keep their parent")
end
assert(math.abs(StanceButton1._w * unit(StanceButton1) - L.stance.size) < 0.01, "stance button size")
assert(L.stance.y >= 0.55 * L.s and L.stance.x > L.portraitArt.x + L.portraitArt.w - 0.2 * L.s,
	"stance row sits on the wall over the grid")
assert(StanceBar._mouse == false and PetActionBar._mouse == false and StanceBar._alpha == nil,
	"stance and pet bar frames are click-through, not hidden")
-- The day/night indicator is hidden, not moved.
assert(GameTimeFrame._alpha == 0 and #GameTimeFrame._points == 0, "GameTimeFrame should be concealed, not moved")
assert(MinimapCluster.DielFrame._alpha == 0 and #MinimapCluster.DielFrame._points == 0,
	"Forever's DielFrame (the moon) should be concealed, not moved")
for _, b in ipairs(ns.modules.minimap.buttons) do
	assert(b ~= GameTimeFrame, "GameTimeFrame must not join the minimap button row")
end
assert(placed == 145, "the hearthstone should go into the first slot beside the minimap")
assert(ReforgedUIDB.consoleOpts.hearthstone["Thrall-Forever"], "the hearthstone is placed once per character")

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
	ns:FitText(fs, ns:FullName("player"))
end
assert(math.abs(hero.xp.bar._w - L.xp.bar.w / 4) < 0.01, "XP bar at 25%")
assert(math.abs(hero.xp.rested._w - L.xp.bar.w * 1500 / 4000) < 0.01, "rested XP")
assert(hero.stats[1].value._text == "10 - 16", "main hand damage")
assert(not hero.stats[2]:IsShown(), "second stat icon is off by default")
assert(hero.stats[4].value._text:find("%%"), "armour reduction")
hero:SetIconChoice(2, "offhand")
assert(hero.stats[2].value._text == "13.4%\n (10)", "a shield shows block chance and value")
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
assert(ReforgedUIDB.consoleOpts.icons.SHAMAN[3] == "heal", "icon choices are kept per class")
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
assert(L.keyRing.x + L.keyRing.w <= L.inventory[1].x, "the key ring stands left of the inventory")
inv.buttons[1]._scripts.OnClick(inv.buttons[1])
inv.buttons[3]._scripts.OnClick(inv.buttons[3])
assert(MainMenuBarBackpackButton._clicks == 1 and CharacterBag1Slot._clicks == 1, "bag clicks go to Blizzard's buttons")

-- Top bar: clock, and our own data feeds in the first slots.
local tb = ns.modules.topbar
assert(math.abs(tb.dial._rotation + math.pi) < 1e-6, "midnight should turn the moon to the window")
gameHour = 12
tb:UpdateClock()
assert(math.abs(tb.dial._rotation) < 1e-6, "noon should put the sun in the window")
assert(tb.slots[1].text._text:find("20%%"), "slot 1 should show durability")
assert(tb.slots[2].text._text == "25 / 80", "slot 2 should show bag space")
assert(tb.slots[3].text._text == "123", "slot 3 should show gold")
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

-- Protected frames moved in combat are queued until combat ends.
inCombat = true
ActionButton1:SetPoint("CENTER", UIParent, "CENTER", 5, 5)
assert(ActionButton1._points[#ActionButton1._points][1] == "CENTER", "protected frame moved in combat")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(ActionButton1._points[1][1] == "BOTTOMLEFT", "queued relock did not run")

-- The options menu.
local config = ns.modules.config
SlashCmdList.REFORGEDUI("config")
assert(ReforgedUIConfig:IsShown(), "/rui config opens the menu")
for _, eb in ipairs(config.edits) do
	if eb.key == "uiScale" then eb._text = "999" end
end
function methods:GetText() return self._text end
config:Apply()
assert(ReforgedUIDB.consoleOpts.uiScale == 270 and ns.layout.s == 270, "UI scale is clamped to 240-270")
for _, eb in ipairs(config.edits) do
	assert(not tContains({ "chatWidth" }, eb.key), "no chat width option")
end
for _, cb in ipairs(config.checks) do
	assert(not tContains({ "hideBags", "placeChat", "hideMicro" }, cb.key), "no " .. tostring(cb.key) .. " option")
	assert(cb.key, "every checkbox is a plain option (no centre mode boxes)")
end
config.cogwheel._scripts.OnClick()
assert(not ReforgedUIConfig:IsShown(), "the cogwheel toggles the menu")

-- The top bar's pieces never collide: plates, micro buttons, clock and feed
-- slots (slots give way first), the clock centred.
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
	for _, r in ipairs(T.topButtons) do
		if r then
			assert(not O(r, T.clockArt), "a plate overlaps the clock")
			pieces[#pieces + 1] = r
		end
	end
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
	{ 1024, 768, "standard" }, { 1920, 1080, "standard" }, { 4266.67, 1200, "superwide" } }) do
	UIParent._w, UIParent._h = size[1], size[2]
	slash("layout auto")
	assert(math.abs(ns.topLayout.H - 768 / ns.db.scale) < 0.01, "the top bar should keep its share of the screen")
	assert(ns.topLayout.profile == size[3],
		("expected %s at %sx%s, got %s"):format(size[3], size[1], size[2], ns.topLayout.profile))
	assert(ns.layout.H == 768, "the console is 768 units tall")
	for _, theme in ipairs({ "human", "orc", "undead", "nightelf", "dwarf", "gnome", "tauren", "troll",
		"highorder", "windshapers", "skyborne", "auto" }) do
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
	{ "Troll", "Troll", "Horde", "troll" }, { "Undead", "Scourge", "Horde", "undead" },
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
	local files = {}
	for _, s in ipairs({ 240, 250, 270 }) do
		local LL = Layout.Compute(1792, 768, { s = s, m = 10, theme = key, zoneTextPos = 1 })
		for _, piece in ipairs(LL.pieces) do
			files[piece.file] = true
		end
	end
	for file in pairs(files) do
		assert(file:sub(1, #key + 1) == key .. "\\" or file:sub(1, 6) == "other\\",
			file .. " is not in " .. key .. "'s folder")
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
		end
	end
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
-- Buffs hang just below the top bar, debuffs under the buffs; both anchored
-- to Blizzard frames only.
do
	local point, rel, _, x, y = BuffFrame:GetPoint(1)
	assert(point == "TOPRIGHT" and rel == UIParent and x < 0 and y < 0, "buffs pinned below the top bar")
	local _, drel = DebuffFrame:GetPoint(1)
	assert(drel == BuffFrame, "debuffs under the buffs")
	BuffFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	assert(select(2, BuffFrame:GetPoint(1)) == UIParent and BuffFrame:GetPoint(1) == "TOPRIGHT", "buffs stay pinned")
end
-- Bars 2, 3 and 8 are turned on once per character.
assert(settingValues.PROXY_SHOW_ACTIONBAR_2 and settingValues.PROXY_SHOW_ACTIONBAR_3
	and settingValues.PROXY_SHOW_ACTIONBAR_8, "bars 2, 3 and 8 turned on")
settingValues.PROXY_SHOW_ACTIONBAR_8 = false
ns.modules.actionbars:EnableBars()
assert(settingValues.PROXY_SHOW_ACTIONBAR_8 == false, "bars are only turned on once; the player's choice stands")
-- The top bar's Menu button is Blizzard's game menu button laid over it,
-- invisible and clickable, so no addon code opens the menu.
do
	local b = MainMenuMicroButton
	local _, rel = b:GetPoint(1)
	assert(rel == UIParent, "game menu button anchored to UIParent")
	assert(b:GetAlpha() == 0 and b._mouse == true, "game menu button invisible but clickable")
	b:SetAlpha(1); b:EnableMouse(false)
	assert(b:GetAlpha() == 0 and b._mouse == true, "game menu button stays invisible and clickable")
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
	assert(hero.xp.name._text == "Hogger" and hero.xp.level._text == "Level 11 Elite Beast", "swap: target name and level")
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
	secretTarget = false
	fire("UNIT_HEALTH", "target")
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
	-- Target of target: tinted by who it is.
	totIsPlayer = true
	target:UpdateToT()
	assert(target.tot.kind == "player" and target.tot.glow._vertex[3] == 1, "ToT: you are tinted blue")
	totIsPlayer = false
	for r, want in pairs({ [2] = "hostile", [6] = "friendly" }) do
		totReaction = r
		target:UpdateToT()
		assert(target.tot.kind == want, "ToT tint " .. want)
	end
	assert(target.tot.glow._vertex[2] == 1 and target.tot.glow._vertex[1] < 0.5, "friendly ToT is green")
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
	assert(pl.name._text == "Hogger" and pl.info._text == "Level 11 Elite Beast", "plate: name and level line")
	assert(pl.name == pl.plate.name and pl.info == pl.plate.level and not pl.plate.bar:IsShown(),
		"plate: the hero's level plate, without an experience fill")
	assert(pl.healthText._text == "412 / 666" and pl.powerText._text == "30 / 100" and pl.power:IsShown(),
		"plate: health and power numbers")
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
	assert(P.file == LL.theme .. "\\" .. ns.Layout.TARGET_ART.genFile, "the plate uses the theme's own plate art")
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
print("smoke test passed")
io.stdout:write("smoke test passed (" .. #files .. " files)\n")
