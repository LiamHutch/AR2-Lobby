# AR2 Lobby

Lobby and server browser for Apocalypse Rising 2. Press play, pick a map, and you're in. Or open a map's server list and join a specific server.

## Setup
1. `aftman install`, then `rojo plugin install` (Rojo 7.7.0, same as the game).
2. Open the lobby place in Studio and `rojo serve`.
3. First time only: paste [tools/build-ui.lua](tools/build-ui.lua) into the command bar to build `ReplicatedFirst.Lobby`.

## Adding a map
Add an entry to [src/Shared/Maps.lua](src/Shared/Maps.lua) with its name, accent colour, flavour text, stats, platform support, up to 6 preview images, and every place id (prod and test) that runs it. The game place also needs the browser beacon, which it gets once its id is in the game's `isProdPlace` list.

## How servers get listed
Public prod game servers write a small heartbeat to MemoryStore (`BrowserDirectory1`). Each lobby server reads it every 15s and sends it to its players. Details, limits, and the UI contract are in [CLAUDE.md](CLAUDE.md).

## Publishing
The lobby has to live in the **same universe** as the game places it lists. Otherwise it can't see their servers or teleport into them.
