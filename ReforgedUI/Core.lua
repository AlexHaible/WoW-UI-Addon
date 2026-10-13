-- Reforged UI core: saved settings, events, the combat-safe work queue, the
-- frame "lock" helper used to keep Blizzard frames where we put them, and the
-- two roots every module builds on: the console (768 units tall, the
-- screen the original addon was designed for) and the top bar (its own scale).

local addonName, ns = ...

ns.name = addonName
ns.modules = {}
ns.moduleOrder = {}

local DEFAULTS = {
	theme = "auto", -- auto (race default) | skyborne (by faction) | a key of ns.Themes
	layout = "auto", -- top bar: auto | standard | wide | superwide
	scale = 0.75, -- top bar
	version = 4,
	modules = {
		console = true,
		hero = true,
		actionbars = true,
		minimap = true,
		chat = true,
		inventory = true,
		blizzard = true,
		topbar = true,
		target = true,
		config = true,
	},
	-- Data broker feeds shown in the top bar, by slot number (see TopBar.lua).
	broker = {},
	-- The original addon's options (its config menu, see Config.lua).
	consoleOpts = {
		uiScale = 240, -- 240-270
		chatUp = 10, -- "extend bottom right upwards", 0-150
		portraitX = 100, portraitY = 100, portraitScale = 0,
		hpWarning = 25,
		restedColor = { 0, 0, 1, 0.5 },
		icons = {}, -- stat icon choices per class
		healthPercent = false,
		powerPercent = false,
		hideGrid = false,
		hideMicro = true,
		hideChatIcons = false,
		chatInputAbove = false,
		zoneText = 1, -- 1 bottom, 2 top, 3 hidden
		stopAnimation = false,
		hearthstone = {}, -- characters that already got the hearthstone placed
		targetMode = "swap", -- target display: swap (the hero screen shows the target) | plate
		barsEnabled = {}, -- characters whose bars 2, 3 and 8 were turned on once
	},
}

-- Settings saved by older versions.
local function migrate(db)
	if (db.version or 1) < 2 then
		-- Version 1 used 1.0 as its default scale, which turned out far too big.
		if db.scale == 1 then
			db.scale = DEFAULTS.scale
		end
	end
	if (db.version or 1) < 3 then
		-- Version 3 replaced the console with the original addon's; drop the old modules'
		-- switches and settings.
		db.modules, db.stats = nil, nil
	end
	if (db.version or 1) < 4 and type(db.consoleOpts) == "table" then
		-- Version 4 always centres the console with its chat area and
		-- inventory (the original addon's "Center UI"), the chat window placed in it and
		-- the bags shown: those options are gone.
		local o = db.consoleOpts
		o.center, o.chatWidth, o.hideBags, o.placeChat = nil, nil, nil, nil
	end
	db.version = DEFAULTS.version
end

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

-- Newer clients run Blizzard code with "secret" values that addon code must
-- not touch. Reparenting, hiding or moving Blizzard frames makes their own
-- scripts run on our (tainted) call stack, so frames we replace are only made
-- invisible and click-through, which runs none of their code.
local function forbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end
ns.IsForbidden = forbidden

local concealed = setmetatable({}, { __mode = "k" })

local function noMouse(frame, depth)
	if forbidden(frame) then
		return
	end
	if frame.EnableMouse and not (frame:IsProtected() and InCombatLockdown()) then
		frame:EnableMouse(false)
	end
	if depth < 4 and frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			noMouse(child, depth + 1)
		end
	end
end

function ns:Conceal(frame)
	if not frame or forbidden(frame) then
		return
	end
	if frame.SetAlpha then
		frame:SetAlpha(0)
		if not concealed[frame] then
			local busy
			hooksecurefunc(frame, "SetAlpha", function(f)
				if not busy then
					busy = true
					f:SetAlpha(0)
					busy = false
				end
			end)
		end
	end
	concealed[frame] = true
	if frame.GetChildren then
		self:RunOutOfCombat(frame, function() noMouse(frame, 0) end)
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

-- `also` names further methods that should re-apply the lock (e.g. SetScale).
function ns:Lock(frame, apply, also)
	if not frame or forbidden(frame) then
		return
	end
	local hooked = locks[frame] ~= nil
	locks[frame] = apply
	if not hooked then
		hooksecurefunc(frame, "SetPoint", runLock)
		for _, method in ipairs(also or {}) do
			hooksecurefunc(frame, method, runLock)
		end
	end
	runLock(frame)
end

function ns:Unlock(frame)
	locks[frame] = false
end

-- Keep a frame's bottom edge at or above console height `limit()`.
function ns:KeepAbove(frame, limit)
	self:Lock(frame, function(f)
		local bottom = f:GetBottom()
		local point, rel, relPoint, x, y = f:GetPoint(1)
		if not bottom or not point or f:GetNumPoints() > 1 then
			return
		end
		local min = limit() * self.root:GetEffectiveScale() / f:GetEffectiveScale()
		if bottom < min - 0.5 then
			f:SetPoint(point, rel, relPoint, x or 0, (y or 0) + (min - bottom))
		end
	end)
end

-- Scale factor that converts console units into `frame`'s own units.
function ns:UnitsFor(frame)
	return self.root:GetEffectiveScale() / frame:GetEffectiveScale()
end

-- Place a frame that is not a child of the console so its `point` sits at
-- console coordinates (x, y). Blizzard frames are anchored to UIParent (whose
-- bottom-left is the console's), never to our frames: Edit Mode saves anchors
-- by frame name and would otherwise store ours in its layout.
function ns:Anchor(frame, point, x, y)
	local s = self:UnitsFor(frame)
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, "BOTTOMLEFT", x * s, y * s)
end

function ns:PlaceRect(frame, r, point)
	self:Anchor(frame, point or "BOTTOMLEFT", r.x, r.y)
	if r.w and r.h then
		local s = self:UnitsFor(frame)
		frame:SetSize(r.w * s, r.h * s)
	end
end

-- Right-click menu of choices: items are { text, checked, func }. Uses the
-- modern menu API; returns false where the client has none.
function ns:ShowMenu(owner, title, items)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return false
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(title)
		for _, item in ipairs(items) do
			root:CreateRadio(item.text, function() return item.checked end, function() item.func() end)
		end
		if #items > 20 and root.SetScrollMode then
			root:SetScrollMode(400)
		end
	end)
	return true
