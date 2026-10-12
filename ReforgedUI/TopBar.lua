-- The Warcraft III top bar: menu buttons on the left, the day/night clock in
-- the middle turning with the game's server time (sun at the bottom of the
-- window at noon, moon at midnight), and slots for LibDataBroker feeds, like
-- Titan Panel, everywhere else. Gold, bag space and durability are feeds of
-- our own and fill the first three slots by default. Right-click an empty
-- slot, or Alt-right-click a filled one, to choose its feed.

local _, ns = ...
local TopBar = ns:RegisterModule("topbar", {})
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

-- Label, Blizzard micro button to click (secure), and a fallback function for
-- clients without that button.
local BUTTONS = {
	{ label = QUESTLOG_BUTTON or "Quests", micro = { "QuestLogMicroButton" }, fallback = "ToggleQuestLog" },
	-- The game menu micro button opens on mouse-up rather than OnClick, so a
	-- secure click on it does nothing; open the menu directly instead.
	{ label = MAINMENU_BUTTON or "Menu", micro = {}, fallback = "ToggleGameMenu" },
	{ label = SOCIAL_BUTTON or "Allies", micro = { "SocialsMicroButton", "FriendsMicroButton", "GuildMicroButton" },
		fallback = "ToggleFriendsFrame" },
	{ label = WORLD_MAP or "Map", micro = { "WorldMapMicroButton" }, fallback = "ToggleWorldMap" },
}

local FEED_GOLD, FEED_BAGS, FEED_REPAIR = "Reforged: Gold", "Reforged: Bags", "Reforged: Durability"
local DEFAULT_SLOTS = { FEED_REPAIR, FEED_BAGS, FEED_GOLD } -- slot 1 is at the core's right edge

local Container = C_Container or {}
local numFreeSlots = Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local numSlots = Container.GetContainerNumSlots or GetContainerNumSlots

local function place(region, r)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", ns.topRoot, "BOTTOMLEFT", r.x, r.y)
	region:SetSize(r.w, r.h)
end

local function firstGlobal(names)
	for _, name in ipairs(names) do
		if _G[name] then
			return _G[name]
		end
	end
end

----------------------------------------------------------------------------
-- Our own feeds

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

function TopBar:CreateFeeds()
	if not LDB then
		return
	end
	self.feeds = {
		gold = LDB:NewDataObject(FEED_GOLD, {
			type = "data source", label = "Gold", text = "0",
			icon = "Interface\\MoneyFrame\\UI-GoldIcon",
			OnTooltipShow = function(tip)
				tip:AddLine("Gold", 1, 1, 1)
				tip:AddLine(GetCoinTextureString and GetCoinTextureString(GetMoney()) or tostring(GetMoney()))
			end,
		}),
		bags = LDB:NewDataObject(FEED_BAGS, {
			type = "data source", label = "Bags", text = "0 / 0",
			icon = "Interface\\Buttons\\Button-Backpack-Up",
			OnClick = function() if ToggleAllBags then ToggleAllBags() end end,
			OnTooltipShow = function(tip)
				tip:AddLine(BAGSLOT or "Bags", 1, 1, 1)
				tip:AddLine("Free / total slots. Click to open your bags.", 0.8, 0.8, 0.8)
			end,
		}),
		repair = LDB:NewDataObject(FEED_REPAIR, {
			type = "data source", label = "Durability", text = "-",
			icon = "Interface\\Icons\\Trade_BlackSmithing",
			OnTooltipShow = function(tip)
				tip:AddLine(DURABILITY or "Durability", 1, 1, 1)
				tip:AddLine("Lowest durability of your equipped items.", 0.8, 0.8, 0.8)
			end,
		}),
	}
	for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
		"UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }) do
		ns:On(e, function() self:UpdateFeeds() end)
	end
end

function TopBar:UpdateFeeds()
	local feeds = self.feeds
	if not feeds then
		return
	end
	local gold = math.floor(GetMoney() / 10000)
	feeds.gold.text = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)

	local free, total = 0, 0
	if numSlots and numFreeSlots then
		for bag = 0, 4 do
			free = free + (numFreeSlots(bag) or 0)
			total = total + (numSlots(bag) or 0)
		end
	end
	feeds.bags.text = ("%d / %d"):format(free, total)

	local pct = durability()
	if not pct then
		feeds.repair.text = "-"
	else
		local color = pct < 0.25 and "ff3333" or pct < 0.5 and "ffd100" or "ffffff"
		feeds.repair.text = ("|cff%s%d%%|r"):format(color, pct * 100 + 0.5)
	end
end

----------------------------------------------------------------------------
-- Slots

