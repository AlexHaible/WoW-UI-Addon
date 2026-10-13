-- The Warcraft III top bar: menu buttons on the left, the day/night clock in
-- the middle turning with the game's server time (sun at the bottom of the
-- window at noon, moon at midnight) with Blizzard's own micro buttons
-- (character, talents, achievements, group finder, ...) either side of it,
-- and slots for LibDataBroker feeds, like Titan Panel, everywhere else. Gold, bag space and durability are feeds of
-- our own and fill the first three slots by default. Right-click an empty
-- slot, or Alt-right-click a filled one, to choose its feed.

local _, ns = ...
local TopBar = ns:RegisterModule("topbar", {})
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

-- Label, Blizzard micro button to click (secure), and a fallback function for
-- clients without that button. `cover` is a Blizzard button laid, invisible,
-- over ours so the player clicks it directly: the game menu, quest log and
-- social buttons open on their own mouse-up (a secure click does nothing),
-- and opening the menu from addon code is blocked (ToggleGameMenu stops
-- spell casts) or taints the menu and the Edit Mode button in it.
local BUTTONS = {
	{ label = QUESTLOG_BUTTON or "Quests", micro = {}, cover = { "QuestLogMicroButton" }, fallback = "ToggleQuestLog" },
	{ label = MAINMENU_BUTTON or "Menu", micro = {}, cover = { "MainMenuMicroButton" } },
	{ label = SOCIAL_BUTTON or "Allies", micro = {}, cover = { "SocialsMicroButton", "FriendsMicroButton", "GuildMicroButton" },
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
	-- All of the top bar stays in the BACKGROUND strata (its root's), below
	-- every Blizzard frame: buffs and debuffs that Edit Mode leaves under it
	-- draw on top of the bar instead of behind it.
	self.holder:SetFrameStrata("BACKGROUND")
	self.holder:SetAllPoints(root)
	self.slots = {}

	-- Day/night clock: the frame hangs from the top of the screen over the
	-- bar, and the dial turns between the two (above the bar, below the
	-- frame), showing only through the frame's window.
	self.dialFrame = CreateFrame("Frame", nil, root)
	self.dialFrame:SetFrameLevel(41)
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
	local covers = {}
	for i, spec in ipairs(BUTTONS) do
		local target = firstGlobal(spec.micro)
		local fallback = spec.fallback and _G[spec.fallback]
		local cover = spec.cover and firstGlobal(spec.cover)
		if cover and ns.IsForbidden(cover) then
			cover = nil
		end
		if target or fallback or cover then
			local plate = ns.Art.CreateInset(self.holder, 50)
			plate.text = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			plate.text:SetPoint("CENTER")
			plate.text:SetText(spec.label)
			local btn
			if cover then
				covers[cover] = true
				self:SetupCover(plate, cover)
			elseif target then
				btn = CreateFrame("Button", "ReforgedUITopButton" .. i, plate, "SecureActionButtonTemplate")
				btn:SetAttribute("type", "click")
				btn:SetAttribute("clickbutton", target)
				btn:RegisterForClicks("AnyUp")
			else
				btn = CreateFrame("Button", "ReforgedUITopButton" .. i, plate)
				btn:SetScript("OnClick", function() fallback() end)
			end
			if btn then
				btn:SetAllPoints()
				btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			end
			plate.button = btn
			self.buttons[#self.buttons + 1] = plate
		end
	end

	self:TakeMicroButtons(covers)

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

-- Makes Blizzard's button `b` an invisible, clickable cover for `plate`: it
-- stays transparent and takes the mouse whatever else sets, and lights the
-- plate up on hover. Nothing of Blizzard's runs from our code.
function TopBar:SetupCover(plate, b)
	plate.cover = b
	plate.hl = plate:CreateTexture(nil, "OVERLAY")
	plate.hl:SetAllPoints()
	plate.hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
	plate.hl:SetBlendMode("ADD")
	plate.hl:Hide()
	b:HookScript("OnEnter", function() plate.hl:Show() end)
	b:HookScript("OnLeave", function() plate.hl:Hide() end)
	local busy
	local function keep(f)
		if busy then
			return
		end
		busy = true
		f:SetAlpha(0)
		if not InCombatLockdown() then
			f:EnableMouse(true)
		end
		busy = false
	end
	hooksecurefunc(b, "SetAlpha", keep)
	hooksecurefunc(b, "EnableMouse", keep)
	keep(b)
end

-- Lays `b` exactly over `plate`, on top of the top bar.
local function coverPlate(b, plate)
	local left, bottom = plate:GetLeft(), plate:GetBottom()
	if not left then
		return
	end
	local parent = b:GetParent() or UIParent
	local pe = plate:GetEffectiveScale()
	b:SetScale(pe / parent:GetEffectiveScale())
	b:SetSize(plate:GetWidth(), plate:GetHeight())
	b:SetFrameStrata("HIGH")
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * pe / b:GetEffectiveScale(), bottom * pe / b:GetEffectiveScale())
end

----------------------------------------------------------------------------
-- Blizzard's micro buttons beside the clock

-- Blizzard's order. The plates already stand for the quest log, game menu,
-- social and world map buttons: those stay invisible, as covers over their
-- plates or where they are. Every other micro button the client has (found
-- by name, or among the micro menu's children) moves into the top bar, half
-- either side of the clock, still Blizzard's own button with its own clicks,
-- tooltip, alerts and enabled state; only its position and scale are ours.
local MICRO_ORDER = {
	"CharacterMicroButton", "SpellbookMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
	"TalentMicroButton", "LegacyMicroButton", "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton",
	"SocialsMicroButton", "FriendsMicroButton", "GuildMicroButton", "LFGMicroButton", "LFDMicroButton",
	"WorldMapMicroButton", "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton",
	"MainMenuMicroButton", "HelpMicroButton",
}
-- Buttons for features Forever doesn't have (yet).
local SKIP_MICRO = { HousingMicroButton = true }
local PLATE_MICRO = {
	QuestLogMicroButton = true, MainMenuMicroButton = true, SocialsMicroButton = true,
	FriendsMicroButton = true, WorldMapMicroButton = true,
}

local function microName(b)
	if type(b) ~= "table" or ns.IsForbidden(b) then
		return
	end
	local ok, name = pcall(b.GetName, b)
	if ok and type(name) == "string" and name:find("MicroButton$") then
		return name
	end
end

local function plain(v)
	return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

-- A button's art area: its height and bottom inset, without the part its
-- hit rectangle leaves out (Classic-style buttons are taller than their art).
-- Every micro button is scaled by its full height: their hit insets differ
-- from button to button, and going by those drew some of them oversized.
local function artHeight(b)
	local h = b:GetHeight()
	if not (plain(h) and h > 0) then
		return
	end
	return h, 0
end

function TopBar:TakeMicroButtons(covers)
	local rank = {}
	for i, name in ipairs(MICRO_ORDER) do
		rank[name] = i
	end
	local found, seen, byLayout = {}, {}, true
	local function consider(b, n)
		local name = microName(b)
		if not name or seen[b] or covers[b] then
			return
		end
		-- Forever has the classic talent button and the newer spells and
		-- talents one; with a spellbook button of its own, keep the classic.
		local duplicate = (name == "PlayerSpellsMicroButton" and _G.TalentMicroButton and _G.SpellbookMicroButton)
			-- Forever's Legacy button takes the achievement button's place
			-- (the old one opens the same panel).
			or (name == "AchievementMicroButton" and _G.LegacyMicroButton)
		if SKIP_MICRO[name] or name:find("Housing") or duplicate then
			seen[b] = true
			ns:Conceal(b)
			return
		end
		seen[b] = true
		if PLATE_MICRO[name] then
			ns:Conceal(b) -- e.g. the world map button, which the Map plate clicks
			return
		end
		local index = b.layoutIndex
		byLayout = byLayout and plain(index)
		found[#found + 1] = { button = b, index = plain(index) and index or 0, rank = rank[name] or (#MICRO_ORDER + n) }
	end
	for i, name in ipairs(MICRO_ORDER) do
		consider(_G[name], i)
	end
	local menu = _G.MicroMenu
	if type(menu) == "table" and menu.GetChildren and not ns.IsForbidden(menu) then
		for i, child in ipairs({ menu:GetChildren() }) do
			consider(child, i)
		end
	end
	-- The micro menu lays its buttons out by layoutIndex where it has one.
	table.sort(found, function(a, b)
		if byLayout and a.index ~= b.index then
			return a.index < b.index
		end
		return a.rank < b.rank
	end)
	self.micro = {}
	for i, entry in ipairs(found) do
		self.micro[i] = entry.button
	end
	ns.microButtons = self.micro
	if #self.micro == 0 then
		return
	end

	-- The micro menu stays where Edit Mode puts it, empty now: let clicks
	-- through it, and make its own art (border, background) and any other
	-- frame left in it invisible. The moved buttons and the group finder's
	-- eye keep theirs.
	local keep = { [_G.QueueStatusButton or false] = true, [_G.QueueStatusFrame or false] = true }
	for _, b in ipairs(self.micro) do
		keep[b] = true
	end
	for b in pairs(covers) do
		keep[b] = true
	end
	for _, name in ipairs({ "MicroMenuContainer", "MicroMenu" }) do
		local f = _G[name]
		if type(f) == "table" and f.EnableMouse and not ns.IsForbidden(f) then
			ns:RunOutOfCombat("micro mouse " .. name, function() f:EnableMouse(false) end)
			for _, region in ipairs({ f:GetRegions() }) do
				ns:ConcealRegion(region)
			end
			for _, child in ipairs({ f:GetChildren() }) do
				if not keep[child] and child ~= _G.MicroMenu and not ns.IsForbidden(child) then
					ns:Conceal(child)
				end
			end
		end
	end

	-- Blizzard shows and hides some buttons (the shop, for one): make room
	-- for exactly the shown ones. A new size for the micro menu (Edit Mode)
	-- rescales its buttons, so put them back.
	local relayout = ns:Throttle(function() ns:Relayout() end, 0.1)
	local hooked = {}
	for _, b in ipairs(self.micro) do
		b:HookScript("OnShow", relayout)
		b:HookScript("OnHide", relayout)
		local p = b:GetParent()
		while p and p ~= UIParent and not hooked[p] and not ns.IsForbidden(p) do
			hooked[p] = true
			hooksecurefunc(p, "SetScale", function() self:PlaceMicro() end)
			p = p:GetParent()
		end
	end
end

-- Width/height of each shown micro button, for the layout (Core.lua).
function ns:TopBarMicroRatios()
	local ratios, shown = {}, {}
	for _, b in ipairs(TopBar.micro or {}) do
		if b:IsShown() then
			local w, h = b:GetWidth(), artHeight(b)
			ratios[#ratios + 1] = (plain(w) and w > 0 and h) and w / h or 0.8
			shown[#shown + 1] = b
		end
	end
	TopBar.microShown = shown
	return ratios
end

-- Scales `b` so its art is `r.h` top bar units tall and anchors it to
-- UIParent (never to our frames) at `r`, keeping its parent.
local function placeMicro(b, r)
	local h, bottom = artHeight(b)
	if not h then
		return
	end
	local rootScale = ns.topRoot:GetEffectiveScale()
	local parent = b:GetParent() or UIParent
	b:SetScale(r.h * rootScale / (h * parent:GetEffectiveScale()))
	local s = rootScale / b:GetEffectiveScale()
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r.x * s, r.y * s - bottom)
end

-- The micro menu lays its buttons out again now and then; the lock puts
-- them back.
function TopBar:PlaceMicro()
	local rects = ns.topLayout and ns.topLayout.micro
	if not rects then
		return
	end
	for i, b in ipairs(self.microShown or {}) do
		local r = rects[i]
		if r then
			ns:Lock(b, function(f) placeMicro(f, r) end, { "SetScale" })
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
		if plate.cover and r then
			ns:Lock(plate.cover, function(b) coverPlate(b, plate) end, { "SetScale" })
		end
	end
	self:PlaceMicro()
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
		-- SetFont returns nothing when the game has no such font.
		if not (theme.font and plate.text:SetFont(theme.font, 11, "")) then
			plate.text:SetFontObject("GameFontNormalSmall")
		end
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
