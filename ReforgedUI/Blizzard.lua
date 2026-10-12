-- Blizzard frames around the console. Frames we replace (bag bar, status
-- bars) are made invisible and click-through; the
-- micro menu moves on top of the console, bag windows open above it and the
-- client's Issue Reporter button is lifted clear of it. Everything else that
-- Edit Mode manages (cast bar, stance and pet bars, buffs, quest tracker,
-- party frames) stays wherever Edit Mode puts it: moving those from addon
-- code makes Blizzard's own code fail on "secret" values.

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
local CONCEAL = {
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
			ns:Anchor(f, "BOTTOMRIGHT", L.micro.right, L.micro.bottom)
		end)
	elseif self.microRow then
		self:LayoutMicroRow(L)
	end

	self:LiftIssueReporter()
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
		ns:KeepAbove(self.reporter, function() return ns.layout.base.h + 6 end)
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
	row:SetPoint("BOTTOMRIGHT", ns.root, "BOTTOMLEFT", L.micro.right / scale, L.micro.bottom / scale) -- our own frame
	for i, btn in ipairs(buttons) do
		ns:Lock(btn, function(b)
			b:SetParent(row)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", (i - 1) * bw, 0)
		end)
	end
end
