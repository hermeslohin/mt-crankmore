extends Node
## Global game state: money, garage, rider settings (FTP, weight, difficulty, rivals), physics helpers, save/load (the input map lives in controls.gd).

signal toast(text: String, color: Color)
signal feed(text: String, color: Color)
signal rival_say(rival: int, text: String)
## A racer speaking, for the message box with their face (Hud): `face` names their art/face_<face>.png, `mood` one of
## FACE_MOODS.
signal racer_says(face: String, who: String, text: String, mood: String, color: Color)
## The expressions on a face sheet, in order; each is two frames, mouth shut then open (talking).
const FACE_MOODS := ["happy", "smug", "annoyed", "shocked"]
signal money_changed

const RIDER_MASS := 75.0
const GRAVITY := 9.81
const AIR_RHO := 1.2
const SAVE_PATH := "user://pizza_city_save.json"
const SLOGAN := "Pizza pays the bills, cycling is life"
const LB_PER_KG := 2.20462

## The share of YOUR W/kg (FTP / weight from the menu, at their own weight) rivals ride at, in town and in races alike ("share").
## Their bikes don't change with it (see RIVAL_BIKE).
const DIFFICULTIES := {
	"easy": {"label": "Easy", "share": 0.5, "blurb": "Rivals ride at about 50% of your W/kg. Relaxed spins and big tips."},
	"medium": {"label": "Medium", "share": 0.65, "blurb": "Rivals ride at about 65% of your W/kg. Push a bit and you'll win."},
	"hard": {"label": "Hard", "share": 0.8, "blurb": "Rivals ride at about 80% of your W/kg. Good luck."},
	"ludicrous": {"label": "Ludicrous", "share": 1.0, "blurb": "Rivals ride at 100% of your W/kg. Bring snacks."},
}
const DIFF_ORDER := ["easy", "medium", "hard", "ludicrous"]

## The reigning Tour de Crankmore champion. About once an hour of riding in town he's announced as visiting
## (City._update_champion); get to Race HQ within CHAMPION_WAIT and you can race him and the rivals. He rides 10%
## harder than the strongest of them (Race._build_riders). Art: bike_max.png / bike_max_fall.png.
const CHAMPION := {"name": "Maillot Max", "short": "Max", "color": Color(1.0, 0.86, 0.1), "ftp": 280.0, "speed": 4.4, "attack": 0.6,
	"sig": ["The yellow jersey doesn't wear itself.", "I've won this town's tour three times. Keep up.", "Is that a pizza bike? Adorable.",
		"Allez! Oh wait, that's what my fans shout at ME.", "I trained on this mountain before you had training wheels."]}
const CHAMPION_EVERY := [2700.0, 4500.0]   # seconds of riding in town between his visits
const CHAMPION_WAIT := 300.0               # seconds you have to get to Race HQ once he's announced
const CHAMPION_EDGE := 1.1                 # how much harder he rides than the strongest rival
const CHAMPION_BONUS := 500                # cash for finishing ahead of him (and his bike, CHAMPION_BIKE)
## Thunder Thighs McGee, who rides the Velodoughm (Race course "velo"): one lap, just you and him. He puts out THUNDER_PACE
## of your FTP on his own bike (RIVAL_BIKE, like everyone else) at his own weight (THUNDER_MASS), so only your FTP sets his speed: a
## better bike or a lighter you makes you faster, not him (see thunder_speed, thunder_watts). Art:
## bike_mcgee.png / bike_mcgee_fall.png, face_mcgee.png. "lines": what he says for each Talk category ("sig" otherwise).
const THUNDER := {"name": "Thunder Thighs McGee", "short": "McGee", "color": Color(0.95, 0.22, 0.2), "attack": 0.0,
	"sig": ["These quads have their own postcode.", "I don't skip leg day. Leg day skips everything else.", "Do you even squat, bro?",
		"My thighs have thighs.", "I warm up by leg-pressing the Zamboni."],
	"lines": {
		"race_start": ["One lap. One chance. One pair of LEGENDARY THIGHS.", "Hope you ate your pasta, {n}. All of it.",
			"Feel that rumble? That's my quads warming up.", "750 metres of pain, {n}. Mostly yours."],
		"race_pass_player": ["THUNDER COMING THROUGH!", "Hear that, {n}? That's thunder. From my THIGHS.", "Out of the sprinter's lane, small legs!",
			"Was that a breeze? No, that was me."],
		"race_player_pass": ["WHAT?! Who taught those little legs to do that?", "Impossible! I did 900 squats this morning!",
			"Enjoy it, {n}. The thunder always comes back.", "Hey! My calves weren't ready!"],
		"race_win_rival": ["THUNDER THIGHS WINS AGAIN! Flex for the crowd!", "Go home and do some lunges, {n}.",
			"The Velodoughm belongs to the THIGHS!"],
		"race_lose_player": ["Beaten? By THOSE legs? I need a protein shake. A big one.", "Respect, {n}. You've got thunder too.",
			"My quads... they've never felt this way before."],
		"race_win_player": ["Beaten? By THOSE legs? I need a protein shake. A big one.", "Respect, {n}. You've got thunder too."],
	}}
