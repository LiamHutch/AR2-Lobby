-- Map configs kept in the place instead of git, so anyone can edit them in
-- Studio and publish. Same layout as the old AR2 Development Hub, so its
-- folders can be copied straight in:
--
--   ServerStorage.Teleports.Active.<Title>    one Folder per map; its Name is the title
--     PlaceId        NumberValue    required
--     PlaceIds       Folder of NumberValues: more places running this map (prod + test)
--     Description    StringValue    flavour text
--     Password       StringValue    empty or missing means none; never leaves the server
--     MultiServer    BoolValue      off or missing = single-server lock (everyone to one
--                                   reserved server). Public prod maps want this on
--     Access         Folder of BoolValues: Tester, Staff, Developer, Public. Missing = everyone
--   lobby extras, all optional:
--     Key            StringValue    stable id sent in teleport data; default is the title
--                                   without spaces or punctuation
--     Order          IntValue       display order, then title
--     Accent         Color3Value    colour of the title's first word
--     Images         Folder of StringValues (rbxassetid://…), in name order: landscape
--                    art for the map view's preview
--     CardImages     same, portrait art for the picker card; falls back to Images
--                    (both want Image ids, not Decal ids: paste a decal id into an
--                    ImageLabel's Image in Studio and it turns into the image id)
--     Backdrop       StringValue    tiny copy of the art for the blurred background
--     Stats          Folder of StringValues, Name = label, Value = value; an Order
--                    attribute sorts them, then name
--     Platforms      Folder of StringValues, Name = PC / Xbox / PlayStation / Mobile,
--                    Value = "warn" or "blocked"
--     Vip            Folder of Folders, Name = kind (e.g. freeroam), holding NumberValue place ids
--
--   ServerStorage.Teleports.Archive           ignored; somewhere to park old configs
--   ServerStorage.RoleToAccessRank            StringValues, Name = group role, Value = tier.
--                                             A GroupId attribute picks the group
--
-- Read once when the server starts; edits apply to servers started after publishing.

local serverStorage = game:GetService("ServerStorage")

local library = {}

----

local DEFAULT_GROUP = 9630142 -- the testing group the old hub used
local DEFAULT_ACCENT = Color3.fromRGB(202, 188, 131)

----

local function value(folder, name, className)
	local object = folder:FindFirstChild(name)

	if object and object:IsA(className) then
		return object.Value
	end

	return nil
end

local function hex(color)
	return string.format("#%02X%02X%02X", color.R * 255 + 0.5, color.G * 255 + 0.5, color.B * 255 + 0.5)
end

local function byName(a, b)
	return a.Name < b.Name
end

local function numbers(folder)
	local list = {}

	if folder then
		local children = folder:GetChildren()
		table.sort(children, byName)

		for _, child in children do
			if child:IsA("NumberValue") or child:IsA("IntValue") then
				table.insert(list, child.Value)
			end
		end
	end

	return list
end

local function images(folder)
	local list = {}

	if folder then
		local children = folder:GetChildren()
		table.sort(children, byName)

		for _, child in children do
			if child:IsA("StringValue") and child.Value ~= "" then
				table.insert(list, child.Value)
			end
		end
	end

	return list
end

local function stats(folder)
	local list = {}

	if folder then
		local children = folder:GetChildren()

		table.sort(children, function(a, b)
			local aOrder = a:GetAttribute("Order") or math.huge
			local bOrder = b:GetAttribute("Order") or math.huge

			if aOrder ~= bOrder then
				return aOrder < bOrder
			end

			return a.Name < b.Name
		end)

		for _, child in children do
			if child:IsA("StringValue") then
				table.insert(list, { child.Name:upper(), child.Value })
			end
		end
	end

	return list
end

local function platforms(folder)
	local support = {}

	for _, child in folder and folder:GetChildren() or {} do
		if child:IsA("StringValue") and (child.Value == "warn" or child.Value == "blocked") then
			support[child.Name] = child.Value
		end
	end

	return support
end

local function access(folder)
	if not folder then
		return nil
	end

	local tiers = {}

	for _, child in folder:GetChildren() do
		if child:IsA("BoolValue") and child.Value then
			table.insert(tiers, child.Name)
		end
	end

	return tiers
end

local function vip(folder)
	if not folder then
		return nil
	end

	local kinds = {}

	for _, kind in folder:GetChildren() do
		kinds[kind.Name] = numbers(kind)
	end

	return kinds
end

local function readMap(folder)
	local placeId = value(folder, "PlaceId", "NumberValue") or value(folder, "PlaceId", "IntValue")

	if type(placeId) ~= "number" or placeId <= 0 then
		warn("Lobby map config '" .. folder.Name .. "' skipped: it needs a PlaceId")

		return nil
	end

	local placeIds = { placeId }

	for _, extra in numbers(folder:FindFirstChild("PlaceIds")) do
		if not table.find(placeIds, extra) then
			table.insert(placeIds, extra)
		end
	end

	local accent = value(folder, "Accent", "Color3Value")
	local password = value(folder, "Password", "StringValue")

	return {
		Key = value(folder, "Key", "StringValue") or folder.Name:gsub("[^%w]", ""),
		Name = folder.Name,
		Order = value(folder, "Order", "IntValue") or value(folder, "Order", "NumberValue"),
		Accent = hex(accent or DEFAULT_ACCENT),
		Blurb = value(folder, "Description", "StringValue") or "",
		Stats = stats(folder:FindFirstChild("Stats")),
		Platforms = platforms(folder:FindFirstChild("Platforms")),
		Images = images(folder:FindFirstChild("Images")),
		CardImages = images(folder:FindFirstChild("CardImages")),
		Backdrop = value(folder, "Backdrop", "StringValue"),
		PlaceIds = placeIds,
		Vip = vip(folder:FindFirstChild("Vip")),
		Access = access(folder:FindFirstChild("Access")),
		SingleServer = value(folder, "MultiServer", "BoolValue") ~= true,
		Secret = password ~= "" and password or nil,
	}
end

----

-- the place's config, or nil if it has none
function library:Load()
	local teleports = serverStorage:FindFirstChild("Teleports")
	local active = teleports and teleports:FindFirstChild("Active")

	if not active then
		return nil
	end

	local maps = {}
	local keys = {}

	for _, folder in active:GetChildren() do
		local map = readMap(folder)

		if map and keys[map.Key] then
			warn("Lobby map config '" .. folder.Name .. "' skipped: key '" .. map.Key .. "' is already used")
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

	local roles = {}
	local roleFolder = serverStorage:FindFirstChild("RoleToAccessRank")

	for _, role in roleFolder and roleFolder:GetChildren() or {} do
		if role:IsA("StringValue") then
			roles[role.Name] = role.Value
		end
	end

	return {
		Maps = maps,
		Tiers = {
			Group = roleFolder and roleFolder:GetAttribute("GroupId") or DEFAULT_GROUP,
			Roles = roles,
		},
	}
end

return library
