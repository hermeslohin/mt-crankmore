# Mt. Crankmore

> *Pizza pays the bills, cycling is life.*

A colorful 16-bit-style isometric pizza-delivery racing game set in Crankmore Village, an isolated mountain resort town in summer, built in **Godot 4**.
The game renders at 640x360 and scales up with crisp integer pixels (2x in the default 1280x720 window).
Pedal a **bicycle trainer** (optionally with handlebar controllers) to ride; rival pizza bikers (3 by default, up to 7) trash-talk you the whole way.

![Title screen](docs/title.png)

![Out on a delivery, pizza steaming on the bike](docs/delivery.png)

## Play

Download the latest build for your system from the [Releases page](https://github.com/hermeslohin/mt-crankmore/releases) (currently **0.1**):

| Platform | File | How to run |
|---|---|---|
| Windows | `MtCrankmore-windows-x86_64.zip` | unzip, run `MtCrankmore.exe` |
| macOS | `MtCrankmore-macos.zip` (universal) | unzip, then right-click the app > Open the first time (it's ad-hoc signed, not notarized). If macOS says it's "damaged", run `xattr -cr "Mt. Crankmore.app"` once |
| Linux | `MtCrankmore-linux-x86_64.tar.gz` | extract, `chmod +x MtCrankmore-linux-x86_64`, run it |

**Mac note:** the app is ad-hoc signed but not notarized by Apple, so the first time you open it, right-click (or Control-click) the app and choose **Open**, then confirm. If macOS says the app is "damaged and can't be opened", that is just the download quarantine flag; clear it once in Terminal and open the app again:

```
xattr -cr "/path/to/Mt. Crankmore.app"
```

The game works with just a keyboard. A trainer needs Python 3 and internet once (see [Bicycle trainer](#bicycle-trainer)).

Or run it from source:

```
godot --path .          # or open this folder in the Godot 4 editor and press F5
```

To build the release packages yourself, install the Godot 4.7 export templates and run
`godot --headless --export-release Windows|Linux|macOS` (presets are in `export_presets.cfg`; output goes to `dist/`).

### Continue / New game
The title screen has **Continue game** (resumes your save, showing your money and deliveries; greyed out if there is no save) and **New game**, which **deletes your save** and starts you over with **$100**, one Rusty Trash Bike and zero deliveries. Your rider setup (FTP, weight, rivals) is kept.

### Rider setup
The first time you start delivering (and any time from the title screen or the pause menu) the **Rider setup** screen asks for:

* **FTP** (watts) and **weight**, shown in **kg or lbs**. Your weight is used in the physics, so climbs feel like they do outside.
* **Difficulty**: rivals get a W/kg similar to yours (*Easy* about 85% of it, *Medium* about the same, *Hard* about 12% more, *Ludicrous* about 20% more, with better bikes on the harder levels). In a race they hold a share of their FTP: about 50% on *Easy*, 60% on *Medium*, 70% on *Hard* and 80% on *Ludicrous* (plus the odd surge).
* **Rival bikers**: how many ride against you, 1 to 7 (default 3).

Change values with LEFT / RIGHT (hold to go faster), on the keyboard or the handlebar D-pad. Without a trainer, W rides at 85% of your FTP and Shift sprints.

### Riding on rails
In town you don't steer: just pedal and the bike follows the road. Your only job is choosing a direction at junctions.
A **TURN IN ...m** panel pops up several seconds before every crossroads with three arrows. The yellow one is your choice (straight by default),
and the green **GPS** tag marks the way to your current pickup or delivery. Painted arrows on the road show where you'll go.
One tap is enough: the choice sticks until the junction (no need to hold the button), and the bike curves smoothly through the turn.
If a car is heading for the junction you'll see **CAR COMING!** and you can brake to let it pass.
Pickups and deliveries happen automatically: the bike coasts up to the window and the pizza is handed over as you ride past.

### Controls
| Controller | Keyboard | Action |
|---|---|---|
| pedal | W (210 W), Shift+W sprint | ride |
| D-pad left / right | Left / Right (or A / D) | choose turn at the next junction |
| D-pad up | Up | choose straight |
| D-pad down | Down | U-turn |
| A | E / Enter | enter bike shop / race HQ, menu select |
| B | Esc | pause / back |
| RS1 (right shifter) | R or ] | shift up (harder gear) |
| LS1 (left shifter) | Q or [ | shift down (easier gear) |
| Y, RS2 or right power-up | Y or Space | use your power-up |
| LS2 or left power-up | S | brake |
| Z | H | shout at the rivals |
| | F11 or Alt+Enter | toggle fullscreen (the game starts fullscreen) |

### Virtual shifting
The bike has 21 gears: 1 is the easiest, 21 the hardest, and you start in 11. The range is wide: gear 1 pushes back about a third as hard as gear 11, and gear 21 about two and a half times as hard. There is no front/rear shifter juggling, just up and down. The current gear shows at the top of the WEEHOO bike computer.
With a trainer connected, the gear changes the resistance the trainer sends to your pedals. An easier gear pushes back less, so at the same cadence you make fewer watts and go slower; a harder gear is the reverse. Speed in the game still comes from your real power. Keyboard riders get the same effect: W makes fewer watts and spins faster in low gears.
Resistance needs a trainer that accepts FTMS simulation control.

### Bicycle trainer
On the title screen choose **Connect Trainer**:

1. **Install Bluetooth helper (one time)**: the game sets up a private Python environment in `bridge/.venv` (in a packaged build, in a `bridge` folder in the game's user data folder) with the Bluetooth library. Needs Python 3 (`brew install python` or python.org) and internet, about a minute.
2. The helper starts and scans. Pedal / press a button so your devices wake up; they appear as `TRAINER ...` and `CONTROLS ...`.
3. Select your trainer and your handlebar controllers. The status lines show live power/cadence and the buttons you press, so you can check everything works.
4. Done. Your choices are remembered (`bridge/devices.json`) and reconnect automatically every time you start the game; select a connected device to disconnect it.

Quit any other trainer app first: BLE devices only accept one connection. On macOS, allow Bluetooth for Godot (or your terminal) when asked
(System Settings > Privacy & Security > Bluetooth).

Godot itself can't use Bluetooth, which is why the helper (`bridge/trainer_bridge.py`) exists. You can also run it by hand:
`bridge/.venv/bin/python bridge/trainer_bridge.py` (auto-connects the first trainer/controls it finds), `--scan`, `--dump`, `--fake`.

* **Trainer**: standard FTMS. Your real power and cadence drive your speed. The game puts the trainer in simulation mode and sends the road grade (town hills and Mt. Crankmore, -7% to +12%) so climbs get harder and descents easier, with an extra kick when you hop a fallen tree or wade a creek; it repeats the grade every 2 s so the trainer doesn't fall back to a fixed resistance, and goes flat in menus, the bike shop and the ER. The helper log (`grade -> +6.3%`, `trainer: resistance control ready`) shows what is being sent.
* **Controllers**: see the controls table above.

> **Heads-up:** the trainer side uses a published standard. The handlebar controller protocol is proprietary and reverse-engineered by the community. The button bit-map in `bridge/trainer_bridge.py` is a best-effort default that I could not test against real hardware. If a button misbehaves, run `bridge/.venv/bin/python bridge/trainer_bridge.py --learn`: it asks you to press each button and writes `bridge/buttons.json`, which overrides the defaults.

The game shows connection status at the bottom of the screen ("Trainer + controllers connected").

## The game

* **Orders**: pizza shops ring you with orders. A pizza man dances outside the shop holding the steaming box over his head; ride up, slow down, and he hands it to you. The steam on your bike shows how hot the pizza still is: deliver before the timer runs out or the customer won't pay at all. Faster means bigger tips, crashes hurt the pizza.
* **Townsfolk**: people stroll the pavements all over the village and cheer you on as you ride past.
* **Rivals**: up to seven AI bikers (Dough Boy Dave, Spoke-n Word Sam, Cadence Carla, Wheelie Wanda, Gear Grinder Gus, Margherita Maya, Tubeless Tony; the first three ride by default) chase the same orders and will snag them if they reach the window first. They talk trash constantly (family-friendly).
* **Bikes**: you start on a Rusty Trash Bike. **Spokes & Stuff** sells better ones (lighter, more aero, tougher, handle better) and repairs. Bikes have HP; walls and cars damage them, and at 0 HP a bike is destroyed.
* **Cars**: get hit and you wake up at **St. Pedro's ER** with a medical bill (money can go negative) and a banged-up bike.
* **The village**: winding roads around a cobbled plaza full of shops and market stalls, a lake with a beach and dock, hotels by the water and the gondola, chalet neighbourhoods in the woods, and only light traffic.
* **Hills**: the plaza and the lakeshore are flat; the chalet neighbourhoods, Summit Road, Ridge Road and the climb up to the gondola roll up to about 7% (Gondola Way pitches to 9%). The grade is shown on your WEEHOO, slows you down uphill and speeds you up downhill (rivals too), and is sent to your trainer.
* **Mt. Crankmore**: enter races at the Race HQ (the checkered building by the gondola). Two ~20-minute gravel races against your rivals (Foothill Gravel Grind, 6 km averaging 4%; Summit Gravel Showdown, 4.4 km averaging 6.5% with ramps up to 12%) using a real power/weight/aero/grade model with extra gravel rolling resistance, drafting, power-ups, and prize money. The Gravel Grinder bike shines here.
  * The mountain is built at the same scale as the town (about 3.3 m per tile), so race speeds look like town speeds. Long switchbacks with hairpins zig-zag up a hillside of meadows, pine forest, rock and snow, and the profile rolls: long climbs broken up by short plunges and steep kickers.
  * **Jumps** on the descents (hit one above ~30 km/h for BIG AIR), **fallen trees** you hop (they scrub some speed), and **creek fords** that drag you down while you splash through. Yellow warning signs come up before each one, and they're marked on the WEEHOO profile (blue creeks, orange jumps, brown logs).
  * **Wildlife**: deer, foxes and squirrels dash across the road in front of you, rabbits bolt, moose wade near the creeks, goats and marmots watch from the rocks, eagles circle overhead, and bears give chase. Keep pedalling or the bear takes a swipe at your bike.
* **Power-ups**: about 1 in 8 townsfolk hold up a gift box, and spectators along the race course do too. Ride past with empty hands and they toss you a power-up. You carry one at a time; it shows on the WEEHOO, and **Y** (or Space) uses it. The rivals grab and use them too.
  * *Town only*: **Pepperoni Portal** warps you to the nearest pizza shop with a pizza waiting. **Bike Wrench** fixes your bike to full HP. **Walkie Talkie** summons a pizza mascot that dances in front of the nearest rival and slows them to a crawl for 12 s.
  * *Town and races*: **Pizza Frisbee** knocks a rival within 5 m off their bike for 5 s (out of range, you keep it). **Fire Socks** make you 30% faster for 15 s. **Breadsticks** make you huge for 12 s, and anyone you ride into falls over.
* **WEEHOO**: your bike computer in the bottom-right corner. It shows the town map (or the course profile in a race), speed, watts, money (race position in a race), grade, cadence, HP and the power-up you are carrying (or how long Fire Socks / Breadsticks have left). The LED strip along the top lights up with your power, coloured by zone relative to your FTP.
* Progress (money, bikes, HP) is saved automatically. Start over any time with **New game** on the title screen.

## Layout

```
project.godot
export_presets.cfg        Windows / Linux / macOS export presets
scenes/main.tscn          entry scene (everything else is built in code)
scripts/game.gd           autoload: money, bikes, physics, save/load, input map
scripts/trainer_link.gd     autoload: UDP link to the bridge + keyboard fallback
scripts/trash_talk.gd     autoload: rivals and their trash talk
scripts/main.gd           mode switching and menus
scripts/city.gd           isometric city, traffic, rivals, orders
scripts/race.gd           Mt. Crankmore switchbacks, terrain, obstacles, wildlife + race sim
scripts/powerups.gd       power-up definitions and drawing (icons, gift, frisbee, mascot)
scripts/hud.gd            HUD and menus
scripts/iso.gd, bike_draw.gd   drawing helpers
bridge/trainer_bridge.py    BLE <-> UDP bridge (Python, bleak)
```

Everything is drawn procedurally; there are no art assets yet. Dev helpers: `PIZZA_DEBUG=city|race|shop|er|flow|rails|roads|overview godot --path .`; `PIZZA_DEBUG=shot PIZZA_OUT=dir [PIZZA_AT=x,y;...|junctions|shops]` saves screenshots; `PIZZA_DEBUG=race_shot [PIZZA_COURSE=0|1] PIZZA_OUT=dir` saves race screenshots at the first jump, log, creek and wildlife; `PIZZA_DEBUG=powerups PIZZA_OUT=dir` tries every power-up in town and in a race and saves a screenshot of each; `PIZZA_DEBUG=readme godot --path .` regenerates the README screenshots in `docs/`.
