-- Platform-only servers. "Any" is a map's public servers, which Roblox
-- matchmakes. Console-only and mobile-only servers have to be reserved
-- servers, so each map keeps a pool of them per Protocol.POOLS name, reserved
-- once and reused forever: an access code boots a fresh instance once the old
-- one has shut down, so a pool only grows to the most servers it has had
-- running at once.
--
-- Every lobby server shares a pool through one DataStore key (Protocol.lua,
-- "Pools"), read at boot and cached. Access codes never leave lobby servers.
-- The directory tells a pool's servers apart by their privateServerId.
--
-- Picking a server: the fullest running one with room, else the lowest slot
-- that isn't running (every lobby picks the same one, so simultaneous joins
-- land together instead of each booting its own), else a new slot. Once the
-- pools are read, a join costs no DataStore calls.

local replicatedStorage = game:GetService("ReplicatedStorage")
local dataStoreService = game:GetService("DataStoreService")
local teleportService = game:GetService("TeleportService")
local httpService = game:GetService("HttpService")

local protocol = require(replicatedStorage.Shared.Protocol)
local mock = require(script.Parent.Mock)

local library = {}

----

-- a teleport that came back GameFull keeps its server out of picks this long
local FULL_HOLD = 60

-- this lobby's own sends count on top of the directory's player count for
-- about as long as the directory takes to catch up (beacon heartbeat + poll)
local SENT_WINDOW = 90

-- a pool's servers with an id we don't know prompt a re-read at most this often
local PROMPT_GAP = 30

-- slots a faked pool starts with in unpublished Studio
local MOCK_SLOTS = 3

-- ["<placeId>:<pool>"] = { placeId, pool, slots = { { code, id } }, byId, readAt, growing }
local pools = {}

-- [privateServerId] = { count, since }: players this lobby sent there lately
local sent = {}

-- [privateServerId] = os.clock() it stops counting as full
local heldFull = {}

local store = nil

----

local function getStore()
	store = store or dataStoreService:GetDataStore(protocol.POOLS_STORE)

	return store
end

local function keyFor(placeId, pool)
	return string.format("%d:%s", placeId, pool)
end

local function getPool(placeId, pool)
	local key = keyFor(placeId, pool)

	pools[key] = pools[key] or {
		placeId = placeId,
		pool = pool,
		slots = {},
		byId = {},
		readAt = nil,
		promptedAt = -math.huge,
		growing = false,
	}

	return pools[key]
end

local function apply(state, value)
	local slots = {}
	local byId = {}

	if type(value) == "table" and value.v == protocol.POOL_VERSION and type(value.slots) == "table" then
		for _, slot in value.slots do
			if type(slot) == "table" and type(slot.code) == "string" and type(slot.id) == "string" and not byId[slot.id] then
				local entry = { code = slot.code, id = slot.id }

				table.insert(slots, entry)
				byId[slot.id] = entry
			end
		end
	end

	state.slots = slots
	state.byId = byId
end

local function fakeSlot()
	return { code = "mock", id = httpService:GenerateGUID(false):lower(), at = os.time() }
end

-- yields; errors if the read fails
local function read(state)
	if mock.Active then
		if not state.readAt then
			local slots = {}

			for _ = 1, MOCK_SLOTS do
				table.insert(slots, fakeSlot())
			end

			apply(state, { v = protocol.POOL_VERSION, slots = slots })
		end
	else
		apply(state, getStore():GetAsync(keyFor(state.placeId, state.pool)))
	end

	state.readAt = os.clock()
end

local function held(id, now)
	return (heldFull[id] or 0) > now
end

local function recentlySent(id, now)
	local record = sent[id]

	return record and now - record.since <= SENT_WINDOW and record.count or 0
end

local function idleSlot(state, running, now)
	for _, slot in state.slots do
		if not running[slot.id] and not held(slot.id, now) then
			return slot
		end
	end

	return nil
end

-- reserves one more server and adds it to the pool; the pool's current
-- slots on success. Yields
local function grow(state)
	if #state.slots >= protocol.POOL_CAP then
		return false
	end

	if mock.Active then
		local slots = table.clone(state.slots)
		table.insert(slots, fakeSlot())
		apply(state, { v = protocol.POOL_VERSION, slots = slots })

		return true
	end

	local code, id = teleportService:ReserveServer(state.placeId)

	local saved = getStore():UpdateAsync(keyFor(state.placeId, state.pool), function(old)
		if type(old) ~= "table" or old.v ~= protocol.POOL_VERSION or type(old.slots) ~= "table" then
			old = { v = protocol.POOL_VERSION, slots = {} }
		end

		-- another lobby may have filled it up meanwhile
		if #old.slots >= protocol.POOL_CAP then
			return nil
		end

		table.insert(old.slots, { code = code, id = id, at = os.time() })

		return old
	end)

	if saved == nil then
		return false
	end

	apply(state, saved)
	state.readAt = os.clock()

	return true
