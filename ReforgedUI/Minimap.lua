-- The original addon's minimap: a square map in the bottom-left block, the tracking
-- button in the round slot under it, the mail slot beside it (a grey letter
-- when there is no mail), the zone name on the bottom (or top) edge of the
-- map and zooming with the mouse wheel. The other minimap buttons (addon
-- buttons, ...) line up along the top edge of the map. The day/night (or
-- calendar) indicator is made invisible: the top bar has its own clock.
--
-- The map stays a child of its cluster (an Edit Mode frame we never move or
-- hide); only the map itself and the buttons are placed, anchored to
-- UIParent, and the cluster's own decorations are made invisible.

local _, ns = ...
local MinimapModule = ns:RegisterModule("minimap", {})

-- Tell other addons (LibDBIcon and friends) the minimap is square.
function GetMinimapShape()
	return "SQUARE"
end

-- The original addon's MinimapMask is plain white: a square mask.
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

-- Calls fn(f) for each non-nil argument (lists of frames that may not exist
-- on this client).
local function each(fn, ...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if f then
			fn(f)
		end
	end
end

local function find(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if f then
			return f
		end
	end
end

-- Buttons that normally sit around the round minimap, other than the ones
-- with a place of their own: the known ones first, then any other small
-- button on the minimap or its cluster (other addons' and client-specific
-- ones), so nothing is left stranded on the map.
local function collectButtons(skip)
	local list, seen = {}, {}
	local function add(f)
		if f and not seen[f] and not skip[f] and not ns.IsForbidden(f) then
			seen[f] = true
			list[#list + 1] = f
		end
	end
	add(AddonCompartmentFrame)
	add(find(ExpansionLandingPageMinimapButton, GarrisonLandingPageMinimapButton))
	local function sweep(parent, depth)
		if not parent or not parent.GetChildren then
			return
		end
		for _, child in ipairs({ parent:GetChildren() }) do
			if not skip[child] and not ns.IsForbidden(child) then
				local w, h = child:GetSize()
				if child:GetObjectType() == "Button" and child:IsShown() and w and w >= 12 and w <= 64
					and h and h >= 12 and h <= 64 then
					add(child)
				elseif depth > 0 and child ~= Minimap then
					sweep(child, depth - 1)
				end
			end
		end
	end
	sweep(MinimapCluster, 2)
	sweep(Minimap, 0)
	return list
end

function MinimapModule:OnEnable()
	local map = Minimap
	map:SetMaskTexture(SQUARE_MASK)
	if map.SetArchBlobRingScalar then
		map:SetArchBlobRingScalar(0)
		map:SetQuestBlobRingScalar(0)
	end

	local cluster = MinimapCluster or {}
	-- Round decorations and the cluster's header (zone bar, border, zoom
	-- buttons) that the original addon drops.
	each(function(f)
		if f.GetChildren then
			ns:Conceal(f)
		elseif f.SetAlpha then
			f:SetAlpha(0)
		end
	end, MinimapCompassTexture, MinimapBorder, MinimapBorderTop, MinimapBackdrop,
		map.ZoomIn, map.ZoomOut, map.ZoomHitArea, MinimapZoomIn, MinimapZoomOut,
		cluster.BorderTop, cluster.ZoneTextButton, MinimapZoneTextButton, MiniMapWorldMapButton,
		TimeManagerClockButton, MiniMapMailBorder)
	self.timeFrames = self:FindTimeFrames()
	for _, f in ipairs(self.timeFrames) do
		ns:Conceal(f)
	end

	-- Mouse wheel zoom (newer clients zoom by themselves).
	map:EnableMouseWheel(true)
	if not map:GetScript("OnMouseWheel") then
		map:SetScript("OnMouseWheel", function(m, delta)
			local zoom = m:GetZoom() + (delta > 0 and 1 or -1)
			if zoom >= 0 and zoom < m:GetZoomLevels() then
				m:SetZoom(zoom)
			end
		end)
	end

	self.holder = CreateFrame("Frame", "ReforgedUIMinimap", ns.root)
	self.holder:SetFrameStrata("LOW")
	self.holder:SetFrameLevel(20)
	self.holder:SetAllPoints(ns.root)

	-- The empty mail slot: a grey letter, covered when mail arrives.
	self.noMail = self.holder:CreateTexture(nil, "ARTWORK")
	self.noMail:SetTexture("Interface\\Icons\\INV_Letter_15")
	self.noMail:SetVertexColor(0.25, 0.25, 0.25, 1)
	self.noMail:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	ns:On("UPDATE_PENDING_MAIL", function() self:UpdateMail() end)
	ns:On("PLAYER_ENTERING_WORLD", function() self:UpdateMail() end)

	-- Zone name, coloured by PvP status like Blizzard's.
	self.zone = self.holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.zone:SetJustifyH("CENTER")
	self.zone:SetWordWrap(false)
	for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns:On(e, function() self:UpdateZone() end)
	end
	self:UpdateZone()

	self.tracking = find(cluster.Tracking, cluster.TrackingFrame, MiniMapTracking, MiniMapTrackingFrame,
		MiniMapTrackingButton)
	self.mail = find(cluster.IndicatorFrame, MiniMapMailFrame)
	self.difficulty = find(cluster.InstanceDifficulty, cluster.InstanceDifficultyFrame, MiniMapInstanceDifficulty)
	local skip = {}
	each(function(f) skip[f] = true end, self.tracking, self.mail, self.difficulty, cluster.ZoneTextButton,
		cluster.BorderTop, MinimapZoneTextButton, MiniMapWorldMapButton, TimeManagerClockButton)
	for _, f in ipairs(self.timeFrames) do
		skip[f] = true
	end
	self.buttons = collectButtons(skip)
end

-- The minimap cluster's day/night indicator (Forever's DielFrame, or
-- GameTimeFrame elsewhere: a moon or sun in the screen's top-right corner), by name or by one careful look through
-- the cluster's and UIParent's children.
local TIME_NAMES = { "GameTime", "DayNight", "TimeOfDay", "Diel" }

function MinimapModule:FindTimeFrames()
	local list, seen = {}, {}
	local function add(f)
		if f and not seen[f] and not ns.IsForbidden(f) then
			seen[f] = true
			list[#list + 1] = f
		end
	end
	add(_G.GameTimeFrame)
	local cluster = MinimapCluster
	if cluster then
		add(cluster.DielFrame)
		add(cluster.GameTimeFrame)
		add(cluster.GameTime)
	end
	for _, parent in ipairs({ cluster, UIParent }) do
		for _, f in ipairs({ parent and parent:GetChildren() }) do
			if not ns.IsForbidden(f) then
				local ok, name = pcall(f.GetName, f)
				if ok and type(name) == "string" then
					for _, pattern in ipairs(TIME_NAMES) do
						if name:find(pattern) then
							add(f)
						end
					end
				end
			end
		end
	end
	return list
end

function MinimapModule:UpdateMail()
	self.noMail:SetShown(not HasNewMail())
end

function MinimapModule:UpdateZone()
	local text = GetMinimapZoneText and GetMinimapZoneText() or ""
	local r, g, b = 1, 0.82, 0
	local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo() or (GetZonePVPInfo and GetZonePVPInfo())
	if pvp == "sanctuary" then
		r, g, b = 0.41, 0.8, 0.94
	elseif pvp == "arena" or pvp == "hostile" then
		r, g, b = 1, 0.1, 0.1
	elseif pvp == "friendly" then
		r, g, b = 0.1, 1, 0.1
	elseif pvp == "contested" then
		r, g, b = 1, 0.7, 0
	end
	self.zone:SetText(text)
	self.zone:SetTextColor(r, g, b)
end

-- Scale `f` so its larger side is `size` console units.
local function fit(f, size)
	local w, h = f:GetSize()
	local natural = math.max(w or 0, h or 0)
	if natural > 0 then
		local parentScale = f:GetParent() and f:GetParent():GetEffectiveScale() or 1
		f:SetScale(size * ns.root:GetEffectiveScale() / (natural * parentScale))
	end
end

function MinimapModule:OnLayout(L)
	local m = L.minimap
	ns:Lock(Minimap, function(map)
		ns:PlaceRect(map, m)
	end, { "SetSize" })
	-- Changing the size needs a zoom nudge or the map renders stale tiles.
	local zoom = Minimap:GetZoom()
	Minimap:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
	Minimap:SetZoom(zoom)

	ns.modules.console.Place(self.noMail, L.noMail)
	self:UpdateMail()

	local z = L.zoneText
	self.zone:SetShown(z ~= nil)
	if z then
		ns.modules.console.Place(self.zone, z)
	end

	local t = L.tracking
	if self.tracking then
		ns:Lock(self.tracking, function(f)
			fit(f, t.size)
			ns:Anchor(f, "CENTER", t.cx, t.cy)
		end, { "SetScale" })
	end
	local nm = L.noMail
	if self.mail then
		ns:Lock(self.mail, function(f)
			fit(f, nm.w)
			ns:Anchor(f, "CENTER", nm.x + nm.w / 2, nm.y + nm.h / 2)
		end, { "SetScale" })
	end
	if self.difficulty then
		ns:Lock(self.difficulty, function(f)
			ns:Anchor(f, "TOPLEFT", m.x + 2, m.y + m.h - 2)
		end)
	end

	-- The other buttons in a row along the top edge of the map, shrinking
	-- to fit them all.
	local row = L.minimapButtons
	local n = #self.buttons
	local size = math.min(row.size, (row.maxW - (n - 1) * 2) / math.max(n, 1))
	for i, btn in ipairs(self.buttons) do
		local x = row.x + (i - 1) * (size + 2)
		ns:Lock(btn, function(b)
			fit(b, size)
			ns:Anchor(b, "TOPLEFT", x, row.y)
		end, { "SetScale" })
	end
end

function MinimapModule:OnTheme()
	self:UpdateZone()
end
