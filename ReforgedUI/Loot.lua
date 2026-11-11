-- The group's loot rules as a feed ("Reforged: Loot") for the top bar's
-- slots and any other LibDataBroker display: the loot method (Free for All,
-- Round Robin, Master Looter, Group Loot, Need before Greed), with the loot
-- threshold in its quality colour where the method uses one. The tooltip
-- explains the method and names the threshold and the master looter. A
-- right-click lets the group leader change both, the way the player
-- portrait's menu does; anyone else gets told who can.
--
-- Reads C_PartyInfo.GetLootMethod (an Enum.LootMethod number) where the
-- client has it, else the older GetLootMethod (a name); sets with
-- C_PartyInfo.SetLootMethod or SetLootMethod, and SetLootThreshold.

local _, ns = ...
local Loot = ns:RegisterModule("loot", {})
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

local FEED = "Reforged: Loot"
Loot.FEED = FEED
local ICON = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
Loot.ICON = ICON

local GREY = "|cffcccccc"

-- Our names for the methods, in menu order, with the client's enum names,
-- the older API's names and the words should the client lack its strings.
local METHODS = {
	{ key = "freeforall", enum = "Freeforall", old = "freeforall", label = "LOOT_FREE_FOR_ALL",
		name = "Free for All", tip = "NEWBIE_TOOLTIP_UNIT_FREE_FOR_ALL",
		desc = "Anyone can loot any corpse.", threshold = false },
	{ key = "roundrobin", enum = "Roundrobin", old = "roundrobin", label = "LOOT_ROUND_ROBIN",
		name = "Round Robin", tip = "NEWBIE_TOOLTIP_UNIT_ROUND_ROBIN",
		desc = "Group members take turns looting corpses.", threshold = false },
	{ key = "master", enum = "Masterlooter", old = "master", label = "MASTER_LOOTER",
		name = "Master Looter", tip = "NEWBIE_TOOLTIP_UNIT_MASTER_LOOTER",
		desc = "One player hands out every item at or above the loot threshold.", threshold = true },
	{ key = "group", enum = "Group", old = "group", label = "LOOT_GROUP_LOOT",
		name = "Group Loot", tip = "NEWBIE_TOOLTIP_UNIT_GROUP_LOOT",
		desc = "Turns, as Round Robin, but everyone rolls Need or Greed on items at or above the loot threshold.",
		threshold = true },
	{ key = "needbeforegreed", enum = "Needbeforegreed", old = "needbeforegreed", label = "LOOT_NEED_BEFORE_GREED",
		name = "Need before Greed", tip = "NEWBIE_TOOLTIP_UNIT_NEED_BEFORE_GREED",
		desc = "As Group Loot, but only those who can use an item may roll Need on it.", threshold = true },
	{ key = "personal", enum = "Personal", old = "personalloot", label = "LOOT_PERSONAL_LOOT",
		name = "Personal Loot", desc = "Everyone gets their own loot.", threshold = false },
}
Loot.METHODS = METHODS
local byKey, byOld = {}, {}
for _, m in ipairs(METHODS) do
	byKey[m.key], byOld[m.old] = m, m
end

-- The thresholds a leader may pick (as Blizzard's menu offers), and the
-- quality colours should the client lack its own.
local THRESHOLDS = { 2, 3, 4 }
local QUALITY = {
	[0] = { "Poor", "9d9d9d" }, { "Common", "ffffff" }, { "Uncommon", "1eff00" }, { "Rare", "0070dd" },
	{ "Epic", "a335ee" }, { "Legendary", "ff8000" }, { "Artifact", "e6cc80" },
}

local function methodName(m)
	return _G[m.label] or m.name
end

local function methodDesc(m)
	local tip = m.tip and _G[m.tip]
	return (type(tip) == "string" and tip ~= "") and tip or m.desc
end

local function enumValue(m)
	local e = Enum and Enum.LootMethod
	return e and e[m.enum]
end

local function secret(v)
	return issecretvalue and issecretvalue(v)
end

-- The quality's name and colour: r, g, b and the hex for text.
function Loot.Quality(q)
	local name = _G["ITEM_QUALITY" .. tostring(q) .. "_DESC"]
	local r, g, b
	local colors = _G.ITEM_QUALITY_COLORS
	local c = colors and colors[q]
	if c then
		r, g, b = c.r, c.g, c.b
	end
	local own = QUALITY[q] or QUALITY[1]
	name = name or own[1]
	if not r then
		local hex = own[2]
		r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
	end
	return name, r, g, b, ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5))
