# Lakon — design

Lakon is an RPG Maker MZ-style game maker that runs only on macOS. It uses Swift 6.3 (Swift 5 language mode),
SwiftUI with AppKit for the editor, and SpriteKit for the player. It needs macOS 14 or later and has no third-party dependencies.

## What maps to what

| RPG Maker MZ | Lakon |
|---|---|
| Native editor | SwiftUI app (`Sources/Lakon`): palette, map canvas (NSView), map tree, event editor, database |
| `data/*.json` | Same file names and field names (`Sources/LakonCore/Models.swift`). Lenient decoding, so MZ/MV files load |
| `Game_*` objects (rmmz_objects.js) | `LakonCore`: `GameWorld`, `GameCharacter/GamePlayer/GameEvent`, `Interpreter`, `GameState` |
| `Tilemap` (rmmz_core.js) | `LakonRender.TileRenderer`, which uses the same tile-ID maths and autotile tables |
| Pixi + NW.js player | SpriteKit `GameScene` at 816×624 with a fixed 60 Hz step |
| Deployment (web/desktop) | **Export as Mac App**: copies Lakon's own binary into `<Title>.app`, adds the project under `Resources/Game`, and ad-hoc signs it |
| RTP graphics | Procedural art in MZ's sheet layouts (`DefaultArt.swift`). MZ-format PNGs from users or imports work unchanged |

## Decisions

- **Same data schema, not a new one.** Tile IDs, autotile shapes, the 6-layer `data[]` array, `{code, indent, parameters}`
  commands and 1-based arrays all match MZ. This is why an MZ project can be imported and look right on the first
  run. See EVIDENCE.md for the real-project check.
- **The simulation has no rendering code.** `GameWorld.update(InputState)` is the whole game step, so the
  event system is unit-tested without a window (`swift test`). SpriteKit only reads state, the same way MZ
  splits `Game_*` from `Sprite_*`.
- **Autotile shapes come from table lookup.** Each quarter-tile piece is derived from the neighbours, then
  `floorTable.firstIndex(of:)` turns that into a shape ID. This guarantees the result is a valid MZ shape and needs no second
  hand-written table. A test checks that all 256 neighbour masks produce all 47 edge shapes.
- **Unknown command codes are skipped, as in MZ.** Imported events with battles, shops, audio or plugin
  commands still run their supported parts. The editor marks those lines "imported, not executed by Lakon".
- **Import never writes to the source.** `Project.importMZ` copies into a new folder. Lakon also writes only the fields
  it models, so saving over an MZ project would drop fields such as BGM and encounters.
- **Pressing OK to close a message is consumed.** MZ keeps the message "busy" while it closes. Lakon marks the frame's
  input as used, so the same keypress can't re-trigger the event you just finished talking to (a test covers this).
- **New events are drafts.** An event is added to the map only when you press OK in the event editor, as in MZ.
- **Fixed-step loop with clamped deltas.** `GameScene.update` collects real time into 1/60 s steps and ignores negative or
  oversized deltas. That keeps ProMotion (120 Hz) displays at the right speed.

## Implemented

**Editor:** maps (create, properties/resize, delete, tree). Map properties include BGM/BGS autoplay, battlebacks and an encounter list with weights and regions. The A–E palette supports rectangular multi-tile brushes, with pencil, rectangle, flood fill and eraser tools, MZ-style auto-layering, autotile reshaping, region painting, an option-click eyedropper and 100-step undo/redo. Event mode covers pages, all six condition types, an image picker, movement, options, priority and trigger. There are quick Treasure and Transfer events and a start position.
- **Command list:** insert, edit and block-aware delete, with forms for about 65 commands.
- **Database:** actors (class, initial equipment, traits), classes (EXP curve, parameter curves, learnings, traits), skills and items (scope, occasion, hit type, damage formula, effects, icon), weapons and armors (types, parameters, traits), enemies (parameters, drops, action patterns, traits, battler preview), troops (drag-to-place layout on the battleback, pages with turn/HP/switch conditions and their own command list), states (restriction, removal timing, messages, traits), tilesets (○ × ☆ passage), common events, system, and audio & vehicles (music, the 24 system sounds with preview, boat/ship/airship).
- **Other:** playtest (⌘R) and Export as Mac App (⌘E).

