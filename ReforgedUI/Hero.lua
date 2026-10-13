-- The original addon's hero screen: the 3D portrait with health and power bars under it,
-- the experience bar with name and level, the four stat icons (damage,
-- block, spell or healing power, ammo, and armour) and the player's status
-- icons. All of these are our own frames: the original addon moved Blizzard's player
-- frame bars and icons, which on this client would taint the player frame.
--
-- Health and power can be "secret" values: they go straight into the status
-- bars, text is formatted under pcall and they are never compared (the low
-- health warning and the colour gradient only run when they are not secret).

local _, ns = ...
local Hero = ns:RegisterModule("hero", {})
-- The unit the hero screen shows: "player", or "target" while Target.lua's
-- swap mode shows the target (portrait, name and level, and its own bars in
-- place of the stat icons). The bars under the portrait stay the player's.
Hero.viewUnit = "player"

local floor, ceil = math.floor, math.ceil
local isSecret = issecretvalue or function() return false end

local GOLD = "|cffffd100"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FIST = "other\\fist"
local CAPE = "Interface\\Icons\\INV_Misc_Cape_10"

-- Stat icon choices (the original addon's ChangeWeaponIcon).
Hero.ICON_KINDS = { "main", "offhand", "ranged", "ammo", "spell", "heal", "none" }
Hero.ICON_LABELS = {
	main = "Main hand", offhand = "Offhand", ranged = "Ranged", ammo = "Ammo",
	spell = "Spell power", heal = "Healing", none = "None",
}
local SLOT = { main = 16, offhand = 17, ranged = 18, ammo = 0 }
local SCHOOLS = { "holy", "fire", "nature", "frost", "shadow", "arcane" }

-- Shapeshift forms that replace the weapon and armour icons, by form ID.
local FORM_ICONS = {
	[5] = { "Interface\\Icons\\INV_Misc_MonsterClaw_04", "Interface\\Icons\\Ability_Racial_BearForm" },
	[8] = { "dire", "Interface\\Icons\\Ability_Racial_BearForm" },
	[1] = { "Interface\\Icons\\Ability_Druid_Rake", "Interface\\Icons\\Ability_Druid_CatForm" },
	[4] = { "Interface\\Icons\\ABILITY_SEAL", "Interface\\Icons\\Ability_Druid_AquaticForm" },
	[3] = { "Interface\\Icons\\Spell_Shadow_VampiricAura", "Interface\\Icons\\Ability_Druid_TravelForm" },
	[16] = { "Interface\\Icons\\Ability_Hunter_Pet_Wolf", "Interface\\Icons\\Spell_Nature_SpiritWolf" },
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
-- Info box: the original addon's tooltip for the experience bar and the stat icons.

local function infoBox()
	local box = Hero.infoBox
	if not box then
		box = CreateFrame("Frame", "ReforgedUIInfoBox", UIParent, "BackdropTemplate")
		box:SetFrameStrata("TOOLTIP")
		box:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		box:SetBackdropColor(0, 0, 0, 0.75)
		box.text = box:CreateFontString(nil, "OVERLAY")
		font(box.text, 12)
		box.text:SetPoint("TOPLEFT", 12, -12)
		box.text:SetWidth(276)
		box.text:SetJustifyH("LEFT")
		box.text:SetJustifyV("TOP")
		box:SetWidth(300)
		box:Hide()
		Hero.infoBox = box
	end
	return box
end

local function showInfo(owner, build, dy)
	local ok, text = pcall(build)
	if not ok or not text or text == "" then
		return
	end
	local box = infoBox()
	box.text:SetText(text)
	box:SetHeight(box.text:GetStringHeight() + 24)
	box:ClearAllPoints()
	box:SetPoint("BOTTOM", owner, "TOP", 0, dy or 20)
	box:Show()
end

local function hideInfo()
	if Hero.infoBox then
		Hero.infoBox:Hide()
	end
end

----------------------------------------------------------------------------
-- Portrait

function Hero:CreatePortrait()
	local root = ns.root
	-- Black (or pulsing red) background behind the model, between the
	-- console's background and the portrait block (levels 2 and 3).
	local bgFrame = CreateFrame("Frame", nil, root)
	bgFrame:SetFrameStrata("BACKGROUND")
	bgFrame:SetFrameLevel(2)
	bgFrame:SetAllPoints(root)
	self.portraitBg = bgFrame:CreateTexture(nil, "BACKGROUND")
	self.portraitBg:SetTexture(ns:ArtPath("other\\black_background"))
	self.pulse = bgFrame

	local model = CreateFrame("PlayerModel", "ReforgedUIPortrait", root)
	model:SetFrameStrata("BACKGROUND")
	model:SetFrameLevel(3)
	self.model = model
	local function refresh()
		model:SetUnit(Hero.viewUnit)
		if model.SetPortraitZoom then
			model:SetPortraitZoom(1)
		end
		if ns.db.consoleOpts.stopAnimation and model.FreezeAnimation then
			pcall(model.FreezeAnimation, model, 0, 0, 0)
		end
	end
	model:SetScript("OnShow", refresh)
	ns:On("UNIT_MODEL_CHANGED", function(_, unit)
		if unit == Hero.viewUnit then refresh() end
	end)
	ns:On("PLAYER_ENTERING_WORLD", refresh)
	self.RefreshModel = refresh

	-- Left click targets yourself, right click opens your unit menu.
	local click = CreateFrame("Button", "ReforgedUIPortraitButton", root, "SecureUnitButtonTemplate")
	click:SetFrameStrata("LOW")
	click:SetAttribute("unit", "player")
	click:SetAttribute("*type1", "target")
	click:SetAttribute("*type2", "togglemenu")
	click:RegisterForClicks("AnyUp")
	self.click = click
end

-- The original addon's low health warning: the background pulses black to red.
function Hero:SetWarning(on)
	if on == self.warning then
		return
	end
	self.warning = on
	local bg = self.portraitBg
	if on then
		bg:SetTexture(ns:ArtPath("other\\white_background"))
		local value, rising = 0, true
		self.pulse:SetScript("OnUpdate", function(_, elapsed)
			value = value + (rising and elapsed or -elapsed)
			if value >= 1 then
				value, rising = 1, false
			elseif value <= 0 then
				value, rising = 0, true
			end
			bg:SetVertexColor(value, 0, 0, 1)
		end)
	else
		self.pulse:SetScript("OnUpdate", nil)
		bg:SetTexture(ns:ArtPath("other\\black_background"))
		bg:SetVertexColor(1, 1, 1, 1)
	end
end

----------------------------------------------------------------------------
-- Health and power

local function makeBar(parent, level, size)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetFrameStrata("LOW")
	bar:SetFrameLevel(level)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)
	bar.text = bar:CreateFontString(nil, "OVERLAY")
	font(bar.text, size)
	bar.text:SetPoint("CENTER")
	bar.text:SetTextColor(1, 1, 1)
	return bar
end

-- `percentFn` is the client's own percentage function (UnitHealthPercent,
-- UnitPowerPercent), which works on secret values; plain division otherwise.
local function setText(fs, cur, max, percent, percentFn)
	local ok = pcall(function()
		if percent then
			local p
			if percentFn and CurveConstants and CurveConstants.ScaleTo100 then
				p = percentFn("player", false, CurveConstants.ScaleTo100)
			else
				p = cur / max * 100
			end
			fs:SetFormattedText("%.0f%%", p)
		else
			fs:SetFormattedText("%s / %s", cur, max)
		end
	end)
	if not ok then
		fs:SetText("")
	end