end

function Loot.InGroup()
	if IsInGroup then
		return IsInGroup() and true or false
	end
	return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

function Loot.IsLeader()
	return UnitIsGroupLeader and UnitIsGroupLeader("player") and true or false
end

local function unitName(unit)
	local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
	if name == nil or secret(name) then
		return nil
	end
	return name
end

-- The current rules: { method = METHODS entry, threshold = quality,
-- master = name, masterUnit = unit }, or nil when not in a group.
function Loot:Current()
	if not Loot.InGroup() then
		return nil
	end
	local m, partyID, raidID
	local api = C_PartyInfo
	if api and api.GetLootMethod then
		local ok, method, p, r = pcall(api.GetLootMethod)
		if ok and not secret(method) then
			for _, entry in ipairs(METHODS) do
				if enumValue(entry) == method then
					m = entry
					break
				end
			end
			partyID, raidID = p, r
		end
	end
	if not m and GetLootMethod then
		local ok, method, p, r = pcall(GetLootMethod)
		if ok and type(method) == "string" then
			m, partyID, raidID = byOld[method], p, r
		end
	end
	if not m then
		return nil
	end
	local cur = { method = m }
	if GetLootThreshold then
		local ok, q = pcall(GetLootThreshold)
		cur.threshold = ok and not secret(q) and tonumber(q) or nil
	end
	if m.key == "master" then
		-- The master looter: a raid index in a raid, else 0 (us) to 4.
		local unit
		if raidID and not secret(raidID) and raidID > 0 then
			unit = "raid" .. raidID
		elseif partyID and not secret(partyID) then
			unit = partyID == 0 and "player" or "party" .. partyID
		end
		cur.masterUnit = unit
		cur.master = unit and unitName(unit)
	end
	return cur
end

