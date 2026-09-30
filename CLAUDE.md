# AR2 Lobby — Claude Code Context

The standalone lobby / server browser for Apocalypse Rising 2. Players land here, pick a map (or a specific server), and get teleported into the game. It is deliberately small and does **not** use the game's framework or its sync rules. The human-facing brief is [README.md](README.md).

---

## Language & Platform
- **Roblox**, all code is **Luau**, mostly untyped. Use `task.*`, never `spawn`/`delay`/`wait`.
- No framework, no packages. Plain `require` of sibling modules. Keep it that way unless asked.
- Match the game's code style: tabs, lower-camel locals, `----` section separators, short comments that say *why*.

## Toolchain
- Rojo is pinned in [aftman.toml](aftman.toml) at the same version as the game (**7.7.0**). Bump both together.
- `rojo serve` into the lobby place. `servePlaceIds` in the project locks syncing to the test hub (9350655892) and the prod lobby (863266079), so the plugin refuses any other place, including an unpublished one. `rojo build -o x.rbxl` is only a compile check.
- Lint with selene (`std = "roblox"`). No config is committed yet; the `Keep Up` repo's `selene.toml` + `roblox.yml` work.

## Layout
```
src/Shared/  → ReplicatedStorage.Shared                   Maps.lua (map list + flavour), Protocol.lua (constants shared with the game),
                                                          Names.lua (server names from JobIds), Platform.lua (client platform + support levels)
src/Server/  → ServerScriptService.Lobby                  Main.server.lua, Catalog.lua (variant, maps, access, passwords), Directory.lua (reads the
                                                          server list), Teleports.lua, Reserved.lua (single-server locks), Pools.lua (platform-only servers),
                                                          PlaceConfig.lua (reads map configs from the place),
                                                          Vip.lua (VIP servers, built but hidden), Mock.lua (fake list for unpublished Studio)
src/Client/Browser/ → ReplicatedFirst.Browser             init.client.lua (moves the gui into PlayerGui, binds it), Slideshow.lua (map art), Loading.lua (teleport screen)
tools/build-ui.lua                                        command-bar script that builds ReplicatedFirst.Lobby
```
Remotes (`ReplicatedStorage.Remotes.Directory/Play/Status`) and `Players.CharacterAutoLoads = false` are declared in [default.project.json](default.project.json).

The lobby is **UI only**: the Workspace is empty on purpose (just Camera and Terrain), and no one ever gets a character. `CharacterAutoLoads` is off, and [Main.server.lua](src/Server/Main.server.lua) removes any character that appears anyway, so servers only do lobby work.

