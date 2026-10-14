-- The bags in the original addon's 2x3 inventory: backpack top-left, bags 1-4, then the
-- reagent bag (where the client has one) bottom-right, with the key ring
-- standing to the left of the grid.
--
-- These are our own buttons: clicks go through Blizzard's own (hidden) bag
-- buttons, which bag addons such as BetterBags hook, and drag and drop
-- equips or picks up bags. A small number shows the free slots in each bag.

local _, ns = ...
local Inventory = ns:RegisterModule("inventory", {})

local BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local KEYRING_ART = "Interface\\Buttons\\UI-Button-KeyRing"
local KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local REAGENT_BAG = 5

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

local function blizzardBagButton(bag)
	if bag == 0 then
		return MainMenuBarBackpackButton
	elseif bag == REAGENT_BAG then
		return CharacterReagentBag0Slot
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

local function onLeave()
	GameTooltip:Hide()
end

local function toggleKeyRing()
	if ToggleKeyRing then
		ToggleKeyRing()
	elseif KeyRingButton and not ns.IsForbidden(KeyRingButton) then
		KeyRingButton:Click()
	else
		ToggleBag(KEYRING_CONTAINER or -2)
	end
end

local function makeButton(holder, name)
	local btn = CreateFrame("Button", name, holder)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	ns:IconFrame(btn)
	btn:SetScript("OnLeave", onLeave)
	return btn
end

function Inventory:CreateKeyRing(holder)
	-- Blizzard's own tall key ring button (normal, pushed and highlight art),
	-- without the steel icon frame of the bag buttons. SetTexture returns
	-- false when the client lacks the file; then it is a key icon in the
	-- bag buttons' steel frame instead.
	local btn = CreateFrame("Button", "ReforgedUIKeyRing", holder)
	local normal = btn:CreateTexture(nil, "ARTWORK")
	if normal:SetTexture(KEYRING_ART) ~= false then
		btn:SetNormalTexture(KEYRING_ART)
		btn:SetPushedTexture(KEYRING_ART .. "-Down")
		btn:SetHighlightTexture(KEYRING_ART .. "-Highlight", "ADD")
		for _, t in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture(), btn:GetHighlightTexture() }) do
			t:SetTexCoord(0, 0.5625, 0, 0.609375)
		end
		normal:Hide()
	else
		btn.icon = normal
		normal:SetAllPoints()
		normal:SetTexture(KEYRING_ICON)
		normal:SetTexCoord(0.3, 0.7, 0.07, 0.93)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
		ns:IconFrame(btn)
	end
	btn:SetScript("OnLeave", onLeave)
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
	-- Only clients with a key ring (Classic-based ones, WoW: Forever) get one.
	btn.available = (ToggleKeyRing or KeyRingButton or KEYRING_CONTAINER) ~= nil
	self.keyring = btn
end

function Inventory:OnEnable()
	self.buttons = {}
	local holder = CreateFrame("Frame", "ReforgedUIBags", ns.root)
	holder:SetFrameStrata("MEDIUM") -- above Blizzard's (invisible) bar frames at the screen bottom
	holder:SetAllPoints(ns.root)
	self.holder = holder
	for i = 1, 6 do
		local bag = i - 1 -- 0 backpack, 1-4 bags, 5 reagent bag
		local btn = makeButton(holder, "ReforgedUIBagSlot" .. i)
		btn.bag = bag
		btn.invID = inventoryID(bag)
		btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:RegisterForDrag("LeftButton")
		btn:SetScript("OnClick", onClick)
		btn:SetScript("OnReceiveDrag", onReceiveDrag)
		btn:SetScript("OnDragStart", onDragStart)
		btn:SetScript("OnEnter", onEnter)
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
	end
end

function Inventory:OnLayout(L)
	local slots = L.bagSlots
	for i, btn in ipairs(self.buttons) do
		-- Bag 5 only exists where the client has a reagent bag slot.
		local shown = btn.bag == 0 or btn.invID ~= nil
		btn:SetShown(shown)
		if shown then
			ns.modules.console.Place(btn, slots[i])
		end
	end
	local key = self.keyring
	key:SetShown(key.available)
	ns.modules.console.Place(key, L.keyRing)
	self:Update()
end
