-- Action bars, placed in the original addon's action slot grid: the main bar on the
-- bottom row, bars 2 and 3 above it. The original addon's three extra slots beside the
-- minimap are our own bar (MinimapBar.lua), not one of Blizzard's. (The 2x3
-- inventory holds the bags, see Inventory.lua.) The stance (aura, form) buttons stand in a row on the
-- wall over the grid. The pet bar keeps its buttons where Edit Mode has one:
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
	for _, spec in ipairs(ROWS) do
		local list = {}
		for _, prefix in ipairs(spec.key == "pet" and petInEditMode and {} or spec.prefixes) do
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
	ns:RunOutOfCombat("actionbar-frames", function()
		for _, name in ipairs(own and { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame",
			"PetActionBar", "PetActionBarFrame" } or BAR_FRAMES) do
			local bar = _G[name]
			if bar and not ns.IsForbidden(bar) and bar.EnableMouse then
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
	-- Stance (and, without Edit Mode, pet) buttons in rows over the grid.
	for key, list in pairs(self.rows) do
		local row = key == "pet" and ns:PetRow(L) or L[key]
		for i, btn in pairs(list) do
			ns:Lock(btn, function(b)
				placeButton(b, row.x + (i - 1) * row.step, row.y, row.size)
			end, { "SetScale" })
		end
	end
end
