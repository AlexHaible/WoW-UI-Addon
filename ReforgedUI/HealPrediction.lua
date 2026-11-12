local _, ns = ...

-- Incoming heals on the health bars, as the game's own unit frames show
-- them: the player's own heals in a bright teal, everyone else's in a darker
-- one, both running on from the end of the health fill.
--
-- The amounts come from the client's heal prediction calculator where it
-- has one (UnitGetDetailedHealPrediction), which already clamps them to the
-- missing health, else from UnitGetIncomingHeals. In instances they can be
-- secret: they are then only ever handed to status bars, never compared or
-- added up. The bars sit in a frame that clips them to the health bar, so
-- an unclamped amount can't spill past its end.

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- The classic unit frames' colours (UnitFrame.xml).
local MINE = { 0, 0.827, 0.765 }
local OTHERS = { 0, 0.631, 0.557 }

local calc -- false when the client has none
local function calculator()
	if calc == nil then
		calc = false
		if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
			local ok, c = pcall(CreateUnitHealPredictionCalculator)
			if ok and c then
				local mode = Enum and Enum.UnitIncomingHealClampMode and Enum.UnitIncomingHealClampMode.MissingHealth
				if mode and c.SetIncomingHealClampMode then
					pcall(c.SetIncomingHealClampMode, c, mode)
				end
				calc = c
			end
		end
	end
	return calc or nil
end

-- Not secret (nil counts as plain here).
local function plain(v)
	return not ns.IsSecret(v)
end

-- The player's own incoming heals on `unit` and everyone else's. Never nil;
-- either may be secret.
function ns:IncomingHeals(unit)
	local c = calculator()
	if c then
		local ok, mine, others = pcall(function()
			UnitGetDetailedHealPrediction(unit, "player", c)
			local _, fromMe, fromOthers = c:GetIncomingHeals()
			return fromMe, fromOthers
		end)
		if ok and (not plain(mine) or mine ~= nil) and (not plain(others) or others ~= nil) then
			return mine, others
		end
	end
	if not UnitGetIncomingHeals then
		return 0, 0
	end
	local ok, all, mine = pcall(function()
		return UnitGetIncomingHeals(unit), UnitGetIncomingHeals(unit, "player")
	end)
	if not ok then
		return 0, 0
	end
	if plain(all) and plain(mine) then
		all, mine = all or 0, mine or 0
		if mine > all then
			mine = all
		end
		return mine, all - mine
	end
	-- Secret: no way to split them, so all of it in the others' colour.
	if plain(all) and all == nil then
		return 0, 0
	end
	return 0, all
end

local function makeBar(parent, colour)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture(BAR_TEXTURE)
	b:SetStatusBarColor(colour[1], colour[2], colour[3], 1)
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	return b
end

-- Gives a health status bar its incoming heal bars. Its text, if any, is
-- moved onto a frame above them so heals never cover the numbers.
function ns:AddHealPrediction(bar)
	if bar.heals then
		return bar.heals
	end
	local level = bar:GetFrameLevel()
	local clip = CreateFrame("Frame", nil, bar)
	clip:SetAllPoints(bar)
	clip:SetFrameLevel(level + 1)
	if clip.SetClipsChildren then
		clip:SetClipsChildren(true)
	end
	local heals = { clip = clip }
	heals.mine = makeBar(clip, MINE)
	heals.others = makeBar(clip, OTHERS)
	local function chain(b, after)
		b:SetPoint("TOPLEFT", after, "TOPRIGHT")
		b:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
	end
	chain(heals.mine, bar:GetStatusBarTexture())
	chain(heals.others, heals.mine:GetStatusBarTexture())
	-- As wide as the health bar, so an amount is measured on its scale.
	local function fit()
		local w = bar:GetWidth()
		if w and plain(w) and w > 0 then
			heals.mine:SetWidth(w)
			heals.others:SetWidth(w)
		end
	end
	bar:HookScript("OnSizeChanged", fit)
	fit()
	if bar.text then
		local top = CreateFrame("Frame", nil, bar)
		top:SetAllPoints(bar)
		top:SetFrameLevel(level + 2)
		bar.text:SetParent(top)
		heals.top = top
	end
	bar.heals = heals
	return heals
end

-- Shows `unit`'s incoming heals on a bar given them by AddHealPrediction.
-- Call it wherever the bar's health is set; `max` is the health maximum the
-- bar was given (looked up when left out).
function ns:UpdateHealPrediction(bar, unit, max)
	local heals = bar.heals
	if not heals then
		return
	end
	if max == nil then
		max = UnitHealthMax(unit)
	end
	local mine, others = self:IncomingHeals(unit)
	heals.mine:SetMinMaxValues(0, max)
	heals.mine:SetValue(mine)
	heals.others:SetMinMaxValues(0, max)
	heals.others:SetValue(others)
end
