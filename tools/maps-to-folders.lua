-- Turns the code map config (ReplicatedStorage.Shared.Maps, from
-- src/Shared/Maps.lua) into the place config folders PlaceConfig.lua reads,
-- so maps can be edited in Studio from then on. Paste into the command bar of
-- a lobby place that Rojo has synced.
--
-- Adds to ServerStorage.Teleports.Active and never overwrites: a map whose
-- folder already exists is skipped. Public maps get MultiServer = true (no
-- single-server lock) and no Access list (everyone).

local serverStorage = game:GetService("ServerStorage")
local replicatedStorage = game:GetService("ReplicatedStorage")

local maps = require(replicatedStorage.Shared.Maps)

----

local function child(parent, className, name, value)
	local object = Instance.new(className)
	object.Name = name

	if value ~= nil then
		object.Value = value
	end

	object.Parent = parent

	return object
end

local function folder(parent, name)
	return parent:FindFirstChild(name) or child(parent, "Folder", name)
end

local function color(hex)
	return Color3.fromHex(hex)
end

----

local active = folder(folder(serverStorage, "Teleports"), "Active")
folder(serverStorage.Teleports, "Archive")

local made = {}

for index, map in maps do
	if active:FindFirstChild(map.Name) then
		print("Skipped " .. map.Name .. ": it already has a folder")

		continue
	end

	local config = Instance.new("Folder")
	config.Name = map.Name

	child(config, "StringValue", "Key", map.Key)
	child(config, "IntValue", "Order", index)
	child(config, "StringValue", "Description", map.Blurb or "")
	child(config, "BoolValue", "MultiServer", true)

	if map.Accent then
		child(config, "Color3Value", "Accent", color(map.Accent))
	end

	if map.PlaceIds[1] then
		child(config, "NumberValue", "PlaceId", map.PlaceIds[1])
	end

	if #map.PlaceIds > 1 then
		local extra = child(config, "Folder", "PlaceIds")

		for place = 2, #map.PlaceIds do
			child(extra, "NumberValue", tostring(place - 1), map.PlaceIds[place])
		end
	end

	if map.Images and #map.Images > 0 then
		local images = child(config, "Folder", "Images")

		for image, id in map.Images do
			child(images, "StringValue", tostring(image), id)
		end
	end

	if map.CardImages and #map.CardImages > 0 then
		local images = child(config, "Folder", "CardImages")

		for image, id in map.CardImages do
			child(images, "StringValue", tostring(image), id)
		end
	end

	if map.Backdrop then
		child(config, "StringValue", "Backdrop", map.Backdrop)
	end

	if map.Stats and #map.Stats > 0 then
		local stats = child(config, "Folder", "Stats")

		for order, stat in map.Stats do
			child(stats, "StringValue", stat[1], stat[2]):SetAttribute("Order", order)
		end
	end

	if map.Platforms and next(map.Platforms) then
		local platforms = child(config, "Folder", "Platforms")

		for platform, support in map.Platforms do
			child(platforms, "StringValue", platform, support)
		end
	end

	if map.Vip then
		local vip = child(config, "Folder", "Vip")

		for kind, placeIds in map.Vip do
			local places = child(vip, "Folder", kind)

			for place, placeId in placeIds do
				child(places, "NumberValue", tostring(place), placeId)
			end
		end
	end

	config.Parent = active
	table.insert(made, map.Name)
end

print("Map configs made: " .. (#made > 0 and table.concat(made, ", ") or "none"))
