-- Pure layout math for the Reforged console. No WoW API calls in this file so
-- it can also run under plain Lua (tools/dump_layout.lua uses it to render the
-- preview mockups). All values are in console units: UIParent units divided by
-- the console scale, origin at the bottom-left of the screen.

local _, ns = ...
ns = ns or {}

local floor, max, min = math.floor, math.max, math.min

local Layout = {}
ns.Layout = Layout

-- Each profile decides how wide the central console is and where chat lives.
-- Anything wider than the core becomes decorative "wings" on either side.
Layout.PROFILES = {
	standard = { label = "16:9", coreAspect = 16 / 9, chatInConsole = false, wingBars = false },
	wide = { label = "21:9", coreAspect = 21 / 9, chatInConsole = true, wingBars = false },
	superwide = { label = "32:9", coreAspect = 21 / 9, chatInConsole = true, wingBars = true },
}
Layout.PROFILE_ORDER = { "standard", "wide", "superwide" }

local S = {
	edge = 16, -- trim thickness drawn on every panel
	pad = 18, -- distance from a panel's outer edge to its content
	tall = 212, -- minimap and command card blocks
	mid = 176, -- portrait, inventory and in-console chat blocks
	low = 150, -- the base band that spans the whole screen
	map = 162,
	mapButtonsW = 28,
	cmdBtn = 44, cmdGap = 5,
	invBtn = 38, invGap = 6,
	portraitW = 150, portrait = 100,
	chatW = 440, chatMinW = 320,
	infoMinW = 360,
	barBtn = 34, barGap = 3,
	sideBtn = 36, sideGap = 3,
	crest = 104,
	topH = 32, topSlot = 128, -- topbar.tga (256x64) shown 32 tall repeats every 128
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

local function grid(x, y, cols, rows, size, gap)
	return {
		x = x, y = y, cols = cols, rows = rows, size = size, gap = gap,
		w = cols * size + (cols - 1) * gap,
		h = rows * size + (rows - 1) * gap,
	}
end

-- Returns the position of button `index` (1-based, row-major from the top-left)
-- inside a grid as bottom-left coordinates.
function Layout.GridCell(g, index)
	local col = (index - 1) % g.cols
	local row = floor((index - 1) / g.cols)
	local x = g.x + col * (g.size + g.gap)
	local y = g.y + g.h - g.size - row * (g.size + g.gap)
	return x, y
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

	local coreW = min(W, floor(H * P.coreAspect + 0.5))
	local coreX = floor((W - coreW) / 2)
	L.coreX, L.coreW = coreX, coreW
	L.base = rect(0, 0, W, S.low)

	local mapW = S.pad + S.mapButtonsW + 4 + S.map + S.pad
	local invW = S.pad * 2 + 2 * S.invBtn + S.invGap
	local cmdW = S.pad * 2 + 4 * S.cmdBtn + 3 * S.cmdGap
	local fixed = mapW + S.portraitW + invW + cmdW

	-- Chat goes inside the console when the profile asks for it and the info
	-- panel can still breathe; otherwise it floats above the minimap like the
	-- Warcraft III message area.
	local chatW = 0
	if P.chatInConsole then
		chatW = min(S.chatW, coreW - fixed - S.infoMinW)
		if chatW < S.chatMinW then
			chatW = 0
		end
	end
	local infoW = coreW - fixed - chatW
	L.chatInConsole = chatW > 0

	local x = coreX

	-- Minimap block (left, raised).
	local mm = rect(x, 0, mapW, S.tall)
	L.panels[#L.panels + 1] = { key = "minimap", x = mm.x, y = mm.y, w = mm.w, h = mm.h }
	local mapX = x + S.pad + S.mapButtonsW + 4
	L.minimap = rect(mapX, S.pad, S.map, S.map)
	L.zoneText = rect(mapX, S.pad + S.map + 2, S.map, 14)
	L.minimapButtons = rect(x + S.pad, S.pad, S.mapButtonsW, S.map)
	x = x + mapW

	-- Chat block (wide/superwide only).
	if chatW > 0 then
		L.panels[#L.panels + 1] = { key = "chat", x = x, y = 0, w = chatW, h = S.mid }
		L.insets[#L.insets + 1] = { key = "chat", x = x + 10, y = 10, w = chatW - 20, h = S.mid - 26 }
		-- 44 on the left leaves room for the chat menu buttons beside the frame
		L.chat = rect(x + 44, 40, chatW - 60, S.mid - 40 - 40)
		L.chatEdit = rect(x + 12, 12, chatW - 24, 24)
		x = x + chatW
	end

	-- Portrait block, with the faction crest rising above it.
	local pt = rect(x, 0, S.portraitW, S.mid)
	L.panels[#L.panels + 1] = { key = "portrait", x = pt.x, y = pt.y, w = pt.w, h = pt.h }
	local px = x + floor((S.portraitW - S.portrait) / 2)
	L.insets[#L.insets + 1] = { key = "portrait", x = px - 4, y = 52, w = S.portrait + 8, h = S.portrait + 8 }
	L.portrait = rect(px, 56, S.portrait, S.portrait)
	L.healthText = rect(x + 8, 30, S.portraitW - 16, 16)
	L.powerText = rect(x + 8, 12, S.portraitW - 16, 16)
	L.crest = rect(x + floor((S.portraitW - S.crest) / 2), S.mid + 30 - floor(S.crest / 2), S.crest, S.crest)
	x = x + S.portraitW

	-- Info block: name, XP and action bars 2 and 3 on a recessed screen.
	local info = rect(x, 0, infoW, S.low)
	L.info = info
	L.insets[#L.insets + 1] = { key = "info", x = x + 6, y = 10, w = infoW - 12, h = S.low - 26 }
	local innerW = infoW - 2 * S.pad
	local barBtn = max(16, min(S.barBtn, floor((innerW - 11 * S.barGap) / 12)))
	local barsW = 12 * barBtn + 11 * S.barGap
	local barsX = x + floor((infoW - barsW) / 2)
	L.bars.bar3 = grid(barsX, S.pad, 12, 1, barBtn, S.barGap)
	L.bars.bar2 = grid(barsX, S.pad + barBtn + 4, 12, 1, barBtn, S.barGap)
	local xpY = S.pad + 2 * barBtn + 4 + 8
	L.xpBar = rect(barsX, xpY, barsW, 10)
	L.nameText = rect(barsX, xpY + 14, barsW, 18)
	x = x + infoW

	-- Inventory block: the six bag slots in Warcraft III's 2x3 inventory grid.
	L.panels[#L.panels + 1] = { key = "inventory", x = x, y = 0, w = invW, h = S.mid }
	local invGrid = grid(x + S.pad, 0, 2, 3, S.invBtn, S.invGap)
	invGrid.y = floor((S.mid - S.edge - invGrid.h) / 2)
	L.inventory = invGrid
	x = x + invW

	-- Command card: the main action bar as a 4x3 grid (right, raised).
	L.panels[#L.panels + 1] = { key = "command", x = x, y = 0, w = cmdW, h = S.tall }
	L.bars.main = grid(x + S.pad, 24, 4, 3, S.cmdBtn, S.cmdGap)
	L.command = rect(x, 0, cmdW, S.tall)

	L.top = max(S.tall, L.crest.y + L.crest.h)
	L.valley = S.low + 6 -- free space above the info panel

	-- Wings: anything outside the core.
	L.wings = {}
	if coreX > 0 then
		L.wings.left = rect(0, 0, coreX, S.low)
		L.wings.right = rect(coreX + coreW, 0, W - coreX - coreW, S.low)
	end

	-- Bars 4 and 5: in the wings as 6x2 grids when there's room, otherwise
	-- vertical columns on the right edge of the screen.
	local wingGrid = 6 * S.sideBtn + 5 * S.sideGap
	if P.wingBars and coreX >= wingGrid + 2 * S.pad then
		local gy = floor((S.low - S.edge - (2 * S.sideBtn + S.sideGap)) / 2)
		L.bars.bar4 = grid(coreX - S.pad - wingGrid, gy, 6, 2, S.sideBtn, S.sideGap)
		L.bars.bar5 = grid(coreX + coreW + S.pad, gy, 6, 2, S.sideBtn, S.sideGap)
		for _, key in ipairs({ "bar4", "bar5" }) do
			local g = L.bars[key]
			L.insets[#L.insets + 1] = { key = key, x = g.x - 8, y = g.y - 8, w = g.w + 16, h = g.h + 16 }
		end
		L.sideBarsW = 0
	else
		local bottom = S.tall + 48
		local avail = H - bottom - 40
		local size = max(20, min(S.sideBtn, floor((avail - 11 * S.sideGap) / 12)))
		local colH = 12 * size + 11 * S.sideGap
		local y = bottom + floor((avail - colH) / 2)
		L.bars.bar4 = grid(W - 8 - size, y, 1, 12, size, S.sideGap)
		L.bars.bar5 = grid(W - 8 - 2 * size - 4, y, 1, 12, size, S.sideGap)
		L.sideBarsW = 2 * size + 4 + 8
	end

	-- Floating chat (standard profile): above the minimap, clear of the crest.
	if not L.chatInConsole then
		L.chat = rect(coreX + 40, L.top + 36, 400, 150)
		L.chatEdit = rect(coreX + 36, L.top + 6, 408, 24)
	end

	-- Anchors for Blizzard frames we keep but move out of the console's way.
	L.micro = { right = L.command.x + L.command.w - 6, bottom = S.tall + 4, maxW = L.command.w + 60 }
	L.stance = { x = info.x + 10, y = L.valley }
	L.pet = { right = info.x + info.w - 10, y = L.valley }
	L.castBar = { cx = info.x + floor(info.w / 2), y = S.tall + 34 }
	L.extra = { cx = info.x + floor(info.w / 2), y = S.tall + 110 }
	L.override = { cx = coreX + floor(coreW / 2), y = S.low }
	L.tracker = { right = W - 12 - L.sideBarsW, top = H - 190 }

	-- Top bar: menu buttons on the left, the day/night clock hanging from the
	-- middle, resources (gold, bag space, durability) on the right.
	L.topBar = rect(0, H - S.topH, W, S.topH)
	L.topSlot = S.topSlot
	local cx = coreX + floor(coreW / 2)
	-- The dial's centre sits on the bar's trim; the bar hides its upper half.
	local cy = H - S.topH + 8
	L.clock = { cx = cx, cy = cy, radius = S.dialR }
	L.clockFrame = rect(cx - S.clockW / 2, cy + 4 - S.clockH, S.clockW, S.clockH)
	-- The bar is drawn as two runs of topbar slots: one starting at the left of
	-- the core, one ending at its right, meeting under the clock. Buttons and
	-- resources sit in the dark window of one slot each.
	L.topSlotsLeft = coreX
	L.topSlotsRight = coreX + coreW
	local function window(slotX)
		return rect(slotX + 5, H - 25, S.topSlot - 10, 22)
	end
	-- On narrow screens, slots that would run under the clock are left out.
	local clockL, clockR = L.clockFrame.x - 4, L.clockFrame.x + L.clockFrame.w + 4
	L.topButtons = {}
	for i = 1, 4 do
		local r = window(coreX + (i - 1) * S.topSlot)
		L.topButtons[i] = (r.x + r.w <= clockL) and r or false
	end
	L.resources = {}
	for i = 1, 3 do
		local r = window(coreX + coreW - (4 - i) * S.topSlot)
		L.resources[i] = (r.x >= clockR) and r or false
	end
	L.topLimit = H - S.topH - 4 -- frames are kept below this line
	L.centerLimit = L.clockFrame.y - 4 -- ...and centred frames below the clock

	return L
end

return Layout
