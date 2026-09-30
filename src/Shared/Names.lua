-- Stable, readable names for game servers, made from their JobId. Every
-- client gets the same name for the same server with nothing extra sent.

local ADJECTIVES = {
	"Rusted", "Hollow", "Quiet", "Pale", "Broken", "Grey", "Burnt", "Sunken",
	"Iron", "Cold", "Ashen", "Silent", "Lonely", "Frozen", "Bitter", "Crooked",
	"Faded", "Muddy", "Weary", "Empty", "Distant", "Northern", "Southern", "Low",
	"Old", "Dusty", "Smoky", "Stray", "Hidden", "Forgotten", "Tattered", "Narrow",
	"Salted", "Copper", "Timber", "Scorched", "Boarded", "Flooded", "Overgrown", "Rolling",
}

local NOUNS = {
	"Lantern", "Harbor", "Pines", "Mile", "Culvert", "Signal", "Compass", "Orchard",
	"Diner", "Rail", "Chapel", "Ridge", "Crossing", "Quarry", "Silo", "Depot",
	"Bridge", "Creek", "Ferry", "Watchtower", "Motel", "Pier", "Mill", "Junction",
	"Radio", "Barn", "Tunnel", "Outpost", "Lighthouse", "Highway", "Pass", "Marsh",
	"Refinery", "Checkpoint", "Garage", "Freight", "Hangar", "Bunker", "Cabin", "Beacon",
}

local library = {}

----

-- 32-bit FNV-1a; the multiply is split so it stays exact in a double
local function hash(text)
	local value = 2166136261

	for index = 1, #text do
		value = bit32.bxor(value, string.byte(text, index))
		value = (bit32.lshift(value, 24) + value * 403) % 4294967296
	end

	return value
end

----

function library:ForJob(jobId)
	local value = hash(jobId)

	return ADJECTIVES[value % #ADJECTIVES + 1] .. " " .. NOUNS[(value // #ADJECTIVES) % #NOUNS + 1]
end

-- first and last four characters, e.g. "9f2c…41ab"
function library:ShortId(jobId)
	if #jobId <= 9 then
		return jobId
	end

	return jobId:sub(1, 4) .. "…" .. jobId:sub(-4)
end

return library
