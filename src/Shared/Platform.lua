-- Which platform this client is on, for the per-map support notices in
-- Maps.lua. Client-only. This is advisory: a client could lie about it, which
-- only hurts that client.

local guiService = game:GetService("GuiService")
local userInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local library = {}

-- display order for the chips; Icon is an image id, empty shows Short as text
library.List = {
	{ Key = "PC", Short = "PC", Long = "PC", Icon = "" },
	{ Key = "Xbox", Short = "XBOX", Long = "XBOX", Icon = "" },
	{ Key = "PS4", Short = "PS4", Long = "PS4", Icon = "" },
	{ Key = "PS5", Short = "PS5", Long = "PS5", Icon = "" },
	{ Key = "Mobile", Short = "MOBILE", Long = "MOBILE", Icon = "" },
}

-- what Detect can return but has no chip of its own: Roblox doesn't tell
-- scripts a PS4 from a PS5, so a PlayStation client is either
library.Groups = {
	PlayStation = { Long = "PLAYSTATION", Covers = { "PS4", "PS5" } },
}

library.ByKey = {}

for _, platform in library.List do
	library.ByKey[platform.Key] = platform
end

for key, group in library.Groups do
	library.ByKey[key] = { Key = key, Long = group.Long }
end

----

function library:Detect()
	-- set ReplicatedStorage's DebugPlatform attribute in Studio to preview another platform
	local override = runService:IsStudio() and replicatedStorage:GetAttribute("DebugPlatform")

	if override and self.ByKey[override] then
		return override
	end

	if guiService:IsTenFootInterface() then
		-- PlayStation pads name their face buttons by shape
		local named, name = pcall(userInputService.GetStringForKeyCode, userInputService, Enum.KeyCode.ButtonA)

		return (named and name == "ButtonCross") and "PlayStation" or "Xbox"
	end

	if userInputService.TouchEnabled and not userInputService.KeyboardEnabled then
		return "Mobile"
	end

	return "PC"
end

local RANK = { ok = 1, warn = 2, blocked = 3 }

local function level(map, key)
	return map.Platforms and map.Platforms[key] or "ok"
end

-- true if the chip for `chipKey` stands for the detected platform `here`
function library:Covers(here, chipKey)
	local group = self.Groups[here]

	return here == chipKey or (group ~= nil and table.find(group.Covers, chipKey) ~= nil)
end

-- "ok" | "warn" | "blocked", plus the platform name the notice should use.
-- For a group (PlayStation) where the generations differ, it's a warning
-- naming the worse-off one: blocking would lock out the one that works
function library:Support(map, platformKey)
	local group = self.Groups[platformKey]

	if not group then
		return level(map, platformKey), self.ByKey[platformKey] and self.ByKey[platformKey].Long or platformKey
	end

	local best, worst, worstKey = nil, nil, nil

	for _, key in group.Covers do
		local support = level(map, key)

		if not best or RANK[support] < RANK[best] then
			best = support
		end

		if not worst or RANK[support] > RANK[worst] then
			worst, worstKey = support, key
		end
	end

	if best == worst then
		return best, group.Long
	end

	return "warn", self.ByKey[worstKey].Long, worst
end

return library
