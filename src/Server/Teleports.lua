local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local teleportService = game:GetService("TeleportService")
local memoryStores = game:GetService("MemoryStoreService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local catalog = require(script.Parent.Catalog)
local reserved = require(script.Parent.Reserved)

local remotes = replicatedStorage.Remotes

local library = {}

----

-- Studio can't teleport, so fail on the first try instead of after the backoff
local RETRIES = runService:IsStudio() and 1 or 3
local PENDING_TIMEOUT = 20
local MAX_PASSWORD = 100

-- [player] = token of the teleport in flight
local pending = {}

local grants = nil

----

-- "joining" | "full" | "closed" | "failed" | "denied" | "password" | "slow" | "unavailable"
local function sendStatus(client, code)
	remotes.Status:FireClient(client, code)
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

local function buildOptions(map, placeId, jobId)
	local options = Instance.new("TeleportOptions")

	-- test places read the hub's teleport data (game repo: Hub Beacon)
	if catalog.IsTest then
		options:SetTeleportData({
			source = protocol.HUB_SOURCE,
			v = protocol.HUB_VERSION,
		})
	else
		options:SetTeleportData({
			source = protocol.SOURCE,
			v = protocol.VERSION,
			map = map.Key,
		})
	end

	if map.SingleServer then
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

local function onPlay(directory, client, mapKey, jobId, password)
	if pending[client] or type(mapKey) ~= "string" then
		return
	end

	local map = catalog.ByKey[mapKey]
	local placeId = directory.PlaceByMap[mapKey]

	if not map or not placeId then
		return
	end

	-- claimed before anything yields so a double click can't send two teleports
	local token = {}
	pending[client] = token

	local function refuse(code)
		clearPending(client, token)
		sendStatus(client, code)
	end

	if not catalog:CanSee(client, map) then
		return refuse("denied")
	end

	-- a single-server map only has the one server, whatever was picked
	if map.SingleServer then
		jobId = nil

		if lockedServerFull(directory, map) then
			return refuse("full")
		end
	elseif jobId ~= nil and (type(jobId) ~= "string" or not directory:HasServer(mapKey, jobId)) then
		return refuse("closed")
	end

	local allowed, why = catalog:CheckPassword(client, map, type(password) == "string" and password:sub(1, MAX_PASSWORD) or "")

	if not allowed then
		return refuse(why)
	end

	sendStatus(client, "joining")

	local options = buildOptions(map, placeId, jobId)

	if not options then
		return refuse("unavailable")
	end

	-- without a grant the test place's lock would kick them on arrival
	if catalog.IsTest and not writeGrant(client, placeId) then
		return refuse("failed")
	end

	if not tryTeleport(client, placeId, options) then
		return refuse("failed")
	end

	-- TeleportInitFailed covers most failures; this covers the rest
	task.delay(PENDING_TIMEOUT, function()
		if pending[client] == token and client.Parent then
			clearPending(client, token)
			sendStatus(client, "failed")
		end
	end)
end

----

function library:Start(directory)
	remotes.Play.OnServerEvent:Connect(function(client, mapKey, jobId, password)
		onPlay(directory, client, mapKey, jobId, password)
	end)

	teleportService.TeleportInitFailed:Connect(function(client, result)
		pending[client] = nil

		sendStatus(client, result == Enum.TeleportResult.GameFull and "full" or "failed")
	end)

	playersService.PlayerRemoving:Connect(function(client)
		pending[client] = nil
	end)
end

return library
