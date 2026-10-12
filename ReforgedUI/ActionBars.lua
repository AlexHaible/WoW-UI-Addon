-- Action bars. The main bar becomes the Warcraft III command card (4x3), bars
-- 2 and 3 sit on the info screen, bars 4 and 5 go to the wings (32:9) or the
-- right edge of the screen. Buttons are our own secure ActionBarButtonTemplate
-- buttons; Blizzard's bars are hidden and their key bindings redirected here.

local _, ns = ...
local ActionBars = ns:RegisterModule("actionbars", {})
local Layout = ns.Layout

-- key, Blizzard binding prefix, fixed action page (nil = follows paging)
local BARS = {
	{ key = "main", binding = "ACTIONBUTTON", page = nil },
	{ key = "bar2", binding = "MULTIACTIONBAR1BUTTON", page = 6, buttonType = "MULTIACTIONBAR1BUTTON" },
	{ key = "bar3", binding = "MULTIACTIONBAR2BUTTON", page = 5, buttonType = "MULTIACTIONBAR2BUTTON" },
	{ key = "bar4", binding = "MULTIACTIONBAR3BUTTON", page = 3, buttonType = "MULTIACTIONBAR3BUTTON" },
	{ key = "bar5", binding = "MULTIACTIONBAR4BUTTON", page = 4, buttonType = "MULTIACTIONBAR4BUTTON" },
}

local BLIZZARD_BARS = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
	"MultiBarRight", "MultiBarLeft", "MainMenuBarArtFrame",
}

local BASE_SIZE = 45 -- ActionBarButtonTemplate's native size; we scale from it

local function SkinButton(btn)
	local name = btn:GetName()
	local icon = btn.icon or _G[name .. "Icon"]
	if icon then
		if btn.IconMask and icon.RemoveMaskTexture then
			icon:RemoveMaskTexture(btn.IconMask)
		end
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:ClearAllPoints()
		icon:SetAllPoints()
	end
	local normal = btn.NormalTexture or btn:GetNormalTexture()
	if normal then
		normal:SetAlpha(0)
	end
	for _, key in ipairs({ "SlotBackground", "SlotArt", "RightDivider", "BottomDivider" }) do
		if btn[key] then
			btn[key]:SetAlpha(0)
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
	btn.ReforgedBevel = bevel
end

local function UpdateButton(btn)
	if btn.UpdateAction then
		btn:UpdateAction(true)
	elseif ActionButton_UpdateAction then
		ActionButton_UpdateAction(btn)
	end
end

function ActionBars:CreateBar(spec)
	local header = CreateFrame("Frame", "ReforgedUIBar_" .. spec.key, ns.root, "SecureHandlerBaseTemplate")
	header:SetFrameStrata("MEDIUM")
	header:SetAllPoints(ns.root)
	header.buttons = {}
	for i = 1, 12 do
		local name = ("ReforgedUI%sButton%d"):format(spec.key, i)
		local btn = CreateFrame("CheckButton", name, header, "ActionBarButtonTemplate")
		btn:SetID(i)
		btn.buttonType = spec.buttonType
		if spec.page then
			btn:SetAttribute("actionpage", spec.page)
		end
		btn:SetAttribute("showgrid", 1)
		btn:RegisterForClicks("AnyUp", "AnyDown")
		SkinButton(btn)
		UpdateButton(btn)
		btn:Show()
		header.buttons[i] = btn
	end
	return header
end

function ActionBars:OnEnable()
	for _, name in ipairs(BLIZZARD_BARS) do
		ns:Kill(_G[name])
	end

	self.bars = {}
	for _, spec in ipairs(BARS) do
		self.bars[spec.key] = self:CreateBar(spec)
	end

	-- The main bar follows Blizzard's paging (stances, forms, stealth, skyriding);
	-- refresh its icons whenever the page changes.
	local main = self.bars.main
	for _, event in ipairs({
		"ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
		"UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_POSSESS_BAR",
		"PLAYER_ENTERING_WORLD",
	}) do
		ns:On(event, function()
			for _, btn in ipairs(main.buttons) do
				UpdateButton(btn)
			end
		end)
	end

	self.bindingOwner = CreateFrame("Frame", "ReforgedUIBindings", UIParent)
	ns:On("UPDATE_BINDINGS", function() self:UpdateBindings() end)
	ns:On("PLAYER_ENTERING_WORLD", function() self:UpdateBindings() end)
	self:UpdateBindings()
end

-- Point the keys bound to Blizzard's action buttons at our buttons instead.
function ActionBars:UpdateBindings()
	ns:RunOutOfCombat("bindings", function()
		local owner = self.bindingOwner
		ClearOverrideBindings(owner)
		for _, spec in ipairs(BARS) do
			local header = self.bars[spec.key]
			for i, btn in ipairs(header.buttons) do
				for _, key in ipairs({ GetBindingKey(spec.binding .. i) }) do
					SetOverrideBindingClick(owner, false, key, btn:GetName(), "LeftButton")
				end
			end
		end
	end)
end

function ActionBars:OnLayout(L)
	for _, spec in ipairs(BARS) do
		local header = self.bars[spec.key]
		local grid = L.bars[spec.key]
		local scale = grid.size / BASE_SIZE
		for i, btn in ipairs(header.buttons) do
			local x, y = Layout.GridCell(grid, i)
			btn:SetScale(scale)
			btn:ClearAllPoints()
			btn:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", x / scale, y / scale)
			btn:SetSize(BASE_SIZE, BASE_SIZE)
		end
	end
end
