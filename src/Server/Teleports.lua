local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local teleportService = game:GetService("TeleportService")
local memoryStores = game:GetService("MemoryStoreService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local platform = require(replicatedStorage.Shared.Platform)
local catalog = require(script.Parent.Catalog)
local reserved = require(script.Parent.Reserved)
local pools = require(script.Parent.Pools)
local vip = require(script.Parent.Vip)

local remotes = replicatedStorage.Remotes

local library = {}

----

-- Studio can't teleport, so fail on the first try instead of after the backoff
local RETRIES = runService:IsStudio() and 1 or 3
local PENDING_TIMEOUT = 20
local MAX_PASSWORD = 100

-- [player] = the teleport in flight: { attempt, slotId?, retry?, retried? }
local pending = {}

local grants = nil

----

-- "joining" | "teleporting" | "full" | "closed" | "failed" | "denied"
-- | "password" | "slow" | "unavailable" | "locked" | "banned" | "unsupported"
-- title (the map's) goes with "teleporting" for the loading screen
local function sendStatus(client, code, title)
	remotes.Status:FireClient(client, code, title)
end

local function clearPending(client, token)
	if pending[client] == token then
		pending[client] = nil
	end
end

-- test places only admit players holding a grant for that place (game repo:
-- src/Server/Test server lock.server.lua); it's single use and expires
local function writeGrant(client, placeId)
	grants = grants or memoryStores:GetHashMap(protocol.HUB_GRANTS_MAP)

	return pcall(function()
		grants:SetAsync(tostring(client.UserId), {
			v = protocol.HUB_VERSION,
			placeId = placeId,
			grantedAt = os.time(),
		}, protocol.HUB_GRANT_TTL)
	end)
end

-- slot: the pool server's slot (Pools.lua) when going to a platform-only server
local function buildOptions(map, placeId, jobId, server, slot, pool)
	local options = Instance.new("TeleportOptions")

	-- test places read the hub's teleport data (game repo: Hub Beacon)
	if catalog.IsTest then
		options:SetTeleportData({
			source = protocol.HUB_SOURCE,
			v = protocol.HUB_VERSION,
			pool = pool,
		})
	else
		options:SetTeleportData({
			source = protocol.SOURCE,
			v = protocol.VERSION,
			map = map.Key,
			kind = server and server.Kind or nil,
			hostId = server and server.HostId or nil,
			-- a pool server learns its pool from this (Protocol.lua, "Pools")
			pool = pool,
		})
	end

	-- VIP servers are reserved; Vip:Prepare adds the access code
	if server and server.Kind ~= "public" then
		return options
	end

	if slot then
		options.ReservedServerAccessCode = slot.code
	elseif map.SingleServer then
		local worked, info = pcall(reserved.Get, reserved, placeId)

		if not worked then
			warn("Lobby couldn't get the reserved server for", map.Key, info)

			return nil
		end

		options.ReservedServerAccessCode = info.Code
	elseif jobId then
		-- no instance id means Roblox matchmakes into a public server
		options.ServerInstanceId = jobId
	end

	return options
end

local function lockedServerFull(directory, map)
	local bucket = directory.Snapshot[map.Key]
	local server = bucket and bucket.Servers[1]

	return map.SingleServer and server ~= nil and server.Players >= server.Max
end

local function tryTeleport(client, placeId, options)
	for attempt = 1, RETRIES do
		local worked, why = pcall(teleportService.TeleportAsync, teleportService, placeId, { client }, options)

		if worked then
			return true
		end

		warn("Lobby teleport attempt", attempt, "failed:", why)

		if attempt < RETRIES then
			task.wait(attempt * 2)
		end
	end

	return false
end

-- pool: a platform-only pool to quick-join (nil for Any); device: the
-- Platform.lua key the client says it's on
local function onPlay(directory, client, mapKey, jobId, password, pool, device)
	if pending[client] or type(mapKey) ~= "string" then
		return
	end

	local map = catalog.ByKey[mapKey]
	local placeId = directory.PlaceByMap[mapKey]

	if not map or not placeId then
		return
	end

	-- claimed before anything yields so a double click can't send two teleports
	local token = { attempt = 0 }
	pending[client] = token

	local function refuse(code)
		clearPending(client, token)
		sendStatus(client, code)
	end

	if not catalog:CanSee(client, map) then
		return refuse("denied")
	end

	-- only the client knows what it's on, so this keeps honest players out of
	-- maps they can't play and other platforms' pools; it can't stop a liar
	if type(device) ~= "string" or not platform.ByKey[device] then
		device = "PC"
	end

	if platform:Support(map, device) == "blocked" then
		return refuse("unsupported")
	end

	-- a single-server map only has the one server, whatever was picked
	if map.SingleServer then
		jobId = nil
		pool = nil

		if lockedServerFull(directory, map) then
			return refuse("full")
		end
	elseif jobId ~= nil and (type(jobId) ~= "string" or not directory:HasServer(mapKey, jobId)) then
		return refuse("closed")
	end

	local server = jobId and directory:Server(mapKey, jobId)
	local isVip = server ~= nil and server.Kind ~= "public"

	-- a picked server decides the pool, not the client
	if server then
		pool = server.Pool
	end

	if pool ~= nil then
		if not table.find(directory:MapPools(map), pool) then
			return refuse("closed")
		end

		if platform:PoolFor(device) ~= pool then
			return refuse("unsupported")
		end
	end

	if isVip then
		if not vip.Kinds[server.Kind] then
			return refuse("closed")
		end

		-- the host's live lock and bans, not the directory's copy
		local authorized, reason = vip:Authorize(client, server)

		if not authorized then
			return refuse(reason)
		end

		-- VIP servers live on their own place
		placeId = server.PlaceId
	end

	local allowed, why = catalog:CheckPassword(client, map, type(password) == "string" and password:sub(1, MAX_PASSWORD) or "")

	if not allowed then
		return refuse(why)
	end

	-- a listed pool server: join its slot
	local listedSlot = nil

	if pool and server then
		listedSlot = pools:Slot(placeId, pool, directory:PrivateId(server.Id))

		if not listedSlot then
			return refuse("closed")
		end
	end

	sendStatus(client, "joining")

	local function attempt()
		token.attempt += 1

		local current = token.attempt
		local slot = listedSlot

		if pool and not server then
			slot = pools:Pick(placeId, pool, directory:PoolRunning(mapKey, pool))

			if not slot then
				return refuse("unavailable")
			end

			-- counted before the teleport yields, so other joins see it
			pools:Sent(slot.id)
		end

		token.slotId = slot and slot.id

		local options = buildOptions(map, placeId, jobId, server, slot, pool)

		if not options then
			return refuse("unavailable")
		end

		if isVip then
			local prepared, reason = vip:Prepare(client, server, options)

			if not prepared then
				return refuse(reason)
			end
		end

		-- without a grant the test place's lock would kick them on arrival
		if catalog.IsTest and not writeGrant(client, placeId) then
			return refuse("failed")
		end

		if not tryTeleport(client, placeId, options) then
			return refuse("failed")
		end

		sendStatus(client, "teleporting", map.Title)

		-- TeleportInitFailed covers most failures; this covers the rest
		task.delay(PENDING_TIMEOUT, function()
			if pending[client] == token and token.attempt == current and client.Parent then
				clearPending(client, token)
				sendStatus(client, "failed")
			end
		end)
	end

	-- a quick join can pick a pool server that filled up since the directory
	-- last said; TeleportInitFailed tries the next pick once
	if pool and not server then
		token.retry = attempt
	end

	attempt()
end

----

function library:Start(directory)
	remotes.Play.OnServerEvent:Connect(function(client, mapKey, jobId, password, pool, device)
		onPlay(directory, client, mapKey, jobId, password, pool, device)
	end)

	teleportService.TeleportInitFailed:Connect(function(client, result)
		local token = pending[client]
		local full = result == Enum.TeleportResult.GameFull

		if token and full and token.slotId then
			pools:HoldFull(token.slotId)

			if token.retry and not token.retried then
				token.retried = true
				task.spawn(token.retry)

				return
			end
		end

		pending[client] = nil

		sendStatus(client, full and "full" or "failed")
	end)

	playersService.PlayerRemoving:Connect(function(client)
		pending[client] = nil
	end)
end

return library
