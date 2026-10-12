-- Pure layout math, ported from the original addon's Align* functions.
-- No WoW API calls in this file so it can also run under plain
-- Lua (tools/dump_layout.lua uses it to render preview mockups).
--
-- The console is laid out in "console units": a screen 768 units tall, the
-- size the original addon was designed for, with the origin at the bottom-left corner.
-- `s` is the original addon's "UI scale" option (240-270), the height of the minimap and
-- portrait blocks; nearly every size and offset is a fraction of it, and the
-- odd pixel corrections per theme and per scale are the original addon's own.
--
-- The original addon anchors most pieces to each other; here every piece gets absolute
-- coordinates instead, so the whole console can be shifted for the "Center
-- UI" modes by building it twice.

local _, ns = ...
ns = ns or {}

local floor, max, min = math.floor, math.max, math.min

local Layout = {}
ns.Layout = Layout

local function rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end
Layout.rect = rect

local function right(r) return r.x + r.w end
local function top(r) return r.y + r.h end

----------------------------------------------------------------------------
-- Top bar (Reforged UI): the core aspect decides where the menu buttons and
-- the default data feeds go on wide screens.

Layout.PROFILES = {
	standard = { label = "16:9", coreAspect = 16 / 9 },
	wide = { label = "21:9", coreAspect = 21 / 9 },
	superwide = { label = "32:9", coreAspect = 21 / 9 },
}
Layout.PROFILE_ORDER = { "standard", "wide", "superwide" }

local TOP = {
	topH = 40, topBtnW = 84, slotW = 120, slotGap = 8,
	dialR = 52, clockW = 176, clockH = 88,
}
Layout.TOP_SIZES = TOP

function Layout.DetectProfile(w, h)
	local aspect = w / h
	if aspect < 2.0 then
		return "standard"
	elseif aspect < 2.75 then
		return "wide"
	end
	return "superwide"
end

