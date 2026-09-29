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
--   }
--
-- Teleport data the lobby sends to the game:
--   { source = SOURCE, v = VERSION, map = <Maps key> }

return {
	VERSION = 1,
	SOURCE = "AR2Lobby",

	-- MemoryStore hashmap the game writes and the lobby reads
	DIRECTORY_MAP = "BrowserDirectory1",

	-- lobby read budget; each hub server reads once per interval and fans
	-- the result out to its players, clients never touch MemoryStore
	POLL_INTERVAL = 15,
	PAGE_SIZE = 200,
	MAX_PAGES = 5,
	MAX_SERVERS_PER_MAP = 50,
}
