-- The private server modes: Tourney and Free Roam. They show as tiles beside
-- the maps, and every player hosts their own lobby or server for each, with
-- no paid private server needed (Sessions.lua). This file is the one
-- description of a mode the server (defaults, validation, list rows) and the
-- client (labels, dropdowns, tiles) both read.
--
-- A mode entry:
--   Key        stable id used in code and attributes
--   Kind       the directory kind (Protocol.lua KINDS) its game servers list as
--   Name       tile title; the mode view's heading
--   Blurb      copy under the title
--   Tags       { text, colour? } pairs on the tile, like a map's
--   Platforms  support per platform key, like a map's (Platform.lua)
--   Icon       vector art for the tile
--   Images     the mode view's preview slideshow, 1024x576 unless ImageAspect
--              says otherwise (width / height), with ImageFocus the share of
--              each image to keep in frame (Slideshow.lua)
--   PlaceIds   every place that runs this mode, in the order to prefer them:
--              the lobby uses the first one in its own universe. The test
--              universe has both a Test - Prod and a Development copy, and the
--              test lobby should send players to the Test - Prod one
--   Heading    the session list's heading; Empty its empty text; Primary the
--              main button's label
--   Settings   ordered list of { Key, Label, Default, Options = { { value, label } } }
--              that the host configures. Values are typed (booleans, numbers,
--              short strings), never display text: labels are only here
--
-- Tourney also has TeamSizes, MaxSpectators, Maps and the team Colors.
--
-- A host's config, as stored and sent to clients (Protocol.PRIVATE_STORE,
-- key "<kind>:<userId>"):
--   { v, visibility, settings = { [Key] = value }, whitelist, ...mode fields }
--   whitelist = { [userId string] = true }: players who see and join the
--             session whatever its visibility (Server/Whitelist.lua); on free
--             roam they also get past the lock, without a co-host's powers
--   tourney:  teams = { { name, color }, { name, color } }, maps = { mapName }
--   freeroam: hosts = { [userId string] = true } (co-hosts: they get past the
--             lock and can lock, kick and ban in game), bans = { [userId string] = true }

local library = {}

----

-- visibility decides who sees a session in the list. Private is unlisted:
-- only the host, anyone already on its rosters, and the host's whitelist
library.Visibilities = { "private", "friends", "public" }

library.VisibilityLabels = {
	private = "PRIVATE",
	friends = "FRIENDS",
	public = "PUBLIC",
}

library.DefaultVisibility = "friends"