-- The top bar in its own units (W x H, origin bottom-left).
function Layout.ComputeTopBar(W, H, profile)
	if not Layout.PROFILES[profile] then
		profile = Layout.DetectProfile(W, H)
	end
	local P = Layout.PROFILES[profile]
	local T = { W = W, H = H, profile = profile }
	local coreW = min(W, floor(H * P.coreAspect + 0.5))
	local coreX = floor((W - coreW) / 2)
	T.coreX, T.coreW = coreX, coreW
	T.topBar = rect(0, H - TOP.topH, W, TOP.topH)
	local cx = floor(W / 2)
	-- The dial's centre sits on the bar's trim; the bar hides its upper half.
	local cy = H - TOP.topH + 8
	T.clock = { cx = cx, cy = cy, radius = TOP.dialR }
	T.clockFrame = rect(cx - TOP.clockW / 2, cy + 4 - TOP.clockH, TOP.clockW, TOP.clockH)
	-- Plates sit on the bar above its trim (the bottom 16 units).
	local plateY, plateH = H - TOP.topH + 18, TOP.topH - 22
	local clockL, clockR = T.clockFrame.x - 6, T.clockFrame.x + T.clockFrame.w + 6
	T.topButtons = {}
	local bx = coreX + 16
	for i = 1, 4 do
		local r = rect(bx, plateY, TOP.topBtnW, plateH)
		T.topButtons[i] = (r.x + r.w <= clockL) and r or false
		bx = bx + TOP.topBtnW + 6
	end
	local buttonsEnd = coreX + 16 + 4 * (TOP.topBtnW + 6)

	-- Data feed slots in order of preference: from the core's right edge in
	-- towards the clock (where Warcraft III shows its resources), then from
	-- the menu buttons towards the clock, then the right and left wings.
	local slots, step = {}, TOP.slotW + TOP.slotGap
	local function add(sx)
		slots[#slots + 1] = rect(sx, plateY, TOP.slotW, plateH)
	end
	local coreR = coreX + coreW - 16
	local sx = coreR - TOP.slotW
	while sx >= clockR do
		add(sx)
		sx = sx - step
	end
	sx = buttonsEnd + TOP.slotGap
	while sx + TOP.slotW <= clockL do
		add(sx)
		sx = sx + step
	end
	sx = coreR + 16 + TOP.slotGap
	while sx + TOP.slotW <= W - 8 do
		add(sx)
		sx = sx + step
	end
	sx = coreX - TOP.slotGap - TOP.slotW
	while sx >= 8 do
		add(sx)
		sx = sx - step
	end
	T.topSlots = slots
	return T
end

----------------------------------------------------------------------------
-- Console

Layout.THEMES = { "human", "orc", "undead", "nightelf" }
Layout.SCALE_MIN, Layout.SCALE_MAX = 240, 270
Layout.CENTER_MODES = { "off", "center", "slim", "noinv" }

-- Draw layers that the original addon's ChangeTheme gives the overlapping pieces.
local LAYERS = {
	human = {
		ext1 = { "OVERLAY", 0 }, ext2 = { "ARTWORK", 0 }, ext3 = { "BORDER", 0 }, right_left = { "BACKGROUND", 0 },
		lid = { "ARTWORK", 5 }, br_top = { "BORDER", 4 }, filler_top1 = { "BORDER", 0 },
	},
	orc = {
		ext1 = { "ARTWORK", 0 }, ext2 = { "OVERLAY", 0 }, ext3 = { "BORDER", 0 }, right_left = { "ARTWORK", 0 },
		lid = { "BORDER", 4 }, br_top = { "OVERLAY", 5 }, filler_top1 = { "BORDER", 0 },
	},
	undead = {
		ext1 = { "OVERLAY", 0 }, ext2 = { "ARTWORK", 0 }, ext3 = { "BORDER", 0 }, right_left = { "ARTWORK", 0 },
		lid = { "BORDER", 4 }, br_top = { "ARTWORK", 5 }, filler_top1 = { "OVERLAY", 0 },
	},
	nightelf = {
		ext1 = { "OVERLAY", 0 }, ext2 = { "ARTWORK", 0 }, ext3 = { "OVERLAY", 0 }, right_left = { "ARTWORK", 0 },
		lid = { "BORDER", 4 }, br_top = { "ARTWORK", 4 }, filler_top1 = { "OVERLAY", 0 },
	},
}

-- Columns and rows of the original addon's 2x3 inventory, in its slot order (slot 1 is
-- the bottom-left one).
local INVENTORY_CELLS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { 1, 2 }, { 0, 2 } }

-- Width (in 512ths) cut off the inventory texture for "Center UI, no chat area".
local SLIM_CUT = { human = 512 - 209, orc = 512 - 210, undead = 512 - 221, nightelf = 512 - 254 }

