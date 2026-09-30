# AR2 Lobby — Claude Code Context

The standalone lobby / server browser for Apocalypse Rising 2. Players land here, pick a map (or a specific server), and get teleported into the game. It is deliberately small and does **not** use the game's framework or its sync rules. The human-facing brief is [README.md](README.md).

---

## Language & Platform
- **Roblox**, all code is **Luau**, mostly untyped. Use `task.*`, never `spawn`/`delay`/`wait`.
- No framework, no packages. Plain `require` of sibling modules. Keep it that way unless asked.
- Match the game's code style: tabs, lower-camel locals, `----` section separators, short comments that say *why*.

## Toolchain
- Rojo is pinned in [aftman.toml](aftman.toml) at the same version as the game (**7.7.0**). Bump both together.
- `rojo serve` into the lobby place. `rojo build -o x.rbxl` is only a compile check.
- Lint with selene (`std = "roblox"`). No config is committed yet; the `Keep Up` repo's `selene.toml` + `roblox.yml` work.

## Layout
```
src/Shared/  → ReplicatedStorage.Shared                   Maps.lua (map list + flavour), Protocol.lua (constants shared with the game),
                                                          Names.lua (server names from JobIds), Platform.lua (client platform + support levels)
src/Server/  → ServerScriptService.Lobby                  Main.server.lua, Catalog.lua (variant, maps, access, passwords), Directory.lua (reads the
                                                          server list), Teleports.lua, Reserved.lua (single-server locks), PlaceConfig.lua (reads map configs from the place),
                                                          Vip.lua (VIP servers, built but hidden), Mock.lua (fake list for unpublished Studio)
src/Client/  → ReplicatedFirst.Browser                    Browser.client.lua (moves the gui into PlayerGui, binds it)
tools/build-ui.lua                                        command-bar script that builds ReplicatedFirst.Lobby
tools/maps-to-folders.lua                                 command-bar script that turns Shared/Maps.lua into place config folders
```
Remotes (`ReplicatedStorage.Remotes.Directory/Play/Status/Refresh`) and `Players.CharacterAutoLoads = false` are declared in [default.project.json](default.project.json).

