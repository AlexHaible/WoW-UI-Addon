-- The Warcraft III top bar: menu buttons on the left, resources on the right
-- and the day/night clock hanging from the middle, turning with the game's
-- server time (sun at the bottom of the window at noon, moon at midnight).

local _, ns = ...
local TopBar = ns:RegisterModule("topbar", {})

-- Label, Blizzard micro button to click (secure), and a fallback function for
-- clients without that button.
local BUTTONS = {
	{ label = QUESTLOG_BUTTON or "Quests", micro = { "QuestLogMicroButton" }, fallback = "ToggleQuestLog" },
	{ label = MAINMENU_BUTTON or "Menu", micro = { "MainMenuMicroButton" } },
	{ label = SOCIAL_BUTTON or "Allies", micro = { "SocialsMicroButton", "FriendsMicroButton", "GuildMicroButton" },
		fallback = "ToggleFriendsFrame" },
	{ label = WORLD_MAP or "Map", micro = { "WorldMapMicroButton" }, fallback = "ToggleWorldMap" },
}

local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local BAG_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"

local Container = C_Container or {}
local numFreeSlots = Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local numSlots = Container.GetContainerNumSlots or GetContainerNumSlots

local function place(region, r)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.x, r.y)
	region:SetSize(r.w, r.h)
end

local function firstGlobal(names)
	for _, name in ipairs(names) do
		if _G[name] then
			return _G[name]
		end
	end
end

-- Buttons and resources sit in the dark windows of the bar texture.
local function CreatePlate(parent, level)
	local plate = CreateFrame("Frame", nil, parent)
	plate:SetFrameLevel(level)
	plate.text = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	plate.text:SetPoint("CENTER")
	return plate
end

function TopBar:OnEnable()
	local root = ns.root
	-- The bar itself: two runs of the faction's topbar slot texture.
	self.bar = CreateFrame("Frame", nil, root)
	self.bar:SetFrameLevel(40)
	self.bar:EnableMouse(true)
	self.barLeft = self.bar:CreateTexture(nil, "BACKGROUND")
	self.barRight = self.bar:CreateTexture(nil, "BACKGROUND")
	self.holder = CreateFrame("Frame", "ReforgedUITopBar", root)
	self.holder:SetFrameStrata("LOW")
	self.holder:SetAllPoints(root)

	-- Day/night clock: the dial turns underneath its frame; the top bar panel
	-- covers the upper half, so only the lower half shows through the window.
	self.dialFrame = CreateFrame("Frame", nil, root)
	self.dialFrame:SetFrameLevel(39)
	self.dial = self.dialFrame:CreateTexture(nil, "ARTWORK")
	self.dial:SetTexture(ns.MEDIA .. "Common\\dial")
	self.clockFrame = CreateFrame("Frame", "ReforgedUIClock", root)
	self.clockFrame:SetFrameLevel(45)
	self.clockFrame:EnableMouse(true)
	self.clockArt = self.clockFrame:CreateTexture(nil, "ARTWORK")
	self.clockArt:SetAllPoints()
	self.clockFrame:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
		local h, m = GetGameTime()
		GameTooltip:SetText(TIMEMANAGER_TOOLTIP_TITLE or "Time", 1, 1, 1)
		GameTooltip:AddLine(("%02d:%02d"):format(h, m), 1, 0.82, 0)
		GameTooltip:Show()
	end)
	self.clockFrame:SetScript("OnLeave", GameTooltip_Hide)
	local elapsed = 10
	self.clockFrame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 5 then
			elapsed = 0
			self:UpdateClock()
		end
	end)

	self.buttons = {}
	for i, spec in ipairs(BUTTONS) do
		local target = firstGlobal(spec.micro)
		local fallback = spec.fallback and _G[spec.fallback]
		if target or fallback then
			local plate = CreatePlate(self.holder, 50)
			plate.text:SetText(spec.label)
			local btn
			if target then
				btn = CreateFrame("Button", "ReforgedUITopButton" .. i, plate, "SecureActionButtonTemplate")
				btn:SetAttribute("type", "click")
				btn:SetAttribute("clickbutton", target)
				btn:RegisterForClicks("AnyUp", "AnyDown")
			else
				btn = CreateFrame("Button", "ReforgedUITopButton" .. i, plate)
				btn:SetScript("OnClick", function() fallback() end)
			end
			btn:SetAllPoints()
			btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			plate.button = btn
			self.buttons[#self.buttons + 1] = plate
		end
	end

	self.resources = {}
	for i, icon in ipairs({ GOLD_ICON, BAG_ICON, REPAIR_ICON }) do
		local plate = CreatePlate(self.holder, 50)
		plate.icon = plate:CreateTexture(nil, "OVERLAY")
		plate.icon:SetSize(12, 12)
		plate.icon:SetPoint("LEFT", 6, 0)
		plate.icon:SetTexture(icon)
		plate.text:ClearAllPoints()
		plate.text:SetPoint("LEFT", plate.icon, "RIGHT", 6, 0)
		plate.text:SetPoint("RIGHT", -6, 0)
		plate.text:SetJustifyH("RIGHT")
		self.resources[i] = plate
	end
	for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
		"UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }) do
		ns:On(e, function() self:UpdateResources() end)
	end

end

-- Unit frames, buffs and top-centre widgets move down to clear the bar.
function TopBar:ClearTopFrames()
	local function topLimit() return ns.layout.topLimit end
	local function centerLimit() return ns.layout.centerLimit end
	for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "BuffFrame",
		"DebuffFrame", "TemporaryEnchantFrame" }) do
		if _G[name] then
			ns:KeepBelow(_G[name], topLimit)
		end
	end
	for _, name in ipairs({ "UIWidgetTopCenterContainerFrame", "UIErrorsFrame" }) do
		if _G[name] then
			ns:KeepBelow(_G[name], centerLimit)
		end
	end
