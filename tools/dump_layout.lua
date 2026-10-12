-- Usage: lua5.1 tools/dump_layout.lua <width> <theme> [uiScale] [chatUp] [center]
-- Prints the computed console layout (768 units tall) as JSON; used by
-- render_preview.py.
local W, theme = tonumber(arg[1]), arg[2] or "orc"
local s, m, center = tonumber(arg[3]) or 240, tonumber(arg[4]) or 10, arg[5] or "off"
local here = (arg[0]:match("^(.*)[/\\]") or ".")
local ns = {}
assert(loadfile(here .. "/../ReforgedUI/Layout.lua"))("ReforgedUI", ns)
local L = ns.Layout.Compute(W, 768, { s = s, m = m, theme = theme, center = center, zoneTextPos = 1 })
L.byKey = nil
-- The top bar has its own scale (0.75 by default: 1024 units tall).
L.topBar = ns.Layout.ComputeTopBar(W * 1024 / 768, 1024, "auto")

local function encode(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local out = {}
			for i = 1, #v do out[i] = encode(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do out[#out + 1] = string.format("%q:%s", k, encode(v[k])) end
		return "{" .. table.concat(out, ",") .. "}"
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return string.format("%.3f", v)
end
print(encode(L))
