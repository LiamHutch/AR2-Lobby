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
--     location = table?,      -- its parts, newer game builds: { area, city,
--                             -- state, country, countryCode, continent }; area
--                             -- is "US East", "US Central", "US West", "Canada"
--                             -- or the continent
--     kind = string?,         -- see KINDS; missing means "public"
--     privateServerId = string?, -- test directory: every server (single-server
--                             -- maps list just their shared one). Prod: pool
--                             -- servers only (see Pools below)
--     pool = string?,         -- pool servers only: the pool from the lobby's
--                             -- TeleportData, "console" or "mobile"
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
--   freeroam  a host's Free Roam server, one persistent reserved server
--             per host; joined through the lobby's ticket, never directly
--   tourney   a reserved match server; roster-locked, never listed or joined
--
-- Pools: platform-only servers (the lobby's Pools.lua). "Any" is a map's
-- public servers, which Roblox matchmakes. Console-only and mobile-only
-- servers are reserved servers the lobby keeps in a pool per map and POOLS
-- name, reserved once and reused forever:
--   POOLS_STORE, key "<placeId>:<pool>"
--   -> { v = POOL_VERSION, slots = { { code, id, at } } }   (id = PrivateServerId)
-- Lobby-only; access codes never leave lobby servers. A game server learns its
-- pool from the first arrival's TeleportData (only the lobby holds the codes,
-- so every arrival came from it), lists itself as kind "public" with `pool`
-- and `privateServerId`, and writes its entry as soon as it knows. The lobby
-- matches entries to slots by privateServerId, not by the `pool` label.
--
-- Teleport data the lobby sends to the game:
--   { source = SOURCE, v = VERSION, map = <Maps key>, kind?, hostId?, pool? }
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

	-- platform-only servers (see Pools above and Pools.lua). Platform.lua says
	-- which platforms belong to which pool
	POOLS = { "console", "mobile" },
	POOLS_STORE = "LobbyPlatformPools1",
	POOL_VERSION = 1,
	-- most servers one pool may ever reserve, in case something runs away
	POOL_CAP = 50,
	-- seconds between re-reads of a pool, to pick up slots other lobbies added
	-- (the test directory doesn't label pool servers, so it can't prompt one)
	POOL_REFRESH = 300,

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

	-- private server sessions (Sessions.lua): every player hosts their own
	-- tourney lobby and free roam server from the lobby. Each host's config is
	-- lobby-owned (Shared/Private.lua has the shape):
	--   PRIVATE_STORE  DataStore, key "<kind>:<userId>" -> { v = PRIVATE_VERSION, ... }
	-- The freeroam build reads its host's record at boot and writes settings
	-- and bans back (game: HubProtocol.PRIVATE_STORE); never change the shape
	-- on one side alone
	PRIVATE_STORE = "PrivateConfigs1",
	PRIVATE_VERSION = 1,
	-- seconds between re-reads of a hosted free roam server's live data
	PRIVATE_LIVE_POLL = 30,
	-- the lobby's own countdown before a match commits and teleports
	TOURNEY_COUNTDOWN = 10,

	-- game stores the private modes still talk through. Their shapes are the
	-- game's (Tourney.lua and Freeroam.lua adapt to them); once the game reads
	-- the lobby's config directly these go
	--   TOURNEY_HANDOFF_MAP     MemoryStore hash map, key = the reserved match
	--                           server's PrivateServerId -> the match config
	--   TOURNEY_SESSIONS_STORE  DataStore, key = userId -> { PlaceId, AccessCode,
	--                           ServerId, WrittenAt }, written by a running
	--                           match server so a player can rejoin it
	--   TOURNEY_LEGACY_STORE    the old VIP lobby's saved match configs, read
	--                           once to seed a host's lobby config
	--   FREEROAM_SERVERS_STORE  DataStore, key = hostId -> { AccessCode, ServerId,
	--                           HostId, CreatedAt }: the host's permanent reserved
	--                           server, which the game checks on arrival
	--   FREEROAM_CONFIGS_STORE  DataStore, key = hostId -> the old VIP lobby's
	--                           config shape; read once to seed a host's record
	--   FREEROAM_LOBBIES_MAP    MemoryStore hash map, key = hostId -> live data a
	--                           running free roam server writes every 15s
	TOURNEY_HANDOFF_MAP = "Tourney Match Handoff",
	TOURNEY_HANDOFF_TTL = 24 * 60 * 60,
	TOURNEY_SESSIONS_STORE = "Tourney Sessions",
	TOURNEY_SESSION_MAX_AGE = 12 * 60 * 60,
	TOURNEY_LEGACY_STORE = "VIP Match Configs 3",
	FREEROAM_SERVERS_STORE = "Freeroam Servers - 4",
	FREEROAM_CONFIGS_STORE = "Freeroam Configs - 4",
	FREEROAM_LOBBIES_MAP = "Freeroam Lobbies - 4",

	-- lobby-to-lobby invites (Invites.lua): one MessagingService topic every
	-- lobby server subscribes to; a message is
	--   { to, from, fromName, key, jobId, placeId, at }
	-- and the server holding `to` shows them the invite. INVITE_TTL seconds is
	-- how long an invite stays accepted and how long a private session stays
	-- visible to the invitee; INVITE_GAP the seconds between a host's invites
	INVITE_TOPIC = "LobbyInvites1",
	INVITE_TTL = 120,
	INVITE_GAP = 5,

	-- the game's Return To Lobby button sends players here with
	-- { source = GAME_SOURCE, v = 1, placeId, mode? }; mode names the page to
	-- open on arrival ("Tourney" / "Freeroam"). Game: HubProtocol.GAME_SOURCE
	GAME_SOURCE = "AR2Game",

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
