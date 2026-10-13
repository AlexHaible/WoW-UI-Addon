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
function methods:SetShown(v) self._shown = not not v end
function methods:Show() self._shown = true end
function methods:Hide() self._shown = false end
function methods:IsShown() return self._shown end
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
function methods:GetObjectType() return self._kind == "button" and "Button" or "Frame" end
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
	{ "MultiBarBottomRightButton" }, { "MultiBarRightButton" }, { "MultiBarLeftButton" }, { "MultiBar5Button" } }) do
	local bar = spec[2] or new("frame", spec[1]:gsub("Button$", ""), UIParent)
	for i = 1, 12 do
		local b = new("secure", spec[1] .. i, bar)
		b._w, b._h = 45, 45
		b.icon = new("texture", nil, b)
		b.IconMask = new("texture", nil, b)
	end
end
MultiBar5Button1.action = 145
MainMenuBarBackpackButton = new("button", "MainMenuBarBackpackButton", UIParent)
for i = 0, 3 do new("button", "CharacterBag" .. i .. "Slot", UIParent) end
TargetFrame = new("secure", "TargetFrame", UIParent)
StanceBar = new("secure", "StanceBar", UIParent)
PetActionBar = new("secure", "PetActionBar", UIParent)
PlayerCastingBarFrame = new("frame", "PlayerCastingBarFrame", UIParent)
ObjectiveTrackerFrame = new("frame", "ObjectiveTrackerFrame", UIParent)
ObjectiveTrackerFrame._h = 400
CharacterMicroButton = new("button", "CharacterMicroButton", MainMenuBar)
CharacterMicroButton._w, CharacterMicroButton._h = 28, 58
MainMenuMicroButton = new("button", "MainMenuMicroButton", MainMenuBar)
MainMenuMicroButton._w, MainMenuMicroButton._h = 28, 58
GameTooltip = new("frame", "GameTooltip", UIParent)
PlayerFrame = new("secure", "PlayerFrame", UIParent)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4)
function PlayerFrame:GetTop() local _, _, _, _, y = self:GetPoint(1); return 768 + y end
QuestLogMicroButton = new("button", "QuestLogMicroButton", MainMenuBar)
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
function UnitExists() return true end
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
playerRace, playerRaceFile, playerFaction = "Orc", "Orc", "Horde"
function UnitRace() return playerRace, playerRaceFile end
function UnitFactionGroup() return playerFaction end
function UnitName() return "Thrall" end
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

