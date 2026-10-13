# Lakon

A native **macOS** RPG maker, modelled on how RPG Maker MZ works. You paint tile maps, script events with
MZ's page/condition/command model, edit a database, playtest, and export a standalone `.app` or an HTML5 build for itch.io.

![editor](docs/images/editor.png)

| Intro picture | Name input | Dialogue |
|---|---|---|
| ![](docs/images/04-intro-picture.png) | ![](docs/images/05-name-input.png) | ![](docs/images/07-dialogue.png) |
| **Side-view battle** | **Skills** | **Shop** |
| ![](docs/images/21-sideview-battle.png) | ![](docs/images/15-battle-skills.png) | ![](docs/images/12-shop.png) |
| **Parallax (Sky Ledge)** | **Show Animation** | **Change Parallax** |
| ![](docs/images/22-sky-parallax.png) | ![](docs/images/23-map-animation.png) | ![](docs/images/24-change-parallax.png) |
| **Web build: battle animation** | **Web build: Sky Ledge** | **Animations tab** |
| ![](docs/images/web-battle.png) | ![](docs/images/web-starlit.png) | ![](docs/images/db-animations.png) |
| **Menu** | **Equip** | **World: rain + ship + airship** |
| ![](docs/images/08-menu.png) | ![](docs/images/10-menu-equip.png) | ![](docs/images/19-ship.png) |

Database: ![](docs/images/db-skills.png)

- **How MZ works, with source citations:** [docs/EVIDENCE.md](docs/EVIDENCE.md)
- **Architecture, decisions, scope:** [docs/DESIGN.md](docs/DESIGN.md)

## Build & run

```bash
scripts/build-app.sh          # → build/Lakon.app (release, ad-hoc signed)
open build/Lakon.app
swift test                    # 34 tests (tiles, events, battle, side view, animations, parallax, shop, scripts, vehicles, save/load, web parity)
scripts/web-check.sh          # export the demo for the web and play it in headless Chrome
```

Requires macOS 14+ and Xcode 16+ (Swift 6 toolchain). The web parity tests and `web-check.sh` also need Node 20+ (and Chrome for the latter).

## Using it

- **New Project…** creates a demo with synthesised music and sounds, a full database and four maps. The village has a shop, an inn, a guessing game, a chest and a boat. In the house a second hero joins. The world map has random encounters, rain, a ship, an airship, a campfire driven by a plugin command, and a boss battle.
  Through the gap in the trees north of the village is Sky Ledge, a path over a scrolling sky (parallax) with a Wind Spirit
  (Show Animation) and a chest that switches the sky to stars (Change Parallax). Battles are side view; switch it off in Database ▸ System.
  Press **⌘R** to play it. Controls: arrows move, Z/Enter/Space to confirm, X/Esc for the menu.
- **Map mode (⌘1):** choose a tile in the palette and drag across it for a multi-tile brush. Option-click the map to pick up a tile.
- **Event mode (⌘2):** double-click a cell to create or edit an event. Drag events to move them. Right-click for quick
  events and to set the starting position.
- **Region mode (⌘3):** paint region IDs.
- **Database (⌘D):** actors (with side-view battler), classes, skills, items, weapons, armors, enemies, troops (drag-to-place), states (with side-view motion and overlay), animations (MV cells or Effekseer, with preview), tilesets (○ × ☆), common events, system (side-view toggle), audio & vehicles.
- **Map properties:** BGM/BGS autoplay, parallax (loop and scroll), battlebacks, random encounters (troop, weight, regions).
- **Import RPG Maker MZ Project…:** copies an MZ/MV project's `data/` and `img/` into a new Lakon project. The source is never modified.
- **Export as Mac App (⌘E):** produces `<Title>.app`, which boots straight into the game.
- **Export for Web (itch.io) (⇧⌘E):** produces `<Title>-web/` and `<Title>-web.zip`. Upload the zip to itch.io as an HTML game
  (816 × 624 viewport). It runs Lakon's own JavaScript runtime, converts `.ogg` to `.m4a` with loop points kept, and plays
  imported MZ Effekseer effects with the bundled Effekseer for WebGL (MIT). Saves go to the browser's localStorage. To try it
  locally, serve the folder (`python3 -m http.server`); opened as a file it still runs, but audio falls back to plain `<audio>` without loop points.

Your own assets work if they use MZ's layouts: `img/tilesets`, `img/characters`, `img/faces`, `img/enemies`, `img/sv_actors`, `img/sv_enemies`, `img/animations`, `img/parallaxes`, `img/battlebacks1/2`, `img/pictures`, `img/system/IconSet.png` (plus `Weapons1-3`, `States`, `Shadow2` for side view), `effects/*.efkefc`, and `audio/{bgm,bgs,me,se}` (`.ogg` with loop tags, `.wav`, `.m4a`, `.mp3`). Scripts and plugins are JavaScript: see `plugins/LakonDemo.js` in a new project.

## CLI helpers

```bash
Lakon --make-sample <dir>                 # create the demo project
Lakon --import <mzProject> <dir>          # import an MZ project
Lakon --render-map <project> <id> <png>   # render a map to PNG
Lakon --export <project> <outDir>         # build a standalone game .app
Lakon --export-web <project> <outDir>     # HTML5 build for itch.io (folder + zip)
Lakon --sim <project> <script.json> <out> # headless scripted run, one snapshot per frame (compare: node web/sim.js …)
Lakon --decode-audio <file.ogg>           # check audio decoding / loop tags
```
