-- Private server sessions: every player in a lobby server can host their own
-- tourney lobby (Tourney.lua) and free roam server (Freeroam.lua), so no
-- paid private server is needed. This owns the sessions in this server, who
-- may see each one, who is looking at which, and the one remote the client
-- talks to them through.
--
-- Remotes.Private, client -> server (action, ...):
--   "open", key          the mode view opened; the player's own session is
--                        made (its config loads) and they get the list
--   "close"              the mode view closed
--   "view", key, hostId  look at a session (their own, or a listed one)
--   "act", key, hostId, action, ...   an action on a session (Tourney.lua /
--                        Freeroam.lua Act); "join" on a tourney lobby leaves
--                        any other lobby first
--   "unview"             back to the list
--   "rejoin"             back into a live match (Tourney.Rejoin)
--   "friends", entries   what the client's GetFriendsOnlineAsync returned;
--                        answered with where they are (Friends.lua)
--   "follow", userId     go to that friend's server
--   "ready"              the client is up: told who to open if a friend's
--                        JOIN sent them here, or which page if the game's
--                        Return To Lobby did
--
-- server -> client:
--   "list", key, rows, own      the sessions this player may see (Row, plus
--                               Friend), own = their own session's row, or
--                               nil while loading
--   "state", key, hostId, state what the panel shows (State), nil = gone
--   "rejoin", info              a live match to go back to, once per server
--   "counts", tally, live       per mode: { Online, Sessions } of the listed
--                               sessions, for the tiles; live = which modes
--                               have a place in this universe
--   "friends", rows             Friends.lua rows
--   "follow", userId            open this friend's session (they sent you)
--   "open", key                 open this mode's page (back from that game mode)
--
-- Visibility: a private session is listed only to its host and the players
-- already in it (a tourney lobby's rosters, a free roam server's co-hosts);
-- friends to the host's friends; public to everyone. The
-- lists are per player (friendship), so each is one FireClient.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)
local tourney = require(script.Parent.Tourney)
local freeroam = require(script.Parent.Freeroam)
local teleports = require(script.Parent.Teleports)
local friendsLibrary = require(script.Parent.Friends)

local remote = replicatedStorage.Remotes.Private

local library = {}

----

local CLASSES = {
	Tourney = tourney,
	Freeroam = freeroam,
}

-- seconds between actions a client may send
local ACT_GAP = 0.1

-- [key] = { [userId] = session }
local sessions = {}

-- [client] = the mode key whose list they're looking at
local listing = {}

-- [client] = { Key, HostId } of the session on their screen
local viewing = {}

-- [client] = { [hostId] = true }: their friend list, read once per open with
-- GetFriendsAsync (a few pages) instead of one IsFriendsWith per host; nil
-- while it loads, and the list goes out again when it lands
local friends = {}

-- [client] = os.clock() of their last action
local lastAct = {}

-- [client] = true once their live match was looked up
local rejoinLooked = {}

-- [key] = the mode's place in this universe, from Directory
local places = {}

-- [key] = true while a list broadcast is queued
local listQueued = {}

for _, mode in private.Modes do
	sessions[mode.Key] = {}
end

----

local function isFriend(client, hostId)
	local set = friends[client]

	return set ~= nil and set[hostId] == true
end

local sendList

-- reads the player's friends once; FRIEND_PAGE_CAP pages keeps a huge list
-- from costing more than a few calls
local FRIEND_PAGE_CAP = 10

local function loadFriends(client)
	if friends[client] then
		return
	end

	task.spawn(function()
		local set = {}

		pcall(function()
			local pages = playersService:GetFriendsAsync(client.UserId)

			for _ = 1, FRIEND_PAGE_CAP do
				for _, entry in pages:GetCurrentPage() do
					set[entry.Id] = true
				end

				if pages.IsFinished then
					break
				end

				pages:AdvanceToNextPageAsync()
			end
		end)

		if not client.Parent then
			return
		end

		friends[client] = set

		if listing[client] then
			sendList(client, listing[client])
		end
	end)
