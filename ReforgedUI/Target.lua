-- Our own target display, in one of two modes (db.consoleOpts.targetMode):
--
--  * "swap" (the default), as selecting a unit in Warcraft III: while you
--    have a target the hero screen shows it - its portrait in the arch, its
--    name and level line over the experience bar, and its health and power
--    bars, your combo points and its cast bar in place of the stat icons.
--    The small bars under the portrait stay yours.
--  * "plate": a miniature hero screen stands on the wall above the stats
--    panel: the target's portrait in an arch with its health and power bars
--    in the arch's foot, and an info window with its name over a small level
--    plate, combo points and cast bar. One texture per theme
--    (Layout.TARGET_ART); the level plate and bars are the hero screen's own
--    (Hero.CreateLevelPlate, Hero.MakeBar).
--
-- Optionally, in either mode, a small target bar (name, level, health and
-- power) stands on its own where the player drags it (see "The target bar").
--
-- In both, the target's target is a small unit icon in the theme's trim on
-- the wall above the portrait (your pet's, Pet.lua, stands beside it), and
-- the target's buffs and debuffs (Blizzard's own icons, see below) beside
-- it, above the plate in plate mode. Clicks go to our own secure unit
-- buttons: left-click targets the unit, right-click opens its menu. Their visibility follows the units
-- through RegisterUnitWatch, so nothing secure is shown, hidden or moved in
-- combat; the swap itself only changes non-secure visuals.
--
-- Health and power can be "secret" values: they go straight into status bars,
-- text is formatted under pcall and they are never compared. Blizzard's
-- target frame and its target-of-target frame are made invisible.

local _, ns = ...
local Target = ns:RegisterModule("target", {})

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local MAX_COMBO = 5
Target.MODES = { "swap", "plate" }

local REACTION = {
	hostile = { 1, 0.2, 0.15 },
	neutral = { 1, 0.9, 0 },
	friendly = { 0.2, 1, 0.2 },
}
local TAPPED = { 0.6, 0.6, 0.6 }
local CLASSIFICATION = {
	elite = ELITE or "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = BOSS or "Boss",
}

local isSecret = issecretvalue or function() return false end

local function font(fs, size)
	if not ns:SetFont(fs, size) then
		fs:SetFontObject("GameFontHighlightSmall")
	end
end

local function place(region, r)
	ns.modules.console.Place(region, r)
end

----------------------------------------------------------------------------
-- Unit information (every call that may see a secret value is guarded)

-- "hostile", "neutral" or "friendly", as the unit stands to the player.
local function reactionKind(unit)
	local ok, kind = pcall(function()
		local r = UnitReaction(unit, "player")
		if r then
			return (r >= 5 and "friendly") or (r == 4 and "neutral") or "hostile"
		end
		if UnitCanAttack and UnitCanAttack("player", unit) then
			return "hostile"
		end
		return "friendly"
	end)
	return ok and kind or "neutral"
end
Target.ReactionKind = reactionKind

-- Name colour: class colour for players, grey when tapped by others, else
-- red, yellow or green by reaction.
local function nameColor(unit)
	local ok, r, g, b = pcall(function()
		if UnitIsPlayer(unit) then
			local _, classFile = UnitClass(unit)
			local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
			if c and c.r then
				return c.r, c.g, c.b
			end
		elseif UnitIsTapDenied and UnitIsTapDenied(unit) then
			return unpack(TAPPED)
		end
		return unpack(REACTION[reactionKind(unit)])
	end)
	if ok and r then
		return r, g, b
	end
	return unpack(REACTION.neutral)
end

-- "Level 12 Elite Humanoid", "Level ?? Boss Dragonkin", "Level 60 Warrior".
-- In instances any part can be secret: a part that can't be read is left
-- out (a secret level reads "??"), the rest still shows.
local function infoText(unit)
	local levelText = "??"
	pcall(function()
		local level = UnitLevel(unit)
		if not isSecret(level) and level and level > 0 then
			levelText = tostring(level)
		end
	end)
	local text = (LEVEL or "Level") .. " " .. levelText
	pcall(function()
		local class = CLASSIFICATION[UnitClassification(unit) or ""]
		if class then
			text = text .. " " .. class
		end
	end)
	pcall(function()
		local kind
		if UnitIsPlayer(unit) then
			kind = (UnitClass(unit))
		else
			kind = UnitCreatureType(unit)
		end
		if isSecret(kind) or kind then
			text = text .. " " .. kind
		end
	end)
	return text
end