-- Settings from version 1 had a scale of 1, now far too big.
ReforgedUIDB = { scale = 1, theme = "auto" }
fire("PLAYER_LOGIN")
assert(ns.ready, "init did not finish")
assert(ReforgedUIDB.scale == 0.75 and ReforgedUIDB.version == 3, "old default scale not migrated")
assert(ReforgedUIDB.consoleOpts.uiScale == 240 and ReforgedUIDB.consoleOpts.center == "off", "console option defaults")
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
assert(TargetFrame._alpha == nil and #TargetFrame._points == 0, "the target frame must be left alone")
assert(MinimapCluster:GetParent() == UIParent and MinimapCluster._alpha == nil and #MinimapCluster._points == 0,
	"the minimap cluster must be left alone")
assert(Minimap:GetParent() == UIParent, "the minimap keeps its parent")
assert(#StanceBar._points == 0 and #ObjectiveTrackerFrame._points == 0, "Edit Mode frames must stay put")
assert(MainActionBar.EndCaps._alpha == 0 and MainActionBar._alpha == nil, "main bar art should hide, not its buttons")
assert(MainActionBar._mouse == false and MultiBar5._mouse == false, "empty bar frames should be click-through")

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
assert(CharacterMicroButton._alpha == 0, "micro buttons are hidden by default")
assert(ReforgedUITopButton1 and ReforgedUITopButton1:GetAttribute("clickbutton") == QuestLogMicroButton,
	"quests button should click the quest log micro button")

-- Bars 1-3 in the grid, Action Bar 6 beside the minimap and in the inventory.
for key, prefix in pairs({ main = "ActionButton", bar2 = "MultiBarBottomLeftButton", bar3 = "MultiBarBottomRightButton" }) do
	local row = L.bars[key]
	for _, i in ipairs({ 1, 7, 12 }) do
		local btn = _G[prefix .. i]
		at(btn, row.xs[i], row.y, prefix .. i)
		assert(math.abs(btn._w * unit(btn) - row.size) < 0.01, prefix .. i .. " has the wrong size")
	end
end
at(MultiBar5Button1, L.minimapSlots[1].x, L.minimapSlots[1].y, "Action Bar 6 button 1")
at(MultiBar5Button4, L.inventory[1].x, L.inventory[1].y, "Action Bar 6 button 4")
assert(MultiBar5Button10._points[1] == nil, "Action Bar 6 has nine slots")
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
assert(hero.xp.level._text == "Level 12 Shaman" and hero.xp.name._text == "Thrall", "name and level")
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

-- Bags: our own buttons that click Blizzard's.
local inv = ns.modules.inventory
inv.buttons[1]._scripts.OnClick(inv.buttons[1])
inv.buttons[3]._scripts.OnClick(inv.buttons[3])
assert(MainMenuBarBackpackButton._clicks == 1 and CharacterBag1Slot._clicks == 1, "bag clicks go to Blizzard's buttons")
ContainerFrame1:Hide()
inv:UpdateVisibility()
assert(inv.holder._alpha == 0, "bags are hidden until the backpack opens")
ContainerFrame1:Show()
inv:UpdateVisibility()
assert(inv.holder._alpha == 1, "bags show while the backpack is open")

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
	if eb.key == "chatWidth" then eb._text = "" end
end
function methods:GetText() return self._text end
config:Apply()
assert(ReforgedUIDB.consoleOpts.uiScale == 270 and ns.layout.s == 270, "UI scale is clamped to 240-270")
assert(ReforgedUIDB.consoleOpts.chatWidth == false, "an empty chat width means to the screen edge")
config.cogwheel._scripts.OnClick()
assert(not ReforgedUIConfig:IsShown(), "the cogwheel toggles the menu")

-- Every theme, centre mode, UI scale and screen shape lays out.
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
		for _, center in ipairs({ "off", "center", "slim", "noinv" }) do
			ReforgedUIDB.consoleOpts.center = center
			for _, s in ipairs({ 240, 245, 250, 255, 260, 266, 270 }) do
				ReforgedUIDB.consoleOpts.uiScale = s
				ns:Relayout()
				assert(ns.layout.s == s and ns.layout.center == center, "options reach the layout")
				assert((ns.layout.chat ~= nil) == (center == "off" or center == "center"), "chat area per mode")
			end
		end
	end
	for _, p in ipairs({ "16:9", "21:9", "32:9" }) do
		slash("layout " .. p)
		slash("scale 1")
		slash("scale 0.75")
	end
end
checkAnchors()

-- Race themes: the default ("auto") follows the race, Skyborne by its token or
-- its name, with the faction picking the variant; other races fall back by
-- faction; a chosen theme overrides the race.
local function themeFor(race, raceFile, faction, saved)
	playerRace, playerRaceFile, playerFaction = race, raceFile, faction
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
	{ "Pandaren", "Pandaren", "Alliance", "human" }, { "Pandaren", "Pandaren", "Horde", "orc" },
	{ nil, nil, nil, "human" },
}) do
	local got = themeFor(c[1], c[2], c[3])
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
playerRace, playerRaceFile, playerFaction = "Orc", "Orc", "Horde"
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
	for _, center in ipairs(Layout.CENTER_MODES) do
		for _, s in ipairs({ 240, 250, 270 }) do
			local LL = Layout.Compute(1792, 768, { s = s, m = 10, theme = key, center = center, zoneTextPos = 1 })
			for _, piece in ipairs(LL.pieces) do
				files[piece.file] = true
			end
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
print("smoke test passed")
io.stdout:write("smoke test passed (" .. #files .. " files)\n")
