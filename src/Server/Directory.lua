local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local dataStores = game:GetService("DataStoreService")
local assetService = game:GetService("AssetService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local platform = require(replicatedStorage.Shared.Platform)
local catalog = require(script.Parent.Catalog)
local reserved = require(script.Parent.Reserved)
local pools = require(script.Parent.Pools)
local vip = require(script.Parent.Vip)
local mock = require(script.Parent.Mock)

local remotes = replicatedStorage.Remotes

local library = {}

-- [mapKey] = { Online = number, Servers = { server }, Pools = { [pool] = { server } } }
--   server: { Id, Kind, PlaceId, Players, Max, StartedAt, Region?, Location?, Country?, Version?, Pool? }
--           plus HostId, Host?, Locked, Tags for VIP kinds (see Vip.lua)
-- Servers are the Any servers; Pools holds each platform-only pool's running
-- servers (Pools.lua), for every pool the map has
library.Snapshot = {}

-- [mapKey] = placeId inside this universe
library.PlaceByMap = {}

----

-- unpublished Studio has no universe, DataStores or teleports; fake the
-- server list so the UI can still be built and demoed (see Mock.lua)
local mocking = mock.Active

-- prod reads the Browser Beacon's directory; test reads the Hub Beacon's.
-- Both are sharded DataStores (see Protocol.lua)
local directoryName = catalog.IsTest and protocol.HUB_DIRECTORY_STORE or protocol.DIRECTORY_STORE
local shardCount = catalog.IsTest and protocol.HUB_DIRECTORY_SHARDS or protocol.DIRECTORY_SHARDS

local directoryStore = not mocking and dataStores:GetDataStore(directoryName)

-- [shard index] = the last shard read that worked, reused when a read fails
-- so one bad read doesn't blank that shard's servers for a poll
local lastShards = {}

-- [placeId] = { Map = mapKey, Kind = kind }; an entry only counts if it comes
-- from a place of its own kind
local placeInfo = {}

-- [jobId] = the pool server's PrivateServerId, from the last snapshot; kept
-- here so it never goes to clients with the rest of the server
local privateIds = {}

local lastPoll = -math.huge
local polling = false

-- seconds until the next read: the normal interval, or longer while reads
-- are failing (see POLL_BACKOFF_MAX)
local baseInterval = protocol.POLL_INTERVAL
local interval = baseInterval
local random = Random.new()

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

-- only places in this universe share our DataStores and can be teleported to
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

	-- kept for PlaceFor: the private modes resolve their places the same way
	library.universe = universe
	library.studioFallback = studioFallback

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
				local map = catalog.ByKey[info.Map]

				-- a single-server map only ever has the one server
				table.insert(places, { placeId, map.SingleServer and 1 or nil })

				-- every slot but the last running, so one pool join boots a server
				for _, pool in library:MapPools(map) do
					local ids = pools:Ids(placeId, pool)
					table.remove(ids)
					table.insert(places, { placeId, nil, nil, { name = pool, ids = ids } })
				end
			elseif vip.Kinds[info.Kind] then
				table.insert(places, { placeId, 5, info.Kind })
			end
		end

		return mock:Read(places, protocol.DIRECTORY_VERSION)
	end

	-- the lobby's own joins (reserved servers, VIP lookups) share this budget,
	-- so skip the poll rather than starve them
	local budget = dataStores:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)

	if budget < shardCount then
		error(string.format("only %d GetAsync budget left, %d shards to read", budget, shardCount))
	end

	local entries = {}
	local failures = 0
	local now = os.time()

	for index = 0, shardCount - 1 do
		local worked, shard = pcall(directoryStore.GetAsync, directoryStore, protocol.DIRECTORY_SHARD_PREFIX .. index)

		if worked then
			lastShards[index] = shard
		else
			failures += 1
			warn("Lobby directory shard", index, "read failed:", shard)
			shard = lastShards[index]
		end

		local valid = type(shard) == "table" and shard.v == protocol.DIRECTORY_VERSION and type(shard.servers) == "table"

		for jobId, entry in valid and shard.servers or {} do
			-- a server that stopped refreshing is dead, even if its writers
			-- haven't pruned it yet
			if type(entry) == "table" and type(entry.updatedAt) == "number" and now - entry.updatedAt <= protocol.DIRECTORY_STALE then
				entry.jobId = jobId
				table.insert(entries, entry)
			end
		end
	end

	if failures == shardCount then
		error("every directory shard read failed")
	end

	return entries
