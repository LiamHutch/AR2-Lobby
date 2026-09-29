local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local memoryStores = game:GetService("MemoryStoreService")
local assetService = game:GetService("AssetService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local maps = require(replicatedStorage.Shared.Maps)

local remotes = replicatedStorage.Remotes

local library = {}

-- [mapKey] = { Online = number, Servers = { { Id, Players, Max, StartedAt } } }
library.Snapshot = {}

-- [mapKey] = placeId inside this universe
library.PlaceByMap = {}

----

local hashMap = memoryStores:GetHashMap(protocol.DIRECTORY_MAP)
local mapByPlace = {}

----

local function listUniversePlaces()
	local universe = {}

	local listed, why = pcall(function()
		local pages = assetService:GetGamePlacesAsync()

		while true do
			for _, place in pages:GetCurrentPage() do
				universe[place.PlaceId] = true
			end

			if pages.IsFinished then
				break
			end

			pages:AdvanceToNextPageAsync()
		end
	end)

	if not listed then
		warn("Lobby could not list universe places:", why)
	end

	return universe, listed
end

-- only places in this universe share our MemoryStore and can be teleported to
local function resolvePlaces()
	local universe, listed = listUniversePlaces()

	for _, map in maps do
		for _, placeId in map.PlaceIds do
			-- unpublished Studio places have no universe; take the first id so
			-- the UI is still usable while building it
			local studioFallback = not listed and runService:IsStudio()

			if universe[placeId] or studioFallback then
				library.PlaceByMap[map.Key] = placeId
				mapByPlace[placeId] = map.Key

				break
			end
		end
	end
end

local function readEntries()
	local entries = {}
	local pages = hashMap:ListItemsAsync(protocol.PAGE_SIZE)

	for _ = 1, protocol.MAX_PAGES do
		for _, item in pages:GetCurrentPage() do
			table.insert(entries, item.value)
		end

		if pages.IsFinished then
			break
		end

		pages:AdvanceToNextPageAsync()
	end

	return entries
end

local function sortServers(a, b)
	local aFull = a.Players >= a.Max
	local bFull = b.Players >= b.Max

	if aFull ~= bFull then
		return bFull
	end

	if a.Players ~= b.Players then
		return a.Players > b.Players
	end

	return a.Id < b.Id
end

local function buildSnapshot(entries)
	local snapshot = {}

	for _, map in maps do
		snapshot[map.Key] = {
			Online = 0,
			Servers = {},
		}
	end

	for _, entry in entries do
		if type(entry) ~= "table" or entry.v ~= protocol.VERSION then
			continue
		end

		local mapKey = mapByPlace[entry.placeId]
		local players = tonumber(entry.players)
		local maxPlayers = tonumber(entry.maxPlayers)

		if mapKey and players and maxPlayers and type(entry.jobId) == "string" then
			local bucket = snapshot[mapKey]
			bucket.Online += players

			table.insert(bucket.Servers, {
				Id = entry.jobId,
				Players = players,
				Max = maxPlayers,
				StartedAt = tonumber(entry.startedAt) or os.time(),
			})
		end
	end

	for _, bucket in snapshot do
		table.sort(bucket.Servers, sortServers)

		for index = #bucket.Servers, protocol.MAX_SERVERS_PER_MAP + 1, -1 do
			bucket.Servers[index] = nil
		end
	end

	return snapshot
end

local function poll()
	local worked, entries = pcall(readEntries)

	if not worked then
		warn("Lobby directory read failed:", entries)

		return
	end

	library.Snapshot = buildSnapshot(entries)
	remotes.Directory:FireAllClients(library.Snapshot)
end

----

function library:HasServer(mapKey, jobId)
	local bucket = self.Snapshot[mapKey]

	if bucket then
		for _, server in bucket.Servers do
			if server.Id == jobId then
				return true
			end
		end
	end

	return false
end

function library:Start()
	resolvePlaces()

	-- clients need to know which maps are live before the first poll lands
	local liveKeys = {}

	for key in self.PlaceByMap do
		table.insert(liveKeys, key)
	end

	replicatedStorage:SetAttribute("LiveMaps", table.concat(liveKeys, ","))

	playersService.PlayerAdded:Connect(function(client)
		remotes.Directory:FireClient(client, self.Snapshot)
	end)

	-- an empty lobby server has nobody to show the list to, so it skips reads;
	-- the 1s tick means the first arrival gets a fresh list almost immediately
	local lastPoll = -math.huge

	task.spawn(function()
		while true do
			if os.clock() - lastPoll >= protocol.POLL_INTERVAL and #playersService:GetPlayers() > 0 then
				lastPoll = os.clock()
				poll()
			end

			task.wait(1)
		end
	end)
end

return library
