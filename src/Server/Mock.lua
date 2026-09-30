-- Fake directory entries for unpublished Studio, which has no DataStores and
-- can't teleport. Same shape as what the game's browser beacon writes, so the
-- real snapshot code runs on it. Never used outside Studio.

local httpService = game:GetService("HttpService")

local library = {}

----

local SERVERS_PER_PLACE = 14
local MAX_PLAYERS = 32
-- the game's own geolocation format
local REGIONS = { "Ashburn - Virginia", "Chicago - Illinois", "Los Angeles - California", "London - England", "Frankfurt am Main - Hesse", "Singapore - Singapore", "Sydney - New South Wales" }

local random = Random.new()
local entries = {}

----

local HOSTS = { 1, 156, 261 } -- real accounts, so host names resolve in Studio

local function seed(placeId, count, version, kind)
	for index = 1, count or SERVERS_PER_PLACE do
		local entry = {
			v = version,
			placeId = placeId,
			jobId = httpService:GenerateGUID(false):lower(),
			-- one full server so the dimmed row style shows up
			players = index == 1 and MAX_PLAYERS or random:NextInteger(0, MAX_PLAYERS - 1),
			maxPlayers = MAX_PLAYERS,
			startedAt = os.time() - random:NextInteger(60, 8 * 3600),
			-- mostly the current build, the odd server still on the last one
			placeVersion = index % 4 == 0 and 411 or 412,
			region = REGIONS[random:NextInteger(1, #REGIONS)],
		}

		if kind then
			entry.kind = kind
			entry.hostId = HOSTS[(index - 1) % #HOSTS + 1]
			entry.locked = index == 2
			entry.settings = {
				FirstPersonOnly = index == 3 and "On" or "Off",
				ZombiesEnabled = index == 4 and "Off" or "On",
				LootEnabled = "On",
				TimeOfDayFrozen = "Off",
			}
		end

		table.insert(entries, entry)
	end
end

----

-- places: { { placeId, serverCount?, kind? } }; version matches the directory being faked
function library:Read(places, version)
	if #entries == 0 then
		for _, place in places do
			seed(place[1], place[2], version, place[3])
		end
	end

	-- drift populations a little each poll so the list visibly updates
	for _, entry in entries do
		entry.players = math.clamp(entry.players + random:NextInteger(-2, 2), 0, entry.maxPlayers)
	end

	return entries
end

return library
