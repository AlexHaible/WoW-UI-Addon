-- The three action slots beside the minimap: Reforged UI's own bar, so none
-- of Blizzard's action bars is given up for them.
--
-- They are our own secure buttons (SecureActionButtonTemplate, type
-- "action"), so they cast whatever a bar slot can hold: spells, items,
-- macros, mounts, flyouts. They need action slots, and Blizzard's bars and
-- pages claim most of 1-180. The moonkin form page (109-120) is only ever
-- used by druids, so everyone else uses 109-111. Druids use page 11
-- (121-123): no Blizzard bar shows it, and the client's vehicle, override
-- and temporary shapeshift bars are pages 31-33 (checked in game). Up to
-- 1.15 druids got 133-135, but those are the shaman totem bar's slots
-- (page 12), and the client only lets Fire, Earth and Water totem spells
-- into them, so nothing could be put there.
--
-- Blizzard's ActionBarButtonTemplate is not used: on clients with secret
-- values its code tainted when run from our buttons. The icon, cooldown,
-- count and states are drawn here from the action APIs, and anything that
-- comes back secret is passed only to widgets that accept it.
--
-- Up to 1.11 these were the first three buttons of Action Bar 8. Once per
-- character, their actions move onto our slots, the keys bound to them move
-- to our bindings, and Action Bar 8 (which the addon had turned on) goes back
-- to off, ready for the player's own use.

local _, ns = ...
local MinimapBar = ns:RegisterModule("minimapbar", {})

local COUNT = 3
local HEARTHSTONE = 6948
local BUTTON_NAME = "ReforgedUIMinimapButton"
local BINDING = "CLICK " .. BUTTON_NAME .. "%d:LeftButton"
-- Action Bar 8 (MultiBar7, action page 15) and its key bindings.
local OLD_FIRST_SLOT = 169
-- A druid's slots: page 11, which no bar or form uses.
local DRUID_FIRST_SLOT = 121
local OLD_BINDING = "MULTIACTIONBAR7BUTTON%d"
local EMPTY_TOOLTIP = "Empty slot: drag a spell, item or macro here."
local ICON_CROP = 0.07
local RANGE_INTERVAL = 0.2

_G.BINDING_HEADER_REFORGEDUI = "Reforged UI"
for i, where in ipairs({ "top", "middle", "bottom" }) do
	_G["BINDING_NAME_" .. BINDING:format(i)] = ("Minimap action slot %d (%s)"):format(i, where)
end

local isSecret, plain = ns.IsSecret, ns.IsKnown

-- C_ActionBar's version of an action API where the client has it, else the
-- old global.
local function api(name)
	return (C_ActionBar and C_ActionBar[name]) or _G[name]
end

local function call(name, ...)
	local fn = api(name)
	if not fn then
		return nil
	end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then
		return a, b, c, d
	end
end

local function characterKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- The action slot behind minimap slot `i` for this character.
local function isDruid()
	local _, class = UnitClass("player")
	return class == "DRUID"
end

function ns:MinimapSlot(i)
	return (isDruid() and DRUID_FIRST_SLOT or 109) + i - 1
end

-- A secret answer counts as yes (only widgets may look at it).
local function yes(v)
	return v ~= nil and (isSecret(v) or v ~= false)
end

local function hasAction(slot)
	return yes(call("HasAction", slot))
end

----------------------------------------------------------------------------
-- Display