-- public is paid: the SubscriptionService ids a host needs an active
-- subscription to, checked by Server/Subscriptions; the test lobby (the
-- AR2 Development Hub's place) uses the dev one. nil leaves public free
library.PublicSubscriptionIds = {
	prod = "EXP-4749682403386196533",
	test = "EXP-466912041412723193",
}

function library:PublicSubscriptionId()
	local protocol = require(script.Parent.Protocol)

	return self.PublicSubscriptionIds[game.PlaceId == protocol.TEST_LOBBY_PLACE_ID and "test" or "prod"]
end

-- team colours a host picks from; a team stores the index
library.TeamColors = {
	Color3.fromRGB(127, 57, 57),
	Color3.fromRGB(49, 54, 106),
	Color3.fromRGB(47, 107, 63),
	Color3.fromRGB(122, 90, 28),
	Color3.fromRGB(90, 47, 107),
	Color3.fromRGB(47, 100, 104),
	Color3.fromRGB(138, 74, 32),
	Color3.fromRGB(63, 63, 63),
	Color3.fromRGB(107, 47, 74),
	Color3.fromRGB(74, 107, 47),
	Color3.fromRGB(31, 74, 122),
	Color3.fromRGB(122, 122, 47),
}

local function onOff(default)
	return { { false, "Off" }, { true, "On" } }, default
end

local function range(values, suffix)
	local options = {}

	for _, value in values do
		table.insert(options, { value, string.format("%d %s", value, value == 1 and suffix:gsub("s$", "") or suffix) })
	end

	return options
end

local TIMES = {
	{ "night", "Night" },
	{ "morning", "Morning" },
	{ "afternoon", "Afternoon" },
	{ "evening", "Evening" },
	{ "dusk", "Dusk" },
}

----

library.Modes = {
	{
		Key = "Tourney",
		Kind = "tourney",
		Name = "Tourney",
		Blurb = "Tourney mode is a round-based deathmatch where two teams of up to ten players face off with an arsenal of weapons across a variety of AR2 map locations and custom arenas.",
		Tags = {
			{ "Private", "#CABC83" },
			{ "PVP", "#D65C4A" },
		},
		Platforms = {
			Mobile = "blocked",
		},
		Icon = "rbxassetid://77592314681741",
		-- the tourney art is 1024x1024: fit its width, the frame crops top and bottom
		ImageAspect = 1,
		ImageFocus = { 1, 1 },
		Images = {
			"rbxassetid://105285500939800", -- Ward
			"rbxassetid://117356394719262", -- Swamp
			"rbxassetid://108374078195018", -- Crates
			"rbxassetid://89550864691432", -- Alley
		},
		PlaceIds = {
			10077968348, -- Prod - VIP Tourney
			12123100380, -- Test - Prod VIP Tourney
			10075831055, -- Dev - VIP Tourney
		},
		Heading = "Lobbies",
		Empty = "No Lobbies",
		Primary = "HOST A MATCH",

		-- the two teams; spectators are a third roster with its own cap
		TeamSizes = { 1, 2, 3, 4, 5, 6, 8, 10 },
		MaxSpectators = 30,

		Settings = {
			{ Key = "teamSize", Label = "Team size", Default = 5, Options = (function()
				local options = {}

				for _, size in { 1, 2, 3, 4, 5, 6, 8, 10 } do
					table.insert(options, { size, string.format("%d per team", size) })
				end

				return options
			end)() },
			{ Key = "scoreMode", Label = "Score mode", Default = "bestOf", Options = { { "bestOf", "Best of" }, { "firstTo", "First to" } } },
			{ Key = "rounds", Label = "Number of rounds", Default = 5, Options = range({ 1, 2, 3, 5, 10, 15, 20 }, "rounds") },
			{ Key = "countdown", Label = "Start countdown", Default = 10, Options = range({ 5, 10, 15, 20, 30, 60 }, "seconds") },
			{ Key = "roundLength", Label = "Round length", Default = 10, Options = range({ 2, 5, 10, 15, 20, 30 }, "minutes") },
			{ Key = "timeOfDay", Label = "Time of day", Default = "afternoon", Options = TIMES },
			{ Key = "dayLength", Label = "Day length", Default = 1, Options = { { 0, "0x" }, { 0.5, "0.5x" }, { 1, "1x" }, { 2, "2x" }, { 3, "3x" } } },
			{ Key = "firstPerson", Label = "First person lock", Default = false, Options = (onOff()) },
			{ Key = "mapOrder", Label = "Map rotation", Default = "inOrder", Options = { { "inOrder", "In order" }, { "shufflePicks", "Shuffle picks" }, { "shuffleAll", "Shuffle all" } } },
			{ Key = "spectating", Label = "Spectating mode", Default = "team", Options = { { "team", "Team" }, { "free", "Free" }, { "off", "Off" } } },
			{ Key = "sides", Label = "Team sides", Default = "regular", Options = { { "regular", "Regular" }, { "flipped", "Flipped" }, { "alternating", "Alternating" } } },
		},

		-- Name is the model in ReplicatedStorage.TourneyMaps on the tourney place
		Maps = {
			{ Name = "Ward", DisplayName = "Ward", SmallImage = "rbxassetid://97226975172014", BigImage = "rbxassetid://105285500939800" },
			{ Name = "Swamp", DisplayName = "Swamp", SmallImage = "rbxassetid://97791266216808", BigImage = "rbxassetid://117356394719262" },
			{ Name = "Crates", DisplayName = "Crates", SmallImage = "rbxassetid://111995108174306", BigImage = "rbxassetid://108374078195018" },
			{ Name = "Alley", DisplayName = "Alley", SmallImage = "rbxassetid://73471527900829", BigImage = "rbxassetid://89550864691432" },
			{ Name = "Ashland", DisplayName = "Ashland", SmallImage = "rbxassetid://10076993831", BigImage = "rbxassetid://10076994076" },
			{ Name = "Forest", DisplayName = "Lakeside Forest", SmallImage = "rbxassetid://10076993278", BigImage = "rbxassetid://10077045018" },
			{ Name = "Hayfields", DisplayName = "Grain Hayfields", SmallImage = "rbxassetid://10076992651", BigImage = "rbxassetid://10076993085" },
			{ Name = "Huntington", DisplayName = "Huntington", SmallImage = "rbxassetid://10076992526", BigImage = "rbxassetid://10076992315" },
			{ Name = "Lockport", DisplayName = "Lockport", SmallImage = "rbxassetid://10076991543", BigImage = "rbxassetid://10076991949" },
			{ Name = "Military Air", DisplayName = "Naval Airbase", SmallImage = "rbxassetid://10076990697", BigImage = "rbxassetid://10076991419" },
			{ Name = "Oil Rig", DisplayName = "Mackinaw Oil Rig", SmallImage = "rbxassetid://10076990090", BigImage = "rbxassetid://10076990569" },
			{ Name = "Power Plant", DisplayName = "Power Plant", SmallImage = "rbxassetid://10076989333", BigImage = "rbxassetid://10076989899" },
			{ Name = "Volcano Dealer", DisplayName = "Santa's Workshop", SmallImage = "rbxassetid://10076988779", BigImage = "rbxassetid://10076989155" },
			{ Name = "Oil Rig Squared", DisplayName = "Dueling Oil Rigs", SmallImage = "rbxassetid://10076988189", BigImage = "rbxassetid://10076988644" },
			{ Name = "Undertakers Forest", DisplayName = "Undertakers Forest", SmallImage = "rbxassetid://10076987354", BigImage = "rbxassetid://10076987962" },
			{ Name = "University", DisplayName = "University", SmallImage = "rbxassetid://10076986779", BigImage = "rbxassetid://10076987173" },
			{ Name = "Large Farmfield", DisplayName = "Hay Bales", SmallImage = "rbxassetid://10085443241", BigImage = "rbxassetid://10085442683" },
			{ Name = "Border", DisplayName = "Border", SmallImage = "rbxassetid://10368937367", BigImage = "rbxassetid://10368933951" },
			{ Name = "Regional AP", DisplayName = "Airport Terminal", SmallImage = "rbxassetid://10076994184", BigImage = "rbxassetid://10076994560" },
			{ Name = "Lower Prison Island", DisplayName = "Lower Prison Island", SmallImage = "rbxassetid://15696412386", BigImage = "rbxassetid://15696409451" },
		},
	},

	{
		Key = "Freeroam",
		Kind = "freeroam",
		Name = "Free Roam",
		Blurb = "Your own private Halsey Islands for solo play and friends, with no matchmaking. Free roam servers share one loot and progression save, kept separate from the main game.",
		Tags = {
			{ "Private", "#CABC83" },
			{ "Halsey Islands", "#8FC46A" },
		},
		Platforms = {
			PS4 = "blocked",
			Mobile = "blocked",
		},
		Icon = "rbxassetid://110525320209137",
		Images = {
			"rbxassetid://100458318643619", -- beta1 ashland
			"rbxassetid://119965385609259", -- beta3 fairview
			"rbxassetid://108090803277875", -- beta4 grain
			"rbxassetid://90113538973109", -- beta5 beaufort
			"rbxassetid://140317366312469", -- beta6 swamp
			"rbxassetid://119672357664079", -- beta7 magnolia
		},
		PlaceIds = {
			105446216022659, -- Prod - VIP Freeroam
			73731901834889, -- Test - Prod VIP Freeroam
			107047742607799, -- Dev - VIP Freeroam
		},
		Heading = "Servers",
		Empty = "No Servers",
		Primary = "CUSTOMIZE",
		MaxPlayers = 16,

		Settings = {
			{ Key = "locked", Label = "Server lock", Default = false, Options = (onOff()) },
			{ Key = "firstPerson", Label = "First person only", Default = false, Options = (onOff()) },
			{ Key = "statsDegrade", Label = "Survival stats", Default = true, Options = (onOff()) },
			{ Key = "freeCam", Label = "Free camera", Default = false, Options = (onOff()) },
			{ Key = "timeOfDay", Label = "Time of day", Default = "off", Options = {
				{ "off", "Off" },
				{ "morning", "Morning" },
				{ "afternoon", "Afternoon" },
				{ "evening", "Evening" },
				{ "dusk", "Dusk" },
				{ "night", "Night" },
			} },
			{ Key = "zombies", Label = "Infected spawns", Default = true, Options = (onOff()) },
			{ Key = "vehicles", Label = "Vehicle spawns", Default = true, Options = (onOff()) },
			{ Key = "randoms", Label = "Random events", Default = true, Options = (onOff()) },
			{ Key = "loot", Label = "Loot cycling", Default = true, Options = (onOff()) },
		},

		-- what a row says about a server whose settings differ from the defaults
		SettingTags = {
			{ "firstPerson", true, "FIRST PERSON" },
			{ "freeCam", true, "FREECAM" },
			{ "statsDegrade", false, "STATS FROZEN" },
			{ "zombies", false, "NO ZOMBIES" },
			{ "loot", false, "NO LOOT" },
			{ "vehicles", false, "NO VEHICLES" },
			{ "randoms", false, "NO RANDOMS" },
		},
	},
}

library.ByKey = {}
library.ByKind = {}

for _, mode in library.Modes do
	library.ByKey[mode.Key] = mode
	library.ByKind[mode.Kind] = mode

	mode.SettingsByKey = {}

	for _, setting in mode.Settings do
		mode.SettingsByKey[setting.Key] = setting
	end

	if mode.Maps then
		mode.MapsByName = {}

		for _, map in mode.Maps do
			mode.MapsByName[map.Name] = map
		end
	end
end

----

-- the option a setting holds, or nil if the value isn't one of its options
function library:Option(setting, value)
	for _, option in setting.Options do
		if option[1] == value then
			return option
		end
	end

	return nil
end

function library:Label(setting, value)
	local option = self:Option(setting, value)

	return option and option[2] or tostring(value)
end

function library:Defaults(mode)
	local settings = {}

	for _, setting in mode.Settings do
		settings[setting.Key] = setting.Default
	end

	return settings
end

-- a settings table with every unknown or invalid value replaced by its default
function library:Sanitize(mode, raw)
	local settings = self:Defaults(mode)

	if type(raw) == "table" then
		for _, setting in mode.Settings do
			if self:Option(setting, raw[setting.Key]) then
				settings[setting.Key] = raw[setting.Key]
			end
		end
	end

	return settings
end

function library:IsVisibility(value)
	return table.find(self.Visibilities, value) ~= nil
end

-- "FIRST PERSON", "NO ZOMBIES", "DUSK": the ways a free roam server differs
-- from a stock one, for its row and footer
function library:SettingTags(mode, settings)
	local tags = {}

	for _, rule in mode.SettingTags or {} do
		if settings[rule[1]] == rule[2] then
			table.insert(tags, rule[3])
		end
	end

	local time = mode.SettingsByKey.timeOfDay

	if time and settings.timeOfDay ~= "off" and settings.timeOfDay ~= nil then
		table.insert(tags, self:Label(time, settings.timeOfDay):upper())
	end

	return tags
end

-- "Best of 5 on: Ward, Swamp" and "5v5, rounds are 10 minutes, Map rotation
-- is In order, Team spectating" for a tourney config
function library:MatchTitle(config)
	local mode = self.ByKey.Tourney
	local settings = config.settings
	local maps = {}

	if settings.mapOrder == "shuffleAll" then
		maps = { "Random maps" }
	else
		for _, name in config.maps or {} do
			local map = mode.MapsByName[name]

			if map then
				table.insert(maps, map.DisplayName)
			end
		end
	end

	if #maps == 0 then
		return "Waiting for host", "Pick a map to get started"
	end

	local big = string.format("%s %d on: %s", self:Label(mode.SettingsByKey.scoreMode, settings.scoreMode), settings.rounds, table.concat(maps, ", "))
	local spectating = settings.spectating == "off" and "No spectating" or (self:Label(mode.SettingsByKey.spectating, settings.spectating) .. " spectating")
	local small = string.format(
		"%dv%d, rounds are %d minutes, Map rotation is %s, %s",
		settings.teamSize,
		settings.teamSize,
		settings.roundLength,
		self:Label(mode.SettingsByKey.mapOrder, settings.mapOrder),
		spectating
	)

	return big, small
end

return library
