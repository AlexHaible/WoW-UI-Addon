-- Action bars, placed in the original addon's action slot grid: the main bar on the
-- bottom row, bars 2 and 3 above it. The original addon's three extra slots beside the
-- minimap are our own bar (MinimapBar.lua), not one of Blizzard's. (The 2x3
-- inventory holds the bags, see Inventory.lua.) The stance (aura, form) buttons stand in a row on the
-- wall over the grid; the row can be dragged elsewhere while Edit Mode is
-- open (consoleOpts.stanceSpot, /rui stance reset), or left to another bar
-- addon altogether (consoleOpts.leaveStance, or Dominos loaded). The pet bar keeps its buttons where Edit Mode has one:
-- it is placed just above the stance row once (on it, for classes without
-- stances), then moved in Edit Mode (see ns:PetBarSpot); on clients without,
-- its buttons get that row (ns:PetRow).
--
-- These are Blizzard's own buttons, moved (and the action buttons
-- reskinned): they keep their bindings, paging, cooldowns and spell
-- overlays, and none of Blizzard's button code ever runs from ours. Their bar
-- frames are Edit Mode frames and stay where Edit Mode puts them, empty and
-- click-through. Bars 2 and 3 must be turned on in Edit Mode (or Options
-- > Gameplay > Action Bars) to show.

local _, ns = ...
local ActionBars = ns:RegisterModule("actionbars", {})

-- Console bar and the Blizzard button names that fill it.
local BARS = {
	{ key = "main", prefix = "ActionButton" },
	{ key = "bar2", prefix = "MultiBarBottomLeftButton" },
	{ key = "bar3", prefix = "MultiBarBottomRightButton" },
}

-- Stance and pet buttons: current names first, Classic-era ones after.
local ROWS = {
	{ key = "stance", prefixes = { "StanceButton", "ShapeshiftButton" }, count = 10 },
	{ key = "pet", prefixes = { "PetActionButton" }, count = 10 },
}

-- Bar addons that put Blizzard's own stance buttons on their bars: holding
-- the buttons on the wall would fight theirs.
local STANCE_ADDONS = { "Dominos" }

local BAR_FRAMES = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
	"StanceBar", "StanceBarFrame", "ShapeshiftBarFrame", "PetActionBar", "PetActionBarFrame",
}

-- Decorations of the main bar (end caps, border, page number and arrows).
local MAIN_ART = {
	"EndCaps", "BorderArt", "ActionBarPageNumber", "Background",
}
local MAIN_ART_GLOBALS = {
	"MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarPageNumber", "ActionBarUpButton",
	"ActionBarDownButton", "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2",
	"MainMenuBarTexture3", "MainMenuXPBarTexture0", "MainMenuBarArtFrameBackground",
}

local skinned = setmetatable({}, { __mode = "k" })

-- The grid art is the button frame: drop Blizzard's border and slot art,
-- let the icon fill the cell, and lay Warcraft III's steel button frame over
-- it so the icon looks like a recessed command button, not a flat square.
local function SkinButton(btn)
	if skinned[btn] then
		return
	end
	skinned[btn] = true
	local name = btn:GetName()
	local icon = btn.icon or _G[name .. "Icon"]
	if icon and btn.IconMask and icon.RemoveMaskTexture then
		icon:RemoveMaskTexture(btn.IconMask)
	end
	local normal = btn:GetNormalTexture()
	if normal then
		normal:SetAlpha(0)
	end
	ns:IconFrame(btn)
	for _, key in ipairs({ "SlotBackground", "SlotArt" }) do
		local region = btn[key]
		if region and region.SetAlpha and region ~= icon then
			region:SetAlpha(0)
		end
	end
	-- The gold pillars between buttons: kept invisible whatever Blizzard's
	-- divider code sets later.
	for _, key in ipairs({ "RightDivider", "BottomDivider", "Divider" }) do
		local region = btn[key]
		if region and region.SetAlpha and region ~= icon then
			ns:Conceal(region)
		end
	end
	local floating = _G[name .. "FloatingBG"]
	if floating then
		floating:SetAlpha(0)
	end
end

-- Trim only the dark border baked into the icon art, so the whole picture
-- shows. (The original addon zoomed in by up to a fifth on each side,
-- which crops most icons.)
local ICON_CROP = 0.07
local function trimIcon(btn)
	local icon = btn.icon or _G[btn:GetName() .. "Icon"]
	if icon then
		icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	end
end

local function isAncestorOf(frame, child)
	local p = child and child:GetParent()
	while p do
		if p == frame then
			return true
		end
		p = p:GetParent()
	end
	return false
end