end

local function canSee(client, session)
	if session:IsHost(client) or session:IsMember(client) then
		return true
	end

	local visibility = session:Visibility()

	if visibility == "public" then
		return true
	elseif visibility == "friends" then
		return isFriend(client, session.HostId)
	end

	return false
end

local function sortRows(a, b)
	if a.Mine ~= b.Mine then
		return a.Mine
	end

	if a.Full ~= b.Full then
		return b.Full
	end

	if a.Locked ~= b.Locked then
		return b.Locked
	end

	if a.Players ~= b.Players then
		return (a.Players or -1) > (b.Players or -1)
	end

	return a.Host < b.Host
end

function sendList(client, key)
	if listing[client] ~= key or not client.Parent then
		return
	end

	local rows = {}
	local own = nil

	for hostId, session in sessions[key] do
		if canSee(client, session) then
			local row = session:Row(client)
			row.Friend = not row.Mine and isFriend(client, hostId)

			if row.Mine then
				own = row
			else
				table.insert(rows, row)
			end
		end
	end

	table.sort(rows, sortRows)

	if client.Parent then
		remote:FireClient(client, "list", key, rows, own)
	end
end

-- the tiles' numbers: everyone listed (not private) and who's in them
local countsQueued = false

local function tally()
	local counts = {}

	for key, byHost in sessions do
		local online, listed = 0, 0

		for _, session in byHost do
			if session:Visibility() ~= "private" then
				listed += 1
				local row = session:Row(nil)
				online += row.Players or 0
			end
		end

		counts[key] = { Online = online, Sessions = listed }
	end

	return counts
end

local function sendCounts(client)
	local live = {}

	for key in sessions do
		live[key] = places[key] ~= nil
	end

	if client.Parent then
		remote:FireClient(client, "counts", tally(), live)
	end
end

local function broadcastCounts()
	if countsQueued then
		return
	end

	countsQueued = true

	task.defer(function()
		countsQueued = false

		for _, client in playersService:GetPlayers() do
			sendCounts(client)
		end
	end)
end

-- lists change for everyone looking at the mode; coalesced to one send per
-- player per frame
local function broadcastList(key)
	if listQueued[key] then
		return
	end

	listQueued[key] = true

	task.defer(function()
		listQueued[key] = nil

		for client, open in listing do
			if open == key then
				task.spawn(sendList, client, key)
			end
		end
	end)

	broadcastCounts()
end

local function sendState(client)
	local view = viewing[client]

	if not view or not client.Parent then
		return
	end

	local session = sessions[view.Key][view.HostId]

	if session and canSee(client, session) then
		remote:FireClient(client, "state", view.Key, view.HostId, session:State(client))
	else
		remote:FireClient(client, "state", view.Key, view.HostId, nil)
	end
end

local function broadcastState(key, hostId)
	for client, view in viewing do
		if view.Key == key and view.HostId == hostId then
			sendState(client)
		end
	end
end

----

-- the player's own session for a mode, made on first use. The config read
-- yields, so the list goes out without it and again once it's there
local creating = {}

local function ensureSession(client, key)
	local userId = client.UserId
	local existing = sessions[key][userId]

	if existing then
		return existing
	end

	creating[client] = creating[client] or {}

	if creating[client][key] then
		return nil
	end

	creating[client][key] = true

	task.spawn(function()
		local class = CLASSES[key]
		local saved = class.Load(userId)

		if not client.Parent or sessions[key][userId] then
			return
		end

		local session

		local function sync(what)
			if what == "state" then
				broadcastState(key, userId)
			elseif what == "list" then
				broadcastList(key)
			end
		end

		session = class.new(client, saved, sync, places[key])
		sessions[key][userId] = session

		if creating[client] then
			creating[client][key] = nil
		end

		broadcastList(key)
		broadcastState(key, userId)
	end)

	return nil
end

