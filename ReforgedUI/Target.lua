-- Target panel: the target's portrait, name, level and classification, health
-- and power bars, the player's combo points on it, and the target's target
-- underneath. Both are our own secure unit buttons: left-click targets,
-- right-click opens the unit menu. Blizzard's target frame is made invisible.

local _, ns = ...
local Target = ns:RegisterModule("target", {})

local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"
local MAX_COMBO = 5

local function place(region, r)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.x, r.y)
	region:SetSize(r.w, r.h)
end

-- Health and power may be "secret" values: status bars accept them, text is
-- formatted under pcall, and nothing compares them.
local function setPair(fs, a, b)
	if not pcall(fs.SetFormattedText, fs, "%s / %s", a, b) then
		fs:SetText("")
	end
end

local function CreateBar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(STATUSBAR)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetPoint("TOPLEFT", -1, 1)
	bar.bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bar.bg:SetColorTexture(0, 0, 0, 0.8)
	bar.text = bar:CreateFontString(nil, "OVERLAY", height > 12 and "GameFontHighlightSmall" or "SystemFont_Tiny")
	bar.text:SetPoint("CENTER")
	return bar
end

local function CreateUnitButton(name, unit)
	local b = CreateFrame("Button", name, ns.root, "SecureUnitButtonTemplate")
	b:SetFrameStrata("MEDIUM") -- above Blizzard's (invisible) bar frames at the screen bottom
	b:SetFrameLevel(30)
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

	b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)
	b.health = CreateBar(b, 14)
	return b
end

local function reactionColor(unit)
	if UnitIsPlayer(unit) then
		local _, classFile = UnitClass(unit)
		local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
		if c then
			return c.r, c.g, c.b
		end
	end
	if UnitIsTapDenied and UnitIsTapDenied(unit) then
		return 0.6, 0.6, 0.6
	end
	local reaction = UnitReaction(unit, "player")
	local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 0.82, 0
end

local CLASSIFICATION = {
	elite = ELITE or "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = BOSS or "Boss",
}

function Target:OnEnable()
	ns:Conceal(TargetFrame)
	local t = CreateUnitButton("ReforgedUITarget", "target")
	t.model = CreateFrame("PlayerModel", nil, t)
	t.info = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t.info:SetJustifyH("LEFT")
	t.info:SetWordWrap(false)
	t.power = CreateBar(t, 10)
	t.combo = {}
	for i = 1, MAX_COMBO do
		local pip = t:CreateTexture(nil, "OVERLAY")
		pip:SetTexture("Interface\\ComboFrame\\ComboPoint")
		pip:SetTexCoord(0.375, 0.5625, 0, 1)
		t.combo[i] = pip
	end
	self.target = t

	local tot = CreateUnitButton("ReforgedUITargetTarget", "targettarget")
	tot.portrait = tot:CreateTexture(nil, "ARTWORK")
	self.tot = tot
	-- The target's target has no events of its own; poll it while shown.
	local elapsed = 0
	tot:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.2 then
			elapsed = 0
			self:UpdateToT()
		end
	end)
	tot:HookScript("OnShow", function() self:UpdateToT() end)

	local function unitEvent(event, fn)
		ns:On(event, function(_, unit)
			if unit == "target" then
				fn(self)
			end
		end)
	end
	for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do unitEvent(e, self.UpdateHealth) end
	for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do unitEvent(e, self.UpdatePower) end
	for _, e in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED" }) do
		unitEvent(e, self.UpdateName)
	end
	unitEvent("UNIT_MODEL_CHANGED", self.UpdateModel)
	ns:On("PLAYER_TARGET_CHANGED", function() self:UpdateAll() end)
	ns:On("UNIT_POWER_UPDATE", function(_, unit) if unit == "player" then self:UpdateCombo() end end)
	ns:On("PLAYER_COMBO_POINTS", function() self:UpdateCombo() end)
	t:HookScript("OnShow", function() self:UpdateAll() end)
end

function Target:UpdateAll()
	if not UnitExists("target") then
		return
	end
	self:UpdateModel()
	self:UpdateName()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateCombo()
	self:UpdateToT()
end

function Target:UpdateModel()
	local m = self.target.model
	m:ClearModel()
	m:SetUnit("target")
	m:SetPortraitZoom(1)
end

function Target:UpdateName()
	local t = self.target
	t.name:SetText(UnitName("target") or "")
	t.name:SetTextColor(reactionColor("target"))
	local level = UnitLevel("target") or 0
	local levelText = level > 0 and tostring(level) or "??"
	local class = CLASSIFICATION[UnitClassification("target") or ""]
	local kind = UnitIsPlayer("target") and (UnitClass("target")) or UnitCreatureType("target")
	local text = table.concat({ LEVEL or "Level", levelText, class or "", kind or "" }, " ")
	t.info:SetText((text:gsub("  +", " ")))
end

function Target:UpdateHealth()
	local bar = self.target.health
	bar:SetMinMaxValues(0, UnitHealthMax("target"))
	bar:SetValue(UnitHealth("target"))
	bar:SetStatusBarColor(0.1, 0.8, 0.1)
	setPair(bar.text, UnitHealth("target"), UnitHealthMax("target"))
end

function Target:UpdatePower()
	local bar = self.target.power
	bar:SetMinMaxValues(0, UnitPowerMax("target"))
	bar:SetValue(UnitPower("target"))
	local _, token = UnitPowerType("target")
	local c = PowerBarColor and token and PowerBarColor[token]
	if token == "MANA" or not c then
		bar:SetStatusBarColor(0.2, 0.4, 1)
	else
		bar:SetStatusBarColor(c.r, c.g, c.b)
	end
	setPair(bar.text, UnitPower("target"), UnitPowerMax("target"))
end

local function comboPoints()
	if GetComboPoints then
		return GetComboPoints("player", "target") or 0
	end
	local enum = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
	return enum and UnitPower("player", enum) or 0
end

function Target:UpdateCombo()
	local ok, n = pcall(comboPoints)
	n = ok and n or 0
	for i, pip in ipairs(self.target.combo) do
		pip:SetShown(i <= n)
	end
end

function Target:UpdateToT()
	local tot = self.tot
	if not UnitExists("targettarget") then
		return
	end
	SetPortraitTexture(tot.portrait, "targettarget")
	tot.name:SetText(UnitName("targettarget") or "")
	tot.name:SetTextColor(reactionColor("targettarget"))
	tot.health:SetMinMaxValues(0, UnitHealthMax("targettarget"))
	tot.health:SetValue(UnitHealth("targettarget"))
	tot.health:SetStatusBarColor(0.1, 0.8, 0.1)
	setPair(tot.health.text, UnitHealth("targettarget"), UnitHealthMax("targettarget"))
end

function Target:OnLayout(L)
	ns:RunOutOfCombat("target-layout", function()
		local t, r = self.target, L.target
		place(t, r.frame)
		place(t.model, r.portrait)
		place(t.name, r.name)
		place(t.info, r.info)
		place(t.health, r.health)
		place(t.power, r.power)
		local size = r.combo.h
		for i, pip in ipairs(t.combo) do
			pip:ClearAllPoints()
			pip:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.combo.x + (i - 1) * (size + 4), r.combo.y)
			pip:SetSize(size, size)
		end
		local tot, q = self.tot, L.tot
		place(tot, q.frame)
		place(tot.portrait, q.portrait)
		place(tot.name, q.name)
		place(tot.health, q.health)
	end)
end
