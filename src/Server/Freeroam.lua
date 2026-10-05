-- A host's free roam server: one permanent reserved server per player on the
-- Free Roam place, configured and joined from the lobby. One object per host,
-- made and driven by Sessions.lua.
--
-- The host's config is the lobby's own (Shared/Private.lua); the free roam
-- server reads it at boot and writes its in-game lock, co-host and ban
-- changes back (settings, hosts and bans only). A host from before the lobby owned the config is
-- seeded once from the old VIP lobby's record (FREEROAM_CONFIGS_STORE). The
-- host's reserved server record (FREEROAM_SERVERS_STORE) stays: the game
-- checks it on arrival to know whose server it is.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local teleportService = game:GetService("TeleportService")
local memoryStores = game:GetService("MemoryStoreService")
local dataStoreService = game:GetService("DataStoreService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)
local platform = require(replicatedStorage.Shared.Platform)
local store = require(script.Parent.PrivateStore)
local teleports = require(script.Parent.Teleports)

local class = {}
class.__index = class

----

local MODE = private.ByKey.Freeroam
local RECORD_TRIES = 3

local offline = runService:IsStudio() and game.GameId == 0

local servers = not offline and dataStoreService:GetDataStore(protocol.FREEROAM_SERVERS_STORE)
local legacyStore = not offline and dataStoreService:GetDataStore(protocol.FREEROAM_CONFIGS_STORE)
local lobbies = not offline and memoryStores:GetHashMap(protocol.FREEROAM_LOBBIES_MAP)
local tickets = not offline and memoryStores:GetHashMap(protocol.TICKETS_MAP)
-- TEMP: a free roam build from before the lobby's ticket learns its host from
-- this instead (key = userId -> hostId); goes once every place runs a build
-- that takes the ticket
local sessions = not offline and memoryStores:GetHashMap("Freeroam Sessions - 4")

-- every live session, for the poll of their running servers
local live = {}

-- [userId] = name, looked up for ban rows
local names = {}

----

local function sanitizeConfig(raw)
	raw = type(raw) == "table" and raw or {}

	local config = {
		v = protocol.PRIVATE_VERSION,
		visibility = private:IsVisibility(raw.visibility) and raw.visibility or private.DefaultVisibility,
		settings = private:Sanitize(MODE, raw.settings),
		hosts = {},
		bans = {},
	}

	for _, field in { "hosts", "bans" } do
		for key, value in type(raw[field]) == "table" and raw[field] or {} do
			if tonumber(key) and value then
				config[field][tostring(key)] = true
			end
		end
	end

	return config
end

-- the old VIP lobby's config keys and the lobby's, for the one-time seed
local LEGACY_KEYS = {
	{ "firstPerson", "FirstPersonOnly" },
	{ "statsDegrade", "StatsDegrade" },
	{ "freeCam", "FreeCamEnabled" },
	{ "zombies", "ZombiesEnabled" },
	{ "vehicles", "VehiclesEnabled" },
	{ "randoms", "RandomsEnabled" },
	{ "loot", "LootEnabled" },
}

local function fromLegacy(record)
	if type(record) ~= "table" then
		return nil
	end

	local settings = { locked = record.ServerLocked == true }
	local legacySettings = type(record.Config) == "table" and record.Config or {}

	for _, pair in LEGACY_KEYS do
		local value = legacySettings[pair[2]]

		if value == "On" or value == "Off" then
			settings[pair[1]] = value == "On"
		end
	end

	if type(legacySettings.TimeOfDayFrozen) == "string" then
		settings.timeOfDay = legacySettings.TimeOfDayFrozen:lower()
	end

	return {
		settings = settings,
		hosts = record.Hosts,
		bans = record.Bans,
	}
end

local function nameOf(userId)
	userId = tonumber(userId)

	if not userId then
		return nil
	end

	if names[userId] == nil then
		names[userId] = false

		task.spawn(function()
			local found, name = pcall(playersService.GetNameFromUserIdAsync, playersService, userId)
			names[userId] = found and name or string.format("[%d]", userId)
		end)
	end

	return names[userId] or nil
end

----

-- the saved record, else the game's old config for this host, else defaults
function class.Load(userId)
	local saved, loaded = store:Load("freeroam", userId)

	if not saved and loaded and legacyStore then
		local read, record = pcall(legacyStore.GetAsync, legacyStore, tostring(userId))

		if read then
			saved = fromLegacy(record)
		end
	end

	return saved
end

function class.new(host, saved, sync, placeId)
	local self = setmetatable({}, class)

	self.Host = host
	self.HostId = host.UserId
	self.HostName = host.Name
	self.Config = sanitizeConfig(saved)
	self.PlaceId = placeId

	-- the host's reserved server: { AccessCode, ServerId }, once found or made
	self.Record = nil
	self.Broken = false

	-- what the running server last wrote: { Locked, Online = { names }, Players }
	self.Live = nil

	self.sync = sync

	live[self] = true

	for _, field in { "hosts", "bans" } do
		for userId in self.Config[field] do
			nameOf(userId)
		end
	end

	task.spawn(function()
		self:loadRecord()
	end)

	return self
end

----

-- a record is only good for the place its access code was reserved on. The
-- old VIP lobby's records carry no PlaceId: on prod they were reserved on the
-- prod place, elsewhere on the Development place, so only the prod lobby
-- trusts one
local function recordFor(record, placeId)
	if type(record) ~= "table" or type(record.AccessCode) ~= "string" or type(record.ServerId) ~= "string" then
		return false
	end

	if record.PlaceId == nil then
		return placeId == MODE.PlaceIds[1]
	end

	return record.PlaceId == placeId
end

-- the host's permanent reserved server on this lobby's free roam place,
-- reserved on first use. The free roam server trusts this record for who
-- its host is, so it's only replaced for a server on another place
function class:loadRecord()
	if not self.PlaceId then
		self.Broken = true
		self.sync("state")

		return
	end

	if offline then
		self.Record = { AccessCode = "studio", ServerId = "studio" }
		self.sync("state")

		return
	end

	local key = tostring(self.HostId)

	for attempt = 1, RECORD_TRIES do
		local worked, record = pcall(function()
			local existing = servers:GetAsync(key)

			if recordFor(existing, self.PlaceId) then
				return existing
			end

			local code, serverId = teleportService:ReserveServer(self.PlaceId)
			local fresh = {
				AccessCode = code,
				ServerId = serverId,
				HostId = self.HostId,
				PlaceId = self.PlaceId,
				CreatedAt = os.time(),
			}

			-- another lobby server may have reserved one meanwhile; theirs stays
			return servers:UpdateAsync(key, function(old)
				if recordFor(old, self.PlaceId) then
					return old
				end

				return fresh
			end)
		end)

		if worked and type(record) == "table" then
			self.Record = record
			self.sync("state")

			return
		end

		warn("Lobby couldn't get the free roam server for host", self.HostId, record)
		task.wait(attempt * 2)
	end

	self.Broken = true
	self.sync("state")
end

function class:Save()
	store:Save("freeroam", self.HostId, self.Config)
end

----

function class:IsHost(client)
	return client == self.Host
end

-- a co-host: in on a locked server and a private listing, like the host
function class:IsCoHost(client)
	return self.Config.hosts[tostring(client.UserId)] == true
end

function class:IsMember(client)
	return self:IsCoHost(client)
end

function class:Visibility()
	return self.Config.visibility
end

function class:IsLocked()
	return self.Config.settings.locked == true
end

function class:IsBanned(client)
	return self.Config.bans[tostring(client.UserId)] == true
end

function class:Row(viewer)
	local tags = private:SettingTags(MODE, self.Config.settings)
	local players = self.Live and self.Live.Players or nil

	return {
		HostId = self.HostId,
		Host = self.HostName,
		Detail = #tags > 0 and table.concat(tags, "  ·  ") or "default settings",
		Access = self:IsLocked() and "LOCKED" or private.VisibilityLabels[self.Config.visibility],
		Locked = self:IsLocked(),
		Players = players,
		Max = MODE.MaxPlayers,
		Running = self.Live ~= nil,
		Full = players ~= nil and players >= MODE.MaxPlayers,
		Mine = viewer == self.Host,
	}
end

local function people(set)
	local list = {}

	for userId in set do
		table.insert(list, { UserId = tonumber(userId), Name = nameOf(userId) })
	end

	table.sort(list, function(a, b)
		return (a.Name or "") < (b.Name or "")
	end)

	return list
end

function class:State(viewer)
	local hosts = people(self.Config.hosts)
	local bans = people(self.Config.bans)

	return {
		HostId = self.HostId,
		Host = self.HostName,
		Mine = viewer == self.Host,
		Visibility = self.Config.visibility,
		Settings = self.Config.settings,
		Tags = private:SettingTags(MODE, self.Config.settings),
		Hosts = hosts,
		Bans = bans,
		Online = self.Live and self.Live.Online or {},
		Players = self.Live and self.Live.Players or nil,
		Running = self.Live ~= nil,
		Ready = self.Record ~= nil,
		Broken = self.Broken,
		Banned = self:IsBanned(viewer),
		Locked = self:IsLocked(),
		CoHost = self:IsCoHost(viewer),
	}
end

----

local hostActions = {}

function hostActions.setting(self, key, value)
	local setting = MODE.SettingsByKey[key]

	if not setting or not private:Option(setting, value) then
		return false
	end

	self.Config.settings[key] = value

	return true
end

function hostActions.visibility(self, value)
	if not private:IsVisibility(value) then
		return false
	end

	self.Config.visibility = value

	return true
end

function hostActions.ban(self, userId)
	userId = tonumber(userId)

	if not userId or userId == self.HostId then
		return false
	end

	self.Config.bans[tostring(userId)] = true
	-- a banned co-host would be kicked every second
	self.Config.hosts[tostring(userId)] = nil
	nameOf(userId)

	return true
end

function hostActions.host(self, userId)
	userId = tonumber(userId)

	if not userId or userId == self.HostId or self.Config.bans[tostring(userId)] then
		return false
	end

	self.Config.hosts[tostring(userId)] = true
	nameOf(userId)

	return true
end

function hostActions.unhost(self, userId)
	userId = tonumber(userId)

	if not userId or not self.Config.hosts[tostring(userId)] then
		return false
	end

	self.Config.hosts[tostring(userId)] = nil

	return true
end

function hostActions.unban(self, userId)
	userId = tonumber(userId)

	if not userId or not self.Config.bans[tostring(userId)] then
		return false
	end

	self.Config.bans[tostring(userId)] = nil

	return true
end

-- a client action from Sessions; returns stateChanged, listChanged
function class:Act(client, action, ...)
	if action == "join" then
		self:Join(client, ...)

		return false, false
	end

	if not self:IsHost(client) then
		return false, false
	end

	local handler = hostActions[action]

	if not handler then
		return false, false
	end

	local changed = handler(self, ...)

	if changed then
		self:Save()
	end

	return changed, changed
end

-- sends a player to this server. The free roam server checks the lock and
-- bans again on arrival; this spares a wasted teleport
function class:Join(client, device)
	if not self.Record then
		return teleports:Refuse(client, "unavailable")
	end

	if self:IsBanned(client) then
		return teleports:Refuse(client, "banned")
	end

	if self:IsLocked() and not (self:IsHost(client) or self:IsCoHost(client)) then
		return teleports:Refuse(client, "locked")
	end

	if type(device) ~= "string" or not platform.ByKey[device] then
		device = "PC"
	end

	if platform:Support(MODE, device) == "blocked" then
		return teleports:Refuse(client, "unsupported")
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = self.Record.AccessCode
	options:SetTeleportData({
		source = protocol.SOURCE,
		v = protocol.VERSION,
		kind = MODE.Kind,
		hostId = self.HostId,
	})

	teleports:SendPrivate(client, self.PlaceId, options, MODE.Name, function()
		-- the ticket is how the free roam server learns whose server this is
		if not tickets then
			return true
		end

		pcall(sessions.SetAsync, sessions, tostring(client.UserId), self.HostId, protocol.TICKET_TTL)

		return pcall(tickets.SetAsync, tickets, tostring(client.UserId), {
			v = protocol.VERSION,
			kind = MODE.Kind,
			hostId = self.HostId,
			placeId = self.PlaceId,
			issuedAt = os.time(),
		}, protocol.TICKET_TTL)
	end)
end

function class:OnLeave(client)
end

function class:Destroy()
	live[self] = nil
	self.sync = function() end
end

----

-- what the host's running server last wrote, if it's up
local function readLive(self)
	local read, data = pcall(lobbies.GetAsync, lobbies, tostring(self.HostId))

	if not read then
		return
	end

	local was = self.Live

	if type(data) == "table" then
		local online = {}

		for _, entry in type(data.Online) == "table" and data.Online or {} do
			if type(entry) == "table" and type(entry.UserName) == "string" then
				table.insert(online, entry.UserName)
			end
		end

		self.Live = { Locked = data.Locked == true, Online = online, Players = #online }
	else
		self.Live = nil
	end

	local changed = (was == nil) ~= (self.Live == nil) or (was and self.Live and was.Players ~= self.Live.Players)

	if changed then
		self.sync("state")
		self.sync("list")
	end
end

if not offline then
	task.spawn(function()
		while true do
			task.wait(protocol.PRIVATE_LIVE_POLL)

			for session in live do
				task.spawn(readLive, session)
			end
		end
	end)
end

return class