end

function Hero:UpdateHealth()
	local cur, max = UnitHealth("player"), UnitHealthMax("player")
	local bar = self.health
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	setText(bar.text, cur, max, ns.db.consoleOpts.healthPercent, UnitHealthPercent)
	if isSecret(cur) or isSecret(max) then
		bar:SetStatusBarColor(0, 1, 0, 1)
		self:SetWarning(false)
		return
	end
	-- The original addon's gradient: green to yellow to red.
	local p = max > 0 and cur / max or 0
	if p < 0.5 then
		bar:SetStatusBarColor(1, 2 * p, 0, 1)
	else
		bar:SetStatusBarColor(2 * (1 - p), 1, 0, 1)
	end
	self:SetWarning(cur > 0 and p <= (tonumber(ns.db.consoleOpts.hpWarning) or 25) / 100)
end

local POWER_COLORS = { [0] = { 0, 0, 1 }, [1] = { 1, 0, 0 }, [3] = { 1, 1, 0 } }

function Hero:UpdatePower()
	local ptype, token = UnitPowerType("player")
	local cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
	local bar = self.power
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	setText(bar.text, cur, max, ns.db.consoleOpts.powerPercent, UnitPowerPercent and function(unit, ...)
		return UnitPowerPercent(unit, ptype, ...)
	end)
	local c = POWER_COLORS[ptype]
	if c then
		bar:SetStatusBarColor(c[1], c[2], c[3], 1)
	else
		local pc = PowerBarColor and (PowerBarColor[token] or PowerBarColor[ptype])
		if pc then
			bar:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
		end
	end
