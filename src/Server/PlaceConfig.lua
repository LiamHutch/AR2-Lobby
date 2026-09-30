-- Map configs kept in the place instead of git, so they can be edited in
-- Studio and published without the repo. Each lobby has its own root, picked
-- by the place it's published to, so one place file carries both configs and
-- can be published to either lobby without the other's maps going live:
--
--   ServerStorage.ProdTeleports.Active    prod lobby
--   ServerStorage.Teleports.Active        test lobby (the old hub's folder name)
--
-- Active holds one ModuleScript per map, named with its title. Each returns a
-- table in the same shape as an entry in Shared/Maps.lua (Key, Accent, Blurb,
-- Stats, Tags, Platforms, Images, Backdrop, PlaceIds, Vip), plus:
--
--   Order         display order, then title
--   Access        tiers that can see and join it: "Tester", "Staff",
--                 "Developer", "Public". Missing means everyone
--   Password      missing or "" means none. Never leaves the server
--   SingleServer  true sends everyone to one shared reserved server, so a
--                 test can be watched. Test places want this on
--
-- Images and PlaceIds can be plain numbers. Archive, next to Active, is
-- ignored: somewhere to park old maps.
--
--   ServerStorage.RoleToAccessRank    ModuleScript returning
--                                     { GroupId = 9630142, Roles = { [group role] = tier } }
--
-- Read once when the server starts; edits apply to servers started after publishing.

local serverStorage = game:GetService("ServerStorage")

local library = {}

----

local DEFAULT_GROUP = 9630142 -- the testing group the old hub used
local DEFAULT_ACCENT = "#CABC83"

-- variant -> its config root in ServerStorage
library.Roots = {
	test = "Teleports",
	prod = "ProdTeleports",
}

----

local function asset(id)
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end

	return type(id) == "string" and id ~= "" and id or nil
end

local function placeId(id)
	return type(id) == "number" and id > 0 and id or nil
end

local function tierName(tier)
	return type(tier) == "string" and tier or nil
end

-- the valid, unique entries of a list
local function clean(values, convert)
	local list = {}

	for _, value in type(values) == "table" and values or {} do
		local converted = convert(value)

		if converted ~= nil and not table.find(list, converted) then
			table.insert(list, converted)
		end
	end

	return list
end

local function stats(list)
	local rows = {}

	for _, row in type(list) == "table" and list or {} do
		if type(row) == "table" and row[1] ~= nil and row[2] ~= nil then
			table.insert(rows, { tostring(row[1]):upper(), tostring(row[2]) })
		end
	end

	return rows
end

-- { text, colour? } pairs or plain strings; colour is a hex string or Color3
local function tags(list)
	local rows = {}

	for _, tag in type(list) == "table" and list or {} do
		local label, color = tag, nil

		if type(tag) == "table" then
			label, color = tag[1], tag[2]
		end

		if typeof(color) == "Color3" then
			color = "#" .. color:ToHex():upper()
		end

		if type(label) == "string" and label ~= "" then
			table.insert(rows, { label:upper(), type(color) == "string" and color or nil })
		end
	end

	return rows
end

-- keys are Platform.lua chips (PC, Xbox, PS4, PS5, Mobile); "PlayStation"
-- is shorthand for both PS4 and PS5, and a generation set on its own wins
local function platforms(support)
	local levels = {}

	for key, level in type(support) == "table" and support or {} do
		if level ~= "warn" and level ~= "blocked" then
			continue
		end

		if key == "PlayStation" then
			levels.PS4 = levels.PS4 or support.PS4 or level
			levels.PS5 = levels.PS5 or support.PS5 or level
		else
			levels[key] = level
		end
	end

	return levels
end

local function vip(kinds)
	if type(kinds) ~= "table" then
		return nil
	end

	local places = {}

	for kind, ids in kinds do
		places[kind] = clean(ids, placeId)
	end

	return places
end

----

-- a map as the rest of the lobby uses it, from a config module's table or a
-- Shared/Maps.lua entry; nil (with a warning) if it can't be used
function library.Normalize(raw, title)
	local name = raw.Name or title
	local placeIds = clean(raw.PlaceIds, placeId)

	if placeId(raw.PlaceId) and not table.find(placeIds, raw.PlaceId) then
		table.insert(placeIds, 1, raw.PlaceId)
	end

	if type(name) ~= "string" or #placeIds == 0 then
		warn("Lobby map config '" .. tostring(name) .. "' skipped: it needs a name and PlaceIds")

		return nil
	end

	local accent = raw.Accent

	if typeof(accent) == "Color3" then
		accent = "#" .. accent:ToHex():upper()
	end

	local password = raw.Password

	return {
		Key = type(raw.Key) == "string" and raw.Key or (name:gsub("[^%w]", "")),
		Name = name,
		Order = type(raw.Order) == "number" and raw.Order or nil,
		Accent = type(accent) == "string" and accent or DEFAULT_ACCENT,
		Blurb = type(raw.Blurb) == "string" and raw.Blurb or "",
		Stats = stats(raw.Stats),
		Tags = tags(raw.Tags),
		Platforms = platforms(raw.Platforms),
		Images = clean(raw.Images, asset),
		Backdrop = asset(raw.Backdrop),
		PlaceIds = placeIds,
		Vip = vip(raw.Vip),
		Access = type(raw.Access) == "table" and clean(raw.Access, tierName) or nil,
		SingleServer = raw.SingleServer == true,
		Secret = type(password) == "string" and password ~= "" and password or nil,
	}
end

-- a config module's table, or nil (with a warning) if it errors or isn't one
local function load(module)
	local worked, result = pcall(require, module)

	if not worked then
		warn("Lobby config '" .. module:GetFullName() .. "' errored: " .. tostring(result))

		return nil
	end

	if type(result) ~= "table" then
		warn("Lobby config '" .. module:GetFullName() .. "' skipped: it must return a table")

		return nil
	end

	return result
end

local function loadTiers()
	local module = serverStorage:FindFirstChild("RoleToAccessRank")
	local config = module and module:IsA("ModuleScript") and load(module) or {}
	local roles = {}

	for role, tier in type(config.Roles) == "table" and config.Roles or {} do
		if type(role) == "string" and type(tier) == "string" then
			roles[role] = tier
		end
	end

	return {
		Group = type(config.GroupId) == "number" and config.GroupId or DEFAULT_GROUP,
		Roles = roles,
	}
end

----

-- the variant's config from the place, or nil if it has none
function library:Load(variant)
	local root = serverStorage:FindFirstChild(library.Roots[variant])
	local active = root and root:FindFirstChild("Active")

	if not active then
		return nil
	end

	local maps = {}
	local keys = {}

	for _, module in active:GetChildren() do
		local raw = module:IsA("ModuleScript") and load(module)
		local map = raw and library.Normalize(raw, module.Name)

		if map and keys[map.Key] then
			warn("Lobby map config '" .. module.Name .. "' skipped: key '" .. map.Key .. "' is already used")
		elseif map then
			keys[map.Key] = true
			table.insert(maps, map)
		end
	end

	table.sort(maps, function(a, b)
		local aOrder = a.Order or math.huge
		local bOrder = b.Order or math.huge

		if aOrder ~= bOrder then
			return aOrder < bOrder
		end

		return a.Name < b.Name
	end)

	return {
		Maps = maps,
		Tiers = loadTiers(),
	}
end

return library
