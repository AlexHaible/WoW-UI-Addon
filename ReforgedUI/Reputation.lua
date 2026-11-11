-- The watched faction (the one ticked "Show as Experience Bar" in the
-- reputation panel) as a feed ("Reforged: Reputation") for the top bar's
-- slots and any other LibDataBroker display: its name in its standing's
-- colour and how far along the standing it is, with the details in the
-- tooltip. A click opens the reputation panel.
--
-- Reads C_Reputation.GetWatchedFactionData where the client has it, else
-- the older GetWatchedFactionInfo; friendship factions and paragon levels
-- are shown the way the reputation panel shows them, where the client has
-- those.

local _, ns = ...
local Reputation = ns:RegisterModule("reputation", {})
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

local FEED = "Reforged: Reputation"
Reputation.FEED = FEED
local ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
Reputation.ICON = ICON

-- The game's standing colours (FACTION_BAR_COLORS), should the client lack
-- the table: Hated to Exalted.
local COLORS = {
	{ r = 0.8, g = 0.3, b = 0.22 }, { r = 0.8, g = 0.3, b = 0.22 }, { r = 0.75, g = 0.27, b = 0 },
	{ r = 0.9, g = 0.7, b = 0 }, { r = 0, g = 0.6, b = 0.1 }, { r = 0, g = 0.6, b = 0.1 },
	{ r = 0, g = 0.6, b = 0.1 }, { r = 0, g = 0.6, b = 0.1 },
}
local LABELS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
-- Friendship factions have no standing number of their own: shown in the
-- Friendly colour, as the reputation panel does.
local FRIEND_REACTION = 5

local GREY = "|cffcccccc"