-- 950, 12.3k, 123k, 1.2m: plain numbers only (secret ones are left to the
-- client's AbbreviateLargeNumbers).
local function short(n)
	if n >= 1e8 then
		return ("%dm"):format(n / 1e6)
	elseif n >= 1e6 then
		return ("%.1fm"):format(n / 1e6)
	elseif n >= 1e5 then
		return ("%dk"):format(n / 1e3)
	elseif n >= 1e4 then
		return ("%.1fk"):format(n / 1e3)
	end
	return tostring(n)
end

local function abbreviate(v)
	if type(v) == "number" and not isSecret(v) then
		return short(v)
	end
	return AbbreviateLargeNumbers and AbbreviateLargeNumbers(v) or v
end

-- "cur / max" for health and power; empty when the client will not say.
local function setPair(fs, cur, max)
	local ok = pcall(function()
		fs:SetFormattedText("%s / %s", abbreviate(cur), abbreviate(max))
	end)
	if not ok then
		fs:SetText("")
	end
end

local MIN_PAIR_SIZE = 6

-- setPair, then shrink the font until the text fits its width: never "...".
-- When the width cannot be measured (secret text), the smallest size.
local function fitPair(fs, cur, max)
	local path, size = fs:GetFont()
	fs.fitSize = fs.fitSize or size
	if path then
		ns:ResizeFont(fs, fs.fitSize)
	end
	setPair(fs, cur, max)
	local ok = pcall(function()
		local maxW = fs:GetWidth()
		local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
		size = fs.fitSize
		while measure(fs) > maxW and size > MIN_PAIR_SIZE do
			size = size - 1
			ns:ResizeFont(fs, size)
		end
	end)
	if not ok and path then
		ns:ResizeFont(fs, MIN_PAIR_SIZE)
	end
end

-- Whether the unit has no power bar (a maximum of 0). Unknown, as when the
-- value is secret, counts as having one.
local function noPower(max)
	if isSecret(max) then
		return false
	end
	local ok, none = pcall(function() return max == 0 end)
	return ok and none or false
end

local function comboPoints()
	if GetComboPoints then
		return GetComboPoints("player", "target")
	end
	local enum = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
	return enum and UnitPower("player", enum) or 0
end

----------------------------------------------------------------------------
-- Building blocks

local function makeBar(parent, level, textSize)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetFrameLevel(level)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)
	if textSize then
		bar.text = bar:CreateFontString(nil, "OVERLAY")
		font(bar.text, textSize)
		bar.text:SetPoint("CENTER")
		bar.text:SetTextColor(1, 1, 1)
		bar.text:SetWordWrap(false)
	end
	return bar
end

-- Five gold diamonds on dark sockets.
local function makeCombo(parent)
	local pips = {}
	for i = 1, MAX_COMBO do
		local socket = parent:CreateTexture(nil, "ARTWORK")
		socket:SetColorTexture(0, 0, 0, 0.8)
		local gem = parent:CreateTexture(nil, "OVERLAY")
		gem:SetColorTexture(1, 0.78, 0.1, 1)
		if socket.SetRotation then
			socket:SetRotation(math.pi / 4)
			gem:SetRotation(math.pi / 4)
		end
		pips[i] = { socket = socket, gem = gem }
	end
	return pips
end

local function placeCombo(pips, c)
	for i, pip in ipairs(pips) do
		local x = c.x + (i - 1) * c.step
		place(pip.socket, { x = x - 1, y = c.y - 1, w = c.size + 2, h = c.size + 2 })
		place(pip.gem, { x = x + 1, y = c.y + 1, w = c.size - 2, h = c.size - 2 })
	end
end

-- The target's cast bar: spell name inside, gold while casting, green while
-- channelling.
local function makeCast(parent, level, textSize)
	local bar = makeBar(parent, level, textSize)
	bar:Hide()
	bar:SetScript("OnUpdate", function(b)
		if not b.finish then
			return
		end
		local now = GetTime()
		if now >= b.finish then
			b:Hide()
			return
		end
		b:SetValue(b.channel and (b.finish - now) or (now - b.start))
	end)
	return bar
end

