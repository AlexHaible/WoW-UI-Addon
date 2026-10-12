-- Reforged UI core: saved settings, events, the combat-safe work queue, the
-- frame "lock" helper used to keep Blizzard frames where we put them, and the
-- console root that every module builds on.

local addonName, ns = ...

ns.name = addonName
ns.modules = {}
ns.moduleOrder = {}

local DEFAULTS = {
	theme = "auto", -- auto | human | orc | undead | nightelf
	layout = "auto", -- auto | standard | wide | superwide
	scale = 1.0,
	modules = {
		actionbars = true,
		minimap = true,
		chat = true,
		unitinfo = true,
		inventory = true,
		blizzard = true,
		topbar = true,
	},
}

local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = type(dst[k]) == "table" and dst[k] or {}
			copyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns:Print(...)
	print("|cffffd100Reforged UI:|r", ...)
end

----------------------------------------------------------------------------
-- Events

local events = CreateFrame("Frame")
local handlers = {}

-- Unknown events (APIs differ between Retail and Classic-based clients) are
-- skipped quietly.
function ns:On(event, fn)
	if not handlers[event] then
		if not pcall(events.RegisterEvent, events, event) then
			return false
		end
		handlers[event] = {}
	end
	table.insert(handlers[event], fn)
	return true
end

events:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(event, ...)
	end
end)

----------------------------------------------------------------------------
-- Combat queue: protected work requested in combat runs once combat ends.

local queue, queueOrder = {}, {}