## UI lives in the place
The UI is **built in Studio**, not in code. `ReplicatedFirst.Lobby` is not Rojo-managed. It lives in ReplicatedFirst, not StarterGui, because `CharacterAutoLoads = false` means StarterGui is never copied into PlayerGui; the client script moves it over (the game's usual pattern). [tools/build-ui.lua](tools/build-ui.lua) builds the first version with the game's styling recreated from values (see Style below). After that, Studio is the source of truth and designers can edit it freely **as long as the names in the UI contract below survive**. Re-running the build script wipes hand edits, **except `Lobby.Background`**, which it keeps (it's the game's main menu backdrop, art-directed in Studio).

UI contract (what [Browser.client.lua](src/Client/Browser.client.lua) looks up by name). A "text box" is a Frame holding `Text` and its drop-shadow copy `Shadow`; the client writes both. Game-style buttons are Frames with `Stroke`, `Backdrop`, `Label` (text box) or `Icon`, `HighlightBox` and a clear `Button` on top.
- Two screens on `Lobby.Stage` (laid out at 1440x810; the client sets `Stage.Scale` to fit): `Picker.Maps` (card container, layout free) and `MapView`
- `MapView.Info`: text boxes `Title`, `Counts.Online`, `Counts.Servers`, `Blurb`, `Notice`; bins `Stats`, `Platforms`; `Preview.Clip.ImageA/ImageB`; buttons `Buttons.Back`, `Buttons.Play`, `Buttons.Refresh`; `Buttons.Password.Input` (TextBox, shown for password maps)
- `MapView.Browser`: `Sorts.Players/Newest/Region` (chips with `Label`, `Stroke`, `HighlightBox`, `Button`), `List`, text box `Empty`, `Footer` with text boxes `ServerName`, `Meta` and button `Join`
- `Lobby.Background.Bleed` (the open map's `Backdrop` art), `Stage.Status` (text box)
- `Lobby.Templates.*` stay `Visible = false` (they'd render otherwise); the client shows its clones
- Map art: `Images` (landscape) feeds the map view preview; `CardImages` (portrait) feeds the picker card, falling back to `Images`
- `Templates.MapCard`: `Clip.Art`, text boxes `Title`, `Online`, bin `Platforms`, `ComingSoon`, `HighlightBox`, `Button`
- `Templates.ServerRow` (a GuiButton): text boxes `Server`, `Id`, `Region`, `Uptime`, `Players`; `Stroke`, `HighlightBox`. Don't name a child `Name`: the property hides it
- `Templates.StatItem` (text boxes `Label`, `Value`), `Templates.PlatformChip` (`Icon`, `Label`, `Stroke`), `Templates.Selection` (gamepad selection ring)
- Sounds (in the place, not Rojo): `ReplicatedStorage.Sounds.AmbientLoop` fades in to its own Volume when a player joins, played locally; `Sounds.Interface.Click` (button presses), `MapOpen` / `MapClose` (entering and leaving a map). Missing sounds are silent

Platform support is advisory: [Platform.lua](src/Shared/Platform.lua) detects PC / Xbox / PlayStation / Mobile, and each map's `Platforms` marks some `warn` (notice, still joinable) or `blocked` (Play/Join disabled). Nothing server-side enforces it; the game places should kick unsupported platforms themselves because friend-joins skip the lobby. In Studio, set a `DebugPlatform` attribute on ReplicatedStorage to preview another platform.

Style: match the game's main menu (`ReplicatedStorage.Interface.MainMenu.Master` in the game place; `VIPHome.FreeroamWindow` is the closest reference). Terse: **no helper copy or explanatory labels**.
- Type: Oswald **Heavy** for headers and button text, **SemiBold/Medium Italic** subtext, SourceSansPro Italic for body copy. Headers use spaced capitals, all bone (no accent colours).
- Colour: bone `229,226,219` text, gold `202,188,131` button stroke and text, panels `27,27,27`, nav bar `18,18,21`; disabled `85,85,85`.
- Text is drawn twice: a black copy at TextTransparency 0.75 one ZIndex below, offset +4 (big), +2 (subtext) or +1 (small).
- Buttons: black frame at 0.3 transparency, 2px Miter UIStroke, grunge texture `104544475726279` (tiled 1048, 0.7 transparent, tinted), shadow `1677877208` (slice 30, 0.7), HighlightBox `6116907099` (slice 13, +10px) on hover/select, transparent ImageButton on top.
- List rows: black at 0.7 transparency with a UIGradient fading in from the left, square, 4px gaps.
- **No rounded corners** anywhere; strokes are 2px Miter. Small chips are mini buttons (black 0.3, stroke, no grunge); their HighlightBox uses `SliceScale` ~0.45 so its line lands on the chip's edge instead of inside it.
- Server ids show only the JobId's first group (before the first dash).
- The ScreenGui is full screen (`ScreenInsets = None`, so the background runs under Roblox's top bar); the client scales and centres the 1440x810 Stage in the area below the top bar (`GuiService.TopbarInset`) with a 24px margin. Don't use CoreUISafeInsets: an inset ScreenGui clips its background.

---

## How the game side works

The game is the `ApocalypseRising2` repo (branches `production`, `tourney`, `freeroam`; read its CLAUDE.md before touching it). The lobby only talks to it through **MemoryStore** and **TeleportService**, never through code sharing.

**Server list.** Each public prod game server runs `src/Server/Browser Beacon.server.lua` (game repo, branch `serverbrowser` until merged). It writes one entry to the MemoryStore hashmap `BrowserDirectory1`, keyed by JobId, with a 120s TTL:
`{ v, placeId, jobId, players, maxPlayers, startedAt, placeVersion, region? }`. `region` is the game's own geolocation, `"City - Region"` (e.g. "Ashburn - Virginia"); the lobby shows the part after " - ", cut on a word, and "—" without one. The game writes `kind = "public"` and `region` on branch `serverbrowser` (not merged yet).
It skips Studio, reserved/VIP servers, Ban Land, and every non-prod place, because the game's test server lock wipes public servers on test places.

**Protocol constants.** [src/Shared/Protocol.lua](src/Shared/Protocol.lua) here mirrors the `BROWSER_*` fields in the game's `src/Server/Configs/HubProtocol.lua`. Change both together, and bump the version (and the map name, e.g. `BrowserDirectory2`) for breaking changes.

**Two lobbies, one codebase.** [Catalog.lua](src/Server/Catalog.lua) picks the variant from `game.PlaceId` (Studio: a `LobbyVariant` attribute on ServerStorage, `"test"` or `"prod"`).
- **prod**: the public browser. Maps from [Shared/Maps.lua](src/Shared/Maps.lua), directory `BrowserDirectory1`, public servers.
- **test**: replaces the old *AR2 Development Hub* in its place (9350655892) and keeps its names so test places need no changes: it reads `HubServerDirectory1` (the game's Hub Beacon), writes a single-use grant to `HubTeleportGrants1` before every teleport (the game's Test server lock checks it), and sends TeleportData `{ source = "AR2Hub", v }`. Its maps are the hub's own `ServerStorage.Teleports.Active` config, copied into the place (see "Map config lives in the place").
  - **Access**: group 9630142 role → tier (Tester/Staff/Developer/Public, from the hub's `RoleToAccessRank`), checked on the lobby server. Clients only receive maps their tier can see.
  - **Passwords**: a map's `Password` StringValue in the place config, **never in git** and never sent to a client. Checked server-side, 5 wrong tries a minute.
  - **Single-server lock** (`SingleServer`): everyone goes to one shared reserved server per map so a test can be watched. [Reserved.lua](src/Server/Reserved.lua) uses the hub's DataStore `ReservedServerInfo`, key `"<placeId> - 3"`, so the hub's existing locked servers carry over. Full means full; there's no queue yet.
  - The old hub also wrote a legacy `TestServerWhitelist` DataStore entry and waited 3s; the lobby doesn't. Test places still running the pre-grant lock will kick lobby arrivals.

**Joining.** The lobby calls `TeleportAsync` server-side. With no instance id, Roblox matchmakes into a public server (the one-click card). With `ServerInstanceId`, it joins a specific server from the list. Teleport data is `{ source = "AR2Lobby", v, map }`. The game doesn't read it yet.

**Places.** Prod lobby **863266079** (formerly the game's Prod - Main). Test lobby **9350655892** (the old dev hub's place). Beta Map runs on **90014710188160** (production main; test copy 12123099753), Kin Map on **81089296768446** (production retro). The prod map configs are place folders in the lobby place; `Maps.lua` mirrors them as the fallback.

**Universe.** MemoryStore and teleports are per-universe. The lobby must be published **inside the same universe** as the game places it lists. [Directory.lua](src/Server/Directory.lua) resolves each map's place with `AssetService:GetGamePlacesAsync()`. A map with no place in the current universe shows as "coming soon". In unpublished Studio (`GameId == 0`) it falls back to each map's first id and serves a fake server list from [Mock.lua](src/Server/Mock.lua), so the UI can be built and demoed. Teleports there fail straight away with "couldn't join". Once the place is published, Studio reads the real directory.

## Map config lives in the place
Map configs are Folders and ValueBase objects in the lobby place, read by [PlaceConfig.lua](src/Server/PlaceConfig.lua) when a server starts, so people without the repo can edit them in Studio and publish. It's the **old dev hub's layout**, so the hub's folders copy straight across:
- `ServerStorage.Teleports.Active.<Title>`: one Folder per map. Hub fields `PlaceId`, `Description`, `Password`, `MultiServer` (off = single-server lock), `Access` (BoolValues per tier; missing = everyone). Lobby extras, all optional: `Key`, `Order`, `Accent`, `Images`, `Backdrop`, `Stats`, `Platforms`, `Vip`, `PlaceIds`. The full list is at the top of PlaceConfig.lua.
- `ServerStorage.Teleports.Archive`: ignored. `ServerStorage.RoleToAccessRank`: group role → tier StringValues (`GroupId` attribute, default 9630142).

A prod place without that folder falls back to [Shared/Maps.lua](src/Shared/Maps.lua); [tools/maps-to-folders.lua](tools/maps-to-folders.lua) converts it into folders. A test place without it has no maps. Config is ServerStorage-only; clients get `PublicInfo` for the maps they may see.

## VIP servers (built, hidden)
Directory entries carry a `kind` (see [Protocol.lua](src/Shared/Protocol.lua)); missing means `"public"`. Lobbies skip kinds they don't handle, and an entry only counts if it comes from a place of that kind (a map's `Vip = { [kind] = placeIds }` in Maps.lua). `Protocol.VIP_LISTING` is **off**: nothing VIP is listed or joinable until the game side exists. In Studio, a `ShowVip` attribute on ServerStorage turns on mock VIP rows.

What "VIP" is in the game, and what the lobby does with it:
- **Freeroam** (the kind that's built): each host has one permanent reserved server on the VIP Freeroam place. The game's Browser Beacon would list it with `kind = "freeroam"`, `hostId`, `locked`, `settings`, and **never** an access code or PrivateServerId. On join, [Vip.lua](src/Server/Vip.lua) pre-checks the lock from the directory entry (only the host gets past it), plus bans and co-hosts from the game's MemoryStore `Freeroam Configs - 4` when there's an entry (60s TTL, written only on setting changes, so usually missing). The freeroam server enforces its lock and bans on arrival, so this is only to spare a wasted teleport. It then reads the access code from the DataStore `Freeroam Servers - 4` (server-side only, cached), writes a single-use ticket to `BrowserTickets1`, and teleports to the VIP place with `ReservedServerAccessCode`. The freeroam server accepts that ticket on arrival (game branches `serverbrowser` + `freeroambrowser`, not merged yet); the lobby never writes the game's own `Freeroam Sessions - 4`. Freeroam `settings` values are strings ("On"/"Off"; TimeOfDayFrozen is a time or "Off").
- **Paid VIP lobbies on Main** (Roblox private servers): strangers can't be teleported into them, so at most listable. Not a kind yet.
- **Tourney matches**: roster-locked per match. Not a kind.

Rows for VIP servers show "VIP · host", LOCKED in amber, and the host's notable settings in the footer; public servers sort first. Access codes and private server ids never reach a client.

## Rate limits: keep it cheap
- MemoryStore budget is per experience: 1000 + 100 × CCU requests/min.
- Game servers write at most once per 15s on population changes, otherwise once per 45s. That's ≤4 req/min per server, against the ≥100/min each of its players adds to the budget.
- Each **lobby server** reads the directory once per 15s, and only while it has players. The Refresh button only triggers an early read if the snapshot is over 5s old, so it's at most one extra read per 5s per lobby server, however many players press it (and each player is limited to one request per 3s). It sends each player their visible maps and servers over one RemoteEvent (one FireClient each, no extra reads). **Clients never read MemoryStore**, and nothing should poll per player.
- Reads are capped at 5 pages × 200 entries. Up to 50 servers per map go to the client, sorted with non-full first, then by player count.
- No MessagingService in the browser path. If you add push updates later, measure the per-topic limits against prod server counts first.

## Game data
Longer term the lobby may mirror the game's shop and character creator, which means reading the game's SaveData stores. That work has **not** started. The game's persistence layer (`src/Server/Libraries/SaveData.lua` in the game repo) is sensitive and has a time-based session lock, so any lobby access to player data needs an explicit plan agreed with the owner first. The lobby must never write to game stores.

## Roblox Studio MCP
Same rules as the game repo. Code goes through Rojo, never the MCP. Reading the tree and instances is fine. **Every write, including `execute_luau`, needs an explicit yes per action.** Never start Play or a test session; say what to test and stop.

## Git
- Single `main` branch at github.com/LiamHutch/AR2-Lobby. Short lower-case commit messages.
- Commit when asked; show the diff and get a yes before pushing.
- Never commit `.rbxl`/`.rbxlx` or `sourcemap.json`.
