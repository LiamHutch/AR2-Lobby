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
--                        any other lobby first; "whitelist", text takes
--                        typed or pasted usernames and user ids, commas
--                        between, looked up here (Whitelist.lua)
--   "unview"             back to the list
--   "rejoin"             back into a live match (Tourney.Rejoin)
--   "friends", entries   what the client's GetFriendsOnlineAsync returned;
--                        answered with where they are (Friends.lua)
--   "invite", key, userId   invite a friend to the session you host (Invites.lua)
--   "accept", id / "decline", id   answer an invite
--   "follow", userId     go to that friend's server
--   "go", key, hostId    go to the lobby server hosting a session listed
--                        from another server (Listings.lua); the host's
--                        page opens on arrival, like a friend's JOIN
--   "ready"              the client is up: told who to open if a friend's
--                        JOIN sent them here, or which page if the game's
--                        Return To Lobby did
--
-- server -> client:
--   "list", key, rows, own      the sessions this player may see (Row, plus
--                               Friend and Whitelisted; Remote for one hosted
--                               in another lobby server, which JOIN goes to
--                               with "go"), own = their own session's row,
--                               or nil while loading
--   "state", key, hostId, state what the panel shows (State), nil = gone
--   "rejoin", info              a live match to go back to, once per server
--   "counts", tally, live       per mode: { Online, Sessions } of the
--                               sessions this player could join (listed to
--                               them, not their own, not full or locked
--                               against them), for the tiles; live = which
--                               modes have a place in this universe
--   "friends", rows             Friends.lua rows
--   "follow", userId, key?      open this friend's session (they sent you or
--                               invited you); key says which mode
--   "invite", info              an invite: { Id, From, FromName, Key, Same }
--   "invited", userId, sent, code   the answer to an "invite" 
--   "whitelisted", added, failed, code   the answer to a "whitelist" act:
--                               added = the entries that took, failed =
--                               { { Entry, Code } } with Code = "unknown" |
--                               "self" | "already" | "full" | "banned" |
--                               "failed"; code = "slow" (a paste is still
--                               being looked up) or "empty" (nothing in it)
--   "open", key                 open this mode's page (back from that game mode)
--
-- Visibility: a private session is listed only to its host and the players
-- already in it (a tourney lobby's rosters, a free roam server's co-hosts);
-- friends to the host's friends; public to everyone. The host's whitelist
-- and anyone they invited see it whatever the visibility. The lists are per
-- player (friendship, whitelist), so each is one FireClient. Sessions in
-- other lobby servers are listed too (Listings.lua), under the same rules
-- bar invites, with JOIN taking the player to the host's server.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)
local tourney = require(script.Parent.Tourney)
local freeroam = require(script.Parent.Freeroam)
local teleports = require(script.Parent.Teleports)
local friendsLibrary = require(script.Parent.Friends)
local invites = require(script.Parent.Invites)
local subscriptions = require(script.Parent.Subscriptions)
local catalog = require(script.Parent.Catalog)
local whitelist = require(script.Parent.Whitelist)
local listings = require(script.Parent.Listings)

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

local function canSee(client, session, key)
	if session:IsHost(client) or session:IsMember(client) or session:IsWhitelisted(client) then
		return true
	end

	-- an invite from the host opens a private session to them for a while
	if invites:IsInvited(key, session.HostId, client.UserId) then
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

