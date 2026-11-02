# Developing Mt. Crankmore

How the game is put together, how to run and test it, how the art is made, and how a release is cut. For playing the game see the [README](../README.md); for how rivals, races and challenges are balanced against your FTP see the [difficulty page](https://hermeslohin.github.io/mt-crankmore/difficulty.html) (`docs/difficulty.html`).

- [Requirements](#requirements)
- [Running the game](#running-the-game)
- [Project layout](#project-layout)
- [Debug modes](#debug-modes)
- [Testing changes](#testing-changes)
- [Race simulator](#race-simulator)
- [Art pipeline](#art-pipeline)
- [The trainer bridge](#the-trainer-bridge)
- [Saves and user data](#saves-and-user-data)
- [Strava](#strava)
- [Releasing](#releasing)
- [The website](#the-website)

## Requirements

- **Godot 4.7** (the project is on 4.7.2). To export builds, also the 4.7 export templates for Windows, Linux and macOS.
- **Python 3** for the trainer bridge (`bridge/`), the race simulator and the PixelLab scripts.
- A **PixelLab** account for new art (see [Art pipeline](#art-pipeline)). Keep the API key out of the repo.

## Running the game

```sh
godot --path .            # or open the folder in the Godot editor and press F5
```

The game renders at 640x360 and scales up in whole pixels (2x in the default 1280x720 window). Useful extras:

| | |
|---|---|
| `PIZZA_NO_SAVE=1` | Never write the save file. Use it for every test and screenshot run. |
| `--headless` | No window: for checking scripts and running logic. Nothing is drawn, so anything that waits for a frame to be drawn (`await RenderingServer.frame_post_draw`, the screenshot modes) waits forever. |
| `--resolution 1280x720` | A fixed window size, so screenshots come out the same every time. |
| `--fixed-fps 10` | Steps the game in fixed 0.1 s ticks as fast as the machine can go (the race simulator uses it). |

Headless runs print a lot of harmless `keyboard_get_label_from_physical` errors; filter them out.

## Project layout

```
scenes/main.tscn     the one scene: Main, with the city, the race and the HUD under it
scripts/             all the game code (below)
art/                 the packed pictures the game loads (sheets, strips, single images)
sprites/             the PixelLab exports the art is packed from (ignored by Godot, see sprites/README.md)
bridge/              the Bluetooth / Wi-Fi trainer helper (Python)
tools/               packers, the race simulator, the sprite viewer and other dev tools
docs/                the website (GitHub Pages) and this document
dist/                exported builds (not committed)
```

### Autoloads

Global objects Godot creates at start-up (`project.godot`, `[autoload]`):

| Name | Script | What it holds |
|---|---|---|
| `Controls` | `controls.gd` | Key and handlebar-button bindings for every action |
| `Season` | `season.gd` | The current season ("auto" follows the date) |
| `Game` | `game.gd` | Money, garage and bikes, rider settings (FTP, weight, difficulty, rivals), the physics helpers, save and load |
| `Trainer` | `trainer_link.gd` | The link to the trainer bridge: power, cadence, heart rate, gears, controller buttons |
| `Talk` | `trash_talk.gd` | The rival roster and their trash talk |
| `Ride` | `ride_log.gd` | The session being recorded for Strava |
| `Strava` | `strava.gd` | Linking a Strava account and posting rides |
| `Skies` | `sky.gd` | Time of day and weather |

### Scripts

| Script | |
|---|---|
| `main.gd` | Scene manager: title, town, races and the menus between them; all the `PIZZA_DEBUG` modes |
| `city.gd` | Crankmore Village: roads, buildings, traffic, rivals, orders and the paid challenges |
| `town_events.gd`, `town_happenings.gd` | Random happenings round town (parades, robberies, seagulls, zombie kids...) |
| `race.gd` | A race: the course, riders, drafting and attacks, the Crusty Crit loop, the Velodoughm |
| `race_life.gd` | Race-day dressing: crowds, marshals, the TV moto, helicopters |
| `hud.gd` | HUD, the WEEHOO bike computer, toasts, chat feed and every menu |
| `session_chart.gd` | The Session over timeline |
| `sprites.gd` | Loading and drawing sprite sheets: riders, people, vehicles, animals, turning |
| `bike_draw.gd` | Draws a rider: shadow, sprite, the steam off a hot pizza |
| `iso.gd` | Isometric helpers: world tiles to screen |
| `ground.gd`, `flora.gd`, `weather.gd`, `night.gd`, `sky_fx.gd` | Ground textures, plants, falling snow and leaves, the dark, fireworks |
| `powerups.gd` | Power-ups and their effects |
| `med_heli.gd`, `news_heli.gd` | The air ambulance and the news helicopter |
| `trainer_link.gd`, `controls.gd` | Trainer link, input bindings |
| `ride_log.gd`, `strava.gd` | Ride recording and the Strava upload |

## Debug modes

Set `PIZZA_DEBUG` to start straight into something. Most of them quit by themselves when they're done.

| `PIZZA_DEBUG=` | What it does |
|---|---|
| `city` | Starts a game and rides with W held. Add `PIZZA_POPS=<frames>` to report anything that pops in or out of sight (`tools/pop_watch.gd`; `PIZZA_POPS_EVENTS=1` sets off a happening every 15 s). |
| `city_fast` | The same at 15x speed, steering right. |
| `race` | Starts the Summit race with W held. |
| `race_fast` | Starts race `PIZZA_COURSE` (0 Foothill, 1 Summit, 2 Flour Run, 3 Crusty Crit, 4 Velodoughm) at 40x. `PIZZA_PELOTON=1` prints where every rival is every 20 s and the result. |
| `shop` | Opens the bike shop with $3000. |
| `er` | Gets hit by a car and wakes up in hospital. |
| `shot` | Screenshots in town to `PIZZA_OUT`: `PIZZA_SHOTS=<n>` one a second, or `PIZZA_AT=x,y;...` / `junctions` / `shops` / `er` / `townhall` / `nineties` / `edges` for set spots. `PIZZA_CARRY=1` carries a pizza, `PIZZA_SHIFT=1` shifts up before each shot. |
| `race_shot` | Race screenshots at the first jump, log, creek and wildlife (`PIZZA_COURSE`, `PIZZA_OUT`). |
| `readme` | Regenerates the README screenshots in `docs/`. |
| `session` | Fakes a 40-minute session and saves the Session over screen (`PIZZA_TRAINER=0` without power, `PIZZA_HR=0` without heart rate). |
| `ride` | Rides a few seconds and writes the Strava TCX file. |
| `events` | Sets off every town happening next to you and screenshots each (`PIZZA_EVENTS=a,b` for just those). |
| `eventviewer` | The event viewer (also `tools/event_viewer.sh`): step through happenings with ] / [ and R. |
| `powerups`, `wipeout`, `animals` | Screenshots of every power-up, the wipe-out animations, every race animal. |
| `seasons` | The title view and each season's scenery, in every season. |
| `buildings`, `roads` | Counts buildings by kind and size; checks the road network for dead ends and unreachable roads. |
| `flow`, `rails`, `latch` | Headless checks of the order loop, riding on rails through junctions, and a single tap choosing a turn. |
| `trainer`, `link`, `gears` | Drives the Connect Trainer screen, the bridge link and the gear shifting headlessly. |
| `overview` | The town map without the title menu (`PIZZA_ZOOM` to zoom out). |

Other switches: `PIZZA_SEASON=spring|summer|fall|winter`, `PIZZA_TIME=<hour>` (holds the clock), `PIZZA_WEATHER=rain|snow|clear`, `PIZZA_FPS=1` (prints the frame rate), `PIZZA_TS=<time scale>` and `PIZZA_FRAMES=<n>` for the modes that take them.

## Testing changes

There are no unit tests; changes are checked by running the game:

1. **Scripts compile and run:** `PIZZA_NO_SAVE=1 PIZZA_DEBUG=city timeout 60 godot --headless --path .` and look for `SCRIPT ERROR` or `Parse Error`.
2. **Look at it:** a `shot` or `race_shot` mode with a window (`--resolution 1280x720`), then open the PNGs.
3. **Small throwaway scripts** for anything specific: an `extends SceneTree` script that instantiates `res://scenes/main.tscn`, calls `main._start_game()` or `main._start_race(i)` and pokes at `main.city` / `main.race`, run with `godot --headless --path . -s <script>`. `tools/race_sim.gd` is a worked example.

Scripts run with `-s` are compiled before the autoloads exist, so code that a tool script uses (like `sprites.gd`) shouldn't name an autoload such as `Game` directly: look it up at run time (`get_tree().root.get_node_or_null("Game")`).

## Race simulator

`tools/race_sim.py` finds the steady power it takes to win each race. It runs `tools/race_sim.gd` (one headless race, you holding a fixed wattage on a pretend trainer) for every combination you ask for, in parallel, saves each result as it comes in, and prints the lowest wattage that won every run.

```sh
python3 tools/race_sim.py --ftp 200 --weight-lb 175 --bike 3 --difficulty easy,hard \
    --watts 100:250:10 --seeds 1,2,3 --champion --out sims.txt
python3 tools/race_sim.py --summarize sims.txt
```

`--bike` is the bike's place in `Game.bikes` (0 Rusty Trash Bike ... 3 Carbon Crit Machine ... 7 Champion's Bike). A road race takes 1 to 5 minutes of CPU per run and a crit several, so sweep coarsely first (one seed, 10 to 20 W steps) and then narrow down with more seeds. The numbers on the difficulty page come from this.

## Art pipeline

Nearly all the art is pixel art made with [PixelLab](https://www.pixellab.ai) through its API (`https://api.pixellab.ai/v2`, a bearer key kept outside the repo). The exports live in `sprites/` (see `sprites/README.md` for every character and its PixelLab ids), and the game loads packed pictures from `art/`.

### Riders

A rider is a set of sheets named `bike_<rider>*.png`: 8 rows of directions (down-right, down, down-left, left, up-left, up, up-right, right), one column per animation frame, 80 px square frames, the wheels touching the ground 12 px above the bottom centre.

| Sheet | Look |
|---|---|
| `bike_<rider>.png` | Plain bike (races) |
| `bike_<rider>_boxed.png` | With the delivery bag or box (town) |
| `bike_<rider>_pizza.png` | Carrying a pizza |
| `..._fall*.png` | The same three wiping out (frame 0 is the riding pose) |
| `..._throw.png`, `..._throw_boxed.png` | Flinging a pizza frisbee |
| `..._turn.png` | In-between frames for turning (4 per pair of neighbouring rows) |
| `winter_...` | The same in winter clothes |

The player's sheets are `bike_rookie_boy*` and `bike_rookie_girl*`; with a bike of its own art they're `bike_rookie_<boy|girl>_<art>*`, where `<art>` is the bike's `"art"` in `Game.bikes` (`rusty`, `commuter`, `gravel`, `carbon`, `golden`, `fixie`, `hoofy`, `champion`). A missing sheet falls back: pizza to bag to plain, a bike's own sheets to the plain ones, a missing turn sheet to a cross-fade.

To make a rider in PixelLab:

1. Create the character (8 directions, 48 px, high top-down view), or make a **state** of an existing one with `create-character-state` and an edit description ("replace only the bicycle with...", "add a red delivery box...", "dress the rider for winter...") so it stays the same person.
2. Animate each state in all 8 directions with `characters/animations` (`mode: "v3"`): `pedaling` (8 frames), `fall` (12 frames plus the start pose: 13), and for throws `throw` (8 plus the start pose: 9). Describe the rider as alone, or PixelLab draws other people and bikes into the frames.
3. Download the frames (check every one is really a PNG: the file server sometimes answers with an error message instead) into `<export>/<State>/rotations/<dir>.png` and `<export>/<State>/animations/<anim>/<dir>/frame_NNN.png`.
4. Pack them:

```sh
godot --headless --path . -s tools/import_rider.gd -- <export> \
    rows=south-east,south,south-west,west,north-west,north,north-east,east \
    anim=pedaling Plain=bike_rookie_boy_rusty Bag=bike_rookie_boy_rusty_boxed Pizza=bike_rookie_boy_rusty_pizza
```

`rows=` picks the export direction for each sheet row (the line above is right for the Rookie Boy and Girl exports); `anim=` which animation to pack.

### Everything else

`tools/import_sprite.gd` packs everything that isn't a rider:

| Mode | For |
|---|---|
| `strip <dir> <direction> <anim> <out> [anchor=feet\|center]` | One row of frames: a baker's dance, the Velodoughm's waving flag |
| `people <dir> <anim\|still> <out>` | A person walking in 8 directions (west mirrored from east and so on) |
| `vehicle <dir> <anim> <out>` | A vehicle driving, 8 directions |
| `rotations <dir> <out>` | 8 stills, one per direction |

`tools/trim_images.gd` crops single pictures into `art/` so their bottom edge is where they stand, and `tools/recolor_vehicle.gd` makes the colour variants of the cars. After adding art, run `godot --headless --path . --import` so exported builds include it, and `godot --headless -s tools/build_sprite_viewer.gd` to refresh the sprite viewer (`tools/sprite_viewer/index.html`, open it in a browser).

## The trainer bridge

Godot can't talk Bluetooth, so `bridge/trainer_bridge.py` does and relays over localhost UDP. The game installs it into a private Python environment (`bridge/.venv`, or `user://bridge` in an exported build), starts it in `--managed` mode and tells it what to scan for and connect.

- **Bridge to game** (UDP 9871): `{"type": "data", "power", "cadence", "speed", "hr", "hr_source", "buttons", "trainer", "controller"}` 20 times a second, and every half second `{"type": "status", "scanning", "devices", "trainer", "controller", "hrm", "error"}`.
- **Game to bridge** (UDP 9872): `{"grade": %, "gear": ratio, "mass": kg}` for the trainer's resistance, and commands `{"cmd": "ping" | "scan" | "connect" | "disconnect" | "quit", "role", "address"}`.
- **Roles:** `trainer` (FTMS smart trainers, or a Cycling Power meter), `controller` (handlebar controllers), `hrm` (heart rate straps). Heart rate also comes from a trainer that relays one (a Wahoo KICKR passes on an ANT+ strap paired to it).
- **Wi-Fi trainers** (Wahoo Direct Connect) are found over mDNS and spoken to over TCP with the same services, so the rest of the code treats them like Bluetooth ones.
- Chosen devices are remembered in `bridge/devices.json`; `bridge/bridge.log` says what happened.

Run it by hand to debug:

```sh
bridge/.venv/bin/python bridge/trainer_bridge.py --scan    # list what's nearby and exit
bridge/.venv/bin/python bridge/trainer_bridge.py --fake    # fake power, cadence and heart rate, no hardware
bridge/.venv/bin/python bridge/trainer_bridge.py --dump    # print raw controller messages
bridge/.venv/bin/python bridge/trainer_bridge.py --learn   # record your controller's buttons into buttons.json
```

With `--fake` running, start the game normally and it rides on the fake trainer.

## Saves and user data

The save is `user://pizza_city_save.json`: on Linux `~/.local/share/godot/app_userdata/Mt. Crankmore/`, on macOS `~/Library/Application Support/Godot/app_userdata/Mt. Crankmore/`, on Windows `%APPDATA%\Godot\app_userdata\Mt. Crankmore\`. Posted rides' screenshots go to `user://rides/<activity>`. Pictures in `user://art/` override the game's own, for trying out art without rebuilding.

## Strava

`ride_log.gd` records a session once a second (distance, speed, altitude, power and cadence from a trainer, heart rate from a monitor) and writes it as a Garmin TCX file; `strava.gd` uploads it as a Virtual Ride. Players link their own Strava API app (Strava doesn't give games shared keys). `PIZZA_DEBUG=ride` writes a TCX file to check.

## Releasing

1. **Bump the version** in `project.godot` (`config/version`), in `export_presets.cfg` (four places: Windows' `file_version` and `product_version`, macOS's `short_version` and `version`) and in the README's "(currently **x.y.z**)". Commit it, titled just the version.
2. **Merge `dev` into `main`** with a pull request (a merge commit, not a squash).
3. **Export** from a tree identical to `main`:

```sh
godot --headless --path . --export-release Windows
godot --headless --path . --export-release Linux
godot --headless --path . --export-release macOS
```

4. **Package** with the same file names every time: `MtCrankmore-windows-x86_64.zip` (one .exe inside), `MtCrankmore-linux-x86_64.tar.gz` (one executable binary) and `MtCrankmore-macos.zip` (Godot's export as it is). The website's download buttons link to these names in the latest release.
5. **Publish** a GitHub release `vX.Y.Z` titled "Mt. Crankmore X.Y.Z": a one-line summary, the downloads, then "What's in X.Y.Z".

The macOS export needs `textures/vram_compression/import_s3tc_bptc=true` (already set). The macOS app is ad-hoc signed, not notarized.

## The website

`docs/` is the game's site on GitHub Pages, published from `docs/` on the `dev` branch (switch it to `main` in the repository's Pages settings once `main` has it): `index.html` (the home page) and `difficulty.html` (balance and formulas). `.nojekyll` makes Pages serve the files as they are, so Markdown files in `docs/`, like this one, are read on GitHub rather than on the site. The screenshots are the README's: regenerate them with `PIZZA_DEBUG=readme`.