end

----------------------------------------------------------------------------
-- Experience bar

function Hero:CreateXP(holder)
	local xp = {}
	for i, key in ipairs({ "left", "middle", "right" }) do
		local t = holder:CreateTexture(nil, "OVERLAY")
		t:SetTexture(ns:ArtPath("other\\xp" .. i))
		xp[key] = t
	end
	xp.bar = holder:CreateTexture(nil, "ARTWORK")
	xp.bar:SetTexture(ns:ArtPath("other\\xpProgressBar"))
	xp.bar:SetVertexColor(0.5, 0, 0.5, 1)
	xp.rested = holder:CreateTexture(nil, "BORDER")
	xp.rested:SetTexture(ns:ArtPath("other\\xpProgressBar"))
	xp.name = holder:CreateFontString(nil, "OVERLAY")
	font(xp.name, 16)
	xp.name:SetTextColor(1, 1, 1)
	xp.level = holder:CreateFontString(nil, "OVERLAY")
	font(xp.level, 12)
	xp.level:SetTextColor(1, 1, 1)

	local hover = CreateFrame("Frame", nil, holder)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(f)
		if self.viewUnit ~= "player" then
			return
		end
		self.hovering = true
		self:UpdateXP()
		showInfo(f, function()
			local cur, max = UnitXP("player"), UnitXPMax("player")
			if max <= 0 then return nil end
			local pct = cur / max * 100
			return ("%sExperience required to level up:|r %d\n%sExperience until next level:|r %d (%.2f %%)\n"
				.. "%sCurrent Experience:|r %d (%.2f %%)\n%sRested Experience:|r %d"):format(
				GOLD, max, GOLD, max - cur, 100 - pct, GOLD, cur, pct, GOLD, GetXPExhaustion() or 0)
		end, 30)
	end)
	hover:SetScript("OnLeave", function()
		self.hovering = false
		self:UpdateXP()
		hideInfo()
	end)
	xp.hover = hover
	self.xp = xp
end

function Hero:UpdateXP()
	local xp, L = self.xp, ns.layout
	if not L then
		return
	end
	if self.viewUnit ~= "player" then
		-- The target's name and level are Target.lua's to write.
		xp.bar:Hide()
		xp.rested:Hide()
		return
	end
	xp.bar:Show()
	local full = L.xp.bar.w
	local cur, max = UnitXP("player"), UnitXPMax("player")
	local atMax = IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()
	local w, rested = 1, 1
	if atMax then
		w = full
	elseif max and max > 0 then
		w = math.max(1, full * cur / max)
		local ex = GetXPExhaustion() or 0
		if ex > 0 then
			rested = math.min(full, full * (cur + ex) / max)
		end
	end
	xp.bar:SetWidth(w)
	xp.rested:SetWidth(rested)
	local c = ns.db.consoleOpts.restedColor
	xp.rested:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 1, c[4] or 0.5)
	xp.rested:SetShown(not atMax and (c[4] or 0) > 0)

	xp.name:SetText(ns:FullName("player"))
	xp.name:SetTextColor(1, 1, 1)
	if self.hovering and not atMax then
		xp.level:SetFormattedText("XP %d / %d", cur, max)
	else
		xp.level:SetFormattedText("%s %d %s", LEVEL or "Level", UnitLevel("player"), (UnitClass("player")))
	end
end

----------------------------------------------------------------------------
-- Stat icons

local function rangedOrAmmo()
	local count = GetInventoryItemCount("player", 0) or 0
	local slot = 0
	if (GetInventoryItemCount("player", 18) or 0) > 1 then
		slot = 18 -- thrown weapons count themselves
		count = GetInventoryItemCount("player", 18)
	end
	return slot, count
end