-- a session another lobby server listed: the same rules as a local one, bar
-- invites (an invite carries the player over itself)
local function canSeeRemote(client, record)
	if listings:Whitelisted(record, client.UserId) then
		return true
	end

	if record.visibility == "public" then
		return true
	elseif record.visibility == "friends" then
		return isFriend(client, record.hostId)
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
		if canSee(client, session, key) then
			local row = session:Row(client)
			row.Friend = not row.Mine and isFriend(client, hostId)
			row.Whitelisted = not row.Mine and session:IsWhitelisted(client)

			if row.Mine then
				own = row
			else
				table.insert(rows, row)
			end
		end
	end

	-- the other servers' sessions; a host's own server knows best, and a
	-- host who moved here is already listed above
	for hostId, record in listings:Remote(key) do
		if not sessions[key][hostId] and hostId ~= client.UserId and canSeeRemote(client, record) then
			local row = table.clone(record.row)
			row.HostId = hostId
			row.Host = tostring(record.hostName)
			row.Mine = false
			row.Friend = isFriend(client, hostId)
			row.Whitelisted = listings:Whitelisted(record, client.UserId)
			row.Remote = true

			table.insert(rows, row)
		end
	end

	table.sort(rows, sortRows)

	if client.Parent then
		remote:FireClient(client, "list", key, rows, own)
	end
end

-- the tiles' numbers for one player: the sessions they could join up on
-- (listed to them, not their own, not full, not locked against them) and
-- who's in them
local countsQueued = false

-- a locked free roam server still takes the host's whitelist (and co-hosts,
-- which only the local session knows)
local function joinable(key, row, allowed)
	if row.Full then
		return false
	end

	return not row.Locked or (key == "Freeroam" and allowed)
end

local function tally(client)
	local counts = {}

	for key, byHost in sessions do
		local online, listed = 0, 0

		for _, session in byHost do
			if not session:IsHost(client) and canSee(client, session, key) then
				local row = session:Row(client)

				if joinable(key, row, session.MayEnter ~= nil and session:MayEnter(client)) then
					listed += 1
					online += row.Players or 0
				end
			end
		end

		for hostId, record in listings:Remote(key) do
			if not byHost[hostId] and hostId ~= client.UserId and canSeeRemote(client, record) then
				if joinable(key, record.row, listings:Whitelisted(record, client.UserId)) then
					listed += 1
					online += record.row.Players or 0
				end
			end
		end

		counts[key] = { Online = online, Sessions = listed }
	end

	return counts
end

-- on the test lobby the private modes take the same testing permissions as
-- its maps: a group role in one of these tiers. The prod lobby is open to all
local TEST_ACCESS = { "Tester", "Staff", "Developer" }

-- whether this client may use a mode here: its place is in this universe,
-- and on the test lobby they hold a testing role
local function allowed(client, key)
	if not places[key] then
		return false
	end

	return not catalog.IsTest or catalog:CanSee(client, { Access = TEST_ACCESS })
end

local function sendCounts(client)
	local live = {}

	for key in sessions do
		live[key] = allowed(client, key)
	end

	if client.Parent then
		remote:FireClient(client, "counts", tally(client), live)
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

-- a local session changed in a way its row shows: the other servers get the
-- new record, and the lists here go out
local function publishList(key, session)
	if session then
		listings:Publish(key, session.HostId, session.HostName, session:Listing())
	end

	broadcastList(key)
end

local function sendState(client)
	local view = viewing[client]

	if not view or not client.Parent then
		return
	end

	local session = sessions[view.Key][view.HostId]

	if session and canSee(client, session, view.Key) then
		local state = session:State(client)

		-- the host's own view: whether public is open to them
		if state and state.Mine then
			state.CanPublic = subscriptions:CanPublic(client)
		end

		remote:FireClient(client, "state", view.Key, view.HostId, state)
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
				publishList(key, session)
			end
		end

		session = class.new(client, saved, sync, places[key])
		sessions[key][userId] = session

		-- a public session whose host's subscription lapsed drops to friends
		if session:Visibility() == "public" and client.Parent and not subscriptions:CanPublic(client) then
			session:Act(client, "visibility", "friends")
		end

		if creating[client] then
			creating[client][key] = nil
		end

		publishList(key, session)
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

-- a looked-up name landing: the panels showing "…" for it redraw, once per frame
local namesQueued = false

whitelist.NameLoaded.Event:Connect(function()
	if namesQueued then
		return
	end

	namesQueued = true

	task.defer(function()
		namesQueued = false

		for client in viewing do
			sendState(client)
		end
	end)
end)

