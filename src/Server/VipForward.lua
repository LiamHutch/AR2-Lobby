-- Paid VIP servers on the lobby place (863266079, formerly the game's
-- Prod - Main) don't show the browser: they forward everyone straight to the
-- host's own reserved server on the VIP map (Protocol.VIP_FORWARD_MAP), one
-- per host, kept forever.
--
-- A reserved server has no PrivateServerOwnerId, so the game can't tell who
-- its host is. The paid VIP server here is the only place that sees the real
-- owner, so it records it in two lobby-owned DataStores (see Protocol.lua):
--
--   VIP_HOSTS_STORE    key = reserved server's PrivateServerId -> { v, hostId, placeId, createdAt }
--   VIP_SERVERS_STORE  key = "<placeId>:<hostId>" -> { v, hostId, placeId, accessCode, privateServerId, createdAt }
--
-- DataStores are server-only, so the game can trust VIP_HOSTS_STORE for who
-- hosts a server. It must never take the host from TeleportData. The access
-- code never leaves the server, so the forward is the only way in.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local dataStoreService = game:GetService("DataStoreService")
local teleportService = game:GetService("TeleportService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local catalog = require(script.Parent.Catalog)

local remotes = replicatedStorage.Remotes

local library = {}

----

local SETUP_TRIES = 4
local TELEPORT_TRIES = 3
local RETRY_WAIT = 15

----

-- the host's reserved server: { accessCode, privateServerId, ... }, once found
local record = nil

local function valid(entry, hostId, placeId)
	return type(entry) == "table"
		and entry.hostId == hostId
		and entry.placeId == placeId
		and type(entry.accessCode) == "string"
		and type(entry.privateServerId) == "string"
end

-- finds or reserves the host's server and (re)writes the lookup the game
-- uses to learn its host; errors if the DataStores or ReserveServer fail
local function resolve(hostId, placeId)
	local servers = dataStoreService:GetDataStore(protocol.VIP_SERVERS_STORE)
	local hosts = dataStoreService:GetDataStore(protocol.VIP_HOSTS_STORE)
	local key = placeId .. ":" .. hostId

	local entry = servers:GetAsync(key)

	if not valid(entry, hostId, placeId) then
		local code, privateServerId = teleportService:ReserveServer(placeId)
		local fresh = {
			v = protocol.VIP_VERSION,
			hostId = hostId,
			placeId = placeId,
			accessCode = code,
			privateServerId = privateServerId,
			createdAt = os.time(),
		}

		-- if another boot of this host's VIP server got there first, keep its
		-- server; the spare reservation is just never used
		entry = servers:UpdateAsync(key, function(old)
			return valid(old, hostId, placeId) and old or fresh
		end)
	end

	-- written every boot so it heals if an earlier boot died between the two writes
	hosts:SetAsync(entry.privateServerId, {
		v = protocol.VIP_VERSION,
		hostId = hostId,
		placeId = placeId,
		createdAt = entry.createdAt,
	})

	return entry
end

local function forward(client, hostId, placeId)
	while client.Parent do
		remotes.Status:FireClient(client, "joining")

		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = record.accessCode
		-- informational only; the game gets the host from VIP_HOSTS_STORE
		options:SetTeleportData({
			source = protocol.SOURCE,
			v = protocol.VERSION,
			kind = "vip",
			hostId = hostId,
		})

		for attempt = 1, TELEPORT_TRIES do
			local worked, why = pcall(teleportService.TeleportAsync, teleportService, placeId, { client }, options)

			if worked then
				-- TeleportInitFailed restarts this if the teleport doesn't land
				return
			end

			warn("VIP forward attempt", attempt, "failed:", why)
			task.wait(attempt * 2)
		end

		remotes.Status:FireClient(client, "failed")
		task.wait(RETRY_WAIT)
	end
end

----

-- the paid VIP server's owner, or nil when this isn't one. Studio can fake
-- it with a SimulateVipHost attribute (a UserId) on ServerStorage
function library:Detect()
	if catalog.IsTest then
		return nil
	end

	if runService:IsStudio() then
		local simulated = serverStorage:GetAttribute("SimulateVipHost")

		return type(simulated) == "number" and simulated > 0 and simulated or nil
	end

	-- reserved servers also have a PrivateServerId, but no owner
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0 then
		return game.PrivateServerOwnerId
	end

	return nil
end

-- true if this is a VIP server now forwarding everyone; false means carry on
-- as the normal browser (not a VIP server, or the forward couldn't be set up)
function library:Start(directory)
	local hostId = self:Detect()

	if not hostId then
		return false
	end

	-- clients hide the browser straight away
	replicatedStorage:SetAttribute("VipForward", true)

	directory:Resolve()

	local map = catalog.ByKey[protocol.VIP_FORWARD_MAP]
	local placeId = map and directory.PlaceByMap[map.Key]

	if placeId then
		for attempt = 1, SETUP_TRIES do
			local worked, result = pcall(resolve, hostId, placeId)

			if worked then
				record = result

				break
			end

			warn("VIP forward setup attempt", attempt, "failed:", result)
			task.wait(attempt * 3)
		end
	else
		warn("VIP forward: map", protocol.VIP_FORWARD_MAP, "has no place in this universe")
	end

	if not record then
		-- better a working browser than a stuck VIP server
		replicatedStorage:SetAttribute("VipForward", false)

		return false
	end

	playersService.PlayerAdded:Connect(function(client)
		forward(client, hostId, placeId)
	end)

	for _, client in playersService:GetPlayers() do
		task.spawn(forward, client, hostId, placeId)
	end

	teleportService.TeleportInitFailed:Connect(function(client)
		task.delay(RETRY_WAIT, function()
			if client.Parent then
				forward(client, hostId, placeId)
			end
		end)
	end)

	return true
end

return library
