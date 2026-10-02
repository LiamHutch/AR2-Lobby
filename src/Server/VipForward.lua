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
--
-- VIP is PC and console only. Mobile players are sent on to a public lobby
-- server instead, where they can pick a map as usual. Only the client knows
-- what it's on, so it reports its platform and the forward waits for it.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local dataStoreService = game:GetService("DataStoreService")
local teleportService = game:GetService("TeleportService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local platform = require(replicatedStorage.Shared.Platform)
local catalog = require(script.Parent.Catalog)

local remotes = replicatedStorage.Remotes

local library = {}

----

local SETUP_TRIES = 4
local TELEPORT_TRIES = 3
local RETRY_WAIT = 15
-- how long to wait for a client to say what it's on before treating it as PC,
-- so a slow load still gets forwarded
local REPORT_WAIT = 20
-- long enough to read the notice before the teleport screen covers it
local NOTICE_WAIT = 2

-- Platform.lua keys that don't get VIP servers
local NOT_FORWARDED = {
	Mobile = true,
}

----

-- the host's reserved server: { accessCode, privateServerId, ... }, once found
local record = nil

-- client -> the Platform.lua key it reported
local devices = {}

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

-- what the client said it's on, once it has; PC if it never does
local function deviceOf(client)
	local deadline = os.clock() + REPORT_WAIT

	while not devices[client] and client.Parent and os.clock() < deadline do
		task.wait(0.25)
	end

	return devices[client] or "PC"
end

-- no options matchmakes into one of the lobby's public servers
local function redirect(client)
	remotes.Status:FireClient(client, "unsupported")
	task.wait(NOTICE_WAIT)

	while client.Parent do
		for attempt = 1, TELEPORT_TRIES do
			local worked, why = pcall(teleportService.TeleportAsync, teleportService, game.PlaceId, { client })

			if worked then
				return
			end

			warn("VIP redirect attempt", attempt, "failed:", why)
			task.wait(attempt * 2)
		end

		remotes.Status:FireClient(client, "failed")
		task.wait(RETRY_WAIT)
		remotes.Status:FireClient(client, "unsupported")
	end
end

local function forward(client, hostId, placeId, title)
	while client.Parent do
		-- the title names the map on the teleport's loading screen
		remotes.Status:FireClient(client, "joining", title)

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
				remotes.Status:FireClient(client, "teleporting", title)

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

	-- clients hide the browser straight away, and report their platform
	-- when they see this
	replicatedStorage:SetAttribute("VipForward", true)

	remotes.Platform.OnServerEvent:Connect(function(client, device)
		if type(device) == "string" and platform.ByKey[device] then
			devices[client] = device
		end
	end)

	playersService.PlayerRemoving:Connect(function(client)
		devices[client] = nil
	end)

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

	local title = map.Title

	local function send(client)
		if NOT_FORWARDED[deviceOf(client)] then
			redirect(client)
		else
			forward(client, hostId, placeId, title)
		end
	end

	playersService.PlayerAdded:Connect(send)

	for _, client in playersService:GetPlayers() do
		task.spawn(send, client)
	end

	teleportService.TeleportInitFailed:Connect(function(client)
		-- back to the forwarding status until the retry
		remotes.Status:FireClient(client, "failed")

		task.delay(RETRY_WAIT, function()
			if client.Parent then
				send(client)
			end
		end)
	end)

	return true
end

return library