-- a purchase prompt closing: the host's own view shows the new answer
subscriptions.Changed.Event:Connect(function(client)
	local view = viewing[client]

	if view and view.HostId == client.UserId then
		sendState(client)
	end
end)

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

	if not session or not canSee(client, session, key) then
		return
	end

	-- public is paid: without the subscription, the purchase prompt instead
	if action == "visibility" and (...) == "public" and not subscriptions:CanPublic(client) then
		subscriptions:Offer(client, remote)

		return
	end

	-- a whitelist add comes as typed or pasted names and ids: looked up here
	-- (it yields), and the host hears back what took and what didn't
	if action == "whitelist" then
		if not session:IsHost(client) then
			return
		end

		local results, code = whitelist:Resolve(client, (...))
		local added, failed = {}, {}

		for _, result in results or {} do
			local why = result.Code

			if result.UserId then
				local stateChanged, _, actCode = session:Act(client, action, result.UserId)

				if stateChanged then
					table.insert(added, result.Entry)
					why = nil
				else
					why = actCode or "failed"
				end
			end

			if why then
				table.insert(failed, { Entry = result.Entry, Code = why })
			end
		end

		if results and #results == 0 then
			code = "empty"
		end

		if #added > 0 then
			broadcastState(key, hostId)
			publishList(key, session)
		end

		if client.Parent then
			remote:FireClient(client, "whitelisted", added, failed, code)
		end

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
		publishList(key, session)
	end
end

-- a session another lobby server listed: off to that server, with the
-- follow data that opens the host's page on arrival
function handlers.go(client, key, hostId)
	hostId = tonumber(hostId)
	local record = CLASSES[key] and hostId and listings:Find(key, hostId)

	if not record or sessions[key][hostId] or not canSeeRemote(client, record) then
		return teleports:Refuse(client, "closed")
	end

	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = record.jobId
	options:SetTeleportData({
		source = protocol.SOURCE,
		v = protocol.VERSION,
		followId = hostId,
		mode = key,
	})

	teleports:SendPrivate(client, record.placeId, options, "Lobby")
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
		remote:FireClient(client, "follow", arrival.followId, arrival.mode)
	elseif arrival.mode then
		remote:FireClient(client, "open", arrival.mode)
	end
end

-- a host invites a friend (by user id, from the Friends page) to the session
-- they host in this server
function handlers.invite(client, key, userId)
	local session = CLASSES[key] and sessions[key][client.UserId]

	if not session then
		return
	end

	local sent, code = invites:Send(client, key, userId)

	if client.Parent then
		remote:FireClient(client, "invited", userId, sent, code)
	end
end

function handlers.accept(client, id)
	if type(id) == "string" then
		invites:Accept(client, id)
	end
end

function handlers.decline(client, id)
	if type(id) == "string" then
		invites:Decline(client, id)
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
			listings:Retract(key, client.UserId)
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
	invites:Forget(client)
	whitelist:Forget(client)
end

function library:Start(directory)
	friendsLibrary:Start(directory)
	listings:Start()

	-- the other servers' sessions changed: every open list
	listings.Changed.Event:Connect(function()
		for key in sessions do
			broadcastList(key)
		end
	end)

	-- an invite accepted in the host's own server: open their page here
	invites:Start(function(client, hostId, key)
		if client.Parent then
			remote:FireClient(client, "follow", hostId, key)
		end
	end)

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

		if (action == "act" or action == "friends" or action == "follow" or action == "go") and now - (lastAct[client] or 0) < ACT_GAP then
			return
		end

		-- the mode actions take the mode as their first argument; the tile is
		-- hidden without permission, so this only stops a forged message
		if (action == "open" or action == "view" or action == "act" or action == "invite" or action == "go") and not allowed(client, (...)) then
			return
		end

		if action == "rejoin" and not allowed(client, "Tourney") then
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