local function spellPower()
	local best, by = 0, {}
	if GetSpellBonusDamage then
		for i, school in ipairs(SCHOOLS) do
			local v = GetSpellBonusDamage(i + 1) or 0
			by[school] = v
			best = math.max(best, v)
		end
	end
	return best, by
end

local function healing()
	return GetSpellBonusHealing and GetSpellBonusHealing() or 0
end

local function dmgText(lo, hi)
	local text = floor(lo) .. " - " .. ceil(hi)
	if #text >= 10 then
		text = floor(lo) .. " -\n " .. ceil(hi)
	end
	return text
end

-- Label, value and icon for a stat icon of kind `kind`.
local function statValues(kind)
	if kind == "main" then
		local lo, hi = UnitDamage("player")
		return "Damage:", dmgText(lo, hi), GetInventoryItemTexture("player", 16)
	elseif kind == "offhand" then
		local icon = GetInventoryItemTexture("player", 17)
		local isShield = C_PaperDollInfo and C_PaperDollInfo.OffhandHasShield and C_PaperDollInfo.OffhandHasShield()
		if isShield and GetBlockChance then
			local block = GetShieldBlock and GetShieldBlock()
			return "Block:", ("%.1f%%"):format(GetBlockChance()) .. (block and ("\n (" .. block .. ")") or ""), icon
		end
		if not icon then
			return "Damage:", "N/A", nil
		end
		local _, _, lo, hi = UnitDamage("player")
		return "Damage:", lo and dmgText(lo, hi) or "N/A", icon
	elseif kind == "ranged" then
		local icon = GetInventoryItemTexture("player", 18)
		if not icon then
			return "Damage:", "N/A", nil
		end
		local _, lo, hi = UnitRangedDamage("player")
		return "Damage:", dmgText(lo, hi), icon
	elseif kind == "ammo" then
		local slot, count = rangedOrAmmo()
		local icon = GetInventoryItemTexture("player", slot)
		if not icon then
			return "Ammo:", "|cffff0000No ammo|r", nil
		end
		local color = count < 200 and "|cffff0000" or count < 400 and "|cffffff00" or "|cffffffff"
		return "Ammo:", color .. count .. "|r", icon
	elseif kind == "spell" then
		return "Spell:", tostring((spellPower())), "Interface\\Icons\\INV_Staff_07"
	elseif kind == "heal" then
		return "Healing:", tostring(healing()), "Interface\\Icons\\Spell_Holy_Heal"
	end
end

local function attackInfo()
	local lo, hi, offLo, offHi = UnitDamage("player")
	local speed, offSpeed = UnitAttackSpeed("player")
	local text = ("%sMain Hand Damage:|r %d - %d\n%sAttack Speed:|r %.2f\n%sDamage per second:|r %.2f\n"):format(
		GOLD, floor(lo), ceil(hi), GOLD, speed, GOLD, (floor(lo) + ceil(hi)) / 2 / speed)
	if offSpeed and offLo then
		text = text .. ("\n%sOffhand damage:|r %d - %d\n%sAttack Speed:|r %.2f\n%sDamage per second:|r %.2f\n"):format(
			GOLD, floor(offLo), ceil(offHi), GOLD, offSpeed, GOLD, (floor(offLo) + ceil(offHi)) / 2 / offSpeed)
	end
	if GetInventoryItemTexture("player", 18) then
		local rSpeed, rLo, rHi = UnitRangedDamage("player")
		if rSpeed and rSpeed > 0 then
			text = text .. ("\n%sRanged damage:|r %d - %d\n%sAttack Speed:|r %.2f\n%sDamage per second:|r %.2f\n"):format(
				GOLD, floor(rLo), ceil(rHi), GOLD, rSpeed, GOLD, (floor(rLo) + ceil(rHi)) / 2 / rSpeed)
			local _, count = rangedOrAmmo()
			if count > 0 then
				text = text .. GOLD .. "Ammo left:|r " .. count .. "\n"
			end
		end
	end
	return text
end

local function statInfo(kind)
	if kind == "heal" then
		local sp, hp = spellPower(), healing()
		return ("%sHealing power:|r %d\n%sSpell power:|r %d\n"):format(GOLD, hp, GOLD, sp)
	elseif kind == "spell" then
		local sp, by = spellPower()
		local text = GOLD .. "Spell power:|r " .. sp .. "\n\n"
		for _, school in ipairs({ "arcane", "fire", "frost", "holy", "nature", "shadow" }) do
			text = text .. GOLD .. school:gsub("^%l", string.upper) .. ":|r " .. (by[school] or 0) .. "\n"
		end
		return text
	end
	return attackInfo()