end

-- Coalesce bursts of events into one call on the next frame or so.
function ns:Throttle(fn, delay)
	local pending
	return function()
		if pending then
			return
		end
		pending = true
		C_Timer.After(delay or 0.1, function()
			pending = false
			fn()
		end)
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

-- The original addon's options as Layout.Compute wants them.
function ns:LayoutOptions()
	local o = self.db.consoleOpts
	local Layout = self.Layout
	local s = math.floor(tonumber(o.uiScale) or 240)
	return {
		s = math.max(Layout.SCALE_MIN, math.min(Layout.SCALE_MAX, s)),
		m = math.max(0, math.min(150, tonumber(o.chatUp) or 10)),
		theme = self.themeKey,
		zoneTextPos = o.zoneText,
		portraitX = tonumber(o.portraitX) or 100,
		portraitY = tonumber(o.portraitY) or 100,
		portraitScale = tonumber(o.portraitScale) or 0,
		chatInputAbove = o.chatInputAbove,
	}
end

function ns:Relayout()
	self:RunOutOfCombat("relayout", function()
		-- The console is laid out for a screen 768 units tall (the original addon's
		-- design size); scale it so it keeps that share of the screen at any
		-- resolution and UI scale.
		local root = self.root
		local scale = UIParent:GetHeight() / 768
		root:SetScale(scale)
		local W = UIParent:GetWidth() / scale
		root:ClearAllPoints()
		root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		root:SetSize(W, 768)

		-- The top bar keeps Reforged UI's own scale setting (/rui scale).
		local topRoot = self.topRoot
		local topScale = self.db.scale * UIParent:GetHeight() / 768
		topRoot:SetScale(topScale)
		local TW, TH = UIParent:GetWidth() / topScale, UIParent:GetHeight() / topScale
		topRoot:ClearAllPoints()
		topRoot:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		topRoot:SetSize(TW, TH)
		self.topLayout = self.Layout.ComputeTopBar(TW, TH, self.db.layout)

		local L = self.Layout.Compute(W, 768, self:LayoutOptions())
		self.layout = L
		self:ForEachModule("OnLayout", L)
	end)
end

function ns:ApplyTheme()
	self.themeKey = self:ResolveThemeKey(self.db.theme)
	self.theme = self.Themes[self.themeKey]
	self:ForEachModule("OnTheme", self.theme)
	-- The original addon's pieces sit differently per theme.
	if self.ready then
		self:Relayout()
	end
end

----------------------------------------------------------------------------
-- Edit Mode repair