-- Ext pieces, the grid, the inventory and the frame of the chat area.
local function buildRight(L, o, W, g, add, themed, themedLayer)
	local s, m, t = o.s, o.m, o.theme
	local d1 = ({ human = 2, orc = 1, undead = 1 })[t] or 0
	local d2 = ({ human = 2, orc = 1 })[t] or 0
	local RM = rect(right(g[4]) - 0.2479 * s - d1, 0, s + 0.01851 * s, s)
	local RL = rect(RM.x + 0.35 * s - d2 - s / 2, 0, s / 2, s)
	L.inventoryArt, L.noInventoryArt = RM, RL
	local rlLayer, rlSub = themedLayer("right_left")
	add("right_left", "left", themed("inventory\\no_inventory"), rlLayer, rlSub, RL)
	local rm = add("right_middle", "right", themed("inventory\\inventory"), "OVERLAY", 0, RM)

	local brTop = rect(W - 0.7259 * s, 0.5208 * s + m, s, s / 4)
	local extraHeight = (t == "human" or t == "undead") and 0.022222 * s or 0
	local brMid = rect(W - 0.0625 * s, 0, s / 16,
		0.5 * s + m + extraHeight + (t == "human" and 0 or 0.0208333 * s))
	local brMidTc
	local brBot = rect(W - 0.7259 * s, 0, s, s / 8)
	local shiftWidth = t == "undead" and 0.0185185 * s or 0
	local lid = rect(RM.x + 0.2833333333 * s - shiftWidth, -0.3166 * s + m, s, s)
	local lidTc
	local bg = rect(right(RL) + 3, 0, 0, 0.5578 * s + m)
	if o.chatWidth then
		bg.w = o.chatWidth
	elseif o.center == "center" then
		bg.w = 2.2 * s -- The original addon's default width
	else
		bg.w = max(0, W - bg.x) -- reach the screen edge
	end

	local aeh = 0
	if s >= 250 and s <= 259 then aeh = -3 elseif s > 259 then aeh = -6 end
	local RMr = right(RM)
	local fT, fB, tcT = {}, {}, {}
	fT[1] = rect(RMr - 0.09 * s + aeh, 0.5206 * s + m, s / 2, s / 4)
	fB[1] = rect(RMr - 0.03703 * s, 0, s / 2, s / 16)
	fT[2] = rect(fB[1].x + 0.2291 * s + aeh, 0.5206 * s + m, s / 2, s / 4)
	fB[2] = rect(fB[1].x + 0.2768 * s, 0, s / 2, s / 16)
	fT[3] = rect(fB[2].x + 0.2291 * s + aeh, 0.5206 * s + m, s / 2, s / 4)
	fB[3] = rect(fB[2].x + 0.2768 * s, 0, s / 2, s / 16)
	local showT = { not (s >= 269 and (t == "human" or t == "undead")), s < 258, s <= 245 }
	local showB = { true, s < 258, s <= 245 }

	if t == "undead" then
		local offset, offset2 = 15, 0
		local shiftExtra = 270 - s
		showT = { false, false, false }
		local a1, a2 = 0, 0
		local OFFSETS = { [270] = 0, [269] = 17, [268] = 23, [267] = 27, [266] = 33, [265] = 40, [264] = 45,
			[263] = 51, [262] = 59, [261] = 68, [260] = 77 }
		if OFFSETS[s] then
			offset = OFFSETS[s]
			if s <= 267 then
				offset2 = s * 0.014981 - 2
			end
		elseif s >= 257 then
			showT[1] = true
			shiftExtra = 261 - s
			a1 = 25
			fT[1].w = s / 2
		elseif s <= 256 then
			showT[1] = true
			shiftExtra = 258 - s
			offset = 25
			offset2 = s * 0.014981 - 2
			a1 = 40
			fT[1].w = s / 2 - (10 - (shiftExtra * 2 + 5))
			if s == 253 then
				offset = 28
			elseif s >= 250 and s <= 252 then
				offset = 40
				fT[1].w = s / 2 + 35
			elseif s <= 249 then
				offset, a1 = 53, 53
				if s == 249 then
					fT[1].w = s / 2 + 35
				elseif s >= 247 and s <= 248 then
					fT[1].w = s / 2 + 45
				elseif s == 246 then
					offset, a1 = 65, 60
					fT[1].w = s / 2 + 45
				elseif s == 245 then
					offset, a1 = 65, 61
					fT[1].w = s / 2 + 52
				else
					showT[2] = true
					shiftExtra, offset = 0, 0
					a1, a2 = 20, 87
					fT[1].w = s / 2
					fT[2].w = s / 2 + 25
					if s >= 242 and s <= 243 then
						fT[2].w = s / 2 + 38
					elseif s <= 241 then
						a1, a2 = 23, 102
						fT[1].w = s / 2 + 25
						fT[2].w = s / 2 + 35
					end
				end
			end
		end
		fT[1].x, fT[1].y = RMr - 0.09 * s + a1, 0.5206 * s + m + 1
		fT[2].x, fT[2].y = RMr - 0.09 * s + a2, 0.5206 * s + m + 1
		lid.w = s + offset
		lid.x = RM.x + 0.2833333333 * s - shiftWidth - shiftExtra
		brTop.w = s + offset2
		brTop.x = W - 0.7259 * s - offset2
	elseif t == "nightelf" then
		if s >= 267 then
			lid.w = 0.7890625 * s + (s == 267 and 3 or 0)
			lidTc = { 0, 0.7890625, 0, 1 }
		end
		brTop = rect(W - 0.7259 * s - 0.17037037 * s, 0.5208 * s + m, s + 0.088888 * s, s / 4 + 0.088888 * s / 4)
		local makeSmaller = 0
		if s > 252 and s <= 260 then
			makeSmaller = 1
		elseif s > 250 and s <= 252 then
			makeSmaller = 2
		elseif s == 250 then
			makeSmaller = 3
		elseif s <= 249 then
			makeSmaller = 4
		end
		brMid.w = 270 / 8 + 0.088888 * s / 8 - makeSmaller
		brMid.h = 0.5 * s + m + 0.022222 * s + 1
		local cut = 0
		if m > 90 and m < 100 then
			cut = 0.05
		elseif m > 70 and m <= 90 then
			cut = 0.1
		elseif m > 40 and m <= 70 then
			cut = 0.25
		elseif m > 30 and m <= 40 then
			cut = 0.38
		elseif m >= 0 and m <= 30 then
			cut = 0.475
		end
		brMidTc = { 0, 1, 0.04296875 + cut, 1 }
		brMid.x = W - 37 + makeSmaller
		lid.x, lid.y = RM.x + 0.2833333333 * s - 6, -0.3166 * s + m + 6
		showT = { false, false, false }
		if s <= 260 then
			showT[1] = true
			local a = 35
			if s >= 250 then
				a = 50
			elseif s >= 247 and s <= 249 then
				a = 60
			else
				showT[2] = true
				fT[2].x, fT[2].y = fB[1].x + 0.2291 * s + 5, 0.5206 * s + m
				tcT[2] = { 1, 0, 0, 1 }
			end
			fT[1].x, fT[1].y = RMr - 0.09 * s + a, 0.5206 * s + m
		end
	end

	-- "Center UI": the bottom-right pieces follow the chat area instead of
	-- the screen edge.
	local mode = o.center
	if mode == "center" then
		local bgR, bgT = right(bg), top(bg)
		if t == "nightelf" then
			brTop.x = bgR - 0.9 * s
		elseif t == "undead" then
			brTop.x = bgR - 0.734615 * s
		else
			brTop.x = bgR - 0.725833 * s
		end
		brTop.y = bgT - 0.03846153 * s
		brBot.x = bgR - 0.725833 * s
		brMid.x = t == "nightelf" and (bgR - 37) or (bgR - 0.0625 * s)
	end

	-- The original addon's frame pieces only reach across a 16:9 screen; on wider screens
	-- (or a wider chat area) repeat the filler pieces until they meet the
	-- bottom-right corner.
	if mode == "off" or mode == "center" then
		local topCover = right(lid) - 0.6 * s
		for i = 1, 3 do
			if showT[i] then topCover = max(topCover, right(fT[i])) end
		end
		local n = 3
		while topCover < brTop.x + 0.1 * s do
			n = n + 1
			fT[n] = rect(topCover - 0.2709 * s, 0.5206 * s + m, s / 2, s / 4)
			showT[n] = true
			topCover = right(fT[n])
		end
		local botCover = RMr
		for i = 1, 3 do
			if showB[i] then botCover = max(botCover, right(fB[i])) end
		end
		n = 3
		while botCover < brBot.x + 0.1 * s do
			n = n + 1
			fB[n] = rect(botCover - 0.2232 * s, 0, s / 2, s / 16)
			showB[n] = true
			botCover = right(fB[n])
		end
	end

	add("chat_bg", "right", "other\\black_background", "BACKGROUND", 0, bg)
	local lidLayer, lidSub = themedLayer("lid")
	add("lid", "right", themed("bottom right\\right_part_lid"), lidLayer, lidSub, lid, lidTc)
	local topLayer, topSub = themedLayer("br_top")
	add("br_top", "right", themed("bottom right\\BottomRight_Top"), topLayer, topSub, brTop)
	add("br_middle", "right", themed("bottom right\\BottomRight_Middle"), "BORDER", 0, brMid, brMidTc)
	add("br_bottom", "right", themed("bottom right\\BottomRight_Bottom"), "BORDER", 0, brBot)
	for i = 1, max(#fT, #fB) do
		if fT[i] then
			local layer, sub = "ARTWORK", 0
			if i == 1 then
				layer, sub = themedLayer("filler_top1")
			end
			local p = add("filler_top" .. i, "right", themed("bottom right\\BottomRightFillerTop"), layer, sub, fT[i], tcT[i])
			p.shown = showT[i] and true or false
		end
		if fB[i] then
			local p = add("filler_bottom" .. i, "right", themed("bottom right\\BottomRightFillerBottom"),
				i == 1 and "BORDER" or "ARTWORK", 0, fB[i])
			p.shown = showB[i] and true or false
		end
	end

	-- The 2x3 inventory: slot 1 bottom-left, then right, and up.
	local slotX, slotY = RM.x + 0.02 * s + 0.5, 0.016 * s + 0.5
	L.inventory = {}
	for n, cell in ipairs(INVENTORY_CELLS) do
		local col, rowN = cell[1], cell[2]
		local sz = 0.1185185 * s
		L.inventory[n] = rect(slotX + col * 0.156 * s - (1 - col), slotY + rowN * 0.148 * s, sz, sz)
	end

	-- Bags above the chat area, backpack on the right; the key ring to their left.
	L.bags = {
		right = right(brTop) - (t == "nightelf" and 0.192592 * s or 0.2769 * s),
		top = brTop.y + 63, size = 37, step = 39,
	}

	-- Centre modes that drop parts of the right side.
	L.rightPoint = right(bg)
	if mode == "slim" then
		for _, p in ipairs(L.pieces) do
			if p.frame == "right" and p ~= rm then
				p.shown = false
			end
		end
		local cut = SLIM_CUT[t]
		rm.tc = { 0, 1 - cut / 512, 0, 1 }
		RM.w = (512 - cut) / 2
		if t == "nightelf" or t == "undead" then
			rm.file = themed("inventory\\slim")
		end
		local invW = RM.w
		local offsetSlot = invW * 0.3714285714
		local slotSize = invW * 0.28571428
		if t == "undead" and s >= 245 and s <= 250 then
			slotSize = slotSize - s * (0.3 / 110)
		elseif t == "undead" and s < 245 then
			slotSize = slotSize - s * (0.5 / 110)
		elseif t == "nightelf" and s < 243 then
			slotSize = slotSize - s * (4 / 127)
		elseif t == "nightelf" and s < 250 then
			slotSize = slotSize - s * (3.5 / 127)
		elseif t == "nightelf" then
			slotSize = slotSize - s * (3 / 127)
		end
		local offY = (t == "human" and s / 260) or (t == "undead" and s / 250) or 0
		local offX = (t == "undead" and -3 * s / 260) or (t == "nightelf" and -8 * s / 260) or 0
		local neX = (t == "nightelf" and s < 250 and 2 * s / 260) or (t == "nightelf" and s / 260) or 0
		for n, cell in ipairs(INVENTORY_CELLS) do
			local col, rowN = cell[1], cell[2]
			local x = slotX + col * offsetSlot - (1 - col) + offX * col + neX
				- ((col == 1 and t == "nightelf" and s < 250) and s / 260 or 0)
			local y = slotY + rowN * 0.148076 * s - offY - ((rowN == 2 and t == "undead") and -s / 250 or 0)
			L.inventory[n] = rect(x, y, slotSize, slotSize)
		end
		local EB = L.extBg
		EB.w = max(0, EB.w - (right(EB) - RM.x))
		L.rightPoint = right(RM)
		L.bags = nil
	elseif mode == "noinv" then
		for _, p in ipairs(L.pieces) do
			if p.frame == "right" then
				p.shown = false
			end
		end
		L.inventory, L.bags = nil, nil
		if t == "nightelf" then
			add("tree", "left", themed("inventory\\inventory"), "BACKGROUND", 0,
				rect(RL.x + 0.1615384 * s, -0.02692307 * s, 0.9846153 * s, 1.03461538 * s))
		end
		local EB = L.extBg
		if right(EB) > right(RL) then
			EB.w = EB.w - (right(EB) - right(RL))
		end
		L.rightPoint = right(RL) + (t == "nightelf" and 18 or 0)
	end

	-- Chat window: inside the black area, clear of the frame pieces.
	if mode == "off" or mode == "center" then
		local x0 = right(RL) + 0.08 * s
		local x1 = min(right(bg), brMid.x) - 6
		local y0 = brBot.y + s / 16 + 4
		local y1 = brTop.y + 0.03 * s
		local edit = 26
		if o.chatInputAbove then
			L.chat = rect(x0, y0, x1 - x0, y1 - y0 - edit)
			L.chatEdit = rect(x0 - 4, y1 - edit + 2, x1 - x0 + 8, edit - 2)
		else
			L.chat = rect(x0, y0 + edit, x1 - x0, y1 - y0 - edit)
			L.chatEdit = rect(x0 - 4, y0, x1 - x0 + 8, edit - 2)
		end
	end
	L.consoleTop = L.bags and (L.bags.top + 4) or (0.6 * s + m)
end

local function build(W, H, o, X0)
	local s, m, t = o.s, o.m, o.theme
	local layers = LAYERS[t]
	local L = { W = W, H = H, s = s, m = m, theme = t, center = o.center, pieces = {}, byKey = {} }

	-- Art pieces. `frame` says which of the original addon's frames the piece belongs to,
	-- which decides the stacking: bg < left < grid < right.
	local function add(key, frame, file, layer, sub, r, tc)
		local p = { key = key, frame = frame, file = file, layer = layer, sub = sub or 0, rect = r, tc = tc, shown = true }
		L.pieces[#L.pieces + 1] = p
		L.byKey[key] = p
		return p
	end
	local function themed(file)
		return t .. "\\" .. file
	end
	local function themedLayer(key)
		local spec = layers[key]
		return spec[1], spec[2]
	end

	-- Left part: minimap block and portrait block.
	local MT = rect(X0, 0, s, s)
	local PT = rect(X0 + s, 0, s, s)
	L.minimapArt, L.portraitArt = MT, PT
	add("minimap", "left", themed("minimap_portrait\\minimap"), "ARTWORK", 0, MT)
	add("portrait", "left", themed("minimap_portrait\\portrait"), "BORDER", 0, PT)

	-- Blizzard's minimap: centred 0.189s left of and 0.2s below the block's
	-- centre, 0.55s square.
	local mm = rect(MT.x + 0.5 * s - 0.189 * s - 0.275 * s, 0.5 * s - 0.2 * s - 0.275 * s, 0.55 * s, 0.55 * s)
	L.minimap = mm
	local mmR, mmB = right(mm), mm.y
	-- Column beside the minimap: three action slots, the mail slot and the
	-- round tracking slot.
	L.noMail = rect(mmR + 0.01851 * s, mmB + 0.19259 * s, 0.085 * s, 0.085 * s)
	local resize, addW, addH = 4, 2, 2
	if t == "orc" then
		resize, addW, addH = 3, 2, 1
	end
	L.minimapSlots = {}
	for n = 1, 3 do
		local size = 0.08518 * s - resize
		L.minimapSlots[n] = rect(mmR + 0.01851 * s + addW,
			mmB + 0.455555 * s - (n - 1) * 0.08518 * s - floor(n * 0.34) + addH, size, size)
	end
	L.tracking = { cx = MT.x + 0.64 * s, cy = 0.16 * s, size = 0.09 * s }
	if o.zoneTextPos ~= 3 then
		L.zoneText = rect(mm.x, mm.y + 1 + (o.zoneTextPos == 2 and 0.5 * s or 0), mm.w, 12)
	end
	-- Other minimap buttons (calendar, addon buttons, ...) along the top
	-- edge of the map.
	L.minimapButtons = { x = mm.x + 2, y = top(mm) - 2, size = 0.07 * s, maxW = mm.w - 4 }

	-- Portrait.
	local px, py = o.portraitX or 100, o.portraitY or 100
	local ps = 0.27 * s + (o.portraitScale or 0)
	L.portrait = rect(MT.x + 0.86 * s - (100 - px), 0.10 * s - (100 - py), ps, ps)
	local pcx, pcy = MT.x + 0.86 * s + 0.135 * s, 0.10 * s + 0.135 * s
	L.portraitBg = rect(pcx - 0.175 * s, pcy - (0.35 * s + 20) / 2, 0.35 * s, 0.35 * s + 20)
	L.health = rect(right(MT) - 0.147 * s, 0.07 * s, 0.27 * s, 0.03 * s)
	L.power = rect(right(MT) - 0.147 * s, 0.02 * s, 0.27 * s, 0.03 * s)
	-- Status icons (the original addon moves Blizzard's; we draw our own in their places).
	L.leaderIcon = rect(PT.x + 0.0784313 * s, 0.368627 * s, 16, 16)
	L.pvpIcon = rect(PT.x - 0.2307692 * s, 0, 64, 64)
	L.restIcon = rect(PT.x - 0.188235 * s, 0.32941 * s, 31, 31)

	-- Hero screen: experience bar and the four stat icons.
	local xs = 0.375
	local xpX, xpY = PT.x + 0.23 * s, 0.3 * s
	local capW, capH = 0.05924 * s * xs, 0.2370 * s * xs
	local midW = 1.70 * s * xs
	local total = 2 * capW + midW
	L.xp = {
		left = rect(xpX, xpY, capW, capH),
		middle = rect(xpX + capW, xpY, midW, capH),
		right = rect(xpX + capW + midW, xpY, capW, capH),
		bar = rect(xpX, xpY, 0.6814 * s, 0.083 * s), -- at 100%
		hover = rect(xpX + capW, xpY, total, 0.08 * s),
		nameY = xpY + capH / 2 + 0.080 * s,
		levelY = xpY + capH / 2,
		cx = xpX + capW + midW / 2,
		width = total,
	}
	local iconSize = total * 0.17
	local extraSpace = s <= 250 and 1 or 0
	local function statIcon(dx, dy, labelX, valueY, valueH)
		local r = rect(xpX + 1 + dx, xpY - 0.14 * s + dy, iconSize, iconSize)
		local iconTop = top(r)
		r.label = rect(r.x + labelX, iconTop - 0.065 * s, 100, 15)
		r.value = rect(r.x + labelX, iconTop + valueY, 100, valueH)
		return r
	end
	local valueY = -0.1667 * s - extraSpace
	L.statIcons = {
		statIcon(0, 0, 0.1294 * s, valueY, 30),
		statIcon(0.3607 * s, 0, 0.1294 * s, valueY, 30),
		statIcon(0.3607 * s, -0.1412 * s, 0.1294 * s, valueY, 30),
		statIcon(0, -0.14 * s, 0.14 * s, -0.1111111111111 * s, 15), -- armour
	}

	-- Black background behind the action grid.
	L.extBg = rect(right(PT) - 0.18 * s, 0, 2.1 * s, 0.5 * s)

	-- Action slot grid: four copies of a 4x3 grid overlapping into 12x3.
	local gs = 0.91851 * s
	local g = { rect(L.extBg.x + 0.2 * s - 0.01666666667 * s, 1, gs, gs) }
	g[2] = rect(right(g[1]) - 0.4518 * s, 1, gs, gs)
	g[3] = rect(right(g[2]) - 0.4518 * s, 1, gs, gs)
	g[4] = rect(right(g[3]) - 0.6115 * s + 2, 1, gs, gs)
	L.grid = g
	for i, layer in ipairs({ "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }) do
		add("grid" .. i, "grid", themed("actionbar\\actionslots_grid"), layer, 0, g[i])
	end

	-- Action bars 1-3, the original addon's spacing with its pixel corrections.
	local barX, barY = g[1].x + 0.037037 * s, g[1].y - 1
	local size = 0.11111 * s
	local spacing = 0.159259 * s
	local function row(y)
		local list, x, extra = {}, barX - 6, 0
		for k = 1, 12 do
			if k == 4 then
				extra = extra - 3
			elseif k == 5 then
				extra = extra + 2
			elseif k == 10 then
				extra = extra + 1
			elseif k == 12 and s >= 240 and s <= 260 then
				extra = extra + 1
			end
			if k > 1 then
				x = x + spacing + extra
			end
			list[k] = x
		end
		return { xs = list, y = y, size = size }
	end
	local row2 = barY + size + 0.0667 * s
	L.bars = { main = row(barY + 5), bar2 = row(row2), bar3 = row(row2 + size + 0.04444 * s) }

	-- Micro buttons on top of the grid's right end.
	local moveX, moveY = -8, 0
	if s < 245 then moveX = -3 elseif s < 253 then moveX = -4 elseif s < 260 then moveX = -6 end
	if t == "human" then
		moveX = -8
	elseif t == "undead" then
		moveX, moveY = -5, 7
	elseif t == "nightelf" then
		moveX, moveY = -12, 11
	end
	L.micro = { right = right(g[4]) + moveX + 27, bottom = top(g[4]) - 0.3916 * s + moveY, maxW = 8 * 27 }

	-- Extensions: the wall above the action grid.
	local ext1 = rect(right(PT) - 0.15 * s, 0.45 * s, s, 0.12592 * s)
	local ext2 = rect(0, ext1.y, s, 0.12592 * s)
	local ext3 = rect(0, 0, 0.9481 * s, 0.12592 * s)
	local tc2, tc3
	if s >= 260 then
		ext2.x = right(ext1) - 0.17 * s
		ext3.x, ext3.y = right(ext1) + 0.15 * s, ext1.y + 0.013 * s
	elseif s >= 240 then
		ext2.x = right(ext1) - 0.40 * s
		ext3.x, ext3.y = right(ext2) - 0.50 * s, ext2.y + 0.013 * s
	else
		ext2.x = right(ext1) - 0.05 * s
		ext3.x, ext3.y = right(ext2) - 0.55 * s, ext2.y + 0.013 * s
	end
	if t == "human" then
		tc2 = { 0.265625, 1, 0, 1 }
		ext2.w = 0.8148148 * s
		ext2.x = right(ext1)
		ext3.x, ext3.y = right(ext1) + 0.73333 * s, ext1.y + 0.01481481 * s
		ext3.w, ext3.h = 0.26667 * s, 0.13333334 * s
		tc3 = { 0.5, 1, 0, 1 }
	elseif t == "undead" then
		ext1.x = right(PT) - 0.15 * s + 0.083333333 * s
		ext3.w, ext3.h = s, s / 8
		ext3.x, ext3.y = right(ext1) - 0.088888888 * s + 2, ext1.y + 2
		ext2.w = s <= 255 and (s + 145) or (s + 0.54166666 * s)
		ext2.h = 0.12592 * s - 1
		ext2.x = right(ext1) - 125
		tc2 = { 0.09, 1, 0, 1 }
	elseif t == "nightelf" then
		ext1 = rect(right(PT) - 0.096296 * s, 0.43333 * s, s, s / 4)
		ext2 = rect(right(PT) + 0.685185 * s - 5, 0.43333 * s, s, s / 4)
		ext3 = rect(right(ext2) - 0.296296 * s, ext2.y, s / 2, s / 4)
	end
	local l1, s1 = themedLayer("ext1")
	local l2, s2 = themedLayer("ext2")
	local l3, s3 = themedLayer("ext3")
	add("ext1", "left", themed("actionbar\\ext1"), l1, s1, ext1)
	add("ext2", "left", themed("actionbar\\ext1"), l2, s2, ext2, tc2)
	add("ext3", "left", themed("actionbar\\ext2"), l3, s3, ext3, tc3)

	buildRight(L, o, W, g, add, themed, themedLayer)
	return L
end

-- o: s (240-270), m (raise the chat area, 0-150), theme, center ("off",
-- "center", "slim", "noinv"), chatWidth (nil = to the screen edge),
-- zoneTextPos (1-3), portraitX/Y (100 = default), portraitScale (0-35),
-- chatInputAbove.
function Layout.Compute(W, H, o)
	local L = build(W, H, o, 0)
	L.shift = 0
	if o.center and o.center ~= "off" then
		local dx = math.max(0, floor((W - L.rightPoint) / 2))
		L = build(W, H, o, dx)
		L.shift = dx
	end
	return L
end

return Layout