local function secureButton(name, unit, level)
	local b = CreateFrame("Button", name, ns.root, "SecureUnitButtonTemplate")
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(level)
	b:SetAttribute("unit", unit)
	b:SetAttribute("*type1", "target")
	b:SetAttribute("*type2", "togglemenu")
	b:RegisterForClicks("AnyUp")
	b.unit = unit
	b:SetScript("OnEnter", function(f)
		GameTooltip_SetDefaultAnchor(GameTooltip, f)
		GameTooltip:SetUnit(f.unit)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	RegisterUnitWatch(b)
	return b
end

----------------------------------------------------------------------------

function Target:Mode()
	return ns.db.consoleOpts.targetMode == "plate" and "plate" or "swap"
end

function Target:SetMode(mode)
	ns.db.consoleOpts.targetMode = mode == "plate" and "plate" or "swap"
	ns:RunOutOfCombat("target-buttons", function() self:PlaceButtons() end)
	-- Blizzard's aura icons follow, through the Edit Mode layout.
	ns:RunOutOfCombat("target-auras", function() ns:SetupEditMode() end)
	self:Refresh()
end

function Target:CreateSwap()
	-- The bars and cast bar that replace the stat icons; name, level line
	-- and portrait are the hero screen's own.
	local f = CreateFrame("Frame", nil, ns.root)
	f:SetFrameStrata("LOW")
	f:SetFrameLevel(10)
	f:SetAllPoints(ns.root)
	f:Hide()
	local v = { frame = f }
	v.health = makeBar(f, 11, 11)
	v.power = makeBar(f, 11, 10)
	v.healthText, v.powerText = v.health.text, v.power.text
	v.combo = makeCombo(f)
	v.cast = makeCast(f, 11, 9)
	self.swap = v
end

function Target:CreatePlate()
	local hero = ns.modules.hero
	local f = CreateFrame("Frame", "ReforgedUITargetPlate", ns.root)
	f:SetFrameStrata("LOW")
	f:SetFrameLevel(10)
	f:SetAllPoints(ns.root)
	f:Hide()
	local v = { frame = f }
	-- Black behind the model, the model, then the plate over both: the arch
	-- window shapes the portrait, as on the hero screen.
	v.portraitBg = f:CreateTexture(nil, "BACKGROUND")
	v.portraitBg:SetTexture(ns:ArtPath("other\\black_background"))
	v.flatPortrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	v.flatPortrait:Hide()
	local model = CreateFrame("PlayerModel", nil, f)
	model:SetFrameLevel(11)
	model:SetScript("OnShow", function(m)
		ns:SetUnitModel(m, v.flatPortrait, "target")
	end)
	v.model = model
	local art = CreateFrame("Frame", nil, f)
	art:SetFrameLevel(12)
	art:SetAllPoints(f)
	v.art = art:CreateTexture(nil, "ARTWORK")
	-- Over the plate: the hero screen's bars in the arch's foot, its level
	-- plate in the info window, combo points and cast bar under it.
	local top = CreateFrame("Frame", nil, f)
	top:SetFrameLevel(13)
	top:SetAllPoints(f)
	v.health = hero.MakeBar(top, 14, 9)
	v.power = hero.MakeBar(top, 14, 9)
	v.healthText, v.powerText = v.health.text, v.power.text
	for _, fs in ipairs({ v.healthText, v.powerText }) do
		fs:SetJustifyH("CENTER")
		fs:SetWordWrap(false)
	end
	v.plate = hero.CreateLevelPlate(top, 13, 10)
	v.plate.bar:Hide() -- no experience fill for a target
	v.name, v.info = v.plate.name, v.plate.level
	v.combo = makeCombo(top)
	v.cast = makeCast(top, 15, 8)
	self.plate = v
end

-- A Warcraft III unit icon on a secure unit button (target of target,
-- pet): a square portrait over a small health bar (and a power bar), in the
-- theme's trim (Trim.lua, thinner than around a window). Its parts are placed relative to the button
-- (PlaceUnitIcon), so they move with it.
function Target.CreateUnitIcon(name, unit, level, power)
	local b = secureButton(name, unit, level)
	b.back = b:CreateTexture(nil, "BORDER")
	b.back:SetColorTexture(0, 0, 0, 1)
	b.portrait = b:CreateTexture(nil, "ARTWORK")
	b.portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)
	b.health = makeBar(b, level + 1)
	b.health:SetStatusBarColor(0.1, 0.9, 0.1)
	if power then
		b.power = makeBar(b, level + 1)
		b.power:SetStatusBarColor(0.2, 0.4, 1)
	end
	local holder = CreateFrame("Frame", nil, b)
	holder:SetFrameLevel(level + 2)
	holder:SetScale(ns.Layout.UNIT_TRIM_SCALE)
	holder:SetPoint("TOPLEFT", b.back, "TOPLEFT")
	holder:SetPoint("BOTTOMRIGHT", b.back, "BOTTOMRIGHT")
	b.trim = ReforgedUI.CreateTrim(holder)
	return b
end

-- Places a unit icon's parts from its layout `U` (Layout.lua's unitIcon).
function Target.PlaceUnitIcon(b, U)
	local o = U.frame
	local function at(region, r)
		region:ClearAllPoints()
		region:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", r.x - o.x, r.y - o.y)
		region:SetSize(math.max(r.w, 0.01), math.max(r.h, 0.01))
	end
	at(b.back, U.box)
	at(b.portrait, U.icon)
	at(b.health, U.health)
	if b.power and U.power then
		at(b.power, U.power)
	end
	b.trim:Paint()
end

function Target:CreateToT()
	local b = Target.CreateUnitIcon("ReforgedUITargetTarget", "targettarget", 32)
	-- The target's target has few events of its own; poll it while shown.
	local elapsed = 0
	b:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.2 then
			elapsed = 0
			self:UpdateToT()
		end
	end)
	b:HookScript("OnShow", function() self:UpdateToT() end)
	self.tot = b
end

----------------------------------------------------------------------------
-- Buffs and debuffs. In combat the client lets no addon read a target's
-- auras ("cannot be accessed when secret while tainted"), only Blizzard's
-- own code. So Blizzard's target frame stays, showing nothing but its aura
-- icons: its portrait, bars, art, cast bar and target of target are made
-- invisible, and the "Reforged UI" Edit Mode layout (Core.lua) places it,
-- buffs on top, so the icons stand on the wall beside the target of target
-- (above the plate in plate mode).

-- Where the first aura icon's bottom-left corner goes, in console units.
function Target:AuraSpot()
	local L = self.layout
	if not L then
		return nil
	end
	local T = L.targetAuras
	return (self:Mode() == "swap" and ns.modules.hero.enabled) and T.swap or T.plate
