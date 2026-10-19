-- Blizzard frames around the console. Frames we replace (player frame, bag
-- bar, status bars) are made invisible and click-through (the micro menu's
-- buttons live in the top bar, see TopBar.lua), bag windows open above the
-- console and the client's Issue Reporter button is lifted clear of it.
-- Everything that Edit Mode manages (buffs and debuffs, cast bar, quest
-- tracker, party frames, and the stance and pet bar frames, whose buttons
-- ActionBars.lua places) stays wherever Edit Mode puts it: moving those from
-- addon code makes Blizzard's own code fail on "secret" values, and keeps
-- the player from moving them. Where buffs and the cast bar start out is set
-- in the Edit Mode layout instead (Core.lua).

local _, ns = ...
local Blizzard = ns:RegisterModule("blizzard", {})

-- Replaced by our own hero screen, XP bar and bag row.
local CONCEAL = {
	"PlayerFrame",
	"BagsBar", "MicroButtonAndBagsBar", "MainStatusTrackingBarContainer",
	"SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
	"MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar",
}

-- True when `frame` holds one of the micro buttons the top bar shows:
-- concealing it would make them invisible too.
local function holdsMicro(frame)
	for _, b in ipairs(ns.microButtons or {}) do
		local p = b:GetParent()
		while p do
			if p == frame then
				return true
			end
			p = p:GetParent()
		end
	end
	return false
end

function Blizzard:OnEnable()
	for _, name in ipairs(CONCEAL) do
		local f = _G[name]
		if f and not ns.IsForbidden(f) and not holdsMicro(f) then
			ns:Conceal(f)
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

function Blizzard:OnLayout()
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
		ns:KeepAbove(self.reporter, function() return ns.layout.consoleTop + 6 end)
	end
end