end

function TopBar:UpdateClock()
	local h, m = GetGameTime()
	local hours = (h or 12) + (m or 0) / 60
	-- Noon puts the sun at the bottom of the window; the dial turns
	-- anticlockwise so the sun rises on the left and sets on the right.
	self.dial:SetRotation((hours - 12) / 24 * 2 * math.pi)
end

local function durability()
	local lowest
	for slot = 1, 18 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then
			local pct = cur / max
			lowest = lowest and math.min(lowest, pct) or pct
		end
	end
	return lowest
end

function TopBar:UpdateResources()
	local gold, bags, repair = unpack(self.resources)
	local copper = GetMoney()
	gold.text:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(copper / 10000)) or math.floor(copper / 10000))

	local free, total = 0, 0
	if numSlots and numFreeSlots then
		for bag = 0, 4 do
			free = free + (numFreeSlots(bag) or 0)
			total = total + (numSlots(bag) or 0)
		end
	end
	bags.text:SetFormattedText("%d / %d", free, total)

	local pct = durability()
	if pct then
		repair.text:SetFormattedText("%d%%", pct * 100 + 0.5)
		if pct < 0.25 then
			repair.text:SetTextColor(1, 0.2, 0.2)
		elseif pct < 0.5 then
			repair.text:SetTextColor(1, 0.82, 0)
		else
			repair.text:SetTextColor(1, 1, 1)
		end
	else
		repair.text:SetText("-")
	end
end

function TopBar:OnLayout(L)
	self:PlaceBar(L)
	local c = L.clock
	self.dial:ClearAllPoints()
	self.dial:SetPoint("CENTER", ns.root, "BOTTOMLEFT", c.cx, c.cy)
	self.dial:SetSize(c.radius * 2, c.radius * 2)
	place(self.clockFrame, L.clockFrame)
	for i, plate in ipairs(self.buttons) do
		self:PlacePlate(plate, L.topButtons[i])
	end
	for i, plate in ipairs(self.resources) do
		self:PlacePlate(plate, L.resources[i])
	end
	self:UpdateClock()
	self:UpdateResources()
	self:ClearTopFrames() -- re-checks every frame against the new limits
end

-- Slots left of the clock line up with the core's left edge and slots right
-- of it with the core's right edge; the clock frame covers the seam.
function TopBar:PlaceBar(L)
	local r, slot, root = L.topBar, L.topSlot, ns.root
	local mid = L.clock.cx
	self.bar:ClearAllPoints()
	self.bar:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", r.x, r.y)
	self.bar:SetSize(r.w, r.h)
	self.barLeft:ClearAllPoints()
	self.barLeft:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", r.x, r.y)
	self.barLeft:SetSize(mid - r.x, r.h)
	self.barLeft:SetTexCoord((r.x - L.topSlotsLeft) / slot, (mid - L.topSlotsLeft) / slot, 0, 1)
	self.barRight:ClearAllPoints()
	self.barRight:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", mid, r.y)
	self.barRight:SetSize(r.x + r.w - mid, r.h)
	self.barRight:SetTexCoord((mid - L.topSlotsRight) / slot, (r.x + r.w - L.topSlotsRight) / slot, 0, 1)
end

function TopBar:PlacePlate(plate, r)
	if r then
		place(plate, r)
		plate:Show()
	else
		plate:Hide()
	end
end

function TopBar:OnTheme(theme)
	for _, t in ipairs({ self.barLeft, self.barRight }) do
		t:SetTexture(ns:Media("topbar", theme), "REPEAT", "CLAMP")
	end
	self.clockArt:SetTexture(ns:Media("clockframe", theme))
	for _, plate in ipairs(self.buttons) do
		plate.text:SetTextColor(unpack(theme.title))
	end
	if ns.layout then
		self:PlaceBar(ns.layout)
	end
end
