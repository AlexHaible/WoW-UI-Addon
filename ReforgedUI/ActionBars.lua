-- Action bars. Bars 1-3 fill the screen in the middle of the console, bars 4
-- and 5 go to free console space on wide screens or the right edge of the
-- screen. These are Blizzard's own action buttons, moved and reskinned: they
-- keep their bindings, paging, cooldowns and spell overlays, and none of
-- Blizzard's action button code ever runs from ours. Bars 2-5 must be turned
-- on in Options > Gameplay > Action Bars for their buttons to show.

local _, ns = ...
local ActionBars = ns:RegisterModule("actionbars", {})
local Layout = ns.Layout

-- Console bar and the Blizzard button names that fill it.
local BARS = {
	{ key = "main", prefix = "ActionButton" },
	{ key = "bar2", prefix = "MultiBarBottomLeftButton" },
	{ key = "bar3", prefix = "MultiBarBottomRightButton" },
	{ key = "bar4", prefix = "MultiBarRightButton" },
	{ key = "bar5", prefix = "MultiBarLeftButton" },
}

local BAR_FRAMES = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
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

-- Our bevels, kept here rather than written into Blizzard's button tables.
local bevels = setmetatable({}, { __mode = "k" })

local function SkinButton(btn)
	if bevels[btn] then
		return
	end
	local name = btn:GetName()
	local icon = btn.icon or _G[name .. "Icon"]
	if icon then
		if btn.IconMask and icon.RemoveMaskTexture then
			icon:RemoveMaskTexture(btn.IconMask)
		end
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	local normal = btn:GetNormalTexture()
	if normal then
		normal:SetAlpha(0)
	end
	for _, key in ipairs({ "SlotBackground", "SlotArt", "RightDivider", "BottomDivider" }) do
		local region = btn[key]
		if region and region.SetAlpha then
			region:SetAlpha(0)
		end
	end
	local floating = _G[name .. "FloatingBG"]
	if floating then
		floating:SetAlpha(0)
	end
	-- Warcraft III style bevel over the icon.
	local bevel = btn:CreateTexture(nil, "OVERLAY", nil, -1)
	bevel:SetAllPoints()
	bevel:SetTexture(ns.MEDIA .. "Common\\bevel")
	bevels[btn] = bevel
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

function ActionBars:OnEnable()
	self.buttons = {}
	for _, spec in ipairs(BARS) do
		local list = {}
		for i = 1, 12 do
			local btn = _G[spec.prefix .. i]
			if btn and not ns.IsForbidden(btn) then
				list[i] = btn
				SkinButton(btn)
			end
		end
		self.buttons[spec.key] = list
	end

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

function ActionBars:OnLayout(L)
	for _, spec in ipairs(BARS) do
		local grid = L.bars[spec.key]
		for i, btn in pairs(self.buttons[spec.key]) do
			local x, y = Layout.GridCell(grid, i)
			ns:Lock(btn, function(b)
				placeButton(b, x, y, grid.size)
			end, { "SetScale" })
		end
	end
end
