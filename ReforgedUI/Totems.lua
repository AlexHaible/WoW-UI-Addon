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
-- The row can move: Shift-drag a totem out of combat, or drag the row's
-- outline while Edit Mode is open. The buttons hang from one holder, which
-- is what moves; its spot is kept per account (consoleOpts.totemSpot,
-- console units from the console's bottom-left), and /rui totems reset puts
-- it back on the wall.
--
-- Totem info may be secret (Blizzard's ShouldTotemSlotBeSecret), which it
-- is in combat on the newer clients: then the icon and the time left are
-- still shown, through calls that take secret values (the time as whole
-- seconds, since a secret can't be compared or divided), without the sweep.
-- Should the client refuse that, the time comes from a duration text
-- binding (the client's own countdown text, fed GetTotemDuration). An empty
-- slot may also answer nothing at all, which is no totem, not a secret one.
-- /rui totems prints what each slot answers and how its time is shown.

local _, ns = ...
local Totems = ns:RegisterModule("totems", {})

local isSecret, plain = ns.IsSecret, ns.IsKnown
local SLOTS = _G.MAX_TOTEMS or 4
local CANCEL_HINT = "Right-click to cancel."
local MOVE_HINT = "Shift-drag to move."

local stopBinding -- below

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
		GameTooltip:AddLine(MOVE_HINT, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end
end

local function makeButton(holder, index, slot)
	local b = CreateFrame("Button", "ReforgedUITotem" .. index, holder, "SecureActionButtonTemplate")
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
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() Totems:StartDrag(IsShiftKeyDown()) end)
	b:SetScript("OnDragStop", function() Totems:StopDrag() end)
	b:Hide()
	return b
end

-- The holder all buttons hang from: what moves. Click-through except while
-- Edit Mode is open, when it shows an outline to drag (also for an empty or
-- hidden row).
local function makeHolder()
	local h = CreateFrame("Frame", "ReforgedUITotems", ns.root)
	h:SetFrameStrata("MEDIUM")
	h:SetFrameLevel(9)
	h:SetClampedToScreen(true)
	h:EnableMouse(false)
	local outline = CreateFrame("Frame", nil, h)
	outline:SetAllPoints()
	outline:SetFrameLevel(h:GetFrameLevel() + 20)
	outline.fill = outline:CreateTexture(nil, "BACKGROUND")
	outline.fill:SetAllPoints()
	outline.fill:SetColorTexture(0.1, 0.5, 1, 0.35)
	outline.label = outline:CreateFontString(nil, "OVERLAY")
	if not ns:SetFont(outline.label, 10, "OUTLINE") then
		outline.label:SetFontObject("GameFontHighlightSmall")
	end
	outline.label:SetPoint("CENTER")
	outline.label:SetText("Totems")
	outline:Hide()
	h.outline = outline
	ns:MakeDraggable(h, function() Totems:SaveSpot() end, function() return Totems:CanDrag(true) end)
	return h
end

function Totems:OnEnable()
	if not _G.GetTotemInfo then
		return
	end
	local _, class = UnitClass("player")
	self.always = class == "SHAMAN"
	self.holder = makeHolder()
	self.buttons = {}
	for i, slot in ipairs(slotOrder(class)) do
		if i > SLOTS then
			break
		end
		self.buttons[i] = makeButton(self.holder, i, slot)
	end
	ns:OnEditMode(function(open) self:SetEditing(open) end)
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

-- The client's own countdown text on a button, kept up to date by the
-- client: the last resort when it won't format a secret time left for us.
local function startBinding(b)
	if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding and _G.GetTotemDuration) then
		return false, "no duration text binding in this client"
	end
	return pcall(function()
		local binding = b.binding
		if not binding then
			binding = C_DurationUtil.CreateDurationTextBinding()
			binding:SetFontString(b.face.time)
			local f = C_StringUtil.CreateSecondsFormatter()
			-- "5m", "45s", like Blizzard's aura timers; each setting is optional.
			local E = Enum or {}
			local function set(method, enum, key)
				local value = enum
				if key then
					value = E[enum] and E[enum][key]
				end
				if f[method] and value ~= nil then
					pcall(f[method], f, value)
				end
			end
			set("SetDefaultAbbreviation", "SecondsFormatterAbbreviation", "OneLetter")
			set("SetRounding", "SecondsFormatterRounding", "Truncate")
			set("SetCanRoundUpLastUnit", true)
			set("SetMinInterval", "SecondsFormatterInterval", "Seconds")
			set("SetDesiredUnitCount", 1)
			binding:SetFormatter(f)
			pcall(binding.SetZeroDurationText, binding, "")
			pcall(binding.SetExpiredText, binding, "")
			b.binding = binding
		end
		binding:SetDuration(GetTotemDuration(b.slot))
		binding:SetEnabled(true)
	end)
end

stopBinding = function(b)
	if b.binding then
		pcall(b.binding.SetEnabled, b.binding, false)
	end
	b.bound = false
end

-- One slot's state onto its button: true when it holds a totem (or may:
-- a secret answer counts as one).
local function fill(b)
	local face = b.face
	local ok, have, _, start, duration, icon = pcall(GetTotemInfo, b.slot)
	if not ok then
		have = false
	end
	b.howTime, b.timeError = nil, nil
	stopBinding(b)
	-- Nothing at all (the client may answer so for an empty slot) is no totem.
	if have == nil or plain(have) then
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
	-- Secret: show the icon if the client says there is one, no sweep; the
	-- time left comes from UpdateTimes.
	b.active, b.secret = true, true
	face.cooldown:Hide()
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

-- A secret time left can't be compared or turned into "1m", but a font
-- string takes it as is: whole seconds, formatted by the client. If the
-- client won't, its own countdown text takes over (once per totem update).
local function secretTime(b, left)
	local fs = b.face.time
	local ok, err = pcall(fs.SetFormattedText, fs, "%.0f", left)
	if ok then
		b.howTime = "secret seconds"
		return
	end
	fs:SetText("")
	local bound, why = startBinding(b)
	b.bound = bound and true or false
	b.howTime = bound and "client countdown" or "none"
	b.timeError = tostring(bound and err or why or err)
end

function Totems:UpdateTimes()
	for _, b in ipairs(self.buttons or {}) do
		if b.active and not b.bound then
			local ok, left = pcall(GetTotemTimeLeft, b.slot)
			if not ok then
				b.face.time:SetText("")
				b.howTime, b.timeError = "none", tostring(left)
			elseif isSecret(left) then
				secretTime(b, left)
			elseif left and left > 0 then
				b.face.time:SetText(timeText(left))
				b.howTime = "plain"
			else
				b.face.time:SetText("")
				b.howTime = "none (no time left)"
			end
		end
		if b.active and GameTooltip:IsOwned(b) then
			onEnter(b)
		end
	end
end

-- /rui totems: what each slot answers and how its time is shown.
local function describe(v)
	if isSecret(v) then
		return "secret"
	end
	return tostring(v)
end

function Totems:Describe()
	if not self.buttons then
		return { "totem timers: off (no totem API in this client)" }
	end
	local lines = {}
	for _, b in ipairs(self.buttons) do
		local ok, have, _, start, duration = pcall(GetTotemInfo, b.slot)
		local okLeft, left = pcall(GetTotemTimeLeft, b.slot)
		lines[#lines + 1] = ("slot %d: have %s, start %s, duration %s, time left %s; %s, time shown: %s%s"):format(
			b.slot, ok and describe(have) or "error", describe(start), describe(duration),
			okLeft and describe(left) or "error",
			b.active and (b.secret and "active (secret)" or "active") or "empty",
			tostring(b.howTime or "none"), b.timeError and (" (" .. b.timeError .. ")") or "")
	end
	lines[#lines + 1] = "in combat: " .. tostring(InCombatLockdown() and true or false)
	return lines
end

----------------------------------------------------------------------------
-- Layout

-- The row's box in console units: where the player put it, else on the
-- wall, right-aligned so the last slot ends where the action slots do.
function Totems:Spot()
	local T = self.layout.totems
	local n = #self.buttons
	local w = n * T.step - (T.step - T.size)
	local spot = ns.db.consoleOpts.totemSpot
	if type(spot) == "table" and plain(spot[1]) and plain(spot[2]) then
		return { x = spot[1], y = spot[2], w = w, h = T.size }
	end
	return { x = T.right - w, y = T.y, w = w, h = T.size }
end

function Totems:PlaceButtons()
	local T = self.layout and self.layout.totems
	if not T then
		return
	end
	ns.modules.console.Place(self.holder, self:Spot())
	for i, b in ipairs(self.buttons) do
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", self.holder, "BOTTOMLEFT", (i - 1) * T.step, 0)
		b:SetSize(T.size, T.size)
	end
	self:ShowButtons()
end

-- Dragging: with Shift (or in Edit Mode), out of combat; protected frames
-- can't move in combat.
function Totems:CanDrag(allowed)
	return (allowed or self.editing) and not InCombatLockdown() and self.layout and true or false
end

-- (A drag of one of the buttons moves the whole row.)
function Totems:StartDrag(allowed)
	if self:CanDrag(allowed) then
		ns:StartDrag(self.holder)
	end
end

function Totems:StopDrag()
	ns:StopDrag(self.holder)
end

-- After a drag: the row's corner in console units, kept per account.
function Totems:SaveSpot()
	local h, root = self.holder, ns.root
	local x, y = h:GetLeft(), h:GetBottom()
	local rx, ry = root:GetLeft(), root:GetBottom()
	if x and y and rx and ry then
		ns.db.consoleOpts.totemSpot = { x - rx, y - ry }
	end
	ns:RunOutOfCombat("totem-place", function() self:PlaceButtons() end)
end

function Totems:ResetSpot()
	ns.db.consoleOpts.totemSpot = false
	if self.holder then
		ns:RunOutOfCombat("totem-place", function() self:PlaceButtons() end)
	end
end

-- Edit Mode open: the row's outline shows and can be dragged.
function Totems:SetEditing(on)
	self.editing = on
	local h = self.holder
	h.outline:SetShown(on)
	ns:RunOutOfCombat("totem-edit", function()
		h:EnableMouse(on and true or false)
	end)
	if not on then
		self:StopDrag()
	end
end

function Totems:OnLayout(L)
	if not self.buttons then
		return
	end
	self.layout = L
	ns:RunOutOfCombat("totem-place", function() self:PlaceButtons() end)
	self:Update()
end
