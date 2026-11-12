-- Edit Mode: the account-wide "Reforged UI" layout and the Blizzard frames
-- placed through it (cast bar, buffs, pet bar, leave vehicle button, target
-- frame, action bars 1-3). Everything here only edits the saved layouts
-- (C_EditMode.GetLayouts / SaveLayouts): it is Edit Mode that then moves the
-- frames, so every one of them can still be moved and changed there.

local _, ns = ...

local forbidden = ns.IsForbidden

-- Earlier versions anchored Blizzard frames to our console, and Edit Mode
-- saved those anchors into the player's layouts (stored by the game, so the
-- warning stayed even with the addon off). Put any such frame back in its
-- default position once.
function ns:RepairEditModeLayouts()
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
		return
	end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
		return
	end
	local fixed = 0
	for _, layout in ipairs(info.layouts) do
		for _, system in ipairs(layout.systems or {}) do
			for _, key in ipairs({ "anchorInfo", "anchorInfo2" }) do
				local anchor = system[key]
				if type(anchor) == "table" and type(anchor.relativeTo) == "string"
					and anchor.relativeTo:find("^ReforgedUI") then
					anchor.relativeTo = "UIParent"
					system.isInDefaultPosition = true
					fixed = fixed + 1
				end
			end
		end
	end
	if fixed > 0 and pcall(C_EditMode.SaveLayouts, info) then
		ns:AskReload(("reset %d Edit Mode position(s) left over from an older version."):format(fixed))
	end
end

-- Edit Mode layout. Each character is switched once to an account-wide
-- "Reforged UI" layout, made (once) as a copy of the layout in use, with:
--  * the cast bar just above the console (its default place is under it, and
--    moving it from addon code breaks Blizzard's own, see Blizzard.lua);
--  * raid-style party frames, and the raid frames' options (class colours,
--    power bars, debuffs) turned on when the layout is made;
--  * Blizzard's target frame, buffs on top, placed so its aura icons (all
--    that is left visible of it, see Target.lua) stand beside the target of
--    target. Placed again at each login and target mode change, as it
--    follows the console's layout;
--  * buffs just below the top bar, debuffs under them (in every layout
--    where they are still in their default place).
-- It is all saved in the layout, so it is Edit Mode that applies it and
-- every piece can still be moved and changed there. A cast bar that is still
-- in its default place in any other layout of the player's own is raised too.
ns.EDIT_LAYOUT = "Reforged UI"
local CAST_BAR_GAP = 8
local RAID_CVARS = {
	raidFramesDisplayClassColor = "1", raidFramesDisplayPowerBars = "1",
	raidFramesDisplayOnlyHealerPowerBars = "0", raidFramesDisplayDebuffs = "1",
	raidFramesDisplayAggroHighlight = "1", raidFramesDisplayIncomingHeals = "1",
	raidOptionDisplayMainTankAndAssist = "1", raidFramesHealthText = "perc",
}

local function deepCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and deepCopy(v) or v
	end
	return out
end

