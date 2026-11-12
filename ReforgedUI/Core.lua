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
		pet = true,
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
		stopAnimation = false,
		hearthstone = {}, -- characters that already got the hearthstone placed
		targetMode = "swap", -- target display: swap (the hero screen shows the target) | plate
		targetBar = false, -- a movable target health and power bar, besides the target display
		targetBarPos = false, -- where it was dragged to ({ x, y } from the screen's centre)
		totBar = false, -- the same window for the target's target
		totBarPos = false, -- where it was dragged to ({ x, y } from the screen's centre)
		targetBarSize = 100, -- both bars' size, 100-200 %
		barsEnabled = {}, -- characters whose bars 2 and 3 (and up to 1.11, bar 8) were turned on once
		minimapBarMoved = {}, -- characters whose Action Bar 8 slots and keys moved to the minimap bar once
		editLayout = {}, -- characters switched to the Reforged UI Edit Mode layout once
		editModeBars = false, -- bars 1-3 stay on their Edit Mode bars, pre-placed once, not in the grid
		barsPlaced = false, -- those bars were pre-placed in the Reforged UI layout
		buffSpot = false, -- where the buffs were last placed in Edit Mode layouts ({ x, y })
		petSpot = false, -- where the pet bar was last placed in Edit Mode layouts ({ x, y })
		leaveSpot = false, -- where the leave vehicle button was last placed in Edit Mode layouts ({ x, y })
		spotKey = false, -- the shared settings those spots were placed for (EditSpotKey)
		editPlaced = {}, -- per Edit Mode layout: frames already moved out of their default place once
		transparency = 0, -- how see-through the console's art is, 0-100 %
		petIconSpot = false, -- where the player moved the pet's icon ({ x, y } in console units), or beside the target of target
		totemSpot = false, -- where the player moved the totem timers ({ x, y } in console units), or on the wall over the grid
		stanceSpot = false, -- where the player moved the stance buttons ({ x, y } in console units), or on the wall over the grid
		leaveStance = false, -- leave the stance buttons where Blizzard or another bar addon puts them (reload)
		hideStance = false, -- the stance buttons on the console are invisible and click-through (key bindings still work)
		chatWiden = 0, -- how much the console shrinks to widen the chat area on narrow screens, 0-100 %
		hideTopBar = false, -- no top bar: Blizzard's micro buttons stand on the minimap block instead
		clockSpot = false, -- where the time capsule was dragged to with the top bar hidden ({ x, y } in console units from the centre)
		uiSize = 100, -- the console and top bar at this share of their usual size, 70-100 %
		repFeed = "progress", -- what the reputation feed shows: name, standing, progress or next (right-click cycles)
		repBar = true, -- the watched faction's strip under the experience bar (a flatter bar to make room)
		targetAuraOwn = nil, -- true: the player moved the target frame (its aura icons) in Edit Mode
		targetAuraLast = nil, -- our last few places for the target frame in our Edit Mode layout ({ x, y }, newest first)
		targetAuraSize = false, -- the target's buff and debuff icons at this size, 100-200 % (false: as Edit Mode has them)
		targetBuffsFirst = false, -- the target's buffs in the bottom rows, on its portrait, and its debuffs after them
		themeTooltips = true, -- the game's tooltips in the theme's frame, like the damage meter (Tooltip.lua)
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
	if type(db.consoleOpts) == "table" then
		-- The minimap's addon compartment used to remember being open; it
		-- now always starts closed.
		db.consoleOpts.addonDrawerOpen = nil
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

-- Run a frame's lock again (after what it places by has changed).
function ns:Relock(frame)
	runLock(frame)
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
		repBar = o.repBar ~= false,
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

-- The "UI size" option (70-100 %) as a factor: the console and top bar
-- shrink by it, keeping their place at the bottom and top of the screen.
ns.UI_SIZE_MIN, ns.UI_SIZE_MAX = 70, 100

function ns:UISize()
	local p = math.floor(tonumber(self.db.consoleOpts.uiSize) or 100)
	return math.max(self.UI_SIZE_MIN, math.min(self.UI_SIZE_MAX, p)) / 100
end

-- UIParent units per console unit.
function ns:ConsoleScale()
	return math.min(UIParent:GetHeight() / 768, UIParent:GetWidth() / self:ConsoleMinWidth()) * self:UISize()
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

-- The watched faction's strip under the experience bar (the bar is a
-- little flatter while it's on).
function ns:SetRepBarShown(on)
	self.db.consoleOpts.repBar = on and true or false
	self:Relayout()
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

		-- The top bar keeps Reforged UI's own scale setting (/rui scale),
		-- times the "UI size" option.
		local topRoot = self.topRoot
		local topScale = self.db.scale * self:UISize() * UIParent:GetHeight() / 768
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
-- Reload popup (the Edit Mode layout itself is in EditMode.lua)

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
	ns:RepairEditModeLayouts()

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
	-- Another Edit Mode layout active: said a while after login, and when
	-- Edit Mode closes (where the player may have switched).
	local layoutChecked = false
	ns:On("PLAYER_ENTERING_WORLD", function()
		if not layoutChecked then
			layoutChecked = true
			C_Timer.After(5, function() ns:SayOtherEditLayout() end)
		end
	end)
	local editMode = _G.EditModeManagerFrame
	if editMode and editMode.HookScript then
		editMode:HookScript("OnHide", function()
			C_Timer.After(1, function() ns:SayOtherEditLayout() end)
		end)
	end
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
	print("  /rui size 70-100  (console and top bar, in %)")
	print("  /rui scale 0.5-1.5  (top bar)")
	print("  /rui layout auto||16:9||21:9||32:9  (top bar)")
	print("  /rui topbar on||off  (off: the menu buttons stand above the minimap)")
	print("  /rui clock reset  (put the time back above the minimap; with the top bar hidden, Shift-drag or Edit Mode moves it)")
	print("  /rui module <name> on||off  (console, hero, actionbars, minimap, chat, inventory, blizzard, target,"
		.. " pet, totems, topbar, config; needs /reload)")
	print("  /rui status")
	print("  /rui auras  (where your target's buff and debuff icons are)")
	print("  /rui auras reset  (put them back on the wall after moving the Target Frame in Edit Mode)")
	print("  /rui aurasize 100-200  (your target's buff and debuff icons on the wall, in %)")
	print("  /rui buffsfirst on||off  (your target's buffs on the bottom rows, its debuffs after them)")
	print("  /rui font  (whether names in Korean, Chinese and Cyrillic get their fonts)")
	print("  /rui target swap||plate  (target display: on the hero screen, or a plate on the wall)")
	print("  /rui pet reset  (put your pet's icon back beside the target of target; Shift-drag moves it)")
	print("  /rui totems reset  (put the totem timers back on the wall; Shift-drag or Edit Mode moves them)")
	print("  /rui totems  (what each totem slot reports and how its time is shown)")
	print("  /rui stance reset  (put the stance buttons back on the wall; drag them in Edit Mode)")
	print("  /rui stance off||on  (off: leave the stance buttons to Blizzard or your bar addon; needs /reload)")
	print("  /rui stance hide||show  (hide the stance buttons on the console; their key bindings still work)")
	print("  /rui repbar on||off  (the watched faction's bar under the experience bar)")
	print("  /rui tooltips on||off  (tooltips in the theme's frame, like the damage meter)")
	print("  /rui targetbar on||off||reset  (a movable target health bar: Shift-drag it, or move it in Edit Mode)")
	print("  /rui totbar on||off||reset  (the same for the target's target)")
	print("  /rui barsize 100-200  (both bars' size, in %)")
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
	elseif cmd == "size" and tonumber(arg) then
		ns.db.consoleOpts.uiSize = math.max(ns.UI_SIZE_MIN, math.min(ns.UI_SIZE_MAX, math.floor(tonumber(arg))))
		ns:Relayout()
		ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
		ns:Print("UI size:", ns.db.consoleOpts.uiSize .. "%")
	elseif cmd == "aurasize" and tonumber(arg) and ns.modules.target.enabled then
		ns.db.consoleOpts.targetAuraSize = math.max(ns.TARGET_AURA_SIZE_MIN, math.min(ns.TARGET_AURA_SIZE_MAX,
			math.floor(tonumber(arg) / 5 + 0.5) * 5))
		ns:RunOutOfCombat("edit-mode", function() ns:SetupEditMode() end)
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
		ns:SayTargetAuraSize()
	elseif cmd == "buffsfirst" and (arg == "on" or arg == "off") and ns.modules.target.enabled then
		ns.modules.target:SetBuffsFirst(arg == "on")
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
		ns:Print(arg == "on" and "target buffs first, debuffs after them." or "target auras in the game's order.")
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
	elseif cmd == "clock" and arg == "reset" and ns.modules.topbar.enabled then
		ns.modules.topbar:ResetCapsuleSpot()
		ns:Print("time back above the minimap.")
	elseif cmd == "pet" and arg == "reset" and ns.modules.pet.enabled then
		ns.modules.pet:ResetSpot()
		ns:Print("pet icon back beside the target of target.")
	elseif cmd == "totems" and arg == "reset" and ns.modules.totems.enabled then
		ns.modules.totems:ResetSpot()
		ns:Print("totem timers back on the wall over the action bars.")
	elseif cmd == "totems" and ns.modules.totems.enabled then
		for _, line in ipairs(ns.modules.totems:Describe()) do
			ns:Print(line)
		end
	elseif cmd == "stance" and arg == "reset" and ns.modules.actionbars.enabled then
		ns.modules.actionbars:ResetStanceSpot()
		ns:Print("stance buttons back on the wall over the action bars.")
	elseif cmd == "stance" and (arg == "hide" or arg == "show") and ns.modules.actionbars.enabled then
		ns.modules.actionbars:SetStanceShown(arg == "show")
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
		ns:Print(arg == "hide" and "stance buttons hidden (their key bindings still work)." or "stance buttons shown.")
	elseif cmd == "stance" and (arg == "on" or arg == "off") then
		ns.db.consoleOpts.leaveStance = arg == "off"
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
		ns:AskReload(arg == "off" and "the stance buttons are left to Blizzard or your bar addon."
			or "the stance buttons go back on the console's wall.")
	elseif cmd == "repbar" and (arg == "on" or arg == "off") then
		ns:SetRepBarShown(arg == "on")
		ns:Print(arg == "on" and "reputation bar on, under the experience bar." or "reputation bar off.")
	elseif cmd == "tooltips" and (arg == "on" or arg == "off") and ns.modules.tooltip.enabled then
		ns.modules.tooltip:SetEnabled(arg == "on")
		ns:Print(arg == "on" and "tooltips in the theme's frame." or "tooltips as Blizzard draws them.")
	elseif (cmd == "targetbar" or cmd == "totbar") and (arg == "on" or arg == "off" or arg == "reset")
		and ns.modules.target.enabled then
		local target = ns.modules.target
		local v = cmd == "totbar" and target.totBar or target.bar
		local what = cmd == "totbar" and "target of target bar" or "target bar"
		if arg == "reset" then
			target:ResetBarSpot(v)
			ns:Print(what .. " back in its first place.")
		else
			target:SetBarEnabled(arg == "on", v)
			ns:Print(arg == "on" and what .. " on: hold Shift and drag it, or move it in Edit Mode." or what .. " off.")
		end
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
	elseif cmd == "barsize" and tonumber(arg) and ns.modules.target.enabled then
		local pct = ns.modules.target:SetBarSize(tonumber(arg))
		ns:Print(("target bars at %d%%."):format(pct))
		if ns.modules.config.frame then
			ns.modules.config:Refresh()
		end
	elseif cmd == "auras" and arg == "reset" and ns.modules.target.enabled then
		ns.db.consoleOpts.targetAuraOwn, ns.db.consoleOpts.targetAuraLast = nil, nil
		ns:RunOutOfCombat("target-auras", function()
			ns:SetupEditMode(("the target's buffs and debuffs go back %s once the UI reloads."):format(
				ns.modules.target:AuraSpotName()))
		end)
		ns:Print("target buffs and debuffs: back to their place on the wall.")
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
