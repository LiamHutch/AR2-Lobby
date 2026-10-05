-- Lobby-to-lobby invites: a host asks a friend who's in some lobby server
-- over to their tourney lobby or free roam server. Each player has a
-- MessagingService topic (Protocol.INVITE_TOPIC_PREFIX .. userId) that the
-- server holding them subscribes to on join and drops on leave, so an invite
-- only ever reaches the one server that can show it. Accepting in the same server
-- opens the host's page; from another server it's a teleport by server id
-- with the follow data the Friends page uses, so the page opens on arrival.
-- The host's server remembers who it invited (IsInvited) so a private session
-- is visible to them while the invite lasts. Lobby only: nothing in game.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local messagingService = game:GetService("MessagingService")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)
local teleports = require(script.Parent.Teleports)

local remote = replicatedStorage.Remotes.Private

local library = {}

----

-- most invites a host can have out at once
local MAX_OUT = 20

local offline = runService:IsStudio() and game.GameId == 0

-- [key] = { [hostId] = { [userId] = expiresAt } }: who this server's hosts invited
local invited = {}

-- [client] = { [inviteId] = message }: invites shown to a player here
local pending = {}

-- [client] = os.clock() of their last invite sent
local lastSent = {}

-- [client] = their topic's subscription
local subscriptions = {}

local onDeliver = nil

for _, mode in private.Modes do
	invited[mode.Key] = {}
end

----

local function topicFor(userId)
	return protocol.INVITE_TOPIC_PREFIX .. userId
end

local function prune(set)
	local now = os.time()

	for userId, expiresAt in set do
		if expiresAt <= now then
			set[userId] = nil
		end
	end
end

local function deliver(message)
	local target = playersService:GetPlayerByUserId(tonumber(message.to) or 0)

	if not target then
		return
	end

	-- an old message from a topic replay
	if type(message.at) ~= "number" or os.time() - message.at > protocol.INVITE_TTL then
		return
	end

	local id = httpService:GenerateGUID(false)
	pending[target] = pending[target] or {}
	pending[target][id] = message

	remote:FireClient(target, "invite", {
		Id = id,
		From = message.from,
		FromName = message.fromName,
		Key = message.key,
		Same = message.jobId == game.JobId,
	})

	task.delay(protocol.INVITE_TTL, function()
		if pending[target] then
			pending[target][id] = nil
		end
	end)
end

----

-- true while hostId's invite to userId stands
function library:IsInvited(key, hostId, userId)
	local byHost = invited[key] and invited[key][hostId]

	if not byHost then
		return false
	end

	prune(byHost)

	return byHost[userId] ~= nil
end

-- sends an invite to a friend's user id for the session the client hosts;
-- the caller checks the client has one. Returns false and a status code
-- when it can't
function library:Send(client, key, userId)
	userId = tonumber(userId)

	if not invited[key] or not userId or userId == client.UserId then
		return false, "failed"
	end

	local now = os.clock()

	if now - (lastSent[client] or -protocol.INVITE_GAP) < protocol.INVITE_GAP then
		return false, "slow"
	end

	lastSent[client] = now

	local byHost = invited[key][client.UserId] or {}
	invited[key][client.UserId] = byHost
	prune(byHost)

	local out = 0

	for _ in byHost do
		out += 1
	end

	if out >= MAX_OUT then
		return false, "slow"
	end

	byHost[userId] = os.time() + protocol.INVITE_TTL

	local message = {
		to = userId,
		from = client.UserId,
		fromName = client.Name,
		key = key,
		jobId = game.JobId,
		placeId = game.PlaceId,
		at = os.time(),
	}

	-- a friend in this server hears it straight away; others through their topic
	if playersService:GetPlayerByUserId(userId) then
		deliver(message)

		return true
	end

	if offline then
		return true
	end

	local published, why = pcall(messagingService.PublishAsync, messagingService, topicFor(userId), message)

	if not published then
		warn("Lobby couldn't send an invite:", why)

		return false, "failed"
	end

	return true
end

-- the player takes an invite: here, the host's page; elsewhere, a teleport
-- to the host's server that opens it on arrival
function library:Accept(client, id)
	local message = pending[client] and pending[client][id]

	if not message then
		return teleports:Refuse(client, "closed")
	end

	pending[client][id] = nil

	if message.jobId == game.JobId then
		if onDeliver then
			onDeliver(client, message.from, message.key)
		end

		return
	end

	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = message.jobId
	options:SetTeleportData({
		source = protocol.SOURCE,
		v = protocol.VERSION,
		followId = message.from,
		mode = message.key,
	})

	teleports:SendPrivate(client, message.placeId, options, "Lobby")
end

function library:Decline(client, id)
	if pending[client] then
		pending[client][id] = nil
	end
end

function library:Forget(client)
	pending[client] = nil
	lastSent[client] = nil

	if subscriptions[client] then
		subscriptions[client]:Disconnect()
		subscriptions[client] = nil
	end

	for _, byKey in invited do
		byKey[client.UserId] = nil
	end
end

-- listens on the player's own topic while they're here
local function listen(client)
	if offline or subscriptions[client] then
		return
	end

	task.spawn(function()
		local subscribed, connection = pcall(messagingService.SubscribeAsync, messagingService, topicFor(client.UserId), function(packet)
			if type(packet.Data) == "table" and tonumber(packet.Data.to) == client.UserId then
				deliver(packet.Data)
			end
		end)

		if not subscribed then
			warn("Lobby couldn't listen for invites to", client.Name, connection)

			return
		end

		-- they left while the subscribe was in flight
		if not client.Parent then
			connection:Disconnect()

			return
		end

		subscriptions[client] = connection
	end)
end

-- sameServer(client, hostId, key) is what an accepted invite in this server does
function library:Start(sameServer)
	onDeliver = sameServer

	playersService.PlayerAdded:Connect(listen)

	for _, client in playersService:GetPlayers() do
		listen(client)
	end
end

return library