end

local function armourText()
	local _, effective = UnitArmor("player")
	local level = UnitLevel("player")
	local dr
	if PaperDollFrame_GetArmorReduction then
		dr = PaperDollFrame_GetArmorReduction(effective, level)
	else
		dr = effective / (effective + 400 + 85 * level) * 100
	end
	return ("%.1f%%"):format(dr)
end

function Hero:CreateStatIcon(holder, index)
	local f = CreateFrame("Frame", nil, holder)
	f.index = index
	f:EnableMouse(true)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.frame = f:CreateTexture(nil, "OVERLAY")
	f.frame:SetAllPoints()
	f.frame:SetTexture(ns:ArtPath("other\\golden_frame"))
	f.label = holder:CreateFontString(nil, "OVERLAY")
	font(f.label, 10)
	f.label:SetJustifyH("LEFT")
	f.label:SetJustifyV("TOP")
	f.value = holder:CreateFontString(nil, "OVERLAY")
	font(f.value, 10)
	f.value:SetTextColor(1, 1, 1)
	f.value:SetJustifyH("LEFT")
	f.value:SetJustifyV("TOP")
	f:SetScript("OnEnter", function(frame)
		if frame.index == 4 then
			showInfo(self.xp.hover, function()
				local base, effective = UnitArmor("player")
				return ("%sArmor:|r %d (%d base)\n%sDamage reduction:|r %s"):format(GOLD, effective, base, GOLD, armourText())
			end, 50)
		elseif frame.kind and frame.kind ~= "none" then
			showInfo(self.xp.hover, function() return statInfo(frame.kind) end, 50)
		end
	end)
	f:SetScript("OnLeave", hideInfo)
	return f
end

-- The stat icon choices of this character's class.
function Hero:IconChoices()
	local _, class = UnitClass("player")
	local icons = ns.db.consoleOpts.icons
	class = class or "UNKNOWN"
	icons[class] = icons[class] or { "main", "none", "none" }
	return icons[class]
end

local function formIcons()
	local id = GetShapeshiftFormID and GetShapeshiftFormID()
	local icons = id and FORM_ICONS[id]
	if icons and icons[1] == "dire" then
		return { ns:ArtPath("other\\direbear_claw"), icons[2] }
	end
	return icons
end

function Hero:UpdateStats()
	local mine = self.viewUnit == "player"
	if not mine then
		hideInfo()
	end
	for _, f in ipairs(self.stats) do
		f:SetShown(mine)
		f.label:SetShown(mine)
		f.value:SetShown(mine)
	end
	if not mine then
		return
	end
	local choices = self:IconChoices()
	local form = formIcons()
	for i = 1, 3 do
		local f = self.stats[i]
		f.kind = choices[i] or "none"
		local shown = f.kind ~= "none"
		f:SetShown(shown)
		f.label:SetShown(shown)
		f.value:SetShown(shown)
		if shown then
			local ok, label, value, icon = pcall(statValues, f.kind)
			if not ok then
				label, value = "", ""
			end
			if form and SLOT[f.kind] == 16 then
				icon = form[1]
			end
			f.label:SetText(GOLD .. (label or "") .. "|r")
			f.value:SetText(value or "")
			f.icon:SetTexture(icon or ns:ArtPath(FIST))
		end
	end
	local armour = self.stats[4]
	armour.label:SetText(GOLD .. "Armor:|r")
	local ok, text = pcall(armourText)
	armour.value:SetText(ok and text or "")
	armour.icon:SetTexture((form and form[2]) or GetInventoryItemTexture("player", 5) or CAPE)
end

-- Show `unit` ("player" or "target") on the hero screen. Touches no secure
-- frame, so it is safe in combat.
function Hero:SetView(unit)
	self.viewUnit = unit
	if self.model then
		self.model:ClearModel()
		self.RefreshModel()
	end
	self.hovering = false
	self:UpdateXP()
	self:UpdateStats()
end

function Hero:SetIconChoice(index, kind)
	self:IconChoices()[index] = kind
	self:UpdateStats()
end

----------------------------------------------------------------------------
-- Status icons: resting / in combat, group leader and PvP.