local function number(n)
	n = math.floor((n or 0) + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

function Reputation.Color(reaction)
	local t = _G.FACTION_BAR_COLORS
	return (t and t[reaction]) or COLORS[reaction] or COLORS[4]
end

local function hex(c)
	return ("%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
		math.floor(c.b * 255 + 0.5))
end

local function standingLabel(reaction)
	return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or LABELS[reaction] or ""
end

-- The watched faction as { factionID, name, description, reaction, label,
-- min, max, value, atWar, friend, paragon = { value, threshold, reward } },
-- value counted from the standing's start, or nil when none is watched.
function Reputation:Watched()
	local w
	local api = C_Reputation
	if api and api.GetWatchedFactionData then
		local ok, d = pcall(api.GetWatchedFactionData)
		if ok and type(d) == "table" and d.name and d.name ~= "" then
			w = {
				factionID = d.factionID, name = d.name, description = d.description, reaction = d.reaction,
				min = d.currentReactionThreshold or 0, max = d.nextReactionThreshold or 0,
				value = d.currentStanding or 0, atWar = d.atWarWith,
			}
		end
	elseif GetWatchedFactionInfo then
		local name, reaction, min, max, value, factionID = GetWatchedFactionInfo()
		if name and name ~= "" then
			w = { factionID = factionID, name = name, reaction = reaction, min = min or 0, max = max or 0, value = value or 0 }
		end
	end
	if not w then
		return nil
	end
	w.reaction = tonumber(w.reaction) or 4
	w.label = standingLabel(w.reaction)

	-- A friendship faction (Forever's own factions may be): its rank's
	-- name and thresholds.
	local gossip = C_GossipInfo
	if w.factionID and gossip and gossip.GetFriendshipReputation then
		local ok, f = pcall(gossip.GetFriendshipReputation, w.factionID)
		if ok and type(f) == "table" and (f.friendshipFactionID or 0) > 0 then
			w.friend = true
			w.label = f.reaction or w.label
			w.reaction = FRIEND_REACTION
			w.value = f.standing or w.value
			w.min = f.reactionThreshold or 0
			w.max = f.nextThreshold or w.value
		end
	end

	-- Exalted with a paragon level: the paragon's progress.
	if w.factionID and api and api.IsFactionParagon and api.GetFactionParagonInfo then
		local ok, isParagon = pcall(api.IsFactionParagon, w.factionID)
		if ok and isParagon then
			local ok2, value, threshold, _, reward = pcall(api.GetFactionParagonInfo, w.factionID)
			if ok2 and value and threshold and threshold > 0 then
				w.paragon = { value = value % threshold, threshold = threshold, reward = reward }
			end
		end
	end

	-- Count from the standing's start; the top standing has nothing left.
	w.cur = math.max(0, w.value - w.min)
	w.size = math.max(0, w.max - w.min)
	w.top = w.size <= 0
	return w
end

-- Progress through the current standing, 0 to 1 (1 at the top standing).
function Reputation.Fraction(w)
	if w.paragon then
		return w.paragon.value / w.paragon.threshold
	end
	if w.top then
		return 1
	end
	return math.min(1, w.cur / w.size)
end

-- The feed's text: the faction's name in its standing's colour, and how
-- far along the standing (the standing's name at the top).
function Reputation:FeedText(w)
	w = w or self:Watched()
	if not w then
		return "No faction"
	end
	local name = ("|cff%s%s|r"):format(hex(Reputation.Color(w.reaction)), w.name)
	if w.top and not w.paragon then
		return ("%s %s"):format(name, w.label)
	end
	return ("%s %d%%"):format(name, math.floor(Reputation.Fraction(w) * 100))
end

-- Reputation gained this session, per faction: the first value seen since
-- login (or since the faction was first watched) is the baseline.
local start = {}

local function total(w)
	return w.value + (w.paragon and w.paragon.value or 0)
end

function Reputation:Tooltip(tip)
	local w = self:Watched()
	if not w then
		tip:AddLine(REPUTATION or "Reputation", 1, 1, 1)
		tip:AddLine("No faction is shown as experience bar. Tick \"Show as Experience Bar\" on a faction in the "
			.. "reputation panel.", 0.8, 0.8, 0.8, true)
		tip:AddLine("Click to open the reputation panel.", 0.8, 0.8, 0.8)
		return
	end
	local c = Reputation.Color(w.reaction)
	tip:AddLine(w.name, 1, 1, 1)
	if w.description and w.description ~= "" then
		tip:AddLine(w.description, 0.8, 0.8, 0.8, true)
	end
	tip:AddDoubleLine("Standing", w.label, 0.8, 0.8, 0.8, c.r, c.g, c.b)
	if w.paragon then
		local p = w.paragon
		tip:AddDoubleLine("Paragon", ("%s / %s (%.1f %%)"):format(number(p.value), number(p.threshold),
			p.value / p.threshold * 100), 0.8, 0.8, 0.8, 1, 1, 1)
		if p.reward then
			tip:AddLine("A paragon reward is waiting.", 0, 1, 0)
		end
	elseif w.top then
		tip:AddLine("Highest standing reached.", 0.8, 0.8, 0.8)
	else
		tip:AddDoubleLine("Progress", ("%s / %s (%.1f %%)"):format(number(w.cur), number(w.size),
			w.cur / w.size * 100), 0.8, 0.8, 0.8, 1, 1, 1)
		tip:AddDoubleLine("To next standing", number(w.size - w.cur), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	local base = w.factionID and start[w.factionID]
	if base then
		local gained = total(w) - base
		if gained ~= 0 then
			tip:AddDoubleLine("This session", (gained > 0 and "+" or "") .. number(gained), 0.8, 0.8, 0.8,
				gained > 0 and 0 or 1, gained > 0 and 1 or 0.2, 0.2)
		end
	end
	if w.atWar then
		tip:AddLine(AT_WAR or "At War", 1, 0.2, 0.2)
	end
	tip:AddLine(GREY .. "Click to open the reputation panel.|r")
end

function Reputation:Open()
	if ToggleCharacter then
		ToggleCharacter("ReputationFrame")
	end
end

function Reputation:Update()
	local w = self:Watched()
	if w and w.factionID and not start[w.factionID] then
		start[w.factionID] = total(w)
	end
	if self.feed then
		self.feed.text = self:FeedText(w)
	end
end

function Reputation:OnEnable()
	if LDB then
		self.feed = LDB:NewDataObject(FEED, {
			type = "data source", label = REPUTATION or "Reputation", text = "", icon = ICON,
			OnClick = function() Reputation:Open() end,
			OnTooltipShow = function(tip) Reputation:Tooltip(tip) end,
		})
	end
	local update = ns:Throttle(function() self:Update() end, 0.2)
	for _, e in ipairs({ "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE" }) do
		ns:On(e, update)
	end
	self:Update()
end