## UI lives in the place
The UI is **built in Studio**, not in code. `ReplicatedFirst.Lobby` is not Rojo-managed. It lives in ReplicatedFirst, not StarterGui, because `CharacterAutoLoads = false` means StarterGui is never copied into PlayerGui; the client script moves it over (the game's usual pattern). [tools/build-ui.lua](tools/build-ui.lua) builds the first version with the game's styling recreated from values (see Style below). After that, Studio is the source of truth and designers can edit it freely **as long as the names in the UI contract below survive**. Re-running the build script wipes hand edits, **except `Lobby.Background`**, which it keeps (it's the game's main menu backdrop, art-directed in Studio).

UI contract (what [init.client.lua](src/Client/Browser/init.client.lua) looks up by name). A "text box" is a Frame holding `Text` and its drop-shadow copy `Shadow`; the client writes both. Game-style buttons are Frames with `Stroke`, `Backdrop`, `Label` (text box) or `Icon`, `HighlightBox` and a clear `Button` on top.
- Two screens on `Lobby.Stage` (laid out at 1440x810; the client sets `Stage.Scale` to fit): `Picker.Heading` (text box, top right, clear of Roblox's top-left buttons), `Picker.EdgeFade.Maps` (card row, a ScrollingFrame with a thin square bone scroll bar that shows once the maps overflow; the client centres it with its UIPadding while the cards fit) and `MapView`
- `MapView.Info`: text boxes `Title`, `Counts.Online`, `Counts.Servers`, `Blurb`, `Notice`; bins `Stats`, `Platforms`; `Preview.Clip` (the slideshow adds its viewports), `Preview.Clip.Dots` (the image picker, filled from `Templates.PreviewDot`, each with a `Bar`) and `Preview.Clip.Shade`; buttons `Buttons.Back`, `Buttons.Play` (Any servers), `Buttons.PlayPool` (optional: this platform's own servers, shown when the map has a pool for it, "PLAY CONSOLE"/"PLAY MOBILE"; Play then reads "PLAY ANY"); `Buttons.Password.Input` (TextBox, shown for password maps). Play and PlayPool are 355 wide with a `UIFlexItem` (Shrink), so they only narrow when they share the row
- `MapView.Browser`: `Sorts.Players/Newest/Region` (chips with `Label`, `Stroke`, `HighlightBox`, `Button`), optional `Filter` (a chip like the sorts, "CONSOLE ONLY"/"MOBILE ONLY", shown only with a pool to filter to) and `Search.Input` (TextBox; matches name, id, region, host), `EdgeFade.List`, text box `Empty`, `Footer` with text boxes `ServerName`, `Meta` and button `Join`
- `Lobby.Background.Bleed` (the open map's `Backdrop` art), `Stage.Status` (text box)
- Scrolling lists sit in an `EdgeFade` CanvasGroup holding a `UIGradient` (the game's trick): the client fades an edge over 36 stage px only while there's more to scroll past it. A list without the group still works, just without fades
- `Lobby.Templates.*` stay `Visible = false` (they'd render otherwise); the client shows its clones
- Map art is shown by [Slideshow.lua](src/Client/Browser/Slideshow.lua): each image is a Decal on a flat part in a ViewportFrame with a moving camera, because GUI images only move in whole pixels and slow pans look choppy. Every image is **1024x576** with its subject in the undarkened centre (about 83% x 78%) and darkened margins to move into; the frame shows the focal area and moves (drift, push-in, skew swing, rise) stay inside the image. Picker cards start at staggered times.
- Map art: one `Images` list per map, cycled on the map view preview and, unless the map has `CardImages`, on the picker card (cropped to its shape). `CardImages` are the card's own art: **756x1024**, full-bleed (no darkened margins), so the card only pushes in and drifts vertically. Prod: Halsey Islands has CardImages, Kin Flats uses its Images for both
- `Templates.MapCard`: `Clip` (the slideshow adds its viewports under `Clip.Fade`), text boxes `Title`, `Online`, bins `Platforms`, `Tags` (optional, filled from `Templates.Tag`: `Label`, `Stroke`), `ComingSoon`, `HighlightBox` (with an optional `HighlightShadow` UIShadow glow the client enables alongside it), `Button`, and an optional game-style button `Play` (ZIndex above `Button`): one tap into this platform's pool where the map has one, Any otherwise; hidden for password maps and blocked platforms
- `Templates.ServerRow` (a GuiButton): text boxes `Server`, `Id`, `Region`, `Uptime`, `Players`; `Stroke`, `HighlightBox`. Don't name a child `Name`: the property hides it
- `Templates.StatItem` (text boxes `Label`, `Value`), `Templates.PlatformChip` (`Icon`, `Label`, `Stroke`), `Templates.Selection` (gamepad selection ring)
- Sounds (in the place, not Rojo): `ReplicatedStorage.Sounds.AmbientLoop` fades in to its own Volume when a player joins, played locally; `Sounds.Interface.Click` (button presses), `MapOpen` / `MapClose` (entering and leaving a map). Missing sounds are silent
- Teleport screen (in the place, not Rojo, optional): `ReplicatedFirst.LoadingGui`, a copy of the game's `GuiMain.LoadingGui` wrapped in a ScreenGui. The client needs `LoadingGui.Logo.ImageLabel`, `Logo.Label.Label` / `LabelBackdrop` and `Loading Shade`. It's registered with `SetTeleportGui` before each Play (and on a VIP forward's `joining`), and fades in over the lobby when the server sends `teleporting` (after `TeleportAsync` returns). The game adopts it on arrival, so keep it matching the game's own copy or the hand-off jumps

Platform support: [Platform.lua](src/Shared/Platform.lua) shows chips for PC / Xbox / PS4 / PS5 / Mobile, and each map's `Platforms` marks some `warn` (notice, still joinable) or `blocked` (red chip and notice, Play/PlayPool/Join hidden, and the lobby server refuses the join with `unsupported`); `PlayStation` in a config means both generations. Roblox can't tell scripts a PS4 from a PS5, so a PlayStation client is detected as `PlayStation` and both chips are outlined. When the generations differ (Beta: PS4 blocked, PS5 fine) it gets an amber "not available on PS4" notice but can still join. Current prod: Beta blocks PS4 and Mobile, Kin supports everything. The client sends the platform it detected with every Play; the lobby can't verify it, so this only stops honest players. The game places should kick unsupported platforms themselves because friend-joins skip the lobby. In Studio, set a `DebugPlatform` attribute on ReplicatedStorage to preview another platform.

Style: match the game's main menu (`ReplicatedStorage.Interface.MainMenu.Master` in the game place; `VIPHome.FreeroamWindow` is the closest reference). Terse: **no helper copy or explanatory labels**.
- Type: Oswald **Heavy** for headers and button text, **SemiBold/Medium Italic** subtext, SourceSansPro Italic for body copy. Headers use spaced capitals, all bone (no accent colours), spaced like the game's `spaceOut`: a **hair space** (U+200A) between every character, never full spaces (the client's `spaced()`, the builder's `spaced()`).
- Colour: bone `229,226,219` text, gold `202,188,131` button stroke and text, panels `27,27,27`, nav bar `18,18,21`; disabled `85,85,85`. Play/PlayPool use a brighter gold `236,210,120`; Join and the card's Play are bone (white) with a bone grunge tint. The client greys buttons out and restores whatever colours they have in the place, so recolour them in Studio.
- Text is drawn twice: a black copy at TextTransparency 0.75 one ZIndex below, offset +4 (big), +2 (subtext) or +1 (small). The picker card's title shadow is heavier (0.5), since the card art runs bright behind it.
- Buttons: black frame at 0.3 transparency, 2px Miter UIStroke, grunge texture `104544475726279` (tiled 1048, 0.7 transparent, tinted), shadow `1677877208` (slice 30, 0.7), HighlightBox `6116907099` (slice 13, +10px) on hover/select, transparent ImageButton on top.
- Floating things (map cards, the preview, buttons, chips, the password field) also get a `UIShadow` named `DropShadow`, offset down so they lift off the background: deep (blur 28, offset 10, 0.4) for cards and the preview, shallow (blur 12, offset 4, 0.55) for the rest. List rows and the panel don't: they sit on it
- List rows: black at 0.7 transparency with a UIGradient fading in from the left, square, 4px gaps.
- **No rounded corners** anywhere; strokes are 2px Miter. Small chips are mini buttons (black 0.3, stroke, no grunge); their HighlightBox uses `SliceScale` ~0.45 so its line lands on the chip's edge instead of inside it.
- Server ids show only the JobId's first group (before the first dash).
- The ScreenGui is full screen (`ScreenInsets = None`, so the background runs under Roblox's top bar). The client scales the 1440x810 Stage to the biggest fit inside the device safe area that stays clear of Roblox's top bar buttons (`GuiService.TopbarInset`): either below the whole bar or beside the buttons at full height, whichever is bigger (phones: beside). Margin is 24px, 8px on screens under 600 tall. Don't use CoreUISafeInsets on the lobby gui: an inset ScreenGui clips its background.
- Controllers use Roblox's **virtual cursor**, like the game: `StarterGui.VirtualCursorMode = Enabled` in the place (Properties panel only; scripts can't read or set it). The client doesn't drive `GuiService.SelectedObject`; hover and click paths serve mouse, touch and cursor alike. Gamepad B closes the map view. Phones are locked to landscape.

---

## How the game side works

The game is the `ApocalypseRising2` repo (branches `production`, `tourney`, `freeroam`; read its CLAUDE.md before touching it). The lobby only talks to it through **DataStores** (the server directory, VIP host records), a little **MemoryStore** (test-lock grants, VIP tickets) and **TeleportService**, never through code sharing.

**Server list.** Each public prod game server runs `src/Server/Browser Beacon.server.lua` (game repo, branch `serverbrowser` until merged). The directory is a **sharded DataStore**, not MemoryStore (MemoryStore budget is saved for other things; the tiny test universe kept running out of it and servers blinked off the list). `BrowserDirectory2` (test: `HubServerDirectory2`) has `DIRECTORY_SHARDS` keys `shard-0..n` (20 prod, 2 test), each `{ v = 1, servers = { [jobId] = entry } }`. A server's shard is `(sum of its JobId's bytes) % shards`. With UpdateAsync each server refreshes its entry (with `updatedAt = os.time()`) about every 60s and on population changes, prunes entries older than `DIRECTORY_STALE` (180s) from its shard, and removes itself in BindToClose. The lobby ignores entries older than 180s: **cold means dead**. One key per server would need a read per server to list them, which prod's server count can't afford. The full spec is at the top of [Protocol.lua](src/Shared/Protocol.lua). Entry:
`{ updatedAt, placeId, jobId, players, maxPlayers, startedAt, placeVersion, region?, kind?, privateServerId? (test only) }`. `region` is the game's own geolocation, `"City - Region"` (e.g. "Ashburn - Virginia"); the lobby shows the part after " - ", cut on a word, and "—" without one. The game writes `kind = "public"` and `region` on branch `serverbrowser` (not merged yet).
`placeVersion` (game.PlaceVersion) shows as "v1234" on each server row and in the footer, in amber when a server is on an older build than the newest one up for that map. The test directory's Hub Beacon doesn't send it yet, so test servers show no version until it does.
It skips Studio, reserved/VIP servers, Ban Land, and every non-prod place, because the game's test server lock wipes public servers on test places.

**Protocol constants.** [src/Shared/Protocol.lua](src/Shared/Protocol.lua) here mirrors the `BROWSER_*` fields in the game's `src/Server/Configs/HubProtocol.lua`. Change both together, and bump `DIRECTORY_VERSION` (and the store name, e.g. `BrowserDirectory3`) for breaking changes. Shard counts must match on both sides.

**Two lobbies, one codebase.** [Catalog.lua](src/Server/Catalog.lua) picks the variant from `game.PlaceId` (Studio: a `LobbyVariant` attribute on ServerStorage, `"test"` or `"prod"`).
- **prod**: the public browser. Maps from [Shared/Maps.lua](src/Shared/Maps.lua), directory `BrowserDirectory2`, public servers.
- **test**: replaces the old *AR2 Development Hub* in its place (9350655892) and keeps its names so test places need no changes: it reads `HubServerDirectory2` (the game's Hub Beacon), writes a single-use grant to `HubTeleportGrants1` before every teleport (the game's Test server lock checks it), and sends TeleportData `{ source = "AR2Hub", v }`. Its maps are the hub's own `ServerStorage.Teleports.Active` config, copied into the place (see "Map config lives in the place").
  - **Access**: group 9630142 role → tier (Tester/Staff/Developer/Public, from the hub's `RoleToAccessRank`), checked on the lobby server. Clients only receive maps their tier can see.
  - **Passwords**: a map's `Password` in its place config module, **never in git** and never sent to a client. Checked server-side, 5 wrong tries a minute.
  - **Single-server lock** (`SingleServer`): everyone goes to one shared reserved server per map so a test can be watched. [Reserved.lua](src/Server/Reserved.lua) uses the hub's DataStore `ReservedServerInfo`, key `"<placeId> - 3"`, so the hub's existing locked servers carry over. Full means full; there's no queue yet.
  - The old hub also wrote a legacy `TestServerWhitelist` DataStore entry and waited 3s; the lobby doesn't. Test places still running the pre-grant lock will kick lobby arrivals.

**Joining.** The lobby calls `TeleportAsync` server-side. With no instance id, Roblox matchmakes into a public server (the one-click card). With `ServerInstanceId`, it joins a specific server from the list. Teleport data is `{ source = "AR2Lobby", v, map, pool? }`. The game doesn't read it yet.

**Platform-only servers** ([Pools.lua](src/Server/Pools.lua)). Three kinds of server: **Any** (the public servers, everyone), **Console** and **Mobile** (only those platforms). Every map that isn't single-server offers the pools its platforms can play (Beta: console only, Mobile is blocked); nothing is configured per map. Console and mobile servers are **reserved servers** in a pool per map and pool, reserved once and reused forever (a reused access code boots a fresh instance), so a pool only grows to its peak concurrent count (`POOL_CAP` 50). All lobby servers share a pool through one lobby-owned DataStore key, `LobbyPlatformPools1["<placeId>:<pool>"]`, read at boot, re-read every `POOL_REFRESH` (300s) and whenever the directory shows a labelled pool server it doesn't know. Codes never leave lobby servers.
- A quick join picks the fullest running pool server with room (directory count + this lobby's sends in the last 90s), else the lowest slot that isn't running (every lobby picks the same one, so they converge), else reserves a new slot. A `GameFull` holds that slot out for 60s and retries once. Joining a listed pool server uses its slot's code.
- The game learns its pool from the first arrival's TeleportData `pool` (safe: only the lobby holds the codes) and should list itself as kind `public` with `pool` and `privateServerId`. The lobby matches entries to slots by `privateServerId`; `pool` only prompts a re-read. Until the game lists them, pool servers work but don't show in the browser. The test directory already lists every server's `privateServerId`, so test pools show without game changes.
- Gating is by the client's reported platform (`Platform.lua` `Pool`): PC gets Any only, and never sees pool servers. Console/mobile see Any plus their own pool, with a filter chip for pool-only.

**Places.** Prod lobby **863266079** (formerly the game's Prod - Main). Test lobby **9350655892** (the old dev hub's place). Beta Map runs on **90014710188160** (production main; test copy 12123099753), Kin Map on **81089296768446** (production retro). The prod map configs are place folders in the lobby place; `Maps.lua` mirrors them as the fallback.

**Universe.** DataStores, MemoryStore and teleports are per-universe. The lobby must be published **inside the same universe** as the game places it lists. [Directory.lua](src/Server/Directory.lua) resolves each map's place with `AssetService:GetGamePlacesAsync()`. A map with no place in the current universe shows as "coming soon". In unpublished Studio (`GameId == 0`) it falls back to each map's first id and serves a fake server list from [Mock.lua](src/Server/Mock.lua), so the UI can be built and demoed. In the published file, tick the **`ServerStorage.ProdDemo`** BoolValue to demo the prod lobby (prod config, fake list, fake pools); Studio only. Teleports there fail straight away with "couldn't join". Once the place is published, Studio reads the real directory.

## Map config lives in the place
Map configs are **ModuleScripts in the lobby place**, not in git and not Rojo-managed (ServerStorage is outside the project tree), read by [PlaceConfig.lua](src/Server/PlaceConfig.lua) when a server starts, so people without the repo can edit them in Studio and publish.

Each variant has its own root, picked by the place id the file is published to, so **one place file carries both configs** and can be published to either lobby without the wrong maps going live: **`ServerStorage.ProdTeleports`** is the prod lobby's and **`ServerStorage.Teleports`** is the test lobby's (the old hub's folder name). Inside either:
- `Active.<Title>`: one ModuleScript per map, named with its title, returning a table shaped like a [Shared/Maps.lua](src/Shared/Maps.lua) entry, plus `Order`, `Access` (list of tiers; missing = everyone), `Password` and `SingleServer`. Images and place ids can be plain numbers. The full list is at the top of PlaceConfig.lua; a module that errors or returns junk is skipped with a warning.
- `Archive`: ignored. `ServerStorage.RoleToAccessRank` (shared ModuleScript): `{ GroupId = 9630142, Roles = { [group role] = tier } }`.

A prod place without `ProdTeleports.Active` falls back to [Shared/Maps.lua](src/Shared/Maps.lua) (its entries go through the same `Normalize`). A test place without `Teleports.Active` has no maps. Config is ServerStorage-only; clients get `PublicInfo` for the maps they may see.

## Paid VIP servers forward to the host's Kin server
The lobby place (863266079) used to be the game's Prod - Main, so hosts' paid VIP servers now boot the lobby. [VipForward.lua](src/Server/VipForward.lua) detects one (`PrivateServerId ~= ""` and `PrivateServerOwnerId ~= 0`, prod variant only), skips the browser, and teleports everyone to **the host's own reserved server on `Protocol.VIP_FORWARD_MAP` (Kin)**, reserved once and reused forever.
- A reserved server has no `PrivateServerOwnerId`, so the lobby records the host in lobby-owned DataStores: `LobbyVipHosts1` (key = reserved PrivateServerId → `{ v, hostId, placeId, createdAt }`, what the game reads to learn its host) and `LobbyVipServers1` (key = `"<placeId>:<hostId>"` → the access code and ids). Both are rewritten on each VIP boot so they self-heal.
- The access code never reaches a client, so the forward is the only way into a host's server; Roblox already limits who can join the paid VIP server. TeleportData `{ source, v, kind = "vip", hostId }` is informational: **the game must take the host from `LobbyVipHosts1`, never TeleportData.**
- The game side is on branch `kinvip` (`globals.getVIPHost()` in the Kin build). It reads `LobbyVipHosts1` **once at boot and caches it**, so the lobby must write the record before the first teleport and never delete it; a server that boots before its record exists runs non-VIP until it shuts down. It only accepts `v == Protocol.VIP_VERSION` (1) and `placeId == game.PlaceId`: change the record's shape on both sides together.
- If setup fails (no Kin place in the universe, DataStore errors after retries) the server falls back to the normal browser. Clients hide the browser while the `VipForward` attribute on ReplicatedStorage is true.
- Studio: a `SimulateVipHost` attribute (a UserId) on ServerStorage fakes a VIP server; unpublished Studio can't reach DataStores, so it falls back to the browser after the retries.

## VIP servers (built, hidden)
Directory entries carry a `kind` (see [Protocol.lua](src/Shared/Protocol.lua)); missing means `"public"`. Lobbies skip kinds they don't handle, and an entry only counts if it comes from a place of that kind (a map's `Vip = { [kind] = placeIds }` in Maps.lua). `Protocol.VIP_LISTING` is **off**: nothing VIP is listed or joinable until the game side exists. In Studio, a `ShowVip` attribute on ServerStorage turns on mock VIP rows.

What "VIP" is in the game, and what the lobby does with it:
- **Freeroam** (the kind that's built): each host has one permanent reserved server on the VIP Freeroam place. The game's Browser Beacon would list it with `kind = "freeroam"`, `hostId`, `locked`, `settings`, and **never** an access code or PrivateServerId. On join, [Vip.lua](src/Server/Vip.lua) pre-checks the lock from the directory entry (only the host gets past it), plus bans and co-hosts from the game's MemoryStore `Freeroam Configs - 4` when there's an entry (60s TTL, written only on setting changes, so usually missing). The freeroam server enforces its lock and bans on arrival, so this is only to spare a wasted teleport. It then reads the access code from the DataStore `Freeroam Servers - 4` (server-side only, cached), writes a single-use ticket to `BrowserTickets1`, and teleports to the VIP place with `ReservedServerAccessCode`. The freeroam server accepts that ticket on arrival (game branches `serverbrowser` + `freeroambrowser`, not merged yet); the lobby never writes the game's own `Freeroam Sessions - 4`. Freeroam `settings` values are strings ("On"/"Off"; TimeOfDayFrozen is a time or "Off").
- **Paid VIP lobbies on Main** (Roblox private servers): strangers can't be teleported into them, so at most listable. Not a kind yet.
- **Tourney matches**: roster-locked per match. Not a kind.

Rows for VIP servers show "VIP · host", LOCKED in amber, and the host's notable settings in the footer; public servers sort first. Access codes and private server ids never reach a client.

## Rate limits: keep it cheap
- DataStore budgets are **per server**: GetAsync and UpdateAsync each get 60 + 10 × players per minute. Per key, writes are capped at 4 MB/min and reads at 25 MB/min, and one server can't write the same key more often than every 6s.
- Game servers write their shard about once a minute, plus population changes debounced to ~30s. That's ≤3 writes/min per server. In prod (~1,000+ servers over 20 shards) that's roughly 1–2 UpdateAsync per second per shard key, each a ~15 KB value, well under the per-key limits. More shards spread writes thinner but cost the lobby more reads per poll.
- Each **lobby server** reads every shard once per 30s (±15% jitter), and only while it has players: 20 GetAsync per poll, 40/min, inside even an empty server's 60/min. It checks `GetRequestBudgetForRequestType` first and skips the poll if the budget is short. A failed shard read reuses that shard's last good copy. A failed poll doubles the interval up to 120s, and players keep the last list. There's **no refresh button**: lists update on their own. It sends each player their visible maps and servers over one RemoteEvent (one FireClient each, no extra reads). **Clients never read the directory**, and nothing should poll per player.
- Up to 50 servers per map go to the client, sorted with non-full first, then by player count, plus up to 50 per pool.
- Pools cost one GetAsync per (map, pool) at boot and every 5 minutes, from whatever budget a poll leaves. A join costs no DataStore calls unless the pool has to grow (a GetAsync, a `ReserveServer` and an UpdateAsync, once per new slot ever). No MemoryStore.
- No MessagingService in the browser path. If you add push updates later, measure the per-topic limits against prod server counts first.

## Game data
Longer term the lobby may mirror the game's shop and character creator, which means reading the game's SaveData stores. That work has **not** started. The game's persistence layer (`src/Server/Libraries/SaveData.lua` in the game repo) is sensitive and has a time-based session lock, so any lobby access to player data needs an explicit plan agreed with the owner first. The lobby must never write to game stores.

## Roblox Studio MCP
Same rules as the game repo. Code goes through Rojo, never the MCP. Reading the tree and instances is fine. **Every write, including `execute_luau`, needs an explicit yes per action.** Never start Play or a test session; say what to test and stop.

## Git
- Single `main` branch at github.com/LiamHutch/AR2-Lobby. Short lower-case commit messages.
- Commit when asked; show the diff and get a yes before pushing.
- Never commit `.rbxl`/`.rbxlx` or `sourcemap.json`.
