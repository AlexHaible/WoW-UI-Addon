-- Pure layout math for the Reforged console. No WoW API calls in this file so
-- it can also run under plain Lua (tools/dump_layout.lua uses it to render the
-- preview mockups). All values are in console units: UIParent units divided by
-- the console scale, origin at the bottom-left of the screen.
--
-- Left to right the console holds: chat, minimap, the player's portrait, the
-- hero screen (name, level/experience and four stat icons), action bars 1-3,
-- the 2x3 inventory with the key ring, and the target panel. Action bars 1-3
-- sit in the middle of the screen whenever there is room for that.

local _, ns = ...
ns = ns or {}

local floor, max, min = math.floor, math.max, math.min

local Layout = {}
ns.Layout = Layout

-- The core aspect decides where the top bar's menu buttons and default data
-- feeds go; bars 4 and 5 move into free console space on wide screens.
Layout.PROFILES = {
	standard = { label = "16:9", coreAspect = 16 / 9 },
	wide = { label = "21:9", coreAspect = 21 / 9 },
	superwide = { label = "32:9", coreAspect = 21 / 9 },
}
Layout.PROFILE_ORDER = { "standard", "wide", "superwide" }

local S = {
	edge = 16, -- trim thickness drawn on every panel
	pad = 18, -- distance from a panel's outer edge to its content
	tall = 212, -- chat and minimap blocks
	mid = 176, -- target block
	low = 150, -- the base band that spans the whole screen
	sec = 288, -- a 512px console section is drawn 288 units square
	secTop = 158, -- top of the portrait and inventory sections' walls
	chatMax = 520, chatMin = 300,
	statIcon = 30,
	barBtn = 36, barBtnMin = 22, barGap = 3, barRowGap = 4,
	targetW = 250,
	sideBtn = 36, sideGap = 3,
	crest = 104,
	topH = 40, topBtnW = 84, slotW = 120, slotGap = 8,
	dialR = 52, clockW = 176, clockH = 88,
}
Layout.SIZES = S

function Layout.DetectProfile(w, h)
	local aspect = w / h
	if aspect < 2.0 then
		return "standard"
	elseif aspect < 2.75 then
		return "wide"
	end
	return "superwide"
end

local function rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

local function grid(x, y, cols, rows, size, gap, rowGap)
	rowGap = rowGap or gap
	return {
		x = x, y = y, cols = cols, rows = rows, size = size, gap = gap, rowGap = rowGap,
		w = cols * size + (cols - 1) * gap,
		h = rows * size + (rows - 1) * rowGap,
	}
end

-- Returns the position of button `index` (1-based, row-major from the top-left)
-- inside a grid as bottom-left coordinates.
function Layout.GridCell(g, index)
	local col = (index - 1) % g.cols
	local row = floor((index - 1) / g.cols)
	local x = g.x + col * (g.size + g.gap)
	local y = g.y + g.h - g.size - row * (g.size + (g.rowGap or g.gap))
	return x, y
end

local function clamp(v, lo, hi)
	return max(lo, min(hi, v))
end

