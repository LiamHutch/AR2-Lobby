-- A host's whitelist: players who may see and join their session whatever
-- its visibility (and, on free roam, get past the server lock without a
-- co-host's powers), so a community tourney host on private or friends can
-- let in people who aren't friends. Stored in the host's config as
-- whitelist = { [userId string] = true } (Shared/Private.lua), kept by
-- Tourney.lua and Freeroam.lua, edited from the lobby by pasting usernames
-- or user ids, commas between them for a bulk import.
--
-- The name lookups both modes need live here too: a user id's name for the
-- rows, and a pasted entry's id for an add.

local playersService = game:GetService("Players")

local library = {}

----

-- most entries a list holds; keeps the record and its name lookups small
library.CAP = 100

-- [userId] = name, false while it loads
local names = {}

-- fired when a looked-up name lands, so the rows showing "…" can redraw
library.NameLoaded = Instance.new("BindableEvent")

-- [lower name] = userId, once a name was found (a miss isn't kept: it may
-- have been an outage)
local ids = {}

----

-- a saved set as { [userId string] = true }, capped
function library:Sanitize(raw)
	local set = {}
	local count = 0

	for key, value in type(raw) == "table" and raw or {} do
		if tonumber(key) and value and count < self.CAP then
			set[tostring(key)] = true
			count += 1
		end
	end

	return set
end

function library:Has(set, userId)
	return set[tostring(userId)] == true
end

function library:Count(set)
	local count = 0

	for _ in set do
		count += 1
	end

	return count
end

-- adds a user id; false and why when it can't ("self", "already", "full")
function library:Add(set, userId, hostId)
	userId = tonumber(userId)

	if not userId or userId == hostId then
		return false, "self"
	end

	if set[tostring(userId)] then
		return false, "already"
	end

	if self:Count(set) >= self.CAP then
		return false, "full"
	end

	set[tostring(userId)] = true
	self:NameOf(userId)

	return true
end

function library:Remove(set, userId)
	userId = tonumber(userId)

	if not userId or not set[tostring(userId)] then
		return false
	end

	set[tostring(userId)] = nil

	return true
end

----

-- a user id's name, looked up once per server; nil until it's known
function library:NameOf(userId)
	userId = tonumber(userId)

	if not userId then
		return nil
	end

	if names[userId] == nil then
		names[userId] = false

		task.spawn(function()
			local found, name = pcall(playersService.GetNameFromUserIdAsync, playersService, userId)
			names[userId] = found and name or string.format("[%d]", userId)
			library.NameLoaded:Fire()
		end)
	end

	return names[userId] or nil
end

-- a set as rows { UserId, Name }, by name
function library:People(set)
	local list = {}

	for userId in set do
		table.insert(list, { UserId = tonumber(userId), Name = self:NameOf(userId) })
	end

	table.sort(list, function(a, b)
		return (a.Name or "") < (b.Name or "")
	end)

	return list
end

-- the entries in what a host typed or pasted: usernames or user ids, split
-- on commas (and whitespace or newlines: a name holds neither), without
-- repeats, at most CAP of them
function library:Entries(text)
	local entries, seen = {}, {}

	if type(text) ~= "string" then
		return entries
	end

	for entry in text:gmatch("[^,;%s]+") do
		entry = entry:gsub("^@", "")
		local key = entry:lower()

		if entry ~= "" and #entry <= 20 and not seen[key] and #entries < self.CAP then
			seen[key] = true
			table.insert(entries, entry)
		end
	end

	return entries
end

-- one entry's user id: someone in this server, a user id (checked to exist),
-- or a username looked up on Roblox. nil and "unknown" when it's nobody; the
-- third value says a web call was made
local function lookup(entry)
	local present = playersService:FindFirstChild(entry)

	if present and present:IsA("Player") then
		names[present.UserId] = present.Name

		return present.UserId
	end

	local id = tonumber(entry)

	if id then
		if id ~= math.floor(id) or id <= 0 then
			return nil, "unknown"
		end

		-- known already (a row's name), unless that lookup failed
		local known = names[id]

		if type(known) == "string" and known:sub(1, 1) ~= "[" then
			return id
		end

		local found, name = pcall(playersService.GetNameFromUserIdAsync, playersService, id)

		if not found then
			return nil, "unknown", true
		end

		names[id] = name

		return id, nil, true
	end

	local lower = entry:lower()

	if ids[lower] then
		return ids[lower]
	end

	local found, userId = pcall(playersService.GetUserIdFromNameAsync, playersService, entry)

	if not found or not tonumber(userId) then
		return nil, "unknown", true
	end

	ids[lower] = tonumber(userId)

	-- the typed casing may differ from the account's; the row shows the real one
	library:NameOf(ids[lower])

	return ids[lower], nil, true
end

-- seconds between web lookups in one paste
local LOOKUP_PAUSE = 0.2

-- [client] = true while a paste of theirs is being looked up
local busy = {}

-- every entry in what a host typed or pasted, looked up in turn (yields):
-- { { Entry, UserId?, Code? } }. One paste at a time per host: nil and
-- "slow" while the last one is still going
function library:Resolve(client, text)
	if busy[client] then
		return nil, "slow"
	end

	busy[client] = true

	local results = {}
	local fetched = false

	for _, entry in self:Entries(text) do
		if fetched then
			task.wait(LOOKUP_PAUSE)
		end

		local userId, code, web = lookup(entry)
		fetched = web == true

		table.insert(results, { Entry = entry, UserId = userId, Code = code })
	end

	busy[client] = nil

	return results
end

function library:Forget(client)
	busy[client] = nil
end

return library