**Runtime (ports of MZ's rmmz_objects.js behaviour):**
- **Map:** walking and dashing (Shift), followers, the 5 triggers, 3 priorities, page switching, self switches, autorun and parallel events (map and common), and random/approach/custom movement with the full move-route set. Terrain flags are honoured: bush (half-transparent legs), counter (talk across), damage floor and ladder. Balloons, generic animation bursts and A1 tile animation (water) all work.
- **Battle:** front view with battlebacks, enemy sprites, a battle log, party and actor commands, skill and item lists and target selection. MZ's damage formula pipeline runs on JavaScriptCore (element rate, pdr/mdr, rec, critical ×3, variance, guard). Hit and evasion use the hit/eva/mev x-params. States cover restriction, auto-removal timing and removal by damage. Buffs, TP, enemy action patterns with conditions and rating, troop events (turn, turn end, HP and switch conditions; battle, turn or moment span) and escape ratio all work. Rewards give EXP (MZ's EXP curve), gold and drops, with level-ups and learned skills. Battle Processing supports Win/Escape/Lose branches. Random encounters use step counts, weights and regions, with preemptive and surprise rolls.
- **Menus:** Item, Skill (with targets), Equip (with parameter preview), Status, Options (volumes), Save/Load (4 slots with info), Game End, and a title screen with Continue/Options.
- **Shop:** buy and sell with quantity, possession count and an equipment comparison per member.
- **Message:** `\V \N \P \G \C[n] \I[n]`, faces, speaker name, choices, Input Number, Select Item, scrolling text and Name Input.
- **Screen:** tint (including gray), flash, shake, rain/storm/snow weather, and pictures (show, move with MZ easing, rotate, tint, erase, blend modes).
- **Audio:** BGM, BGS, ME and SE on AVAudioEngine with pitch, pan and fades. ME interrupts and then resumes the BGM. Ogg Vorbis goes through the vendored public-domain stb_vorbis decoder, which honours `LOOPSTART`/`LOOPLENGTH`. WAV, M4A and MP3 go through AVFoundation.
- **Vehicles:** boat (flag 0x200), ship (0x400) and airship (lands where 0x800 is clear). You board and alight with the action button, and each vehicle has its own BGM.
- **Scripts and plugins:** Script (355/655), script conditions, script variable operands, move-route scripts and damage formulas all run on macOS JavaScriptCore. They see an MZ-shaped API: `$gameVariables`, `$gameSwitches`, `$gameSelfSwitches`, `$gameParty`, `$gameActors`, `$gamePlayer`, `$gameMap`, `$gameMessage`, `$gameScreen`, `$gameTemp`, `AudioManager` and `$data*`. Plugins live in `plugins/*.js`, with `plugins/plugins.json` using MZ's `$plugins` shape. `PluginManager.registerCommand` serves Plugin Command (357), and `Lakon.on("mapStart"|"update"|"battleStart"|"battleEnd")` provides hooks.
- **Commands executed:** 101–105, 108, 111–117, 121–136, 201–206, 211–217, 221–225, 230–236, 241–251, 282–285, 301–303, 311–326, 331–342, 351–357, plus 401/402/403/404/405/408/411/412/413/601–605/655.

## Not implemented (versus MZ)

- **Side-view battle and real battle animations:** MZ draws Effekseer particle effects, Lakon shows a generic burst.
- **Rendering extras:** parallax backgrounds and the shadow pen.
- **Movies:** Play Movie (261) does nothing.
- **Text codes:** `\{` and `\}` font size changes are ignored.
- **TP mode:** TP is always on.
- **Party menu:** no Formation command.
- **Battle tests:** the database can't launch a test battle.
- **MZ plugins** that patch `Scene_`/`Window_`/`Sprite_` classes can't run, because there's no PixiJS runtime to patch. Plugins that only use the exposed `$game*` API and `PluginManager.registerCommand` do run.

## Verification

- **`swift test`:** 25 tests. Two cover the earlier tile and world behaviour, `SystemsTests` covers the newer systems, and one runs a real MZ project when `LAKON_MZ_FIXTURE` is set.
  - `SystemsTests` asserts MZ's damage formula and EXP curve values, a full battle won with rewards and the If Win branch, escape/guard/skills, losing with Continue When Loss, random encounters, shop buy/sell/equip, menu item and skill use, script command and condition plus a plugin command from `plugins/LakonDemo.js`, ship boarding/sailing/landing, pictures/tint/weather persisting through save, number and name input, and followers and actor save round-trips.
  - The MZ fixture run loads every map and all battle data from a real MZ project and simulates 1,200 frames.
- **`Lakon --decode-audio file.ogg`:** a real MZ BGM (`Theme4.ogg`) decodes as 44.1 kHz stereo, 88 s, with its `LOOPSTART`/`LOOPLENGTH` read.
- **Game smoke run:** `LAKON_SMOKE_PROJECT=<dir> LAKON_SMOKE_OUT=<dir> Lakon` drives the real app with frame-exact input. It covers the intro picture, name input, a balloon, dialogue, menus (items, equip, status), the shop, a battle (target select, skills, victory), the world map with rain, ship boarding and sailing, and a screen tint, with a snapshot at each step. A 60 Hz timer drives the scene, because SKView's display link stops when the display sleeps.
- **Editor smoke run:** `LAKON_SMOKE_EDITOR_ONLY=1 …` opens the database tabs. With Screen Recording allowed for the terminal, the editor's real window, including native toolbar and form controls, was captured and checked (`docs/images/editor.png`, `db-*.png`).