-- a live match the player can go back to; told once per server
local function lookupRejoin(client)
	if rejoinLooked[client] then
		return
	end

	rejoinLooked[client] = true

	task.spawn(function()
		local info = tourney.Rejoin(client.UserId)

		if info and client.Parent then
			remote:FireClient(client, "rejoin", info)
			rejoinLooked[client] = info
		end
	end)
end

----

local handlers = {}

function handlers.open(client, key)
	if not CLASSES[key] then
		return
	end

	listing[client] = key

	loadFriends(client)
	ensureSession(client, key)
	sendList(client, key)

	if key == "Tourney" then
		lookupRejoin(client)
	end
end

function handlers.close(client)
	listing[client] = nil
	viewing[client] = nil
end

function handlers.unview(client)
	viewing[client] = nil
end

function handlers.view(client, key, hostId)
	hostId = tonumber(hostId)

	if not CLASSES[key] or not hostId then
		return
	end

	if hostId == client.UserId then
		ensureSession(client, key)
	end

	viewing[client] = { Key = key, HostId = hostId }
	sendState(client)
end

function handlers.act(client, key, hostId, action, ...)
	hostId = tonumber(hostId)

	if not CLASSES[key] or not hostId or type(action) ~= "string" then
		return
	end

	local session = sessions[key][hostId]

	if not session or not canSee(client, session) then
		return
	end

	-- one lobby at a time: joining a tourney lobby leaves any other
	if key == "Tourney" and action == "join" then
		for otherId, other in sessions[key] do
			if otherId ~= hostId and other:IsMember(client) then
				other:Act(client, "leave")
				broadcastState(key, otherId)
			end
		end
	end

	local stateChanged, listChanged = session:Act(client, action, ...)

	if stateChanged then
		broadcastState(key, hostId)
	end

	if listChanged then
		broadcastList(key)
	end
end

function handlers.friends(client, online)
	local rows = friendsLibrary:List(client, online)

	if client.Parent then
		remote:FireClient(client, "friends", rows)
	end
end

function handlers.follow(client, userId)
	friendsLibrary:Follow(client, userId)
end

function handlers.ready(client)
	local arrival = friendsLibrary:ArrivedFor(client)

	if not arrival or not client.Parent then
		return
	end

	if arrival.followId then
		remote:FireClient(client, "follow", arrival.followId)
	elseif arrival.mode then
		remote:FireClient(client, "open", arrival.mode)
	end
end

function handlers.rejoin(client)
	local info = rejoinLooked[client]

	if type(info) ~= "table" then
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = info.AccessCode

	teleports:SendPrivate(client, info.PlaceId, options, private.ByKey.Tourney.Name)
end

----

local function onLeave(client)
	for key, byHost in sessions do
		local own = byHost[client.UserId]

		if own then
			own:Destroy()
			byHost[client.UserId] = nil
			broadcastState(key, client.UserId)
		end

		for _, session in byHost do
			session:OnLeave(client)
		end

		broadcastList(key)
	end

	listing[client] = nil
	viewing[client] = nil
	friends[client] = nil
	lastAct[client] = nil
	rejoinLooked[client] = nil
	creating[client] = nil
	friendsLibrary:Forget(client)
end

function library:Start(directory)
	friendsLibrary:Start(directory)

	for _, mode in private.Modes do
		places[mode.Key] = directory:PlaceFor(mode.PlaceIds)

		if not places[mode.Key] then
			warn("Lobby has no", mode.Name, "place in this universe; its sessions can't start")
		end
	end

	remote.OnServerEvent:Connect(function(client, action, ...)
		local handler = handlers[action]

		if not handler then
			return
		end

		local now = os.clock()

		if (action == "act" or action == "friends" or action == "follow") and now - (lastAct[client] or 0) < ACT_GAP then
			return
		end

		lastAct[client] = now
		handler(client, ...)
	end)

	playersService.PlayerAdded:Connect(sendCounts)

	for _, client in playersService:GetPlayers() do
		sendCounts(client)
	end

	playersService.PlayerRemoving:Connect(onLeave)
end

return library
