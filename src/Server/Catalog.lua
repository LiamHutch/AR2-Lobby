-- Which lobby this place runs and which maps it offers.
--
--   prod  the public server browser
--   test  the tester lobby in the old AR2 Development Hub's place: reads the
--         hub's directory, writes its grants
--
-- Maps come from the place's own config folders (PlaceConfig.lua), so they
-- can be edited in Studio without the repo. A prod place with no config
-- falls back to Shared/Maps.lua. Access, passwords and single-server locks
-- work the same in both variants; the test maps just use them.
--
-- Clients only ever get PublicInfo for maps they're allowed to see.

local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local marketplaceService = game:GetService("MarketplaceService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)

local library = {}

----

local function pickVariant()
	-- set a LobbyVariant attribute ("test" or "prod") on ServerStorage to try the other one in Studio
	local override = runService:IsStudio() and serverStorage:GetAttribute("LobbyVariant")

	if override == "test" or override == "prod" then
		return override
	end

	return game.PlaceId == protocol.TEST_LOBBY_PLACE_ID and "test" or "prod"
end

library.Variant = pickVariant()
library.IsTest = library.Variant == "test"

local placeConfigLibrary = require(script.Parent.PlaceConfig)
local placeConfig = placeConfigLibrary:Load(library.Variant)

if not placeConfig and library.IsTest then
	warn("Test lobby has no ServerStorage." .. placeConfigLibrary.Roots.test .. ".Active config, so it has no maps")
end

-- group role -> access tier; only maps with an Access list use it
local roleTiers = placeConfig and placeConfig.Tiers or { Group = 0, Roles = {} }

library.Maps = {}
library.ByKey = {}

local sourceMaps = placeConfig and placeConfig.Maps or (library.IsTest and {} or require(replicatedStorage.Shared.Maps))

for _, source in sourceMaps do
	-- place config maps arrive normalised; Maps.lua entries get the same treatment
	local map = placeConfig and source or placeConfigLibrary.Normalize(source)

	if map then
		table.insert(library.Maps, map)
		library.ByKey[map.Key] = map
	end
end

----

-- [player] = tier name
local tiers = {}

-- [player] = { count, windowStart }
local attempts = {}

-- [map.Key] = "Updated Sep 29"; test maps only, filled in after boot
local updated = {}

----

function library:Tier(client)
	if roleTiers.Group == 0 then
		return "Public"
	end

	if tiers[client] then
		return tiers[client]
	end

	local found, role = pcall(client.GetRoleInGroup, client, roleTiers.Group)
	local tier = found and roleTiers.Roles[role] or "Public"

	-- a failed lookup isn't cached, so the next request tries again
	if found then
		tiers[client] = tier
	end

	return tier
end

function library:CanSee(client, map)
	if not map.Access then
		return true
	end

	local tier = self:Tier(client)

	return table.find(map.Access, tier) ~= nil or table.find(map.Access, "Public") ~= nil
end

function library:NeedsPassword(map)
	return map.Secret ~= nil
end

-- true, or false and a status code for the client
function library:CheckPassword(client, map, attempt)
	local password = map.Secret

	if not password then
		return true
	end

	local now = os.clock()
	local record = attempts[client]

	if not record or now - record.windowStart >= 60 then
		record = { count = 0, windowStart = now }
		attempts[client] = record
	end

	if record.count >= protocol.PASSWORD_ATTEMPTS then
		return false, "slow"
	end

	if attempt == password then
		return true
	end

	record.count += 1

	return false, "password"
end

-- what a client may know about a map; never Access or the password itself
function library:PublicInfo(map, live)
	local stats = map.Stats or {}

	if updated[map.Key] then
		stats = table.clone(stats)
		table.insert(stats, { "UPDATED", updated[map.Key] })
	end

	return {
		Key = map.Key,
		Name = map.Name,
		Accent = map.Accent,
		Blurb = map.Blurb,
		Stats = stats,
		Platforms = map.Platforms,
		Images = map.Images,
		Backdrop = map.Backdrop,
		Password = self:NeedsPassword(map),
		SingleServer = map.SingleServer == true,
		Live = live,
	}
end

function library:Forget(client)
	tiers[client] = nil
	attempts[client] = nil
end

-- the old hub showed each test place's last publish date; one web call per place
function library:FetchUpdated()
	if not self.IsTest then
		return
	end

	for _, map in self.Maps do
		local placeId = map.PlaceIds[1]
		local fetched, info = pcall(marketplaceService.GetProductInfo, marketplaceService, placeId)
		local date = fetched and info and info.Updated and info.Updated:match("^(%d+%-%d+%-%d+)")

		if date then
			updated[map.Key] = date
		end
	end
end

return library