const THUNDER_PACE := 1.5    # his watts, as a share of YOUR FTP
const THUNDER_MASS := 75.0   # kg
const MAX_RIVALS := 8

var bikes: Array = [
	{"name": "Rusty Trash Bike", "price": 0, "mass": 11.8, "cda": 0.384, "crr": 0.0084, "hp": 60.0, "gravel": 0.73, "turn": 0.85,
		"color": Color(0.6, 0.45, 0.3), "blurb": "Found behind a dumpster. Squeaks in three keys."},
	{"name": "Garage Sale Commuter", "price": 250, "mass": 9.7, "cda": 0.352, "crr": 0.0066, "hp": 85.0, "gravel": 0.73, "turn": 0.95,
		"color": Color(0.25, 0.65, 0.9), "blurb": "Comes with a bell and a mysterious stain."},
	{"name": "Gravel Grinder", "price": 8000, "mass": 8.3, "cda": 0.32, "crr": 0.0056, "hp": 110.0, "gravel": 0.43, "turn": 1.05,
		"color": Color(0.35, 0.75, 0.35), "blurb": "Eats curbs for breakfast."},
	{"name": "Carbon Crit Machine", "price": 2600, "mass": 7.2, "cda": 0.293, "crr": 0.0047, "hp": 130.0, "gravel": 0.68, "turn": 1.15,
		"color": Color(0.85, 0.2, 0.3), "blurb": "Light as a thin crust. Costs like a stuffed one."},
	{"name": "Golden Pepperoni Pro", "price": 7500, "mass": 6.6, "cda": 0.275, "crr": 0.0043, "hp": 150.0, "gravel": 0.55, "turn": 1.25,
		"color": Color(1.0, 0.8, 0.15), "blurb": "Legendary. Smells faintly of mozzarella."},
	# "fixed": one gear (Trainer.FIXED_GEAR), no shifting and no brakes
	{"name": "Fixie", "price": 2000, "mass": 7.5, "cda": 0.311, "crr": 0.0052, "hp": 95.0, "gravel": 0.77, "turn": 1.1, "fixed": true,
		"color": Color(0.95, 0.3, 0.75), "blurb": "Completely impractical, but utterly awesome."},
	# "gift": not for sale; Santa drops it on a winter night (see TownHappenings "santa")
	{"name": "Hoofy Bike", "price": 0, "gift": true, "mass": 11.1, "cda": 0.371, "crr": 0.0077, "hp": 70.0, "gravel": 0.71, "turn": 0.9,
		"color": Color(0.85, 0.15, 0.2), "blurb": "A present from Santa: bells on the bars, antlers on the stem. Jingles over every bump."},
	# "gift": not for sale; yours for beating the Tour de Crankmore champion (see Race._end_race)
	{"name": "Champion's Bike", "price": 0, "gift": true, "mass": 6.5, "cda": 0.27, "crr": 0.0045, "hp": 160.0, "gravel": 0.5, "turn": 1.25,
		"color": Color(1.0, 0.86, 0.1), "blurb": "Maillot Max's own yellow race bike, handed over after you beat him. Signed on the top tube."},
]
const HOOFY := 6   # the Hoofy Bike's place in `bikes`
const CHAMPION_BIKE := 7   # the Champion's Bike's place in `bikes`

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
var rival_order: Array = []    # roster short names in this game's lineup order; the first rival_count ride (shuffled by New game)
var setup_done := false       # the rider has seen the setup screen at least once


func _ready() -> void:
	load_game()


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


const REPAIR_MIN := 200    # the bike shop's charge for the smallest repair
const REPAIR_MAX := 1500   # ...rising with the share of HP missing, to this for a wreck

## The mechanic at Spokes & Stuff takes one look at you on the Rusty Trash Bike and fixes it for nothing.
const MECHANIC_PITY := ["Oh, you poor thing. You look like you need help. This one's on the house.",
	"Yikes. Did a truck do this? Or a bear? Don't answer. No charge.",
	"Kid, you look like you need help more than the bike does. Free. Go eat something.",
	"I've seen pizzas in better shape. Put your wallet away, it's on me.",
	"You look like you need a hug. I don't do hugs. I do free repairs."]


