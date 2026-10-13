-- Our own target display, in one of two modes (db.consoleOpts.targetMode):
--
--  * "swap" (the default), as selecting a unit in Warcraft III: while you
--    have a target the hero screen shows it - its portrait in the arch, its
--    name and level line over the experience bar, and its health and power
--    bars, your combo points and its cast bar in place of the stat icons.
--    The small bars under the portrait stay yours.
--  * "plate": a small copy of the portrait arch stands on the wall above the
--    stats panel with the target in it, a name plate beside it.
--
-- In both, the target's target is a small unit icon on the wall above the
-- portrait. Clicks go to our own secure unit buttons: left-click targets the
-- unit, right-click opens its menu. Their visibility follows the units
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
	player = { 0.25, 0.55, 1 }, -- the target of target is you
}
local TAPPED = { 0.6, 0.6, 0.6 }
local CLASSIFICATION = {
	elite = ELITE or "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = BOSS or "Boss",
}

local function font(fs, size)
	if not fs:SetFont(ns.FONT, size, "") then
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
local function infoText(unit)
	local ok, text = pcall(function()
		local level = UnitLevel(unit)
		local levelText = (level and level > 0) and tostring(level) or "??"
		local class = CLASSIFICATION[UnitClassification(unit) or ""]
		local kind
		if UnitIsPlayer(unit) then
			kind = (UnitClass(unit))
		else
			kind = UnitCreatureType(unit)
		end
		local parts = { LEVEL or "Level", levelText }
		parts[#parts + 1] = class
		parts[#parts + 1] = kind
		return table.concat(parts, " ")
	end)
	return ok and text or ""
end

-- "cur / max" for health and power; empty when the client will not say.
local function setPair(fs, cur, max)
	local ok = pcall(function()
		local abbr = AbbreviateLargeNumbers
		if abbr then
			fs:SetFormattedText("%s / %s", abbr(cur), abbr(max))
		else
			fs:SetFormattedText("%s / %s", cur, max)
		end
	end)
	if not ok then
		fs:SetText("")
	end
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

local function makeText(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	font(fs, size)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	fs:SetTextColor(1, 1, 1)
	return fs
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
	local f = CreateFrame("Frame", "ReforgedUITargetPlate", ns.root)
	f:SetFrameStrata("LOW")
	f:SetFrameLevel(10)
	f:SetAllPoints(ns.root)
	f:Hide()
	local v = { frame = f }
	-- Black behind the model, the model, then the arch over both.
	v.portraitBg = f:CreateTexture(nil, "BACKGROUND")
	v.portraitBg:SetTexture(ns:ArtPath("other\\black_background"))
	local model = CreateFrame("PlayerModel", nil, f)
	model:SetFrameLevel(11)
	model:SetScript("OnShow", function(m)
		m:SetUnit("target")
		if m.SetPortraitZoom then
			m:SetPortraitZoom(1)
		end
	end)
	v.model = model
	local art = CreateFrame("Frame", nil, f)
	art:SetFrameLevel(12)
	art:SetAllPoints(f)
	v.art = {}
	for i = 1, 2 do
		v.art[i] = art:CreateTexture(nil, "ARTWORK")
	end
	v.health = makeBar(f, 13)
	v.power = makeBar(f, 13)
	-- Name plate.
	local box = ns.Art.CreateInset(f, 12)
	v.box = box
	v.name = makeText(box, 13)
	v.info = makeText(box, 10)
	v.healthText = makeText(box, 10)
	v.powerText = makeText(box, 10, "RIGHT")
	v.combo = makeCombo(box)
	v.cast = makeCast(box, 14, 8)
	self.plate = v
end

function Target:CreateToT()
	local b = secureButton("ReforgedUITargetTarget", "targettarget", 32)
	-- Warcraft III unit icon: square portrait in a gold frame, a coloured
	-- glow behind it, a small health bar underneath.
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture(ns:ArtPath("other\\white_background"))
	b.portrait = b:CreateTexture(nil, "ARTWORK")
	b.portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture(ns:ArtPath("other\\golden_frame"))
	b.health = makeBar(b, 33)
	b.health:SetStatusBarColor(0.1, 0.9, 0.1)
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

function Target:OnEnable()
	ns:Conceal(TargetFrame)
	ns:Conceal(TargetFrameToT)

	self:CreateSwap()
	self:CreatePlate()
	-- Clicks on the target: over the hero's portrait in swap mode, over the
	-- plate in plate mode (above the hero's own player button).
	self.button = secureButton("ReforgedUITargetButton", "target", 30)
	self:CreateToT()

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
	unitEvent({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }, self.UpdateCast)
	ns:On("PLAYER_TARGET_CHANGED", function() self:Refresh() end)
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
		v.model:SetUnit("target")
		if v.model.SetPortraitZoom then
			v.model:SetPortraitZoom(1)
		end
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
	if tapped then
		v.health:SetStatusBarColor(unpack(TAPPED))
	else
		v.health:SetStatusBarColor(0.1, 0.85, 0.1)
	end
	setPair(v.healthText, cur, max)
	if v == self.plate then
		v.healthText:SetTextColor(0.25, 1, 0.25)
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
	setPair(v.powerText, cur, max)
	if v == self.plate then
		-- Blue text is hard to read on the dark plate: lighten it.
		v.powerText:SetTextColor(0.5 + r / 2, 0.5 + g / 2, 0.5 + b / 2)
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

-- Target of target: portrait, health and a tint for who it is: blue for
-- you, else green, yellow or red by reaction.
function Target:UpdateToT()
	local tot = self.tot
	if not UnitExists("targettarget") then
		return
	end
	SetPortraitTexture(tot.portrait, "targettarget")
	local isMe = UnitIsUnit and UnitIsUnit("targettarget", "player")
	local kind = isMe and "player" or reactionKind("targettarget")
	tot.kind = kind
	local c = REACTION[kind]
	tot.glow:SetVertexColor(c[1], c[2], c[3], 0.9)
	tot.border:SetVertexColor(1, 1, 1, 1)
	tot.health:SetMinMaxValues(0, UnitHealthMax("targettarget"))
	tot.health:SetValue(UnitHealth("targettarget"))
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
		local P = L.targetPlate
		place(b, { x = P.arch.x, y = P.arch.y, w = P.box.x + P.box.w - P.arch.x, h = P.top - P.arch.y })
	end
	place(self.tot, L.tot.frame)
end

function Target:OnTheme()
	if self.plate then
		ns.Art.PaintInset(self.plate.box, ns.theme)
	end
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
	for i, piece in ipairs(P.pieces) do
		local t = pl.art[i]
		t:SetTexture(ns:ArtPath(piece.file))
		t:SetTexCoord(piece.tc[1], piece.tc[2], piece.tc[3], piece.tc[4])
		place(t, piece.rect)
	end
	place(pl.portraitBg, P.portraitBg)
	place(pl.model, P.portrait)
	place(pl.health, P.health)
	place(pl.power, P.power)
	place(pl.box, P.box)
	ns.Art.PaintInset(pl.box, ns.theme)
	place(pl.name, P.name)
	place(pl.info, P.info)
	place(pl.healthText, P.healthText)
	place(pl.powerText, P.powerText)
	placeCombo(pl.combo, P.combo)
	place(pl.cast, P.cast)

	local T, tot = L.tot, self.tot
	place(tot.glow, { x = T.icon.x - 2, y = T.icon.y - 2, w = T.icon.w + 4, h = T.icon.h + 4 })
	place(tot.portrait, T.icon)
	place(tot.border, T.icon)
	place(tot.health, T.health)

	ns:RunOutOfCombat("target-buttons", function() self:PlaceButtons() end)
	self:Refresh()
end
