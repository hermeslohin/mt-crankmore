extends Node
## Global game state: money, garage, rider settings (FTP, weight, difficulty, rivals), physics helpers, input map, save/load.

signal toast(text: String, color: Color)
signal feed(text: String, color: Color)
signal rival_say(rival: int, text: String)
signal money_changed

const RIDER_MASS := 75.0
const GRAVITY := 9.81
const AIR_RHO := 1.2
const SAVE_PATH := "user://pizza_city_save.json"
const SLOGAN := "Pizza pays the bills, cycling is life"
const LB_PER_KG := 2.20462

## Rival strength relative to the player's own W/kg, how good their bikes are (offset on their usual bike tier),
## and the share of YOUR FTP (as W/kg, at their own weight) they hold in a race ("race").
const DIFFICULTIES := {
	"easy": {"label": "Easy", "wkg": 0.85, "tier": -1, "race": 0.4, "blurb": "Rivals race at about 40% of your FTP. Relaxed spins and big tips."},
	"medium": {"label": "Medium", "wkg": 1.0, "tier": 0, "race": 0.5, "blurb": "Rivals race at about 50% of your FTP. Push a bit and you'll win."},
	"hard": {"label": "Hard", "wkg": 1.12, "tier": 1, "race": 0.6, "blurb": "Rivals race at about 60% of your FTP on better bikes. Good luck."},
	"ludicrous": {"label": "Ludicrous", "wkg": 1.2, "tier": 2, "race": 0.8, "blurb": "Rivals race at 80% of your FTP on their best bikes. Bring snacks."},
}
const DIFF_ORDER := ["easy", "medium", "hard", "ludicrous"]
const MAX_RIVALS := 8

var bikes: Array = [
	{"name": "Rusty Trash Bike", "price": 0, "mass": 18.0, "cda": 0.52, "crr": 0.013, "hp": 60.0, "gravel": 1.0, "turn": 0.85,
		"color": Color(0.6, 0.45, 0.3), "blurb": "Found behind a dumpster. Squeaks in three keys."},
	{"name": "Garage Sale Commuter", "price": 250, "mass": 13.5, "cda": 0.45, "crr": 0.009, "hp": 85.0, "gravel": 1.0, "turn": 0.95,
		"color": Color(0.25, 0.65, 0.9), "blurb": "Comes with a bell and a mysterious stain."},
	{"name": "Gravel Grinder", "price": 8000, "mass": 10.5, "cda": 0.38, "crr": 0.007, "hp": 110.0, "gravel": 0.35, "turn": 1.05,
		"color": Color(0.35, 0.75, 0.35), "blurb": "Eats curbs for breakfast."},
	{"name": "Carbon Crit Machine", "price": 2600, "mass": 8.0, "cda": 0.32, "crr": 0.005, "hp": 130.0, "gravel": 0.9, "turn": 1.15,
		"color": Color(0.85, 0.2, 0.3), "blurb": "Light as a thin crust. Costs like a stuffed one."},
	{"name": "Golden Pepperoni Pro", "price": 7500, "mass": 6.8, "cda": 0.28, "crr": 0.004, "hp": 150.0, "gravel": 0.6, "turn": 1.25,
		"color": Color(1.0, 0.8, 0.15), "blurb": "Legendary. Smells faintly of mozzarella."},
	# "fixed": one gear (Trainer.FIXED_GEAR), no shifting and no brakes
	{"name": "Fixie", "price": 2000, "mass": 8.6, "cda": 0.36, "crr": 0.006, "hp": 95.0, "gravel": 1.1, "turn": 1.1, "fixed": true,
		"color": Color(0.95, 0.3, 0.75), "blurb": "Completely impractical, but utterly awesome."},
	# "gift": not for sale; Santa drops it on a winter night (see TownHappenings "santa")
	{"name": "Hoofy Bike", "price": 0, "gift": true, "mass": 16.5, "cda": 0.49, "crr": 0.0115, "hp": 70.0, "gravel": 0.95, "turn": 0.9,
		"color": Color(0.85, 0.15, 0.2), "blurb": "A present from Santa: bells on the bars, antlers on the stem. Jingles over every bump."},
]
const HOOFY := 6   # the Hoofy Bike's place in `bikes`

