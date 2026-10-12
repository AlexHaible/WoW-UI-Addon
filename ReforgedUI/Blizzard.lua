-- Blizzard frames we keep but move around the console: micro menu, stance,
-- pet and possess bars, cast bar, extra action button, vehicle bar, quest
-- tracker and bag windows. Frame names differ between Retail and
-- Classic-based clients, so every lookup tries both.

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

-- Replaced by our own XP bar and inventory.
local KILL = {
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

-- Place `frame` so its `point` sits at console coordinates (x, y).
local function anchor(frame, point, x, y)
	local u = ns:UnitsFor(frame)
	frame:ClearAllPoints()
	frame:SetPoint(point, ns.root, "BOTTOMLEFT", x * u, y * u)
end

function Blizzard:OnEnable()
	for _, name in ipairs(KILL) do
		-- Bag buttons and micro buttons may live inside these on Classic
		-- clients; the micro buttons are rescued below.
		if _G[name] then
			ns:Kill(_G[name])
		end
	end

	self.micro = first("MicroMenuContainer", "MicroMenu")
	if not self.micro then
		-- Classic-style clients: micro buttons are loose children of the main
		-- bar, so gather them into a row of our own.
		self.microRow = CreateFrame("Frame", "ReforgedUIMicroMenu", ns.root)
		self.microRow:SetFrameStrata("MEDIUM")
		self.microButtons = {}
		for _, name in ipairs(MICRO_NAMES) do
			if _G[name] then
				self.microButtons[#self.microButtons + 1] = _G[name]
			end
		end
	end

	self.stance = first("StanceBar", "StanceBarFrame")
	self.pet = first("PetActionBar", "PetActionBarFrame")
	self.possess = first("PossessActionBar", "PossessBarFrame")
	self.castBar = first("PlayerCastingBarFrame", "CastingBarFrame")
	self.extra = first("ExtraAbilityContainer", "ExtraActionBarFrame")
	self.override = first("OverrideActionBar")
	self.tracker = first("ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame")

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
	local lift = ns.layout and (ns.layout.micro.bottom + 44) or 0
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
			-- Shrink (never grow) until the menu fits above the command card.
			local w = f:GetWidth() * f:GetEffectiveScale() / ns.root:GetEffectiveScale()
			if w > L.micro.maxW then
				f:SetScale(f:GetScale() * L.micro.maxW / w)
			end
			anchor(f, "BOTTOMRIGHT", L.micro.right, L.micro.bottom)
		end)
	elseif self.microRow then
		self:LayoutMicroRow(L)
	end

	if self.stance then
		ns:Lock(self.stance, function(f) anchor(f, "BOTTOMLEFT", L.stance.x, L.stance.y) end)
	end
	if self.possess then
		ns:Lock(self.possess, function(f) anchor(f, "BOTTOMLEFT", L.stance.x, L.stance.y) end)
	end
	if self.pet then
		ns:Lock(self.pet, function(f) anchor(f, "BOTTOMRIGHT", L.pet.right, L.pet.y) end)
	end
	if self.castBar then
		ns:Lock(self.castBar, function(f) anchor(f, "BOTTOM", L.castBar.cx, L.castBar.y) end)
	end
	if self.extra then
		ns:Lock(self.extra, function(f) anchor(f, "BOTTOM", L.extra.cx, L.extra.y) end)
	end
	if self.override then
		ns:Lock(self.override, function(f) anchor(f, "BOTTOM", L.override.cx, L.override.y) end)
	end
	-- Client-specific buttons parked at the bottom of the screen (WoW: Forever's
	-- Issue Reporter) are lifted to sit on top of the console.
	for _, f in ipairs({ UIParent:GetChildren() }) do
		local name = f:GetName()
		if name and name:find("IssueReport") then
			ns:KeepAbove(f, function() return ns.layout.base.h + 6 end)
		end
	end
	if self.tracker then
		ns:Lock(self.tracker, function(f)
			local h = f:GetHeight()
			anchor(f, "TOPRIGHT", L.tracker.right, L.tracker.top)
			if h and h > 0 then
				f:SetHeight(h)
			end
		end)
	end
end

function Blizzard:LayoutMicroRow(L)
	local row, buttons = self.microRow, self.microButtons
	if #buttons == 0 then
		return
	end
	local bw, bh = buttons[1]:GetSize()
	local natural = #buttons * bw
	local scale = math.min(1, L.micro.maxW / natural)
	row:SetScale(scale)
	row:SetSize(natural, bh)
	row:ClearAllPoints()
	row:SetPoint("BOTTOMRIGHT", ns.root, "BOTTOMLEFT", L.micro.right / scale, L.micro.bottom / scale)
	for i, btn in ipairs(buttons) do
		ns:Lock(btn, function(b)
			b:SetParent(row)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", (i - 1) * bw, 0)
		end)
	end
end
