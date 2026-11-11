-- The game's tooltips in the theme's frame, like the damage meter's windows
-- (ReforgedUI_DamageMeter): the top bar's trim all round (Trim.lua) over a
-- dark inset in the theme's colour, in place of Blizzard's grey border.
-- A unit's health bar under the tooltip goes inside the frame too.
--
-- Only art changes: Blizzard's border (the tooltip's NineSlice) is made
-- invisible rather than hidden or replaced, so nothing Blizzard's code does
-- with it fails, and switching the option off (consoleOpts.themeTooltips,
-- the options' "Themed tooltips", /rui tooltips) brings it straight back.

local _, ns = ...
local Tooltip = ns:RegisterModule("tooltip", {})

-- The tooltips we dress, where the client has them.
local TIPS = {
	"GameTooltip", "ItemRefTooltip",
	"ShoppingTooltip1", "ShoppingTooltip2",
	"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
}

-- Blizzard's own clamp insets for tooltips (SharedTooltip_OnLoad).
local CLAMP_TOP = 25
-- The health bar sits this far under the tooltip's bottom; the frame takes
-- in this much more below it.
local BAR_PAD = 3

local skins = setmetatable({}, { __mode = "k" }) -- tooltip -> { trim, bg }

local function on()
	return ns.db.consoleOpts.themeTooltips ~= false
end

local function forbidden(frame)
	return not frame or (frame.IsForbidden and frame:IsForbidden())
end

local function healthBar(tip)
	local name = tip.GetName and tip:GetName()
	return tip.StatusBar or (name and _G[name .. "StatusBar"])
end

-- The box the frame goes around: the tooltip, and its health bar when shown.
local function PlaceBox(tip, s)
	local box = s.trim.box
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", tip, "TOPLEFT")
	local bar = healthBar(tip)
	if bar and bar:IsShown() then
		box:SetPoint("TOPRIGHT", tip, "TOPRIGHT")
		box:SetPoint("BOTTOM", bar, "BOTTOM", 0, -BAR_PAD)
	else
		box:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT")
	end
end

local function Paint(tip)
	local s = skins[tip]
	if not s then
		return
	end
	local show = on() and ns.theme ~= nil
	if tip.NineSlice then
		tip.NineSlice:SetAlpha(show and 0 or 1)
	end
	s.trim:SetShown(show)
	s.bg:SetShown(show)
	if tip.SetClampRectInsets then
		-- Keep the frame on screen, not only the tooltip inside it.
		local out = ReforgedUI.TRIM_OUT
		if show then
			tip:SetClampRectInsets(-out, out, math.max(CLAMP_TOP, out), -out)
		else
			tip:SetClampRectInsets(0, 0, CLAMP_TOP, 0)
		end
	end
	if not show then
		return
	end
	PlaceBox(tip, s)
	s.trim:Paint()
	local inset = ns.theme.inset
	s.bg:SetColorTexture(inset[1], inset[2], inset[3], inset[4] or 0.9)
end

local function Skin(tip)
	if forbidden(tip) or skins[tip] then
		return
	end
	-- The trim is drawn in the tooltip's own BORDER layer: over the inset,
	-- under its text, icons and child frames.
	local s = { trim = ReforgedUI.CreateTrim(tip) }
	s.bg = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
	s.bg:SetAllPoints(s.trim.box)
	skins[tip] = s
	local bar = healthBar(tip)
	if bar and bar.HookScript then
		local function place()
			if on() then
				PlaceBox(tip, s)
			end
		end
		bar:HookScript("OnShow", place)
		bar:HookScript("OnHide", place)
	end
	Paint(tip)
end

function Tooltip:Repaint()
	for tip in pairs(skins) do
		Paint(tip)
	end
end

function Tooltip:SetEnabled(enabled)
	ns.db.consoleOpts.themeTooltips = enabled and true or false
	self:Repaint()
end

function Tooltip:OnEnable()
	for _, name in ipairs(TIPS) do
		Skin(_G[name])
	end
	-- Blizzard shows the border again on every style change (an item's,
	-- a quest's): make it invisible again after it.
	if SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tip)
			if skins[tip] and tip.NineSlice and on() then
				tip.NineSlice:SetAlpha(0)
			end
		end)
	end
end

function Tooltip:OnTheme()
	self:Repaint()
end
