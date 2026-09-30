-- VIP servers in the browser. Built but hidden (Protocol.VIP_LISTING) until
-- the game lists them in the directory and honours lobby tickets; see
-- CLAUDE.md "VIP servers".
--
-- Today that means Freeroam: each host owns one persistent reserved server
-- on the VIP Freeroam place. Its access code never goes to a client or into
-- the directory; it's read here, at join time, after the host's lock and
-- bans are checked. Paid VIP lobbies on Main can't be teleported into by
-- strangers and Tourney matches are roster-locked, so neither is a kind yet.
--
-- The lobby only reads the game's Freeroam stores. It never writes them: the
-- hand-off is the lobby's own single-use ticket (Protocol.TICKETS_MAP).

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local dataStoreService = game:GetService("DataStoreService")
local memoryStores = game:GetService("MemoryStoreService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)

local library = {}

----

-- game repo: src/Server/VIP Main.server.lua and freeroam:src/Server/Configs/Freeroam.lua
local FREEROAM_SERVERS = "Freeroam Servers - 4" -- DataStore, key hostId: { AccessCode, ServerId, HostId, CreatedAt }
-- MemoryStore, key hostId: { OwnerId, ServerLocked, Hosts, Bans, Config }. 60s TTL and
-- only written when the host changes a setting, so usually there's no entry
local FREEROAM_CONFIGS = "Freeroam Configs - 4"

-- freeroam settings worth a word on the row, shown when they differ from a
-- normal server. Freeroam's Config values are strings ("On"/"Off")
local SETTING_TAGS = {
	{ "FirstPersonOnly", "On", "FIRST PERSON" },
	{ "FreeCamEnabled", "On", "FREECAM" },
	{ "ZombiesEnabled", "Off", "NO ZOMBIES" },
	{ "LootEnabled", "Off", "NO LOOT" },
	{ "VehiclesEnabled", "Off", "NO VEHICLES" },
	{ "RandomsEnabled", "Off", "NO RANDOMS" },
}

-- set a ShowVip attribute on ServerStorage in Studio to preview VIP rows with mock data
library.Enabled = protocol.VIP_LISTING or (runService:IsStudio() and serverStorage:GetAttribute("ShowVip") == true)

-- kinds this lobby can list and join; anything else in the directory is skipped
library.Kinds = {
	public = true,
	freeroam = library.Enabled,
}

----

-- [hostId] = name, or false while it's being looked up
local names = {}

-- [hostId] = access code; a host's freeroam server is permanent, so is its code
local codes = {}

local configs = nil
local servers = nil
local tickets = nil

----

local function hostName(hostId)
	local cached = names[hostId]

	if cached ~= nil then
		return cached or nil
	end

	-- looked up in the background; the row shows up without a name until the next poll
	names[hostId] = false

	task.spawn(function()
		local found, name = pcall(playersService.GetNameFromUserIdAsync, playersService, hostId)
		names[hostId] = found and name or nil
	end)

	return nil
end

local function tagsFor(settings)
	local tags = {}

	if type(settings) ~= "table" then
		return tags
	end

	for _, rule in SETTING_TAGS do
		if settings[rule[1]] == rule[2] then
			table.insert(tags, rule[3])
		end
	end

	return tags
end

----

-- extra snapshot fields for a VIP entry, or nil if it's malformed
function library:Describe(kind, entry)
	local hostId = tonumber(entry.hostId)

	if kind ~= "freeroam" or not hostId then
		return nil
	end

	return {
		HostId = hostId,
		Host = hostName(hostId),
		Locked = entry.locked == true,
		Tags = tagsFor(entry.settings),
	}
end

-- true, or false and a status code. A pre-check to save a wasted teleport:
-- the freeroam server enforces its lock and bans on arrival itself, so a
-- stale answer here can't let anyone past them
function library:Authorize(client, server)
	configs = configs or memoryStores:GetHashMap(FREEROAM_CONFIGS)

	-- the live config names bans and co-hosts, when there is one
	local read, config = pcall(configs.GetAsync, configs, tostring(server.HostId))

	if not read then
		warn("Lobby couldn't read freeroam config for host", server.HostId, config)
	end

	if type(config) ~= "table" then
		config = nil
	end

	local userKey = tostring(client.UserId)
	local coHost = config and type(config.Hosts) == "table" and config.Hosts[userKey] == true
	local isHost = client.UserId == server.HostId or coHost
	local locked = server.Locked

	if config and config.ServerLocked ~= nil then
		locked = config.ServerLocked == true
	end

	if config and type(config.Bans) == "table" and config.Bans[userKey] then
		return false, "banned"
	end

	if locked and not isHost then
		return false, "locked"
	end

	return true
end

-- points the teleport at the host's reserved server and leaves a ticket the
-- freeroam server can check on arrival. Returns true, or false and a status code
function library:Prepare(client, server, options)
	local code = codes[server.HostId]

	if not code then
		servers = servers or dataStoreService:GetDataStore(FREEROAM_SERVERS)

		local read, info = pcall(servers.GetAsync, servers, tostring(server.HostId))

		if not read or type(info) ~= "table" or type(info.AccessCode) ~= "string" then
			warn("Lobby couldn't find the freeroam server for host", server.HostId)

			return false, "unavailable"
		end

		code = info.AccessCode
		codes[server.HostId] = code
	end

	tickets = tickets or memoryStores:GetHashMap(protocol.TICKETS_MAP)

	local wrote = pcall(tickets.SetAsync, tickets, tostring(client.UserId), {
		v = protocol.VERSION,
		kind = "freeroam",
		hostId = server.HostId,
		placeId = server.PlaceId,
		issuedAt = os.time(),
	}, protocol.TICKET_TTL)

	if not wrote then
		return false, "failed"
	end

	options.ReservedServerAccessCode = code

	return true
end

return library