end

-- Blizzard's target frame keeps only its aura icons. Its named parts (cast
-- bar, target of target, combo points...) are hidden whole. The unnamed
-- frames it groups the rest in are not, as the aura icons live in one of
-- them on modern clients: only what they hold at login is hidden, their
-- textures and text and, frame by frame, everything inside. Aura buttons,
-- which are made as auras appear, stay visible.
local function isAuraButton(f)
	local name = f.GetName and f:GetName()
	if type(name) == "string" and (name:find("Buff%d") or name:find("Debuff%d")) then
		return true
	end
	return (f.Icon or f.icon) and (f.Cooldown or f.cooldown) and true or false
end

local hiddenByUs = {}
local function concealedByUs(f)
	return hiddenByUs[f] or false
end

local function keepAuras(frame, depth)
	for _, region in ipairs({ frame:GetRegions() }) do
		ns:ConcealRegion(region)
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if not isAuraButton(child) then
			if child:GetName() or depth >= 5 then
				ns:Conceal(child)
				hiddenByUs[child] = true
			else
				keepAuras(child, depth + 1)
				hiddenByUs[child] = "parts"
				ns:RunOutOfCombat(child, function()
					if child.EnableMouse then
						child:EnableMouse(false)
					end
				end)
			end
		end
	end
end

-- The target's name and the strip behind it, tinted by reaction (yellow
-- when neutral). Blizzard shows and recolours them on every target change,
-- and the name could come back past its hidden alpha, so they are hidden
-- outright, not only made clear.
local stripsHidden = {}
local function hideNameStrips(tf)
	local content = tf.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	for _, region in ipairs({ main and main.ReputationColor or false, tf.nameBackground or false,
		_G.TargetFrameNameBackground or false, main and main.Name or false, tf.name or false }) do
		if region and region.Hide then
			ns:ConcealRegion(region)
			region:Hide()
			if not stripsHidden[region] then
				stripsHidden[region] = true
				hooksecurefunc(region, "Show", region.Hide)
				if region.SetShown then
					hooksecurefunc(region, "SetShown", region.Hide)
				end
			end
		end
	end
end

function Target:KeepBlizzardAuras()
	local tf = TargetFrame
	if not tf then
		return
	end
	-- Again on each target change: parts Blizzard makes later get hidden too.
	keepAuras(tf, 1)
	hideNameStrips(tf)
	for _, f in ipairs({ tf.spellbar or _G.TargetFrameSpellBar, tf.totFrame or TargetFrameToT,
		_G.TargetFrameNumericalThreat }) do
		ns:Conceal(f)
	end
	-- Clicks go to our own target button; the aura icons keep theirs.
	ns:RunOutOfCombat("target-frame-mouse", function() tf:EnableMouse(false) end)
end

