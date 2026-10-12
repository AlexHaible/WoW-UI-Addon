-- Action bars, placed in the original addon's action slot grid: the main bar on the
-- bottom row, bars 2 and 3 above it. The original addon's nine extra slots (three beside
-- the minimap, six in the inventory) are Blizzard's Action Bar 6
-- (MultiBar5): enable it in Edit Mode, and its key bindings are the original addon's
-- "custom action button" bindings.
--
-- These are Blizzard's own action buttons, moved and reskinned: they keep
-- their bindings, paging, cooldowns and spell overlays, and none of
-- Blizzard's action button code ever runs from ours. Bars 2, 3 and 6 must be
-- turned on in Edit Mode (or Options > Gameplay > Action Bars) to show.

local _, ns = ...
local ActionBars = ns:RegisterModule("actionbars", {})

local HEARTHSTONE = 6948

-- Console bar and the Blizzard button names that fill it.
local BARS = {
	{ key = "main", prefix = "ActionButton" },
	{ key = "bar2", prefix = "MultiBarBottomLeftButton" },
	{ key = "bar3", prefix = "MultiBarBottomRightButton" },
}
local EXTRA_PREFIX = "MultiBar5Button"

local BAR_FRAMES = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBar5",
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

-- The original addon's look: the grid art is the button frame, so drop Blizzard's own
-- border and slot art and let the icon fill the cell.
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
	for _, key in ipairs({ "SlotBackground", "SlotArt", "RightDivider", "BottomDivider" }) do
		local region = btn[key]
		if region and region.SetAlpha and region ~= icon then
			region:SetAlpha(0)
		end
	end
	local floating = _G[name .. "FloatingBG"]
	if floating then
		floating:SetAlpha(0)
	end
end

-- The original addon zooms each icon a little, relative to the button size.
local function zoomIcon(btn, s, size)
	local icon = btn.icon or _G[btn:GetName() .. "Icon"]
	if icon then
		local z = math.min(0.2, 0.01851 * s / size)
		icon:SetTexCoord(z, 1 - z, z, 1 - z)
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
	for _, spec in ipairs(BARS) do
		self.buttons[spec.key] = collect(spec.prefix, 12)
	end
	self.extra = collect(EXTRA_PREFIX, 9)

	-- The bars' own frames stay where Edit Mode put them (now empty, at the
	-- bottom of the screen); stop them catching clicks meant for the console.
	ns:RunOutOfCombat("actionbar-frames", function()
		for _, name in ipairs(BAR_FRAMES) do
			local bar = _G[name]
			if bar and not ns.IsForbidden(bar) and bar.EnableMouse then
				bar:EnableMouse(false)
			end
		end
	end)

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
		C_Timer.After(2, function() self:PlaceHearthstone() end)
	end)
end

-- The original addon puts a hearthstone in the first slot beside the minimap, once per
-- character, when that slot is empty.
function ActionBars:PlaceHearthstone()
	local btn = self.extra[1]
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	local done = ns.db.consoleOpts.hearthstone
	if done[key] or not btn or InCombatLockdown() or GetCursorInfo() then
		return
	end
	local ok = pcall(function()
		local slot = btn.action or btn:GetAttribute("action")
		if not slot or HasAction(slot) or (C_Item.GetItemCount(HEARTHSTONE) or 0) == 0 then
			return
		end
		C_Item.PickupItem(HEARTHSTONE)
		if GetCursorInfo() == "item" then
			PlaceAction(slot)
		end
		ClearCursor()
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

local function lockButton(btn, r, s)
	ns:Lock(btn, function(b)
		placeButton(b, r.x, r.y, r.w)
	end, { "SetScale" })
	zoomIcon(btn, s, r.w)
end

function ActionBars:OnLayout(L)
	for _, spec in ipairs(BARS) do
		local row = L.bars[spec.key]
		for i, btn in pairs(self.buttons[spec.key]) do
			lockButton(btn, { x = row.xs[i], y = row.y, w = row.size }, L.s)
		end
	end
	-- Action Bar 6: 1-3 beside the minimap, 4-9 in the inventory (parked
	-- below the screen when the inventory is turned off).
	for i, btn in pairs(self.extra) do
		local r
		if i <= 3 then
			r = L.minimapSlots[i]
		else
			r = L.inventory and L.inventory[i - 3]
		end
		lockButton(btn, r or { x = 0, y = -200, w = 30 }, L.s)
	end
end
