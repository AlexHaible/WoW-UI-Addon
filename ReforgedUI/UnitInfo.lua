-- Portrait and info screen: the animated 3D portrait with hit points and mana
-- below it, and the hero line (name, level, class) with the experience bar.

local _, ns = ...
local UnitInfo = ns:RegisterModule("unitinfo", {})

local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"

local function place(region, r)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.x, r.y)
	region:SetSize(r.w, r.h)
end

-- Health and power can be "secret" values in combat on newer Retail clients:
-- they may be displayed but not compared, so any arithmetic is guarded.
local function setPair(fs, a, b)
	if not pcall(fs.SetFormattedText, fs, "%s / %s", a, b) then
		fs:SetText("")
	end
end

function UnitInfo:OnEnable()
	local holder = CreateFrame("Frame", "ReforgedUIUnitInfo", ns.root)
	holder:SetFrameStrata("LOW")
	holder:SetAllPoints(ns.root)
	self.holder = holder

	local model = CreateFrame("PlayerModel", "ReforgedUIPortrait", holder)
	model:EnableMouse(true)
	model:SetScript("OnEnter", function(f)
		GameTooltip_SetDefaultAnchor(GameTooltip, f)
		GameTooltip:SetUnit("player")
		GameTooltip:Show()
	end)
	model:SetScript("OnLeave", GameTooltip_Hide)
	self.model = model

	self.health = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.power = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.name = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	for _, fs in ipairs({ self.health, self.power, self.name }) do
		fs:SetJustifyH("CENTER")
		fs:SetWordWrap(false)
	end
	self.name:SetJustifyH("LEFT")

	local xp = CreateFrame("StatusBar", "ReforgedUIXPBar", holder)
	xp:SetStatusBarTexture(STATUSBAR)
	xp.rested = CreateFrame("StatusBar", nil, xp)
	xp.rested:SetAllPoints()
	xp.rested:SetStatusBarTexture(STATUSBAR)
	xp.rested:SetFrameLevel(xp:GetFrameLevel())
	xp:SetFrameLevel(xp:GetFrameLevel() + 1)
	xp.bg = xp.rested:CreateTexture(nil, "BACKGROUND")
	xp.bg:SetPoint("TOPLEFT", -1, 1)
	xp.bg:SetPoint("BOTTOMRIGHT", 1, -1)
	xp.bg:SetColorTexture(0, 0, 0, 0.8)
	xp.text = xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	xp.text:SetPoint("CENTER")
	xp.text:Hide()
	xp:EnableMouse(true)
	xp:SetScript("OnEnter", function(f) f.text:Show() end)
	xp:SetScript("OnLeave", function(f) f.text:Hide() end)
	self.xp = xp

	self.maxLevel = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

	local function unitEvent(event, fn)
		ns:On(event, function(_, unit)
			if unit == nil or unit == "player" then
				fn(self)
			end
		end)
	end
	for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do unitEvent(e, self.UpdateHealth) end
	for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do unitEvent(e, self.UpdatePower) end
	for _, e in ipairs({ "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE" }) do unitEvent(e, self.UpdateModel) end
	for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do unitEvent(e, self.UpdateXP) end
	unitEvent("PLAYER_LEVEL_UP", self.UpdateName)
	unitEvent("UNIT_NAME_UPDATE", self.UpdateName)
	ns:On("PLAYER_ENTERING_WORLD", function() self:UpdateAll() end)
end

function UnitInfo:UpdateAll()
	self:UpdateModel()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateName()
	self:UpdateXP()
end

function UnitInfo:UpdateModel()
	self.model:SetUnit("player")
	self.model:SetPortraitZoom(1)
end

function UnitInfo:UpdateHealth()
	setPair(self.health, UnitHealth("player"), UnitHealthMax("player"))
end

function UnitInfo:UpdatePower()
	local fs = self.power
	local ok, hasPower = pcall(function() return UnitPowerMax("player") > 0 end)
	if ok and not hasPower then
		fs:SetText("")
		return
	end
	setPair(fs, UnitPower("player"), UnitPowerMax("player"))
	local _, token = UnitPowerType("player")
	local c = PowerBarColor and token and PowerBarColor[token]
	if c then
		fs:SetTextColor(c.r, c.g, c.b)
	else
		fs:SetTextColor(0.4, 0.6, 1)
	end
end

function UnitInfo:UpdateName()
	local name = UnitName("player") or ""
	local level = UnitLevel("player") or 0
	local race = UnitRace("player") or ""
	local className, classFile = UnitClass("player")
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	local classText = color and color:WrapTextInColorCode(className) or (className or "")
	local t = ns.theme and ns.theme.title or { 1, 0.82, 0 }
	self.name:SetFormattedText("|cff%02x%02x%02x%s|r  |cffd0d0d0%s %d %s|r %s",
		t[1] * 255, t[2] * 255, t[3] * 255, name, LEVEL or "Level", level, race, classText)
end

local function atMaxLevel()
	if IsPlayerAtEffectiveMaxLevel then
		return IsPlayerAtEffectiveMaxLevel()
	end
	return GetMaxPlayerLevel and UnitLevel("player") >= GetMaxPlayerLevel()
end

function UnitInfo:UpdateXP()
	local xp = self.xp
	if atMaxLevel() then
		xp:Hide()
		self.maxLevel:SetText(MAX_PLAYER_LEVEL_TEXT or "")
		self.maxLevel:Show()
		return
	end
	self.maxLevel:Hide()
	xp:Show()
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if max <= 0 then max = 1 end
	local rested = GetXPExhaustion() or 0
	xp:SetMinMaxValues(0, max)
	xp:SetValue(cur)
	xp.rested:SetMinMaxValues(0, max)
	xp.rested:SetValue(math.min(max, cur + rested))
	if rested > 0 then
		xp.text:SetFormattedText("%s %d / %d  (+%d)", XP or "XP", cur, max, rested)
	else
		xp.text:SetFormattedText("%s %d / %d", XP or "XP", cur, max)
	end
end

function UnitInfo:OnLayout(L)
	place(self.model, L.portrait)
	place(self.health, L.healthText)
	place(self.power, L.powerText)
	place(self.name, L.nameText)
	place(self.xp, L.xpBar)
	place(self.maxLevel, L.xpBar)
	self:UpdateAll()
end

function UnitInfo:OnTheme(theme)
	self.health:SetTextColor(unpack(theme.health))
	local c = theme.xp
	self.xp:SetStatusBarColor(c[1], c[2], c[3])
	self.xp.rested:SetStatusBarColor(c[1], c[2], c[3], 0.35)
	self:UpdateName()
end
