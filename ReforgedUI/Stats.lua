-- The four stat icons on the hero screen. Bottom-left is always armour (icon
-- from the chest piece); the other three show, per class, one of: main hand,
-- off hand (block chance and value with a shield), ranged weapon, ammo
-- (yellow under 400, red under 200), spell power, healing, or nothing.
-- Right-click an icon, or use /rui stat, to choose. Hover for details.

local _, ns = ...
local Stats = ns:RegisterModule("stats", {})

local EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
local SPELL_ICON = "Interface\\Icons\\Spell_Fire_FlameBolt"
local HEAL_ICON = "Interface\\Icons\\Spell_Holy_FlashHeal"

local SLOT = { main = 16, offhand = 17, ranged = 18, ammo = 0, armor = 5 }

Stats.KINDS = { "main", "offhand", "ranged", "ammo", "spell", "heal", "none" }
local KIND_NAMES = {
	main = "Main", offhand = "Offhand", ranged = "Ranged", ammo = "Ammo",
	spell = "Spell power", heal = "Heal", none = "None",
}
-- Which cell each configurable position is.
Stats.POSITIONS = { tl = 1, tr = 2, br = 4 }
local POSITION_NAMES = { [1] = "Top left", [2] = "Top right", [4] = "Bottom right" }

local CLASS_DEFAULTS = {
	WARRIOR = { "main", "offhand", "ranged" },
	ROGUE = { "main", "offhand", "ranged" },
	HUNTER = { "main", "ranged", "ammo" },
	DEATHKNIGHT = { "main", "offhand", "none" },
	MONK = { "main", "offhand", "heal" },
	DEMONHUNTER = { "main", "offhand", "none" },
}
local CASTER_DEFAULT = { "main", "spell", "heal" }

local floor, ceil = math.floor, math.ceil
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local function label(text)
	return "|cffffd100" .. text .. "|r"
end

local function range(lo, hi)
	return ("%d - %d"):format(floor(lo), ceil(hi))
end

local function itemIcon(slot, empty)
	return GetInventoryItemTexture("player", slot) or (EMPTY .. empty)
end

local function hasShield()
	local id = GetInventoryItemID("player", SLOT.offhand)
	if not id or not GetItemInfoInstant then
		return false
	end
	local equipLoc = select(4, GetItemInfoInstant(id))
	return equipLoc == "INVTYPE_SHIELD"
end

local function armorReduction(armor)
	local level = UnitLevel("player") or 1
	if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
		return C_PaperDollInfo.GetArmorEffectiveness(armor, level) * 100
	end
	-- Classic formula against an attacker of the player's level.
	local k = level < 60 and (400 + 85 * level) or (467.5 * level - 22167.5)
	return armor / (armor + k) * 100
end

local function spellPower()
	local best = 0
	for school = 2, 7 do
		best = math.max(best, GetSpellBonusDamage and GetSpellBonusDamage(school) or 0)
	end
	return best
end

-- Each returns icon, label, value text and an optional value colour.
local READERS = {}

function READERS.main()
	local lo, hi = UnitDamage("player")
	return itemIcon(SLOT.main, "MainHand"), DAMAGE or "Damage", lo and range(lo, hi) or "-"
end

function READERS.offhand()
	local icon = itemIcon(SLOT.offhand, "SecondaryHand")
	if hasShield() then
		local chance = GetBlockChance and GetBlockChance() or 0
		local value = GetShieldBlock and GetShieldBlock() or 0
		return icon, BLOCK or "Block", ("%.1f%% (%d)"):format(chance, value)
	end
	local _, _, lo, hi = UnitDamage("player")
	if lo and hi and hi > 0 then
		return icon, DAMAGE or "Damage", range(lo, hi)
	end
	return icon, DAMAGE or "Damage", "-"
end

function READERS.ranged()
	local speed, lo, hi = UnitRangedDamage("player")
	local text = (speed and speed > 0 and lo) and range(lo, hi) or "-"
	return itemIcon(SLOT.ranged, "Ranged"), DAMAGE or "Damage", text
end

function READERS.ammo()
	local count = GetInventoryItemID("player", SLOT.ammo) and GetInventoryItemCount("player", SLOT.ammo) or 0
	local color
	if count < 200 then
		color = { 1, 0.2, 0.2 }
	elseif count < 400 then
		color = { 1, 0.82, 0 }
	end
	return itemIcon(SLOT.ammo, "Ammo"), AMMOSLOT or "Ammo", tostring(count), color
end

function READERS.spell()
	return SPELL_ICON, "Spell", tostring(spellPower())
end

function READERS.heal()
	return HEAL_ICON, "Healing", tostring(GetSpellBonusHealing and GetSpellBonusHealing() or 0)
end

function READERS.armor()
	local _, effective = UnitArmor("player")
	effective = effective or 0
	return itemIcon(SLOT.armor, "Chest"), ARMOR or "Armor", ("%.1f%%"):format(armorReduction(effective))
end

