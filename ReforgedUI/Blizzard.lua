-- Blizzard frames around the console. Frames we replace (player frame, bag
-- bar, status bars) are made invisible and click-through; the micro menu
-- moves on top of the action grid (or is hidden, the original addon's default), bag
-- windows open above the console and the client's Issue Reporter button is
-- lifted clear of it. Buffs and debuffs are held just below the top bar, the
-- way the chat window is held in the chat area. Everything else that
-- Edit Mode manages (cast bar, quest tracker, party frames, and the
-- stance and pet bar frames, whose buttons ActionBars.lua places) stays
-- wherever Edit Mode puts it: moving those from addon code makes Blizzard's
-- own code fail on "secret" values.

local _, ns = ...
local Blizzard = ns:RegisterModule("blizzard", {})

local function first(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if _G[name] then
			return _G[name]
		end
	end
end

-- Replaced by our own hero screen, XP bar and bag row.
local CONCEAL = {
	"PlayerFrame",
	"BagsBar", "MicroButtonAndBagsBar", "MainStatusTrackingBarContainer",
	"SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
	"MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar",
}

local MICRO_NAMES = {
	"CharacterMicroButton", "SpellbookMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
	"TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
	"GuildMicroButton", "LFGMicroButton", "LFDMicroButton", "WorldMapMicroButton", "CollectionsMicroButton",
	"EJMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

function Blizzard:OnEnable()
	for _, name in ipairs(CONCEAL) do
		ns:Conceal(_G[name])
	end

	self.micro = first("MicroMenuContainer", "MicroMenu")
	if ns.db.consoleOpts.hideMicro then
		-- The top bar's buttons open the game menu, and every window has
		-- its key binding.
		if self.micro then
			ns:Conceal(self.micro)
		else
			for _, name in ipairs(MICRO_NAMES) do
				ns:Conceal(_G[name])
			end
		end
		self.micro = nil
	elseif not self.micro then
		-- Classic-style clients: micro buttons are loose children of the main
		-- bar, so line them up one by one. The game menu button sits over the
		-- top bar's Menu button instead.
		self.microButtons = {}
		for _, name in ipairs(MICRO_NAMES) do
			if _G[name] and name ~= "MainMenuMicroButton" then
				self.microButtons[#self.microButtons + 1] = _G[name]
			end
		end
	end

	-- Bag windows open above the console instead of over it.
	local hookName = (UpdateContainerFrameAnchors and "UpdateContainerFrameAnchors")
		or (updateContainerFrameAnchors and "updateContainerFrameAnchors")
	if hookName then
		hooksecurefunc(hookName, function() self:LiftContainers() end)
	end
end

function Blizzard:LiftContainers()
	local frames = {}
	if ContainerFrameCombinedBags then
		frames[#frames + 1] = ContainerFrameCombinedBags
	end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		frames[#frames + 1] = _G["ContainerFrame" .. i]
	end
	-- Only the bottom of each column is anchored to UIParent; the rest stack
	-- on top of it, so lifting those lifts everything.
	local lift = ns.layout and ns.layout.consoleTop or 0
	for _, f in ipairs(frames) do
		if f:IsShown() then
			local point, rel, relPoint, x, y = f:GetPoint(1)
			if rel == UIParent and point and point:find("BOTTOM") then
				local need = lift * ns.root:GetEffectiveScale() / f:GetEffectiveScale()
				local bottom = f:GetBottom()
				if bottom and bottom < need then
					f:SetPoint(point, rel, relPoint, x, y + need - bottom)
				end
			end
		end
	end
end

function Blizzard:OnLayout(L)
	if self.micro then
		ns:Lock(self.micro, function(f)
			-- Shrink (never grow) until the menu fits on the action grid.
			local w = f:GetWidth() * f:GetEffectiveScale() / ns.root:GetEffectiveScale()
			if w > L.micro.maxW then
				f:SetScale(f:GetScale() * L.micro.maxW / w)
			end
			ns:Anchor(f, "BOTTOMRIGHT", L.micro.right, L.micro.bottom)
		end)
	elseif self.microButtons then
		self:LayoutMicroRow(L)
	end

	self:LiftIssueReporter()
	self:PlaceBuffs()
end

-- Buffs and debuffs hang in the top-right corner, just below the top bar,
-- held there the way the chat window is; debuffs keep their own place under
-- the buffs.
local BUFF_GAP, BUFF_RIGHT = 6, 12

function Blizzard:PlaceBuffs()
	local buffs = _G.BuffFrame
	if not buffs or ns.IsForbidden(buffs) or not (ns.topRoot and ns.topLayout) then
		return
	end
	ns:Lock(buffs, function(f)
		local s = ns.topRoot:GetEffectiveScale() / f:GetEffectiveScale()
		f:ClearAllPoints()
		f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -BUFF_RIGHT * s, -(ns.topLayout.topBar.h + BUFF_GAP) * s)
	end)
	local debuffs = _G.DebuffFrame
	if debuffs and not ns.IsForbidden(debuffs) then
		ns:Lock(debuffs, function(f)
			f:ClearAllPoints()
			f:SetPoint("TOPRIGHT", buffs, "BOTTOMRIGHT", 0, -BUFF_GAP)
		end)
	end
end

-- WoW: Forever parks its Issue Reporter button at the bottom of the screen;
-- lift it on top of the console. Found by name, or by one careful look
-- through UIParent's children (some of which are forbidden to addons).
function Blizzard:LiftIssueReporter()
	if self.reporter == nil then
		local found = _G.PTR_IssueReporter or _G.IssueReporterButton
		if not found then
			for _, f in ipairs({ UIParent:GetChildren() }) do
				if not ns.IsForbidden(f) then
					local ok, name = pcall(f.GetName, f)
					if ok and type(name) == "string" and name:find("IssueReport") then
						found = f
						break
					end
				end
			end
		end
		self.reporter = found or false
	end
	if self.reporter then
		ns:KeepAbove(self.reporter, function() return ns.layout.consoleTop + 6 end)
	end
end

-- Width of `b` in console units at scale 1.
local function naturalWidth(b)
	return b:GetWidth() * b:GetParent():GetEffectiveScale() / ns.root:GetEffectiveScale()
end

function Blizzard:LayoutMicroRow(L)
	local buttons = self.microButtons
	if #buttons == 0 then
		return
	end
	local step = math.min(naturalWidth(buttons[1]), L.micro.maxW / #buttons)
	local x0 = L.micro.right - #buttons * step
	for i, btn in ipairs(buttons) do
		ns:Lock(btn, function(b)
			b:SetScale(step / naturalWidth(b))
			ns:Anchor(b, "BOTTOMLEFT", x0 + (i - 1) * step, L.micro.bottom)
		end)
	end
end
