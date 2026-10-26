-- Cross-server listings: a session hosted in one lobby server shows in every
-- other, so a whitelisted player or a friend finds it from whichever lobby
-- server they landed in. Each lobby server keeps its sessions' records in one
-- entry of a sharded DataStore laid out like the server directory (rewritten
-- on change and every LISTING_REFRESH, dropped once cold), and every lobby
-- server with players reads the shards each LISTING_POLL and keeps what isn't
-- its own. Sessions.lua shows those as rows; JOIN on one teleports to the
-- host's lobby server with the follow data an invite uses, so the host's page
-- opens on arrival.
--
-- A DataStore, not MemoryStore: the MemoryStore quota is the whole universe's,
-- shared with the game, and a record per session grew with lobby players.
--
-- Protocol.LISTINGS_STORE, key "<LISTING_SHARD_PREFIX><n>", n = shardFor(jobId):
--   { v, servers = { [jobId] = { at, placeId, sessions = { record, ... } } } }
-- A record:
--   { key, hostId, hostName, visibility, whitelist = { userId, ... }?,
--     row = the session's Row for a stranger, less HostId, Host and Mine }
-- Sessions.lua decides which sessions are worth listing (worthListing).

local dataStores = game:GetService("DataStoreService")
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)

local library = {}

----

-- unpublished Studio has no DataStores
local offline = runService:IsStudio() and game.GameId == 0

local store = not offline and dataStores:GetDataStore(protocol.LISTINGS_STORE)

-- published Studio reads the live listings but doesn't add to them: its
-- sessions can't be joined
local readOnly = runService:IsStudio()

-- the directory's shard rule: (sum of the JobId's bytes) % shards
local function shardFor(jobId)
	local sum = 0

	for index = 1, #jobId do
		sum += string.byte(jobId, index)
	end

	return protocol.LISTING_SHARD_PREFIX .. sum % protocol.LISTING_SHARDS
end

local ownShard = shardFor(game.JobId)

-- [id] = record, the sessions hosted here that other servers may see
local published = {}

-- our entry needs writing; whether the store holds one
local dirty = false
local stored = false
local writing = false
local writtenAt = -math.huge

-- [mode key] = { [hostId] = record } from other servers, as of the last poll
local remote = {}

-- [shard index] = the last read that worked, reused when one fails
local lastShards = {}

-- fires after a poll that changed what's listed
library.Changed = Instance.new("BindableEvent")

for _, mode in private.Modes do
	remote[mode.Key] = {}
end

----

local function idFor(key, hostId)
	return key .. ":" .. hostId
end

function library:Retract(key, hostId)
	local id = idFor(key, hostId)

	if published[id] then
		published[id] = nil
		dirty = true
	end
end

-- a session hosted here changed; `listing` is its Listing():
-- { Visibility, Whitelist, Row }
function library:Publish(key, hostId, hostName, listing)
	if not store or readOnly then
		return
	end

	-- the reader puts these back from the record
	local row = table.clone(listing.Row)
	row.HostId = nil
	row.Host = nil
	row.Mine = nil

	published[idFor(key, hostId)] = {
		key = key,
		hostId = hostId,
		hostName = hostName,
		visibility = listing.Visibility,
		whitelist = #listing.Whitelist > 0 and listing.Whitelist or nil,
		row = row,
	}

	dirty = true
end

-- the other servers' sessions of a mode, [hostId] = record
function library:Remote(key)
	return remote[key] or {}
end

function library:Find(key, hostId)
	return remote[key] and remote[key][hostId] or nil
end

-- whether a record's host whitelisted a user
function library:Whitelisted(record, userId)
	return record.whitelistSet ~= nil and record.whitelistSet[userId] == true
end

----

local function isShard(value)
	return type(value) == "table" and value.v == protocol.LISTING_VERSION and type(value.servers) == "table"
end

local function isEntry(value, now)
	return type(value) == "table" and type(value.at) == "number" and now - value.at <= protocol.LISTING_STALE
		and tonumber(value.placeId) and type(value.sessions) == "table"
end

local function isRecord(value)
	return type(value) == "table" and remote[value.key] ~= nil and tonumber(value.hostId) and type(value.row) == "table"
end

-- our entry in, or out when nothing's left to list; cold entries go too
local function write()
	local sessions = {}

	for _, record in published do
		table.insert(sessions, record)
	end

	writing = true
	dirty = false
	writtenAt = os.clock()

	local worked, why = pcall(store.UpdateAsync, store, ownShard, function(shard)
		local now = os.time()
		shard = isShard(shard) and shard or { v = protocol.LISTING_VERSION, servers = {} }

		for jobId, entry in shard.servers do
			if not isEntry(entry, now) then
				shard.servers[jobId] = nil
			end
		end

		shard.servers[game.JobId] = #sessions > 0 and { at = now, placeId = game.PlaceId, sessions = sessions } or nil

		return shard
	end)

	writing = false

	if worked then
		stored = #sessions > 0
	else
		dirty = true
		warn("Lobby couldn't list its sessions", why)
	end
end

local function poll()
	local budget = dataStores:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)

	-- short on budget: the last list stands
	if budget < protocol.LISTING_SHARDS then
		return
	end

	local fresh = {}
	local newest = {}
	local now = os.time()

	for key in remote do
		fresh[key] = {}
		newest[key] = {}
	end

	for index = 0, protocol.LISTING_SHARDS - 1 do
		local worked, shard = pcall(store.GetAsync, store, protocol.LISTING_SHARD_PREFIX .. index)

		if worked then
			lastShards[index] = shard
		else
			warn("Lobby couldn't read session listings shard", index, shard)
			shard = lastShards[index]
		end

		for jobId, entry in isShard(shard) and shard.servers or {} do
			if jobId ~= game.JobId and isEntry(entry, now) then
				for _, record in entry.sessions do
					if isRecord(record) then
						local hostId = tonumber(record.hostId)

						-- a host listed twice (a server that died with them in it): the fresher one
						if not newest[record.key][hostId] or entry.at > newest[record.key][hostId] then
							record.hostId = hostId
							record.jobId = jobId
							record.placeId = tonumber(entry.placeId)
							record.whitelistSet = {}

							for _, userId in type(record.whitelist) == "table" and record.whitelist or {} do
								if tonumber(userId) then
									record.whitelistSet[tonumber(userId)] = true
								end
							end

							fresh[record.key][hostId] = record
							newest[record.key][hostId] = entry.at
						end
					end
				end
			end
		end
	end

	remote = fresh
	library.Changed:Fire()
end

function library:Start()
	if not store then
		return
	end

	-- the writer: a change after a short gap, a heartbeat while listed
	task.spawn(function()
		while true do
			task.wait(1)

			local since = os.clock() - writtenAt
			local due = (dirty and since >= protocol.LISTING_WRITE_GAP) or (stored and since >= protocol.LISTING_REFRESH)

			if due and not writing then
				if stored or next(published) then
					task.spawn(write)
				else
					-- nothing listed and nothing to list
					dirty = false
				end
			end
		end
	end)

	-- the reader, only while someone is here to see the list
	task.spawn(function()
		local random = Random.new()

		while true do
			if #playersService:GetPlayers() > 0 then
				poll()
			end

			task.wait(protocol.LISTING_POLL * random:NextNumber(0.85, 1.15))
		end
	end)

	game:BindToClose(function()
		-- a write in flight could land after this one and put the entry back
		while writing do
			task.wait()
		end

		if stored then
			table.clear(published)
			write()
		end
	end)
end

return library
