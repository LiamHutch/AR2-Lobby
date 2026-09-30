-- Constants shared with the game servers that report into the lobby.
-- KEEP IN SYNC with the BROWSER_* fields in the game's
-- ApocalypseRising2/src/Server/Configs/HubProtocol.lua.
--
-- Directory entry written by each public game server (key = JobId):
--   {
--     v = VERSION,
--     placeId = number,
--     jobId = string,
--     players = number,
--     maxPlayers = number,
--     startedAt = number,     -- unix time the server booted
--     placeVersion = number,  -- game.PlaceVersion, spots outdated servers
--     region = string?,       -- coarse location, e.g. "US East"; optional,
--                             -- older beacons don't send it
--   }
--
-- Teleport data the lobby sends to the game:
--   { source = SOURCE, v = VERSION, map = <Maps key> }

return {
	VERSION = 1,
	SOURCE = "AR2Lobby",

	-- MemoryStore hashmap the game writes and the lobby reads
	DIRECTORY_MAP = "BrowserDirectory1",

	-- the test lobby replaces the AR2 Development Hub in its place and keeps
	-- the hub's names, so test servers' Hub Beacon and join lock work unchanged
	-- (game repo: src/Server/Configs/HubProtocol.lua)
	TEST_LOBBY_PLACE_ID = 9350655892,
	HUB_VERSION = 1,
	HUB_SOURCE = "AR2Hub",
	HUB_DIRECTORY_MAP = "HubServerDirectory1",
	HUB_GRANTS_MAP = "HubTeleportGrants1",
	HUB_GRANT_TTL = 300,

	-- the old hub's cache of each single-server place's reserved server;
	-- reusing it keeps testers going to the same locked servers
	RESERVED_STORE = "ReservedServerInfo",
	RESERVED_INDEX = 3,

	-- wrong passwords allowed per player per minute
	PASSWORD_ATTEMPTS = 5,

	-- lobby read budget; each lobby server reads once per interval and fans
	-- the result out to its players, clients never touch MemoryStore
	POLL_INTERVAL = 15,

	-- the refresh button reads early only if the snapshot is this old, and
	-- that read is shared by the whole lobby server, not one per player
	REFRESH_MIN_AGE = 5,
	REFRESH_COOLDOWN = 3,
	PAGE_SIZE = 200,
	MAX_PAGES = 5,
	MAX_SERVERS_PER_MAP = 50,
}