function Hero:CreateStatusIcons(holder)
	local rest = holder:CreateTexture(nil, "OVERLAY")
	rest:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	local leader = holder:CreateTexture(nil, "OVERLAY")
	leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	local pvp = holder:CreateTexture(nil, "OVERLAY")
	self.icons = { rest = rest, leader = leader, pvp = pvp }
end

function Hero:UpdateStatusIcons()
	local icons = self.icons
	if UnitAffectingCombat("player") then
		icons.rest:SetTexCoord(0.5, 1, 0, 0.484375)
		icons.rest:Show()
	elseif IsResting() then
		icons.rest:SetTexCoord(0, 0.5, 0, 0.421875)
		icons.rest:Show()
	else
		icons.rest:Hide()
	end
	icons.leader:SetShown(UnitIsGroupLeader and UnitIsGroupLeader("player") or false)
	local faction = UnitFactionGroup("player")
	if UnitIsPVPFreeForAll("player") then
		icons.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
		icons.pvp:Show()
	elseif faction and faction ~= "Neutral" and UnitIsPVP("player") then
		icons.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
		icons.pvp:Show()
	else
		icons.pvp:Hide()
	end
end

----------------------------------------------------------------------------

function Hero:OnEnable()
	self:CreatePortrait()
	local holder = CreateFrame("Frame", "ReforgedUIHero", ns.root)
	holder:SetFrameStrata("LOW")
	holder:SetAllPoints(ns.root)
	self.holder = holder
	self.health = makeBar(holder, 2, 10)
	self.power = makeBar(holder, 4, 9)
	self:CreateXP(holder)
	self.stats = {}
	for i = 1, 4 do
		self.stats[i] = self:CreateStatIcon(holder, i)
	end
	self:CreateStatusIcons(holder)

	local function unitEvent(fn)
		return function(_, unit)
			if unit == "player" then fn() end
		end
	end
	local health = unitEvent(function() self:UpdateHealth() end)
	local power = unitEvent(function() self:UpdatePower() end)
	for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
		ns:On(e, health)
	end
	for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
		ns:On(e, power)
	end
	ns:On("PLAYER_DEAD", function() self:SetWarning(false) end)
	local xp = function() self:UpdateXP() end
	for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING" }) do
		ns:On(e, xp)
	end
	local stats = ns:Throttle(function() self:UpdateStats() end, 0.2)
	for _, e in ipairs({ "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_INVENTORY_CHANGED", "UNIT_AURA",
		"UNIT_RESISTANCES", "UNIT_STATS", "UNIT_DAMAGE", "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE" }) do
		ns:On(e, unitEvent(stats))
	end
	for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
		ns:On(e, stats)
	end
	local status = function() self:UpdateStatusIcons() end
	for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
		"GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "UNIT_FACTION", "PLAYER_FLAGS_CHANGED" }) do
		ns:On(e, status)
	end
	ns:On("PLAYER_ENTERING_WORLD", function() self:Update() end)
end

function Hero:Update()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateXP()
	self:UpdateStats()
	self:UpdateStatusIcons()
end

function Hero:OnLayout(L)
	place(self.portraitBg, L.portraitBg)
	place(self.model, L.portrait)
	place(self.click, L.portrait)
	self.RefreshModel()
	place(self.health, L.health)
	place(self.power, L.power)

	local xp, X = self.xp, L.xp
	place(xp.left, X.left)
	place(xp.middle, X.middle)
	place(xp.right, X.right)
	place(xp.bar, X.bar)
	place(xp.rested, X.bar)
	place(xp.hover, X.hover)
	for _, fs in ipairs({ xp.name, xp.level }) do
		fs:ClearAllPoints()
		fs:SetWidth(X.width)
	end
	xp.name:SetPoint("CENTER", ns.root, "BOTTOMLEFT", X.cx, X.nameY)
	xp.level:SetPoint("CENTER", ns.root, "BOTTOMLEFT", X.cx, X.levelY)

	for i, f in ipairs(self.stats) do
		local r = L.statIcons[i]
		place(f, r)
		place(f.label, r.label)
		place(f.value, r.value)
	end

	place(self.icons.rest, L.restIcon)
	place(self.icons.leader, L.leaderIcon)
	place(self.icons.pvp, L.pvpIcon)
	self:Update()
end