-- Hides a decoration unless it holds the buttons themselves (on some clients
-- the main bar's art frame is the buttons' parent).
local function hideArt(obj, firstButton)
	if not obj or ns.IsForbidden(obj) then
		return
	end
	if obj.GetChildren then
		if not isAncestorOf(obj, firstButton) then
			ns:Conceal(obj)
		end
	elseif obj.SetAlpha then
		obj:SetAlpha(0)
	end
end

-- Newer clients draw the dividers between a bar's buttons from texture pools
-- on the bar (re-acquired by its UpdateDividers): make every one invisible,
-- now and after each update.
local DIVIDER_POOLS = { "HorizontalDividersPool", "VerticalDividersPool", "DividersPool", "DividerPool" }

local function concealDividers(bar)
	for _, key in ipairs(DIVIDER_POOLS) do
		local pool = bar[key]
		if type(pool) == "table" and pool.EnumerateActive then
			for divider in pool:EnumerateActive() do
				ns:Conceal(divider)
			end
		end
	end
	if type(bar.dividers) == "table" then
		for _, divider in pairs(bar.dividers) do
			if type(divider) == "table" then
				ns:Conceal(divider)
			end
		end
	end
	for _, region in ipairs({ bar:GetRegions() }) do
		local ok, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
		if ok and type(atlas) == "string" and atlas:lower():find("divider") then
			ns:Conceal(region)
		end
	end
end

local function hideDividers(bar)
	if not bar or ns.IsForbidden(bar) then
		return
	end
	concealDividers(bar)
	if type(bar.UpdateDividers) == "function" then
		hooksecurefunc(bar, "UpdateDividers", concealDividers)
	end
end

local function collect(prefix, count)
	local list = {}
	for i = 1, count do
		local btn = _G[prefix .. i]
		if btn and not ns.IsForbidden(btn) then
			list[i] = btn
			SkinButton(btn)
		end
	end
	return list
end

function ActionBars:OnEnable()
	self.buttons = {}
	-- "Let Edit Mode place the action bars": bars 1-3 keep their buttons and
	-- Blizzard's look, and Edit Mode places them (see ns:PlaceActionBars).
	local own = ns.db.consoleOpts.editModeBars
	for _, spec in ipairs(BARS) do
		self.buttons[spec.key] = own and {} or collect(spec.prefix, 12)
	end
	-- Stance and pet buttons keep Blizzard's own look: they sit on the
	-- wall, not in the grid art.
	self.rows = {}
	local petInEditMode = ns:PetBarInEditMode()
	local leaveStance = self:LeavesStance()
	for _, spec in ipairs(ROWS) do
		local list = {}
		local skip = spec.key == "pet" and petInEditMode or spec.key == "stance" and leaveStance
		for _, prefix in ipairs(skip and {} or spec.prefixes) do
			if _G[prefix .. "1"] then
				for i = 1, spec.count do
					local btn = _G[prefix .. i]
					if btn and not ns.IsForbidden(btn) then
						list[i] = btn
					end
				end
				break
			end
		end
		self.rows[spec.key] = list
	end

	-- The bars' own frames stay where Edit Mode put them (now empty, at the
	-- bottom of the screen, except an Edit Mode pet bar, which keeps its
	-- buttons); stop them catching clicks meant for the console.
	-- Stance bar frames left to another addon keep their buttons and clicks.
	local stanceFrames = { StanceBar = true, StanceBarFrame = true, ShapeshiftBarFrame = true }
	ns:RunOutOfCombat("actionbar-frames", function()
		for _, name in ipairs(own and { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame",
			"PetActionBar", "PetActionBarFrame" } or BAR_FRAMES) do
			local bar = _G[name]
			if bar and not ns.IsForbidden(bar) and bar.EnableMouse
				and not (leaveStance and stanceFrames[name]) then
				bar:EnableMouse(false)
			end
		end
	end)

	if not own then
		for _, name in ipairs({ "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight" }) do
			hideDividers(_G[name])
		end
	end

	local first = self.buttons.main[1]
	local bar = _G.MainActionBar or _G.MainMenuBar
	if bar then
		for _, key in ipairs(MAIN_ART) do
			hideArt(bar[key], first)
		end
	end
	for _, name in ipairs(MAIN_ART_GLOBALS) do
		hideArt(_G[name], first)
	end

	ns:On("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(2, function()
			self:EnableBars()
		end)
	end)

	if next(self.rows.stance) then
		self.stanceHolder = self:MakeStanceHolder()
		local editMode = _G.EditModeManagerFrame
		if editMode and editMode.HookScript then
			editMode:HookScript("OnShow", function() self:SetEditing(true) end)
			editMode:HookScript("OnHide", function() self:SetEditing(false) end)
		end
		ns:On("UPDATE_SHAPESHIFT_FORMS", function()
			if self.editing then
				self:PlaceStanceHolder()
			end
		end)
	end