----------------------------------------------------------------------------

function Stats:Config()
	local _, classFile = UnitClass("player")
	classFile = classFile or "WARRIOR"
	local db = ns.db.stats
	if not db[classFile] then
		local d = CLASS_DEFAULTS[classFile] or CASTER_DEFAULT
		db[classFile] = { tl = d[1], tr = d[2], br = d[3] }
	end
	return db[classFile]
end

function Stats:KindFor(i)
	if i == 3 then
		return "armor"
	end
	local cfg = self:Config()
	for pos, cell in pairs(Stats.POSITIONS) do
		if cell == i then
			return cfg[pos] or "none"
		end
	end
	return "none"
end

function Stats:Set(pos, kind)
	self:Config()[pos] = kind
	self:Update()
end

local function onEnter(cell)
	local kind = Stats:KindFor(cell.index)
	GameTooltip:SetOwner(cell, "ANCHOR_TOP")
	local slot = SLOT[kind]
	if not (slot and GetInventoryItemID("player", slot) and GameTooltip:SetInventoryItem("player", slot)) then
		GameTooltip:SetText(cell.labelText or "", 1, 1, 1)
	end
	if cell.valueText then
		GameTooltip:AddLine(label((cell.labelText or "") .. ":") .. " " .. cell.valueText, 1, 1, 1)
	end
	if cell.index ~= 3 then
		GameTooltip:AddLine("Right-click to choose what this icon shows.", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function onClick(cell, button)
	if button ~= "RightButton" or cell.index == 3 then
		return
	end
	local pos
	for p, i in pairs(Stats.POSITIONS) do
		if i == cell.index then pos = p end
	end
	local current = Stats:Config()[pos]
	local items = {}
	for _, kind in ipairs(Stats.KINDS) do
		items[#items + 1] = {
			text = KIND_NAMES[kind], checked = current == kind,
			func = function() Stats:Set(pos, kind) end,
		}
	end
	if not ns:ShowMenu(cell, POSITION_NAMES[cell.index] .. " icon", items) then
		ns:Print("use /rui stat " .. pos .. " main|offhand|ranged|ammo|spell|heal|none")
	end
end

function Stats:OnEnable()
	ns.db.stats = ns.db.stats or {}
	local holder = CreateFrame("Frame", "ReforgedUIStats", ns.root)
	holder:SetFrameStrata("LOW")
	holder:SetAllPoints(ns.root)
	self.cells = {}
	for i = 1, 4 do
		local cell = CreateFrame("Button", nil, holder)
		cell.index = i
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetAllPoints()
		cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		cell.bevel = cell:CreateTexture(nil, "OVERLAY")
		cell.bevel:SetAllPoints()
		cell.bevel:SetTexture(ns.MEDIA .. "Common\\bevel")
		cell.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell.text:SetJustifyH("LEFT")
		cell.text:SetJustifyV("MIDDLE")
		cell:RegisterForClicks("RightButtonUp")
		cell:SetScript("OnClick", onClick)
		cell:SetScript("OnEnter", onEnter)
		cell:SetScript("OnLeave", GameTooltip_Hide)
		self.cells[i] = cell
	end
	local update = ns:Throttle(function() self:Update() end, 0.2)
	for _, e in ipairs({
		"UNIT_DAMAGE", "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER",
		"UNIT_RESISTANCES", "UNIT_STATS", "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
		"PLAYER_DAMAGE_DONE_MODS", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
	}) do
		ns:On(e, function(_, unit)
			if unit == nil or unit == "player" then
				update()
			end
		end)
	end
end

function Stats:Update()
	for i, cell in ipairs(self.cells) do
		local kind = self:KindFor(i)
		local reader = READERS[kind]
		local ok, icon, name, value, color = false, nil, nil, nil, nil
		if reader then
			ok, icon, name, value, color = pcall(reader)
		end
		if reader and ok then
			cell.icon:SetTexture(icon)
			cell.labelText, cell.valueText = name, value
			if color then
				value = ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, value)
			end
			cell.text:SetText(label(name .. ":") .. "\n" .. value)
			cell:Show()
			cell.text:Show()
		elseif kind == "none" then
			-- An empty socket that can still be right-clicked.
			cell.icon:SetTexture(nil)
			cell.labelText, cell.valueText = KIND_NAMES.none, nil
			cell:Show()
			cell.text:Hide()
		else
			cell.icon:SetTexture(EMPTY .. "Chest")
			cell.labelText, cell.valueText = name or kind, "-"
			cell.text:SetText("-")
		end
	end
end

function Stats:OnLayout(L)
	for i, cell in ipairs(self.cells) do
		local r = L.stats[i]
		cell:ClearAllPoints()
		cell:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.icon.x, r.icon.y)
		cell:SetSize(r.icon.w, r.icon.h)
		cell.text:ClearAllPoints()
		cell.text:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", r.text.x, r.text.y)
		cell.text:SetSize(r.text.w, r.text.h)
	end
	self:Update()
end
