local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local memoryStores = game:GetService("MemoryStoreService")
local assetService = game:GetService("AssetService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local catalog = require(script.Parent.Catalog)
local reserved = require(script.Parent.Reserved)
local vip = require(script.Parent.Vip)
local mock = require(script.Parent.Mock)

local remotes = replicatedStorage.Remotes

local library = {}

-- [mapKey] = { Online = number, Servers = { server } }
--   server: { Id, Kind, PlaceId, Players, Max, StartedAt, Region? }
--           plus HostId, Host?, Locked, Tags for VIP kinds (see Vip.lua)
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

-- [placeId] = { Map = mapKey, Kind = kind }; an entry only counts if it comes
-- from a place of its own kind
local placeInfo = {}

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

	local function first(placeIds)
		for _, placeId in placeIds do
			if universe[placeId] or studioFallback then
				return placeId
			end
		end

		return nil
	end

	for _, map in catalog.Maps do
		local placeId = first(map.PlaceIds)

		if placeId then
			library.PlaceByMap[map.Key] = placeId
			placeInfo[placeId] = { Map = map.Key, Kind = "public" }
		end

		for kind, placeIds in map.Vip or {} do
			local vipPlace = first(placeIds)

			if vipPlace then
				placeInfo[vipPlace] = { Map = map.Key, Kind = kind }
			end
		end
	end
end

local function readEntries()
	if mocking then
		local places = {}

		for placeId, info in placeInfo do
			if info.Kind == "public" then
				-- a single-server map only ever has the one server
				table.insert(places, { placeId, catalog.ByKey[info.Map].SingleServer and 1 or nil })
			elseif vip.Kinds[info.Kind] then
				table.insert(places, { placeId, 5, info.Kind })
			end
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

-- the game sends "City - Region" (e.g. "Ashburn - Virginia"); the column only
-- has room for the region, cut on a word boundary if it's still long
local REGION_LENGTH = 18

local function shortRegion(region)
	if type(region) ~= "string" or region == "" then
		return nil
	end

	region = region:match(" %- (.+)$") or region

	if #region <= REGION_LENGTH then
		return region
	end

	local cut = region:sub(1, REGION_LENGTH):match("^(.*%S)%s") or region:sub(1, REGION_LENGTH)

	return cut
end

local function sortServers(a, b)
	local aFull = a.Players >= a.Max
	local bFull = b.Players >= b.Max

	if aFull ~= bFull then
		return bFull
	end

	-- public servers first, then VIP
	if a.Kind ~= b.Kind then
		return a.Kind == "public"
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

		local kind = type(entry.kind) == "string" and entry.kind or "public"
		local info = placeInfo[entry.placeId]
		local players = tonumber(entry.players)
		local maxPlayers = tonumber(entry.maxPlayers)

		-- skip kinds this lobby doesn't list yet, and entries whose kind
		-- doesn't match the place they came from
		if not info or info.Kind ~= kind or not vip.Kinds[kind] then
			continue
		end

		if not (players and maxPlayers and type(entry.jobId) == "string") then
			continue
		end

		local server = {
			Id = entry.jobId,
			Kind = kind,
			PlaceId = entry.placeId,
			Players = players,
			Max = maxPlayers,
			StartedAt = tonumber(entry.startedAt) or os.time(),
			Region = shortRegion(entry.region),
		}

		if kind == "public" then
			if not belongs(catalog.ByKey[info.Map], entry) then
				continue
			end
		else
			local extra = vip:Describe(kind, entry)

			if not extra then
				continue
			end

			for key, value in extra do
				server[key] = value
			end
		end

		local bucket = snapshot[info.Map]
		bucket.Online += players
		table.insert(bucket.Servers, server)
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
