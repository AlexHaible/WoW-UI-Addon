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
	version = 5,
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
	-- Each character's money in copper, by realm then name, for the gold
	-- feed's tooltip: { [realm] = { [name] = { money = n, class = "MAGE",
	-- name = "full name", faction = "Horde" } } }.
	money = {},
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
		hideChatIcons = false,
		chatInputAbove = false,
		freeChat = false, -- let the player move and resize the chat window
		chatPlaced = false, -- (freeChat) put in the chat area once
		zoneText = 1, -- 1 bottom, 2 top, 3 hidden
		addonDrawerOpen = false, -- the minimap's addon compartment
		stopAnimation = false,
		hearthstone = {}, -- characters that already got the hearthstone placed
		targetMode = "swap", -- target display: swap (the hero screen shows the target) | plate
		targetBar = false, -- a movable target health and power bar, besides the target display
		targetBarPos = false, -- where it was dragged to ({ x, y } from the screen's centre)
		barsEnabled = {}, -- characters whose bars 2, 3 and 8 were turned on once
		editLayout = {}, -- characters switched to the Reforged UI Edit Mode layout once
		editModeBars = false, -- bars 1-3 stay on their Edit Mode bars, pre-placed once, not in the grid
		barsPlaced = false, -- those bars were pre-placed in the Reforged UI layout
		buffSpot = false, -- where the buffs were last placed in Edit Mode layouts ({ x, y })
		transparency = 0, -- how see-through the console's art is, 0-100 %
		chatWiden = 0, -- how much the console shrinks to widen the chat area on narrow screens, 0-100 %
		hideTopBar = false, -- no top bar: Blizzard's micro buttons stand on the minimap block instead
	},
}

