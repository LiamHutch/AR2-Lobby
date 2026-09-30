-- Constants shared with the game servers that report into the lobby.
-- KEEP IN SYNC with the BROWSER_* fields in the game's
-- ApocalypseRising2/src/Server/Configs/HubProtocol.lua.
--
-- The server directory lives in a DataStore, not MemoryStore (MemoryStore
-- budget is kept for other things). One key per server would need a read per
-- server to list them, so servers share SHARDS keys instead:
--
--   key "<SHARD_PREFIX><n>", n = 0 .. SHARDS - 1
--   value { v = DIRECTORY_VERSION, servers = { [jobId] = entry } }
--
-- Each game server picks its shard from its JobId (shardFor below; both sides
-- must agree), and with UpdateAsync:
--   - writes its entry with updatedAt = os.time() every heartbeat (~60s) and
--     on population changes (debounced ~30s)
--   - drops any entry in the shard whose updatedAt is older than
--     DIRECTORY_STALE: a server that stopped refreshing is dead
--   - removes its own entry in BindToClose
-- The lobby reads every shard each poll and ignores entries older than
-- DIRECTORY_STALE, so a crashed server drops off within a few minutes.
--
-- shardFor(jobId) = (sum of the JobId's bytes) % SHARDS
--
-- Directory entry (the value under servers[jobId]):
--   {
--     updatedAt = number,     -- unix time of this write; cold = dead
--     placeId = number,
--     jobId = string,
--     players = number,
--     maxPlayers = number,
--     startedAt = number,     -- unix time the server booted
--     placeVersion = number,  -- game.PlaceVersion, spots outdated servers
--     region = string?,       -- the game's "City - Region", e.g. "Ashburn - Virginia"
--     kind = string?,         -- see KINDS; missing means "public"
--     privateServerId = string?, -- test directory only: single-server maps
--                             -- list just their shared reserved server
--
--     -- VIP kinds only (never an access code or PrivateServerId):
--     hostId = number,        -- the host's UserId
--     locked = boolean?,      -- host has locked the server
--     settings = table?,      -- the mode's config, e.g. Freeroam's Config
--   }
--
-- Kinds (lobbies skip kinds they don't handle, so the game can start writing
-- a new one before any lobby shows it):
--   public    a normal public server; matchmake, or join by ServerInstanceId
--   freeroam  a host's VIP Freeroam server, one persistent reserved server
--             per host; joined through the lobby's ticket, never directly
--
-- Teleport data the lobby sends to the game:
--   { source = SOURCE, v = VERSION, map = <Maps key>, kind?, hostId? }
--
-- Ticket the lobby writes before sending someone to a VIP server
-- (TICKETS_MAP, key = tostring(UserId), single use, TICKET_TTL):
--   { v = VERSION, kind = string, hostId = number, placeId = number, issuedAt = number }
--   (still MemoryStore: one short-lived key per VIP join)

return {
	VERSION = 1,
	SOURCE = "AR2Lobby",

	-- the directory DataStores (see the top of this file). Prod has many more
	-- servers, so more shards: fewer servers writing each key, and one lobby
	-- poll is still only SHARDS reads
	DIRECTORY_STORE = "BrowserDirectory2",
	DIRECTORY_SHARDS = 20,
	DIRECTORY_VERSION = 1,
	DIRECTORY_SHARD_PREFIX = "shard-",
	-- seconds without a refresh before an entry counts as a dead server
	DIRECTORY_STALE = 180,

	-- VIP servers are built but hidden until the game writes their entries
	-- and checks tickets on arrival (CLAUDE.md, "VIP servers")
	VIP_LISTING = false,
	TICKETS_MAP = "BrowserTickets1",
	TICKET_TTL = 300,

	-- paid VIP servers on the lobby place forward everyone to the host's own
	-- reserved server on this map (VipForward.lua). The lobby records who the
	-- host is, since a reserved server has no PrivateServerOwnerId:
	--   VIP_HOSTS_STORE    DataStore, key = reserved PrivateServerId
	--                      -> { v, hostId, placeId, createdAt }
	--                      the game looks itself up here to learn its host
	--   VIP_SERVERS_STORE  DataStore, key = "<placeId>:<hostId>"
	--                      -> { v, hostId, placeId, accessCode, privateServerId, createdAt }
	--                      one reserved server per host, reused forever
	-- Arrivals carry TeleportData { source, v, kind = "vip", hostId }, which is
	-- informational only: never trust it for who the host is
	VIP_FORWARD_MAP = "Kin",
	-- the game (branch kinvip, globals.getVIPHost) only accepts v == 1: bump
	-- both sides together, and never with VERSION
	VIP_VERSION = 1,
	VIP_HOSTS_STORE = "LobbyVipHosts1",
	VIP_SERVERS_STORE = "LobbyVipServers1",

	-- the test lobby replaces the AR2 Development Hub in its place and keeps
	-- the hub's names, so test servers' Hub Beacon and join lock work unchanged
	-- (game repo: src/Server/Configs/HubProtocol.lua)
	TEST_LOBBY_PLACE_ID = 9350655892,
	HUB_VERSION = 1,
	HUB_SOURCE = "AR2Hub",
	-- the test directory: same shard format as DIRECTORY_STORE, fewer shards
	HUB_DIRECTORY_STORE = "HubServerDirectory2",
	HUB_DIRECTORY_SHARDS = 2,
	HUB_GRANTS_MAP = "HubTeleportGrants1",
	HUB_GRANT_TTL = 300,

	-- the old hub's cache of each single-server place's reserved server;
	-- reusing it keeps testers going to the same locked servers
	RESERVED_STORE = "ReservedServerInfo",
	RESERVED_INDEX = 3,

	-- wrong passwords allowed per player per minute
	PASSWORD_ATTEMPTS = 5,

	-- lobby read budget; each lobby server reads every shard once per
	-- interval (SHARDS GetAsync calls) and fans the result out to its players.
	-- Clients never read the directory, and there's no refresh button: lists
	-- update on their own. 20 shards every 30s is 40 reads a minute, inside
	-- even an empty lobby server's GetAsync budget (60 + 10 per player)
	POLL_INTERVAL = 30,

	-- after a failed read, or too little DataStore budget to read every shard,
	-- the interval doubles per failure up to this, and resets on a good read
	POLL_BACKOFF_MAX = 120,
	MAX_SERVERS_PER_MAP = 50,
}