function ns:RunOutOfCombat(key, fn)
	if not InCombatLockdown() then
		fn()
		return
	end
	if not queue[key] then
		queueOrder[#queueOrder + 1] = key
	end
	queue[key] = fn
end

ns:On("PLAYER_REGEN_ENABLED", function()
	local order = queueOrder
	queueOrder = {}
	for _, key in ipairs(order) do
		local fn = queue[key]
		queue[key] = nil
		if fn then
			fn()
		end
	end
end)

----------------------------------------------------------------------------
-- Frame helpers

-- Parent for Blizzard frames we replace. Hidden, so anything parented to it
-- is never drawn, but it keeps a valid position for code that measures it.
ns.hider = CreateFrame("Frame", "ReforgedUIHider", UIParent)
ns.hider:Hide()

function ns:Kill(frame)
	if frame and frame.SetParent then
		frame:SetParent(self.hider)
	end
end

-- Lock a frame's position: `apply` places the frame, and runs again whenever
-- something else (Edit Mode, layout managers) calls SetPoint on it.
local locks, applying = {}, {}

local function runLock(frame)
	local apply = locks[frame]
	if not apply or applying[frame] then
		return
	end
	if InCombatLockdown() and frame:IsProtected() then
		ns:RunOutOfCombat(frame, function()
			runLock(frame)
		end)
		return
	end
	applying[frame] = true
	local ok, err = pcall(apply, frame)
	applying[frame] = nil
	if not ok then
		geterrorhandler()(err)
	end
end

function ns:Lock(frame, apply)
	if not frame then
		return
	end
	local hooked = locks[frame] ~= nil
	locks[frame] = apply
	if not hooked then
		hooksecurefunc(frame, "SetPoint", runLock)
	end
	runLock(frame)
end

function ns:Unlock(frame)
	locks[frame] = false
end

-- Keep a frame's top edge at or below console height `limit()`, shifting it
-- down only when something places it higher (used to clear the top bar).
function ns:KeepBelow(frame, limit)
	self:Lock(frame, function(f)
		local top = f:GetTop()
		local point, rel, relPoint, x, y = f:GetPoint(1)
		if not top or not point or f:GetNumPoints() > 1 then
			return
		end
		local max = limit() * self.root:GetEffectiveScale() / f:GetEffectiveScale()
		if top > max + 0.5 then
			f:SetPoint(point, rel, relPoint, x or 0, (y or 0) - (top - max))
		end
	end)
end

-- Scale factor that converts console units into `frame`'s own units.
function ns:UnitsFor(frame)
	return self.root:GetEffectiveScale() / frame:GetEffectiveScale()
end

-- Place a frame that is not a child of the console using console units.
function ns:PlaceRect(frame, r, point)
	local s = self:UnitsFor(frame)
	frame:ClearAllPoints()
	frame:SetPoint(point or "BOTTOMLEFT", self.root, "BOTTOMLEFT", r.x * s, r.y * s)
	if r.w and r.h then
		frame:SetSize(r.w * s, r.h * s)
	end
end

----------------------------------------------------------------------------
-- Modules

function ns:RegisterModule(key, mod)
	mod.key = key
	self.modules[key] = mod
	self.moduleOrder[#self.moduleOrder + 1] = key
	return mod
end

function ns:ForEachModule(method, ...)
	for _, key in ipairs(self.moduleOrder) do
		local mod = self.modules[key]
		if mod.enabled and mod[method] then
			local ok, err = pcall(mod[method], mod, ...)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Layout and theme

function ns:Relayout()
	self:RunOutOfCombat("relayout", function()
		local root = self.root
		local scale = self.db.scale
		root:SetScale(scale)
		local W = UIParent:GetWidth() / scale
		local H = UIParent:GetHeight() / scale
		local L = self.Layout.Compute(W, H, self.db.layout)
		self.layout = L
		root:ClearAllPoints()
		root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		root:SetSize(W, L.top)
		self:ForEachModule("OnLayout", L)
	end)
end

function ns:ApplyTheme()
	self.themeKey = self:ResolveThemeKey(self.db.theme)
	self.theme = self.Themes[self.themeKey]
	self:ForEachModule("OnTheme", self.theme)
end

----------------------------------------------------------------------------
-- Startup

local function init()
	ReforgedUIDB = copyDefaults(DEFAULTS, ReforgedUIDB or {})
	ns.db = ReforgedUIDB

	local root = CreateFrame("Frame", "ReforgedUIConsole", UIParent, "SecureHandlerStateTemplate")
	root:SetFrameStrata("BACKGROUND")
	root:SetFrameLevel(1)
	ns.root = root
	RegisterStateDriver(root, "visibility", "[petbattle] hide; show")

	ns.themeKey = ns:ResolveThemeKey(ns.db.theme)
	ns.theme = ns.Themes[ns.themeKey]

	for _, key in ipairs(ns.moduleOrder) do
		local mod = ns.modules[key]
		mod.enabled = ns.db.modules[key] ~= false
		if mod.enabled and mod.OnEnable then
			local ok, err = pcall(mod.OnEnable, mod)
			if not ok then
				mod.enabled = false
				geterrorhandler()(err)
			end
		end
	end

	ns:Relayout()
	ns:ApplyTheme()

	ns:On("DISPLAY_SIZE_CHANGED", function() ns:Relayout() end)
	ns:On("UI_SCALE_CHANGED", function() ns:Relayout() end)
	ns:On("PLAYER_ENTERING_WORLD", function() ns:Relayout() end)
	ns.ready = true
end

ns:On("PLAYER_LOGIN", function()
	-- Building secure frames needs to happen out of combat (a /reload while
	-- fighting would otherwise leave half the console unbuilt).
	ns:RunOutOfCombat("init", init)
end)

----------------------------------------------------------------------------
-- Slash commands

local LAYOUT_ALIASES = {
	["16:9"] = "standard", ["21:9"] = "wide", ["32:9"] = "superwide",
	standard = "standard", wide = "wide", superwide = "superwide", auto = "auto",
}

local function usage()
	ns:Print("commands:")
	print("  /rui theme auto|human|orc|undead|nightelf")
	print("  /rui layout auto|16:9|21:9|32:9")
	print("  /rui scale 0.5-1.5")
	print("  /rui module <name> on|off  (actionbars, minimap, chat, unitinfo, inventory, blizzard, topbar; needs /reload)")
	print("  /rui status")
	print("  /rui reset")
end

SLASH_REFORGEDUI1 = "/rui"
SLASH_REFORGEDUI2 = "/reforged"
SlashCmdList.REFORGEDUI = function(msg)
	if not ns.ready then
		ns:Print("still loading, try again after combat.")
		return
	end
	local cmd, arg, arg2 = strsplit(" ", strtrim(msg or ""):lower(), 3)
	if cmd == "theme" and arg then
		if arg ~= "auto" and not ns.Themes[arg] then
			ns:Print("unknown theme", arg)
			return
		end
		ns.db.theme = arg
		ns:ApplyTheme()
		ns:Print("theme:", ns.theme.name, arg == "auto" and "(auto)" or "")
	elseif cmd == "layout" and arg and LAYOUT_ALIASES[arg] then
		ns.db.layout = LAYOUT_ALIASES[arg]
		ns:Relayout()
		ns:Print("layout:", ns.db.layout)
	elseif cmd == "scale" and tonumber(arg) then
		ns.db.scale = math.max(0.5, math.min(1.5, tonumber(arg)))
		ns:Relayout()
		ns:Print("scale:", ns.db.scale)
	elseif cmd == "module" and arg and ns.modules[arg] and (arg2 == "on" or arg2 == "off") then
		ns.db.modules[arg] = arg2 == "on"
		ns:Print(arg, arg2, "- type /reload to apply.")
	elseif cmd == "status" then
		local L = ns.layout
		ns:Print(("theme %s, layout %s (%s), screen %.0fx%.0f units, scale %.2f"):format(
			ns.theme.name, L.profile, ns.Layout.PROFILES[L.profile].label, L.W, L.H, ns.db.scale))
	elseif cmd == "reset" then
		ReforgedUIDB = nil
		ns:Print("settings reset - type /reload to apply.")
	else
		usage()
	end
end
