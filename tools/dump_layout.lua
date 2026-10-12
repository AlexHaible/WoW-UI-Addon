-- Usage: lua5.1 tools/dump_layout.lua <width> <height> [profile]
-- Prints the computed console layout as JSON (used by render_preview.py).
local W, H, profile = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local here = (arg[0]:match("^(.*)[/\\]") or ".")
local ns = {}
assert(loadfile(here .. "/../ReforgedUI/Layout.lua"))("ReforgedUI", ns)
local L = ns.Layout.Compute(W, H, profile)

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
	return string.format("%.2f", v)
end
print(encode(L))
