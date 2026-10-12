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
local function new(kind, name, parent)
	local o = setmetatable({
		_kind = kind, _name = name, _parent = parent, _w = 0, _h = 0, _scale = 1,
		_shown = true, _points = {}, _scripts = {}, _attrs = {}, _level = 1,
	}, Object)
	if name then _G[name] = o end
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
function methods:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function methods:SetText(t) self._text = t end
function methods:GetNumPoints() return #self._points end
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
function methods:SetColorTexture(r, g, b) assert(r and g and b, "colour needs rgb") end
function methods:SetTextColor(r, g, b) assert(r and g and b, "colour needs rgb") end

----------------------------------------------------------------------------
-- Globals the addon touches

local eventFrames = {}
function CreateFrame(kind, name, parent, template)
	local secure = template and (template:find("Secure") or template:find("ActionBarButton"))
	local f = new(secure and "secure" or kind, name, parent)
	if template == "ActionBarButtonTemplate" then
		f.icon = new("texture", nil, f)
		f.IconMask = new("texture", nil, f)
		f.NormalTexture = new("texture", nil, f)
		f.UpdateAction = function(btn) btn._updated = (btn._updated or 0) + 1 end
	end
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
ChatFrame1 = new("frame", "ChatFrame1", UIParent)
ChatFrame1EditBox = new("editbox", "ChatFrame1EditBox", UIParent)
MainMenuBar = new("frame", "MainMenuBar", UIParent)
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
function UnitRace() return "Orc", "Orc" end
function UnitFactionGroup() return "Horde" end
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
	if line:match("^[%w_]+%.lua$") then files[#files + 1] = line end
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

fire("PLAYER_LOGIN")
assert(ns.ready, "init did not finish")
assert(ReforgedUIDB and ReforgedUIDB.scale == 1, "saved variables not initialised")
fire("PLAYER_ENTERING_WORLD")
assert(ns.themeKey == "orc", "orc race should pick the orc theme")
assert(overrides == 2, "expected 2 override bindings, got " .. overrides)
assert(Minimap._points[1][2] == ns.root, "minimap not anchored to the console")
assert(ReforgedUIBar_main and ReforgedUImainButton1._updated, "main bar buttons not built")
assert(CharacterMicroButton:GetParent() == ReforgedUIMicroMenu, "classic micro buttons not rescued")
assert(ReforgedUITopButton1 and ReforgedUITopButton1:GetAttribute("clickbutton") == QuestLogMicroButton,
	"quests button should click the quest log micro button")
local _, _, _, _, py = PlayerFrame:GetPoint(1)
assert(py < -4, "player frame not moved below the top bar")
local tb = ns.modules.topbar
assert(math.abs(tb.dial._rotation + math.pi) < 1e-6, "midnight should turn the moon to the window")
gameHour = 12
tb:UpdateClock()
assert(math.abs(tb.dial._rotation) < 1e-6, "noon should put the sun in the window")
assert(tb.resources[3].text._text == "20%", "durability should show the lowest item")

-- Something else moving a locked frame snaps it back.
ChatFrame1:ClearAllPoints()
ChatFrame1:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
assert(ChatFrame1._points[1][1] == "BOTTOMLEFT" and ChatFrame1._points[1][2] == ns.root, "chat lock failed")

-- Protected frames moved in combat are queued until combat ends.
inCombat = true
StanceBar:SetPoint("CENTER", UIParent, "CENTER", 5, 5)
assert(StanceBar._points[#StanceBar._points][1] == "CENTER", "protected frame moved in combat")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(StanceBar._points[1][1] == "BOTTOMLEFT", "queued relock did not run")

local slash = SlashCmdList.REFORGEDUI
for _, size in ipairs({ { 1365.33, 768, "standard" }, { 1792, 768, "wide" }, { 2730.67, 768, "superwide" },
	{ 1024, 768, "standard" }, { 1920, 1080, "standard" } }) do
	UIParent._w, UIParent._h = size[1], size[2]
	slash("layout auto")
	assert(ns.layout.profile == size[3], ("expected %s at %sx%s, got %s"):format(size[3], size[1], size[2], ns.layout.profile))
	for _, theme in ipairs({ "human", "orc", "undead", "nightelf", "auto" }) do
		slash("theme " .. theme)
	end
	for _, p in ipairs({ "16:9", "21:9", "32:9" }) do
		slash("layout " .. p)
		slash("scale 0.8")
		slash("scale 1")
	end
end
ContainerFrame1:Show()
updateContainerFrameAnchors()
slash("status")
slash("bogus")
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_POWER_UPDATE", "PLAYER_XP_UPDATE", "BAG_UPDATE_DELAYED",
	"UPDATE_BINDINGS", "ZONE_CHANGED_NEW_AREA", "ACTIONBAR_PAGE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
	fire(e, "player")
end
print("smoke test passed")
io.stdout:write("smoke test passed (" .. #files .. " files)\n")