end

-- the game sends "City - Region" (e.g. "Ashburn - Virginia"); the column only
-- has room for the region, cut on a word boundary if it's still long
local REGION_LENGTH = 22

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

local function text(value)
	return type(value) == "string" and value ~= "" and value or nil
end

-- newer game servers also send location = { area, city, state, country,
-- countryCode, continent }. The column gets "US East · Ashburn", or just the
-- area if that's too long; the footer gets the whole thing. Older servers
-- only have region, and fall back to shortRegion
local function describeLocation(entry)
	local location = type(entry.location) == "table" and entry.location or {}
	-- the game's area is its continent outside the US and Canada, and is
	-- missing if ip-api left the continent out; the country is the next best
	local area = text(location.area) or text(location.continent) or text(location.country)

	if not area then
		return shortRegion(entry.region), nil, nil
	end

	local city = text(location.city)
	local column = city and (area .. " · " .. city) or area

	if utf8.len(column) > REGION_LENGTH then
		column = area
	end

	local parts = {}

	for _, part in { city, text(location.state), text(location.countryCode) } do
		table.insert(parts, part)
	end

	local full = #parts > 0 and (area .. " · " .. table.concat(parts, ", ")) or area

	return column, full, text(location.country)
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

-- [jobId] = true once a hidden server has been logged
local reportedHidden = {}

-- a single-server map only shows its shared reserved server, not stray
-- reserved servers the same place might also be running (the lobby can only
-- send people to the shared one). If the shared one isn't known (its lookup
-- failed), everything shows rather than nothing
local function belongs(map, entry)
	if not map.SingleServer then
		return true
	end

	local reservedId = reserved:Known(entry.placeId)

	if reservedId == nil or entry.privateServerId == reservedId then
		return true
	end

	if not reportedHidden[entry.jobId] then
		reportedHidden[entry.jobId] = true
		print(string.format(
			"Lobby: hiding server %s on %s, it isn't the map's shared server (%s vs %s)",
			tostring(entry.jobId),
			map.Name,
			tostring(entry.privateServerId),
			reservedId
		))
	end

	return false
end

local function buildSnapshot(entries)
	local snapshot = {}
	local ids = {}

	for _, map in catalog.Maps do
		local bucket = {
			Online = 0,
			Servers = {},
			Pools = {},
		}

		for _, pool in library:MapPools(map) do
			bucket.Pools[pool] = {}
		end

		snapshot[map.Key] = bucket
	end

	for _, entry in entries do
		if type(entry) ~= "table" then
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
			-- Region, Location and Country, see describeLocation
			-- game.PlaceVersion; the test directory's Hub Beacon doesn't send it
			Version = tonumber(entry.placeVersion),
		}

		server.Region, server.Location, server.Country = describeLocation(entry)

		local bucket = snapshot[info.Map]
		local list = bucket.Servers

		-- a pool server is known by its PrivateServerId, whatever it calls itself
		local pool = kind == "public" and type(entry.privateServerId) == "string" and pools:Lookup(entry.placeId, entry.privateServerId)

		if pool then
			-- a pool the map no longer offers (its platforms got blocked)
			if not bucket.Pools[pool] then
				continue
			end

			server.Pool = pool
			ids[entry.jobId] = entry.privateServerId
			list = bucket.Pools[pool]
		elseif kind == "public" and type(entry.pool) == "string" and table.find(protocol.POOLS, entry.pool) then
			-- labelled as a pool server we don't know yet: another lobby grew
			-- the pool since we read it. Left out until we have its slot
			pools:Prompt(entry.placeId, entry.pool)

			continue
		elseif kind == "public" then
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

		bucket.Online += players
		table.insert(list, server)
	end

	local function trim(servers)
		table.sort(servers, sortServers)

		for index = #servers, protocol.MAX_SERVERS_PER_MAP + 1, -1 do
			servers[index] = nil
		end
	end

	for _, bucket in snapshot do
		trim(bucket.Servers)

		for _, servers in bucket.Pools do
			trim(servers)
		end
	end

	return snapshot, ids
end

