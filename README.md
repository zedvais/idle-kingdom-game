# Idle Kingdom

A medieval idle game for Roblox. Grow one farm into a realm by earning gold,
hiring stewards and conquering neighboring lands.

## How the project is laid out

| Folder | Where it ends up in Roblox Studio | What goes in it |
| --- | --- | --- |
| `src/server` | ServerScriptService > Server | Game logic that runs on the server |
| `src/client` | StarterPlayer > StarterPlayerScripts > Client | UI and anything the player sees |
| `src/shared` | ReplicatedStorage > Shared | Settings and code both sides use |

`default.project.json` tells [Rojo](https://rojo.space) how to turn these
folders into a Roblox place.

## Trying the game

The quick way needs no tools: open the latest `IdleKingdom.rbxlx` place file
in Roblox Studio and press Play.

## Building the place file yourself

1. Install Rojo 7 (see the [install guide](https://rojo.space/docs/v7/getting-started/installation/)).
2. In this folder, run:

   ```
   rojo build -o IdleKingdom.rbxlx
   ```

3. Open `IdleKingdom.rbxlx` in Roblox Studio.

## Live syncing while editing code

1. Install the Rojo plugin in Roblox Studio (same install guide as above).
2. Run `rojo serve` in this folder.
3. In Studio, open the Rojo plugin and press Connect. Edits to files in `src`
   now show up in Studio right away.
