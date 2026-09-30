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
	{ Key = "PlayStation", Short = "PS", Long = "PLAYSTATION", Icon = "" },
	{ Key = "Mobile", Short = "MOBILE", Long = "MOBILE", Icon = "" },
}

library.ByKey = {}

for _, platform in library.List do
	library.ByKey[platform.Key] = platform
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

-- "ok" | "warn" | "blocked"
function library:Support(map, platformKey)
	return map.Platforms and map.Platforms[platformKey] or "ok"
end

return library
