-- Portrait and hero screen: the animated 3D portrait with hit points and mana
-- below it, the player's name, and the level bar (experience fill with
-- "Level N Class" written on it; hover for the numbers).

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
	-- The portrait, hit points and mana replace Blizzard's player frame. It is
	-- only made invisible: hiding or moving it runs Blizzard's unit frame
	-- code on our call stack, which fails on "secret" health values.
	ns:Conceal(PlayerFrame)

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
	xp.border = xp.rested:CreateTexture(nil, "BACKGROUND", nil, -1)
	xp.border:SetPoint("TOPLEFT", -2, 2)
	xp.border:SetPoint("BOTTOMRIGHT", 2, -2)
	xp.label = xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	xp.label:SetPoint("CENTER")
	xp:EnableMouse(true)
	xp:SetScript("OnEnter", function(f)
		f.hover = true
		self:UpdateXP()
	end)
	xp:SetScript("OnLeave", function(f)
		f.hover = false
		self:UpdateXP()
	end)
	self.xp = xp

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
	unitEvent("UNIT_NAME_UPDATE", self.UpdateName)
	unitEvent("UNIT_LEVEL", self.UpdateXP)
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
	if token == "MANA" or not c then
		-- Blizzard's mana blue is unreadable on the dark console.
		fs:SetTextColor(0.45, 0.65, 1)
	else
		fs:SetTextColor(c.r, c.g, c.b)
	end
end

function UnitInfo:UpdateName()
	self.name:SetText(UnitName("player") or "")
end

local function atMaxLevel()
	if IsPlayerAtEffectiveMaxLevel then
		return IsPlayerAtEffectiveMaxLevel()
	end
	return GetMaxPlayerLevel and UnitLevel("player") >= GetMaxPlayerLevel()
end

function UnitInfo:UpdateXP()
	local xp = self.xp
	local cur, max, rested = 1, 1, 0
	if not atMaxLevel() then
		cur, max = UnitXP("player"), UnitXPMax("player")
		if max <= 0 then max = 1 end
		rested = GetXPExhaustion() or 0
	end
	xp:SetMinMaxValues(0, max)
	xp:SetValue(cur)
	xp.rested:SetMinMaxValues(0, max)
	xp.rested:SetValue(math.min(max, cur + rested))
	if xp.hover and not atMaxLevel() then
		if rested > 0 then
			xp.label:SetFormattedText("%s %d / %d  (+%d)", XP or "XP", cur, max, rested)
		else
			xp.label:SetFormattedText("%s %d / %d", XP or "XP", cur, max)
		end
	else
		local className = UnitClass("player") or ""
		xp.label:SetFormattedText("%s %d %s", LEVEL or "Level", UnitLevel("player") or 0, className)
	end
end

function UnitInfo:OnLayout(L)
	place(self.model, L.portrait)
	place(self.health, L.healthText)
	place(self.power, L.powerText)
	place(self.name, L.nameText)
	place(self.xp, L.xpBar)
	self:UpdateAll()
end

function UnitInfo:OnTheme(theme)
	self.health:SetTextColor(unpack(theme.health))
	local c = theme.xp
	self.xp:SetStatusBarColor(c[1], c[2], c[3])
	self.xp.rested:SetStatusBarColor(c[1], c[2], c[3], 0.35)
	self.xp.border:SetColorTexture(unpack(theme.title))
	self.name:SetTextColor(unpack(theme.title))
end
