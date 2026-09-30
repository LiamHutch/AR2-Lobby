-- The one shared reserved server behind each single-server map (the test
-- lobby's "single server lock"). Same DataStore and key format as the old
-- AR2 Development Hub, so the servers it already reserved carry over.

local replicatedStorage = game:GetService("ReplicatedStorage")
local dataStoreService = game:GetService("DataStoreService")
local teleportService = game:GetService("TeleportService")

local protocol = require(replicatedStorage.Shared.Protocol)

local library = {}

----

-- [placeId] = { Code = accessCode, Id = privateServerId }
local cache = {}

local store = nil

local function getStore()
	store = store or dataStoreService:GetDataStore(protocol.RESERVED_STORE)

	return store
end

----

-- yields; errors if the DataStore or ReserveServer call fails
function library:Get(placeId)
	if cache[placeId] then
		return cache[placeId]
	end

	local key = string.format("%d - %d", placeId, protocol.RESERVED_INDEX)
	local info = getStore():GetAsync(key)

	if type(info) ~= "table" or type(info.Code) ~= "string" then
		local code, id = teleportService:ReserveServer(placeId)
		info = { Code = code, Id = id }
		getStore():SetAsync(key, info)
	end

	cache[placeId] = info

	return info
end

-- the private server id if we've looked it up already, without yielding
function library:Known(placeId)
	return cache[placeId] and cache[placeId].Id
end

-- looks everything up at boot so the first join doesn't wait on a DataStore.
-- Yields until every lookup is done (failed ones included) or `timeout` passes
function library:Prefetch(placeIds, timeout)
	local pending = #placeIds
	local started = os.clock()

	for _, placeId in placeIds do
		task.spawn(function()
			local worked, why = pcall(self.Get, self, placeId)

			if not worked then
				warn("Lobby couldn't get the reserved server for", placeId, why)
			end

			pending -= 1
		end)
	end

	while pending > 0 and os.clock() - started < (timeout or 10) do
		task.wait(0.2)
	end
end

return library
