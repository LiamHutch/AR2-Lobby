-- A host's tourney lobby: the match config they're editing, the rosters of
-- players in this lobby server who joined it, and the start that reserves a
-- match server and sends everyone there. One object per host, made and
-- driven by Sessions.lua, which owns who may see it and who is viewing it.
--
-- The config is the lobby's own (Shared/Private.lua). The match server still
-- reads the old VIP lobby's handoff shape, so Start exports to that in
-- `legacyHandoff` and adds the new fields beside it; once the tourney build
-- reads the lobby's config directly, that export goes.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local teleportService = game:GetService("TeleportService")
local memoryStores = game:GetService("MemoryStoreService")
local dataStoreService = game:GetService("DataStoreService")
local textService = game:GetService("TextService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)
local store = require(script.Parent.PrivateStore)
local teleports = require(script.Parent.Teleports)

local class = {}
class.__index = class

----

local MODE = private.ByKey.Tourney
local TEAMS = 2
local SPECTATORS = 3
local NAME_LENGTH = 24
local DEFAULT_NAMES = { "Team One", "Team Two" }
local HANDOFF_TRIES = 3

-- unpublished Studio can't reserve servers or reach stores
local offline = runService:IsStudio() and game.GameId == 0

local handoffs = not offline and memoryStores:GetHashMap(protocol.TOURNEY_HANDOFF_MAP)
local sessions = not offline and dataStoreService:GetDataStore(protocol.TOURNEY_SESSIONS_STORE)
local legacy = not offline and dataStoreService:GetDataStore(protocol.TOURNEY_LEGACY_STORE)

----

local function sanitizeConfig(raw)
	raw = type(raw) == "table" and raw or {}

	local config = {
		v = protocol.PRIVATE_VERSION,
		visibility = private:IsVisibility(raw.visibility) and raw.visibility or private.DefaultVisibility,
		settings = private:Sanitize(MODE, raw.settings),
		teams = {},
		maps = {},
	}

	for index = 1, TEAMS do
		local team = type(raw.teams) == "table" and type(raw.teams[index]) == "table" and raw.teams[index] or {}
		local color = tonumber(team.color)

		config.teams[index] = {
			name = type(team.name) == "string" and team.name ~= "" and team.name:sub(1, NAME_LENGTH) or DEFAULT_NAMES[index],
			color = color and private.TeamColors[color] and color or index,
		}
	end

	for _, name in type(raw.maps) == "table" and raw.maps or {} do
		if MODE.MapsByName[name] and not table.find(config.maps, name) then
			table.insert(config.maps, name)
		end
	end

	return config
end

-- the old VIP lobby's saved config (TOURNEY_LEGACY_STORE) in the lobby's
-- shape, so a host keeps their match setup. Read once, when they have no
-- lobby config yet
local LEGACY_SETTINGS = {
	["Score mode"] = { "scoreMode", { ["Best of"] = "bestOf", ["First to"] = "firstTo" } },
	["Number of rounds"] = { "rounds", tonumber },
	["Start countdown"] = { "countdown", tonumber },
	["Round length"] = { "roundLength", tonumber },
	["Time of day"] = { "timeOfDay", string.lower },
	["Day length"] = { "dayLength", function(value)
		return tonumber((value:gsub("x$", "")))
	end },
	["First person lock"] = { "firstPerson", { On = true, Off = false } },
	["Map rotation"] = { "mapOrder", { ["In order"] = "inOrder", ["Shuffle picks"] = "shufflePicks", ["Shuffle all"] = "shuffleAll" } },
	["Spectating mode"] = { "spectating", string.lower },
	["Team sides"] = { "sides", string.lower },
}

local function importLegacy(userId)
	if not legacy then
		return nil
	end

	local read, saved = pcall(legacy.GetAsync, legacy, string.format("%d Match Config v2", userId))

	if not read or type(saved) ~= "table" then
		return nil
	end

	local settings = {}

	for name, value in type(saved.Settings) == "table" and saved.Settings or {} do
		local rule = LEGACY_SETTINGS[name]

		if rule and type(value) == "string" then
			local convert = rule[2]
			settings[rule[1]] = type(convert) == "function" and convert(value) or convert[value]
		end
	end

	local teams = {}

	for index = 1, TEAMS do
		teams[index] = { name = type(saved.TeamNames) == "table" and saved.TeamNames[index] or nil, color = index }
	end

	return {
		settings = settings,
		teams = teams,
		maps = saved.MapPicks,
	}
end

-- the match server's config, in the shape tourney's Tournament.lua reads
-- today (its sanitizeMatchConfig); the lobby's own values ride along for
-- the build that reads them
local function legacyHandoff(self, accessCode, serverId, placeId)
	local config = self.Config
	local settings = config.settings
	local labels = {}

	for key, value in settings do
		labels[key] = private:Label(MODE.SettingsByKey[key], value)
	end

	-- the round log names maps by their display names
	local mapNames = {}

	for _, map in MODE.Maps do
		mapNames[map.Name] = map.DisplayName
	end

	local rosters = {}

	for index, rosterName in { "Team 1", "Team 2", "Spectators" } do
		rosters[rosterName] = {}

		for _, client in self.Rosters[index] do
			table.insert(rosters[rosterName], client.Name)
		end
	end

	return {
		v = 2,
		source = protocol.SOURCE,

		Maps = table.clone(config.maps),
		Rosters = rosters,

		Rounds = tostring(settings.rounds),
		MapOrder = labels.mapOrder,
		ScoreMode = labels.scoreMode,
		RoundLength = tostring(settings.roundLength),
		StartDelay = tostring(settings.countdown),
		TimeOfDay = labels.timeOfDay,
		DayLength = labels.dayLength,
		FirstPerson = labels.firstPerson,
		SpectatingEnabled = labels.spectating,
		TeamSides = labels.sides,

		AccessCode = accessCode,
		ServerId = serverId,
		PlaceId = placeId,
		HostId = self.HostId,
		Team1Name = config.teams[1].name,
		Team2Name = config.teams[2].name,

		-- the lobby's config, for a match server that reads it
		TeamSize = settings.teamSize,
		TeamColors = { private.TeamColors[config.teams[1].color]:ToHex(), private.TeamColors[config.teams[2].color]:ToHex() },
		Settings = table.clone(settings),
		MapNames = mapNames,
	}
end

----

-- a saved record from the store, else the old VIP lobby's, else defaults
function class.Load(userId)
	local saved, loaded = store:Load("tourney", userId)

	if not saved and loaded then
		saved = importLegacy(userId)
	end

	return saved
end

-- a live match the player can go back to, or nil
function class.Rejoin(userId)
	if not sessions then
		return nil
	end

	local read, data = pcall(sessions.GetAsync, sessions, userId)

	if not read or type(data) ~= "table" or type(data.AccessCode) ~= "string" or type(data.PlaceId) ~= "number" then
		return nil
	end

	-- entries without WrittenAt are from before the match server cleaned up
	-- after itself; old ones are from a server that died
	if type(data.WrittenAt) ~= "number" or os.time() - data.WrittenAt > protocol.TOURNEY_SESSION_MAX_AGE then
		return nil
	end

	return { PlaceId = data.PlaceId, AccessCode = data.AccessCode }
end

-- sync(what) is Sessions' hook: "state" for the people looking at this lobby,
-- "list" when its row changes. placeId is the match place in this universe
function class.new(host, saved, sync, placeId)
	local self = setmetatable({}, class)

	self.Host = host
	self.HostId = host.UserId
	self.HostName = host.Name
	self.Config = sanitizeConfig(saved)
	self.PlaceId = placeId

	-- [team index] = { Player }; 3 is spectators
	self.Rosters = { {}, {}, {} }

	-- "open" (editing, joinable), "countdown", "committed" (reserving and teleporting)
	self.Phase = "open"
	self.CountdownEnds = nil
	self.Notice = nil

	self.sync = sync

	return self
end

----

function class:Save()
	store:Save("tourney", self.HostId, self.Config)
end

function class:IsHost(client)
	return client == self.Host
end

-- the team index and slot a player holds, or nil
function class:Seat(client)
	for index, roster in self.Rosters do
		local slot = table.find(roster, client)

		if slot then
			return index, slot
		end
	end

	return nil
end

function class:IsMember(client)
	return self:Seat(client) ~= nil
end

function class:Members()
	local members = {}

	for _, roster in self.Rosters do
		for _, client in roster do
			table.insert(members, client)
		end
	end

	return members
end

function class:TeamCap(index)
	return index == SPECTATORS and MODE.MaxSpectators or self.Config.settings.teamSize
end

function class:Visibility()
	return self.Config.visibility
end

-- joinable: open and not mid-start
function class:IsOpen()
	return self.Phase == "open"
end

function class:CanStart()
	local settings = self.Config.settings
	local hasMap = #self.Config.maps > 0 or settings.mapOrder == "shuffleAll"

	return hasMap and (#self.Rosters[1] > 0 or #self.Rosters[2] > 0)
end

function class:StartButton()
	if self.Phase == "committed" then
		return ""
	elseif self.Phase == "countdown" then
		return "cancel"
	elseif self:CanStart() then
		return "start"
	end

	return "blocked"
end

-- the two lines at the top of the roster
function class:Readout()
	local big, small = private:MatchTitle(self.Config)

	if self.Notice then
		return self.Notice[1], self.Notice[2]
	elseif self.Phase == "countdown" then
		local left = math.max(0, math.ceil(self.CountdownEnds - os.clock()))

		return string.format("Starting in %d seconds", left), big .. ", " .. small
	elseif self.Phase == "committed" then
		return "Starting match...", "Teleporting players, this may take a moment"
	end

	return big, small
end

----

-- a row in the session list
function class:Row(viewer)
	local big = private:MatchTitle(self.Config)
	local players = #self:Members()
	local max = self.Config.settings.teamSize * TEAMS + MODE.MaxSpectators

	return {
		HostId = self.HostId,
		Host = self.HostName,
		Detail = big,
		Access = self:IsOpen() and private.VisibilityLabels[self.Config.visibility] or "LOCKED",
		Locked = not self:IsOpen(),
		Players = players,
		Max = max,
		Full = players >= max,
		Mine = viewer == self.Host,
	}
end

-- everything the panel shows
function class:State(viewer)
	local teams = {}

	for index = 1, SPECTATORS do
		local team = self.Config.teams[index]
		local names = {}

		for _, client in self.Rosters[index] do
			table.insert(names, client.Name)
		end

		teams[index] = {
			Name = team and team.name or "Spectators",
			Color = team and team.color or nil,
			Roster = names,
			Cap = self:TeamCap(index),
		}
	end

	local big, small = self:Readout()

	return {
		HostId = self.HostId,
		Host = self.HostName,
		Mine = viewer == self.Host,
		Visibility = self.Config.visibility,
		Settings = self.Config.settings,
		Maps = self.Config.maps,
		Teams = teams,
		Phase = self.Phase,
		CountdownLeft = self.Phase == "countdown" and math.max(0, self.CountdownEnds - os.clock()) or nil,
		StartButton = self:StartButton(),
		Readout = { big, small },
		YourTeam = (self:Seat(viewer)),
		Members = #self:Members(),
	}
end

----

local function filterName(name, client)
	local worked, filtered = pcall(function()
		local result = textService:FilterStringAsync(name, client.UserId, Enum.TextFilterContext.PublicChat)

		return result:GetNonChatStringForBroadcastAsync()
	end)

	return worked and filtered or nil
end

-- a member joins a team (or spectators), leaving whatever seat they had
function class:Join(client, index)
	index = tonumber(index)

	if not self:IsOpen() or not index or index < 1 or index > SPECTATORS then
		return false
	end

	local roster = self.Rosters[index]

	if #roster >= self:TeamCap(index) then
		return false
	end

	self:Leave(client)
	table.insert(roster, client)

	return true
end

function class:Leave(client)
	local index, slot = self:Seat(client)

	if index then
		table.remove(self.Rosters[index], slot)

		return true
	end

	return false
end

-- a player left the lobby server
function class:OnLeave(client)
	if client == self.Host then
		return
	end

	if self:Leave(client) then
		self.sync("state")
		self.sync("list")
	end
end

-- host actions while editing. Each returns true when the state changed
local hostActions = {}

function hostActions.setting(self, key, value)
	local setting = MODE.SettingsByKey[key]

	if not setting or not private:Option(setting, value) then
		return false
	end

	self.Config.settings[key] = value

	-- a smaller team drops its last seats
	for index = 1, TEAMS do
		local roster = self.Rosters[index]

		while #roster > self:TeamCap(index) do
			table.remove(roster)
		end
	end

	return true
end

function hostActions.visibility(self, value)
	if not private:IsVisibility(value) then
		return false
	end

	self.Config.visibility = value

	return true
end

function hostActions.map(self, name)
	if not MODE.MapsByName[name] then
		return false
	end

	local maps = self.Config.maps
	local index = table.find(maps, name)

	if index then
		table.remove(maps, index)
	else
		table.insert(maps, name)
	end

	return true
end

-- seconds between team renames: each one is a TextService filter call
local RENAME_GAP = 2

function hostActions.teamName(self, index, name)
	index = tonumber(index)

	if not index or not self.Config.teams[index] or type(name) ~= "string" then
		return false
	end

	if os.clock() - (self.lastRename or -RENAME_GAP) < RENAME_GAP then
		return false
	end

	self.lastRename = os.clock()

	name = name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, NAME_LENGTH)

	if name == "" then
		name = DEFAULT_NAMES[index]
	else
		name = filterName(name, self.Host)

		if not name then
			return false
		end
	end

	self.Config.teams[index].name = name

	return true
end

function hostActions.teamColor(self, index, color)
	index = tonumber(index)
	color = tonumber(color)

	if not index or not self.Config.teams[index] or not color or not private.TeamColors[color] then
		return false
	end

	self.Config.teams[index].color = color

	return true
end

function hostActions.kick(self, userId)
	for _, client in self:Members() do
		if client.UserId == tonumber(userId) and client ~= self.Host then
			return self:Leave(client)
		end
	end

	return false
end

-- a client action from Sessions; returns stateChanged, listChanged
function class:Act(client, action, ...)
	if action == "join" then
		return self:Join(client, ...), true
	elseif action == "leave" then
		return self:Leave(client), true
	end

	if not self:IsHost(client) then
		return false, false
	end

	if action == "start" then
		return self:Start(), true
	elseif action == "cancel" then
		return self:Cancel(), true
	end

	local handler = hostActions[action]

	if not handler or not self:IsOpen() then
		return false, false
	end

	local changed = handler(self, ...)

	if changed then
		self:Save()
	end

	return changed, changed
end

----

function class:Start()
	if self.Phase ~= "open" or not self:CanStart() then
		return false
	end

	self.Phase = "countdown"
	self.CountdownEnds = os.clock() + protocol.TOURNEY_COUNTDOWN
	self.Notice = nil

	local token = {}
	self.countdown = token

	task.spawn(function()
		while os.clock() < self.CountdownEnds do
			task.wait(0.25)

			if self.countdown ~= token then
				return
			end
		end

		if self.countdown == token then
			self:Commit()
		end
	end)

	return true
end

function class:Cancel()
	if self.Phase ~= "countdown" then
		return false
	end

	self.countdown = nil
	self.Phase = "open"
	self.CountdownEnds = nil

	return true
end

-- back to editing after a failed start, with a line saying why
local function abort(self, why)
	self.Phase = "open"
	self.CountdownEnds = nil
	self.Notice = { "Couldn't start", why }
	self.sync("state")
	self.sync("list")

	task.delay(6, function()
		if self.Notice and self.Notice[2] == why then
			self.Notice = nil
			self.sync("state")
		end
	end)
end

function class:Commit()
	self.Phase = "committed"
	self.sync("state")
	self.sync("list")
	self:Save()

	if not self.PlaceId then
		return abort(self, "no match server in this universe")
	end

	local accessCode, serverId

	-- Studio can't reserve servers (403); a fake code shows the rest of the flow
	if runService:IsStudio() then
		accessCode, serverId = "studio", "studio-" .. os.time()
	else
		local reserved, code, id = pcall(teleportService.ReserveServer, teleportService, self.PlaceId)

		if not reserved then
			warn("Lobby couldn't reserve a match server:", code)

			return abort(self, "couldn't reserve a server")
		end

		accessCode, serverId = code, id
	end

	local handoff = legacyHandoff(self, accessCode, serverId, self.PlaceId)

	-- the match server reads its config here by its PrivateServerId; a client
	-- could edit the teleport data copy, so this one wins. If it can't be
	-- stored the match still starts and the server falls back to the host's upload
	if handoffs and not runService:IsStudio() then
		local stored = false

		for attempt = 1, HANDOFF_TRIES do
			stored = pcall(handoffs.SetAsync, handoffs, serverId, handoff, protocol.TOURNEY_HANDOFF_TTL)

			if stored then
				break
			end

			task.wait(attempt)
		end

		if not stored then
			warn("Lobby couldn't store the match handoff, the match server will use the host's teleport data")
		end
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(handoff)

	local list = {}

	for _, client in self:Members() do
		if client.Parent then
			table.insert(list, client)
		end
	end

	local sent = teleports:SendGroup(list, self.PlaceId, options, MODE.Name)

	if not sent then
		return abort(self, "couldn't teleport the players")
	end

	-- whoever is left wasn't sent; the lobby opens again for them
	self.Phase = "open"
	self.CountdownEnds = nil
	self.sync("state")
	self.sync("list")

	return true
end

function class:Destroy()
	self.countdown = nil
	self.Rosters = { {}, {}, {} }
	self.sync = function() end
end

return class