## Whether the bike is short of full HP.
func needs_repair() -> bool:
	return bike_hp() < float(bike()["hp"]) - 0.01


## What the bike shop charges to put the bike back to full HP: nothing for the Rusty Trash Bike (the mechanic feels
## sorry for you), else REPAIR_MIN rising with the share of HP missing to REPAIR_MAX.
func repair_cost() -> int:
	if equipped == 0 or not needs_repair():
		return 0
	var missing := clampf(1.0 - bike_hp() / float(bike()["hp"]), 0.0, 1.0)
	return int(roundf(lerpf(REPAIR_MIN, REPAIR_MAX, missing) / 5.0) * 5.0)


## Puts the bike back to full HP for repair_cost(). False when it didn't need it or you can't pay.
func repair() -> bool:
	var cost := repair_cost()
	if not needs_repair() or money < cost:
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


const RIVAL_SPREAD := 0.05   # the strongest / weakest rival is 5% above / below the base

## A rival's FTP in watts: the player's W/kg from the menu (FTP / weight), spread 5% either way per rival, times the
## rival's own weight `rider_mass`, so they climb like you would. They ride at rival_share() of it, by difficulty.
func rival_ftp(info: Dictionary, rider_mass: float) -> float:
	# the roster ftp (215-275) maps onto a personal spread of -5% .. +5% around the menu W/kg
	var spread := clampf((float(info["ftp"]) - 245.0) / 30.0, -1.0, 1.0) * RIVAL_SPREAD
	return wkg() * rider_mass * (1.0 + spread) * float(info.get("ftp_pct", 1.0))   # "ftp_pct" trims a rival further


## The share of their FTP rivals ride at, by difficulty: the same in town and in a race.
func rival_share() -> float:
	return float(DIFFICULTIES[difficulty]["share"])


func rival_mass(i: int) -> float:
	return 68.0 + (i % 3) * 3.0


## What every rival rides, in town and in races (Maillot Max and Thunder Thighs McGee too): a middle-of-the-road bike,
## the middle of the five bikes for sale on every count, whatever the difficulty. Only your bike changes with what you
## buy, so a better bike makes you faster and nobody else.
const RIVAL_BIKE := {"name": "Club Racer", "mass": 8.3, "cda": 0.32, "crr": 0.0056, "hp": 110.0, "gravel": 0.68, "turn": 1.05,
	"color": Color(0.55, 0.6, 0.7)}


func rival_bike() -> Dictionary:
	return RIVAL_BIKE


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
## How fast McGee goes on flat smooth boards (m/s): THUNDER_PACE of your FTP on RIVAL_BIKE, at THUNDER_MASS.
func thunder_speed() -> float:
	var b := rival_bike()
	return speed_from_power(ftp * THUNDER_PACE, b["mass"], b["cda"], b["crr"], 0.0, THUNDER_MASS)


## The watts it takes you to match McGee on your current bike (flat, smooth boards): beat this to beat him.
func thunder_watts() -> float:
	return power_for_speed(thunder_speed(), bike()["mass"], bike()["cda"], bike()["crr"], 0.0)


## The other way round from speed_from_power: the watts that hold `v` m/s.
func power_for_speed(v: float, bike_mass: float, cda: float, crr: float, grade: float, rider_mass: float = -1.0) -> float:
	if rider_mass < 0.0:
		rider_mass = weight_kg
	var m := rider_mass + bike_mass
	var theta := atan(grade)
	return v * (m * GRAVITY * (sin(theta) + crr * cos(theta)) + 0.5 * AIR_RHO * cda * v * v) / 0.975


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
	rival_order = []
	for r in Talk.roster:
		rival_order.append(r["short"])
	rival_order.shuffle()   # a new game gets a random field
	Talk.set_count(rival_count)
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
		"ftp": ftp, "weight_kg": weight_kg, "units": units, "difficulty": difficulty, "rival_count": rival_count, "rival_order": rival_order, "setup_done": setup_done, "rider": rider,
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
	rival_order = Array(d.get("rival_order", []))
	setup_done = bool(d.get("setup_done", false))
	set_rider(str(d.get("rider", "boy")))
	Season.set_choice(str(d.get("season", "auto")))
	if not owned.has(equipped):
		equipped = 0
	if not hp.has(equipped):
		hp[equipped] = bikes[equipped]["hp"]
