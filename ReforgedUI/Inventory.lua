-- The Warcraft III 2x3 inventory, holding the backpack and bag slots, with the
-- key ring beside it. Click to open a bag, drag a bag onto a slot to equip it,
-- drag from a slot to pick the bag up. A small number shows the free slots in
-- each bag.

local _, ns = ...
local Inventory = ns:RegisterModule("inventory", {})
local Layout = ns.Layout

local BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03"

local Container = C_Container or {}
local toInventoryID = Container.ContainerIDToInventoryID or ContainerIDToInventoryID
local numFreeSlots = Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local numSlots = Container.GetContainerNumSlots or GetContainerNumSlots

local function inventoryID(bag)
	if bag == 0 or not toInventoryID then
		return nil
	end
	local ok, id = pcall(toInventoryID, bag)
	return ok and id or nil
end

-- Clicks go through Blizzard's own (hidden) bag buttons: bag addons such as
-- BetterBags hook those buttons rather than ToggleBag, and keep Blizzard's
-- bag windows hidden. Without a bag addon the button just runs ToggleBag.
local function blizzardBagButton(bag)
	if bag == 0 then
		return MainMenuBarBackpackButton
	end
	return _G["CharacterBag" .. (bag - 1) .. "Slot"]
end

local function onClick(btn)
	local blizz = blizzardBagButton(btn.bag)
	if blizz and not ns.IsForbidden(blizz) and blizz.Click then
		blizz:Click()
	elseif btn.bag == 0 then
		ToggleBackpack()
	else
		ToggleBag(btn.bag)
	end
end

local function onReceiveDrag(btn)
	if btn.bag == 0 then
		PutItemInBackpack()
	elseif btn.invID then
		PutItemInBag(btn.invID)
	end
end

local function onDragStart(btn)
	if btn.invID then
		PickupBagFromSlot(btn.invID)
	end
end

local function onEnter(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
	if btn.bag == 0 then
		GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack", 1, 1, 1)
	elseif not GameTooltip:SetInventoryItem("player", btn.invID) then
		GameTooltip:SetText(EQUIP_CONTAINER or "Equip Container", 1, 1, 1)
	end
	GameTooltip:Show()
end

local function toggleKeyRing()
	if ToggleKeyRing then
		ToggleKeyRing()
	elseif KeyRingButton then
		KeyRingButton:Click()
	else
		ToggleBag(KEYRING_CONTAINER or -2)
	end
end

function Inventory:CreateKeyRing(holder)
	local btn = CreateFrame("Button", "ReforgedUIKeyRing", holder)
	-- A small key on the ledge above the bag slots.
	btn:SetNormalTexture(KEYRING_ICON)
	btn:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	btn:SetScript("OnClick", toggleKeyRing)
	btn:SetScript("OnReceiveDrag", function()
		if PutKeyInKeyRing then
			PutKeyInKeyRing()
		end
	end)
	btn:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		GameTooltip:SetText(KEYRING or "Key Ring", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	-- Only clients with a key ring (Classic-based ones, WoW: Forever) get one.
	btn:SetShown((ToggleKeyRing or KeyRingButton or KEYRING_CONTAINER) ~= nil)
	self.keyring = btn
end

function Inventory:OnEnable()
	self.buttons = {}
	local holder = CreateFrame("Frame", "ReforgedUIInventory", ns.root)
	holder:SetFrameStrata("MEDIUM") -- above Blizzard's (invisible) bar frames at the screen bottom
	holder:SetAllPoints(ns.root)
	for i = 1, 6 do
		local bag = i - 1 -- 0 backpack, 1-4 bags, 5 reagent bag (Retail only)
		local btn = CreateFrame("Button", "ReforgedUIBagSlot" .. i, holder)
		btn.bag = bag
		btn.invID = inventoryID(bag)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetAllPoints()
		btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.bevel = btn:CreateTexture(nil, "OVERLAY")
		btn.bevel:SetAllPoints()
		btn.bevel:SetTexture(ns.MEDIA .. "Common\\bevel")
		btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:RegisterForDrag("LeftButton")
		btn:SetScript("OnClick", onClick)
		btn:SetScript("OnReceiveDrag", onReceiveDrag)
		btn:SetScript("OnDragStart", onDragStart)
		btn:SetScript("OnEnter", onEnter)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		self.buttons[i] = btn
	end
	self:CreateKeyRing(holder)
	for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BAG_CONTAINER_UPDATE",
		"BAG_SLOT_FLAGS_UPDATED", "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED" }) do
		ns:On(e, function() self:Update() end)
	end
end

function Inventory:Update()
	for _, btn in ipairs(self.buttons) do
		if btn.bag == 0 then
			btn.icon:SetTexture(BACKPACK_ICON)
		elseif btn.invID then
			btn.icon:SetTexture(GetInventoryItemTexture("player", btn.invID) or EMPTY_ICON)
		end
		local size = numSlots and numSlots(btn.bag) or 0
		if size > 0 and numFreeSlots then
			btn.count:SetText((numFreeSlots(btn.bag)))
		else
			btn.count:SetText("")
		end
		-- Bag 5 only exists where the client has a reagent bag slot.
		btn:SetShown(btn.bag == 0 or btn.invID ~= nil)
	end
end

function Inventory:OnLayout(L)
	local g = L.inventory
	for i, btn in ipairs(self.buttons) do
		local x, y = Layout.GridCell(g, i)
		btn:ClearAllPoints()
		btn:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", x, y)
		btn:SetSize(g.size, g.size)
	end
	local k = L.keyring
	self.keyring:ClearAllPoints()
	self.keyring:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", k.x, k.y)
	self.keyring:SetSize(k.w, k.h)
	self:Update()
end
