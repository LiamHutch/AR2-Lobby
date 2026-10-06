-- Each host's private mode configs (Shared/Private.lua has the shape), in one
-- lobby-owned DataStore keyed "<kind>:<userId>". Loads are one GetAsync per
-- (host, mode) when they first open it in a server; saves are debounced to
-- the per-key write limit and flushed on close.

local dataStoreService = game:GetService("DataStoreService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)

local library = {}

----

-- Roblox refuses writes to the same key more often than this
local WRITE_GAP = 6

-- unpublished Studio has no DataStores; everything stays in memory
local inMemory = runService:IsStudio() and game.GameId == 0

local store = not inMemory and dataStoreService:GetDataStore(protocol.PRIVATE_STORE)

-- [key] = the record to write next, and when it may go
local dirty = {}
local lastWrite = {}
local memory = {}

----

local function keyFor(kind, userId)
	return string.format("%s:%d", kind, userId)
end

local function write(key)
	local record = dirty[key]
	dirty[key] = nil

	if not record then
		return
	end

	if inMemory then
		memory[key] = record

		return
	end

	-- stamped before the call too, so a save made while this one is in
	-- flight (a pasted whitelist adds several in a row) waits its turn
	lastWrite[key] = os.clock()

	local worked, why = pcall(store.SetAsync, store, key, record)
	lastWrite[key] = os.clock()

	if not worked then
		warn("Lobby couldn't save private config", key, why)
	end
end

----

-- the saved record, or nil; `loaded` is false when the read itself failed, so
-- a caller can tell "nothing saved" from "couldn't read"
function library:Load(kind, userId)
	local key = keyFor(kind, userId)

	if inMemory then
		return memory[key], true
	end

	local worked, record = pcall(store.GetAsync, store, key)

	if not worked then
		warn("Lobby couldn't load private config", key, record)

		return nil, false
	end

	return type(record) == "table" and record or nil, true
end

function library:Save(kind, userId, record)
	local key = keyFor(kind, userId)
	local queued = dirty[key] ~= nil

	dirty[key] = record

	if queued then
		return
	end

	task.spawn(function()
		local wait = WRITE_GAP - (os.clock() - (lastWrite[key] or -WRITE_GAP))

		if wait > 0 then
			task.wait(wait)
		end

		write(key)
	end)
end

function library:Flush()
	for key in dirty do
		write(key)
	end
end

game:BindToClose(function()
	library:Flush()
end)

return library
