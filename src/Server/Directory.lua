local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local memoryStores = game:GetService("MemoryStoreService")
local assetService = game:GetService("AssetService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local catalog = require(script.Parent.Catalog)
local reserved = require(script.Parent.Reserved)
local mock = require(script.Parent.Mock)

local remotes = replicatedStorage.Remotes

local library = {}

-- [mapKey] = { Online = number, Servers = { { Id, Players, Max, StartedAt, Region } } }
library.Snapshot = {}

-- [mapKey] = placeId inside this universe
library.PlaceByMap = {}

----

-- unpublished Studio has no universe, MemoryStore or teleports; fake the
-- server list so the UI can still be built and demoed
local mocking = runService:IsStudio() and game.GameId == 0

-- prod reads the browser beacon's map; test reads the Hub Beacon's
local directoryName = catalog.IsTest and protocol.HUB_DIRECTORY_MAP or protocol.DIRECTORY_MAP
local entryVersion = catalog.IsTest and protocol.HUB_VERSION or protocol.VERSION

local hashMap = not mocking and memoryStores:GetHashMap(directoryName)
local mapByPlace = {}

local lastPoll = -math.huge
local polling = false

-- [player] = os.clock() of their last refresh request
local lastAsk = {}

----

local function listUniversePlaces()
	local universe = {}

	if mocking then
		return universe, false
	end

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

	-- with no universe to check against, take each map's first id so the UI
	-- is still usable in Studio
	local studioFallback = mocking or (not listed and runService:IsStudio())

	for _, map in catalog.Maps do
		for _, placeId in map.PlaceIds do
			if universe[placeId] or studioFallback then
				library.PlaceByMap[map.Key] = placeId
				mapByPlace[placeId] = map.Key

				break
			end
		end
	end
end

local function readEntries()
	if mocking then
		local places = {}

		for mapKey, placeId in library.PlaceByMap do
			-- a single-server map only ever has the one server
			table.insert(places, { placeId, catalog.ByKey[mapKey].SingleServer and 1 or nil })
		end

		return mock:Read(places, entryVersion)
	end

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

-- a single-server map only shows its shared reserved server, not stray
-- reserved servers the same place might also be running
local function belongs(map, entry)
	if not map.SingleServer then
		return true
	end

	local reservedId = reserved:Known(entry.placeId)

	return reservedId == nil or entry.privateServerId == reservedId
end

local function buildSnapshot(entries)
	local snapshot = {}

	for _, map in catalog.Maps do
		snapshot[map.Key] = {
			Online = 0,
			Servers = {},
		}
	end

	for _, entry in entries do
		if type(entry) ~= "table" or entry.v ~= entryVersion then
			continue
		end

		local mapKey = mapByPlace[entry.placeId]
		local players = tonumber(entry.players)
		local maxPlayers = tonumber(entry.maxPlayers)

		if mapKey and players and maxPlayers and type(entry.jobId) == "string" and belongs(catalog.ByKey[mapKey], entry) then
			local bucket = snapshot[mapKey]
			bucket.Online += players

			table.insert(bucket.Servers, {
				Id = entry.jobId,
				Players = players,
				Max = maxPlayers,
				StartedAt = tonumber(entry.startedAt) or os.time(),
				Region = type(entry.region) == "string" and entry.region:sub(1, 24) or nil,
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

-- each player only hears about the maps they may see (the test lobby hides
-- maps by group role), so this is one FireClient per player, not a broadcast
local function send(client)
	local visible = {}
	local servers = {}

	for _, map in catalog.Maps do
		if catalog:CanSee(client, map) then
			table.insert(visible, catalog:PublicInfo(map, library.PlaceByMap[map.Key] ~= nil))
			servers[map.Key] = library.Snapshot[map.Key]
		end
	end

	if client.Parent then
		remotes.Directory:FireClient(client, { Maps = visible, Servers = servers })
	end
end

local function sendAll()
	for _, client in playersService:GetPlayers() do
		-- the first send for a player waits on their group role
		task.spawn(send, client)
	end
end

local function poll()
	if polling then
		return
	end

	polling = true
	lastPoll = os.clock()

	local worked, entries = pcall(readEntries)

	polling = false

	if not worked then
		warn("Lobby directory read failed:", entries)

		return
	end

	library.Snapshot = buildSnapshot(entries)
	sendAll()
end

local function onRefresh(client)
	local now = os.clock()

	if now - (lastAsk[client] or -math.huge) < protocol.REFRESH_COOLDOWN then
		return
	end

	lastAsk[client] = now

	if now - lastPoll >= protocol.REFRESH_MIN_AGE then
		poll()
	else
		send(client)
	end
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

function library:Server(mapKey, jobId)
	local bucket = self.Snapshot[mapKey]

	for _, server in bucket and bucket.Servers or {} do
		if server.Id == jobId then
			return server
		end
	end

	return nil
end

function library:Start()
	resolvePlaces()

	if catalog.IsTest and not mocking then
		local placeIds = {}

		for mapKey, placeId in self.PlaceByMap do
			if catalog.ByKey[mapKey].SingleServer then
				table.insert(placeIds, placeId)
			end
		end

		reserved:Prefetch(placeIds)

		task.spawn(function()
			catalog:FetchUpdated()
			sendAll()
		end)
	end

	playersService.PlayerAdded:Connect(send)

	for _, client in playersService:GetPlayers() do
		task.spawn(send, client)
	end

	playersService.PlayerRemoving:Connect(function(client)
		lastAsk[client] = nil
		catalog:Forget(client)
	end)

	remotes.Refresh.OnServerEvent:Connect(onRefresh)

	-- an empty lobby server has nobody to show the list to, so it skips reads;
	-- the 1s tick means the first arrival gets a fresh list almost immediately
	task.spawn(function()
		while true do
			if os.clock() - lastPoll >= protocol.POLL_INTERVAL and #playersService:GetPlayers() > 0 then
				poll()
			end

			task.wait(1)
		end
	end)
end

return library