local function setSetting(system, setting, value)
	if setting == nil then
		return
	end
	system.settings = system.settings or {}
	for _, entry in ipairs(system.settings) do
		if entry.setting == setting then
			entry.value = value
			return
		end
	end
	system.settings[#system.settings + 1] = { setting = setting, value = value }
end

local function findSystem(layout, system, index)
	for _, sys in ipairs(layout.systems or {}) do
		if sys.system == system and (index == nil or sys.systemIndex == index) then
			return sys
		end
	end
end

-- What a layout is remembered by in consoleOpts.editPlaced: its name, and
-- for a character's own layout, the character too.
local function layoutKey(layout)
	local name = tostring(layout.layoutName or "?")
	local character = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character
	if character ~= nil and layout.layoutType == character then
		name = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") .. ":" .. name
	end
	return name
end

----------------------------------------------------------------------------
-- Frames placed in every layout
--
-- Each has an entry in PLACEMENTS (further down), and they all follow one
-- rule (wantsPlacing): a frame is ours to place while it is still in its
-- default place in a layout we haven't placed it in yet, or still where we
-- put it last after a setting all characters share has changed. Anywhere
-- else it is the player's, and stays.

local function near(v, want)
	return type(v) == "number" and math.abs(v - want) <= 2
end

-- Whether an Edit Mode anchor holds a frame by `corner` to the same corner
-- of the screen, at `spot`.
local function anchoredAt(a, corner, spot)
	return a.point == corner and (a.relativeTo == nil or a.relativeTo == "UIParent") and a.relativePoint == corner
		and near(a.offsetX, spot.x) and near(a.offsetY, spot.y)
end

-- `last`: where we put it last (nil unless it is to follow from there);
-- `fresh`: the layout hasn't been placed before; `spots`: other spots that
-- count as in place too.
local function wantsPlacing(entry, corner, spot, last, fresh, spots)
	if entry.isInDefaultPosition and fresh then
		return true
	end
	local a = entry.anchorInfo or {}
	if not (last and anchoredAt(a, corner, last)) or anchoredAt(a, corner, spot) then
		return false
	end
	for _, other in ipairs(spots or {}) do
		if anchoredAt(a, corner, other) then
			return false
		end
	end
	return true
end

local function anchorTo(entry, corner, spot)
	entry.anchorInfo = { point = corner, relativeTo = "UIParent", relativePoint = corner,
		offsetX = spot.x, offsetY = spot.y }
	entry.anchorInfo2 = nil
	entry.isInDefaultPosition = false
end

-- The cast bar goes just above the console (never follows: once raised it
-- is the player's), unless it is locked to the player frame.
local function castBarSpot(self)
	local bar = _G.PlayerCastingBarFrame
	local scale = bar and bar:GetScale() or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	return { x = 0, y = math.floor((self.layout.consoleTop * self:ConsoleScale() + CAST_BAR_GAP) / scale + 0.5) }
end

local function raiseCastBar(_, layout, spot, _, fresh)
	local y = spot.y
	local sys = findSystem(layout, Enum.EditModeSystem.CastBar)
	if not (sys and sys.isInDefaultPosition and fresh) then
		return false
	end
	local lock = Enum.EditModeCastBarSetting and Enum.EditModeCastBarSetting.LockToPlayerFrame
	for _, setting in ipairs(sys.settings or {}) do
		if lock and setting.setting == lock and setting.value == 1 then
			return false
		end
	end
	sys.anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = y }
	sys.isInDefaultPosition = false
	return true
end

-- Buffs start in the top-right corner just below the top bar (Blizzard's
-- default place is under it), or at the screen's top edge with the top bar
-- hidden; debuffs under the buffs. Placed in every
-- layout where they are still in their default place, or still where we
-- put them last (so a new top bar scale carries them along); once moved in
-- Edit Mode they are the player's. Like the pet bar and the leave button
-- they only follow after a shared setting changes (EditSpotKey).
local BUFF_GAP, BUFF_RIGHT = 6, 12

function ns:BuffSpot()
	local buffs = _G.BuffFrame
	if not (buffs and not forbidden(buffs) and self.topRoot and self.topLayout) then
		return nil
	end
	local s = self.topRoot:GetEffectiveScale() / buffs:GetEffectiveScale()
	local barH = self:TopBarShown() and self.topLayout.topBar.h or 0
	return { x = math.floor(-BUFF_RIGHT * s + 0.5), y = math.floor(-(barH + BUFF_GAP) * s + 0.5) }
end

local function placeBuffs(_, layout, spot, last, fresh)
	local sys, indices = Enum.EditModeSystem, Enum.EditModeAuraFrameSystemIndices
	local buffs = sys.AuraFrame and indices and findSystem(layout, sys.AuraFrame, indices.BuffFrame)
	if not (buffs and spot) then
		return false
	end
	local changed = false
	if wantsPlacing(buffs, "TOPRIGHT", spot, last, fresh) then
		anchorTo(buffs, "TOPRIGHT", spot)
		changed = true
	end
	local debuffs = findSystem(layout, sys.AuraFrame, indices.DebuffFrame)
	if debuffs and debuffs.isInDefaultPosition and fresh then
		debuffs.anchorInfo = { point = "TOPRIGHT", relativeTo = "BuffFrame", relativePoint = "BOTTOMRIGHT",
			offsetX = 0, offsetY = -BUFF_GAP }
		debuffs.anchorInfo2 = nil
		debuffs.isInDefaultPosition = false
		changed = true
	end
	return changed
end

-- The pet bar starts just above the stance row on the console wall
-- (Blizzard's default place is over the console). Like the buffs it is placed
-- in every layout where it is still in its default place, or still where we
-- put it last after a shared setting changed (so a new console scale
-- carries it along, see EditSpotKey); once moved in Edit Mode it is the
-- player's.
function ns:PetBarInEditMode()
	local indices = Enum and Enum.EditModeActionBarSystemIndices
	local bar = _G.PetActionBar
	return indices and indices.PetActionBar ~= nil and bar ~= nil and not forbidden(bar)
		and C_EditMode ~= nil and C_EditMode.SaveLayouts ~= nil or false
end

-- The pet row is just above the stance row; without stance buttons (as for
-- most pet classes) the pet bar takes the stance row itself.
function ns:PetRow(L)
	L = L or self.layout
	local forms = _G.GetNumShapeshiftForms
	if L and L.stance and forms and (forms() or 0) == 0 then
		return L.stance
	end
	return L and L.pet
end

function ns:PetBarSpot(row)
	row = row or self:PetRow()
	if not (row and self:PetBarInEditMode()) then
		return nil
	end
	local u = self:UnitsFor(_G.PetActionBar)
	return { x = math.floor(row.x * u + 0.5), y = math.floor(row.y * u + 0.5),
		size = row.size * u, padding = (row.step - row.size) * u }
end

-- Both rows the pet bar may be placed on: which one depends on the
-- character (stance buttons or not), but the layout is shared by all of
-- them, so a bar on either row counts as in place.
function ns:PetBarSpots()
	local L = self.layout
	local spots = {}
	for _, row in ipairs({ L and L.pet, L and L.stance }) do
		local spot = self:PetBarSpot(row)
		if spot then
			spots[#spots + 1] = spot
		end
	end
	return spots
end

local BUTTON_SIZE = 45 -- an action button at 100% icon size
local PET_BUTTON_SIZE = 30 -- a pet button at 100% icon size
local BAR_PADDING = 8

-- Sets an Edit Mode bar's icon size (`scale` of its buttons' own size, in
-- 10% steps) and padding. Layouts store sliders either as the value or as
-- the step index from the minimum: the icon size tells which.
local function setIconSize(entry, settings, scale, padding)
	local stored
	for _, s in ipairs(entry.settings or {}) do
		if s.setting == settings.IconSize then
			stored = s.value
		end
	end
	local indexed = stored ~= nil and stored <= 15
	local pct = math.max(50, math.min(200, math.floor(scale * 10 + 0.5) * 10))
	setSetting(entry, settings.IconSize, indexed and (pct - 50) / 10 or pct)
	setSetting(entry, settings.IconPadding, indexed and padding - 2 or padding)
end

local function placePetBar(self, layout, spot, last, fresh)
	local sys, indices = Enum.EditModeSystem, Enum.EditModeActionBarSystemIndices
	local pet = spot and sys.ActionBar and indices and indices.PetActionBar
		and findSystem(layout, sys.ActionBar, indices.PetActionBar)
	if not (pet and wantsPlacing(pet, "BOTTOMLEFT", spot, last, fresh, self:PetBarSpots())) then
		return false
	end
	-- Placed the first time at about the stance buttons' size, so the row
	-- fits over the grid; after that the size is the player's.
	local settings = Enum.EditModeActionBarSetting
	if pet.isInDefaultPosition and settings and settings.IconSize then
		setIconSize(pet, settings, spot.size / PET_BUTTON_SIZE, math.max(2, math.floor(spot.padding + 0.5)))
	end
	anchorTo(pet, "BOTTOMLEFT", spot)
	return true
end

-- The leave vehicle button (also the flight path's "request stop") starts
-- just above the minimap's top-left corner (Layout.lua); Blizzard's default
-- place is under the top bar, over its slots. Placed in every layout where
-- it is still in its default place. It only follows (from where we put it
-- last) when a setting all characters share changes (EditSpotKey): the
-- spot itself differs a little from character to character and login to
-- login (theme, menu buttons, the button's scale), but the layout is shared,
-- so following that moved it, saved the layouts and asked for a reload on
-- every relog.
function ns:LeaveButtonSpot()
	local button = _G.MainMenuBarVehicleLeaveButton
	local spot = self.layout and self.layout.leaveButton
	local systems = Enum and Enum.EditModeSystem
	if not (spot and button and not forbidden(button) and systems and systems.VehicleLeaveButton) then
		return nil
	end
	local u = self:UnitsFor(button)
	return { x = math.floor(spot.x * u + 0.5), y = math.floor(spot.y * u + 0.5) }
end

-- What the buffs', pet bar's and leave button's spots depend on that is
-- the same for every character: the screen and the account-wide options.
-- The spots also differ between characters (theme, stance buttons, menu
-- buttons) and logins (frame scales), but the Edit Mode layouts are shared,
-- so frames we placed only follow a change of this.
function ns:EditSpotKey()
	local o = self.db.consoleOpts
	return table.concat({ math.floor(UIParent:GetWidth() + 0.5), math.floor(UIParent:GetHeight() + 0.5),
		tostring(self.db.scale), tostring(self.db.layout), tostring(o.uiScale), tostring(o.uiSize),
		tostring(o.chatWiden), tostring(not not o.hideTopBar), tostring(self.db.theme) }, " ")
end

local function placeLeaveButton(_, layout, spot, last, fresh)
	local entry = spot and findSystem(layout, Enum.EditModeSystem.VehicleLeaveButton)
	if not (entry and wantsPlacing(entry, "BOTTOMLEFT", spot, last, fresh)) then
		return false
	end
	anchorTo(entry, "BOTTOMLEFT", spot)
	return true
end

-- The frames placed in every layout, in the order their reload messages
-- take precedence. To place another Blizzard frame, add an entry:
--   key      its name here (and in the smoke test);
--   saved    the consoleOpts key that remembers where we put it last, for
--            it to follow from (none: placed once, never follows);
--   spot     function(ns): where it goes now as { x, y } (nil: not placed);
--   place    function(ns, layout, spot, last, fresh): moves it in `layout`
--            if it is ours to place (wantsPlacing), true if it did;
--   message  function(n, moved): what the reload popup says after it was
--            placed in n layouts (`moved`: the count for every key).
-- Each entry needs an Edit Mode system and a `saved` key of its own
-- (tools/smoke_test.lua checks the keys, and that placing twice changes
-- nothing the second time).
local PLACEMENTS = {
	{
		key = "castBar",
		spot = castBarSpot,
		place = raiseCastBar,
		message = function(n)
			return ("moved the cast bar above the console in %d Edit Mode layout(s)."):format(n)
		end,
	},
	{
		key = "buffs", saved = "buffSpot",
		spot = function(self) return self:BuffSpot() end,
		place = placeBuffs,
		message = function(n, moved)
			return ("placed your buffs below the top bar%s in %d Edit Mode layout(s); move them there as you"
				.. " like."):format(moved.petBar > 0 and " and the pet bar on the console wall" or "",
				math.max(n, moved.petBar))
		end,
	},
	{
		key = "petBar", saved = "petSpot",
		spot = function(self) return self:PetBarSpot() end,
		place = placePetBar,
		message = function(n)
			return ("placed the pet bar on the console wall in %d Edit Mode layout(s); move it there as"
				.. " you like."):format(n)
		end,
	},
	{
		key = "leaveButton", saved = "leaveSpot",
		spot = function(self) return self:LeaveButtonSpot() end,
		place = placeLeaveButton,
		message = function(n)
			return ("placed the leave vehicle (and flight path stop) button above the minimap in %d Edit Mode"
				.. " layout(s); move it there as you like."):format(n)
		end,
	},
}
ns.EditPlacements = PLACEMENTS

local function setCVar(name, value)
	local cvars = _G.C_CVar
	local get = cvars and cvars.GetCVar or _G.GetCVar
	local set = cvars and cvars.SetCVar or _G.SetCVar
	if get and set and get(name) ~= nil then
		pcall(set, name, value)
	end
end

-- Blizzard puts the first aura icon's bottom-left corner this far from its
-- target frame's top-left corner when buffs are on top (TargetFrame.lua).
local TARGET_AURA_X, TARGET_AURA_Y = 5, -15
local targetFrameCorner -- below
ns.TARGET_AURA_X, ns.TARGET_AURA_Y = TARGET_AURA_X, TARGET_AURA_Y

-- A target frame within this many UI units of where we put it is still ours.
local TARGET_MOVE_SLACK = 8

-- Where an Edit Mode anchor puts the target frame's top-left corner, as
-- UIParent BOTTOMLEFT offsets like ours (nil: anchored to another frame).
-- Edit Mode offsets are in UIParent units (ApplySystemAnchor divides them
-- by the frame's scale itself).
local POINT_X = { LEFT = 0, CENTER = 0.5, RIGHT = 1 }
local POINT_Y = { BOTTOM = 0, CENTER = 0.5, TOP = 1 }
local function pointFraction(point)
	if type(point) ~= "string" then
		return nil
	end
	local v = point:match("^(TOP)") or point:match("^(BOTTOM)") or "CENTER"
	local h = point:match("(LEFT)$") or point:match("(RIGHT)$") or "CENTER"
	return POINT_X[h], POINT_Y[v]
end

targetFrameCorner = function(a)
	if not (type(a.offsetX) == "number" and type(a.offsetY) == "number")
		or not (a.relativeTo == nil or a.relativeTo == "UIParent") then
		return nil
	end
	local px, py = pointFraction(a.point)
	local rx, ry = pointFraction(a.relativePoint or a.point)
	local tf, ui = _G.TargetFrame, _G.UIParent
	local ok, w, h, W, H = pcall(function()
		local scale = tf:GetScale()
		return tf:GetWidth() * scale, tf:GetHeight() * scale, ui:GetWidth(), ui:GetHeight()
	end)
	if not (px and rx and ok and type(w) == "number" and type(h) == "number" and type(W) == "number"
		and type(H) == "number") then
		return nil
	end
	return rx * W + a.offsetX - px * w, ry * H + a.offsetY + (1 - py) * h
end

-- The "Target aura size" option: Edit Mode's Frame Size for the target
-- frame (100-200 % in steps of 5), which is all that makes its aura icons
-- bigger. Blizzard wraps a row of them at AURA_ROW_WIDTH (122 at 100 %),
-- so the size is kept to what fits on the wall between the target of target
-- and the stance row (`spot`, in console units).
ns.TARGET_AURA_SIZE_MIN, ns.TARGET_AURA_SIZE_MAX = 100, 200
local TARGET_AURA_ROW = 122

-- The size wanted (nil: as Edit Mode has it), and the size that fits.
function ns:TargetAuraSize(spot)
	local p = tonumber(self.db.consoleOpts.targetAuraSize)
	if not p then
		return nil
	end
	p = math.max(self.TARGET_AURA_SIZE_MIN, math.min(self.TARGET_AURA_SIZE_MAX, math.floor(p / 5 + 0.5) * 5))
	local fit = p
	if spot and spot.x1 and spot.x0 then
		local room = (spot.x1 - spot.x0) * self:ConsoleScale() - TARGET_AURA_X
		fit = math.floor(room / TARGET_AURA_ROW * 100 / 5) * 5
	end
	return p, math.max(self.TARGET_AURA_SIZE_MIN, math.min(p, fit))
end

-- Tells the player the target aura size, and when it is more than fits.
function ns:SayTargetAuraSize()
	local target = self.modules.target
	local want, fit = self:TargetAuraSize(target and target.enabled and target:AuraSpot())
	if not want then
		self:Print("target aura size: as Edit Mode has it.")
	elseif fit < want then
		self:Print(("target aura size: %d%% (%d%% is all that fits on the wall at this UI size)."):format(want, fit))
	else
		self:Print(("target aura size: %d%%."):format(want))
	end
end

-- Places the target frame in `layout`; true if that changed it, and where
-- it went (to remember once the layout is saved). Once the player has moved
-- it in Edit Mode (anywhere but where we put it last) it is theirs: only
-- its settings are kept, until `/rui auras reset`.
function ns:PlaceTargetAuras(layout)
	local frames, sys = Enum.EditModeUnitFrameSystemIndices, Enum.EditModeSystem
	local target = self.modules.target
	local spot = target and target.enabled and target:AuraSpot()
	local tf = frames and sys.UnitFrame and findSystem(layout, sys.UnitFrame, frames.Target)
	if not (spot and tf) then
		return false
	end
	local o = self.db.consoleOpts
	local a = tf.anchorInfo or {}
	local atOurs = a.point == "TOPLEFT" and (a.relativeTo == nil or a.relativeTo == "UIParent")
		and a.relativePoint == "BOTTOMLEFT" and not tf.isInDefaultPosition
	-- Our last few places count as ours: a game that hands a layout back
	-- unchanged must not make the frame look moved by the player. Compared
	-- by where the frame's top-left corner lands, a few units either way:
	-- a click on it in Edit Mode re-anchors it (another point, snapped)
	-- without really moving it.
	local last, ours = o.targetAuraLast, false
	local cx, cy = targetFrameCorner(a)
	for _, p in ipairs(type(last) == "table" and last or {}) do
		ours = ours or (atOurs and near(a.offsetX, p.x) and near(a.offsetY, p.y))
			or (cx and math.abs(cx - p.x) <= TARGET_MOVE_SLACK and math.abs(cy - p.y) <= TARGET_MOVE_SLACK) or false
	end
	if not o.targetAuraOwn and type(last) == "table" and #last > 0 and not tf.isInDefaultPosition and not ours then
		o.targetAuraOwn = true
	end
	local own = o.targetAuraOwn and not tf.isInDefaultPosition
	if not own then
		o.targetAuraOwn = nil
	end
	local k = self:ConsoleScale()
	local sizeSetting = Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.FrameSize
	local _, size = self:TargetAuraSize(not own and spot or nil)
	size = sizeSetting and size
	local scale = size and size / 100 or TargetFrame and TargetFrame:GetScale() or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	-- Edit Mode keeps offsets in UIParent units and divides them by the
	-- frame's scale itself (EditModeSystemMixin:ApplySystemAnchor); only the
	-- first icon's place inside the frame scales with it.
	local x = math.floor(spot.x0 * k - TARGET_AURA_X * scale + 0.5)
	local y = math.floor(spot.y * k - TARGET_AURA_Y * scale + 0.5)
	local changed, at = false, nil
	if not own then
		-- The game hands saved offsets back rounded its own way, so a pixel
		-- or two either way counts as already in place (otherwise every
		-- login would save the layout again and ask for a reload).
		local inPlace = atOurs and near(a.offsetX, x) and near(a.offsetY, y)
		changed = not inPlace
		if inPlace then
			x, y = a.offsetX, a.offsetY
		end
		tf.anchorInfo = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", offsetX = x, offsetY = y }
		tf.anchorInfo2 = nil
		tf.isInDefaultPosition = false
		at = { x = x, y = y }
	end
	local onTop = Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.BuffsOnTop
	if onTop then
		local set = false
		for _, entry in ipairs(tf.settings or {}) do
			set = set or (entry.setting == onTop and entry.value ~= 0 and entry.value ~= false)
		end
		changed = changed or not set
		setSetting(tf, onTop, 1)
	end
	-- Edit Mode keeps a slider's step, not its value: (size - 100) / 5.
	if size then
		local stored = (size - ns.TARGET_AURA_SIZE_MIN) / 5
		local was
		for _, entry in ipairs(tf.settings or {}) do
			if entry.setting == sizeSetting then
				was = entry.value
			end
		end
		changed = changed or was ~= stored
		setSetting(tf, sizeSetting, stored)
	end
	return changed, at
end

-- With "Let Edit Mode place the action bars", bars 1-3 keep their buttons
-- and are only pre-placed (once) in our layout, over the console's grid
-- rows at about the grid's button size. After that they are the player's to
-- move, resize and reflow in Edit Mode.
local ACTION_BARS = {
	{ index = "MainBar", row = "main", frame = { "MainActionBar", "MainMenuBar" } },
	{ index = "Bar2", row = "bar2", frame = { "MultiBarBottomLeft" } },
	{ index = "Bar3", row = "bar3", frame = { "MultiBarBottomRight" } },
}

function ns:PlaceActionBars(layout)
	local o, L = self.db.consoleOpts, self.layout
	local sys, indices = Enum.EditModeSystem, Enum.EditModeActionBarSystemIndices
	local settings = Enum.EditModeActionBarSetting
	if not (o.editModeBars and not o.barsPlaced and sys and sys.ActionBar and indices and L and L.bars) then
		return false
	end
	local changed = false
	for _, spec in ipairs(ACTION_BARS) do
		local entry = indices[spec.index] and findSystem(layout, sys.ActionBar, indices[spec.index])
		local row = L.bars[spec.row]
		local frame
		for _, name in ipairs(spec.frame) do
			frame = frame or _G[name]
		end
		if entry and row and row.xs and row.xs[1] then
			local u = frame and self:UnitsFor(frame) or self:ConsoleScale()
			entry.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
				offsetX = math.floor(row.xs[1] * u + 0.5), offsetY = math.floor(row.y * u + 0.5) }
			entry.anchorInfo2 = nil
			entry.isInDefaultPosition = false
			-- Icon size in 10% steps, near the grid's cells; padding 8 with
			-- the bar art and scrolling hidden and every slot shown (as a
			-- tester found fits).
			if settings and settings.IconSize then
				setIconSize(entry, settings, row.size * u / BUTTON_SIZE, BAR_PADDING)
			end
			if settings then
				setSetting(entry, settings.HideBarArt, 1)
				setSetting(entry, settings.HideBarScrolling, 1)
				setSetting(entry, settings.AlwaysShowButtons, 1)
			end
			changed = true
		end
	end
	return changed
end

-- Until Blizzard's Edit Mode has its layouts (EDIT_MODE_LAYOUTS_UPDATED,
-- which can come after PLAYER_LOGIN), the game may hand us an incomplete
-- list: our layout looks missing and gets made again, and what we save is
-- overwritten when Blizzard's own list arrives. So wait for it.
local function editModeReady()
	local manager = _G.EditModeManagerFrame
	if not (manager and manager.IsInitialized) or forbidden(manager) then
		return true
	end
	local ok, ready = pcall(manager.IsInitialized, manager)
	return not ok or ready
end

-- The active Edit Mode layout's name (nil: one of Blizzard's presets, or
-- unknown), and whether our layout exists.
function ns:ActiveEditLayout()
	local api = C_EditMode
	if not (api and api.GetLayouts) then
		return nil, false
	end
	local ok, info = pcall(api.GetLayouts)
	if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
		return nil, false
	end
	local ours = false
	for _, layout in ipairs(info.layouts) do
		ours = ours or layout.layoutName == ns.EDIT_LAYOUT
	end
	if type(info.activeLayout) ~= "number" then
		return nil, ours
	end
	local presets = 2
	local manager = _G.EditModePresetLayoutManager
	if manager and manager.GetCopyOfPresetLayouts then
		local okP, list = pcall(manager.GetCopyOfPresetLayouts, manager)
		presets = okP and type(list) == "table" and #list or presets
	end
	local layout = info.layouts[info.activeLayout - presets]
	return layout and layout.layoutName or nil, ours
end

-- With another Edit Mode layout active, the target frame (its aura icons)
-- is where that layout has it, and other frames we place only leave their
-- default place: say so in chat, once per layout and session (`force`:
-- again).
local saidLayout
function ns:SayOtherEditLayout(force)
	local name, ours = self:ActiveEditLayout()
	if name == ns.EDIT_LAYOUT or not ours then
		saidLayout = nil
		return false
	end
	local shown = name and ("%q"):format(name) or "a preset"
	if saidLayout == shown and not force then
		return true
	end
	saidLayout = shown
	self:Print(("you're on the %s Edit Mode layout, not %q. Here Reforged UI doesn't place the target's buffs"
		.. " and debuffs, and moves other Blizzard frames (cast bar, buffs, pet bar...) only out of their"
		.. " default place: move them yourself in Edit Mode, or switch back to %q there."):format(
		shown, ns.EDIT_LAYOUT, ns.EDIT_LAYOUT))
	return true
end

-- `why`: what to tell the player should only the target frame move.
function ns:SetupEditMode(why)
	local systems = Enum and Enum.EditModeSystem
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and systems and systems.CastBar
		and self.layout) then
		return
	end
	if not editModeReady() then
		if self.editModeWaiting == nil then
			-- A frame after the event, so after Blizzard's own handler has
			-- taken the layouts in (or failed to: it can raise an error
			-- part way, e.g. on a negative right bar scale).
			self:On("EDIT_MODE_LAYOUTS_UPDATED", function()
				if self.editModeWaiting then
					self.editModeWaiting = false
					C_Timer.After(0, function()
						self:RunOutOfCombat("edit-mode", function() self:SetupEditMode() end)
					end)
				end
			end)
		end
		self.editModeWaiting = true
		return
	end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
		return
	end
	-- The layout list starts with Blizzard's presets, which addons can't change.
	local presets, presetList = 2, nil
	local manager = _G.EditModePresetLayoutManager
	if manager and manager.GetCopyOfPresetLayouts then
		local okP, list = pcall(manager.GetCopyOfPresetLayouts, manager)
		if okP and type(list) == "table" then
			presets, presetList = #list, list
		end
	end

	local index, made
	-- Older versions could make the layout more than once. Layout names
	-- are meant to be unique (Edit Mode errors on two alike), so the first
	-- keeps the name and the others are renamed, keeping what is in them.
	local names, renamed = {}, 0
	for _, layout in ipairs(info.layouts) do
		names[layout.layoutName or ""] = true
	end
	for i, layout in ipairs(info.layouts) do
		if layout.layoutName == ns.EDIT_LAYOUT then
			if not index then
				index = i
			else
				local n = 2
				while names[ns.EDIT_LAYOUT .. " " .. n] do
					n = n + 1
				end
				layout.layoutName = ns.EDIT_LAYOUT .. " " .. n
				names[layout.layoutName] = true
				renamed = renamed + 1
			end
		end
	end
	if not index then
		local active = type(info.activeLayout) == "number" and info.activeLayout or 1
		local base = active > presets and info.layouts[active - presets] or (presetList and presetList[active])
		if type(base) == "table" and type(base.systems) == "table" then
			local layout = deepCopy(base)
			layout.layoutName = ns.EDIT_LAYOUT
			layout.layoutType = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
			local frames = Enum.EditModeUnitFrameSystemIndices
			local party = systems.UnitFrame and frames and findSystem(layout, systems.UnitFrame, frames.Party)
			if party and Enum.EditModeUnitFrameSetting then
				setSetting(party, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames, 1)
			end
			-- The cast bar always gets its place in our layout.
			local cast = findSystem(layout, systems.CastBar)
			if cast then
				cast.isInDefaultPosition = true
				setSetting(cast, Enum.EditModeCastBarSetting and Enum.EditModeCastBarSetting.LockToPlayerFrame, 0)
			end
			-- After the other account-wide layouts, before the character's
			-- own, where the game itself keeps account layouts.
			index = #info.layouts + 1
			local character = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character
			for i, other in ipairs(info.layouts) do
				if character ~= nil and other.layoutType == character then
					index = i
					break
				end
			end
			table.insert(info.layouts, index, layout)
			if type(info.activeLayout) == "number" and info.activeLayout >= presets + index then
				info.activeLayout = info.activeLayout + 1 -- the same layout, one further down
			end
			made = true
		end
	end

	local placed, auraAt = false, nil
	if index then
		placed, auraAt = self:PlaceTargetAuras(info.layouts[index])
	end
	local barsPlaced = index and self:PlaceActionBars(info.layouts[index])
	placed = placed or barsPlaced

	local o = self.db.consoleOpts
	local moved, spots, lasts, anyMoved = {}, {}, {}, false
	for _, p in ipairs(PLACEMENTS) do
		moved[p.key], spots[p.key], lasts[p.key] = 0, p.spot(self), p.saved and o[p.saved] or nil
	end
	-- Frames we placed follow only after a shared setting changed (none
	-- saved yet, from an older version: they stay as they are).
	local spotKey, spotKeyLast = self:EditSpotKey(), self.db.consoleOpts.spotKey
	local follow = spotKeyLast and spotKeyLast ~= spotKey
	-- Frames still in their default place are moved once per layout. Should
	-- the game hand the layout back unchanged (it does for some players),
	-- they are left there instead of being moved, saved and offered a reload
	-- at every login: saving layouts from addon code taints Blizzard's frames
	-- for the session (see AskReload).
	local placedOnce, newlyPlaced = self.db.consoleOpts.editPlaced, {}
	for _, layout in ipairs(info.layouts) do
		local key = layoutKey(layout)
		local fresh = not placedOnce[key]
		for _, p in ipairs(PLACEMENTS) do
			if p.place(self, layout, spots[p.key], follow and lasts[p.key] or nil, fresh) then
				moved[p.key], anyMoved = moved[p.key] + 1, true
			end
		end
		if fresh then
			newlyPlaced[#newlyPlaced + 1] = key
		end
	end
	if (made or placed or renamed > 0 or anyMoved) and not pcall(C_EditMode.SaveLayouts, info) then
		return
	end
	for _, key in ipairs(newlyPlaced) do
		placedOnce[key] = true
	end
	-- Where we put them last: kept while nothing moved, so another
	-- character's (or login's) spot doesn't make them look moved by the
	-- player.
	for _, p in ipairs(PLACEMENTS) do
		local spot = spots[p.key]
		if p.saved and spot and (moved[p.key] > 0 or not lasts[p.key]) then
			o[p.saved] = { x = spot.x, y = spot.y }
		end
	end
	self.db.consoleOpts.spotKey = spotKey
	if barsPlaced then
		self.db.consoleOpts.barsPlaced = true
	end
	if auraAt then
		local places = type(self.db.consoleOpts.targetAuraLast) == "table" and self.db.consoleOpts.targetAuraLast or {}
		local newest = places[1]
		if not (newest and newest.x == auraAt.x and newest.y == auraAt.y) then
			table.insert(places, 1, auraAt)
			places[5] = nil
		end
		self.db.consoleOpts.targetAuraLast = places
	end
	if made then
		for name, value in pairs(RAID_CVARS) do
			setCVar(name, value)
		end
	end

	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	local switched = self.db.consoleOpts.editLayout
	if index and not switched[key] and C_EditMode.SetActiveLayout
		and pcall(C_EditMode.SetActiveLayout, presets + index) then
		switched[key] = true
		self:AskReload(("switched to the %q Edit Mode layout (cast bar above the console, raid-style party"
			.. " frames). Pick another layout in Edit Mode any time."):format(ns.EDIT_LAYOUT))
	elseif anyMoved then
		for _, p in ipairs(PLACEMENTS) do
			if moved[p.key] > 0 then
				self:AskReload(p.message(moved[p.key], moved))
				break
			end
		end
	elseif barsPlaced then
		self:AskReload(("placed action bars 1-3 over the console in the %q Edit Mode layout; move or resize"
			.. " them there as you like."):format(ns.EDIT_LAYOUT))
	elseif made or placed then
		self:AskReload(why or "updated the target frame's place and size in the Edit Mode layout.")
	elseif renamed > 0 then
		self:AskReload(("renamed %d extra %q Edit Mode layout(s) (delete them in Edit Mode if you don't use them).")
			:format(renamed, ns.EDIT_LAYOUT))
	end
end