-- The methods this client and group offer, in menu order.
function Loot:Available()
	local list = {}
	local api = C_PartyInfo
	for _, m in ipairs(METHODS) do
		local e = enumValue(m)
		local ok = true
		if api and api.IsLootMethodAvailable and e then
			local fine, avail = pcall(api.IsLootMethodAvailable, e)
			ok = fine and avail and true or false
		elseif m.key == "personal" then
			ok = false -- the older clients have no personal loot to set
		end
		if ok then
			list[#list + 1] = m
		end
	end
	return list
end

function Loot:SetMethod(key, master)
	local m = byKey[key]
	if not m then
		return
	end
	local api = C_PartyInfo
	if api and api.SetLootMethod and enumValue(m) then
		api.SetLootMethod(enumValue(m), master)
	elseif SetLootMethod then
		SetLootMethod(m.old, master)
	end
end

function Loot:SetThreshold(q)
	if SetLootThreshold then
		SetLootThreshold(q)
	end
end

-- The feed's text: the method, with the threshold in its colour where
-- the method uses one.
function Loot:FeedText(cur)
	if cur == nil then
		cur = self:Current()
	end
	if not cur then
		return GREY .. "Solo|r"
	end
	local text = methodName(cur.method)
	if cur.method.threshold and cur.threshold then
		local name, _, _, _, hex = Loot.Quality(cur.threshold)
		text = ("%s |cff%s%s|r"):format(text, hex, name)
	end
	return text
end

function Loot:Tooltip(tip)
	tip:AddLine(_G.LOOT_METHOD or "Loot Method", 1, 1, 1)
	local cur = self:Current()
	if not cur then
		tip:AddLine("You're not in a group, so you loot everything yourself. The group's leader sets the loot "
			.. "method once you're in one.", 0.8, 0.8, 0.8, true)
		return
	end
	local m = cur.method
	tip:AddDoubleLine("Method", methodName(m), 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddLine(methodDesc(m), 0.8, 0.8, 0.8, true)
	if cur.threshold and m.key ~= "personal" then
		local name, r, g, b = Loot.Quality(cur.threshold)
		tip:AddDoubleLine("Loot threshold", name, 0.8, 0.8, 0.8, r, g, b)
		if m.threshold then
			tip:AddLine(("Items of %s quality and better are %s."):format(name,
				m.key == "master" and "handed out by the master looter" or "rolled for"), 0.8, 0.8, 0.8, true)
		end
	end
	if m.key == "master" then
		tip:AddDoubleLine("Master looter", cur.master or (_G.UNKNOWN or "Unknown"), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if Loot.IsLeader() then
		tip:AddLine(GREY .. "Right-click to change the loot method or threshold.|r")
	else
		tip:AddLine(GREY .. "Only the group leader can change these.|r")
	end
end

-- The group's members, as { unit, name, class } for the master looter
-- menu: the player first.
function Loot:Members()
	local list = {}
	local function add(unit)
		local name = unitName(unit)
		if name and UnitExists(unit) then
			local _, class = UnitClass(unit)
			list[#list + 1] = { unit = unit, name = name, class = class }
		end
	end
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
			add("raid" .. i)
		end
	else
		add("player")
		for i = 1, 4 do
			add("party" .. i)
		end
	end
	return list
end

local function classColored(member)
	local c = member.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
	if c and c.colorStr then
		return ("|c%s%s|r"):format(c.colorStr, member.name)
	end
	return member.name
end

-- The right-click menu: the methods (Master Looter with the group's
-- members under it) and the thresholds. Returns false where it can't show
-- one.
function Loot:OpenMenu(owner)
	if not Loot.InGroup() then
		ns:Print("you're not in a group: there's no loot method to set.")
		return false
	end
	if not Loot.IsLeader() then
		ns:Print("only the group leader can change the loot method.")
		return false
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns:Print("this client has no menu to show; use the menu on your portrait.")
		return false
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(_G.LOOT_METHOD or "Loot Method")
		for _, m in ipairs(self:Available()) do
			local item = root:CreateRadio(methodName(m), function()
				local cur = self:Current()
				return cur and cur.method == m
			end, function()
				self:SetMethod(m.key, m.key == "master" and unitName("player") or nil)
			end)
			if item.SetTooltip then
				item:SetTooltip(function(tip)
					tip:AddLine(methodName(m), 1, 1, 1)
					tip:AddLine(methodDesc(m), 0.8, 0.8, 0.8, true)
				end)
			end
			if m.key == "master" then
				-- Pick who hands out the loot; clicking Master Looter
				-- itself makes it the player.
				for _, member in ipairs(self:Members()) do
					item:CreateRadio(classColored(member), function()
						local cur = self:Current()
						return cur and cur.method == m and cur.master == member.name
					end, function()
						self:SetMethod("master", member.name)
					end)
				end
			end
		end
		local cur = self:Current()
		if not (cur and cur.method.key == "personal") then
			root:CreateTitle(_G.LOOT_THRESHOLD or "Loot Threshold")
			for _, q in ipairs(THRESHOLDS) do
				local name, _, _, _, hex = Loot.Quality(q)
				root:CreateRadio(("|cff%s%s|r"):format(hex, name), function()
					local now = self:Current()
					return now and now.threshold == q
				end, function()
					self:SetThreshold(q)
				end)
			end
		end
	end)
	return true
end

function Loot:Update()
	if self.feed then
		self.feed.text = self:FeedText()
	end
end

function Loot:OnEnable()
	if LDB then
		self.feed = LDB:NewDataObject(FEED, {
			type = "data source", label = _G.LOOT_METHOD or "Loot", text = "", icon = ICON,
			OnClick = function(frame, button)
				if button == "RightButton" then
					Loot:OpenMenu(frame)
				end
			end,
			OnTooltipShow = function(tip) Loot:Tooltip(tip) end,
		})
	end
	local update = ns:Throttle(function() self:Update() end, 0.2)
	for _, e in ipairs({ "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
		"PLAYER_ENTERING_WORLD" }) do
		ns:On(e, update)
	end
	self:Update()
end
