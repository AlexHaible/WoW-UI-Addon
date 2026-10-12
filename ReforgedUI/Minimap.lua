-- Square minimap in the console's left block, with the minimap buttons stacked
-- in a column beside it the way Warcraft III lines up its minimap signals.

local _, ns = ...
local MinimapModule = ns:RegisterModule("minimap", {})

-- Tell other addons (LibDBIcon and friends) the minimap is square.
function GetMinimapShape()
	return "SQUARE"
end

local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

local function find(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if f then
			return f
		end
	end
end

-- Buttons that normally sit around the round minimap: the known ones first,
-- then any other small button on the minimap or its cluster (other addons'
-- and client-specific ones), so nothing is left stranded on the map.
local function collectButtons(skip)
	local cluster = MinimapCluster or {}
	local list, seen = {}, {}
	local function add(f)
		if f and not seen[f] and not skip[f] then
			seen[f] = true
			list[#list + 1] = f
		end
	end
	add(find(cluster.Tracking, cluster.TrackingFrame, MiniMapTracking, MiniMapTrackingButton))
	add(GameTimeFrame)
	add(find(cluster.IndicatorFrame, MiniMapMailFrame))
	add(AddonCompartmentFrame)
	add(find(ExpansionLandingPageMinimapButton, GarrisonLandingPageMinimapButton))
	local function sweep(parent, depth)
		if not parent or not parent.GetChildren then
			return
		end
		for _, child in ipairs({ parent:GetChildren() }) do
			local w, h = child:GetSize()
			if child:GetObjectType() == "Button" and child:IsShown() and w and w >= 12 and w <= 64
				and h and h >= 12 and h <= 64 then
				add(child)
			elseif depth > 0 and child ~= Minimap then
				sweep(child, depth - 1)
			end
		end
	end
	sweep(MinimapCluster, 2)
	sweep(Minimap, 0)
	return list
end

function MinimapModule:OnEnable()
	local Minimap = Minimap
	self.holder = CreateFrame("Frame", "ReforgedUIMinimapHolder", ns.root)
	self.holder:SetFrameStrata("LOW")

	Minimap:SetParent(self.holder)
	Minimap:SetFrameStrata("LOW")
	Minimap:SetMaskTexture(SQUARE_MASK)
	if Minimap.SetArchBlobRingScalar then
		Minimap:SetArchBlobRingScalar(0)
		Minimap:SetQuestBlobRingScalar(0)
	end

	-- Round decorations that make no sense on a square map.
	for _, f in ipairs({
		MinimapCompassTexture, MinimapBorder, MinimapBorderTop, MinimapBackdrop and MinimapBackdrop.StaticOverlay,
		Minimap.ZoomIn, Minimap.ZoomOut, MinimapZoomIn, MinimapZoomOut,
		MinimapCluster and MinimapCluster.BorderTop, MinimapCluster and MinimapCluster.ZoneTextButton,
		MinimapZoneTextButton, MiniMapWorldMapButton,
	}) do
		if f then
			if f.SetParent then
				ns:Conceal(f)
			else
				f:Hide()
			end
		end
	end

	-- Mouse wheel zoom (the zoom buttons are gone).
	Minimap:EnableMouseWheel(true)
	if not Minimap:GetScript("OnMouseWheel") then
		Minimap:SetScript("OnMouseWheel", function(map, delta)
			local zoom = map:GetZoom() + (delta > 0 and 1 or -1)
			if zoom >= 0 and zoom < map:GetZoomLevels() then
				map:SetZoom(zoom)
			end
		end)
	end

	-- Zone name on the plate above the map, Warcraft III gold.
	self.zone = self.holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.zone:SetJustifyH("CENTER")
	self.zone:SetWordWrap(false)
	ns:On("ZONE_CHANGED", function() self:UpdateZone() end)
	ns:On("ZONE_CHANGED_INDOORS", function() self:UpdateZone() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() self:UpdateZone() end)
	ns:On("PLAYER_ENTERING_WORLD", function() self:UpdateZone() end)
	self:UpdateZone()

	self.extras = {
		clock = TimeManagerClockButton,
		difficulty = MinimapCluster and (MinimapCluster.InstanceDifficulty or MinimapCluster.InstanceDifficultyFrame)
			or MiniMapInstanceDifficulty,
	}
	local skip = {}
	for _, f in pairs(self.extras) do skip[f] = true end
	self.buttons = collectButtons(skip)
	-- Everything worth keeping is out of the cluster now; hide the rest of it
	-- (zone bar, border, header) wherever the client anchors it.
	if MinimapCluster then
		for _, f in pairs(self.extras) do
			if f then f:SetParent(self.holder) end
		end
		for _, b in ipairs(self.buttons) do
			b:SetParent(self.holder)
		end
		ns:Conceal(MinimapCluster)
	end
end

function MinimapModule:UpdateZone()
	local text = GetMinimapZoneText and GetMinimapZoneText() or ""
	local r, g, b = 1, 0.82, 0
	local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo() or (GetZonePVPInfo and GetZonePVPInfo())
	if pvp == "sanctuary" then
		r, g, b = 0.41, 0.8, 0.94
	elseif pvp == "hostile" then
		r, g, b = 1, 0.1, 0.1
	elseif pvp == "contested" then
		r, g, b = 1, 0.7, 0
	end
	self.zone:SetText(text)
	self.zone:SetTextColor(r, g, b)
end

function MinimapModule:OnLayout(L)
	local root, m = ns.root, L.minimap
	ns:Lock(Minimap, function(map)
		map:ClearAllPoints()
		ns:PlaceRect(map, m)
	end)
	-- Changing the size needs a zoom nudge or the map renders stale tiles.
	local zoom = Minimap:GetZoom()
	Minimap:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
	Minimap:SetZoom(zoom)

	local z = L.zoneText
	self.zone:ClearAllPoints()
	self.zone:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", z.x, z.y)
	self.zone:SetSize(z.w, z.h)

	-- Column of minimap buttons, top to bottom; shrinks to fit them all.
	local col = L.minimapButtons
	local n = #self.buttons
	local slot = math.min(col.w, (col.h - (n - 1) * 4) / math.max(n, 1))
	local y = col.y + col.h
	for _, btn in ipairs(self.buttons) do
		local top = y
		ns:Lock(btn, function(b)
			-- The holder shares the console's scale, so a scale of slot/size
			-- makes the button exactly one slot tall in console units.
			b:SetParent(self.holder)
			local w, h = b:GetSize()
			local size = math.max(w or 0, h or 0)
			b:SetScale(size > 0 and slot / size or 1)
			ns:Anchor(b, "TOP", col.x + slot / 2, top)
		end)
		y = y - slot - 4
	end

	local clock = self.extras.clock
	if clock then
		ns:Lock(clock, function(b)
			b:SetParent(self.holder)
			ns:Anchor(b, "BOTTOM", m.x + m.w / 2, m.y + 2)
		end)
	end
	local diff = self.extras.difficulty
	if diff then
		ns:Lock(diff, function(b)
			b:SetParent(self.holder)
			ns:Anchor(b, "TOPLEFT", m.x + 2, m.y + m.h - 2)
		end)
	end
end

function MinimapModule:OnTheme()
	self:UpdateZone()
end