-- each player only hears about the maps they may see (the test lobby hides
-- maps by group role), so this is one FireClient per player, not a broadcast
local function send(client)
	local visible = {}
	local servers = {}

	for _, map in catalog.Maps do
		if catalog:CanSee(client, map) then
			local public = catalog:PublicInfo(map, library.PlaceByMap[map.Key] ~= nil)
			public.Pools = library:MapPools(map)

			table.insert(visible, public)
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

	-- ±15% so lobby servers that started together drift apart
	local jitter = random:NextNumber(0.85, 1.15)

	if not worked then
		-- back off instead of adding to the pressure; players keep the last list
		interval = math.min(math.max(interval, baseInterval) * 2, protocol.POLL_BACKOFF_MAX) * jitter
		warn(string.format("Lobby directory read failed, next try in %.0fs: %s", interval, tostring(entries)))

		return
	end

	interval = baseInterval * jitter
	library.Snapshot, privateIds = buildSnapshot(entries)
	sendAll()

	-- whatever GetAsync budget the directory left, beyond a poll's worth kept
	-- back for joins
	if not mocking then
		local budget = dataStores:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
		pools:RefreshStale(budget - shardCount)
	end
end

----

function library:Server(mapKey, jobId)
	local bucket = self.Snapshot[mapKey]

	if not bucket then
		return nil
	end

	for _, server in bucket.Servers do
		if server.Id == jobId then
			return server
		end
	end

	for _, servers in bucket.Pools do
		for _, server in servers do
			if server.Id == jobId then
				return server
			end
		end
	end

	return nil
end

function library:HasServer(mapKey, jobId)
	return self:Server(mapKey, jobId) ~= nil
end

-- the platform-only pools a map offers: all of them, except on single-server
-- maps (one shared server) and pools whose every platform is blocked there
function library:MapPools(map)
	local list = {}

	if not map.SingleServer then
		for _, pool in protocol.POOLS do
			if platform:PoolOpen(map, pool) then
				table.insert(list, pool)
			end
		end
	end

	return list
end

-- { [privateServerId] = server } for a pool's running servers, for Pools:Pick
function library:PoolRunning(mapKey, pool)
	local bucket = self.Snapshot[mapKey]
	local running = {}

	for _, server in bucket and bucket.Pools[pool] or {} do
		local id = privateIds[server.Id]

		if id then
			running[id] = server
		end
	end

	return running
end

-- a listed pool server's PrivateServerId
function library:PrivateId(jobId)
	return privateIds[jobId]
end

-- the map key a public place belongs to, or nil (private places and the
-- lobby itself aren't maps)
function library:MapForPlace(placeId)
	local info = placeInfo[placeId]

	return info and info.Kind == "public" and info.Map or nil
end

-- the first of placeIds in this universe (Studio without one takes the
-- first), or nil. Valid after Resolve
function library:PlaceFor(placeIds)
	for _, placeId in placeIds do
		if (self.universe and self.universe[placeId]) or self.studioFallback then
			return placeId
		end
	end

	return nil
end

local resolved = false

-- which place each map uses in this universe; safe to call more than once
function library:Resolve()
	if not resolved then
		resolved = true
		resolvePlaces()
	end
end

function library:Start()
	self:Resolve()

	local placeIds = {}
	local poolList = {}

	for mapKey, placeId in self.PlaceByMap do
		for _, pool in self:MapPools(catalog.ByKey[mapKey]) do
			table.insert(poolList, { placeId, pool })
		end
	end

	if catalog.IsTest and not mocking then
		for mapKey, placeId in self.PlaceByMap do
			if catalog.ByKey[mapKey].SingleServer then
				table.insert(placeIds, placeId)
			end
		end

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
		catalog:Forget(client)
	end)

	-- an empty lobby server has nobody to show the list to, so it skips reads;
	-- the 1s tick means the first arrival gets a fresh list almost immediately
	task.spawn(function()
		-- the first read waits for the shared servers' ids, so a stray server
		-- doesn't show on the first poll and vanish on the next
		reserved:Prefetch(placeIds, 10)

		-- and the pools, so their servers don't list as Any servers first
		pools:Prefetch(poolList, 10)

		while true do
			if os.clock() - lastPoll >= interval and #playersService:GetPlayers() > 0 then
				poll()
			end

			task.wait(1)
		end
	end)
end

return library