end

-- True when the stance buttons are left where Blizzard or another bar addon
-- puts them: the player asked for it, or such an addon is loaded.
function ActionBars:LeavesStance()
	if ns.db.consoleOpts.leaveStance then
		return true
	end
	local addons = _G.C_AddOns
	local loaded = (addons and addons.IsAddOnLoaded) or _G.IsAddOnLoaded
	if loaded then
		for _, name in ipairs(STANCE_ADDONS) do
			if loaded(name) then
				return true
			end
		end
	end
	return false
end

-- Bars 2 and 3 fill the console, so turn them on once per character
-- (after that the player's own choice in Options stands).
local SHOW_SETTINGS = { "PROXY_SHOW_ACTIONBAR_2", "PROXY_SHOW_ACTIONBAR_3" }
-- GetActionBarToggles order: bottom left (2), bottom right (3), right (4),
-- left (5), then bars 6, 7 and 8.
local TOGGLES = { 1, 2 }

function ActionBars:EnableBars()
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	local done = ns.db.consoleOpts.barsEnabled
	if done[key] or InCombatLockdown() then
		return
	end
	local ok = pcall(function()
		local getSetting = Settings and Settings.GetSetting
		if getSetting and getSetting(SHOW_SETTINGS[1]) then
			for _, name in ipairs(SHOW_SETTINGS) do
				local setting = getSetting(name)
				if setting and not setting:GetValue() then
					setting:SetValue(true)
				end
			end
		elseif GetActionBarToggles and SetActionBarToggles then
			local toggles = { GetActionBarToggles() }
			for _, i in ipairs(TOGGLES) do
				if i <= #toggles then
					toggles[i] = true
				end
			end
			SetActionBarToggles(unpack(toggles))
		end
	end)
	if ok then
		done[key] = true
	end
end

-- Size `btn` to `size` console units and put its bottom-left at (x, y).
local function placeButton(btn, x, y, size)
	local w = btn:GetWidth()
	if not w or w <= 0 then
		w = 45
	end
	local parentScale = btn:GetParent() and btn:GetParent():GetEffectiveScale() or 1
	btn:SetScale(size * ns.root:GetEffectiveScale() / (w * parentScale))
	ns:Anchor(btn, "BOTTOMLEFT", x, y)
end

local function lockButton(btn, r)
	ns:Lock(btn, function(b)
		placeButton(b, r.x, r.y, r.w)
	end, { "SetScale" })
	trimIcon(btn)
end

function ActionBars:OnLayout(L)
	for _, spec in ipairs(BARS) do
		local row = L.bars[spec.key]
		for i, btn in pairs(self.buttons[spec.key]) do
			lockButton(btn, { x = row.xs[i], y = row.y, w = row.size })
		end
	end
	-- Stance (and, without Edit Mode, pet) buttons in rows over the grid;
	-- the stance row wherever the player dragged it.
	self.layout = L
	for key, list in pairs(self.rows) do
		local row = key == "pet" and ns:PetRow(L) or L[key]
		for i, btn in pairs(list) do
			ns:Lock(btn, function(b)
				local r = key == "stance" and self:StanceSpot() or row
				placeButton(b, r.x + (i - 1) * r.step, r.y, r.size)
			end, { "SetScale" })
		end
	end
	if self.stanceHolder then
		self:PlaceStanceHolder()
	end
	if ns.db.consoleOpts.hideStance then
		self:ApplyStanceShown()
	end
end

----------------------------------------------------------------------------
-- Moving the stance row
--
-- The stance buttons are Blizzard's (protected, and a drag on one picks up
-- its spell), so the row moves by an outline of our own that shows while
-- Edit Mode is open: drag it out of combat and the buttons follow. Its spot
-- is kept per account (consoleOpts.stanceSpot, console units from the
-- console's bottom-left); /rui stance reset puts it back on the wall.

-- The row's first button: where the player put it, else on the wall.
function ActionBars:StanceSpot()
	local row = self.layout.stance
	local spot = ns.db.consoleOpts.stanceSpot
	if type(spot) == "table" and type(spot[1]) == "number" and type(spot[2]) == "number" then
		return { x = spot[1], y = spot[2], size = row.size, step = row.step }
	end
	return row
end

-- How many stance buttons the character has (at least one, so the outline
-- can still be found).
local function stanceCount(list)
	local forms = _G.GetNumShapeshiftForms
	local n = forms and forms() or 0
	if type(n) ~= "number" or n < 1 then
		n = 0
		for _ in pairs(list) do
			n = n + 1
		end
	end
	return math.max(1, math.min(n, 10))
end

function ActionBars:MakeStanceHolder()
	local h = CreateFrame("Frame", "ReforgedUIStance", ns.root)
	h:SetFrameStrata("HIGH")
	h:SetMovable(true)
	h:SetClampedToScreen(true)
	h:EnableMouse(false)
	h.fill = h:CreateTexture(nil, "BACKGROUND")
	h.fill:SetAllPoints()
	h.fill:SetColorTexture(0.1, 0.5, 1, 0.35)
	h.label = h:CreateFontString(nil, "OVERLAY")
	if not ns:SetFont(h.label, 10, "OUTLINE") then
		h.label:SetFontObject("GameFontHighlightSmall")
	end
	h.label:SetPoint("CENTER")
	h.label:SetText("Stance bar")
	h:RegisterForDrag("LeftButton")
	h:SetScript("OnDragStart", function() self:StartStanceDrag() end)
	h:SetScript("OnDragStop", function() self:StopStanceDrag() end)
	h:Hide()
	return h
end

function ActionBars:PlaceStanceHolder()
	local h = self.stanceHolder
	if not (h and self.layout) or self.moving then
		return
	end
	local r = self:StanceSpot()
	local n = stanceCount(self.rows.stance)
	ns.modules.console.Place(h, { x = r.x, y = r.y, w = n * r.step - (r.step - r.size), h = r.size })
end

-- Edit Mode open: the outline shows over the row and can be dragged
-- (not while the row is hidden).
function ActionBars:SetEditing(on)
	self.editing = on
	local h = self.stanceHolder
	local show = on and not ns.db.consoleOpts.hideStance
	if show then
		self:PlaceStanceHolder()
	else
		self:StopStanceDrag()
	end
	h:SetShown(show and true or false)
	h:EnableMouse(show and true or false)
end

----------------------------------------------------------------------------
-- Hiding the stance row (consoleOpts.hideStance, /rui stance hide|show)
--
-- For players who never click them (a warrior on key bindings). The
-- buttons are Blizzard's protected ones, so they aren't hidden (Blizzard's
-- stance bar shows them again whenever forms change): they turn invisible
-- and click-through, and their key bindings keep working.

local stanceAlphaHooked = setmetatable({}, { __mode = "k" })

function ActionBars:ApplyStanceShown()
	local hide = ns.db.consoleOpts.hideStance and true or false
	for _, btn in pairs(self.rows and self.rows.stance or {}) do
		if hide and not stanceAlphaHooked[btn] then
			stanceAlphaHooked[btn] = true
			local busy
			hooksecurefunc(btn, "SetAlpha", function(b)
				if ns.db.consoleOpts.hideStance and not busy then
					busy = true
					b:SetAlpha(0)
					busy = false
				end
			end)
		end
		btn:SetAlpha(hide and 0 or 1)
	end
	ns:RunOutOfCombat("stance-mouse", function()
		for _, btn in pairs(self.rows and self.rows.stance or {}) do
			btn:EnableMouse(not hide)
		end
	end)
	if self.stanceHolder then
		self:SetEditing(self.editing)
	end
end

function ActionBars:SetStanceShown(on)
	ns.db.consoleOpts.hideStance = not on
	self:ApplyStanceShown()
end

function ActionBars:StartStanceDrag()
	if self.editing and not InCombatLockdown() and self.layout then
		self.moving = true
		self.stanceHolder:StartMoving()
	end
end

function ActionBars:StopStanceDrag()
	if not self.moving then
		return
	end
	self.moving = false
	local h, root = self.stanceHolder, ns.root
	h:StopMovingOrSizing()
	if h.SetUserPlaced then
		h:SetUserPlaced(false) -- ours to save, not the client's layout cache
	end
	local x, y = h:GetLeft(), h:GetBottom()
	local rx, ry = root:GetLeft(), root:GetBottom()
	if x and y and rx and ry then
		ns.db.consoleOpts.stanceSpot = { x - rx, y - ry }
	end
	self:PlaceStance()
end

-- The buttons to the row's (new) spot: their locks place them, after
-- combat if need be.
function ActionBars:PlaceStance()
	for _, btn in pairs(self.rows and self.rows.stance or {}) do
		ns:Relock(btn)
	end
	self:PlaceStanceHolder()
end

function ActionBars:ResetStanceSpot()
	ns.db.consoleOpts.stanceSpot = false
	if self.layout then
		self:PlaceStance()
	end
end
