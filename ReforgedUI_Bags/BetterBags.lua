-- Reforged UI: Bags, the BetterBags theme. Adds "Reforged UI" to BetterBags'
-- theme list: its bag, bank and option windows in the current Reforged UI
-- theme, as Bags.lua dresses the game's own bags (trim all round, dark inset,
-- the theme's rail under the title, the bag icon in Warcraft III's steel
-- frame) and following it as the theme changes.
--
-- BetterBags is only an optional dependency: without it this file does
-- nothing at all.

local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
local BetterBags = AceAddon and AceAddon:GetAddon("BetterBags", true)
if not BetterBags then
	return
end
local themes = BetterBags:GetModule("Themes", true)
local searchBox = BetterBags:GetModule("SearchBox", true)
if not (themes and themes.RegisterTheme and searchBox) then
	return
end

local ICONFRAME = "Interface\\AddOns\\ReforgedUI\\Media\\Common\\iconframe"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local TITLE_H = 20 -- the title band; BetterBags' search box starts 30 down
local RAIL_H = 3
local ICON = 32
local OUT = ReforgedUI.TRIM_OUT

local theme

-- frame name -> decoration
local decorations = {}

local font = CreateFont("ReforgedUIBagsFont")
font:SetFont(ReforgedUI.FONT, 12, "")
font:SetTextColor(1, 0.82, 0, 1)

local function Paint(d)
	if not theme then
		return
	end
	local inset = theme.inset
	d.bg:SetColorTexture(inset[1], inset[2], inset[3], 1)
	d.rail:SetTexture(ReforgedUI.TrimArt("rail"))
	d.trim:Paint()
end

-- The parts every window has: the inset, the trim around it and the title
-- over the rail. The decoration is a frame of its own, just under the
-- window, so the theme only ever shows or hides it (BetterBags' rule).
local function Decorate(frame, withTitleBand)
	local name = frame:GetName()
	local d = decorations[name]
	if d then
		d:Show()
		Paint(d)
		return d, false
	end
	d = CreateFrame("Frame", name .. "ThemeReforgedUI", frame)
	d:SetAllPoints()
	d:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	d.bg = d:CreateTexture(nil, "BACKGROUND", nil, -8)
	d.bg:SetAllPoints()
	d.trim = ReforgedUI.CreateTrim(d)
	d.rail = d:CreateTexture(nil, "ARTWORK")
	d.rail:SetHeight(RAIL_H)
	d.rail:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -TITLE_H + 1)
	d.rail:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, -TITLE_H + 1)
	d.rail:SetShown(withTitleBand)

	-- Titles can change at any time; BetterBags keeps them in themes.titles.
	local holder = CreateFrame("Frame", nil, d)
	holder:SetAllPoints()
	holder:SetFrameLevel(1001)
	d.title = holder:CreateFontString(nil, "OVERLAY")
	d.title:SetFontObject(font)
	d.title:SetPoint("TOPLEFT", d, "TOPLEFT", 30, 0)
	d.title:SetPoint("TOPRIGHT", d, "TOPRIGHT", -30, 0)
	d.title:SetHeight(TITLE_H)
	d.title:SetText(themes.titles[name] or "")
	d.holder = holder

	decorations[name] = d
	Paint(d)
	return d, true
end

local function CloseButton(d, onClick)
	local close = CreateFrame("Button", nil, d.holder, "UIPanelCloseButtonNoScripts")
	close:SetPoint("TOPRIGHT", d, "TOPRIGHT", 3, 3)
	close:SetFrameLevel(1002)
	BetterBags.SetScript(close, "OnClick", onClick)
	return close
end

---@type Theme
local reforged = {
	Name = "Reforged UI",
	Description = "Your Reforged UI theme: the race's top bar trim around every window, following it as you switch.",
	Available = true,
	-- The bag and bank windows.
	Portrait = function(frame)
		local d, new = Decorate(frame, true)
		if not new then
			return
		end
		CloseButton(d, function(ctx)
			frame.Owner:Hide(ctx)
		end)
		local box = searchBox:CreateBox(frame.Owner.kind, d)
		box.frame:SetPoint("TOPLEFT", d, "TOPLEFT", 20, -30)
		box.frame:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", -10, -50)
		d.search = box
		-- BetterBags' menu button, as the bag's icon in the steel frame on
		-- the top-left corner.
		local button = themes.SetupBagButton(frame.Owner, d)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", d, "TOPLEFT", -OUT + 2, OUT - 2)
		button:SetSize(ICON, ICON)
		button.portrait:ClearAllPoints()
		button.portrait:SetAllPoints()
		button.portrait:SetTexture(BAG_ICON)
		button.portrait:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		button.portrait:SetDrawLayer("ARTWORK")
		button.highlightTex:ClearAllPoints()
		button.highlightTex:SetAllPoints()
		button.highlightTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		button.highlightTex:SetTexCoord(0, 1, 0, 1)
		button.highlightTex:SetBlendMode("ADD")
		local steel = button:CreateTexture(nil, "OVERLAY", nil, 7)
		steel:SetAllPoints()
		steel:SetTexture(ICONFRAME)
	end,
	-- The sidebar and option windows.
	Simple = function(frame)
		local d, new = Decorate(frame, true)
		if new then
			CloseButton(d, function()
				frame:Hide()
			end)
		end
	end,
	-- Small windows without a close button (the bag slots, dialogs).
	Flat = function(frame)
		local d = Decorate(frame, false)
		local title = themes.titles[frame:GetName()]
		d.title:SetShown(title ~= nil and title ~= "")
		d.rail:SetShown(title ~= nil and title ~= "")
	end,
	Opacity = function(frame, alpha)
		local d = decorations[frame:GetName()]
		if d then
			d.bg:SetAlpha(alpha / 100)
		end
	end,
	SectionFont = function(fontString)
		fontString:SetFontObject(font)
	end,
	SetTitle = function(frame, title)
		local d = decorations[frame:GetName()]
		if d then
			d.title:SetText(title)
		end
	end,
	Reset = function()
		for _, d in pairs(decorations) do
			d:Hide()
		end
	end,
	ToggleSearch = function(frame, shown)
		local d = decorations[frame:GetName()]
		if d and d.search then
			d.search:SetShown(shown)
		end
	end,
	-- Above the window, clear of the trim.
	PositionBagSlots = function(frame, bagSlotWindow)
		bagSlotWindow:ClearAllPoints()
		bagSlotWindow:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, OUT + 8)
	end,
	-- Left of the window, clear of the trim.
	OffsetSidebar = function()
		return -(OUT + 4)
	end,
}

themes:RegisterTheme("ReforgedUI", reforged)

ReforgedUI.RegisterThemeCallback(function(_, t)
	theme = t
	for _, d in pairs(decorations) do
		Paint(d)
	end
end)
