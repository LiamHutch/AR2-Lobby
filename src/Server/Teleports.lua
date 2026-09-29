local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local teleportService = game:GetService("TeleportService")

local protocol = require(replicatedStorage.Shared.Protocol)

local remotes = replicatedStorage.Remotes

local library = {}

----

local RETRIES = 3
local PENDING_TIMEOUT = 20

-- [player] = token of the teleport in flight
local pending = {}

----

local function sendStatus(client, code) -- "joining" | "full" | "closed" | "failed"
	remotes.Status:FireClient(client, code)
end

local function clearPending(client, token)
	if pending[client] == token then
		pending[client] = nil
	end
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

local function onPlay(directory, client, mapKey, jobId)
	if pending[client] or type(mapKey) ~= "string" then
		return
	end

	local placeId = directory.PlaceByMap[mapKey]

	if not placeId then
		return
	end

	if jobId ~= nil and (type(jobId) ~= "string" or not directory:HasServer(mapKey, jobId)) then
		sendStatus(client, "closed")

		return
	end

	local token = {}
	pending[client] = token

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		source = protocol.SOURCE,
		v = protocol.VERSION,
		map = mapKey,
	})

	-- no instance id means Roblox matchmakes into a public server
	if jobId then
		options.ServerInstanceId = jobId
	end

	sendStatus(client, "joining")

	if not tryTeleport(client, placeId, options) then
		clearPending(client, token)
		sendStatus(client, "failed")

		return
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
	remotes.Play.OnServerEvent:Connect(function(client, mapKey, jobId)
		onPlay(directory, client, mapKey, jobId)
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
