-- Your pet's unit icon, like the target of target's (Target.lua): its
-- portrait in the theme's trim over its health and power bars, standing on
-- the wall beside the target of target. A hunter's pet shows its happiness
-- in the portrait's corner (hover it for the details), and the pet's buffs
-- and debuffs stand in rows above the icon, debuffs nearest. Left-click
-- targets the pet, right-click opens its menu, Shift-drag moves the whole of
-- it (out of combat; /rui pet reset puts it back).
--
-- Health and power go straight into status bars; an aura that can't be read
-- (the client may keep them secret in combat) leaves its row empty until it
-- can be.

local _, ns = ...
local Pet = ns:RegisterModule("pet", {})

local MAX_AURAS = 6 -- per kind, three to a row
local PER_ROW = 3

local HAPPINESS_TEXTURE = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPINESS_COORDS = {
	{ 0.375, 0.5625, 0, 0.359375 }, -- unhappy
	{ 0.1875, 0.375, 0, 0.359375 }, -- content
	{ 0, 0.1875, 0, 0.359375 }, -- happy
}

local isSecret = issecretvalue or function() return false end

-- The pet's `i`th aura of `filter` ("HELPFUL", "HARMFUL"): true, its icon,
-- stack count, duration and expiry; nil past the last. May error on secrets.
local function auraAt(i, filter)
	local api = _G.C_UnitAuras
	if api and api.GetAuraDataByIndex then
		local d = api.GetAuraDataByIndex("pet", i, filter)
		if type(d) ~= "table" then
			return nil
		end
		return true, d.icon, d.applications, d.duration, d.expirationTime
	end
	if not _G.UnitAura then
		return nil
	end
	local name, icon, count, _, duration, expires = _G.UnitAura("pet", i, filter)
	if not isSecret(name) and not name then
		return nil
	end
	return true, icon, count, duration, expires
end

local function plain(v)
	return type(v) == "number" and not isSecret(v)
end

----------------------------------------------------------------------------

local function makeAura(parent, filter, index)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(parent:GetFrameLevel() + 3)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", -1, 1)
	f.border:SetPoint("BOTTOMRIGHT", 1, -1)
	if filter == "HARMFUL" then
		f.border:SetColorTexture(0.8, 0.1, 0.1, 1)
	else
		f.border:SetColorTexture(0, 0, 0, 1)
	end
	f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cooldown:SetAllPoints()
	f.cooldown:SetReverse(true)
	f.cooldown:SetDrawEdge(false)
	if f.cooldown.SetHideCountdownNumbers then
		f.cooldown:SetHideCountdownNumbers(true)
	end
	f.count = f:CreateFontString(nil, "OVERLAY")
	if not ns:SetFont(f.count, 8, "OUTLINE") then
		f.count:SetFontObject("NumberFontNormalSmall")
	end
	f.count:SetPoint("BOTTOMRIGHT", 1, 0)
	f.filter, f.index = filter, index
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(a)
		GameTooltip:SetOwner(a, "ANCHOR_BOTTOMRIGHT")
		if pcall(GameTooltip.SetUnitAura, GameTooltip, "pet", a.index, a.filter) then
			GameTooltip:Show()
		end
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	f:Hide()
	return f
end

local function happinessTip(owner)
	local happiness, damage = _G.GetPetHappiness()
	if not plain(happiness) then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(_G["PET_HAPPINESS" .. happiness] or "")
	if plain(damage) and damage ~= 100 and _G.PET_DAMAGE_PERCENTAGE then
		GameTooltip:AddLine(_G.PET_DAMAGE_PERCENTAGE:format(damage), 1, 1, 1)
	end
	GameTooltip:Show()
end

function Pet:Create()
	local target = ns.modules.target
	local b = target.CreateUnitIcon("ReforgedUIPet", "pet", 32, true)
	b:HookScript("OnEnter", function()
		GameTooltip:AddLine("Shift-drag to move.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:HookScript("OnShow", function() self:Update() end)

	-- Shift-drag moves it, out of combat (it is a secure button).
	b:SetMovable(true)
	b:SetClampedToScreen(true)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(f)
		if IsShiftKeyDown() and not InCombatLockdown() then
			f.moving = true
			f:StartMoving()
		end
	end)
	b:SetScript("OnDragStop", function(f)
		if not f.moving then
			return
		end
		f.moving = false
		f:StopMovingOrSizing()
		if f.SetUserPlaced then
			f:SetUserPlaced(false)
		end
		self:SaveSpot()
	end)

	-- A hunter's pet's happiness, over the portrait's top-right corner.
	local happy = CreateFrame("Frame", nil, b)
	happy:SetFrameLevel(b:GetFrameLevel() + 4)
	happy.icon = happy:CreateTexture(nil, "OVERLAY")
	happy.icon:SetAllPoints()
	happy.icon:SetTexture(HAPPINESS_TEXTURE)
	happy:EnableMouse(true)
	happy:SetScript("OnEnter", happinessTip)
	happy:SetScript("OnLeave", GameTooltip_Hide)
	happy:Hide()
	b.happiness = happy

	b.auras = { HARMFUL = {}, HELPFUL = {} }
	for filter, list in pairs(b.auras) do
		for i = 1, MAX_AURAS do
			list[i] = makeAura(b, filter, i)
		end
	end
	self.button = b
end

function Pet:OnEnable()
	self:Create()
	local function petEvent(events, fn)
		for _, e in ipairs(events) do
			ns:On(e, function(_, unit)
				if unit == "pet" then
					fn(self)
				end
			end)
		end
	end
	petEvent({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }, self.UpdateHealth)
	petEvent({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }, self.UpdatePower)
	petEvent({ "UNIT_AURA" }, self.UpdateAuras)
	petEvent({ "UNIT_HAPPINESS" }, self.UpdateHappiness)
	petEvent({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }, self.UpdatePortrait)
	ns:On("UNIT_PET", function(_, unit)
		if unit == "player" then
			self:Update()
		end
	end)
	ns:On("PET_UI_UPDATE", function() self:UpdateHappiness() end)
	-- Auras run out without an event.
	local elapsed = 0
	self.button:HookScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.5 then
			elapsed = 0
			self:UpdateAuras()
		end
	end)