## Extra rolling resistance on Mt. Crankmore gravel, scaled by each bike's "gravel" factor.
const GRAVEL_EXTRA_CRR := 0.014

const START_MONEY := 100
var money := START_MONEY
var owned: Array = [0]
var hp := {0: 60.0}
var equipped := 0
var deliveries := 0
var race_wins := 0
var player_name := "Rookie"
const RIDERS := {"boy": {"label": "Rookie Boy", "sheet": "rookie_boy"}, "girl": {"label": "Rookie Girl", "sheet": "rookie_girl"}}
var rider := "boy"            # which Rookie you ride as: "boy" or "girl" (picked in the rider setup)

# rider settings
var ftp := 200.0              # watts
var weight_kg := 75.0
var units := "kg"             # "kg" or "lbs" (display only; weight is stored in kg)
var difficulty := "medium"
var rival_count := 3
var setup_done := false       # the rider has seen the setup screen at least once


func _ready() -> void:
	_setup_input()
	load_game()


func _setup_input() -> void:
	var map := {
		"steer_left": [KEY_A, KEY_LEFT],
		"steer_right": [KEY_D, KEY_RIGHT],
		"pedal": [KEY_W],
		"brake": [KEY_S],
		"sprint": [KEY_SHIFT],
		"powerup": [KEY_Y, KEY_SPACE],
		"honk": [KEY_H],
		"lane_left": [],      # the handlebar paddles: move across the road (never pick a turn)
		"lane_right": [],
		"shift_up": [KEY_R, KEY_BRACKETRIGHT],
		"shift_down": [KEY_Q, KEY_BRACKETLEFT],
		"act_up": [KEY_UP],
		"act_down": [KEY_DOWN],
		"act_select": [KEY_E, KEY_ENTER],
		"act_back": [KEY_ESCAPE],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# ---- bikes -------------------------------------------------------------

func bike() -> Dictionary:
	return bikes[equipped]


func bike_hp() -> float:
	return hp.get(equipped, 0.0)


func hp_ratio() -> float:
	return clampf(bike_hp() / float(bike()["hp"]), 0.0, 1.0)


## Returns true if the bike was destroyed by this damage.
func damage_bike(amount: float) -> bool:
	hp[equipped] = maxf(0.0, bike_hp() - amount)
	if bike_hp() > 0.0:
		return false
	if equipped == 0:
		hp[0] = bikes[0]["hp"]
		toast.emit("Your trash bike exploded into parts... then you duct-taped it back together.", Color.ORANGE)
		return true
	var lost: String = bike()["name"]
	owned.erase(equipped)
	hp.erase(equipped)
	equipped = 0
	hp[0] = bikes[0]["hp"]
	toast.emit("%s is DESTROYED. Back on the trash bike." % lost, Color.RED)
	save_game()
	return true


func buy_bike(i: int) -> bool:
	var price: int = bikes[i]["price"]
	if money < price or owned.has(i):
		return false
	add_money(-price)
	owned.append(i)
	hp[i] = bikes[i]["hp"]
	equipped = i
	save_game()
	return true


## A bike given for free (Santa's present): yours, fresh, and ridden away. False if you already have it.
func give_bike(i: int) -> bool:
	if owned.has(i):
		return false
	owned.append(i)
	hp[i] = bikes[i]["hp"]
	equipped = i
	save_game()
	return true


func repair_cost() -> int:
	return int(ceilf((float(bike()["hp"]) - bike_hp()) * 1.5))


func repair() -> bool:
	var cost := repair_cost()
	if cost <= 0 or money < cost:
		return false
	add_money(-cost)
	hp[equipped] = bike()["hp"]
	save_game()
	return true


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit()


# ---- rider settings ------------------------------------------------------

func wkg() -> float:
	return ftp / maxf(weight_kg, 30.0)


func weight_text() -> String:
	return "%d lbs" % roundi(weight_kg * LB_PER_KG) if units == "lbs" else "%d kg" % roundi(weight_kg)


## A rival's FTP in watts: the player's W/kg, scaled by difficulty (unless `scaled` is false), with a small personal
## spread (the stronger characters stay a little stronger) so the pack doesn't ride as one.
func rival_ftp(info: Dictionary, rider_mass: float, scaled := true) -> float:
	var spread := 1.0 + (float(info["ftp"]) / 244.0 - 1.0) * 0.5
	return wkg() * (float(DIFFICULTIES[difficulty]["wkg"]) if scaled else 1.0) * spread * rider_mass


func rival_mass(i: int) -> float:
	return 68.0 + (i % 3) * 3.0


## Rivals stick to geared bikes.
func rival_bike(info: Dictionary) -> Dictionary:
	var geared := bikes.filter(func(b): return not b.get("fixed", false))
	return geared[clampi(int(info["tier"]) + int(DIFFICULTIES[difficulty]["tier"]), 0, geared.size() - 1)]


## True while riding a fixed-gear bike: no shifting, no brakes.
func fixed_gear() -> bool:
	return bike().get("fixed", false)


func set_rider(r: String) -> void:
	rider = r if RIDERS.has(r) else "boy"
	Sprites.player_sheet = RIDERS[rider]["sheet"]


func set_rival_count(n: int) -> void:
	rival_count = clampi(n, 1, MAX_RIVALS)
	Talk.set_count(rival_count)


# ---- physics -----------------------------------------------------------

## Steady-state speed (m/s) for a given power and grade (fraction, 0.05 = 5%). Rider mass defaults to the player's weight.
func speed_from_power(power: float, bike_mass: float, cda: float, crr: float, grade: float, rider_mass: float = -1.0) -> float:
	if rider_mass < 0.0:
		rider_mass = weight_kg
	var m := rider_mass + bike_mass
	var theta := atan(grade)
	var roll := m * GRAVITY * (sin(theta) + crr * cos(theta))
	var p := maxf(power, 0.0) * 0.975
	var lo := 0.0
	var hi := 28.0
	for i in 18:
		var mid := (lo + hi) * 0.5
		var need := mid * (roll + 0.5 * AIR_RHO * cda * mid * mid)
		if need > p:
			hi = mid
		else:
			lo = mid
	return lo


# ---- save --------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Wipes the save and resets progress (money, garage, stats). Rider settings (FTP, weight, rivals) are kept.
func new_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	money = START_MONEY
	owned = [0]
	hp = {0: bikes[0]["hp"]}
	equipped = 0
	deliveries = 0
	race_wins = 0
	money_changed.emit()


var no_save := OS.has_environment("PIZZA_NO_SAVE")


func save_game() -> void:
	if no_save:   # dev helpers (tests, screenshot runs, the event viewer) never touch the player's save
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var hp_out := {}
	for k in hp:
		hp_out[str(k)] = hp[k]
	f.store_string(JSON.stringify({"money": money, "owned": owned, "hp": hp_out, "equipped": equipped,
		"deliveries": deliveries, "race_wins": race_wins,
		"ftp": ftp, "weight_kg": weight_kg, "units": units, "difficulty": difficulty, "rival_count": rival_count, "setup_done": setup_done, "rider": rider,
		"season": Season.choice}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# the game used to be called "Pizza City": bring the save over from its old user folder once
		var old := OS.get_user_data_dir().get_base_dir().path_join("Pizza City").path_join(SAVE_PATH.get_file())
		if not FileAccess.file_exists(old):
			return
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(SAVE_PATH))
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	money = int(d.get("money", money))
	owned = []
	for o in d.get("owned", [0]):
		owned.append(int(o))
	hp = {}
	var saved_hp: Dictionary = d.get("hp", {})
	for k in saved_hp:
		hp[int(k)] = float(saved_hp[k])
	equipped = int(d.get("equipped", 0))
	deliveries = int(d.get("deliveries", 0))
	race_wins = int(d.get("race_wins", 0))
	ftp = clampf(float(d.get("ftp", ftp)), 50.0, 600.0)
	weight_kg = clampf(float(d.get("weight_kg", weight_kg)), 30.0, 200.0)
	units = "lbs" if d.get("units", units) == "lbs" else "kg"
	difficulty = d.get("difficulty", difficulty) if DIFFICULTIES.has(d.get("difficulty", "")) else "medium"
	rival_count = clampi(int(d.get("rival_count", rival_count)), 1, MAX_RIVALS)
	setup_done = bool(d.get("setup_done", false))
	set_rider(str(d.get("rider", "boy")))
	Season.set_choice(str(d.get("season", "auto")))
	if not owned.has(equipped):
		equipped = 0
	if not hp.has(equipped):
		hp[equipped] = bikes[equipped]["hp"]
