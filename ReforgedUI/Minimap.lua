-- The original addon's minimap: a square map in the bottom-left block, the tracking
-- button in the round slot under it, the mail slot beside it (a grey letter
-- when there is no mail), the zone name on the bottom (or top) edge of the
-- map and zooming with the mouse wheel. Blizzard's other minimap buttons
-- line up along the top edge of the map; other addons' minimap buttons are
-- gathered in a compartment whose button sits just above the map and opens
-- a flyout upwards. The day/night (or
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

-- An addon's own button (named by addon code): it may go in the drawer.
-- Blizzard's buttons are never reparented, so they stay in the row.
local function isAddonButton(f)
	local ok, name = pcall(f.GetName, f)
	if not ok or type(name) ~= "string" then
		return false
	end
	return issecurevariable ~= nil and not issecurevariable(name)
end

-- Buttons that normally sit around the round minimap, other than the ones
-- with a place of their own: Blizzard's known ones (for the row on the map),
-- and any other small button on the minimap or its cluster (other addons'
-- and client-specific ones, for the drawer), so nothing is left stranded on
-- the map. `drawer` finds buttons already moved into the drawer too.
local function collectButtons(skip, drawer)
	local row, list, seen = {}, {}, {}
	local function add(f, into)
		if f and not seen[f] and not skip[f] and not ns.IsForbidden(f) then
			seen[f] = true
			into = into or list
			into[#into + 1] = f
		end
	end
	add(AddonCompartmentFrame, row)
	add(find(ExpansionLandingPageMinimapButton, GarrisonLandingPageMinimapButton), row)
	local function sweep(parent, depth)
		if not parent or not parent.GetChildren then
			return
		end
		for _, child in ipairs({ parent:GetChildren() }) do
			if not skip[child] and not ns.IsForbidden(child) then
				local w, h = child:GetSize()
				if child:GetObjectType() == "Button" and child:IsShown() and w and w >= 12 and w <= 64
					and h and h >= 12 and h <= 64 then
					add(child, not isAddonButton(child) and row or nil)
				elseif depth > 0 and child ~= Minimap then
					sweep(child, depth - 1)
				end
			end
		end
	end
	sweep(MinimapCluster, 2)
	sweep(Minimap, 0)
	if drawer then
		for _, child in ipairs({ drawer:GetChildren() }) do
			if child ~= drawer.bg then
				add(child)
			end
		end
	end
	return row, list
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
	self.skip = skip
	self:CreateCompartment()
	self.buttons, self.addonButtons = collectButtons(skip)
end

----------------------------------------------------------------------------
-- The addon compartment: a button beside the map that opens a flyout of the
-- other addons' minimap buttons.

local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local FLYOUT_ROWS = 8

function MinimapModule:CreateCompartment()
	local toggle = CreateFrame("Button", "ReforgedUIAddonCompartment", self.holder)
	toggle:SetFrameLevel(self.holder:GetFrameLevel() + 5)
	toggle:SetSize(32, 32)
	local icon = toggle:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(BAG_ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	toggle:SetScript("OnClick", function() self:ToggleDrawer() end)
	toggle:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Addon buttons", 1, 1, 1)
		GameTooltip:AddLine(("%d minimap buttons. Click to %s."):format(#(self.addonButtons or {}),
			self.drawer:IsShown() and "close" or "open"), 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.toggle = toggle

	local drawer = CreateFrame("Frame", "ReforgedUIAddonDrawer", self.holder)
	-- Over the game world and the console, like a menu.
	drawer:SetFrameStrata("MEDIUM")
	drawer:SetFrameLevel(50)
	-- The background is a frame a strata below the buttons, so it stays under
	-- them whatever level their addon pins them at.
	drawer.bg = CreateFrame("Frame", nil, drawer)
	drawer.bg:SetFrameStrata("LOW")
	drawer.bg:SetFrameLevel(100)
	drawer.bg:SetAllPoints()
	local shade = drawer.bg:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.75)
	drawer:SetShown(ns.db.consoleOpts.addonDrawerOpen and true or false)
	self.drawer = drawer
end

function MinimapModule:ToggleDrawer()
	local open = not self.drawer:IsShown()
	ns.db.consoleOpts.addonDrawerOpen = open
	if open then
		-- Pick up buttons that addons made since the last look.
		self.buttons, self.addonButtons = collectButtons(self.skip, self.drawer)
		if self.layout then
			self:OnLayout(self.layout)
		end
	end
	self.drawer:SetShown(open)
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

-- Puts a drawer button above the flyout's background, whatever the addon
-- set. LibDBIcon pins its buttons at MEDIUM, level 8 with fixed strata and
-- level, which the client keeps through SetFrameStrata/SetFrameLevel; unpin,
-- move, and pin again at the new place.
local function raise(btn, drawer)
	local fixedStrata = btn.SetFixedFrameStrata and (not btn.IsFixedFrameStrata or btn:IsFixedFrameStrata())
	local fixedLevel = btn.SetFixedFrameLevel and (not btn.IsFixedFrameLevel or btn:IsFixedFrameLevel())
	if fixedStrata then
		btn:SetFixedFrameStrata(false)
	end
	if fixedLevel then
		btn:SetFixedFrameLevel(false)
	end
	btn:SetFrameStrata(drawer:GetFrameStrata())
	btn:SetFrameLevel(drawer:GetFrameLevel() + 2)
	if fixedStrata then
		btn:SetFixedFrameStrata(true)
	end
	if fixedLevel then
		btn:SetFixedFrameLevel(true)
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

	-- Blizzard's other buttons in a row along the top edge of the map,
	-- shrinking to fit them all.
	self.layout = L
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

	-- The compartment: a button beside the map, and a flyout of the addon
	-- buttons opening upwards from it, in columns of FLYOUT_ROWS that grow
	-- to the left (towards the screen's edge, away from the console).
	local c = L.addonCompartment
	local count = #self.addonButtons
	self.toggle:SetShown(count > 0)
	ns:PlaceRect(self.toggle, c)
	size = c.w
	local cols = math.max(1, math.ceil(count / FLYOUT_ROWS))
	local rows = math.min(math.max(count, 1), FLYOUT_ROWS)
	local step = size + 2
	local bottom = c.y + c.h + 2
	ns:PlaceRect(self.drawer, { x = c.x + c.w + 2 - cols * step - 2, y = bottom, w = cols * step + 2,
		h = rows * step + 2 })
	for i, btn in ipairs(self.addonButtons) do
		local col, line = math.floor((i - 1) / FLYOUT_ROWS), (i - 1) % FLYOUT_ROWS
		local x, y = c.x - col * step, bottom + 2 + line * step
		if btn:GetParent() ~= self.drawer then
			btn:SetParent(self.drawer)
		end
		raise(btn, self.drawer)
		ns:Lock(btn, function(b)
			fit(b, size)
			ns:Anchor(b, "BOTTOMLEFT", x, y)
		end, { "SetScale" })
	end
end

function MinimapModule:OnTheme()
	self:UpdateZone()
end
