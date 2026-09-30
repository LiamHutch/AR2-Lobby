# AR2 Lobby

Lobby and server browser for Apocalypse Rising 2. Press play, pick a map, and you're in. Or open a map's server list and join a specific server.

## Setup
1. `aftman install`, then `rojo plugin install` (Rojo 7.7.0, same as the game).
2. Open the lobby place in Studio and `rojo serve`.
3. First time only: paste [tools/build-ui.lua](tools/build-ui.lua) into the command bar to build `ReplicatedFirst.Lobby`.

## Adding or editing a map
Maps are configured **in the place**, no repo needed: in Studio, add or edit a Folder under `ServerStorage.Teleports.Active` (one per map, named with the map's title) and publish. The fields are listed at the top of [PlaceConfig.lua](src/Server/PlaceConfig.lua); it's the same layout the old dev hub used. Changes apply to lobby servers started after publishing.

A prod place with no config uses [src/Shared/Maps.lua](src/Shared/Maps.lua); paste [tools/maps-to-folders.lua](tools/maps-to-folders.lua) into the command bar to turn it into folders. The game place also needs the browser beacon, which it gets once its id is in the game's `isProdPlace` list.

## How servers get listed
Public prod game servers write a small heartbeat to MemoryStore (`BrowserDirectory1`). Each lobby server reads it every 15s and sends it to its players. Details, limits, and the UI contract are in [CLAUDE.md](CLAUDE.md).

## Publishing
The lobby has to live in the **same universe** as the game places it lists. Otherwise it can't see their servers or teleport into them.