function Layout.Compute(W, H, profileKey)
	if not Layout.PROFILES[profileKey] then
		profileKey = Layout.DetectProfile(W, H)
	end
	local P = Layout.PROFILES[profileKey]
	local L = {
		profile = profileKey, W = W, H = H,
		panels = {}, -- raised, trimmed blocks: { key, x, y, w, h }
		insets = {}, -- dark recessed "screens" drawn on top of panels
		bars = {},
	}
	L.base = rect(0, 0, W, S.low)

	-- The original addon's sections (Media/<Faction>/sections): minimap + portrait form
	-- one 576-unit strip (minimap, button column, portrait arch, hero screen);
	-- the inventory section's bag grid and pillar are its left 208 pixels.
	local k = S.sec / 512 -- units per section texture pixel
	local stripW = 2 * S.sec
	local invW = floor(208 * k + 0.5)
	local others = stripW + invW + S.targetW

	-- Action bars shrink their buttons when the screen is too narrow for them.
	local barBtn = clamp(floor((W - others - 2 * S.pad - 11 * S.barGap) / 12), S.barBtnMin, S.barBtn)
	local gridW = 12 * barBtn + 11 * S.barGap
	local barsW = gridW + 2 * S.pad
	local fixed = others + barsW
	local beforeBars = stripW -- left of the bars, chat aside

	-- Chat goes inside the console, sized so the bars land in the middle of
	-- the screen, when it can be at least chatMin wide. Otherwise it floats
	-- above the left end of the console.
	local centred = floor(W / 2 - barsW / 2) - beforeBars
	-- (When the bars can't be centred anyway, chat takes whatever room is left.)
	local chatW = min(centred >= S.chatMin and min(centred, S.chatMax) or S.chatMax, W - fixed)
	if chatW < S.chatMin then
		chatW = 0
	end
	L.chatInConsole = chatW > 0
	local total = fixed + chatW
	local x = clamp(floor(W / 2 - barsW / 2) - beforeBars - chatW, 0, max(0, W - total))
	L.contentX, L.contentW = x, total

	-- Chat block.
	if chatW > 0 then
		-- The minimap section's own pillar closes the chat block's right side.
		L.panels[#L.panels + 1] = { key = "chat", x = x, y = 0, w = chatW, h = S.tall, openRight = true }
		L.insets[#L.insets + 1] = { key = "chat", x = x + 10, y = 10, w = chatW - 20, h = S.tall - 26 }
		-- 44 on the left leaves room for the chat menu buttons beside the frame
		L.chat = rect(x + 44, 44, chatW - 60, S.tall - 44 - 34)
		L.chatEdit = rect(x + 12, 14, chatW - 24, 24)
		x = x + chatW
	end

	-- Minimap and portrait sections. Positions below are the windows painted
	-- into the textures (pixels from the top-left) converted to units.
	local function px(tx, ty, tw, th) -- texture pixels to a console rect
		return rect(x + tx * k, (512 - ty - th) * k, tw * k, th * k)
	end
	L.sections = {
		{ key = "minimap", x = x, y = 0, w = S.sec, h = S.sec, wall = S.tall },
		{ key = "portrait", x = x + S.sec, y = 0, w = S.sec, h = S.sec, wall = S.secTop },
	}
	L.minimap = px(21, 222, 274, 274)
	L.zoneText = px(21, 204, 274, 16)
	L.minimapButtons = px(309, 224, 44, 274)
	local mapX = x
	L.portrait = px(436, 296, 138, 148)
	L.healthText = px(424, 452, 160, 26)
	L.powerText = px(424, 480, 160, 26)
	local pcx = L.portrait.x + L.portrait.w / 2
	L.crest = rect(floor(pcx - S.crest / 2), S.sec - 207 * k - 20, S.crest, S.crest)

	-- Hero screen, in the section's dark window right of the portrait: name,
	-- the level bar (experience fill with "Level N Class" on it) and a 2x2
	-- grid of stat icons with their values.
	local info = px(512 + 92, 272, 418, 240)
	L.info = info
	local ix, iw = info.x, info.w
	L.nameText = rect(ix + 10, 110, iw - 20, 18)
	L.xpBar = rect(ix + 18, 90, iw - 36, 16)
	local cellW = floor((iw - 20) / 2)
	L.stats = {}
	for i = 1, 4 do
		local col, row = (i - 1) % 2, floor((i - 1) / 2)
		local cx, cy = ix + 10 + col * cellW, 48 - row * 36
		L.stats[i] = {
			icon = rect(cx, cy, S.statIcon, S.statIcon),
			text = rect(cx + S.statIcon + 4, cy - 2, cellW - S.statIcon - 6, S.statIcon + 4),
		}
	end
	x = x + stripW

	-- Action bars 1-3, full twelve buttons wide, on a recessed screen.
	local gridH = 3 * barBtn + 2 * S.barRowGap
	local gy = floor((S.low - S.edge - gridH) / 2)
	local gx = x + S.pad
	L.barsRect = rect(x, 0, barsW, S.low)
	-- A stretch of wall as tall as the sections either side, joined on the left.
	L.panels[#L.panels + 1] = { key = "bars", x = x, y = 0, w = barsW, h = S.secTop, openLeft = true }
	L.insets[#L.insets + 1] = { key = "bars", x = x + 6, y = gy - 8, w = barsW - 12, h = gridH + 16 }
	L.bars.main = grid(gx, gy + 2 * (barBtn + S.barRowGap), 12, 1, barBtn, S.barGap)
	L.bars.bar2 = grid(gx, gy + barBtn + S.barRowGap, 12, 1, barBtn, S.barGap)
	L.bars.bar3 = grid(gx, gy, 12, 1, barBtn, S.barGap)
	x = x + barsW

	-- Inventory section: the 2x3 bag slots with its pillar; the key ring sits
	-- on the ledge above them.
	L.sections[#L.sections + 1] = { key = "inventory", x = x, y = 0, w = invW, h = S.sec, u1 = 208 / 512,
		wall = S.secTop }
	L.inventory = grid(x + 7 * k, 7 * k, 2, 3, 64 * k, 15 * k, 13 * k)
	L.keyring = rect(x + 7 * k, (512 - 273) * k, 20 * k, 20 * k)
	L.invRect = rect(x, 0, invW, S.secTop)
	x = x + invW

	-- Target panel: portrait, name, level, health and power, combo points,
	-- and the target's target underneath.
	local tw = S.targetW
	L.panels[#L.panels + 1] = { key = "target", x = x, y = 0, w = tw, h = S.mid, openLeft = true }
	L.insets[#L.insets + 1] = { key = "target", x = x + 8, y = 10, w = tw - 16, h = S.mid - 26 }
	local tx = x + 16
	L.target = {
		frame = rect(x + 8, 60, tw - 16, S.mid - 76),
		portrait = rect(tx, 82, 66, 66),
		name = rect(tx + 74, 132, tw - 106, 16),
		info = rect(tx + 74, 116, tw - 106, 14),
		health = rect(tx + 74, 98, tw - 106, 14),
		power = rect(tx + 74, 84, tw - 106, 10),
		combo = rect(tx, 64, tw - 32, 12),
	}
	L.tot = {
		frame = rect(x + 8, 12, tw - 16, 46),
		portrait = rect(tx, 16, 36, 36),
		name = rect(tx + 44, 36, tw - 76, 14),
		health = rect(tx + 44, 20, tw - 76, 12),
	}

	L.top = max(S.tall, L.crest.y + L.crest.h)

	-- Touching panels read as one wall: a side that meets a neighbour at least
	-- as tall is left open (no side trim, no corner), so trim and corners only
	-- appear where the console's outline steps.
	for _, a in ipairs(L.panels) do
		for _, b in ipairs(L.panels) do
			if a ~= b and a.x + a.w == b.x then
				a.openRight = b.h >= a.h
				b.openLeft = a.h >= b.h
			end
		end
	end

	-- Bars 4 and 5: 6x2 grids on the base band in the free space either side
	-- of the console when there is room, otherwise columns on the right edge
	-- of the screen.
	local wingGrid = 6 * S.sideBtn + 5 * S.sideGap
	local need = wingGrid + 2 * S.pad
	local leftFree, rightFree = L.contentX, W - L.contentX - L.contentW
	local wy = floor((S.low - S.edge - (2 * S.sideBtn + S.sideGap)) / 2)
	local spots = {}
	if leftFree >= need then
		spots[#spots + 1] = L.contentX - S.pad - wingGrid
	end
	local rx = L.contentX + L.contentW + S.pad
	while rightFree >= need and #spots < 2 do
		spots[#spots + 1] = rx
		rx, rightFree = rx + need, rightFree - need
	end
	if #spots == 2 then
		table.sort(spots)
		L.bars.bar4 = grid(spots[1], wy, 6, 2, S.sideBtn, S.sideGap)
		L.bars.bar5 = grid(spots[2], wy, 6, 2, S.sideBtn, S.sideGap)
		for _, key in ipairs({ "bar4", "bar5" }) do
			local g = L.bars[key]
			L.insets[#L.insets + 1] = { key = key, x = g.x - 8, y = g.y - 8, w = g.w + 16, h = g.h + 16 }
		end
		L.sideBarsW = 0
	else
		local bottom = S.tall + 48
		local avail = H - bottom - 60
		local size = max(20, min(S.sideBtn, floor((avail - 11 * S.sideGap) / 12)))
		local colH = 12 * size + 11 * S.sideGap
		local y = bottom + floor((avail - colH) / 2)
		L.bars.bar4 = grid(W - 8 - size, y, 1, 12, size, S.sideGap)
		L.bars.bar5 = grid(W - 8 - 2 * size - 4, y, 1, 12, size, S.sideGap)
		L.sideBarsW = 2 * size + 4 + 8
	end

	-- Floating chat: above the left end of the console.
	if not L.chatInConsole then
		L.chat = rect(mapX + 4, L.top + 36, 400, 150)
		L.chatEdit = rect(mapX, L.top + 6, 408, 24)
	end

	-- The micro menu sits on top of the inventory and target blocks.
	L.micro = { right = L.contentX + L.contentW - 6, bottom = S.mid + 4, maxW = invW + S.targetW + barsW }

	-- Top bar: menu buttons on the left of the core, the day/night clock in
	-- the middle, data feed slots everywhere else.
	local coreW = min(W, floor(H * P.coreAspect + 0.5))
	local coreX = floor((W - coreW) / 2)
	L.coreX, L.coreW = coreX, coreW
	L.topBar = rect(0, H - S.topH, W, S.topH)
	local cx = floor(W / 2)
	-- The dial's centre sits on the bar's trim; the bar hides its upper half.
	local cy = H - S.topH + 8
	L.clock = { cx = cx, cy = cy, radius = S.dialR }
	L.clockFrame = rect(cx - S.clockW / 2, cy + 4 - S.clockH, S.clockW, S.clockH)
	-- Plates sit on the bar above its trim (the bottom 16 units).
	local plateY, plateH = H - S.topH + 18, S.topH - 22
	local clockL, clockR = L.clockFrame.x - 6, L.clockFrame.x + L.clockFrame.w + 6
	L.topButtons = {}
	local bx = coreX + 16
	for i = 1, 4 do
		local r = rect(bx, plateY, S.topBtnW, plateH)
		L.topButtons[i] = (r.x + r.w <= clockL) and r or false
		bx = bx + S.topBtnW + 6
	end
	local buttonsEnd = coreX + 16 + 4 * (S.topBtnW + 6)

	-- Data feed slots in order of preference: from the core's right edge in
	-- towards the clock (where Warcraft III shows its resources), then from
	-- the menu buttons towards the clock, then the right and left wings.
	local slots, step = {}, S.slotW + S.slotGap
	local function add(sx)
		slots[#slots + 1] = rect(sx, plateY, S.slotW, plateH)
	end
	local coreR = coreX + coreW - 16
	local sx = coreR - S.slotW
	while sx >= clockR do
		add(sx)
		sx = sx - step
	end
	sx = buttonsEnd + S.slotGap
	while sx + S.slotW <= clockL do
		add(sx)
		sx = sx + step
	end
	sx = coreR + 16 + S.slotGap
	while sx + S.slotW <= W - 8 do
		add(sx)
		sx = sx + step
	end
	sx = coreX - S.slotGap - S.slotW
	while sx >= 8 do
		add(sx)
		sx = sx - step
	end
	L.topSlots = slots

	return L
end

return Layout