-- For /rui auras: where Blizzard's target frame and its aura icons are.
function Target:DescribeAuras()
	local function n(v)
		local ok, text = pcall(function() return ("%.0f"):format(v) end)
		return ok and text or "?"
	end
	local lines = {}
	local api = C_EditMode
	if api and api.GetLayouts then
		local ok, info = pcall(api.GetLayouts)
		if ok and type(info) == "table" then
			local presets = 2
			local manager = _G.EditModePresetLayoutManager
			if manager and manager.GetCopyOfPresetLayouts then
				local okP, list = pcall(manager.GetCopyOfPresetLayouts, manager)
				presets = okP and type(list) == "table" and #list or presets
			end
			local layout = (info.layouts or {})[(info.activeLayout or 0) - presets]
			lines[#lines + 1] = ("Edit Mode layout: %s (%s)"):format(tostring(info.activeLayout),
				layout and tostring(layout.layoutName) or "a preset")
		end
	end
	local tf = TargetFrame
	if not tf then
		lines[#lines + 1] = "no TargetFrame"
		return lines
	end
	lines[#lines + 1] = ("TargetFrame: shown %s, alpha %s, left %s, top %s, scale %s, buffs on top %s"):format(
		tostring(tf:IsShown()), n(tf:GetAlpha() * 100), n(tf:GetLeft()), n(tf:GetTop()), n(tf:GetScale() * 100),
		tostring(tf.buffsOnTop))
	local auras, kids = {}, {}
	for _, child in ipairs({ tf:GetChildren() }) do
		local name = child:GetName() or ("<" .. child:GetObjectType() .. ">")
		local by = concealedByUs(child)
		kids[#kids + 1] = ("%s%s%s"):format(name, child:IsShown() and "" or " (hidden)",
			by == "parts" and " (parts hidden)" or by and " (hidden by us)" or "")
	end
	local function scan(frame, path, depth)
		for i, child in ipairs({ frame:GetChildren() }) do
			local name = child:GetName() or (path .. "." .. i)
			if isAuraButton(child) then
				if child:IsShown() then
					auras[#auras + 1] = ("%s at %s,%s alpha %s"):format(name, n(child:GetLeft()), n(child:GetBottom()),
						n((child.GetEffectiveAlpha and child:GetEffectiveAlpha() or child:GetAlpha()) * 100))
				end
			elseif depth < 5 then
				scan(child, name, depth + 1)
			end
		end
	end
	scan(tf, "TargetFrame", 1)
	lines[#lines + 1] = ("children (%d): %s"):format(#kids, table.concat(kids, ", "))
	-- Anything of the frame still drawn, besides the aura icons.
	local drawn = {}
	local function regions(frame, path, depth)
		for i, region in ipairs({ frame:GetRegions() }) do
			if region:IsVisible() and region:GetAlpha() > 0 then
				drawn[#drawn + 1] = ("%s at %s,%s"):format(region:GetName() or (region.GetParentKey and region:GetParentKey()) or (path .. ":" .. i),
					n(region:GetLeft()), n(region:GetBottom()))
			end
		end
		for i, child in ipairs({ frame:GetChildren() }) do
			if depth < 5 and not isAuraButton(child) and child:IsVisible() and child:GetAlpha() > 0 then
				regions(child, child:GetName() or (path .. "." .. i), depth + 1)
			end
		end
	end
	regions(tf, "TargetFrame", 1)
	lines[#lines + 1] = ("still drawn (%d): %s"):format(#drawn, table.concat(drawn, ", ", 1, math.min(#drawn, 6)))
	lines[#lines + 1] = ("aura icons shown: %d%s"):format(#auras, #auras > 0 and (": " .. table.concat(auras, "; ", 1,
		math.min(#auras, 4))) or "")
	-- Out of combat the auras can be read, to tell "none" from "not drawn".
	local api2 = _G.C_UnitAuras
	if api2 and api2.GetAuraDataByIndex then
		local counts = {}
		for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
			local count = 0
			for i = 1, 40 do
				local ok, data = pcall(api2.GetAuraDataByIndex, "target", i, filter)
				if not ok then
					count = "unreadable"
					break
				elseif type(data) ~= "table" then
					break
				end
				count = count + 1
			end
			counts[#counts + 1] = filter:lower() .. " " .. tostring(count)
		end
		lines[#lines + 1] = "target has: " .. table.concat(counts, ", ")
	end
	for _, key in ipairs({ "auraPools", "buffPool", "debuffPool" }) do
		local pool = tf[key]
		if pool then
			local ok, active = pcall(function() return pool:GetNumActive() end)
			lines[#lines + 1] = ("%s: %s active"):format(key, ok and tostring(active) or "?")
		end
	end
	local spot, L = self:AuraSpot(), self.layout
	if spot and L then
		local k = ns:ConsoleScale()
		lines[#lines + 1] = ("wanted: first icon at %s,%s"):format(n(spot.x0 * k), n(spot.y * k))
	end
	return lines
end

function Target:OnEnable()
	self:KeepBlizzardAuras()

	self:CreateSwap()
	self:CreatePlate()
	-- Clicks on the target: over the hero's portrait in swap mode, over the
	-- plate in plate mode (above the hero's own player button).
	self.button = secureButton("ReforgedUITargetButton", "target", 30)
	self:CreateToT()
	self:CreateBar()

	local function unitEvent(events, fn)
		for _, e in ipairs(events) do
			ns:On(e, function(_, unit)
				if unit == "target" then
					fn(self)
				end
			end)
		end
	end
	unitEvent({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }, self.UpdateHealth)
	unitEvent({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }, self.UpdatePower)
	unitEvent({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED" }, self.UpdateName)
	unitEvent({ "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE" }, self.UpdateModel)
	unitEvent({ "UNIT_TARGET" }, self.UpdateToT)
	unitEvent({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION" }, self.UpdateBar)
	unitEvent({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }, self.UpdateCast)
	ns:On("PLAYER_TARGET_CHANGED", function()
		self:KeepBlizzardAuras()
		self:Refresh()
	end)
	ns:On("PLAYER_COMBO_POINTS", function() self:UpdateCombo() end)
	ns:On("UNIT_POWER_UPDATE", function(_, unit)
		if unit == "player" then self:UpdateCombo() end
	end)
end

-- The view that shows the target now (nil without a target).
function Target:View()
	return self.active
end

-- Switch between the player's hero screen, the swapped one and the plate.
-- Runs on PLAYER_TARGET_CHANGED, in combat too: touches no secure frame.
function Target:Refresh()
	local hero = ns.modules.hero
	local has = UnitExists("target") and true or false
	local swap = self:Mode() == "swap" and hero.enabled
	local active
	if has then
		active = swap and self.swap or self.plate
	end
	self.active = active
	self:RefreshBar()
	self.swap.frame:SetShown(active == self.swap)
	self.plate.frame:SetShown(active == self.plate)
	if hero.enabled then
		local want = active == self.swap and "target" or "player"
		if want == "target" or hero.viewUnit ~= "player" then
			hero:SetView(want)
		end
	end
	if active then
		self:UpdateAll()
	end
end

function Target:UpdateAll()
	self:UpdateModel()
	self:UpdateName()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateCombo()
	self:UpdateCast()
	self:UpdateToT()
end

function Target:UpdateModel()
	local v = self:View()
	if not v then
		return
	end
	if v == self.swap then
		ns.modules.hero.RefreshModel()
	else
		v.model:ClearModel()
		ns:SetUnitModel(v.model, v.flatPortrait, "target")
	end
end

-- Name and level line: the hero screen's in swap mode, the plate's own.
function Target:UpdateName()
	local v = self:View()
	if not v then
		return
	end
	local name, info = v.name, v.info
	if v == self.swap then
		local xp = ns.modules.hero.xp
		name, info = xp.name, xp.level
	end
	ns:FitText(name, ns:FullName("target"))
	name:SetTextColor(nameColor("target"))
	ns:FitText(info, infoText("target"))
end

function Target:UpdateHealth()
	local v = self:View()
	if not v then
		return
	end
	local cur, max = UnitHealth("target"), UnitHealthMax("target")
	v.health:SetMinMaxValues(0, max)
	v.health:SetValue(cur)
	local tapped = UnitIsTapDenied and UnitIsTapDenied("target")
	if not isSecret(tapped) and tapped then
		v.health:SetStatusBarColor(unpack(TAPPED))
	elseif v == self.plate then
		v.health:SetStatusBarColor(0, 1, 0) -- the hero's green
	else
		v.health:SetStatusBarColor(0.1, 0.85, 0.1)
	end
	if v == self.plate then
		fitPair(v.healthText, cur, max)
	else
		setPair(v.healthText, cur, max)
	end
end

function Target:UpdatePower()
	local v = self:View()
	if not v then
		return
	end
	local ptype, token = UnitPowerType("target")
	local cur, max = UnitPower("target", ptype), UnitPowerMax("target", ptype)
	v.power:SetMinMaxValues(0, max)
	v.power:SetValue(cur)
	local r, g, b = 0.2, 0.4, 1
	local c = PowerBarColor and token and PowerBarColor[token]
	if token ~= "MANA" and c and c.r then
		r, g, b = c.r, c.g, c.b
	end
	v.power:SetStatusBarColor(r, g, b)
	if v == self.plate then
		-- The arch's second slot stays empty for units without power.
		v.power:SetShown(not noPower(max))
		fitPair(v.powerText, cur, max)
	else
		setPair(v.powerText, cur, max)
	end
end

-- Lit gems for the player's combo points; the row only shows with any.
function Target:UpdateCombo()
	local v = self:View()
	if not v then
		return
	end
	local ok = pcall(function()
		local n = comboPoints() or 0
		for i, pip in ipairs(v.combo) do
			pip.socket:SetShown(n > 0)
			pip.gem:SetShown(i <= n)
		end
	end)
	if not ok then
		for _, pip in ipairs(v.combo) do
			pip.socket:Hide()
			pip.gem:Hide()
		end
	end
end

function Target:UpdateCast()
	local v = self:View()
	if not v then
		return
	end
	local bar = v.cast
	local ok = pcall(function()
		local channel = false
		local name, _, _, startMS, endMS = UnitCastingInfo("target")
		if not name and UnitChannelInfo then
			name, _, _, startMS, endMS = UnitChannelInfo("target")
			channel = name ~= nil
		end
		if not name then
			bar.finish = nil
			bar:Hide()
			return
		end
		bar.start, bar.finish, bar.channel = startMS / 1000, endMS / 1000, channel
		bar:SetMinMaxValues(0, bar.finish - bar.start)
		bar:SetValue(channel and (bar.finish - GetTime()) or (GetTime() - bar.start))
		bar:SetStatusBarColor(channel and 0.2 or 1, channel and 0.85 or 0.7, channel and 0.2 or 0)
		if bar.text then
			bar.text:SetText(name)
		end
		bar:Show()
	end)
	if not ok then
		bar.finish = nil
		bar:Hide()
	end
end

-- Target of target: portrait and health.
function Target:UpdateToT()
	local tot = self.tot
	if not UnitExists("targettarget") then
		return
	end
	SetPortraitTexture(tot.portrait, "targettarget")
	tot.health:SetMinMaxValues(0, UnitHealthMax("targettarget"))
	tot.health:SetValue(UnitHealth("targettarget"))
end

----------------------------------------------------------------------------
-- The target bar (db.consoleOpts.targetBar, off by default): the target's
-- name, level, health and power in a small free-standing frame the player
-- can put anywhere, nearer the middle of the screen than the console's
-- target display. It is shown in both modes, beside that display. Not
-- secure, so it shows and hides in combat; it is click-through except while
-- Shift is held out of combat or Edit Mode is open, when it can be dragged
-- (in combat Shift is left to the player's own keybinds). Its place is
-- its own (db.consoleOpts.targetBarPos, from the screen's centre) and never
-- feeds the Edit Mode layout.

local BAR_W, BAR_NAME_H, BAR_HEALTH_H, BAR_POWER_H = 230, 16, 18, 10
local BAR_SPOT = { x = 0, y = -150 }
-- After the level, as on Blizzard's own target frames.
local BAR_CLASS = { elite = "+", rareelite = "R+", rare = "R", worldboss = "" }

function Target:CreateBar()
	local f = CreateFrame("Frame", "ReforgedUITargetBar", UIParent, "BackdropTemplate")
	f:SetFrameStrata("MEDIUM")
	f:SetSize(BAR_W, BAR_NAME_H + BAR_HEALTH_H + BAR_POWER_H + 12)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0, 0, 0, 0.7)
		f:SetBackdropBorderColor(0.8, 0.7, 0.4, 1)
	end
	f:Hide()
	local v = { frame = f }
	v.name = f:CreateFontString(nil, "OVERLAY")
	font(v.name, 12)
	v.name:SetJustifyH("LEFT")
	v.name:SetPoint("TOPLEFT", 6, -5)
	v.name:SetPoint("TOPRIGHT", -50, -5)
	v.name:SetHeight(BAR_NAME_H - 2)
	v.level = f:CreateFontString(nil, "OVERLAY")
	font(v.level, 11)
	v.level:SetJustifyH("RIGHT")
	v.level:SetPoint("TOPRIGHT", -6, -5)
	v.level:SetSize(44, BAR_NAME_H - 2)
	v.level:SetTextColor(1, 0.82, 0)
	v.health = makeBar(f, f:GetFrameLevel() + 1, 11)
	v.health:SetPoint("TOPLEFT", 5, -(BAR_NAME_H + 3))
	v.health:SetPoint("TOPRIGHT", -5, -(BAR_NAME_H + 3))
	v.health:SetHeight(BAR_HEALTH_H)
	v.power = makeBar(f, f:GetFrameLevel() + 1, 9)
	v.power:SetPoint("TOPLEFT", v.health, "BOTTOMLEFT", 0, -1)
	v.power:SetPoint("TOPRIGHT", v.health, "BOTTOMRIGHT", 0, -1)
	v.power:SetHeight(BAR_POWER_H)
	-- While it can be moved: Edit Mode's blue, and its name.
	v.highlight = f:CreateTexture(nil, "OVERLAY")
	v.highlight:SetAllPoints()
	v.highlight:SetColorTexture(0.25, 0.55, 1, 0.3)
	v.highlight:Hide()

	f:SetScript("OnDragStart", function(frame)
		frame.dragging = true
		frame:StartMoving()
	end)
	f:SetScript("OnDragStop", function(frame)
		frame.dragging = nil
		frame:StopMovingOrSizing()
		self:SaveBarSpot()
	end)
	-- Hidden mid-drag (Edit Mode closed, the target lost): end the drag here,
	-- or it would never let go of the mouse.
	f:SetScript("OnHide", function(frame)
		if frame.dragging then
			frame.dragging = nil
			frame:StopMovingOrSizing()
			self:SaveBarSpot()
			self:UpdateBarMouse()
		end
	end)
	f:SetScript("OnEnter", function(frame)
		GameTooltip_SetDefaultAnchor(GameTooltip, frame)
		GameTooltip:SetText("Reforged UI: target bar")
		GameTooltip:AddLine("Drag to move it. /rui targetbar reset puts it back.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	self.bar = v

	for _, e in ipairs({ "MODIFIER_STATE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		ns:On(e, function() self:UpdateBarMouse() end)
	end
	-- Shown and movable while Edit Mode is open, target or not.
	local editMode = _G.EditModeManagerFrame
	if editMode and editMode.HookScript then
		editMode:HookScript("OnShow", function() self:SetBarEditing(true) end)
		editMode:HookScript("OnHide", function() self:SetBarEditing(false) end)
	end
	self:PlaceBar()
end

function Target:BarEnabled()
	return self.bar and ns.db.consoleOpts.targetBar and true or false
end

function Target:SetBarEnabled(on)
	ns.db.consoleOpts.targetBar = on and true or false
	self:RefreshBar()
end

function Target:PlaceBar()
	local f, spot = self.bar.frame, ns.db.consoleOpts.targetBarPos
	if type(spot) ~= "table" or type(spot.x) ~= "number" or type(spot.y) ~= "number" then
		spot = BAR_SPOT
	end
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", spot.x, spot.y)
end

-- After a drag: kept as an offset from the screen's centre, so it stays put
-- through resolution and UI scale changes.
function Target:SaveBarSpot()
	local f = self.bar.frame
	local x, y = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if x and ux then
		local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
		ns.db.consoleOpts.targetBarPos = { x = math.floor(x * k - ux + 0.5), y = math.floor(y * k - uy + 0.5) }
	end
	if f.SetUserPlaced then
		f:SetUserPlaced(false) -- ours to save, not the client's layout cache
	end
	self:PlaceBar()
end

function Target:ResetBarSpot()
	ns.db.consoleOpts.targetBarPos = false
	self:PlaceBar()
end

function Target:SetBarEditing(on)
	self.barEditing = on and true or false
	self:RefreshBar()
end

-- Click-through unless it can be moved; never let go of in mid-drag.
function Target:UpdateBarMouse()
	local v = self.bar
	if not v then
		return
	end
	local shift = IsShiftKeyDown and IsShiftKeyDown() and not InCombatLockdown() and true or false
	local movable = self:BarEnabled() and (self.barEditing or shift)
	if movable or not v.frame.dragging then
		v.frame:EnableMouse(movable)
	end
	v.highlight:SetShown(movable and self.barEditing)
end

function Target:RefreshBar()
	local v = self.bar
	if not v then
		return
	end
	local has = UnitExists("target") and true or false
	local show = self:BarEnabled() and (has or self.barEditing)
	v.frame:SetShown(show)
	self:UpdateBarMouse()
	if not show then
		return
	end
	if has then
		self:UpdateBar()
	else
		-- Edit Mode without a target: a stand-in to place.
		v.name:SetText("Target")
		v.name:SetTextColor(1, 1, 1)
		v.level:SetText("")
		for _, bar in ipairs({ v.health, v.power }) do
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
			bar.text:SetText("")
			bar:Show()
		end
		v.health:SetStatusBarColor(0.1, 0.85, 0.1)
		v.power:SetStatusBarColor(0.2, 0.4, 1)
	end
end

-- At or under the options' HP warning threshold (red then, like the hero's
-- warning). Secret health can't be compared, so it never reads as low.
function Target:BarLow(cur, max)
	if isSecret(cur) or isSecret(max) then
		return false
	end
	local ok, low = pcall(function()
		return max > 0 and cur > 0 and cur / max <= (tonumber(ns.db.consoleOpts.hpWarning) or 25) / 100
	end)
	return ok and low or false
end

-- Name and level, health and power, all as guarded as the console's own.
function Target:UpdateBar()
	local v = self.bar
	if not (v and v.frame:IsShown() and UnitExists("target")) then
		return
	end
	ns:FitText(v.name, ns:FullName("target"))
	v.name:SetTextColor(nameColor("target"))
	local level = "??"
	pcall(function()
		local n = UnitLevel("target")
		if not isSecret(n) and n and n > 0 then
			level = tostring(n)
		end
	end)
	pcall(function()
		local class = BAR_CLASS[UnitClassification("target") or ""]
		if class then
			level = level .. class
		end
	end)
	v.level:SetText(level)

	local cur, max = UnitHealth("target"), UnitHealthMax("target")
	v.health:SetMinMaxValues(0, max)
	v.health:SetValue(cur)
	local tapped = UnitIsTapDenied and UnitIsTapDenied("target")
	if not isSecret(tapped) and tapped then
		v.health:SetStatusBarColor(unpack(TAPPED))
	elseif self:BarLow(cur, max) then
		v.health:SetStatusBarColor(0.9, 0.1, 0.1)
	else
		v.health:SetStatusBarColor(0.1, 0.85, 0.1)
	end
	setPair(v.health.text, cur, max)

	local ptype, token = UnitPowerType("target")
	local pcur, pmax = UnitPower("target", ptype), UnitPowerMax("target", ptype)
	v.power:SetMinMaxValues(0, pmax)
	v.power:SetValue(pcur)
	local r, g, b = 0.2, 0.4, 1
	local c = PowerBarColor and token and PowerBarColor[token]
	if token ~= "MANA" and c and c.r then
		r, g, b = c.r, c.g, c.b
	end
	v.power:SetStatusBarColor(r, g, b)
	v.power:SetShown(not noPower(pmax))
	setPair(v.power.text, pcur, pmax)
end

----------------------------------------------------------------------------
-- Layout

-- Secure frames: placed out of combat only (unit watches show and hide them).
function Target:PlaceButtons()
	local L = self.layout
	if not L then
		return
	end
	local b = self.button
	if self:Mode() == "swap" and ns.modules.hero.enabled then
		place(b, L.portrait)
	else
		place(b, L.targetPlate.frame)
	end
	place(self.tot, L.tot.frame)
end

function Target:OnLayout(L)
	self.layout = L
	local S = L.targetSwap
	local sw = self.swap
	place(sw.health, S.health)
	place(sw.power, S.power)
	placeCombo(sw.combo, S.combo)
	place(sw.cast, S.cast)

	local P, pl = L.targetPlate, self.plate
	pl.art:SetTexture(ns:ArtPath(P.file))
	place(pl.art, P.frame)
	place(pl.portraitBg, P.portraitBg)
	place(pl.model, P.portrait)
	place(pl.flatPortrait, P.portrait)
	place(pl.health, P.health)
	place(pl.power, P.power)
	-- The numbers fit their bar (fitPair measures against this width).
	for _, bar in ipairs({ pl.health, pl.power }) do
		local w = bar:GetWidth()
		if w then
			bar.text:SetWidth(math.max(1, w - 2))
		end
	end
	ns.modules.hero.PlaceLevelPlate(pl.plate, P.level)
	placeCombo(pl.combo, P.combo)
	place(pl.cast, P.cast)

	-- Its parts follow the button, which PlaceButtons places (out of combat).
	Target.PlaceUnitIcon(self.tot, L.tot)

	ns:RunOutOfCombat("target-buttons", function() self:PlaceButtons() end)
	self:Refresh()
end