local function feedText(name, obj)
	if obj.type == "launcher" then
		return obj.label or obj.text or name
	end
	if obj.text and obj.text ~= "" then
		return obj.text
	end
	if obj.value then
		return (obj.label and (obj.label .. ": ") or "") .. tostring(obj.value) .. (obj.suffix and (" " .. obj.suffix) or "")
	end
	return obj.label or name
end

function TopBar:SlotFeed(i)
	return ns.db.broker.slots[i]
end

function TopBar:SetSlotFeed(i, name)
	local slots = ns.db.broker.slots
	if name then
		for j, other in pairs(slots) do
			if other == name then
				slots[j] = false -- a feed shows in one slot at a time
			end
		end
	end
	slots[i] = name or false
	self:RefreshSlots()
end

function TopBar:FeedNames()
	local names = {}
	if LDB then
		for name in LDB:DataObjectIterator() do
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

function TopBar:OpenSlotMenu(slot)
	local current = self:SlotFeed(slot.index)
	local items = { { text = "Empty", checked = not current, func = function() self:SetSlotFeed(slot.index, nil) end } }
	for _, name in ipairs(self:FeedNames()) do
		items[#items + 1] = {
			text = name, checked = current == name,
			func = function() self:SetSlotFeed(slot.index, name) end,
		}
	end
	if not ns:ShowMenu(slot, "Slot " .. slot.index, items) then
		ns:Print("use /rui feeds and /rui slot <number> <feed name>|none")
	end
end

