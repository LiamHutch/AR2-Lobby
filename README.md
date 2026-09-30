# AR2 Lobby

Lobby and server browser for Apocalypse Rising 2. Press play, pick a map, and you're in. Or open a map's server list and join a specific server.

## Setup
1. `aftman install`, then `rojo plugin install` (Rojo 7.7.0, same as the game).
2. Open the lobby place in Studio and `rojo serve`.
3. First time only: paste [tools/build-ui.lua](tools/build-ui.lua) into the command bar to build `ReplicatedFirst.Lobby`.

## Adding or editing a map
Maps are configured **in the place**, no repo needed: in Studio, add or edit a ModuleScript under `ServerStorage.ProdTeleports.Active` (prod lobby) or `ServerStorage.Teleports.Active` (test lobby), one per map, named with the map's title, and publish. Each lobby only reads its own folder (picked by the place id it's published to), so one place file holds both. A module returns a table like an entry in [src/Shared/Maps.lua](src/Shared/Maps.lua); the fields are listed at the top of [PlaceConfig.lua](src/Server/PlaceConfig.lua). Changes apply to lobby servers started after publishing.

A prod place with no config uses [src/Shared/Maps.lua](src/Shared/Maps.lua). The game place also needs the browser beacon, which it gets once its id is in the game's `isProdPlace` list.

## How servers get listed
Game servers keep a heartbeat entry in a sharded DataStore directory (`BrowserDirectory2`; test: `HubServerDirectory2`), and an entry that stops refreshing counts as a dead server. Each lobby server reads it every 30s and sends it to its players. Details, limits, and the UI contract are in [CLAUDE.md](CLAUDE.md).

## Publishing
The lobby has to live in the **same universe** as the game places it lists. Otherwise it can't see their servers or teleport into them.