-- Earlier versions anchored Blizzard frames to our console, and Edit Mode
-- saved those anchors into the player's layouts (stored by the game, so the
-- warning stayed even with the addon off). Put any such frame back in its
-- default position once.
local function repairEditModeLayouts()
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
		return
	end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
		return
	end
	local fixed = 0
	for _, layout in ipairs(info.layouts) do
		for _, system in ipairs(layout.systems or {}) do
			for _, key in ipairs({ "anchorInfo", "anchorInfo2" }) do
				local anchor = system[key]
				if type(anchor) == "table" and type(anchor.relativeTo) == "string"
					and anchor.relativeTo:find("^ReforgedUI") then
					anchor.relativeTo = "UIParent"
					system.isInDefaultPosition = true
					fixed = fixed + 1
				end
			end
		end
	end
	if fixed > 0 and pcall(C_EditMode.SaveLayouts, info) then
		ns:Print(("reset %d Edit Mode position(s) left over from an older version."):format(fixed))
	end
end

----------------------------------------------------------------------------
-- Startup

local function makeRoot(name)
	local f = CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate")
	f:SetFrameStrata("BACKGROUND")
	f:SetFrameLevel(1)
	RegisterStateDriver(f, "visibility", "[petbattle] hide; show")
	return f
end

local function init()
	local db = ReforgedUIDB or {}
	migrate(db) -- before the defaults fill in the new version number
	ReforgedUIDB = copyDefaults(DEFAULTS, db)
	ns.db = ReforgedUIDB
	repairEditModeLayouts()

	ns.root = makeRoot("ReforgedUIConsole")
	ns.topRoot = makeRoot("ReforgedUITopRoot")

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
	ns:Print("commands (the console's own options are in its menu: the cogwheel in the bottom-right corner):")
	print("  /rui config  (open that menu)")
	print("  /rui theme auto||" .. table.concat(ns.THEME_ORDER, "||") .. "||skyborne  (auto: your race's theme)")
	print("  /rui feeds  (list data feeds and top bar slots)")
	print("  /rui slot <number> <feed name>||none")
	print("  /rui scale 0.5-1.5  (top bar)")
	print("  /rui layout auto||16:9||21:9||32:9  (top bar)")
	print("  /rui module <name> on||off  (console, hero, actionbars, minimap, chat, inventory, blizzard, target,"
		.. " topbar, config; needs /reload)")
	print("  /rui status")
	print("  /rui target swap||plate  (target display: on the hero screen, or a plate on the wall)")
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
		if not ns.THEME_ALIASES[arg] and not ns.Themes[arg] then
			ns:Print("unknown theme", arg)
			return
		end
		ns.db.theme = arg
		ns:ApplyTheme()
		ns:Print("theme:", ns.theme.name, ns.THEME_ALIASES[arg] and ("(" .. arg .. ")") or "")
	elseif cmd == "config" and ns.modules.config.enabled then
		ns.modules.config:Toggle()
	elseif cmd == "layout" and arg and LAYOUT_ALIASES[arg] then
		ns.db.layout = LAYOUT_ALIASES[arg]
		ns:Relayout()
		ns:Print("top bar layout:", ns.db.layout)
	elseif cmd == "scale" and tonumber(arg) then
		ns.db.scale = math.max(0.5, math.min(1.5, tonumber(arg)))
		ns:Relayout()
		ns:Print("top bar scale:", ns.db.scale)
	elseif cmd == "feeds" and ns.modules.topbar.enabled then
		ns.modules.topbar:ListFeeds()
	elseif cmd == "slot" and tonumber(arg) and arg2 and ns.modules.topbar.enabled then
		local result = ns.modules.topbar:SetSlotByName(tonumber(arg), arg2)
		ns:Print(result and ("slot " .. arg .. ": " .. (result == true and "empty" or result)) or ("no feed matches " .. arg2))
	elseif cmd == "module" and arg and ns.modules[arg] and (arg2 == "on" or arg2 == "off") then
		ns.db.modules[arg] = arg2 == "on"
		ns:Print(arg, arg2, "- type /reload to apply.")
	elseif cmd == "target" and (arg == "swap" or arg == "plate") and ns.modules.target.enabled then
		ns.modules.target:SetMode(arg)
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
		ns:Print("target display:", arg == "swap" and "swap (hero screen)" or "wall plate")
	elseif cmd == "status" then
		local L, T = ns.layout, ns.topLayout
		ns:Print(("theme %s, UI scale %d, console shifted %d, screen %.0fx%.0f units; top bar %s (%s), scale %.2f"):format(
			ns.theme.name, L.s, L.shift, L.W, L.H, T.profile, ns.Layout.PROFILES[T.profile].label, ns.db.scale))
	elseif cmd == "reset" then
		ReforgedUIDB = nil
		ns:Print("settings reset - type /reload to apply.")
	else
		usage()
	end
end