local function slotEnter(slot)
	local name = TopBar:SlotFeed(slot.index)
	local obj = name and LDB and LDB:GetDataObjectByName(name)
	if obj and obj.OnEnter then
		obj.OnEnter(slot)
		return
	end
	GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
	if obj and obj.OnTooltipShow then
		obj.OnTooltipShow(GameTooltip)
	elseif obj then
		GameTooltip:AddLine(obj.label or name, 1, 1, 1)
	else
		GameTooltip:AddLine("Empty slot", 1, 1, 1)
		GameTooltip:AddLine("Right-click to choose a data feed.", 0.8, 0.8, 0.8)
	end
	if obj then
		GameTooltip:AddLine("Alt-right-click to change this slot.", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function slotLeave(slot)
	local name = TopBar:SlotFeed(slot.index)
	local obj = name and LDB and LDB:GetDataObjectByName(name)
	if obj and obj.OnLeave then
		obj.OnLeave(slot)
	else
		GameTooltip:Hide()
	end
end

local function slotClick(slot, button)
	local name = TopBar:SlotFeed(slot.index)
	local obj = name and LDB and LDB:GetDataObjectByName(name)
	if button == "RightButton" and (IsAltKeyDown() or not (obj and obj.OnClick)) then
		GameTooltip:Hide()
		TopBar:OpenSlotMenu(slot)
	elseif obj and obj.OnClick then
		obj.OnClick(slot, button)
	end
end

function TopBar:GetSlot(i)
	local slot = self.slots[i]
	if not slot then
		slot = CreateFrame("Button", nil, self.holder)
		slot.index = i
		slot:SetFrameLevel(50)
		-- The dark plate is a child frame, so it draws above the slot's own
		-- regions; the icon and text go on a frame above the plate.
		slot.plate = ns.Art.CreateInset(slot, 51)
		slot.plate:SetAllPoints()
		local face = CreateFrame("Frame", nil, slot)
		face:SetAllPoints()
		face:SetFrameLevel(53)
		slot.icon = face:CreateTexture(nil, "OVERLAY")
		slot.icon:SetSize(12, 12)
		slot.icon:SetPoint("LEFT", 6, 0)
		slot.text = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		slot.text:SetPoint("LEFT", slot.icon, "RIGHT", 4, 0)
		slot.text:SetPoint("RIGHT", -6, 0)
		slot.text:SetJustifyH("RIGHT")
		slot.text:SetWordWrap(false)
		slot:RegisterForClicks("AnyUp")
		slot:SetScript("OnEnter", slotEnter)
		slot:SetScript("OnLeave", slotLeave)
		slot:SetScript("OnClick", slotClick)
		if ns.theme then
			ns.Art.PaintInset(slot.plate, ns.theme)
		end
		self.slots[i] = slot
	end
	return slot
end

function TopBar:RefreshSlot(slot)
	local name = self:SlotFeed(slot.index)
	local obj = name and LDB and LDB:GetDataObjectByName(name)
	if obj then
		slot.icon:SetTexture(obj.icon)
		slot.icon:SetShown(obj.icon ~= nil)
		slot.text:SetText(feedText(name, obj))
		if obj.iconR then
			slot.icon:SetVertexColor(obj.iconR, obj.iconG or 1, obj.iconB or 1)
		else
			slot.icon:SetVertexColor(1, 1, 1)
		end
	else
		slot.icon:Hide()
		slot.text:SetText("")
	end
end

function TopBar:RefreshSlots()
	for _, slot in ipairs(self.slots) do
		if slot:IsShown() then
			self:RefreshSlot(slot)
		end
	end
end

----------------------------------------------------------------------------
-- Module

function TopBar:OnEnable()
	local db = ns.db.broker
	db.slots = db.slots or {}
	if not db.initialised then
		for i, name in ipairs(DEFAULT_SLOTS) do
			db.slots[i] = name
		end
		db.initialised = true
	end

	-- The top bar has its own root and scale (see Core.lua).
	local root = ns.topRoot
	self.panel = ns.Art.CreatePanel(root, 40, true)
	self.holder = CreateFrame("Frame", "ReforgedUITopBar", root)
	self.holder:SetFrameStrata("LOW")
	self.holder:SetAllPoints(root)
	self.slots = {}

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
			local plate = ns.Art.CreateInset(self.holder, 50)
			plate.text = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			plate.text:SetPoint("CENTER")
			plate.text:SetText(spec.label)
			local btn
			if target then
				btn = CreateFrame("Button", "ReforgedUITopButton" .. i, plate, "SecureActionButtonTemplate")
				btn:SetAttribute("type", "click")
				btn:SetAttribute("clickbutton", target)
				btn:RegisterForClicks("AnyUp")
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

	self:CreateFeeds()
	if LDB then
		local refresh = ns:Throttle(function() self:RefreshSlots() end, 0.05)
		LDB.RegisterCallback(self, "LibDataBroker_DataObjectCreated", refresh)
		LDB.RegisterCallback(self, "LibDataBroker_AttributeChanged", function(_, name)
			for _, slot in ipairs(self.slots) do
				if slot:IsShown() and self:SlotFeed(slot.index) == name then
					self:RefreshSlot(slot)
				end
			end
		end)
	end
end

function TopBar:UpdateClock()
	local h, m = GetGameTime()
	local hours = (h or 12) + (m or 0) / 60
	-- Noon puts the sun at the bottom of the window; the dial turns
	-- anticlockwise so the sun rises on the left and sets on the right.
	self.dial:SetRotation((hours - 12) / 24 * 2 * math.pi)
end

function TopBar:OnLayout()
	local L = ns.topLayout
	ns.Art.PlacePanel(self.panel, L.topBar, ns.topRoot, false)
	local c = L.clock
	self.dial:ClearAllPoints()
	self.dial:SetPoint("CENTER", ns.topRoot, "BOTTOMLEFT", c.cx, c.cy)
	self.dial:SetSize(c.radius * 2, c.radius * 2)
	place(self.clockFrame, L.clockFrame)
	for i, plate in ipairs(self.buttons) do
		local r = L.topButtons[i]
		if r then
			place(plate, r)
		end
		plate:SetShown(r and true or false)
	end
	for i, r in ipairs(L.topSlots) do
		local slot = self:GetSlot(i)
		place(slot, r)
		slot:Show()
	end
	for i = #L.topSlots + 1, #self.slots do
		self.slots[i]:Hide()
	end
	self:UpdateClock()
	self:UpdateFeeds()
	self:RefreshSlots()
end

function TopBar:OnTheme(theme)
	ns.Art.PaintPanel(self.panel, theme)
	self.clockArt:SetTexture(ns:Media("clockframe", theme))
	for _, plate in ipairs(self.buttons) do
		ns.Art.PaintInset(plate, theme)
		plate.text:SetTextColor(unpack(theme.title))
	end
	for _, slot in ipairs(self.slots) do
		ns.Art.PaintInset(slot.plate, theme)
	end
	if ns.topLayout then
		ns.Art.PlacePanel(self.panel, ns.topLayout.topBar, ns.topRoot, false)
	end
end

-- For /rui feeds and /rui slot.
function TopBar:ListFeeds()
	ns:Print("data feeds:", table.concat(self:FeedNames(), ", "))
	for i, slot in ipairs(self.slots) do
		if slot:IsShown() then
			print(("  slot %d: %s"):format(i, self:SlotFeed(i) or "empty"))
		end
	end
end

function TopBar:SetSlotByName(i, query)
	if query == "none" or query == "empty" then
		self:SetSlotFeed(i, nil)
		return true
	end
	for _, name in ipairs(self:FeedNames()) do
		if name:lower() == query or name:lower():find(query, 1, true) then
			self:SetSlotFeed(i, name)
			return name
		end
	end
end