end

----

-- reads each { placeId, pool } so the first join doesn't wait on a
-- DataStore. Yields until every read is done (failed ones included) or
-- `timeout` passes
function library:Prefetch(list, timeout)
	local pending = #list
	local started = os.clock()

	for _, item in list do
		task.spawn(function()
			local worked, why = pcall(read, getPool(item[1], item[2]))

			if not worked then
				warn("Lobby couldn't read the", item[2], "pool for", item[1], why)
			end

			pending -= 1
		end)
	end

	while pending > 0 and os.clock() - started < (timeout or 10) do
		task.wait(0.2)
	end
end

-- the pool a running server belongs to, from its PrivateServerId, or nil
function library:Lookup(placeId, privateServerId)
	for _, pool in protocol.POOLS do
		local state = pools[keyFor(placeId, pool)]

		if state and state.byId[privateServerId] then
			return pool
		end
	end

	return nil
end

-- a directory entry labelled with this pool has an id we don't know: another
-- lobby has grown it since we read it. Re-read, not too often
function library:Prompt(placeId, pool)
	local state = getPool(placeId, pool)

	if os.clock() - state.promptedAt < PROMPT_GAP then
		return
	end

	state.promptedAt = os.clock()

	task.spawn(function()
		local worked, why = pcall(read, state)

		if not worked then
			warn("Lobby couldn't re-read the", pool, "pool for", placeId, why)
		end
	end)
end

-- re-reads pools older than POOL_REFRESH, as far as `budget` GetAsync calls
-- go. Yields
function library:RefreshStale(budget)
	local now = os.clock()

	for _, state in pools do
		if budget <= 0 then
			return
		end

		if state.readAt and now - state.readAt >= protocol.POOL_REFRESH then
			budget -= 1

			local worked, why = pcall(read, state)

			if not worked then
				warn("Lobby couldn't refresh the", state.pool, "pool for", state.placeId, why)
			end
		end
	end
end

-- the pool's slot ids in order (a copy)
function library:Ids(placeId, pool)
	local ids = {}
	local state = pools[keyFor(placeId, pool)]

	for _, slot in state and state.slots or {} do
		table.insert(ids, slot.id)
	end

	return ids
end

-- the slot behind a running pool server, for joining it from the list
function library:Slot(placeId, pool, privateServerId)
	local state = pools[keyFor(placeId, pool)]

	return state and state.byId[privateServerId]
end

-- the slot to send one more player to. running = { [privateServerId] =
-- { Players, Max } } for this pool's servers in the directory. Nil when the
-- pool can't be read or is at POOL_CAP with every server full. Yields
function library:Pick(placeId, pool, running)
	local state = getPool(placeId, pool)

	if not state.readAt then
		local worked, why = pcall(read, state)

		if not worked then
			warn("Lobby couldn't read the", pool, "pool for", placeId, why)

			return nil
		end
	end

	local now = os.clock()
	local best, bestLoad = nil, -1

	for _, slot in state.slots do
		local server = running[slot.id]

		if server and not held(slot.id, now) then
			local load = server.Players + recentlySent(slot.id, now)

			if load < server.Max and load > bestLoad then
				best, bestLoad = slot, load
			end
		end
	end

	if best then
		return best
	end

	-- one grow at a time; whoever waited uses the slot it made
	while state.growing do
		task.wait(0.2)
	end

	local idle = idleSlot(state, running, now)

	if idle then
		return idle
	end

	state.growing = true

	local worked, result = pcall(function()
		-- another lobby may have grown the pool since we read it
		read(state)

		local fresh = idleSlot(state, running, now)

		if fresh or not grow(state) then
			return fresh
		end

		return idleSlot(state, running, now)
	end)

	state.growing = false

	if not worked then
		warn("Lobby couldn't grow the", pool, "pool for", placeId, result)

		return nil
	end

	return result
end

-- counts a player on their way to a slot until the directory catches up
function library:Sent(id)
	local now = os.clock()
	local record = sent[id]

	if not record or now - record.since > SENT_WINDOW then
		record = { count = 0, since = now }
		sent[id] = record
	end

	record.count += 1
end

-- a teleport to this slot came back GameFull
function library:HoldFull(id)
	heldFull[id] = os.clock() + FULL_HOLD
end

return library