end

function Pet:Update()
	if not UnitExists("pet") then
		return
	end
	self:UpdatePortrait()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateHappiness()
	self:UpdateAuras()
end

function Pet:UpdatePortrait()
	SetPortraitTexture(self.button.portrait, "pet")
end

function Pet:UpdateHealth()
	local bar = self.button.health
	bar:SetMinMaxValues(0, UnitHealthMax("pet"))
	bar:SetValue(UnitHealth("pet"))
end

function Pet:UpdatePower()
	local bar = self.button.power
	local ptype, token = UnitPowerType("pet")
	bar:SetMinMaxValues(0, UnitPowerMax("pet", ptype))
	bar:SetValue(UnitPower("pet", ptype))
	local r, g, b = 0.2, 0.4, 1
	local c = PowerBarColor and token and PowerBarColor[token]
	if token ~= "MANA" and c and c.r then
		r, g, b = c.r, c.g, c.b
	end
	bar:SetStatusBarColor(r, g, b)
end

-- Hunter pets only: other pets have no happiness (nil).
function Pet:UpdateHappiness()
	local icon = self.button.happiness
	local happiness = _G.GetPetHappiness and _G.GetPetHappiness()
	local tc = plain(happiness) and HAPPINESS_COORDS[happiness]
	if tc then
		icon.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
	end
	icon:SetShown(tc and true or false)
end

-- One kind of aura into its icons; false when the client would not say.
local function fill(list)
	local filter = list[1].filter
	local n = 0
	local ok = pcall(function()
		for i = 1, MAX_AURAS do
			local found, icon, count, duration, expires = auraAt(i, filter)
			if not found then
				break
			end
			local f = list[i]
			f.icon:SetTexture(icon)
			f.count:SetText(plain(count) and count > 1 and count or "")
			if plain(duration) and plain(expires) and duration > 0 then
				f.cooldown:SetCooldown(expires - duration, duration)
				f.cooldown:Show()
			else
				f.cooldown:Hide()
			end
			n = i
		end
	end)
	if not ok then
		n = 0
	end
	for i, f in ipairs(list) do
		f:SetShown(i <= n)
	end
	return n
end

-- Debuffs in the rows nearest the icon, buffs above them.
function Pet:UpdateAuras()
	local b = self.button
	if not (b:IsVisible() and self.auraLayout) then
		return
	end
	local A = self.auraLayout
	local row = 0
	for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
		local list = b.auras[filter]
		local n = fill(list)
		for i = 1, n do
			local f = list[i]
			local col, r = (i - 1) % PER_ROW, row + math.floor((i - 1) / PER_ROW)
			f:ClearAllPoints()
			f:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", A.x + col * A.step, A.y + r * A.step)
			f:SetSize(A.size, A.size)
		end
		row = row + math.ceil(n / PER_ROW)
	end
end

----------------------------------------------------------------------------
-- Layout

-- Where the icon is: where the player put it, else beside the target of
-- target (Layout.lua's petIcon).
function Pet:Spot()
	local L = self.layout
	local spot = ns.db.consoleOpts.petSpot
	local r = L.petIcon.frame
	if type(spot) == "table" and plain(spot[1]) and plain(spot[2]) then
		return { x = spot[1], y = spot[2], w = r.w, h = r.h }
	end
	return r
end

function Pet:PlaceButton()
	if self.layout then
		ns.modules.console.Place(self.button, self:Spot())
	end
end

-- After a Shift-drag: the icon's corner in console units, kept per account.
function Pet:SaveSpot()
	local b, root = self.button, ns.root
	local x, y = b:GetLeft(), b:GetBottom()
	local rx, ry = root:GetLeft(), root:GetBottom()
	if not (x and y and rx and ry) then
		return
	end
	ns.db.consoleOpts.petSpot = { x - rx, y - ry }
	ns:RunOutOfCombat("pet-button", function() self:PlaceButton() end)
end

function Pet:ResetSpot()
	ns.db.consoleOpts.petSpot = false
	ns:RunOutOfCombat("pet-button", function() self:PlaceButton() end)
end

function Pet:OnLayout(L)
	self.layout = L
	local P, b = L.petIcon, self.button
	ns.modules.target.PlaceUnitIcon(b, P)
	-- The happiness face over the portrait's top-right corner.
	local size = 0.4 * P.icon.w
	local icon = P.icon
	b.happiness:ClearAllPoints()
	b.happiness:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", icon.x + icon.w - size * 0.75 - P.frame.x,
		icon.y + icon.h - size * 0.75 - P.frame.y)
	b.happiness:SetSize(size, size)
	-- Aura rows: three icons across the box, from just above the trim.
	local gap = 2
	local asize = (P.box.w - (PER_ROW - 1) * gap) / PER_ROW
	self.auraLayout = { x = P.box.x - P.frame.x, y = P.frame.h + gap, size = asize, step = asize + gap }
	ns:RunOutOfCombat("pet-button", function() self:PlaceButton() end)
	self:Update()
end
