-- Cross-server listings: a session hosted in one lobby server shows in every
-- other, so a whitelisted player or a friend finds it from whichever lobby
-- server they landed in. The hosting server writes a record per session to a
-- MemoryStore sorted map while the session lives (rewritten on change and
-- every LISTING_REFRESH, TTL LISTING_TTL, removed when it ends), and every
-- lobby server with players reads the map each LISTING_POLL (a sorted map
-- lists in one range read; a hash map's listing walks every partition) and
-- keeps what isn't its own. Sessions.lua shows those as rows; JOIN on one
-- teleports to the host's lobby server with the follow data an invite uses,
-- so the host's page opens on arrival.
--
-- A record (Protocol.LISTINGS_MAP, key "<mode key>:<hostId>"):
--   { v, key, hostId, hostName, jobId, placeId, at, visibility,
--     whitelist = { userId, ... }, row = the session's Row for a stranger }

local memoryStores = game:GetService("MemoryStoreService")
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)

local library = {}

----

-- seconds between rewrites of a changed record: edits come in bursts
local WRITE_GAP = 5

-- pages of 200 a poll reads at most
local PAGE_CAP = 3

-- unpublished Studio has no MemoryStore
local offline = runService:IsStudio() and game.GameId == 0

local map = not offline and memoryStores:GetSortedMap(protocol.LISTINGS_MAP)

-- [id] = { Record, Dirty, WrittenAt } for the sessions hosted here
local published = {}

-- [mode key] = { [hostId] = record } from other servers, as of the last poll
local remote = {}

-- fires after a poll that changed what's listed
library.Changed = Instance.new("BindableEvent")

for _, mode in private.Modes do
	remote[mode.Key] = {}
end

----

local function idFor(key, hostId)
	return key .. ":" .. hostId
end

local function write(id, entry)
	entry.Dirty = false
	entry.WrittenAt = os.clock()
	entry.Record.at = os.time()

	local worked, why = pcall(map.SetAsync, map, id, entry.Record, protocol.LISTING_TTL)

	if not worked then
		warn("Lobby couldn't list a session", id, why)
	end
end

-- the record for a session hosted here, written soon; `listing` is the
-- session's Listing(): { Visibility, Whitelist, Row }
function library:Publish(key, hostId, hostName, listing)
	if not map then
		return
	end

	local id = idFor(key, hostId)
	local record = {
		v = protocol.LISTING_VERSION,
		key = key,
		hostId = hostId,
		hostName = hostName,
		jobId = game.JobId,
		placeId = game.PlaceId,
		at = os.time(),
		visibility = listing.Visibility,
		whitelist = listing.Whitelist,
		row = listing.Row,
	}

	local entry = published[id]

	if entry then
		entry.Record = record
		entry.Dirty = true
	else
		published[id] = { Record = record, Dirty = true, WrittenAt = -WRITE_GAP }
	end
end

function library:Retract(key, hostId)
	local id = idFor(key, hostId)

	if not map or not published[id] then
		return
	end

	published[id] = nil

	task.spawn(function()
		pcall(map.RemoveAsync, map, id)
	end)
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

local function isRecord(value)
	return type(value) == "table" and value.v == protocol.LISTING_VERSION and remote[value.key] ~= nil
		and tonumber(value.hostId) and type(value.jobId) == "string" and tonumber(value.placeId)
		and type(value.row) == "table" and type(value.at) == "number"
end

local function poll()
	local fresh = {}

	for key in remote do
		fresh[key] = {}
	end

	local worked, why = pcall(function()
		local after = nil

		for _ = 1, PAGE_CAP do
			local items = map:GetRangeAsync(Enum.SortDirection.Ascending, 200, after)

			for _, item in items do
				local record = item.value

				if isRecord(record) and record.jobId ~= game.JobId and os.time() - record.at <= protocol.LISTING_TTL then
					record.hostId = tonumber(record.hostId)
					record.placeId = tonumber(record.placeId)
					record.whitelistSet = {}

					for _, userId in type(record.whitelist) == "table" and record.whitelist or {} do
						if tonumber(userId) then
							record.whitelistSet[tonumber(userId)] = true
						end
					end

					fresh[record.key][record.hostId] = record
				end
			end

			if #items < 200 then
				break
			end

			after = items[#items].key
		end
	end)

	if not worked then
		warn("Lobby couldn't read the session listings", why)

		return
	end

	remote = fresh
	library.Changed:Fire()
end

function library:Start()
	if not map then
		return
	end

	-- the writer: changed records after a short gap, every record on the refresh
	task.spawn(function()
		while true do
			task.wait(1)

			local now = os.clock()

			for id, entry in published do
				local due = (entry.Dirty and now - entry.WrittenAt >= WRITE_GAP) or now - entry.WrittenAt >= protocol.LISTING_REFRESH

				if due then
					task.spawn(write, id, entry)
				end
			end
		end
	end)

	-- the reader, only while someone is here to see the list
	task.spawn(function()
		while true do
			if #playersService:GetPlayers() > 0 then
				poll()
			end

			task.wait(protocol.LISTING_POLL)
		end
	end)

	game:BindToClose(function()
		for id in published do
			pcall(map.RemoveAsync, map, id)
		end
	end)
end

return library
