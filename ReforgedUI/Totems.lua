-- Totem timers: one button per totem slot, standing on the wall over the
-- action grid at its right end (the stance buttons start at the left).
-- Each shows the totem's icon, a cooldown sweep and the time it has left;
-- hover for Blizzard's totem tooltip, right-click to cancel the totem.
--
-- Blizzard's own totem timers hang under the player frame, which we hide
-- (Blizzard.lua), so they went with it. Cancelling a totem is a protected
-- action: these are secure action buttons ("destroytotem", one fixed slot
-- each), so right-click works in combat too. Secure buttons can't move or
-- show in combat, so a shaman's four buttons stay in place, and an empty
-- slot only draws nothing.
--
-- Totem info may be secret (Blizzard's ShouldTotemSlotBeSecret): then only
-- the icon is shown, through calls that take secret values, without the
-- sweep or the time.

local _, ns = ...
local Totems = ns:RegisterModule("totems", {})

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end
local SLOTS = _G.MAX_TOTEMS or 4
local CANCEL_HINT = "Right-click to cancel."

local function plain(v)
	return v ~= nil and not isSecret(v)
end

-- Totem slots in display order, left to right: Blizzard's order for the
-- class (earth, fire, water, air for shamans).
local function slotOrder(class)
	if class == "SHAMAN" then
		return _G.SHAMAN_TOTEM_PRIORITIES or { 2, 1, 3, 4 }
	end
	return _G.STANDARD_TOTEM_PRIORITIES or { 1, 2, 3, 4 }
end

-- "1m" from one minute up, else whole seconds.
local function timeText(left)
	if left >= 60 then
		return math.ceil(left / 60) .. "m"
	end
	return tostring(math.ceil(left))
end

local function onEnter(b)
	if not b.active then
		return
	end
	GameTooltip:SetOwner(b, "ANCHOR_TOP")
	if pcall(GameTooltip.SetTotem, GameTooltip, b.slot) then
		GameTooltip:AddLine(CANCEL_HINT, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end
end

local function makeButton(index, slot)
	local b = CreateFrame("Button", "ReforgedUITotem" .. index, ns.root, "SecureActionButtonTemplate")
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(10)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type2", "destroytotem")
	b:SetAttribute("totem-slot", slot)
	b.slot = slot

	-- Everything drawn sits on one face, so an empty slot fades it out as a
	-- whole (also from a secret "have totem").
	local face = CreateFrame("Frame", nil, b)
	face:SetAllPoints()
	face:SetFrameLevel(b:GetFrameLevel() + 1)
	b.face = face
	face.border = face:CreateTexture(nil, "BACKGROUND")
	face.border:SetPoint("TOPLEFT", -1, 1)
	face.border:SetPoint("BOTTOMRIGHT", 1, -1)
	face.border:SetColorTexture(0, 0, 0, 1)
	face.icon = face:CreateTexture(nil, "ARTWORK")
	face.icon:SetAllPoints()
	face.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	face.cooldown = CreateFrame("Cooldown", nil, face, "CooldownFrameTemplate")
	face.cooldown:SetAllPoints()
	face.cooldown:SetReverse(true)
	face.cooldown:SetDrawEdge(false)
	if face.cooldown.SetHideCountdownNumbers then
		face.cooldown:SetHideCountdownNumbers(true)
	end
	-- The time left, over the icon's bottom (above the sweep).
	local textHolder = CreateFrame("Frame", nil, face)
	textHolder:SetAllPoints()
	textHolder:SetFrameLevel(face:GetFrameLevel() + 3)
	face.time = textHolder:CreateFontString(nil, "OVERLAY")
	if not ns:SetFont(face.time, 10, "OUTLINE") then
		face.time:SetFontObject("NumberFontNormalSmall")
	end
	face.time:SetPoint("BOTTOM", 0, 1)
	face:SetAlpha(0)

	b:SetScript("OnEnter", onEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:Hide()
	return b
end

function Totems:OnEnable()
	if not _G.GetTotemInfo then
		return
	end
	local _, class = UnitClass("player")
	self.always = class == "SHAMAN"
	self.buttons = {}
	for i, slot in ipairs(slotOrder(class)) do
		if i > SLOTS then
			break
		end
		self.buttons[i] = makeButton(i, slot)
	end
	for _, e in ipairs({ "PLAYER_TOTEM_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		ns:On(e, function() self:Update() end)
	end
	-- The time left ticks without events.
	local elapsed = 0
	self.ticker = CreateFrame("Frame")
	self.ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 0.2 then
			elapsed = 0
			self:UpdateTimes()
		end
	end)
end

-- One slot's state onto its button: true when it holds a totem (or may:
-- a secret answer counts as one).
local function fill(b)
	local face = b.face
	local ok, have, _, start, duration, icon = pcall(GetTotemInfo, b.slot)
	if not ok then
		have = false
	end
	if plain(have) then
		local active = have and plain(duration) and duration > 0
		b.active, b.secret = active and true or false, false
		if active then
			face.icon:SetTexture(icon)
			if plain(start) then
				face.cooldown:SetCooldown(start, duration)
				face.cooldown:Show()
			else
				face.cooldown:Hide()
			end
		else
			face.cooldown:Hide()
			face.time:SetText("")
		end
		face:SetAlpha(active and 1 or 0)
		return active
	end
	-- Secret: show the icon if the client says there is one, no sweep or time.
	b.active, b.secret = true, true
	face.cooldown:Hide()
	face.time:SetText("")
	pcall(face.icon.SetTexture, face.icon, icon)
	if not (face.SetAlphaFromBoolean and pcall(face.SetAlphaFromBoolean, face, have, 1, 0)) then
		face:SetAlpha(1)
	end
	return true
end

function Totems:Update()
	if not self.buttons then
		return
	end
	local any = false
	for _, b in ipairs(self.buttons) do
		if fill(b) then
			any = true
		end
	end
	self:UpdateTimes()
	-- A shaman's buttons are always there (empty ones draw nothing), so a
	-- totem dropped in combat has its button ready. Other classes only get
	-- them while they have a totem, shown or hidden out of combat.
	local shown = self.layout ~= nil and (self.always or any)
	if self.shown ~= shown then
		ns:RunOutOfCombat("totem-buttons", function() self:ShowButtons() end)
	end
end

function Totems:ShowButtons()
	local any = false
	for _, b in ipairs(self.buttons) do
		any = any or b.active
	end
	local shown = self.layout ~= nil and (self.always or any)
	self.shown = shown
	for _, b in ipairs(self.buttons) do
		b:SetShown(shown)
	end
	self.ticker:SetShown(shown)
end

function Totems:UpdateTimes()
	for _, b in ipairs(self.buttons or {}) do
		if b.active and not b.secret then
			local ok, left = pcall(GetTotemTimeLeft, b.slot)
			if ok and plain(left) and left > 0 then
				b.face.time:SetText(timeText(left))
			else
				b.face.time:SetText("")
			end
			if GameTooltip:IsOwned(b) then
				onEnter(b)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Layout

function Totems:PlaceButtons()
	local T = self.layout and self.layout.totems
	if not T then
		return
	end
	local n = #self.buttons
	for i, b in ipairs(self.buttons) do
		-- Right-aligned: the last slot ends where the row does.
		ns.modules.console.Place(b, { x = T.right - (n - i) * T.step - T.size, y = T.y, w = T.size, h = T.size })
	end
	self:ShowButtons()
end

function Totems:OnLayout(L)
	if not self.buttons then
		return
	end
	self.layout = L
	ns:RunOutOfCombat("totem-place", function() self:PlaceButtons() end)
	self:Update()
end
