# Idle Kingdom

A medieval menu game for Roblox. Spend energy on quests to earn gold and
experience, level up, buy holdings that pay every hour, build a warband,
and bring down foes. There is no character to control: the whole game is
played through menus.

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

## Selling items for Robux

Everything sold in the Shop and the Royal Pass is set in
`src/shared/StoreConfig.luau`. Each game pass and developer product there has
an `id` of 0 until the game is published. In Roblox Studio, pressing a Robux
button for an item with id 0 gives it for free so it can be tested. Once the
game is published, create the passes and products on create.roblox.com
(your game > Monetization), paste their ids into `StoreConfig.luau`, and
rebuild the place file. The steps are written at the top of that file.

## Promo codes, news letters and rankings

`src/shared/ProfileConfig.luau` holds:

- **Codes:** each has a code, an end time (0 for never) and rewards. Players
  type codes on the Profile page and each works once per player.
- **News:** letters every player gets once, the next time they join. Add one
  to announce an update or hand out a gift. Never reuse an id.
- **Boards:** the all-time rankings. They use Roblox DataStores, so in Studio
  they only work with *Enable Studio Access to API Services* turned on
  (Game Settings > Security), and only once the game is published.

Rebirth numbers are in `RebirthConfig.luau` and the Relic Hall in
`RelicConfig.luau`.