-- Settings saved by older versions.
local function migrate(db)
	-- The console's options used to be saved under a shorter key; keep them.
	if type(db.wiii) == "table" and db.consoleOpts == nil then
		db.consoleOpts = db.wiii
	end
	db.wiii = nil
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
	if (db.version or 1) < 5 and type(db.consoleOpts) == "table" then
		-- Version 5 moved Blizzard's micro buttons into the top bar, beside
		-- the clock: the option to hide them is gone.
		db.consoleOpts.hideMicro = nil
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
-- Keeps a single texture (a frame's border or background) invisible.
local concealedRegions = setmetatable({}, { __mode = "k" })
-- Warcraft III's steel command-button frame over a button's icon (above the
-- icon, below its count and cooldown).
function ns:IconFrame(btn)
	if btn.reforgedFrame then
		return btn.reforgedFrame
	end
	local t = btn:CreateTexture(nil, "ARTWORK", nil, 7)
	t:SetTexture(self.MEDIA .. "Common\\iconframe")
	t:SetAllPoints()
	btn.reforgedFrame = t
	return t
end

function ns:ConcealRegion(region)
	if not region or not region.SetAlpha or concealedRegions[region] or forbidden(region) then
		return
	end
	concealedRegions[region] = true
	region:SetAlpha(0)
	local busy
	hooksecurefunc(region, "SetAlpha", function(r)
		if not busy then
			busy = true
			r:SetAlpha(0)
			busy = false
		end
	end)
end

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

-- Our font (the original addon's) only has Latin letters, so a name in
-- Korean, Chinese or Cyrillic came out as boxes. A font family hands those
-- letters to the fonts the game itself uses for them, read from its own
-- GameFontHighlight family (these files as a fallback); one family per size
-- and outline.
local FALLBACK_FONTS = {
	korean = "Fonts\\2002.TTF",
	simplifiedchinese = "Fonts\\ARKai_T.ttf",
	traditionalchinese = "Fonts\\blei00d.TTF",
	russian = "Fonts\\FRIZQT___CYR.TTF",
}
local ALPHABETS = { "korean", "simplifiedchinese", "traditionalchinese", "russian" }

local function gameFontFile(alphabet)
	local base = GameFontHighlight
	if base and base.GetFontObjectForAlphabet then
		local ok, member = pcall(base.GetFontObjectForAlphabet, base, alphabet)
		local file = ok and member and member:GetFont()
		if file then
			return file
		end
	end
	return FALLBACK_FONTS[alphabet]
end

local families = {}
local function fontFamily(size, flags, file)
	local key = size .. "_" .. flags .. (file ~= ns.FONT and ("_" .. file) or "")
	if families[key] == nil then
		local members = { { alphabet = "roman", file = file, height = size, flags = flags } }
		for i, alphabet in ipairs(ALPHABETS) do
			members[i + 1] = { alphabet = alphabet, file = gameFontFile(alphabet), height = size, flags = flags }
		end
		local ok, family = pcall(CreateFontFamily, "ReforgedUIFont" .. key:gsub("%W", "_"), members)
		families[key] = ok and family or false
		ns.fontFamilyError = not ok and family or nil
	end
	return families[key]
end

-- Whether our font file loads, tried on a spare font string: SetFont on the
-- string itself would set its font directly, and a font set directly wins
-- over the family given to it afterwards (1.6.1 still drew boxes).
local probe
local function fontLoads(file, size, flags)
	probe = probe or UIParent:CreateFontString(nil, "OVERLAY")
	return probe:SetFont(file, size, flags)
end

-- Gives a font string our font (or the font file `file`) at `size`, with the
-- game's fonts for letters it lacks. False when the font file cannot be
-- loaded.
function ns:SetFont(fs, size, flags, file)
	flags, file = flags or "", file or self.FONT
	if not fontLoads(file, size, flags) then
		return false
	end
	fs.ourFont = flags
	fs.ourFontFile = file
	local family = CreateFontFamily and fontFamily(size, flags, file)
	if family then
		fs:SetFontObject(family)
	else
		fs:SetFont(file, size, flags)
	end
	return true
end

-- For /rui font: whether names get the fallback fonts.
function ns:DescribeFont(fs)
	local lines = { "CreateFontFamily: " .. (CreateFontFamily and "yes" or "missing") }
	if self.fontFamilyError then
		lines[#lines + 1] = "font family error: " .. tostring(self.fontFamilyError)
	end
	for _, alphabet in ipairs(ALPHABETS) do
		lines[#lines + 1] = alphabet .. ": " .. tostring(gameFontFile(alphabet))
	end
	if fs then
		local obj = fs.GetFontObject and fs:GetFontObject()
		lines[#lines + 1] = ("name font: %s, object %s"):format(tostring((fs:GetFont())),
			tostring(obj and obj.GetName and obj:GetName()))
	end
	return lines
end

-- Changes a font string's font size, keeping its font (ours with its
-- fallbacks, or whatever it had).
function ns:ResizeFont(fs, size)
	if fs.ourFont then
		self:SetFont(fs, size, fs.ourFont, fs.ourFontFile)
	else
		local path, _, flags = fs:GetFont()
		fs:SetFont(path, size, flags or "")
	end
end

-- Sets `text` on a one-line font string and shrinks its font, a point at a
-- time from the size it was created with, until it fits the string's width.
-- Secret text (a unit name in an instance) can't be measured, and makes the
-- string's own width secret too, so it keeps the starting size.
local MIN_FIT_SIZE = 7
function ns:FitText(fs, text)
	fs:SetWordWrap(false)
	local path, size = fs:GetFont()
	fs.fitSize = fs.fitSize or size
	size = fs.fitSize
	if path and size then
		self:ResizeFont(fs, size)
	end
	fs:SetText(text)
	if issecretvalue and issecretvalue(text) then
		return
	end
	local maxW = fs:GetWidth()
	if not (path and size and maxW) or (issecretvalue and issecretvalue(maxW)) or maxW <= 0 then
		return
	end
	local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
	local ok = pcall(function()
		while measure(fs) > maxW and size > MIN_FIT_SIZE do
			size = size - 1
			self:ResizeFont(fs, size)
		end
	end)
	if not ok then
		self:ResizeFont(fs, fs.fitSize)
	end
end

-- A unit's full name: on Forever a character's surname comes back where
-- other clients put the realm, and GetUnitName(unit, true) joins the two
-- ("John Dwarfadin"). In instances the name can be a "secret" string: it
-- can be shown but not compared, so it is passed on untouched.
function ns:FullName(unit)
	local name = GetUnitName and GetUnitName(unit, true)
	if issecretvalue and issecretvalue(name) then
		return name
	end
	if type(name) ~= "string" or name == "" then
		name = UnitName(unit)
	end
	return name
end

-- Puts `unit` in a 3D portrait model, with its flat portrait on `flat`
-- (a texture behind the model) for as long as the model has nothing to
-- show: in instances an enemy's model can stay empty.
function ns:SetUnitModel(model, flat, unit)
	model:SetUnit(unit)
	if model.SetPortraitZoom then
		model:SetPortraitZoom(1)
	end
	if not flat.hooked and model.HasScript and model:HasScript("OnModelLoaded") then
		flat.hooked = true
		model:HookScript("OnModelLoaded", function() flat:Hide() end)
	end
	local has = true
	if model.GetModelFileID then
		local ok, id = pcall(model.GetModelFileID, model)
		has = ok and not (issecretvalue and issecretvalue(id)) and type(id) == "number" and id > 0
	end
	if has then
		flat:Hide()
	else
		SetPortraitTexture(flat, unit)
		flat:Show()
	end
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
			if item.title then
				root:CreateTitle(item.text)
			else
				root:CreateRadio(item.text, function() return item.checked end, function() item.func() end)
			end
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
		-- With "Chat width" on, the chat area runs to the screen edge rather
		-- than giving up width to the end caps.
		capsOffScreen = (tonumber(o.chatWiden) or 0) > 0,
	}
end

-- The console is laid out for a screen 768 units tall (the original addon's
-- design size) and keeps that share of the screen's height, but never gets
-- narrower than a 16:9 screen: on narrower ones (16:10, 4:3) it scales down
-- to fit that width, so the chat area keeps its 16:9 width. The "Chat width"
-- option (0-100 %) widens that further, up to room for the original addon's
-- chat width, on screens too narrow for it.
local CONSOLE_MIN_ASPECT = 16 / 9

-- The narrowest the console gets, in console units.
function ns:ConsoleMinWidth()
	local Layout = self.Layout
	local base = 768 * CONSOLE_MIN_ASPECT
	local full = math.max(base, (Layout.CONSOLE_FIXED + Layout.CHAT_W) * self:LayoutOptions().s)
	local p = math.max(0, math.min(100, tonumber(self.db.consoleOpts.chatWiden) or 0)) / 100
	return base + (full - base) * p
end

-- UIParent units per console unit.
function ns:ConsoleScale()
	return math.min(UIParent:GetHeight() / 768, UIParent:GetWidth() / self:ConsoleMinWidth())
end

-- Whether the top bar is shown ("Hide top bar" in the menu). Without it,
-- the top bar module still places Blizzard's micro buttons, on the console.
function ns:TopBarShown()
	return not self.db.consoleOpts.hideTopBar
end

-- Shows or hides the top bar; buffs still where we put them move up or
-- down with it (through the Edit Mode layouts, so that asks for a reload).
function ns:SetTopBarShown(on)
	self.db.consoleOpts.hideTopBar = not on
	self:Relayout()
	self:RunOutOfCombat("edit-mode", function() self:SetupEditMode() end)
	local config = self.modules.config
	if config.frame then
		config:Refresh()
	end
end

function ns:Relayout()
	self:RunOutOfCombat("relayout", function()
		local root = self.root
		local scale = self:ConsoleScale()
		root:SetScale(scale)
		local W = UIParent:GetWidth() / scale
		root:ClearAllPoints()
		root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		root:SetSize(W, UIParent:GetHeight() / scale)

		-- The top bar keeps Reforged UI's own scale setting (/rui scale).
		local topRoot = self.topRoot
		local topScale = self.db.scale * UIParent:GetHeight() / 768
		topRoot:SetScale(topScale)
		local TW, TH = UIParent:GetWidth() / topScale, UIParent:GetHeight() / topScale
		topRoot:ClearAllPoints()
		topRoot:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		topRoot:SetSize(TW, TH)
		-- The top bar makes room beside its clock for Blizzard's micro
		-- buttons (TopBar.lua).
		local micro = self.TopBarMicroRatios and self:TopBarMicroRatios()
		self.topLayout = self.Layout.ComputeTopBar(TW, TH, self.db.layout, micro, self.theme and self.theme.folder)
		-- Hidden, the top bar stays hidden through pet battles too; its
		-- micro buttons go on the console instead.
		local shown = self:TopBarShown()
		if self.topRootShown ~= shown then
			self.topRootShown = shown
			RegisterStateDriver(topRoot, "visibility", shown and "[petbattle] hide; show" or "hide")
		end

		local opts = self:LayoutOptions()
		opts.micro = not shown and micro or nil
		local L = self.Layout.Compute(W, 768, opts)
		self.layout = L
		self:ForEachModule("OnLayout", L)
	end)
end

-- Companion addons (ReforgedUI_DamageMeter, listed separately in the addon
-- list so it can be left unloaded) follow the theme through this global.
ns.themeCallbacks = {}
ReforgedUI = {
	FONT = ns.FONT,
	-- SetFont(fs, size, flags): our font, with the game's fonts for Korean,
	-- Chinese and Cyrillic letters (Core.lua).
	SetFont = function(fs, size, flags)
		return ns:SetFont(fs, size, flags)
	end,
	-- The theme's key (also its art folder name) and its table (Themes.lua).
	GetTheme = function()
		return ns.themeKey, ns.theme
	end,
	-- fn(key, theme) runs now if a theme is set, and on every theme change.
	RegisterThemeCallback = function(fn)
		ns.themeCallbacks[#ns.themeCallbacks + 1] = fn
		if ns.ready and ns.theme then
			fn(ns.themeKey, ns.theme)
		end
	end,
}

function ns:ApplyTheme()
	self.themeKey = self:ResolveThemeKey(self.db.theme)
	self.theme = self.Themes[self.themeKey]
	self:ForEachModule("OnTheme", self.theme)
	for _, fn in ipairs(self.themeCallbacks) do
		local ok, err = pcall(fn, self.themeKey, self.theme)
		if not ok then
			geterrorhandler()(err)
		end
	end
	-- The original addon's pieces sit differently per theme.
	if self.ready then
		self:Relayout()
	end
end

----------------------------------------------------------------------------
-- Edit Mode repair

-- When addon code saves or switches Edit Mode layouts or sets the raid frame
-- options, Blizzard applies them in code that then counts as ours (tainted).
-- Its party and raid frames keep that until a reload and later fail on
-- secret values, e.g. when Edit Mode closes. So after any such change the
-- player is asked to reload.
local RELOAD_POPUP = "REFORGEDUI_RELOAD"
function ns:AskReload(why)
	local dialogs, show = _G.StaticPopupDialogs, _G.StaticPopup_Show
	if not (dialogs and show) then
		self:Print(why .. " /reload to finish.")
		return
	end
	dialogs[RELOAD_POPUP] = dialogs[RELOAD_POPUP] or {
		text = "Reforged UI: %s\n\nReload now so Blizzard's frames pick it up cleanly?",
		button1 = _G.RELOADUI or "Reload UI",
		button2 = _G.LATER or "Later",
		OnAccept = function() ReloadUI() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	self:RunOutOfCombat(RELOAD_POPUP, function() show(RELOAD_POPUP, why) end)
end

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
		ns:AskReload(("reset %d Edit Mode position(s) left over from an older version."):format(fixed))
	end
end

-- Edit Mode layout. Each character is switched once to an account-wide
-- "Reforged UI" layout, made (once) as a copy of the layout in use, with:
--  * the cast bar just above the console (its default place is under it, and
--    moving it from addon code breaks Blizzard's own, see Blizzard.lua);
--  * raid-style party frames, and the raid frames' options (class colours,
--    power bars, debuffs) turned on when the layout is made;
--  * Blizzard's target frame, buffs on top, placed so its aura icons (all
--    that is left visible of it, see Target.lua) stand beside the target of
--    target. Placed again at each login and target mode change, as it
--    follows the console's layout;
--  * buffs just below the top bar, debuffs under them (in every layout
--    where they are still in their default place).
-- It is all saved in the layout, so it is Edit Mode that applies it and
-- every piece can still be moved and changed there. A cast bar that is still
-- in its default place in any other layout of the player's own is raised too.
ns.EDIT_LAYOUT = "Reforged UI"
local CAST_BAR_GAP = 8
local RAID_CVARS = {
	raidFramesDisplayClassColor = "1", raidFramesDisplayPowerBars = "1",
	raidFramesDisplayOnlyHealerPowerBars = "0", raidFramesDisplayDebuffs = "1",
	raidFramesDisplayAggroHighlight = "1", raidFramesDisplayIncomingHeals = "1",
	raidOptionDisplayMainTankAndAssist = "1", raidFramesHealthText = "perc",
}

local function deepCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and deepCopy(v) or v
	end
	return out
end

local function setSetting(system, setting, value)
	if setting == nil then
		return
	end
	system.settings = system.settings or {}
	for _, entry in ipairs(system.settings) do
		if entry.setting == setting then
			entry.value = value
			return
		end
	end
	system.settings[#system.settings + 1] = { setting = setting, value = value }
end

local function findSystem(layout, system, index)
	for _, sys in ipairs(layout.systems or {}) do
		if sys.system == system and (index == nil or sys.systemIndex == index) then
			return sys
		end
	end
end

-- Moves a default-placed cast bar (not locked to the player frame) to `y`.
local function raiseCastBar(layout, y)
	local sys = findSystem(layout, Enum.EditModeSystem.CastBar)
	if not (sys and sys.isInDefaultPosition) then
		return false
	end
	local lock = Enum.EditModeCastBarSetting and Enum.EditModeCastBarSetting.LockToPlayerFrame
	for _, setting in ipairs(sys.settings or {}) do
		if lock and setting.setting == lock and setting.value == 1 then
			return false
		end
	end
	sys.anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = y }
	sys.isInDefaultPosition = false
	return true
end

-- Buffs start in the top-right corner just below the top bar (Blizzard's
-- default place is under it), or at the screen's top edge with the top bar
-- hidden; debuffs under the buffs. Placed in every
-- layout where they are still in their default place, or still where we
-- put them last (so a new top bar scale carries them along); once moved in
-- Edit Mode they are the player's.
local BUFF_GAP, BUFF_RIGHT = 6, 12

local function near(v, want)
	return type(v) == "number" and math.abs(v - want) <= 2
end

function ns:BuffSpot()
	local buffs = _G.BuffFrame
	if not (buffs and not forbidden(buffs) and self.topRoot and self.topLayout) then
		return nil
	end
	local s = self.topRoot:GetEffectiveScale() / buffs:GetEffectiveScale()
	local barH = self:TopBarShown() and self.topLayout.topBar.h or 0
	return { x = math.floor(-BUFF_RIGHT * s + 0.5), y = math.floor(-(barH + BUFF_GAP) * s + 0.5) }
end

local function placeBuffs(layout, spot, last)
	local sys, indices = Enum.EditModeSystem, Enum.EditModeAuraFrameSystemIndices
	local buffs = sys.AuraFrame and indices and findSystem(layout, sys.AuraFrame, indices.BuffFrame)
	if not (buffs and spot) then
		return false
	end
	local changed = false
	local a = buffs.anchorInfo or {}
	local atOurs = a.point == "TOPRIGHT" and (a.relativeTo == nil or a.relativeTo == "UIParent")
		and a.relativePoint == "TOPRIGHT"
	local ours = atOurs and last and near(a.offsetX, last.x) and near(a.offsetY, last.y)
	local inPlace = atOurs and near(a.offsetX, spot.x) and near(a.offsetY, spot.y)
	if buffs.isInDefaultPosition or (ours and not inPlace) then
		buffs.anchorInfo = { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT",
			offsetX = spot.x, offsetY = spot.y }
		buffs.anchorInfo2 = nil
		buffs.isInDefaultPosition = false
		changed = true
	end
	local debuffs = findSystem(layout, sys.AuraFrame, indices.DebuffFrame)
	if debuffs and debuffs.isInDefaultPosition then
		debuffs.anchorInfo = { point = "TOPRIGHT", relativeTo = "BuffFrame", relativePoint = "BOTTOMRIGHT",
			offsetX = 0, offsetY = -BUFF_GAP }
		debuffs.anchorInfo2 = nil
		debuffs.isInDefaultPosition = false
		changed = true
	end
	return changed
end

local function setCVar(name, value)
	local cvars = _G.C_CVar
	local get = cvars and cvars.GetCVar or _G.GetCVar
	local set = cvars and cvars.SetCVar or _G.SetCVar
	if get and set and get(name) ~= nil then
		pcall(set, name, value)
	end
end

-- Blizzard puts the first aura icon's bottom-left corner this far from its
-- target frame's top-left corner when buffs are on top (TargetFrame.lua).
local TARGET_AURA_X, TARGET_AURA_Y = 5, -15

-- Places the target frame in `layout`; true if that changed it.
function ns:PlaceTargetAuras(layout)
	local frames, sys = Enum.EditModeUnitFrameSystemIndices, Enum.EditModeSystem
	local target = self.modules.target
	local spot = target and target.enabled and target:AuraSpot()
	local tf = frames and sys.UnitFrame and findSystem(layout, sys.UnitFrame, frames.Target)
	if not (spot and tf) then
		return false
	end
	local k = self:ConsoleScale()
	local scale = TargetFrame and TargetFrame:GetScale() or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	local x = math.floor(spot.x0 * k / scale - TARGET_AURA_X + 0.5)
	local y = math.floor(spot.y * k / scale - TARGET_AURA_Y + 0.5)
	-- The game hands saved offsets back rounded its own way, so a pixel or
	-- two either way counts as already in place (otherwise every login
	-- would save the layout again and ask for a reload).
	local a = tf.anchorInfo or {}
	local inPlace = a.point == "TOPLEFT" and (a.relativeTo == nil or a.relativeTo == "UIParent")
		and a.relativePoint == "BOTTOMLEFT" and near(a.offsetX, x) and near(a.offsetY, y)
		and not tf.isInDefaultPosition
	local changed = not inPlace
	if inPlace then
		x, y = a.offsetX, a.offsetY
	end
	tf.anchorInfo = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", offsetX = x, offsetY = y }
	tf.anchorInfo2 = nil
	tf.isInDefaultPosition = false
	local onTop = Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.BuffsOnTop
	if onTop then
		local set = false
		for _, entry in ipairs(tf.settings or {}) do
			set = set or (entry.setting == onTop and entry.value ~= 0 and entry.value ~= false)
		end
		changed = changed or not set
		setSetting(tf, onTop, 1)
	end
	return changed
end

-- With "Let Edit Mode place the action bars", bars 1-3 keep their buttons
-- and are only pre-placed (once) in our layout, over the console's grid
-- rows at about the grid's button size. After that they are the player's to
-- move, resize and reflow in Edit Mode.
local ACTION_BARS = {
	{ index = "MainBar", row = "main", frame = { "MainActionBar", "MainMenuBar" } },
	{ index = "Bar2", row = "bar2", frame = { "MultiBarBottomLeft" } },
	{ index = "Bar3", row = "bar3", frame = { "MultiBarBottomRight" } },
}
local BUTTON_SIZE = 45 -- an action button at 100% icon size
local BAR_PADDING = 8

function ns:PlaceActionBars(layout)
	local o, L = self.db.consoleOpts, self.layout
	local sys, indices = Enum.EditModeSystem, Enum.EditModeActionBarSystemIndices
	local settings = Enum.EditModeActionBarSetting
	if not (o.editModeBars and not o.barsPlaced and sys and sys.ActionBar and indices and L and L.bars) then
		return false
	end
	local changed = false
	for _, spec in ipairs(ACTION_BARS) do
		local entry = indices[spec.index] and findSystem(layout, sys.ActionBar, indices[spec.index])
		local row = L.bars[spec.row]
		local frame
		for _, name in ipairs(spec.frame) do
			frame = frame or _G[name]
		end
		if entry and row and row.xs and row.xs[1] then
			local u = frame and self:UnitsFor(frame) or self:ConsoleScale()
			entry.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
				offsetX = math.floor(row.xs[1] * u + 0.5), offsetY = math.floor(row.y * u + 0.5) }
			entry.anchorInfo2 = nil
			entry.isInDefaultPosition = false
			-- Icon size in 10% steps, near the grid's cells; padding 8 with
			-- the bar art and scrolling hidden and every slot shown (as a
			-- tester found fits). Layouts store sliders either as the value
			-- or as the step index from the minimum: the icon size tells which.
			if settings and settings.IconSize then
				local stored
				for _, s in ipairs(entry.settings or {}) do
					if s.setting == settings.IconSize then
						stored = s.value
					end
				end
				local indexed = stored ~= nil and stored <= 15
				local pct = math.max(50, math.min(200, math.floor(row.size * u / BUTTON_SIZE * 10 + 0.5) * 10))
				setSetting(entry, settings.IconSize, indexed and (pct - 50) / 10 or pct)
				setSetting(entry, settings.IconPadding, indexed and BAR_PADDING - 2 or BAR_PADDING)
			end
			if settings then
				setSetting(entry, settings.HideBarArt, 1)
				setSetting(entry, settings.HideBarScrolling, 1)
				setSetting(entry, settings.AlwaysShowButtons, 1)
			end
			changed = true
		end
	end
	return changed
end

function ns:SetupEditMode()
	local systems = Enum and Enum.EditModeSystem
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and systems and systems.CastBar
		and self.layout) then
		return
	end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
		return
	end
	-- The layout list starts with Blizzard's presets, which addons can't change.
	local presets, presetList = 2, nil
	local manager = _G.EditModePresetLayoutManager
	if manager and manager.GetCopyOfPresetLayouts then
		local okP, list = pcall(manager.GetCopyOfPresetLayouts, manager)
		if okP and type(list) == "table" then
			presets, presetList = #list, list
		end
	end

	local bar = _G.PlayerCastingBarFrame
	local scale = bar and bar:GetScale() or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	local castY = math.floor((self.layout.consoleTop * self:ConsoleScale() + CAST_BAR_GAP) / scale + 0.5)

	local index, made
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == ns.EDIT_LAYOUT then
			index = i
		end
	end
	if not index then
		local active = type(info.activeLayout) == "number" and info.activeLayout or 1
		local base = active > presets and info.layouts[active - presets] or (presetList and presetList[active])
		if type(base) == "table" and type(base.systems) == "table" then
			local layout = deepCopy(base)
			layout.layoutName = ns.EDIT_LAYOUT
			layout.layoutType = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
			local frames = Enum.EditModeUnitFrameSystemIndices
			local party = systems.UnitFrame and frames and findSystem(layout, systems.UnitFrame, frames.Party)
			if party and Enum.EditModeUnitFrameSetting then
				setSetting(party, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames, 1)
			end
			-- The cast bar always gets its place in our layout.
			local cast = findSystem(layout, systems.CastBar)
			if cast then
				cast.isInDefaultPosition = true
				setSetting(cast, Enum.EditModeCastBarSetting and Enum.EditModeCastBarSetting.LockToPlayerFrame, 0)
			end
			info.layouts[#info.layouts + 1] = layout
			index, made = #info.layouts, true
		end
	end

	local placed = index and self:PlaceTargetAuras(info.layouts[index])
	local barsPlaced = index and self:PlaceActionBars(info.layouts[index])
	placed = placed or barsPlaced

	local raised, buffsMoved = 0, 0
	local spot, last = self:BuffSpot(), self.db.consoleOpts.buffSpot
	for _, layout in ipairs(info.layouts) do
		if raiseCastBar(layout, castY) then
			raised = raised + 1
		end
		if placeBuffs(layout, spot, last or nil) then
			buffsMoved = buffsMoved + 1
		end
	end
	if (made or placed or raised > 0 or buffsMoved > 0) and not pcall(C_EditMode.SaveLayouts, info) then
		return
	end
	if spot then
		self.db.consoleOpts.buffSpot = spot
	end
	if barsPlaced then
		self.db.consoleOpts.barsPlaced = true
	end
	if made then
		for name, value in pairs(RAID_CVARS) do
			setCVar(name, value)
		end
	end

	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	local switched = self.db.consoleOpts.editLayout
	if index and not switched[key] and C_EditMode.SetActiveLayout
		and pcall(C_EditMode.SetActiveLayout, presets + index) then
		switched[key] = true
		self:AskReload(("switched to the %q Edit Mode layout (cast bar above the console, raid-style party"
			.. " frames). Pick another layout in Edit Mode any time."):format(ns.EDIT_LAYOUT))
	elseif raised > 0 then
		self:AskReload(("moved the cast bar above the console in %d Edit Mode layout(s)."):format(raised))
	elseif buffsMoved > 0 then
		self:AskReload(("placed your buffs below the top bar in %d Edit Mode layout(s); move them there as you"
			.. " like."):format(buffsMoved))
	elseif barsPlaced then
		self:AskReload(("placed action bars 1-3 over the console in the %q Edit Mode layout; move or resize"
			.. " them there as you like."):format(ns.EDIT_LAYOUT))
	elseif made or placed then
		self:AskReload("updated the target frame's place in the Edit Mode layout.")
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
	ns:SetupEditMode()

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
	ns:Print("commands (the console's own options are in its menu: the cogwheel in the chat area's bottom-right corner):")
	print("  /rui config  (open that menu)")
	print("  /rui theme auto||" .. table.concat(ns.THEME_ORDER, "||") .. "||skyborne  (auto: your race's theme)")
	print("  /rui feeds  (list data feeds, game panels and top bar slots)")
	print("  /rui slot <number> <feed or panel name>||none")
	print("  /rui scale 0.5-1.5  (top bar)")
	print("  /rui layout auto||16:9||21:9||32:9  (top bar)")
	print("  /rui topbar on||off  (off: the menu buttons stand above the minimap)")
	print("  /rui module <name> on||off  (console, hero, actionbars, minimap, chat, inventory, blizzard, target,"
		.. " topbar, config; needs /reload)")
	print("  /rui status")
	print("  /rui auras  (where your target's buff and debuff icons are)")
	print("  /rui font  (whether names in Korean, Chinese and Cyrillic get their fonts)")
	print("  /rui target swap||plate  (target display: on the hero screen, or a plate on the wall)")
	print("  /rui targetbar on||off||reset  (a movable target health bar: Shift-drag it, or move it in Edit Mode)")
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
	elseif cmd == "topbar" and (arg == "on" or arg == "off") then
		ns:SetTopBarShown(arg == "on")
		ns:Print("top bar:", arg)
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
	elseif cmd == "targetbar" and (arg == "on" or arg == "off" or arg == "reset") and ns.modules.target.enabled then
		local target = ns.modules.target
		if arg == "reset" then
			target:ResetBarSpot()
			ns:Print("target bar back in its first place.")
		else
			target:SetBarEnabled(arg == "on")
			ns:Print(arg == "on" and "target bar on: hold Shift and drag it, or move it in Edit Mode." or "target bar off.")
		end
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
	elseif cmd == "auras" and ns.modules.target.enabled then
		for _, line in ipairs(ns.modules.target:DescribeAuras()) do
			ns:Print(line)
		end
	elseif cmd == "font" then
		local hero = ns.modules.hero
		for _, line in ipairs(ns:DescribeFont(hero and hero.xp and hero.xp.name)) do
			ns:Print(line)
		end
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
