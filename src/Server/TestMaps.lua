-- Maps for the test lobby, the place that replaced the AR2 Development Hub.
-- Server-only, so testers never see maps (or rules) they can't join.
-- Copied from the old hub's ServerStorage.Teleports.Active; its Archive
-- entries are left out.
--
-- Same fields as Shared/Maps.lua, plus:
--   Access        tiers that can see and join it (see Tiers)
--   SingleServer  everyone goes to one shared reserved server so a test stays
--                 in one place you can watch. Off means normal matchmaking,
--                 which the game's test server lock only allows on reserved
--                 servers, so leave it on for test places
--   Password      true to require the password stored in this place at
--                 ServerStorage.LobbyPasswords.<Key> (a StringValue). Kept
--                 out of git on purpose; a missing value blocks joining

local ACCENT = "#CABC83"

local EVERYONE = { "Tester", "Staff", "Developer" }
local STAFF = { "Staff", "Developer" }

return {
	-- group role name -> access tier, from the old hub's RoleToAccessRank.
	-- Anyone else, or anyone not in the group, is "Public"
	Tiers = {
		Group = 9630142,
		Roles = {
			Tester = "Tester",
			Staff = "Staff",
			Manager = "Staff",
			Developer = "Developer",
			Placeholder = "Developer",
			Guest = "Public",
			Limbo = "Public",
		},
	},

	Maps = {
		{
			Key = "Events",
			Name = "Events",
			Blurb = "MONDAY MONDAY MONDAY",
			PlaceIds = { 14818535321 },
			Access = EVERYONE,
		},
		{
			Key = "Balance",
			Name = "Balance",
			Blurb = "PP testing",
			PlaceIds = { 9350725512 },
			Access = EVERYONE,
		},
		{
			Key = "ProdMain",
			Name = "Prod. Main",
			Blurb = "Current production build of the main game",
			PlaceIds = { 12123099753 },
			Access = { "Developer" },
			Password = true,
		},
		{
			Key = "PublicTesting",
			Name = "Public Testing",
			Blurb = "",
			PlaceIds = { 9350727487 },
			Access = EVERYONE,
		},
		{
			Key = "VIPTesting",
			Name = "VIP Testing",
			Blurb = "Mock VIP server, first to join = host",
			PlaceIds = { 10075727235 },
			Access = EVERYONE,
		},
		{
			Key = "BasedFeature",
			Name = "Based Feature",
			Blurb = "building the realm",
			PlaceIds = { 9350726579 },
			Access = STAFF,
		},
		{
			Key = "World",
			Name = "World",
			Blurb = "Wussup da world",
			PlaceIds = { 9350694607 },
			Access = STAFF,
		},
		{
			Key = "Feature2",
			Name = "Feature 2",
			Blurb = "they hid 900 koroks in breath of the wild",
			PlaceIds = { 9734052822 },
			Access = EVERYONE,
		},
		{
			Key = "MobileTest",
			Name = "Mobile Test",
			Blurb = "Do you have any games on your phone?",
			PlaceIds = { 85957012910302 },
			Access = EVERYONE,
		},
	},

	-- filled in for every map that doesn't set its own
	Defaults = {
		Accent = ACCENT,
		SingleServer = true,
		Stats = {},
		Platforms = {},
		Images = {},
	},
}