local function onEnter(b)
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	if hasAction(b.slot) and GameTooltip.SetAction then
		GameTooltip:SetAction(b.slot)
	else
		GameTooltip:SetText(EMPTY_TOOLTIP, 1, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

local function updateIcon(b)
	local texture = call("GetActionTexture", b.slot)
	if type(texture) ~= "nil" then
		b.icon:SetTexture(texture)
		b.icon:Show()
	else
		b.icon:Hide()
	end
end

local function updateCooldown(b)
	if not hasAction(b.slot) then
		b.cooldown:Clear()
		return
	end
	local getDuration = api("GetActionCooldownDuration")
	if getDuration and b.cooldown.SetCooldownFromDurationObject then
		local ok, duration = pcall(getDuration, b.slot)
		if ok and duration and pcall(b.cooldown.SetCooldownFromDurationObject, b.cooldown, duration) then
			return
		end
	end
	local start, duration, enable = call("GetActionCooldown", b.slot)
	if type(start) == "table" then
		start, duration, enable = start.startTime, start.duration, start.isEnabled
	end
	if plain(start) and plain(duration) and plain(enable) and enable and duration > 0 then
		b.cooldown:SetCooldown(start, duration)
	else
		b.cooldown:Clear()
	end
end

-- Cooldown numbers follow the game's "Show cooldown numbers" option
-- (countdownForCooldowns), as on Blizzard's buttons; CooldownFrameTemplate
-- would show them always.
local function updateCountdown(b)
	local show = GetCVarBool and GetCVarBool("countdownForCooldowns") or false
	b.cooldown:SetHideCountdownNumbers(not show)
end

local function updateCount(b)
	local slot = b.slot
	local text = ""
	if hasAction(slot) then
		local display = call("GetActionDisplayCount", slot)
		if type(display) ~= "nil" then
			text = display
		elseif call("IsConsumableAction", slot) or call("IsStackableAction", slot) then
			local count = call("GetActionCount", slot)
			text = plain(count) and tostring(count) or count or ""
		end
	end
	pcall(b.count.SetText, b.count, text)
end

-- Greyed out when unusable, blue when out of power.
local function updateUsable(b)
	if not hasAction(b.slot) then
		return
	end
	local usable, noPower = call("IsUsableAction", b.slot)
	if not plain(usable) or usable then
		b.icon:SetVertexColor(1, 1, 1)
	elseif plain(noPower) and noPower then
		b.icon:SetVertexColor(0.5, 0.5, 1)
	else
		b.icon:SetVertexColor(0.4, 0.4, 0.4)
	end
end

local function updateState(b)
	local current, repeating = call("IsCurrentAction", b.slot), call("IsAutoRepeatAction", b.slot)
	b:SetChecked((plain(current) and current or plain(repeating) and repeating) and true or false)
end

-- Out of range of the target: the key turns red, as on Blizzard's buttons
-- (the icon keeps its colour). `checks` is false when there is nothing to
-- measure (no target, or an action without a range).
local function setRange(b, checks, inRange)
	local red = plain(checks) and checks and plain(inRange) and not inRange
	if red then
		b.hotkey:SetTextColor(1, 0.1, 0.1)
	else
		b.hotkey:SetTextColor(b.keyR, b.keyG, b.keyB)
	end
end

-- Clients without range check events: IsActionInRange is nil when range
-- can't be told (no target), else true or false.
local function pollRange(b)
	local inRange = hasAction(b.slot) and call("IsActionInRange", b.slot)
	setRange(b, plain(inRange) and inRange ~= nil, inRange)
end

local function updateHotkey(b)
	local key = GetBindingKey(BINDING:format(b.index))
	local text = key and GetBindingText and GetBindingText(key, 1) or key or ""
	b.hotkey:SetText(text)
end

local function updateAll(b)
	updateIcon(b)
	updateCooldown(b)
	updateCount(b)
	updateUsable(b)
	updateState(b)
	updateHotkey(b)
	if GameTooltip.GetOwner and GameTooltip:GetOwner() == b then
		onEnter(b)
	end
end

----------------------------------------------------------------------------
-- Buttons

local function barsLocked()
	if Settings and Settings.GetValue then
		local ok, locked = pcall(Settings.GetValue, "lockActionBars")
		if ok and locked ~= nil then
			return locked
		end
	end
	return LOCK_ACTIONBAR == "1"
end

local function onDragStart(b)
	if InCombatLockdown() then
		return
	end
	if not barsLocked() or (IsModifiedClick and IsModifiedClick("PICKUPACTION")) then
		call("PickupAction", b.slot)
		updateAll(b)
	end
end

local function onReceiveDrag(b)
	if InCombatLockdown() then
		return
	end
	call("PlaceAction", b.slot)
	updateAll(b)
end

function MinimapBar:CreateButton(i)
	local b = CreateFrame("CheckButton", BUTTON_NAME .. i, ns.root, "SecureActionButtonTemplate")
	b.index, b.slot = i, ns:MinimapSlot(i)
	b:SetFrameStrata("LOW")
	b:SetFrameLevel(20)
	b:SetAttribute("type", "action")
	b:SetAttribute("action", b.slot)
	b:SetAttribute("checkselfcast", true)
	b:SetAttribute("checkfocuscast", true)
	b:SetAttribute("checkmouseovercast", true)
	-- Mouse clicks act on release; key presses follow "cast on key down"
	-- (SecureActionButtonTemplate decides).
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:RegisterForDrag("LeftButton", "RightButton")

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	b.icon = icon
	ns:IconFrame(b)
	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	-- Count and key above the cooldown swipe.
	local text = CreateFrame("Frame", nil, b)
	text:SetAllPoints()
	text:SetFrameLevel(b:GetFrameLevel() + 3)
	b.count = text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.hotkey = text:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	b.hotkey:SetPoint("TOPRIGHT", -2, -2)
	b.keyR, b.keyG, b.keyB = b.hotkey:GetTextColor()
	b.keyR, b.keyG, b.keyB = b.keyR or 0.6, b.keyG or 0.6, b.keyB or 0.6
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local checked = b:CreateTexture(nil, "OVERLAY")
	checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	checked:SetBlendMode("ADD")
	checked:SetAllPoints()
	b:SetCheckedTexture(checked)

	b:SetScript("OnEnter", onEnter)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnDragStart", onDragStart)
	b:SetScript("OnReceiveDrag", onReceiveDrag)
	b:HookScript("PostClick", updateAll)
	return b
end

function MinimapBar:OnEnable()
	self.buttons = {}
	for i = 1, COUNT do
		self.buttons[i] = self:CreateButton(i)
	end
	local all = function() self:UpdateAll() end
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
		"UPDATE_SHAPESHIFT_FORM", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
		ns:On(event, all)
	end
	local each = function(fn) return function() for _, b in ipairs(self.buttons) do fn(b) end end end
	for _, event in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
		"BAG_UPDATE_COOLDOWN", "LOSS_OF_CONTROL_UPDATE" }) do
		ns:On(event, each(updateCooldown))
	end
	for _, event in ipairs({ "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_USABLE", "UNIT_POWER_FREQUENT",
		"PLAYER_TARGET_CHANGED" }) do
		ns:On(event, each(updateUsable))
	end
	for _, event in ipairs({ "ACTIONBAR_UPDATE_STATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
		"START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT" }) do
		ns:On(event, each(updateState))
	end
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED" }) do
		ns:On(event, each(updateCount))
	end
	-- Range: the client reports it per slot once asked to (as for
	-- Blizzard's own buttons); older clients are polled.
	if api("EnableActionRangeCheck") then
		for _, b in ipairs(self.buttons) do
			call("EnableActionRangeCheck", b.slot, true)
		end
		ns:On("ACTION_RANGE_CHECK_UPDATE", function(_, slot, inRange, checks)
			for _, b in ipairs(self.buttons) do
				if b.slot == slot then
					setRange(b, checks, inRange)
				end
			end
		end)
	else
		local ticker = CreateFrame("Frame", nil, ns.root)
		local elapsed = 0
		ticker:SetScript("OnUpdate", function(_, dt)
			elapsed = elapsed + dt
			if elapsed >= RANGE_INTERVAL then
				elapsed = 0
				for _, b in ipairs(self.buttons) do
					pollRange(b)
				end
			end
		end)
	end

	ns:On("CVAR_UPDATE", function(_, name)
		if type(name) == "string" and name:lower() == "countdownforcooldowns" then
			for _, b in ipairs(self.buttons) do
				updateCountdown(b)
			end
		end
	end)

	ns:On("PLAYER_ENTERING_WORLD", function()
		-- Whether the addon turned Action Bar 8 on in an earlier session
		-- (read before this session's EnableBars runs).
		if self.addonBar8 == nil then
			self.addonBar8 = ns.db.consoleOpts.barsEnabled[characterKey()] and true or false
		end
		C_Timer.After(2, function()
			self:MoveFromBar8()
			self:PlaceHearthstone()
			self:UpdateAll()
		end)
	end)
end

function MinimapBar:UpdateAll()
	for _, b in ipairs(self.buttons) do
		updateAll(b)
	end
end

-- Built at an action button's own size and scaled down onto the slot, like
-- the grid's buttons (ActionBars.lua), so the key, count and cooldown text
-- come out at the same size as theirs.
local BUTTON_SIZE = 45
local function placeButton(b, r)
	local scale = r.w / BUTTON_SIZE
	b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	b:SetScale(scale)
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.x / scale, r.y / scale)
end

function MinimapBar:OnLayout(L)
	ns:RunOutOfCombat("minimap-bar", function()
		for i, b in ipairs(self.buttons) do
			placeButton(b, L.minimapSlots[i])
		end
	end)
	for _, b in ipairs(self.buttons) do
		updateCountdown(b)
	end
	self:UpdateAll()
end

----------------------------------------------------------------------------
-- Once per character

-- Actions and key bindings of Action Bar 8's first three buttons move onto
-- the minimap slots (an occupied slot keeps what it has), and Action Bar 8 is
-- turned off again if the addon had turned it on.
function MinimapBar:MoveFromBar8()
	local key = characterKey()
	local done = ns.db.consoleOpts.minimapBarMoved
	if done[key] or InCombatLockdown() or GetCursorInfo() then
		return
	end
	local ok, err = pcall(function()
		for i = 1, COUNT do
			local old, new = OLD_FIRST_SLOT + i - 1, ns:MinimapSlot(i)
			if old ~= new and hasAction(old) and not hasAction(new) then
				call("PickupAction", old)
				call("PlaceAction", new)
				-- Refused by the slot: the action goes back where it was.
				if GetCursorInfo() then
					call("PlaceAction", old)
				end
				ClearCursor()
			end
		end
		local rebound = false
		for i = 1, COUNT do
			local target = BINDING:format(i)
			if not GetBindingKey(target) then
				for _, k in ipairs({ GetBindingKey(OLD_BINDING:format(i)) }) do
					SetBinding(k, target)
					rebound = true
				end
			end
		end
		if rebound and SaveBindings and GetCurrentBindingSet then
			SaveBindings(GetCurrentBindingSet())
		end
		if self.addonBar8 then
			local setting = Settings and Settings.GetSetting and Settings.GetSetting("PROXY_SHOW_ACTIONBAR_8")
			if setting then
				setting:SetValue(false)
			elseif GetActionBarToggles and SetActionBarToggles then
				local toggles = { GetActionBarToggles() }
				if #toggles >= 7 then
					toggles[7] = false
					SetActionBarToggles(unpack(toggles))
				end
			end
		end
	end)
	if ok then
		done[key] = true
	else
		geterrorhandler()(err)
	end
end

-- The original addon puts a hearthstone in the first slot beside the
-- minimap, once per character, when that slot is empty.
-- Druids got it on the shaman totem slots up to 1.15, which refused it, so
-- each druid gets one more try on their new slots.
function MinimapBar:PlaceHearthstone()
	local key = characterKey()
	local opts = ns.db.consoleOpts
	local done = opts.hearthstone
	if isDruid() and not opts.druidSlotsMoved[key] then
		opts.druidSlotsMoved[key] = true
		done[key] = nil
	end
	if done[key] or InCombatLockdown() or GetCursorInfo() then
		return
	end
	local ok, finished = pcall(function()
		local slot = ns:MinimapSlot(1)
		if hasAction(slot) or (C_Item.GetItemCount(HEARTHSTONE) or 0) == 0 then
			return true
		end
		C_Item.PickupItem(HEARTHSTONE)
		if GetCursorInfo() == "item" then
			call("PlaceAction", slot)
		end
		ClearCursor()
		return hasAction(slot)
	end)
	if ok and finished then
		done[key] = true
	end
end
