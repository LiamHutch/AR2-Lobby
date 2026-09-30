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
                                                          server list), Teleports.lua, Reserved.lua (single-server locks), TestMaps.lua (test lobby maps),
                                                          Mock.lua (fake list for unpublished Studio)
src/Client/  → ReplicatedFirst.Browser                    Browser.client.lua (moves the gui into PlayerGui, binds it)
tools/build-ui.lua                                        command-bar script that builds ReplicatedFirst.Lobby
```
Remotes (`ReplicatedStorage.Remotes.Directory/Play/Status/Refresh`) and `Players.CharacterAutoLoads = false` are declared in [default.project.json](default.project.json).

## UI lives in the place
The UI is **built in Studio**, not in code. `ReplicatedFirst.Lobby` is not Rojo-managed. It lives in ReplicatedFirst, not StarterGui, because `CharacterAutoLoads = false` means StarterGui is never copied into PlayerGui; the client script moves it over (the game's usual pattern). [tools/build-ui.lua](tools/build-ui.lua) builds the first version with the game's styling recreated from values (see Style below). After that, Studio is the source of truth and designers can edit it freely **as long as the names in the UI contract below survive**. Re-running the build script wipes hand edits.

UI contract (what [Browser.client.lua](src/Client/Browser.client.lua) looks up by name). A "text box" is a Frame holding `Text` and its drop-shadow copy `Shadow`; the client writes both. Game-style buttons are Frames with `Stroke`, `Backdrop`, `Label` (text box) or `Icon`, `HighlightBox` and a clear `Button` on top.
- Two screens on `Lobby.Stage` (laid out at 1440x810; the client sets `Stage.Scale` to fit): `Picker.Maps` (card container, layout free) and `MapView`
- `MapView.Info`: text boxes `Title`, `Counts.Online`, `Counts.Servers`, `Blurb`, `Notice`; bins `Stats`, `Platforms`; `Preview.Clip.ImageA/ImageB`; buttons `Buttons.Back`, `Buttons.Play`, `Buttons.Refresh`; `Buttons.Password.Input` (TextBox, shown for password maps)
- `MapView.Browser`: `Sorts.Players/Newest/Region` (chips with `Label`, `Stroke`, `HighlightBox`, `Button`), `List`, text box `Empty`, `Footer` with text boxes `ServerName`, `Meta` and button `Join`
- `Lobby.Background.Bleed` (the open map's `Backdrop` art), `Stage.Status` (text box)
- `Lobby.Templates.*` stay `Visible = false` (they'd render otherwise); the client shows its clones
- `Templates.MapCard`: `Clip.Art`, text boxes `Title`, `Online`, bin `Platforms`, `ComingSoon`, `HighlightBox`, `Button`
- `Templates.ServerRow` (a GuiButton): text boxes `Server`, `Id`, `Region`, `Uptime`, `Players`; `Stroke`, `HighlightBox`. Don't name a child `Name`: the property hides it
- `Templates.StatItem` (text boxes `Label`, `Value`), `Templates.PlatformChip` (`Icon`, `Label`, `Stroke`), `Templates.Selection` (gamepad selection ring)

Platform support is advisory: [Platform.lua](src/Shared/Platform.lua) detects PC / Xbox / PlayStation / Mobile, and each map's `Platforms` marks some `warn` (notice, still joinable) or `blocked` (Play/Join disabled). Nothing server-side enforces it; the game places should kick unsupported platforms themselves because friend-joins skip the lobby. In Studio, set a `DebugPlatform` attribute on ReplicatedStorage to preview another platform.

Style: match the game's main menu (`ReplicatedStorage.Interface.MainMenu.Master` in the game place; `VIPHome.FreeroamWindow` is the closest reference). Terse: **no helper copy or explanatory labels**.
- Type: Oswald **Heavy** for headers and button text, **SemiBold/Medium Italic** subtext, SourceSansPro Italic for body copy. Headers use spaced capitals, first word in the map's accent colour.
- Colour: bone `229,226,219` text, gold `202,188,131` button stroke and text, panels `27,27,27`, nav bar `18,18,21`; disabled `85,85,85`.
- Text is drawn twice: a black copy at TextTransparency 0.75 one ZIndex below, offset +4 (big), +2 (subtext) or +1 (small).
- Buttons: black frame at 0.3 transparency, 2px Miter UIStroke, grunge texture `104544475726279` (tiled 1048, 0.7 transparent, tinted), shadow `1677877208` (slice 30, 0.7), HighlightBox `6116907099` (slice 13, +10px) on hover/select, transparent ImageButton on top.
- List rows: black at 0.7 transparency with a UIGradient fading in from the left, 2px corners, 4px gaps.

---

## How the game side works

The game is the `ApocalypseRising2` repo (branches `production`, `tourney`, `freeroam`; read its CLAUDE.md before touching it). The lobby only talks to it through **MemoryStore** and **TeleportService**, never through code sharing.

**Server list.** Each public prod game server runs `src/Server/Browser Beacon.server.lua` (game repo, branch `serverbrowser` until merged). It writes one entry to the MemoryStore hashmap `BrowserDirectory1`, keyed by JobId, with a 120s TTL:
`{ v, placeId, jobId, players, maxPlayers, startedAt, placeVersion, region? }`. `region` is optional and **not written by the game yet**; the lobby shows "—" without it.
It skips Studio, reserved/VIP servers, Ban Land, and every non-prod place, because the game's test server lock wipes public servers on test places.

**Protocol constants.** [src/Shared/Protocol.lua](src/Shared/Protocol.lua) here mirrors the `BROWSER_*` fields in the game's `src/Server/Configs/HubProtocol.lua`. Change both together, and bump the version (and the map name, e.g. `BrowserDirectory2`) for breaking changes.

**Two lobbies, one codebase.** [Catalog.lua](src/Server/Catalog.lua) picks the variant from `game.PlaceId` (Studio: a `LobbyVariant` attribute on ServerStorage, `"test"` or `"prod"`).
- **prod**: the public browser. Maps from [Shared/Maps.lua](src/Shared/Maps.lua), directory `BrowserDirectory1`, public servers.
- **test**: replaces the old *AR2 Development Hub* in its place (9350655892) and keeps its names so test places need no changes: it reads `HubServerDirectory1` (the game's Hub Beacon), writes a single-use grant to `HubTeleportGrants1` before every teleport (the game's Test server lock checks it), and sends TeleportData `{ source = "AR2Hub", v }`. Maps are in server-only [TestMaps.lua](src/Server/TestMaps.lua), copied from the hub's `ServerStorage.Teleports.Active`.
  - **Access**: group 9630142 role → tier (Tester/Staff/Developer/Public, from the hub's `RoleToAccessRank`), checked on the lobby server. Clients only receive maps their tier can see.
  - **Passwords**: `Password = true` in the map config; the value is a StringValue at `ServerStorage.LobbyPasswords.<Key>` **in the place, never in git**. Checked server-side, 5 wrong tries a minute.
  - **Single-server lock** (`SingleServer`): everyone goes to one shared reserved server per map so a test can be watched. [Reserved.lua](src/Server/Reserved.lua) uses the hub's DataStore `ReservedServerInfo`, key `"<placeId> - 3"`, so the hub's existing locked servers carry over. Full means full; there's no queue yet.
  - The old hub also wrote a legacy `TestServerWhitelist` DataStore entry and waited 3s; the lobby doesn't. Test places still running the pre-grant lock will kick lobby arrivals.

**Joining.** The lobby calls `TeleportAsync` server-side. With no instance id, Roblox matchmakes into a public server (the one-click card). With `ServerInstanceId`, it joins a specific server from the list. Teleport data is `{ source = "AR2Lobby", v, map }`. The game doesn't read it yet.

**Universe.** MemoryStore and teleports are per-universe. The lobby must be published **inside the same universe** as the game places it lists. [Directory.lua](src/Server/Directory.lua) resolves each map's place with `AssetService:GetGamePlacesAsync()`. A map with no place in the current universe shows as "coming soon". In unpublished Studio (`GameId == 0`) it falls back to each map's first id and serves a fake server list from [Mock.lua](src/Server/Mock.lua), so the UI can be built and demoed. Teleports there fail straight away with "couldn't join". Once the place is published, Studio reads the real directory.

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
