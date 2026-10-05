-- Find friends: where a player's friends are in AR2 and following them there.
-- Asked for over Remotes.Private ("friends" to list, "follow" to go), run by
-- Sessions.lua.
--
-- GetFriendsOnlineAsync only runs on the client, so the client sends what
-- it got (user, place, server, location type) and this checks and describes
-- it. A client could invent an entry, which would only ever send itself to
-- one of our own places by server id, as anyone can from the website.
--
-- Where a friend is: a map place (a row with the map, the server's name and,
-- when the directory lists it, its players and region), this lobby place (a
-- lobby server; following lands there with followId in the teleport data,
-- so the client opens that friend's session), a private place (shown, not
-- joinable from here yet) or elsewhere. The client asks at most once per
-- FRIENDS_CACHE seconds.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local protocol = require(replicatedStorage.Shared.Protocol)
local private = require(replicatedStorage.Shared.Private)
local names = require(replicatedStorage.Shared.Names)
local catalog = require(script.Parent.Catalog)
local teleports = require(script.Parent.Teleports)

local library = {}

----

local FRIENDS_CACHE = 30
local MAX_FRIENDS = 200
local NAME_LENGTH = 20

-- GetFriendsOnline LocationType values that mean "in a server"
local IN_GAME = { [1] = true, [4] = true }

-- [client] = { at, entries = { [userId] = raw entry }, rows }
local cache = {}

local directory = nil

----

local function privateModeFor(placeId)
	for _, mode in private.Modes do
		if table.find(mode.PlaceIds, placeId) then
			return mode
		end
	end

	return nil
end

-- a row for the client: { UserId, Name, Where, Detail, Players?, Max?, Joinable, Title? }
local function describe(entry)
	local row = {
		UserId = entry.VisitorId,
		Name = entry.UserName,
		Where = "ONLINE",
		Detail = type(entry.LastLocation) == "string" and entry.LastLocation or "",
		Joinable = false,
	}

	local placeId = tonumber(entry.PlaceId)
	local jobId = type(entry.GameId) == "string" and entry.GameId or nil

	if not IN_GAME[entry.LocationType] or not placeId then
		return row
	end

	if placeId == game.PlaceId then
		row.Where = "LOBBY"
		row.Detail = jobId and ("Lobby  ·  " .. names:ForJob(jobId)) or "Lobby"
		row.Joinable = jobId ~= nil and jobId ~= game.JobId
		row.Title = "Lobby"

		return row
	end

	local mapKey = directory:MapForPlace(placeId)

	if mapKey then
		local map = catalog.ByKey[mapKey]
		local server = jobId and directory:Server(mapKey, jobId)
		local parts = { map.Name }

		if jobId then
			table.insert(parts, names:ForJob(jobId))
		end

		if server then
			table.insert(parts, server.Location or server.Region or nil)
			row.Players = server.Players
			row.Max = server.Max
		end

		row.Where = "IN GAME"
		row.Detail = table.concat(parts, "  ·  ")
		row.Joinable = jobId ~= nil and (server == nil or server.Players < server.Max)
		row.Title = map.Title or map.Name

		return row
	end

	local mode = privateModeFor(placeId)

	if mode then
		row.Where = mode.Key == "Tourney" and "IN MATCH" or "FREE ROAM"
		row.Detail = mode.Name
	else
		row.Where = "ELSEWHERE"
		row.Detail = "Playing something else"
	end

	return row
end

local function sortRows(a, b)
	if a.Joinable ~= b.Joinable then
		return a.Joinable
	end

	if (a.Where == "ONLINE") ~= (b.Where == "ONLINE") then
		return b.Where == "ONLINE"
	end

	return a.Name:lower() < b.Name:lower()
end

----

-- one of the client's entries, checked, or nil
local function clean(raw)
	if type(raw) ~= "table" then
		return nil
	end

	local userId = tonumber(raw.VisitorId)
	local userName = raw.UserName

	if not userId or userId <= 0 or type(userName) ~= "string" or userName == "" then
		return nil
	end

	local placeId = tonumber(raw.PlaceId)
	local jobId = raw.GameId

	if type(jobId) ~= "string" or jobId == "" or #jobId > 64 then
		jobId = nil
	end

	return {
		VisitorId = math.floor(userId),
		UserName = userName:sub(1, NAME_LENGTH),
		LastLocation = type(raw.LastLocation) == "string" and raw.LastLocation:sub(1, 64) or "",
		PlaceId = placeId and math.floor(placeId) or nil,
		GameId = jobId,
		LocationType = tonumber(raw.LocationType),
	}
end

-- the rows for what the client's GetFriendsOnlineAsync returned; the cache
-- answers repeats inside FRIENDS_CACHE and is what Follow trusts
function library:List(client, online)
	local held = cache[client]

	if held and os.clock() - held.at < FRIENDS_CACHE then
		return held.rows
	end

	if type(online) ~= "table" then
		return held and held.rows or {}
	end

	local entries = {}
	local rows = {}

	for index, raw in online do
		if index > MAX_FRIENDS then
			break
		end

		local entry = clean(raw)

		if entry and not entries[entry.VisitorId] then
			entries[entry.VisitorId] = entry
			table.insert(rows, describe(entry))
		end
	end

	table.sort(rows, sortRows)
	cache[client] = { at = os.clock(), entries = entries, rows = rows }

	return rows
end

-- sends the player to the friend's server, if the last list said they can
function library:Follow(client, userId)
	local held = cache[client]
	local entry = held and held.entries[tonumber(userId)]

	if not entry then
		return teleports:Refuse(client, "closed")
	end

	local row = describe(entry)

	if not row.Joinable then
		return teleports:Refuse(client, "closed")
	end

	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = entry.GameId

	if entry.PlaceId == game.PlaceId then
		options:SetTeleportData({
			source = protocol.SOURCE,
			v = protocol.VERSION,
			followId = entry.VisitorId,
		})
	elseif catalog.IsTest then
		options:SetTeleportData({ source = protocol.HUB_SOURCE, v = protocol.HUB_VERSION })
	else
		options:SetTeleportData({
			source = protocol.SOURCE,
			v = protocol.VERSION,
			map = directory:MapForPlace(entry.PlaceId),
		})
	end

	teleports:SendPrivate(client, entry.PlaceId, options, row.Title)
end

-- a lobby arrival sent by a friend's JOIN: the friend to open on landing
function library:FollowedFrom(client)
	local worked, data = pcall(function()
		local joinData = client:GetJoinData()

		return joinData and joinData.TeleportData
	end)

	if worked and type(data) == "table" and data.source == protocol.SOURCE and tonumber(data.followId) then
		return tonumber(data.followId)
	end

	return nil
end

function library:Forget(client)
	cache[client] = nil
end

function library:Start(directoryLibrary)
	directory = directoryLibrary
end

return library
