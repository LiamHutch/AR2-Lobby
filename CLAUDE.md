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
src/Shared/  → ReplicatedStorage.Shared                   Maps.lua (map list), Protocol.lua (constants shared with the game)
src/Server/  → ServerScriptService.Lobby                  Main.server.lua, Directory.lua (reads the server list), Teleports.lua
src/Client/  → StarterPlayer.StarterPlayerScripts.Lobby   Browser.client.lua (binds the UI)
tools/build-ui.lua                                        command-bar script that builds StarterGui.Lobby
```
Remotes (`ReplicatedStorage.Remotes.Directory/Play/Status`) and `Players.CharacterAutoLoads = false` are declared in [default.project.json](default.project.json).

## UI lives in the place
The UI is **built in Studio**, not in code. `StarterGui.Lobby` is not Rojo-managed. [tools/build-ui.lua](tools/build-ui.lua) builds the first version from `StarterGui.PickerDemo` (the game's VIPHome card). After that, Studio is the source of truth and designers can edit it freely **as long as the names in the UI contract below survive**. Re-running the build script wipes hand edits.

UI contract (what [Browser.client.lua](src/Client/Browser.client.lua) looks up by name):
- `Lobby.Maps`: card container (layout inside is free)
- `Lobby.Templates.MapCard`: `Title`, `Status`, `Stats`, `Art`, `HighlightBox`, `ClickButton`, `ComingSoon`, `Servers.Button`, `Servers.HighlightBox`
- `Lobby.Templates.ServerRow`: `Players`, `Uptime`, `Button`, `HighlightBox`
- `Lobby.Servers`: `Title`, `Close`, `CloseHighlight`, `List`, `Empty`
- `Lobby.Status`

Style: match the game's main menu. Oswald (Bold titles, Regular Italic subtext), spaced capitals with the first word in the map's accent colour, dark `#181818`–`#3B3B3B` fills, the sliced soft shadow `rbxassetid://1677877208`, and highlight box `6116907099`. Floating elements, minimal text. **No helper copy or explanatory labels**; the owner wants it terse.

---

## How the game side works

The game is the `ApocalypseRising2` repo (branches `production`, `tourney`, `freeroam`; read its CLAUDE.md before touching it). The lobby only talks to it through **MemoryStore** and **TeleportService**, never through code sharing.

**Server list.** Each public prod game server runs `src/Server/Browser Beacon.server.lua` (game repo, branch `serverbrowser` until merged). It writes one entry to the MemoryStore hashmap `BrowserDirectory1`, keyed by JobId, with a 120s TTL:
`{ v, placeId, jobId, players, maxPlayers, startedAt, placeVersion }`.
It skips Studio, reserved/VIP servers, Ban Land, and every non-prod place, because the game's test server lock wipes public servers on test places.

**Protocol constants.** [src/Shared/Protocol.lua](src/Shared/Protocol.lua) here mirrors the `BROWSER_*` fields in the game's `src/Server/Configs/HubProtocol.lua`. Change both together, and bump the version (and the map name, e.g. `BrowserDirectory2`) for breaking changes.

**Separate from the dev hub.** The same HubProtocol also serves the older *AR2 Development Hub* (place 9350655892): `HubServerDirectory1`, `HubTeleportGrants1`, and `hub-*` MessagingService topics, for test reserved servers only. Don't reuse those names.

**Joining.** The lobby calls `TeleportAsync` server-side. With no instance id, Roblox matchmakes into a public server (the one-click card). With `ServerInstanceId`, it joins a specific server from the list. Teleport data is `{ source = "AR2Lobby", v, map }`. The game doesn't read it yet.

**Universe.** MemoryStore and teleports are per-universe. The lobby must be published **inside the same universe** as the game places it lists. [Directory.lua](src/Server/Directory.lua) resolves each map's place with `AssetService:GetGamePlacesAsync()`. A map with no place in the current universe shows as "coming soon". In unpublished Studio it falls back to the first id so the UI can be built.

## Rate limits: keep it cheap
- MemoryStore budget is per experience: 1000 + 100 × CCU requests/min.
- Game servers write at most once per 15s on population changes, otherwise once per 45s. That's ≤4 req/min per server, against the ≥100/min each of its players adds to the budget.
- Each **lobby server** reads the directory once per 15s, and only while it has players. It fans the snapshot out to its clients over one RemoteEvent. **Clients never read MemoryStore**, and nothing should poll per player.
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
