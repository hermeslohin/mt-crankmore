extends Node2D
## Crankmore Village: an isolated mountain resort town, through the seasons (see Season). Winding roads, a lake with a
## beach, a cobbled village plaza packed with shops, hotels by the lake and the gondola, chalet
## neighbourhoods in the woods, light traffic, tourists, rival pizza bikers (3 by default, up to 7), and the
## order/delivery loop. Drawn flat-shaded with pixel outlines; the project renders at 640x360.
## Rolling hills (height_m) lift everything drawn through Iso.to_screen; the grade under the wheels
## changes the rider's speed and is sent to the trainer as resistance.
##
## The player rides "on rails": the bike follows the road on its own and the rider only picks
## left / straight / right at junctions (announced well ahead), so a trainer rider can focus
## on pedalling. Pickups and deliveries happen automatically while riding past.

signal interact(kind: String)

## The town's scale: every place on the map (roads, plaza, lake, hills, landmarks) is laid out in "design" tiles
## and multiplied by MAP_K, so the map can grow and leave room for wider roads without redrawing it.
const MAP_K := 1.25
const N := 200              # 160 design tiles * MAP_K
const MARGIN := 18
const TILES_PER_MS := 0.45
## Overall pace of the town (rider, rivals, traffic). 0.7 = 30% slower than the original tuning.
const PACE := 0.7
const CAR_HIT_R := 0.14
const CAR_BODY := 0.85      # the part of a car's sprite that's actually car (the rest is air): what can hit you
const CAR_LANE := 0.62      # a car's distance from the middle of the road
const BIKE_LANE := 1.22     # you ride out on the right-hand edge, clear of the cars
const ROAD_HW := 1.3        # half the road's width: two lanes of traffic and a bike
const TURN_R := 2.2         # how far before / after a junction the rider eases into / out of the turn
const PLAZA := Vector2(72, 76) * MAP_K
const RING_R := 9.5 * MAP_K
const LAKE := Vector2(120, 40) * MAP_K
const LAKE_R := 13.0 * MAP_K
const BASE := Vector2(26, 28) * MAP_K
## Hills: [centre, radius (tiles), height (m)]. Negative height is a dip. The plaza and the lake stay flat.
const HILLS := [
	# (centre, radius and height all scale with the map, so the slopes stay as steep)
	[Vector2(30, 34) * MAP_K, 30.0 * MAP_K, 8.0 * MAP_K],     # the gondola side, rising towards Mt. Crankmore
	[Vector2(78, 20) * MAP_K, 18.0 * MAP_K, 4.5 * MAP_K],     # Summit Road / Lookout
	[Vector2(28, 94) * MAP_K, 18.0 * MAP_K, 4.5 * MAP_K],     # Chalet Hill
	[Vector2(50, 134) * MAP_K, 16.0 * MAP_K, 3.5 * MAP_K],    # Pine Hollow
	[Vector2(108, 124) * MAP_K, 18.0 * MAP_K, 4.5 * MAP_K],   # Ridge Road
	[Vector2(148, 90) * MAP_K, 14.0 * MAP_K, 3.5 * MAP_K],    # East shore bluffs
	[Vector2(78, 148) * MAP_K, 18.0 * MAP_K, -2.5 * MAP_K],   # Valley Bottom
]
const PX_PER_M := 10.0                        # screen lift per metre of height
const M_PER_TILE := 1.0 / (TILES_PER_MS * PACE)   # metres of riding per tile, matching the speed model
const MAX_TOWN_SPEED := 13.0                  # m/s cap on descents

enum T { GRASS, PLAZA, SIDEWALK, SAND, WATER, FOREST }

const SHOP_NAMES := ["Sushi Slope", "Rewind Video", "Ski & Board", "Brew Peak Cafe", "Pixel Palace", "Gear Loft", "Poutine Hut",
	"Track 9 Records", "Crankmore Savings Bank", "Maple Mart", "Mega Mall", "Gelato Glacier", "Bike Spa", "The Cozy Mug", "Alpine Outfitters", "Fondue Fondue", "Summit Souvenirs", "Bear Paw Bakery",
	"Marmot Books", "Crepe Escape", "Trailhead Tees", "Cinnamon Lodge", "The Tuning Shop", "Snowcone Shack", "Moose Juice Bar",
	"Glacier Gallery", "Granola Goods", "Hot Tub Supply", "Pinecone Pottery", "Sunburn Shades", "Waffle Chalet", "Peak Pharmacy",
	"Lazy Lake Tackle", "The Yodel Deli", "Kayak Corner", "Sweater Weather", "Candle Cabin", "The Taffy Tram"]
const HOTEL_NAMES := ["Alpine Lodge", "Summit Suites", "Fondue Inn", "Gondola Grand", "Bear Hug Hotel", "Marmot Motel",
	"Chairlift Hotel", "Snowcap Resort", "Lakeview Lodge", "Moose Lodge", "Lift Ticket Inn", "Cowbell Hotel", "Powder Palace",
	"Aspen House", "Sleepy Hollow Inn", "Crankmore Grand", "Hammock Haus", "The Slow Lane Spa", "Driftwood Inn", "Edelweiss Hotel"]
const PIZZA_COLORS := [Color(0.9, 0.2, 0.2), Color(1.0, 0.55, 0.1), Color(0.2, 0.7, 0.35), Color(0.6, 0.3, 0.8), Color(0.15, 0.55, 0.85)]
const WALLS := [Color(0.98, 0.82, 0.45), Color(0.55, 0.8, 0.95), Color(0.98, 0.62, 0.62), Color(0.65, 0.88, 0.55),
	Color(0.98, 0.7, 0.35), Color(0.78, 0.68, 0.98), Color(0.98, 0.94, 0.72), Color(0.5, 0.88, 0.82), Color(0.96, 0.96, 0.96)]
const WOOD := [Color(0.62, 0.42, 0.26), Color(0.72, 0.52, 0.32), Color(0.92, 0.86, 0.72), Color(0.55, 0.36, 0.24)]
const ROOFS := [Color(0.75, 0.22, 0.18), Color(0.2, 0.45, 0.3), Color(0.3, 0.32, 0.42), Color(0.2, 0.5, 0.6), Color(0.5, 0.25, 0.2)]
## Traffic: sprite name (art/vehicle_<kind>.png) -> half length and half width in tiles, and the speed range (x PACE).
## The plain "car" and "truck" are white and get painted a random CAR_COLORS colour; the rest keep their own colours.
const VEHICLE_DIMS := {
	"car": [0.55, 0.3, 2.2, 3.4], "truck": [0.8, 0.34, 2.0, 2.8], "motorcycle": [0.38, 0.16, 3.2, 4.2],
	"sedan_sports_red": [0.55, 0.3, 2.8, 3.8], "sedan_luxury_navy": [0.6, 0.3, 2.2, 3.0], "sedan_taxi": [0.55, 0.3, 2.4, 3.4],
	"sedan_retro_teal": [0.5, 0.29, 2.0, 2.8], "sedan_police": [0.55, 0.3, 2.6, 3.6], "sedan_wagon_green": [0.6, 0.3, 2.0, 2.8],
	"truck_pickup_red": [0.7, 0.32, 2.2, 3.0], "truck_snowplow": [0.85, 0.36, 1.8, 2.5], "truck_flatbed_green": [0.9, 0.34, 1.8, 2.5],
	"van_camper": [0.65, 0.32, 2.0, 2.8], "van_ambulance": [0.65, 0.32, 2.4, 3.4],
	"sedan_pink_convertible": [0.55, 0.3, 2.2, 3.2], "sedan_limo": [0.8, 0.3, 2.0, 2.8], "sedan_electric_lime": [0.5, 0.29, 2.4, 3.4],
	"sedan_hotrod_orange": [0.55, 0.3, 3.0, 4.0], "sedan_beetle_yellow": [0.5, 0.29, 2.0, 2.8], "sedan_microcar_sky": [0.4, 0.26, 2.0, 3.0],
	"truck_firetruck": [0.9, 0.36, 2.4, 3.2], "truck_garbage": [0.9, 0.36, 1.6, 2.2], "truck_icecream": [0.8, 0.34, 1.8, 2.4],
	"truck_tow": [0.8, 0.34, 2.2, 3.0], "truck_tractor": [0.6, 0.32, 1.1, 1.7], "van_school_bus": [1.05, 0.36, 1.8, 2.4],
	"van_mail": [0.65, 0.32, 2.2, 3.0], "van_foodtruck": [0.8, 0.34, 1.6, 2.2], "van_minivan_purple": [0.65, 0.32, 2.2, 3.0],
	"sedan_suv_green": [0.6, 0.3, 2.2, 3.0], "sedan_jeep_khaki": [0.55, 0.3, 2.0, 3.0], "sedan_pickup_red": [0.6, 0.3, 2.2, 3.0],
	"sedan_sportswagon_teal": [0.6, 0.3, 2.2, 3.2], "sedan_cab_checker": [0.6, 0.3, 2.2, 3.0], "sedan_vintage_cream": [0.55, 0.29, 1.8, 2.6],
	"truck_cement_mixer": [0.85, 0.36, 1.6, 2.2], "truck_delivery_box": [0.85, 0.34, 2.0, 2.8], "truck_milk": [0.85, 0.34, 1.8, 2.4],
	"truck_logging": [0.9, 0.34, 1.6, 2.2], "van_camper_orange": [0.65, 0.32, 1.8, 2.6], "van_bakery": [0.7, 0.32, 2.0, 2.8],
	"sedan_hatchback_red": [0.5, 0.29, 2.2, 3.2], "sedan_station_wagon_brown": [0.6, 0.3, 2.0, 2.8], "sedan_compact_white": [0.5, 0.29, 2.2, 3.0],
	"sedan_coupe_silver": [0.55, 0.3, 2.6, 3.6], "sedan_muscle_black": [0.6, 0.3, 2.8, 3.8], "sedan_sedan_green_90s": [0.6, 0.3, 2.2, 3.0],
	"sedan_jeep_wrangler_yellow": [0.5, 0.3, 2.0, 3.0], "sedan_minitruck_teal": [0.5, 0.29, 1.8, 2.6], "sedan_suv_maroon": [0.6, 0.31, 2.2, 3.0],
	"sedan_kei_car_mint": [0.42, 0.27, 2.0, 2.8], "sedan_roadster_british_racing_green": [0.5, 0.28, 2.6, 3.6], "sedan_pt_cruiser_purple": [0.55, 0.3, 2.0, 2.8],
	"van_panel_white": [0.7, 0.32, 2.0, 2.8], "van_vw_bus_blue": [0.65, 0.32, 1.8, 2.5], "van_minibus_orange": [0.8, 0.33, 1.8, 2.5],
	"truck_pickup_blue_old": [0.65, 0.31, 1.8, 2.6], "truck_flatbed_hay": [0.9, 0.34, 1.4, 2.0], "truck_box_rental": [0.85, 0.34, 1.8, 2.5],
	"van_city_bus": [1.05, 0.36, 1.6, 2.2], "sedan_vespa": [0.3, 0.14, 2.4, 3.2], "sedan_tuktuk": [0.4, 0.24, 1.8, 2.6],
	"truck_street_sweeper": [0.7, 0.32, 0.8, 1.2], "truck_crane": [1.0, 0.36, 1.2, 1.8], "sedan_horse_carriage": [0.7, 0.3, 0.9, 1.3],
	"sedan_4x4_skis": [0.6, 0.31, 2.2, 3.0], "van_ski_shuttle": [0.75, 0.33, 1.8, 2.6], "sedan_retro_wagon_wood": [0.6, 0.3, 1.8, 2.6],
	"sedan_sports_blue": [0.55, 0.3, 2.8, 3.8], "truck_moving_van": [0.95, 0.35, 1.6, 2.2], "sedan_rally": [0.55, 0.3, 3.0, 4.0]}
const PAINTED_VEHICLES := ["car", "truck"]
## Drive like maniacs: weave about their lane and, alone of all the traffic, won't wait behind you but swing over the
## centre line to get by (see _wild_step).
const WILD_VEHICLES := ["sedan_hotrod_orange"]
const CAR_COUNT := 66    # vehicles in the town's traffic
const PLAZA_PEOPLE := 13   # townsfolk milling about the plaza
const STREET_PEOPLE := 140 # and strolling the pavements (a crowd, not a crush)
const CAR_COLORS := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.95, 0.95), Color(0.2, 0.75, 0.45), Color(0.15, 0.15, 0.22)]
const ER_JOKES := [
	"Doctor: \"Good news: you're fine. Bad news: your bike filed a complaint.\"",
	"Nurse: \"Say 'cheese!' ...Please don't say pizza, we're all starving.\"",
	"Doctor: \"On a scale of 1 to 10, how much did that hurt?\" \"Pepperoni.\"",
	"Nurse: \"We found a mushroom in your helmet. We've decided not to ask.\"",
	"Doctor: \"Prescription: fewer cars, more cheese.\"",
	"Billing: \"We accept cash, card, or a large pepperoni.\"",
]
const CHEERS := ["Go {n}!", "Pizza hero!", "Woo-hoo!", "Pedal faster!", "Extra cheese!", "Allez allez!", "You got this!",
	"Hot pizza!", "Beat Carl!", "Send it!", "Smell that crust!", "Go go go!", "Legend!"]
const DOOR_FADE := 2.5     # 1/seconds: someone going in at a door (or coming out) fades out (in) over 0.4 s
const SHOP_LINES := ["Bargain!", "Got snacks!", "Ooh, new socks!", "Best gelato ever.", "Back to work...", "Smells like pizza in there!",
	"They were out of anchovies.", "Got a new helmet!", "Two for one!", "Treat yourself!", "Shopping is cardio, right?"]
const HONKS := ["Pizza coming through!", "Hot pizza, comin' atcha!", "On your left!", "Beep beep! Delivery!", "Move it or lose it!", "Ding ding!"]

var active := false

var tiles := PackedByteArray()
var solid := PackedByteArray()
var reserved := PackedByteArray()   # 1 = not buildable, 2 = building
var road_d := PackedFloat32Array()  # distance from tile centre to nearest road centreline
var roads: Array = []
var road_draw: Array = []
var lake_poly := PackedVector2Array()
var lake_screen: Dictionary = {}
var buildings: Array = []
var trees: Array = []
var tree_chunks: Dictionary = {}   # Vector2i(chunk) -> trees, so drawing only visits nearby trees
const CHUNK := 8
var props: Array = []
var spots: Array = []     # delivery destinations
var site_spot := -1       # the construction site's delivery spot (its crew orders pizza now and then)
const SITE_ORDER_CHANCE := 0.15
var shops: Array = []     # pizza shops
var zones: Array = []     # interactive doors
var cars: Array = []
var peds: Array = []
var road_doors: Dictionary = {}   # road index -> [[s, side, building index], ...]: the doors people can pop into
var pops = load("res://tools/pop_watch.gd").new(self) if OS.has_environment("PIZZA_POPS") else null   # dev helper: see tools/pop_watch.gd
var events: TownEvents          # random happenings around the player (see TownEvents)
const MedHeli := preload("res://scripts/med_heli.gd")
const NewsHeli := preload("res://scripts/news_heli.gd")
const NEWS_EVERY := [480.0, 900.0]   # seconds between the news helicopter coming to film you
const NEWS_STAY := [60.0, 100.0]     # seconds it follows you
const NEWS_ALT := 190.0
var heli                        # the air ambulance on the hospital roof (MedHeli)
var news                        # the news helicopter, when it's about (NewsHeli)
var news_state := "off"         # off, on (following you), leaving
var news_t := randf_range(240.0, NEWS_EVERY[1])
var champion_t := randf_range(Game.CHAMPION_EVERY[0], Game.CHAMPION_EVERY[1])   # riding in town until the champion next visits
var champion_left := 0.0        # > 0: he's in town and waiting at Race HQ for that many more seconds
var boats: Array = []
var astar := AStar2D.new()
var gondola_top := Vector2.ZERO
## Chairlifts up Mt. Crankmore from the hills by the gondola: a bottom station in town, towers up the lift line (the
## trees cleared), and the cable running on up the mountain in the backdrop, with chairs going round.
const LIFT_BASES := [Vector2(14, 46), Vector2(40, 16), Vector2(12, 24)]
const LIFT_SUMMITS := [Vector2(-300, -1380), Vector2(140, -1420), Vector2(-120, -1460)]   # where each cable meets the mountain (screen)
const LIFT_Z := 80.0          # px: the cable's height over the ground
const LIFT_CHAIR_GAP := 72.0  # px between chairs along the cable
const LIFT_SPEED_PX := 18.0   # px per second
var lifts: Array = []         # {base: world pos, line: [world points up the lift line], summit, pts (cable, screen; built on first draw), len}
var rng := RandomNumberGenerator.new()
var _name_i := {"shop": 0, "hotel": 0}

var junctions: Array = []   # {"pos", "links": [[road, s], ...]}
var road_js: Array = []     # per road: sorted [[s, junction], ...]
var zebra: Array = []       # crosswalk stripes [screen centre, polygon]

var rr := 0                 # rail state: road, distance along it, direction
var rs := 0.0
var rdir := 1.0
var rail_pos := Vector2.ZERO
var p_lat := 0.0              # tiles across the road from the usual line (- towards the centre line and on over it, + the kerb)
var p_fwd := Vector2.RIGHT
var pending: Dictionary = {}  # the upcoming junction choice
var queued := ""              # a turn pressed before the junction was announced; used at the next real junction
var uturn_hint := false
var _from_j := -1             # the junction the rider just rode through (so it isn't taken twice)
var _turn: Dictionary = {}    # the curve the rider is following through a junction (see _update_turn)
var _uturn: Dictionary = {}   # a U-turn in progress: {from (position), fwd (heading then), t 0-1}
const UTURN_TIME := 1.1       # seconds to swing round
var _hint_clock := 0.0

var p_pos := Vector2.ZERO
var p_head := 0.0
var p_speed := 0.0
var p_phase := 0.0
var pu := ""                  # the power-up you're carrying (see PowerUps), "" = none
var socks_t := 0.0            # Fire Socks seconds left
var bread_t := 0.0            # Breadsticks seconds left
var roller_t := 0.0           # Dough Roller seconds left (climbs feel flat)
var p_down := 0.0             # seconds left lying on the road after a frisbee hit or being run over
var p_fall := 0.0             # seconds since the player went down: the wipe-out animation's clock
var p_fall_pizza := false     # was the player carrying a pizza when they went down
var p_blocked := false        # a pizza mascot is dancing in your way
var mascots: Array = []       # {"victim": -1 player / rival index, "t", "pos", "phase"}
var frisbees: Array = []      # pizzas in flight {"from", "to", "u"}
var invuln := 0.0
var carry: Dictionary = {}
var handoff := 0.0
var handoff_shop := -1
var handoff_live := false       # you're stopped at the window and the baker's throwing (not backing off)
const HANDOFF_TIME := 1.1       # seconds for the baker to wind up and throw you the pizza
const THROW_END := 0.75         # the baker's throw plays over this much of the handoff, then holds
const THROW_RELEASE := 0.56     # where in the handoff the pizza leaves their hands (about frame 7 of the throw), spinning, and flies to you
var prompt := ""
var er_timer := 0.0
const ER_LIE_TIME := 3.0      # seconds the rider lies in the road, after a car hit, before they vanish into the ER
var er_text := ""
var er_bill := 0
var bubbles: Dictionary = {}
var player_bubble := {"text": "", "t": 0.0}

var orders: Array = []
var next_order_id := 1
var order_clock := 3.0
var rival_state: Array = []
var rival_score: Array = []

var t_ := 0.0
var font: Font
var grade := 0.0          # current road grade under the player (fraction, smoothed)
var season_props: Array = []   # scenery that only shows in one season: {"season", "kind", "pos", ...}


func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # the ground textures (see Ground) wrap
	_build_heights()
	Iso.terrain_on = true
	_generate()
	_build_graph()
	_spawn_cars()
	_find_climbs()
	_spawn_rivals()
	_spawn_life()
	events = TownHappenings.new(self)
	heli = MedHeli.new(self)
	heli.setup()
	Game.rival_say.connect(_on_rival_say)
	rival_score.resize(Talk.rivals.size())
	rival_score.fill(0)
	reset_player()
	Iso.terrain_on = false


## Re-creates the rival bikers after the rival count changed in the rider setup.
func respawn_rivals() -> void:
	_spawn_rivals()
	rival_score.resize(Talk.rivals.size())
	rival_score.fill(0)
	bubbles.clear()
	mascots.clear()
	frisbees.clear()
	for o in orders:
		if o["state"] == "rival" and int(o["rival"]) >= Talk.rivals.size():
			o["state"] = "done"


## Picks up new FTP / weight / difficulty settings without moving the rivals.
func refresh_rivals() -> void:
	for i in rival_state.size():
		var info: Dictionary = Talk.rivals[i]
		rival_state[i]["mass"] = Game.rival_mass(i)
		rival_state[i]["bike"] = Game.rival_bike(info)
		rival_state[i]["ftp"] = Game.rival_ftp(info, Game.rival_mass(i))


## Ground height in metres: a few smooth hills, faded out around the plaza and the lake.
func height_m(p: Vector2) -> float:
	var h := 0.0
	for hill in HILLS:
		var d: float = p.distance_to(hill[0]) / float(hill[1])
		h += float(hill[2]) * exp(-d * d)
	h *= smoothstep(RING_R + 3.0 * MAP_K, RING_R + 22.0 * MAP_K, p.distance_to(PLAZA))
	h *= smoothstep(LAKE_R + 2.0 * MAP_K, LAKE_R + 18.0 * MAP_K, p.distance_to(LAKE))
	return h


## Road grade (fraction) at `p` when travelling along `dir`.
func grade_at(p: Vector2, dir: Vector2) -> float:
	var d := dir.normalized() * 0.8
	return (height_m(p + d) - height_m(p - d)) / (1.6 * M_PER_TILE)


func _build_heights() -> void:
	var n := N + 2 * MARGIN + 1
	Iso.hgrid.resize(n * n)
	Iso.hgrid_o = -MARGIN
	Iso.hgrid_n = n
	for j in n:
		for i in n:
			Iso.hgrid[j * n + i] = height_m(Vector2(i - MARGIN, j - MARGIN)) * PX_PER_M


## Light on the hills: slopes facing the upper left are brighter, the far side darker.
func _slope_light(tile: Vector2) -> float:
	var c := tile + Vector2(0.5, 0.5)
	var gx := Iso.ground_z(c + Vector2(0.5, 0)) - Iso.ground_z(c - Vector2(0.5, 0))
	var gy := Iso.ground_z(c + Vector2(0, 0.5)) - Iso.ground_z(c - Vector2(0, 0.5))
	return clampf(1.0 + (gx * 0.9 + gy * 0.35) * 0.13, 0.72, 1.2)


## Contour band of a tile (1.5 m steps), used to draw faint contour lines on the hills.
func _contour(x: int, y: int) -> int:
	return floori(Iso.ground_z(Vector2(x + 0.5, y + 0.5)) / (PX_PER_M * 1.5))


func reset_player() -> void:
	place_on({"road": 0, "s": 0.0})
	rdir = 1.0
	carry = {}
	er_timer = 0.0
	p_fall = 0.0
	invuln = 1.0
	pu = ""
	socks_t = 0.0
	bread_t = 0.0
	roller_t = 0.0
	p_down = 0.0
	mascots.clear()
	frisbees.clear()


## Puts the rider on the road at an anchor ({"road", "s"}), e.g. a shop or the ER.
func place_on(anchor: Dictionary) -> void:
	rr = anchor["road"]
	rs = anchor["s"]
	pending = {}
	_turn = {}
	_uturn = {}
	_from_j = -1
	p_lat = 0.0
	var w := _rail_world()
	rail_pos = w[0]
	p_fwd = w[1]
	p_pos = rail_pos
	p_head = p_fwd.angle()
	p_speed = 0.0


func cam_target() -> Vector2:
	# look a little ahead along the road so upcoming junctions come into view early
	var p := p_pos + p_fwd * 2.2
	return Iso.to_screen(p, 12.0 + Iso.ground_z(p))


func zone_anchor(kind: String) -> Dictionary:
	for z in zones:
		if z["kind"] == kind:
			return z
	return {"road": 0, "s": 0.0}


# ======================================================================
# World generation
# ======================================================================

func _lake_r(a: float) -> float:
	return LAKE_R * (1.0 + 0.16 * sin(3.0 * a + 1.0) + 0.08 * sin(5.0 * a + 2.0))


func _lake_ring(extra: float, mul: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 72:
		var a := TAU * i / 72.0
		out.append(LAKE + Vector2(cos(a), sin(a)) * (_lake_r(a) * mul + extra))
	return out


func _ring_pt(a: float) -> Vector2:
	return PLAZA + Vector2(cos(a), sin(a)) * RING_R


func _generate() -> void:
	rng.seed = 424242
	tiles.resize(N * N)
	tiles.fill(T.GRASS)
	solid.resize(N * N)
	solid.fill(0)
	reserved.resize(N * N)
	reserved.fill(0)
	road_d.resize(N * N)
	road_d.fill(99.0)
	lake_poly = _lake_ring(0.0)
	_make_roads()
	_build_junctions()
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		for p in pts:
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if x < 0 or y < 0 or x >= N or y >= N:
						continue
					var d := p.distance_to(Vector2(x + 0.5, y + 0.5))
					if d < road_d[y * N + x]:
						road_d[y * N + x] = d
	var sand := _lake_ring(1.7)
	for y in N:
		for x in N:
			var c := Vector2(x + 0.5, y + 0.5)
			var i := y * N + x
			if Geometry2D.is_point_in_polygon(c, lake_poly):
				tiles[i] = T.WATER
				solid[i] = 1
				reserved[i] = 1
			elif Geometry2D.is_point_in_polygon(c, sand):
				tiles[i] = T.SAND
				reserved[i] = 1
			elif c.distance_to(PLAZA) < RING_R + ROAD_HW + 0.9:
				tiles[i] = T.PLAZA
				reserved[i] = 1
			elif road_d[i] < ROAD_HW + 1.1 and c.distance_to(PLAZA) < 28.0 * MAP_K:
				tiles[i] = T.SIDEWALK
			elif (x < 3 or y < 3 or x >= N - 3 or y >= N - 3) and road_d[i] > 3.0:
				tiles[i] = T.FOREST
				reserved[i] = 1
			if road_d[i] < ROAD_HW + 0.3:
				reserved[i] = 1
	# fountain + market stalls in the plaza
	for y in range(int(PLAZA.y) - 1, int(PLAZA.y) + 1):
		for x in range(int(PLAZA.x) - 1, int(PLAZA.x) + 1):
			solid[y * N + x] = 1
	props.append({"kind": "fountain", "pos": PLAZA})
	for k in 6:
		var a := TAU * k / 6.0 + 0.5
		var sp := PLAZA + Vector2(cos(a), sin(a)) * 4.3
		solid[int(sp.y) * N + int(sp.x)] = 1
		props.append({"kind": "stall", "pos": Vector2(int(sp.x), int(sp.y)), "col": PIZZA_COLORS[k % PIZZA_COLORS.size()]})

	_place_specials()
	_place_generic()
	_place_nature()
	_build_road_geometry()
	_build_lake_geometry()
	_place_lifts()
	for t in trees:
		var key := Vector2i(floori(t["pos"].x / CHUNK), floori(t["pos"].y / CHUNK))
		if not tree_chunks.has(key):
			tree_chunks[key] = []
		tree_chunks[key].append(t)
	_place_season()
	_place_nineties()


func _spline(ctrl: Array, closed: bool, step: float = 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := ctrl.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = ctrl[(i - 1 + n) % n] if (closed or i > 0) else ctrl[0]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n] if (closed or i + 2 < n) else ctrl[n - 1]
		# Catmull-Rom tangents scaled by neighbouring segment lengths, so short control legs
		# (the straight stubs at junctions) next to long ones don't overshoot into cusps.
		var d01 := p0.distance_to(p1)
		var d12 := p1.distance_to(p2)
		var d23 := p2.distance_to(p3)
		var m1 := (p2 - p0) * (d12 / maxf(d01 + d12, 0.001))
		var m2 := (p3 - p1) * (d12 / maxf(d12 + d23, 0.001))
		var steps := maxi(2, int(d12 / step))
		for k in steps:
			var t := k / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			pts.append((2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2)
	pts.append(ctrl[0] if closed else ctrl[n - 1])
	return pts


func _road(rname: String, ctrl: Array, closed: bool) -> void:
	var pts := _spline(ctrl, closed)
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		cum[i] = acc
	roads.append({"name": rname, "pts": pts, "cum": cum, "closed": closed, "len": acc})


## The road network is a graph: every road runs from one junction node to another (or meets the
## plaza / lake loops), so there are no dead ends anywhere in town.
func _make_roads() -> void:
	var ring: Array = []
	for i in 14:
		ring.append(_ring_pt(TAU * i / 14.0))
	_road("Plaza Loop", ring, true)
	var loop: Array = []
	for i in 18:
		loop.append(_lake_pt(TAU * i / 18.0))
	_road("Lakeshore Drive", loop, true)
	var n := {
		"g": Vector2(30, 34), "nw": Vector2(46, 50), "n": Vector2(70, 30), "ne": Vector2(96, 62), "e": Vector2(128, 86),
		"se": Vector2(110, 112), "s": Vector2(72, 124), "sw": Vector2(36, 112), "w": Vector2(26, 76), "fs": Vector2(100, 146),
		"fsw": Vector2(40, 146), "fe": Vector2(146, 120), "fne": Vector2(148, 64), "fnw": Vector2(12, 54), "n2": Vector2(50, 12),
		"rSE": _ring_pt(PI * 0.25), "rS": _ring_pt(PI * 0.5), "rW": _ring_pt(PI), "rNW": _ring_pt(-PI * 0.75), "rNE": _ring_pt(-0.6),
		"rN": _ring_pt(-PI * 0.5), "lSW": _lake_pt(2.45), "lN": _lake_pt(-PI * 0.5), "lS": _lake_pt(PI * 0.5), "lE": _lake_pt(0.0),
	}
	var edges := [
		["Valley Road", "rSE", "se", [Vector2(92, 96)]],
		["Pine Hollow Road", "rS", "s", [Vector2(68, 104)]],
		["Chalet Hill", "rW", "w", [Vector2(52, 70), Vector2(40, 82)]],
		["Gondola Way", "rNW", "nw", [Vector2(56, 60)]],
		["Lakeside Lane", "rNE", "ne", [Vector2(86, 66)]],
		["Village Hill Road", "rN", "n", [Vector2(76, 52), Vector2(66, 42)]],
		["Lakeshore Connector", "ne", "lSW", [Vector2(102, 58)]],
		["Summit Road", "n", "lN", [Vector2(88, 20), Vector2(104, 16)]],
		["Meadow Lane", "lS", "e", [Vector2(126, 72)]],
		["East Shore Road", "lE", "fne", [Vector2(148, 48)]],
		["Ridge Road", "fne", "e", [Vector2(142, 78)]],
		["Orchard Lane", "e", "se", [Vector2(122, 100)]],
		["Birch Bend", "e", "fe", [Vector2(142, 100)]],
		["Sunset Drive", "fe", "fs", [Vector2(128, 140)]],
		["Aspen Court", "se", "fs", [Vector2(100, 130)]],
		["Pine Hollow South", "s", "fs", [Vector2(86, 138)]],
		["Fern Gully Road", "s", "fsw", [Vector2(56, 136)]],
		["Hollow Lane", "s", "sw", [Vector2(52, 116)]],
		["Cedar Loop", "sw", "fsw", [Vector2(30, 130)]],
		["Woodland Trail", "sw", "w", [Vector2(22, 96)]],
		["Lookout Road", "w", "fnw", [Vector2(16, 66)]],
		["Old Mill Road", "fnw", "g", [Vector2(14, 40)]],
		["Gondola Spur", "g", "nw", [Vector2(36, 44)]],
		["Elk Run", "nw", "w", [Vector2(34, 62)]],
		["Summit Road West", "g", "n2", [Vector2(34, 18)]],
		["High Meadow Road", "n2", "n", [Vector2(62, 18)]],
		["Valley Bottom Road", "fsw", "fs", [Vector2(70, 152)]],
		["Forest Road", "nw", "n", [Vector2(56, 36)]],
	]
	# the junctions and bends above are in design tiles: out to the map's scale (the plaza / lake points already are)
	for key in n:
		if not (key as String).begins_with("r") and not (key as String).begins_with("l"):
			n[key] = n[key] * MAP_K
	for e in edges:
		e[3] = (e[3] as Array).map(func(v): return v * MAP_K)
	_square_junctions(n, edges)
	for e in edges:
		var ctrl: Array = [n[e[1]]]
		ctrl.append_array(e[3])
		ctrl.append(n[e[2]])
		_road(e[0], ctrl, false)


## Straightens the first few tiles of every road arm onto a cross aligned with the junction, so arms
## meet at right angles (a clean crossroads or T) and every exit reads as left / straight / right.
## The roads still wind freely between junctions; only two control points near each end are added.
func _square_junctions(n: Dictionary, edges: Array) -> void:
	var arms := {}   # node -> [[edge index, at end?, direction], ...]
	for ei in edges.size():
		var e: Array = edges[ei]
		var mids: Array = e[3]
		arms.get_or_add(e[1], []).append([ei, false, (mids[0] - n[e[1]]).normalized()])
		arms.get_or_add(e[2], []).append([ei, true, (mids[mids.size() - 1] - n[e[2]]).normalized()])
	for key in arms:
		var p: Vector2 = n[key]
		var list: Array = arms[key]
		var fixed: Array = []   # a plaza / lake loop running through the node holds two opposite arms
		for r in roads:
			if not r["closed"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			for k in pts.size():
				if pts[k].distance_to(p) < 1.5:
					var t: Vector2 = _road_at(r, r["cum"][k])[1]
					fixed = [t, -t]
					break
		if list.size() + fixed.size() < 3:
			continue
		var thetas: Array = []
		if fixed.is_empty():
			for deg in range(0, 90, 3):
				thetas.append(deg_to_rad(deg))
		else:
			thetas.append(fixed[0].angle())
		var best_cost := INF
		var best_dirs: Array = []
		for th in thetas:
			var free: Array = [0, 1, 2, 3]
			if not fixed.is_empty():
				free = [1, 3]
			for combo in _slot_combos(free, list.size()):
				var cost := 0.0
				var dirs: Array = []
				for i in list.size():
					var a: float = th + combo[i] * PI * 0.5
					cost += pow(angle_difference(list[i][2].angle(), a), 2.0)
					dirs.append(Vector2.from_angle(a))
				if cost < best_cost:
					best_cost = cost
					best_dirs = dirs
		for i in list.size():
			var mids: Array = edges[list[i][0]][3]
			var far: Vector2 = mids[mids.size() - 1] if list[i][1] else mids[0]
			var stub := minf(5.0, p.distance_to(far) * 0.45)
			var near: Vector2 = p + best_dirs[i] * stub * 0.45
			# the outer point already leans back toward the road's own heading, spreading the bend out
			var q: Vector2 = p + best_dirs[i].slerp((far - p).normalized(), 0.35) * stub
			if list[i][1]:
				mids.append_array([q, near])
			else:
				mids.insert(0, q)
				mids.insert(0, near)


## Every way of putting `k` arms into distinct slots from `free`.
func _slot_combos(free: Array, k: int) -> Array:
	if k == 0:
		return [[]]
	var out: Array = []
	for s in free:
		var rest := free.duplicate()
		rest.erase(s)
		for c in _slot_combos(rest, k - 1):
			out.append([s] + c)
	return out


func _lake_pt(a: float) -> Vector2:
	return LAKE + Vector2(cos(a), sin(a)) * (_lake_r(a) + 3.6)


## Finds where roads meet: every open road end that touches another road is a junction.
func _build_junctions() -> void:
	junctions.clear()
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		if r["closed"]:
			continue
		for end_s in [0.0, float(r["len"])]:
			var p: Vector2 = _road_at(r, end_s)[0]
			var best_road := -1
			var best_s := 0.0
			var best_d := 1e9
			for rj in roads.size():
				if rj == ri:
					continue
				var pts: PackedVector2Array = roads[rj]["pts"]
				var cum: PackedFloat32Array = roads[rj]["cum"]
				for k in pts.size():
					var d := p.distance_to(pts[k])
					if d < best_d:
						best_d = d
						best_road = rj
						best_s = cum[k]
			if best_d < 2.2:
				_add_junction(p.lerp(_road_at(roads[best_road], best_s)[0], 0.5), [[ri, end_s], [best_road, best_s]])
	road_js.clear()
	for ri in roads.size():
		road_js.append([])
	for ji in junctions.size():
		for l in junctions[ji]["links"]:
			road_js[l[0]].append([l[1], ji])
	for lst in road_js:
		lst.sort_custom(func(a, b): return a[0] < b[0])


func _add_junction(pos: Vector2, links: Array) -> void:
	for j in junctions:
		if j["pos"].distance_to(pos) < 2.5:
			for l in links:
				var dup := false
				for m in j["links"]:
					if m[0] == l[0] and absf(m[1] - l[1]) < 1.5:
						dup = true
				if not dup:
					j["links"].append(l)
			return
	junctions.append({"pos": pos, "links": links})


func _road_at(r: Dictionary, s: float) -> Array:
	var cum: PackedFloat32Array = r["cum"]
	var pts: PackedVector2Array = r["pts"]
	var length: float = r["len"]
	if r["closed"]:
		s = fposmod(s, length)
	else:
		s = clampf(s, 0.0, length)
	var i := clampi(cum.bsearch(s), 1, pts.size() - 1)
	var seg := cum[i] - cum[i - 1]
	var f := 0.0 if seg <= 0.0001 else (s - cum[i - 1]) / seg
	var t := pts[i] - pts[i - 1]
	return [pts[i - 1].lerp(pts[i], f), t.normalized() if t.length() > 0.0001 else Vector2.RIGHT]


## Distance from `p` to the nearest road centreline (exact, over all segments).
func road_dist(p: Vector2) -> float:
	var best := 1e9
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		for i in range(1, pts.size()):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])))
	return best


func _face_of(v: Vector2) -> int:
	if absf(v.x) >= absf(v.y):
		return 0 if v.x > 0.0 else 2
	return 1 if v.y > 0.0 else 3


func _lot_free(pos: Vector2, size: Vector2, gap: int) -> bool:
	var x0 := int(pos.x)
	var y0 := int(pos.y)
	var x1 := x0 + int(size.x)
	var y1 := y0 + int(size.y)
	for y in range(y0 - gap, y1 + gap):
		for x in range(x0 - gap, x1 + gap):
			if x < 2 or y < 2 or x >= N - 2 or y >= N - 2:
				return false
			var i := y * N + x
			if x >= x0 and x < x1 and y >= y0 and y < y1:
				if reserved[i] != 0 or not (tiles[i] == T.GRASS or tiles[i] == T.SIDEWALK) or road_d[i] < ROAD_HW + 0.9:
					return false
			elif reserved[i] == 2:
				return false
	return true


func _try_lot(p: Vector2, n: Vector2, size: Vector2, gap: int, need_visible: bool, road: int, s: float) -> Dictionary:
	for extra in [0.9, 1.4, 1.9]:
		var depth := absf(n.x) * size.x + absf(n.y) * size.y
		var c: Vector2 = p + n * (ROAD_HW + extra + depth * 0.5)
		var pos := (c - size * 0.5).round()
		var face := _face_of(p - (pos + size * 0.5))
		if need_visible and face > 1:
			continue
		if _lot_free(pos, size, gap):
			return {"pos": pos, "size": size, "face": face, "door": p + n * (ROAD_HW + 0.45), "road": road, "s": s}
	return {}


func _next_name(kind: String) -> String:
	var list: Array = SHOP_NAMES if kind == "shop" else HOTEL_NAMES
	var i: int = _name_i[kind]
	_name_i[kind] = i + 1
	var nm: String = list[i % list.size()]
	return nm if i < list.size() else nm + " II"


func _add_building(lot: Dictionary, kind: String, bname: String, accent: Color = Color.WHITE) -> int:
	var pos: Vector2 = lot["pos"]
	var size: Vector2 = lot["size"]
	var b := {"pos": pos, "size": size, "kind": kind, "face": lot["face"], "door": lot["door"], "accent": accent, "road": lot["road"], "s": lot["s"],
		"key": pos.x + pos.y + (size.x + size.y) * 0.5, "ridge_x": size.x >= size.y, "roof_h": 0.0}
	match kind:
		"shop":
			b["h"] = rng.randf_range(24.0, 38.0)
			b["col"] = WALLS[rng.randi() % WALLS.size()]
			b["accent"] = PIZZA_COLORS[rng.randi() % PIZZA_COLORS.size()]
			b["name"] = _next_name("shop")
		"hotel":
			b["h"] = rng.randf_range(62.0, 104.0)
			b["col"] = WALLS[rng.randi() % WALLS.size()]
			b["roof"] = ROOFS[rng.randi() % ROOFS.size()]
			b["roof_h"] = 22.0
			b["name"] = _next_name("hotel")
		"chalet":
			b["h"] = rng.randf_range(18.0, 26.0)
			b["col"] = WOOD[rng.randi() % WOOD.size()]
			b["roof"] = ROOFS[rng.randi() % ROOFS.size()]
			b["roof_h"] = 16.0
			b["name"] = "Chalet #%d" % rng.randi_range(2, 199)
		"condo":
			b["h"] = rng.randf_range(34.0, 46.0)
			b["col"] = WALLS[rng.randi() % WALLS.size()]
			b["roof"] = ROOFS[rng.randi() % ROOFS.size()]
			b["roof_h"] = 14.0
			b["name"] = "%s Condos" % ["Pinecone", "Bluebird", "Fireside", "Trailview", "Hilltop", "Snowberry"][rng.randi() % 6]
		"pizza":
			b["h"] = 40.0
			b["col"] = Color(0.98, 0.94, 0.85)
		"bike":
			b["h"] = 38.0
			b["col"] = Color(0.35, 0.6, 0.95)
		"er":
			b["h"] = 62.0
			b["col"] = Color(0.96, 0.97, 1.0)
		"race":
			b["h"] = 30.0
			b["col"] = Color(0.2, 0.2, 0.26)
		"gondola":
			b["h"] = 30.0
			b["col"] = Color(0.6, 0.42, 0.3)
			b["roof"] = Color(0.3, 0.32, 0.42)
			b["roof_h"] = 18.0
		"site":
			b["h"] = 48.0
			b["col"] = Color(0.75, 0.45, 0.3)
		"townhall":
			b["h"] = 52.0
			b["col"] = Color(0.95, 0.9, 0.78)
			b["roof"] = Color(0.75, 0.28, 0.22)
			b["roof_h"] = 18.0
	if bname != "":
		b["name"] = bname
	var idx := buildings.size()
	buildings.append(b)
	for y in range(int(pos.y), int(pos.y + size.y)):
		for x in range(int(pos.x), int(pos.x + size.x)):
			solid[y * N + x] = 1
			reserved[y * N + x] = 2
	if kind == "site":
		site_spot = spots.size()
	if kind in ["shop", "hotel", "chalet", "condo", "site"]:
		spots.append({"pos": lot["door"], "name": b["name"], "b": idx, "road": lot["road"], "s": lot["s"]})
	return idx


func _hatch(b: Dictionary) -> Vector2:
	var pos: Vector2 = b["pos"]
	var size: Vector2 = b["size"]
	match b["face"]:
		0:
			return Vector2(pos.x + size.x, pos.y + size.y * 0.5)
		1:
			return Vector2(pos.x + size.x * 0.5, pos.y + size.y)
	return pos + size * 0.5


func _place_specials() -> void:
	var specials := [
		["pizza", "Slice of Heaven", Vector2(84, 76), Vector2(3, 3)],
		["pizza", "Crust Bucket", Vector2(112, 106), Vector2(3, 3)],
		["pizza", "Mama Mia Mountain Pies", Vector2(98, 58), Vector2(3, 3)],
		["pizza", "Pie in the Sky", Vector2(52, 56), Vector2(3, 3)],
		["pizza", "The Cheesy Chairlift", Vector2(72, 130), Vector2(3, 3)],
		["pizza", "Dough Ray Me", Vector2(138, 96), Vector2(3, 3)],
		["pizza", "Pepperoni Peak", Vector2(24, 100), Vector2(3, 3)],
		["bike", "Spokes & Stuff", Vector2(62, 88), Vector2(3, 3)],
		["bike", "Gravel Gods Cycles", Vector2(126, 96), Vector2(3, 3)],
		["er", "St. Pedro's Hospital", Vector2(96, 92), Vector2(3, 3)],
		["race", "Mt. Crankmore Race HQ", Vector2(30, 42), Vector2(3, 3)],
		["gondola", "Gondola Base", Vector2(24, 28), Vector2(3, 3)],
		["townhall", "Mt. Crankmore Town Hall", Vector2(81, 67), Vector2(3, 3)],
		["site", "Crankmore Heights", Vector2(46, 66), Vector2(3, 3)],
	]
	var pizza_i := 0
	for sp in specials:
		var target: Vector2 = sp[2] * MAP_K   # (design tiles)
		var cands: Array = []
		for ri in roads.size():
			var r: Dictionary = roads[ri]
			var length: float = r["len"]
			var s := 0.0
			while s < length:
				var at := _road_at(r, s)
				var p: Vector2 = at[0]
				var d := p.distance_to(target)
				if d < 9.0:
					cands.append([d, p, at[1], ri, s])
				s += 0.5
		cands.sort_custom(func(a, b): return a[0] < b[0])
		var lot := {}
		for need_vis in [true, false]:
			for c in cands:
				var tv: Vector2 = c[2]
				var n := Vector2(-tv.y, tv.x)
				for side in [1.0, -1.0]:
					lot = _try_lot(c[1], n * side, sp[3], 1, need_vis, c[3], c[4])
					if not lot.is_empty():
						break
				if not lot.is_empty():
					break
			if not lot.is_empty():
				break
		if lot.is_empty():
			push_warning("could not place " + str(sp[1]))
			continue
		var kind: String = sp[0]
		var accent: Color = PIZZA_COLORS[pizza_i % PIZZA_COLORS.size()] if kind == "pizza" else Color.WHITE
		var bi := _add_building(lot, kind, sp[1], accent)
		var b: Dictionary = buildings[bi]
		match kind:
			"pizza":
				var hatch := _hatch(b)
				var w: Vector2 = lot["door"]
				# the pizza man waits on the pavement between the window and the road
				shops.append({"b": bi, "window": w, "hatch": hatch, "name": sp[1], "color": accent, "road": lot["road"], "s": lot["s"],
					"chef": w + (hatch - w).normalized() * 0.4})
				pizza_i += 1
			"bike", "er", "race":
				zones.append({"pos": lot["door"], "r": 3.0, "kind": kind, "road": lot["road"], "s": lot["s"]})
			"gondola":
				gondola_top = b["pos"] + b["size"] * 0.5


func _pick_kind(p: Vector2) -> Array:
	var r := rng.randf()
	if p.distance_to(PLAZA) < 22.0 * MAP_K:
		if r < 0.78:
			return ["shop", Vector2(2, 2)]
		return ["hotel", Vector2(3, 3)]
	if p.distance_to(LAKE) < 26.0 * MAP_K or p.distance_to(BASE) < 15.0 * MAP_K:
		if r < 0.5:
			return ["hotel", Vector2(3, 3)]
		if r < 0.75:
			return ["condo", [Vector2(3, 2), Vector2(2, 3)][rng.randi() % 2]]
		return ["shop", Vector2(2, 2)]
	if r < 0.8:
		return ["chalet", Vector2(2, 2)]
	return ["condo", [Vector2(3, 2), Vector2(2, 3)][rng.randi() % 2]]


func _place_generic() -> void:
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var length: float = r["len"]
		var s := 1.0
		while s < length - 1.0:
			var at := _road_at(r, s)
			var p: Vector2 = at[0]
			var tv: Vector2 = at[1]
			var n := Vector2(-tv.y, tv.x)
			var core := p.distance_to(PLAZA) < 22.0 * MAP_K
			for side in [1.0, -1.0]:
				var pick := _pick_kind(p)
				var lot := _try_lot(p, n * side, pick[1], 0 if core else 1, false, ri, s)
				if not lot.is_empty():
					_add_building(lot, pick[0], "")
			s += 2.0 if core else 3.2


func _make_tree(p: Vector2, scale_: float = 1.0) -> Dictionary:
	var kind := rng.randi() % 5
	return {"pos": p, "s": scale_ * rng.randf_range(0.8, 1.2), "kind": kind}


func _place_nature() -> void:
	for y in N:
		for x in N:
			var i := y * N + x
			var prob := 0.0
			if tiles[i] == T.FOREST:
				prob = 0.6
			elif tiles[i] == T.GRASS and reserved[i] == 0 and road_d[i] > ROAD_HW + 1.4:
				var near_building := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var xx := x + dx
						var yy := y + dy
						if xx >= 0 and yy >= 0 and xx < N and yy < N and reserved[yy * N + xx] == 2:
							near_building = true
				if near_building:
					continue
				prob = clampf((Vector2(x, y).distance_to(PLAZA) - 12.0 * MAP_K) / (50.0 * MAP_K), 0.03, 0.3)
			if prob > 0.0 and rng.randf() < prob:
				trees.append(_make_tree(Vector2(x + rng.randf_range(0.2, 0.8), y + rng.randf_range(0.2, 0.8))))
	for y in range(-MARGIN, N + MARGIN):
		for x in range(-MARGIN, N + MARGIN):
			if x >= 0 and x < N and y >= 0 and y < N:
				continue
			if rng.randf() < 0.42:
				trees.append(_make_tree(Vector2(x + rng.randf(), y + rng.randf()), 1.25))
	# street lamps: both sides around the plaza and through the village, then one every ~10 m on alternate
	# sides out along the roads
	for r in roads:
		var s := 1.0
		var k := 0
		while s < float(r["len"]):
			var at := _road_at(r, s)
			var p: Vector2 = at[0]
			var village := p.distance_to(PLAZA) < 24.0 * MAP_K
			k += 1
			if village or k % 3 == 0:
				var tv: Vector2 = at[1]
				var n := Vector2(-tv.y, tv.x)
				for side in ([1.0, -1.0] if village else [1.0 if k % 6 == 0 else -1.0]):
					var lp: Vector2 = p + n * side * (ROAD_HW + 0.24)   # on the kerb, clear of the pavement people walk along
					var ix := int(lp.x)
					var iy := int(lp.y)
					if ix >= 0 and iy >= 0 and ix < N and iy < N and reserved[iy * N + ix] != 2 and _road_dist(lp) > ROAD_HW + 0.18:
						props.append({"kind": "lamp", "pos": lp})
			s += 3.5
	# beach umbrellas on the west shore
	for k in 6:
		var a := 2.0 + k * 0.32
		props.append({"kind": "umbrella", "pos": LAKE + Vector2(cos(a), sin(a)) * (_lake_r(a) + 0.9), "col": PIZZA_COLORS[k % PIZZA_COLORS.size()], "season": "summer"})


# ---- seasonal scenery (see Season) -------------------------------------------------

## Open grass for a bit of seasonal scenery: off the road (but at most `road_max` from one, so riders see it),
## clear of buildings, trees and the other scenery.
func _open_spot(p: Vector2, road_max: float, taken: Array) -> bool:
	var ix := floori(p.x)
	var iy := floori(p.y)
	if ix < 1 or iy < 1 or ix >= N - 1 or iy >= N - 1:
		return false
	var i := iy * N + ix
	if tiles[i] != T.GRASS or reserved[i] != 0 or solid[i] != 0 or road_d[i] < ROAD_HW + 0.7 or road_d[i] > road_max:
		return false
	for k in range(1, 4):   # a building just in front (towards the camera) would hide it
		var fx := mini(ix + k, N - 1)
		var fy := mini(iy + k, N - 1)
		if reserved[fy * N + fx] == 2 or reserved[iy * N + fx] == 2 or reserved[fy * N + ix] == 2:
			return false
	for t in tree_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), []):
		if t["pos"].distance_squared_to(p) < 1.2:
			return false
	for q in taken:
		if q.distance_squared_to(p) < 6.0:
			return false
	return true


## The 90s on the high street: a payphone, paper box or vending machine by the shop doors, neon outside the pizza
## places, CRTs and an arcade cabinet outside the video and games shops, inflatable tube men flailing outside a few
## shops (always the mall), satellite dishes by the chalets, and a hoop and a skate ramp on the grass where kids hang out.
const KERB_90S := ["payphone", "newspaper_box", "mailbox_blue", "vending_machine", "phone_booth", "bike_rack", "newspaper_box", "payphone"]
const SHOP_90S := {"Rewind Video": ["crt_tv_stack", "neon_sign_open"], "Pixel Palace": ["arcade_cabinet", "neon_sign_open"],
	"Track 9 Records": ["boombox", "neon_sign_open"], "Mega Mall": ["vending_machine", "payphone"]}

func _place_nineties() -> void:
	var sr := RandomNumberGenerator.new()
	sr.seed = 1990
	var taken: Array = props.map(func(e): return e["pos"])
	var tubes := 0
	for b in buildings:
		var kind: String = b["kind"]
		if kind == "chalet" and sr.randf() < 0.3:
			# in the yard beside the chalet, on whichever side is clear of the road
			for dp in [b["pos"] + Vector2(b["size"].x + 0.35, 0.35), b["pos"] + Vector2(0.35, b["size"].y + 0.35), b["pos"] + Vector2(-0.35, 0.35)]:
				if _kerb_free(dp, taken, ROAD_HW + 0.9):
					props.append({"kind": "90s", "art": "satellite_dish", "pos": dp, "flip": sr.randf() < 0.5})
					taken.append(dp)
					break
			continue
		if not kind in ["shop", "pizza", "bike"] or int(b.get("road", -1)) < 0:
			continue
		var r: Dictionary = roads[b["road"]]
		var at := _road_at(r, float(b["s"]))
		var tv: Vector2 = at[1]
		var sgn := signf(Vector2(-tv.y, tv.x).dot(Vector2(b["door"]) - Vector2(at[0])))
		var name_: String = str(b.get("name", ""))
		var arts: Array = []
		if SHOP_90S.has(name_):
			arts = SHOP_90S[name_].duplicate()
		elif kind == "pizza":
			arts = ["neon_sign_pizza"]
		elif sr.randf() < 0.5:
			arts = [KERB_90S[sr.randi() % KERB_90S.size()]]
		# a tube man on the pavement beside the door, where the camera can see it (not behind the shop)
		if kind == "shop" and int(b["face"]) <= 1 and (name_ == "Mega Mall" or (tubes < 4 and sr.randf() < 0.1)):
			arts.append("tube")
		var sides := [1.0, -1.0] if sr.randf() < 0.5 else [-1.0, 1.0]
		for k in arts.size():
			var ds: float = sides[k % 2] * (1.1 + 0.9 * float(k / 2))
			var on := _road_at(r, clampf(float(b["s"]) + ds, 0.0, float(r["len"])))
			var t2: Vector2 = on[1]
			var pp: Vector2 = Vector2(on[0]) + Vector2(-t2.y, t2.x) * sgn * (ROAD_HW + 0.7)
			if not _kerb_free(pp, taken, ROAD_HW + 0.5):
				continue
			if arts[k] == "tube":
				props.append({"kind": "tube", "pos": pp, "ph": sr.randf() * 3.0})
				tubes += 1
			else:
				props.append({"kind": "90s", "art": arts[k], "pos": pp, "flip": sr.randf() < 0.5})
			taken.append(pp)
	# the hangouts: a hoop with a boombox on the ground, a quarter pipe
	var spots := _season_spots(sr, 2, 6.0, 30.0, 3.0)
	if spots.size() > 0:
		props.append({"kind": "90s", "art": "basketball_hoop", "pos": spots[0]})
		props.append({"kind": "90s", "art": "boombox", "pos": spots[0] + Vector2(0.9, 0.6)})
	if spots.size() > 1:
		props.append({"kind": "90s", "art": "skate_ramp", "pos": spots[1], "flip": true})


## A free bit of pavement or grass: in the town, off the road (at least `road_min` from its middle), not under a
## building and not on top of other scenery.
func _kerb_free(p: Vector2, taken: Array, road_min: float) -> bool:
	var ix := floori(p.x)
	var iy := floori(p.y)
	if ix < 0 or iy < 0 or ix >= N or iy >= N:
		return false
	var i := iy * N + ix
	if reserved[i] == 2 or solid[i] != 0 or road_d[i] < road_min or tiles[i] == T.WATER or _road_dist(p) < road_min:
		return false
	for q in taken:
		if q.distance_squared_to(p) < 0.8:
			return false
	return true


## Distance from `p` to the middle of the nearest road (exact, unlike road_d, which is per tile).
func _road_dist(p: Vector2) -> float:
	var best := 99.0
	for r in roads:
		for q in r["pts"]:
			best = minf(best, p.distance_to(q))
	return best


## Finds a clear spot near each LIFT_BASES point for a bottom station and runs the lift line from there straight up
## the screen (world -x -y) to the edge of the map: towers every 6 tiles where the ground is free, trees cleared.
## The kid who plays in a leaf pile, round and round: stands beside it, runs at it, dives in and disappears under a
## burst of leaves, bursts back out cheering, then walks back to the start.
const LEAF_KIDS := ["kid", "bucket_hat_kid", "skater_kid", "norm_boy_kid", "scout", "norm_teen_girl"]
func _draw_leaf_kid(e: Dictionary, b: Vector2) -> void:
	var kid: Dictionary = e["kid"]
	var look := Sprites.cast(kid, LEAF_KIDS.filter(func(d): return Sprites.sheet("ped_%s_walk" % d) != null))
	var c := fposmod(t_ + float(e["ph"]) * 2.0, 8.0)
	var home := Vector2(-26, 6)   # screen offset of where they stand, beside the pile
	var leaves := -1.0            # seconds into a burst of leaves
	if look != "":
		var to_pile := (-home).normalized()
		var w := Iso.to_world(to_pile)   # world direction they face running at the pile
		if c < 3.0:
			Sprites.draw_person(self, "ped_%s_walk" % look, b + home, w, 0.0, 0.0)
		elif c < 3.7:
			Sprites.draw_person(self, "ped_%s_walk" % look, b + home.lerp(Vector2(-6, 2), (c - 3.0) / 0.7), w, c, 14.0)
		elif c < 4.2:
			var u := (c - 3.7) / 0.5   # the dive: up and into the pile
			Sprites.draw_person(self, "ped_%s_walk" % look, b + Vector2(-6, 2).lerp(Vector2(0, 4), u) + Vector2(0, -sin(u * PI) * 12.0), w, 1.0, 0.0)
		elif c < 5.4:
			leaves = c - 4.2   # under the leaves
		elif c < 6.4:
			Sprites.draw_cheer(self, "ped_%s_cheer" % look, b + Vector2(0, 3), c - 5.4)
			leaves = c - 4.2
		else:
			Sprites.draw_person(self, "ped_%s_walk" % look, b + Vector2(0, 3).lerp(home, (c - 6.4) / 1.6), Iso.to_world(home.normalized()), c, 8.0)
	if leaves >= 0.0:
		for k in 12:
			var hk := int(e["sd"]) * 13 + k * 7
			var u := fposmod(leaves * 0.8 + k / 12.0, 1.0)
			var q := b + Vector2(float(hk % 25) - 12.0 + sin(u * 6.0 + k) * 4.0, -2.0 - sin(u * PI) * (10.0 + float(hk % 9)))
			draw_rect(Rect2(q.round(), Vector2(2, 1)), Season.FALL_LEAVES[hk % 4])


func _place_lifts() -> void:
	for li in LIFT_BASES.size():
		var want: Vector2 = LIFT_BASES[li] * MAP_K
		var base := Vector2.INF
		for r in range(0, 8):
			for k in 16:
				var q := want + Vector2.from_angle(TAU * k / 16.0) * r
				var i := clampi(int(q.y), 0, N - 1) * N + clampi(int(q.x), 0, N - 1)
				if reserved[i] == 0 and solid[i] == 0 and road_d[i] > ROAD_HW + 1.5 and tiles[i] != T.WATER:
					base = q.floor() + Vector2(0.5, 0.5)
					break
			if base != Vector2.INF:
				break
		if base == Vector2.INF:
			continue
		var line: Array = []
		var up := Vector2(-1, -1).normalized()
		var q := base
		while q.x > -2.0 and q.y > -2.0:
			line.append(q)
			q += up
		lifts.append({"base": base, "line": line, "summit": LIFT_SUMMITS[li], "pts": PackedVector2Array(), "len": 0.0})
		props.append({"kind": "lift_station", "pos": base})
		for k in range(4, line.size(), 6):
			var tq: Vector2 = line[k]
			var ti := clampi(int(tq.y), 0, N - 1) * N + clampi(int(tq.x), 0, N - 1)
			if tq.x < 0.0 or tq.y < 0.0 or (reserved[ti] != 2 and road_d[ti] > ROAD_HW + 0.5):
				props.append({"kind": "lift_tower", "pos": tq})
		trees = trees.filter(func(t): return not line.any(func(lq): return (lq as Vector2).distance_to(t["pos"]) < 1.1))


## The cable's screen points (needs the terrain on) and its length, worked out once.
func _lift_cable(l: Dictionary) -> PackedVector2Array:
	if l["pts"].is_empty():
		var pts := PackedVector2Array()
		for q in l["line"]:
			pts.append(Iso.to_screen(q, LIFT_Z))
		pts.append(l["summit"])
		var length := 0.0
		for i in range(1, pts.size()):
			length += pts[i - 1].distance_to(pts[i])
		l["pts"] = pts
		l["len"] = length
	return l["pts"]


## The point `d` px along a polyline.
func _along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if d <= seg:
			return pts[i - 1].lerp(pts[i], d / maxf(seg, 0.001))
		d -= seg
	return pts[pts.size() - 1]


## The lift cables and chairs (people riding up, empty chairs coming down), over everything like the gondola.
func _draw_lifts(vr: Rect2) -> void:
	var view := vr.grow_individual(80.0, 120.0, 80.0, 60.0)   # (the chairs hang well below the cable)
	for l in lifts:
		var pts := _lift_cable(l)
		var down := PackedVector2Array()
		for q in pts:
			down.append(q + Vector2(12, 3))
		draw_polyline(pts, Color(0.15, 0.15, 0.2, 0.9), 1.0)
		draw_polyline(down, Color(0.15, 0.15, 0.2, 0.9), 1.0)
		var length: float = l["len"]
		var n := int(length * 2.0 / LIFT_CHAIR_GAP)
		for k in n:
			var u := fposmod(t_ * LIFT_SPEED_PX + k * LIFT_CHAIR_GAP, length * 2.0)
			var going_up := u < length
			var p := _along(pts, u) if going_up else _along(pts, length * 2.0 - u) + Vector2(12, 3)
			if not view.has_point(p):
				continue
			draw_line(p, p + Vector2(0, 10), Color(0.2, 0.2, 0.25), 1.0)
			Sprites.draw_vehicle(self, "obj_chairlift_chair_riders" if going_up else "obj_chairlift_chair", p + Vector2(0, 26), Vector2(-1, -1) if going_up else Vector2(1, 1))


func _season_spots(sr: RandomNumberGenerator, n: int, rmin: float, rmax: float, road_max: float) -> Array:
	var taken: Array = season_props.map(func(e): return e["pos"])
	var out: Array = []
	for tries in n * 80:
		if out.size() >= n:
			break
		var a := sr.randf() * TAU
		var p := PLAZA + Vector2(cos(a), sin(a)) * sr.randf_range(rmin, rmax) * MAP_K
		if _open_spot(p, road_max, taken):
			out.append(p)
			taken.append(p)
	return out


## A townsperson who stands still (games, kites); drawn with _draw_ped.
func _bystander(sr: RandomNumberGenerator, pos: Vector2) -> Dictionary:
	var shirts := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(1.0, 0.85, 0.2), Color(0.4, 0.85, 0.4), Color(0.95, 0.55, 0.85), Color(1, 1, 1)]
	return {"pos": pos, "col": shirts[sr.randi() % shirts.size()], "hair": [Color(0.3, 0.2, 0.1), Color(0.9, 0.75, 0.3), Color(0.1, 0.1, 0.1)][sr.randi() % 3],
		"skin": [Color(0.96, 0.8, 0.65), Color(0.85, 0.62, 0.45), Color(0.62, 0.42, 0.3)][sr.randi() % 3], "phase": 0.0, "cheer": 0.0,
		"giver": false, "gcool": 0.0, "shout": ""}


const WINTER_SKIERS := 50   # skiers on the town's hills in winter


func _place_season() -> void:
	var sr := RandomNumberGenerator.new()
	sr.seed = 1717
	var jackets := [Color(0.95, 0.25, 0.25), Color(0.2, 0.55, 0.95), Color(1.0, 0.8, 0.15), Color(0.3, 0.8, 0.45), Color(0.85, 0.35, 0.85), Color(1.0, 0.55, 0.15)]
	# winter: snowmen by the roads, skiers down the hills, skaters on the frozen lake
	for p in _season_spots(sr, 26, 7.0, 62.0, 4.0):
		season_props.append({"season": "winter", "kind": "snowman", "pos": p, "sd": sr.randi() % 100})
	var skiers := 0
	for p in _season_spots(sr, 260, 8.0, 76.0, 99.0):
		if skiers >= WINTER_SKIERS:
			break
		var g := Vector2(height_m(p + Vector2(0.5, 0)) - height_m(p - Vector2(0.5, 0)), height_m(p + Vector2(0, 0.5)) - height_m(p - Vector2(0, 0.5)))
		if g.length() < 0.08:
			continue
		var dir := -g.normalized()
		var run := sr.randf_range(5.0, 8.0)
		var clear := true
		for k in 7:
			var q: Vector2 = p + dir * run * k / 6.0
			var qi := clampi(int(q.y), 0, N - 1) * N + clampi(int(q.x), 0, N - 1)
			if road_d[qi] < ROAD_HW + 0.4 or solid[qi] != 0 or tiles[qi] == T.WATER or reserved[qi] == 2:
				clear = false
		if clear:
			season_props.append({"season": "winter", "kind": "skier", "pos": p, "origin": p, "dir": dir, "run": run,
				"ph": sr.randf(), "speed": sr.randf_range(0.10, 0.16), "col": jackets[sr.randi() % jackets.size()]})
			skiers += 1
	for k in 7:
		season_props.append({"season": "winter", "kind": "skater", "pos": LAKE, "a0": sr.randf() * TAU, "rf": sr.randf_range(0.25, 0.75),
			"w": sr.randf_range(0.12, 0.25) * (1.0 if k % 2 == 0 else -1.0), "col": jackets[k % jackets.size()]})
	# fall: pumpkins, leaf piles (with kids jumping in), scarecrows out in the fields
	for p in _season_spots(sr, 30, 6.0, 60.0, 3.5):
		season_props.append({"season": "fall", "kind": "pumpkins", "pos": p, "n": 1 + sr.randi() % 3, "sd": sr.randi() % 100})
	for p in _season_spots(sr, 14, 8.0, 55.0, 4.0):
		season_props.append({"season": "fall", "kind": "leafpile", "pos": p, "sd": sr.randi() % 100, "ph": sr.randf() * 5.0,
			"kid": _bystander(sr, p + Vector2(0.15, 0.15))})
	for p in _season_spots(sr, 5, 30.0, 70.0, 99.0):
		season_props.append({"season": "fall", "kind": "scarecrow", "pos": p, "col": jackets[sr.randi() % jackets.size()]})
	# spring: tulip beds, butterflies, duck families on the lake
	for p in _season_spots(sr, 24, 6.0, 55.0, 3.5):
		season_props.append({"season": "spring", "kind": "flowers", "pos": p, "sd": sr.randi() % 100})
	for p in _season_spots(sr, 26, 6.0, 60.0, 6.0):
		season_props.append({"season": "spring", "kind": "butterfly", "pos": p, "origin": p, "ph": sr.randf() * TAU,
			"col": [Color(1.0, 0.85, 0.2), Color(1.0, 0.55, 0.8), Color(0.55, 0.75, 1.0), Color(1, 1, 1), Color(1.0, 0.6, 0.2)][sr.randi() % 5]})
	for k in 2:
		season_props.append({"season": "spring", "kind": "ducks", "pos": LAKE, "a0": sr.randf() * TAU, "rf": sr.randf_range(0.35, 0.7),
			"w": 0.08 * (1.0 if k == 0 else -1.0)})
	# summer: people playing catch and frisbee, flying kites, picnics, beach volleyball
	var grass_at := func(q: Vector2) -> bool:
		var qi := clampi(int(q.y), 0, N - 1) * N + clampi(int(q.x), 0, N - 1)
		return tiles[qi] == T.GRASS and solid[qi] == 0 and reserved[qi] != 2 and road_d[qi] > ROAD_HW + 0.4
	for p in _season_spots(sr, 120, 8.0, 55.0, 7.0):
		if season_props.filter(func(e): return e["kind"] == "catch").size() >= 8:
			break
		var axis := Vector2.from_angle(sr.randf() * TAU)
		if not (grass_at.call(p + axis * 1.4) and grass_at.call(p - axis * 1.4)):
			continue
		season_props.append({"season": "summer", "kind": "catch", "pos": p, "axis": axis, "ph": sr.randf(), "frisbee": sr.randf() < 0.5,
			"a": _bystander(sr, p - axis * 1.4), "b": _bystander(sr, p + axis * 1.4)})
	for p in _season_spots(sr, 6, 12.0, 60.0, 8.0):
		season_props.append({"season": "summer", "kind": "kite", "pos": p, "ph": sr.randf() * TAU, "who": _bystander(sr, p),
			"col": [Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.5, 0.9, 0.4)][sr.randi() % 4]})
	for p in _season_spots(sr, 7, 8.0, 50.0, 5.0):
		season_props.append({"season": "summer", "kind": "picnic", "pos": p, "col": PIZZA_COLORS[sr.randi() % PIZZA_COLORS.size()],
			"a": _bystander(sr, p + Vector2(-0.45, 0.2)), "b": _bystander(sr, p + Vector2(0.25, -0.45))})
	for k in 40:
		var a := 3.8 + k * 0.06
		var p := LAKE + Vector2(cos(a), sin(a)) * (_lake_r(a) + 0.9)
		var ix := int(p.x)
		var iy := int(p.y)
		if ix >= 0 and iy >= 0 and ix < N and iy < N and tiles[iy * N + ix] == T.SAND and road_d[iy * N + ix] > ROAD_HW + 1.5:
			var t := Vector2(-sin(a), cos(a))
			var team := []
			for j in 4:
				team.append(_bystander(sr, p + t * (-1.3 if j < 2 else 1.3) + Vector2(cos(a), sin(a)) * (0.35 if j % 2 == 0 else -0.35)))
			season_props.append({"season": "summer", "kind": "volley", "pos": p, "t": t, "n": Vector2(cos(a), sin(a)), "team": team})
			break


## Where a bit of seasonal scenery is right now (most stand still; skiers, skaters, butterflies and ducks move).
func _sprop_pos(e: Dictionary) -> Vector2:
	match e["kind"]:
		"skier":
			return _skier_at(e, float(e.get("u", e["ph"])))
		"skater", "ducks":
			var a: float = e["a0"] + t_ * float(e["w"])
			return LAKE + Vector2(cos(a), sin(a)) * _lake_r(a) * float(e["rf"])
		"butterfly":
			var ph: float = e["ph"]
			return e["origin"] + Vector2(cos(t_ * 0.6 + ph) * 1.6, sin(t_ * 0.9 + ph * 1.3) * 1.1)
	return e["pos"]


## Where a skier is `u` of the way down their run (weaving from side to side).
func _skier_at(e: Dictionary, u: float) -> Vector2:
	var d: Vector2 = e["dir"]
	return e["origin"] + d * float(e["run"]) * u + Vector2(-d.y, d.x) * sin(u * TAU * 3.0) * 0.7


func _draw_sprop(e: Dictionary, at: Vector2) -> void:
	var b := Iso.to_screen(at)
	match e["kind"]:
		"snowman":
			Season.snowman(self, b, e["sd"])
		"skier":
			var u: float = e.get("u", e["ph"])
			var d: Vector2 = e["dir"]
			var vel: Vector2 = d * float(e["run"]) + Vector2(-d.y, d.x) * cos(u * TAU * 3.0) * 0.7 * TAU * 3.0
			var sk := Sprites.cast(e, Sprites.skiers())
			if sk != "":   # (stood still at the bottom of the run, waiting for the lift)
				Sprites.draw_person(self, "ped_%s_ski" % sk, b, vel, t_ if u < 1.0 else 0.0, 8.0 if u < 1.0 else 0.0, Color.WHITE, e)
		"skater":
			var a: float = e["a0"] + t_ * float(e["w"])
			var tan := Vector2(-sin(a), cos(a)) * signf(e["w"])
			var sd := Sprites.cast(e)   # townsfolk out skating, gliding in one stride
			if sd != "":
				Sprites.draw_person(self, "ped_%s_walk" % sd, b, tan, 0.25 + 0.25 * float(int(t_ * 0.8 + float(e["a0"]) * 3.0) % 2), 8.0, Color.WHITE, e)
		"pumpkins":
			for k in int(e["n"]):
				Season.pumpkin(self, b + Vector2(k * 7.0 - (int(e["n"]) - 1) * 3.5, (k % 2) * 3.0), 1.3 if k == 0 else 0.9, int(e["sd"]) + k)
		"leafpile":
			Season.leaf_pile(self, b, e["sd"])
			_draw_leaf_kid(e, b)
		"scarecrow":
			Sprites.draw_image(self, "scenery_scarecrow", b)
		"flowers":
			Season.flower_bed(self, b, e["sd"])
		"butterfly":
			Season.butterfly(self, b + Vector2(0, -10.0 - sin(t_ * 2.0 + float(e["ph"])) * 4.0), e["col"], t_ * 14.0 + float(e["ph"]))
		"ducks":
			var a0: float = e["a0"] + t_ * float(e["w"])
			var ahead := a0 + 0.05 * signf(e["w"])
			var facing := 1.0 if (Iso.to_screen(LAKE + Vector2(cos(ahead), sin(ahead)) * _lake_r(ahead) * float(e["rf"])) - b).x > 0.0 else -1.0
			for k in range(4, -1, -1):
				var a := a0 - float(k) * 0.045 * signf(e["w"])
				var q := Iso.to_screen(LAKE + Vector2(cos(a), sin(a)) * _lake_r(a) * float(e["rf"])) + Vector2(0, sin(t_ * 3.0 + k) * 0.6)
				Season.duck(self, q, facing, k > 0)
		"catch":
			var u := fposmod(t_ * 0.45 + float(e["ph"]), 2.0)
			var there := u < 1.0
			var f := u if there else u - 1.0
			var pa: Vector2 = e["pos"] - e["axis"] * 1.4
			var pb: Vector2 = e["pos"] + e["axis"] * 1.4
			for who in ["a", "b"]:
				var pp: Dictionary = e[who]
				var catching: bool = (who == "b" and there and f > 0.85) or (who == "a" and not there and f > 0.85)
				pp["cheer"] = 1.0 if catching else 0.0
				pp["phase"] = 1.3 if catching else 0.0
				_draw_ped(pp)
			var from := pa if there else pb
			var to := pb if there else pa
			var ball := Iso.to_screen(from.lerp(to, f)) + Vector2(0, -16.0 - sin(f * PI) * 22.0)
			if e["frisbee"]:
				draw_rect(Rect2(ball + Vector2(-3, -1), Vector2(6, 2)), Color(1.0, 0.3, 0.2))
				draw_rect(Rect2(ball + Vector2(-2, -2), Vector2(4, 1)), Color(1.0, 0.6, 0.5))
			else:
				draw_circle(ball, 2.5, Iso.OUTLINE)
				draw_circle(ball, 1.8, Color(1, 1, 1))
		"kite":
			_draw_ped(e["who"])
			var ph: float = e["ph"]
			var hand := b + Vector2(3, -26)
			var k := b + Vector2(34 + sin(t_ * 0.7 + ph) * 8.0, -84 + cos(t_ * 1.1 + ph) * 6.0)
			draw_polyline(PackedVector2Array([hand, hand.lerp(k, 0.5) + Vector2(0, 8), k]), Color(1, 1, 1, 0.7), 1.0)
			Sprites.draw_image(self, ["scenery_kite_red", "scenery_kite_blue", "scenery_kite_yellow"][int(ph * 10.0) % 3], k + Vector2(0, 28))
		"picnic":
			var c: Vector2 = e["pos"]
			Sprites.draw_image(self, "scenery_picnic_red" if int(c.x) % 2 == 0 else "scenery_picnic_blue", Iso.to_screen(c) + Vector2(0, 14))
			for who in ["a", "b"]:
				_draw_ped(e[who])
		"volley":
			var t: Vector2 = e["t"]
			var n: Vector2 = e["n"]
			var c: Vector2 = e["pos"]
			Sprites.draw_image(self, "scenery_volleyball_net", Iso.to_screen(c) + Vector2(0, 14), n.x - n.y < 0.0)
			var u := fposmod(t_ * 0.5, 2.0)
			var f := u if u < 1.0 else u - 1.0
			var side := 1.0 if u < 1.0 else -1.0
			var team: Array = e["team"]
			for j in team.size():
				var pp: Dictionary = team[j]
				var hitter := (j == 1 and side > 0 and f < 0.15) or (j == 3 and side < 0 and f < 0.15)
				pp["cheer"] = 1.0 if hitter else 0.0
				pp["phase"] = 1.4 if hitter else 0.0
				_draw_ped(pp)
			var from := c - t * 1.3 * side
			var ball := Iso.to_screen(from.lerp(c + t * 1.3 * side, f), 22.0 + sin(f * PI) * 26.0)
			draw_circle(ball, 2.5, Iso.OUTLINE)
			draw_circle(ball, 1.8, Color(1.0, 0.95, 0.6))


## True if `p` lies on the asphalt of another road joining at a nearby junction (a junction mouth),
## where this road's kerb, edge lines and centre dashes must not be painted across the way.
func _in_mouth(p: Vector2, ri: int) -> bool:
	for j in junctions:
		if j["pos"].distance_squared_to(p) > 25.0:
			continue
		for l in j["links"]:
			if l[0] == ri:
				continue
			var pts: PackedVector2Array = roads[l[0]]["pts"]
			var cum: PackedFloat32Array = roads[l[0]]["cum"]
			for i in range(1, pts.size()):
				if absf(cum[i] - float(l[1])) > 6.0:
					continue
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])) < ROAD_HW + 0.12:
					return true
	return false


func _build_road_geometry() -> void:
	road_draw.clear()
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var cum: PackedFloat32Array = r["cum"]
		var n := pts.size()
		var normals := PackedVector2Array()
		normals.resize(n)
		for i in n:
			var a := pts[maxi(i - 1, 0)]
			var b := pts[mini(i + 1, n - 1)]
			if r["closed"] and (i == 0 or i == n - 1):
				a = pts[n - 2]
				b = pts[1]
			var t := (b - a).normalized()
			normals[i] = Vector2(-t.y, t.x)
		for i in n - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if a.distance_to(b) < 0.001:
				continue
			var na := normals[i]
			var nb := normals[i + 1]
			var mid := (a + b) * 0.5
			var nm := (na + nb).normalized()
			var dash := PackedVector2Array()
			if int(cum[i]) % 2 == 0 and not _in_mouth(mid, ri):
				dash = _ribbon(a, b, na, nb, 0.07)
			var empty := PackedVector2Array()
			var kerb_in := ROAD_HW - 0.18   # the white edge line
			var kerb_out := ROAD_HW + 0.18  # the kerb stone
			var cut_l := _in_mouth(mid + nm * kerb_in, ri) or _in_mouth(mid + nm * kerb_out, ri)
			var cut_r := _in_mouth(mid - nm * kerb_in, ri)
			var specks := PackedVector2Array()
			for k in 3:
				specks.append(Iso.to_screen(a.lerp(b, rng.randf()) + na * rng.randf_range(-0.85, 0.85) * ROAD_HW))
			road_draw.append([Iso.to_screen((a + b) * 0.5), _ribbon(a, b, na, nb, ROAD_HW + 0.3), _ribbon(a, b, na, nb, ROAD_HW), dash,
				empty if cut_l else _ribbon(a + na * kerb_in, b + nb * kerb_in, na, nb, 0.05), empty if cut_r else _ribbon(a - na * kerb_in, b - nb * kerb_in, na, nb, 0.05), specks,
				empty if cut_l else _ribbon(a + na * kerb_out, b + nb * kerb_out, na, nb, 0.12)])
	# Each road end is cut square to its own heading, so where arms meet at an angle a wedge of grass
	# shows between the cuts. Pave every junction with the hull of its arms' ends (pavement, then asphalt).
	for j in junctions:
		var walk := PackedVector2Array()
		var tar := PackedVector2Array()
		for l in j["links"]:
			var r: Dictionary = roads[l[0]]
			for hw in [ROAD_HW + 0.3, ROAD_HW]:
				for d in [-hw, 0.0, hw]:
					var s: float = l[1] + d
					if not r["closed"] and (s < -0.01 or s > float(r["len"]) + 0.01):
						continue
					var at := _road_at(r, s)
					var n := Vector2(-at[1].y, at[1].x)
					var into := walk if hw > ROAD_HW else tar
					into.append_array([at[0] + n * hw, at[0] - n * hw])
		var empty := PackedVector2Array()
		var hulls: Array = []
		for pts in [walk, tar]:
			var h := Geometry2D.convex_hull(pts)
			if h.size() > 1 and h[0] == h[h.size() - 1]:
				h.remove_at(h.size() - 1)
			hulls.append(_to_screen_poly(h))
		road_draw.append([Iso.to_screen(j["pos"]), hulls[0], hulls[1], empty, empty, empty, empty, empty])
	zebra.clear()
	for j in junctions:
		for l in j["links"]:
			var r: Dictionary = roads[l[0]]
			for side in [1.0, -1.0]:
				var s0: float = l[1] + side * 2.4
				if not r["closed"] and (s0 < 0.4 or s0 > float(r["len"]) - 0.4):
					continue
				var at := _road_at(r, s0)
				var t: Vector2 = at[1]
				var n := Vector2(-t.y, t.x)
				for k in 5:
					var c: Vector2 = at[0] + n * (-0.72 + k * 0.36) * ROAD_HW
					zebra.append(PackedVector2Array([Iso.to_screen(c + t * 0.32 + n * 0.1), Iso.to_screen(c - t * 0.32 + n * 0.1),
						Iso.to_screen(c - t * 0.32 - n * 0.1), Iso.to_screen(c + t * 0.32 - n * 0.1)]))


func _ribbon(a: Vector2, b: Vector2, na: Vector2, nb: Vector2, hw: float) -> PackedVector2Array:
	var q := PackedVector2Array([Iso.to_screen(a + na * hw), Iso.to_screen(b + nb * hw), Iso.to_screen(b - nb * hw), Iso.to_screen(a - na * hw)])
	if Geometry2D.triangulate_polygon(q).is_empty():   # folds on a tight bend: share one normal
		var n := (na + nb).normalized()
		q = PackedVector2Array([Iso.to_screen(a + n * hw), Iso.to_screen(b + n * hw), Iso.to_screen(b - n * hw), Iso.to_screen(a - n * hw)])
	return q


func _to_screen_poly(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Iso.to_screen(p))
	return out


func _build_lake_geometry() -> void:
	lake_screen["sand"] = _to_screen_poly(_lake_ring(1.7))
	lake_screen["wet"] = _to_screen_poly(_lake_ring(0.35))
	lake_screen["water"] = _to_screen_poly(lake_poly)
	lake_screen["mid"] = _to_screen_poly(_lake_ring(0.0, 0.75))
	lake_screen["deep"] = _to_screen_poly(_lake_ring(0.0, 0.45))
	var a := 2.75
	var shore := LAKE + Vector2(cos(a), sin(a)) * _lake_r(a)
	var inward := (LAKE - shore).normalized()
	var side := Vector2(-inward.y, inward.x) * 0.35
	var tip := shore + inward * 2.6
	lake_screen["dock"] = PackedVector2Array([Iso.to_screen(shore - inward * 0.6 + side, 3), Iso.to_screen(tip + side, 3), Iso.to_screen(tip - side, 3), Iso.to_screen(shore - inward * 0.6 - side, 3)])
	lake_screen["dock_world"] = [shore - inward * 0.6, tip, side]


func _build_graph() -> void:
	astar.clear()
	var id := 0
	var buckets := {}
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var prev := -1
		var first := id
		var idxs: Array = range(0, pts.size() - (1 if r["closed"] else 0), 2)
		if not r["closed"] and idxs[-1] != pts.size() - 1:
			idxs.append(pts.size() - 1)
		for k in idxs:
			astar.add_point(id, pts[k])
			if prev >= 0:
				astar.connect_points(prev, id)
			var key := Vector2i(int(pts[k].x / 2.0), int(pts[k].y / 2.0))
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append([id, ri])
			prev = id
			id += 1
		if r["closed"]:
			astar.connect_points(prev, first)
	for key in buckets:
		for e in buckets[key]:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var k2: Vector2i = key + Vector2i(dx, dy)
					if not buckets.has(k2):
						continue
					for f in buckets[k2]:
						if f[1] == e[1] or f[0] <= e[0]:
							continue
						if astar.get_point_position(e[0]).distance_to(astar.get_point_position(f[0])) < 1.7:
							astar.connect_points(e[0], f[0])


func _route(from: Vector2, to: Vector2, off: Vector2) -> Array:
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	var path: Array = []
	for p in astar.get_point_path(a, b):
		path.append(p + off)
	path.append(to)
	return path


func _spawn_cars() -> void:
	# traffic spread over the longer roads
	# a random mix of every kind of vehicle that has art, different each game
	# (each kind also comes in the colours tools/recolor_vehicle.gd made: art/vehicle_<kind>_c<n>.png)
	var pool: Array = []   # [kind, art]
	for k in VEHICLE_DIMS.keys():
		if Sprites.sheet("vehicle_%s" % k) != null:
			pool.append([k, "vehicle_%s" % k])
			for n in range(1, 7):
				if Sprites.sheet("vehicle_%s_c%d" % [k, n]) != null:
					pool.append([k, "vehicle_%s_c%d" % [k, n]])
	var kinds: Array = []
	for k in CAR_COUNT:
		kinds.append(pool[randi() % pool.size()])
	var long_roads: Array = []
	for ri in roads.size():
		if float(roads[ri]["len"]) > 25.0:
			long_roads.append(ri)
	for k in kinds.size():
		var ri: int = long_roads[(k * 7) % long_roads.size()]
		var r: Dictionary = roads[ri]
		var kind: String = kinds[k][0]
		var d: Array = VEHICLE_DIMS[kind]
		# somewhere on the road with room around it (cars don't start out on top of each other)
		var s0 := randf_range(3.0, float(r["len"]) - 3.0)
		for _try in 12:
			if not cars.any(func(o): return o["road"] == ri and absf(float(o["s"]) - s0) < 3.0):
				break
			s0 = randf_range(3.0, float(r["len"]) - 3.0)
		var c := {"road": ri, "s": s0, "dir": 1.0 if randf() < 0.5 else -1.0,
			"speed": 0.0, "max": randf_range(d[2], d[3]) * PACE, "col": CAR_COLORS[randi() % CAR_COLORS.size()], "kind": kind, "art": kinds[k][1],
			"hl": d[0], "hw": d[1], "wait": 0.0, "pos": Vector2.ZERO, "fwd": Vector2.RIGHT, "wild": kind in WILD_VEHICLES}
		_car_pose(c)
		cars.append(c)


func _car_pose(c: Dictionary) -> void:
	var at := _road_at(roads[c["road"]], c["s"])
	var fwd: Vector2 = at[1] * c["dir"]
	var lane := CAR_LANE + 0.5 * float(c.get("pull", 0.0))   # pulled over onto the kerb
	if c.get("wild", false):   # weaving about, or out on the wrong side of the road getting past you
		lane += sin(float(c.get("odo", 0.0)) * 0.9) * 0.1 - float(c.get("swing", 0.0))
	c["pos"] = at[0] + Vector2(-fwd.y, fwd.x) * lane
	c["fwd"] = fwd


func _spawn_rivals() -> void:
	rival_state.clear()
	for i in Talk.rivals.size():
		var p := astar.get_point_position(randi() % astar.get_point_count())
		rival_state.append({"pos": p, "head": 0.0, "path": [], "state": "idle", "idle": randf_range(1.0, 5.0), "order": 0,
			"stun": 0.0, "fall": 0.0, "wait": 0.0, "phase": randf() * TAU, "speed": 0.0, "mass": Game.rival_mass(i),
			"bike": Game.rival_bike(Talk.rivals[i]), "ftp": Game.rival_ftp(Talk.rivals[i], Game.rival_mass(i)),
			"off": Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)),
			"pu": "", "pu_hold": 0.0, "socks": 0.0, "bread": 0.0, "roller": 0.0, "blocked": false})


func _spawn_life() -> void:
	var shirts := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(1.0, 0.85, 0.2), Color(0.4, 0.85, 0.4), Color(0.95, 0.55, 0.85), Color(1, 1, 1)]
	var hairs := [Color(0.3, 0.2, 0.1), Color(0.9, 0.75, 0.3), Color(0.1, 0.1, 0.1), Color(0.6, 0.3, 0.15), Color(0.85, 0.85, 0.85)]
	var skins := [Color(0.96, 0.8, 0.65), Color(0.85, 0.62, 0.45), Color(0.62, 0.42, 0.3), Color(0.98, 0.86, 0.74)]
	for k in PLAZA_PEOPLE:
		var a := randf() * TAU
		peds.append({"pos": PLAZA + Vector2(cos(a), sin(a)) * randf_range(2.6, 6.0), "target": PLAZA, "col": shirts[k % shirts.size()],
			"hair": hairs[k % hairs.size()], "skin": skins[k % skins.size()], "t": randf() * 5.0, "phase": randf() * TAU, "road": -1, "look": randi() % Sprites.pedestrians().size(), "face": Vector2(1, 1),
			"cheer": 0.0, "cool": 0.0, "shout": "", "skis": randf() < 0.3})
	# townsfolk strolling the pavements all over town
	var made := 0
	for tries in 4000:
		if made >= STREET_PEOPLE:
			break
		var ri := randi() % roads.size()
		var r: Dictionary = roads[ri]
		var side := 1.0 if randf() < 0.5 else -1.0
		var ps := randf_range(1.0, float(r["len"]) - 1.0)
		var at := _road_at(r, ps)
		var pos: Vector2 = at[0] + Vector2(-at[1].y, at[1].x) * side * (ROAD_HW + 0.5)
		var ix := int(pos.x)
		var iy := int(pos.y)
		if ix < 0 or iy < 0 or ix >= N or iy >= N or solid[iy * N + ix] != 0 or tiles[iy * N + ix] == T.WATER:
			continue
		peds.append({"pos": pos, "road": ri, "s": ps, "dir": 1.0 if randf() < 0.5 else -1.0, "side": side, "speed": randf_range(0.4, 0.7),
			"col": shirts[randi() % shirts.size()], "hair": hairs[randi() % hairs.size()], "skin": skins[randi() % skins.size()],
			"t": randf_range(5.0, 20.0), "phase": randf() * TAU, "look": randi() % Sprites.pedestrians().size(), "face": Vector2(1, 1), "cheer": 0.0, "cool": 0.0, "shout": "", "skis": randf() < 0.3})
		made += 1
	for p in peds:
		p["giver"] = false
		p["gcool"] = 0.0
	# the gift-givers: their own people, standing on the pavement with a present (see _update_giver)
	for k in GIVER_COUNT:
		var g := {"giver": true, "gcool": randf_range(0.0, 20.0), "state": "away", "pos": Vector2.ZERO, "road": -1, "phase": randf() * TAU,
			"t": 0.0, "cool": 0.0, "cheer": 0.0, "shout": "", "face": Vector2(1, 1), "pu": PowerUps.pick(PowerUps.TOWN)}
		_giver_spot(g)
		peds.append(g)
	for k in 3:
		boats.append({"a": randf() * TAU, "rf": randf_range(0.35, 0.65), "w": randf_range(0.05, 0.09) * (1.0 if k % 2 == 0 else -1.0), "col": PIZZA_COLORS[k]})


# ======================================================================
# Simulation
# ======================================================================

func _process(delta: float) -> void:
	t_ += delta
	for k in bubbles.keys():
		bubbles[k]["t"] -= delta
		if bubbles[k]["t"] <= 0.0:
			bubbles.erase(k)
	player_bubble["t"] = maxf(0.0, player_bubble["t"] - delta)
	if player_bubble["t"] > 0.0 and player_bubble.get("boxed", false) == false:   # in the message box too, with your face
		player_bubble["boxed"] = true
		Game.racer_says.emit("rookie_" + Game.rider, Game.player_name, player_bubble["text"], "happy", Color(0.4, 0.75, 1.0))
	_update_cars(delta)
	_update_rivals(delta)
	_update_life(delta)
	_update_lamps(delta)
	_update_challenge(delta)
	_update_climbs(delta)
	outage_t = maxf(0.0, outage_t - delta)
	if events != null:
		events.update(delta)
		events.settle()
	_update_mascots(delta)
	heli.update(delta)
	_update_news(delta)
	_update_champion(delta)
	_update_frisbees(delta)
	_update_squash()
	if active:
		_update_orders(delta)
		_update_player(delta)
		Talk.tick_banter(delta)
	queue_redraw()


func _update_player(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	prompt = ""
	if er_timer > 0.0:
		er_timer -= delta
		p_fall += delta
		p_speed = 0.0
		if er_timer <= 0.0:
			_leave_er()
		return

	socks_t = maxf(0.0, socks_t - delta)
	bread_t = maxf(0.0, bread_t - delta)
	roller_t = maxf(0.0, roller_t - delta)
	if p_down > 0.0:
		p_down = maxf(0.0, p_down - delta)
		p_fall += delta
		p_speed = 0.0
		Trainer.send_grade(0.0)
		if p_down <= 0.0:
			invuln = maxf(invuln, 1.0)
		return

	var bike := Game.bike()
	grade = lerpf(grade, clampf(grade_at(p_pos, p_fwd), -0.1, 0.1), 1.0 - exp(-4.0 * delta))
	var felt := PowerUps.felt_grade(grade, roller_t)
	Trainer.send_grade(felt * 100.0)
	var mps := minf(Game.speed_from_power(Trainer.power(), bike["mass"], bike["cda"], bike["crr"], felt), MAX_TOWN_SPEED)
	var target := mps * TILES_PER_MS * PACE
	if Game.hp_ratio() < 0.3:
		target *= 0.85
	if socks_t > 0.0:
		target *= PowerUps.SOCKS_BOOST
	if p_blocked:
		target = minf(target, 0.4 * PACE)
	if events != null and events.blocks_rider(p_pos, p_fwd):
		target = 0.0   # a cow in the road: you can't ride through it, wait for it to wander off
	if Input.is_action_just_pressed("powerup"):
		_use_powerup(-1)
	# coast in gently when riding up to a pickup window or a delivery door
	var obj := _objective()
	if obj["has"] and p_pos.distance_to(obj["pos"]) < 4.0:
		target = minf(target, 1.5 * PACE)
	var accel := 2.4
	if Input.is_action_pressed("brake") and not Game.fixed_gear():   # a fixie has no brakes
		target = 0.0
		accel = 7.0
	elif target < p_speed:
		accel = 2.0
	p_speed = move_toward(p_speed, target, accel * delta)
	p_phase += Trainer.cadence() / 60.0 * TAU * delta if Trainer.cadence() > 1.0 else p_speed * 2.0 * delta

	if Input.is_action_just_pressed("act_down"):
		rdir = -rdir
		pending = {}
		queued = ""
		_turn = {}
		_from_j = -1
		p_speed *= 0.3
		_uturn = {"from": p_pos, "fwd": p_fwd, "t": 0.0}   # swing round in an arc (see below), not a flip
		Game.toast.emit("U-turn!", Color(0.8, 0.9, 1.0))
	_rail_step(p_speed * delta)
	_update_pending()
	var w := _update_turn(p_speed * delta)
	p_fwd = p_fwd.slerp(w[1], 1.0 - exp(-10.0 * delta)).normalized()
	# the paddles slide you across the road, kerb to kerb, oncoming lane and all (round a parked or queueing car);
	# turns are picked with the D-pad / arrows only
	p_lat = clampf(p_lat + Input.get_axis("lane_left", "lane_right") * 1.4 * delta, -(BIKE_LANE + ROAD_HW - 0.2), 0.0)
	var road_fwd: Vector2 = w[1]
	rail_pos = w[0] + Vector2(-road_fwd.y, road_fwd.x) * p_lat   # across the road, not across the bike (which swings in a U-turn)
	if not _uturn.is_empty():
		# a U-turn: swing out ahead and round across the road to the other side, the bike turning with the curve
		_uturn["t"] = float(_uturn["t"]) + delta / UTURN_TIME
		var u := clampf(float(_uturn["t"]), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		var a: Vector2 = _uturn["from"]
		var k: Vector2 = a + (_uturn["fwd"] as Vector2) * 1.6 + (rail_pos - a) * 0.5
		var b: Vector2 = rail_pos
		p_pos = a.lerp(k, u).lerp(k.lerp(b, u), u)
		# the bike swings round steadily, the way the arc bends: the curve's own tangent lurches when its far end (your
		# new line, moving on with you) shifts, and the camera looks ahead along your heading
		var f0: Vector2 = _uturn["fwd"]
		if not _uturn.has("side"):
			_uturn["side"] = 1.0 if f0.cross(b - a) >= 0.0 else -1.0
		p_fwd = f0.rotated(float(_uturn["side"]) * PI * u)
		if float(_uturn["t"]) >= 1.0:
			_uturn = {}
	elif p_pos.distance_to(rail_pos) > 3.0:
		p_pos = rail_pos
	else:
		p_pos = p_pos.lerp(rail_pos, 1.0 - exp(-14.0 * delta))
	p_head = p_fwd.angle()
	_hint_clock -= delta
	if _hint_clock <= 0.0:
		_hint_clock = 0.7
		_update_uturn_hint()

	for z in zones:
		if p_pos.distance_to(z["pos"]) < z["r"]:
			match z["kind"]:
				"bike":
					prompt = "A / E:  Enter the bike shop"
				"race":
					prompt = "A / E:  Enter a Mt. Crankmore race"
				"er":
					prompt = "St. Pedro's ER. Frequent flyers welcome."
			if Input.is_action_just_pressed("act_select") and z["kind"] != "er":
				p_speed = 0.0
				interact.emit(z["kind"])

	# a ski patroller calling for help at the chairlift: A takes the medical kit up the mountain
	if events != null:
		var rc: Vector2 = events.rescue_call()
		if rc != Vector2.INF and p_pos.distance_to(rc) < 6.0:
			prompt = "A / E:  Save a person on Mt. Crankmore"
			if Input.is_action_just_pressed("act_select"):
				p_speed = 0.0
				events.rescue_taken()
				interact.emit("rescue")

	if Input.is_action_just_pressed("honk"):
		player_bubble = {"text": HONKS.pick_random(), "t": 2.2}
		if randf() < 0.5:
			Talk.say(randi() % Talk.rivals.size(), "banter", true)

	if invuln <= 0.0:
		for c in cars:
			if c.get("hidden", false):
				continue
			var rel: Vector2 = rail_pos - c["pos"]
			var f: Vector2 = c["fwd"]
			# the car's body (CAR_BODY), so riding past one in your lane is a near miss, not a crash
			if absf(rel.dot(f)) < float(c["hl"]) * CAR_BODY + CAR_HIT_R and absf(rel.dot(Vector2(-f.y, f.x))) < float(c["hw"]) * CAR_BODY + CAR_HIT_R * 0.5:
				_hit_by_car(c)
				break

	_update_pickups(delta)


func _wrap_s(r: Dictionary, s: float) -> float:
	return fposmod(s, float(r["len"])) if r["closed"] else clampf(s, 0.0, float(r["len"]))


## World position (riding on the right-hand shoulder) and travel direction.
func _rail_world() -> Array:
	var at := _road_at(roads[rr], rs)
	var fwd: Vector2 = at[1] * rdir
	return [at[0] + Vector2(-fwd.y, fwd.x) * BIKE_LANE, fwd]


## Next junction ahead on the current road: [junction index, distance], or [-1, distance to a dead end].
func _next_junction() -> Array:
	return _next_junction_on(rr, rs, rdir, _from_j)


## The same for anyone at `s` on `road` heading `dir`, just past junction `from_j`.
func _next_junction_on(road: int, s: float, dir: float, from_j: int) -> Array:
	var r: Dictionary = roads[road]
	var length: float = r["len"]
	var best := -1
	var best_d := 1e9
	for e in road_js[road]:
		var d: float = (e[0] - s) * dir
		if r["closed"]:
			d = fposmod(d, length)
		if e[1] == from_j and d < 0.5:
			continue
		if d >= 0.0 and d < best_d:
			best_d = d
			best = e[1]
	if best < 0 and not r["closed"]:
		return [-1, (length - s) if dir > 0.0 else s]
	if not r["closed"]:
		var to_end := (length - s) if dir > 0.0 else s
		if to_end < best_d - 0.05:
			return [-1, to_end]
	return [best, best_d]


func _rail_step(dist: float) -> void:
	for guard in 4:
		if dist <= 0.0:
			return
		var r: Dictionary = roads[rr]
		var nj := _next_junction()
		var ahead: float = nj[1]
		if dist < ahead:
			rs = _wrap_s(r, rs + rdir * dist)
			return
		dist -= ahead
		rs = _wrap_s(r, rs + rdir * ahead)
		if nj[0] < 0:
			rdir = -rdir
			p_speed *= 0.3
			pending = {}
			_turn = {}
			_from_j = -1
			Game.toast.emit("Dead end - turning around", Color(0.8, 0.9, 1.0))
			return
		_take_junction(nj[0])


func _link_s(ji: int, road: int) -> float:
	for l in junctions[ji]["links"]:
		if l[0] == road:
			return l[1]
	return rs


## Exits from a junction for a rider arriving on `road` heading `dir`, with the turn angle of each.
func _options(ji: int, road: int, dir: float) -> Array:
	var j: Dictionary = junctions[ji]
	var ls := _link_s(ji, road)
	var arrive: Vector2 = (_road_at(roads[road], ls)[0] - _road_at(roads[road], ls - dir * 1.5)[0]).normalized()
	var opts: Array = []
	for l in j["links"]:
		var b: int = l[0]
		var sb: float = l[1]
		var rb: Dictionary = roads[b]
		for d in [1.0, -1.0]:
			if b == road and d == -dir:
				continue
			if not rb["closed"] and ((d > 0.0 and sb > float(rb["len"]) - 0.5) or (d < 0.0 and sb < 0.5)):
				continue
			var hv: Vector2 = (_road_at(rb, sb + d * 1.5)[0] - _road_at(rb, sb)[0]).normalized()
			opts.append({"road": b, "s": sb, "dir": d, "ang": arrive.angle_to(hv), "name": rb["name"]})
	return opts


## Maps exits to "left" / "straight" / "right" from the rider's point of view. Exits are taken in
## order from leftmost to rightmost so every one of them (at most three) gets its own button.
func _label_options(opts: Array) -> Dictionary:
	var o := opts.duplicate()
	o.sort_custom(func(a, b): return a["ang"] < b["ang"])
	while o.size() > 3:   # never happens with the squared-up network; keep the three most distinct
		o.remove_at(1 if absf(o[1]["ang"]) > absf(o[o.size() - 2]["ang"]) else o.size() - 2)
	match o.size():
		0:
			return {}
		1:
			return {_side_of(o[0]["ang"]): o[0]}
		2:
			var a: Dictionary = o[0]
			var b: Dictionary = o[1]
			if a["ang"] < 0.0 and b["ang"] > 0.0:
				if absf(a["ang"]) < 0.6 and absf(b["ang"]) > 0.9:
					return {"straight": a, "right": b}
				if absf(b["ang"]) < 0.6 and absf(a["ang"]) > 0.9:
					return {"left": a, "straight": b}
				return {"left": a, "right": b}
			if b["ang"] <= 0.0:
				return {"left": a, "straight": b}
			return {"straight": a, "right": b}
	return {"left": o[0], "straight": o[1], "right": o[2]}


func _side_of(ang: float) -> String:
	if absf(ang) < 0.6:
		return "straight"
	return "right" if ang > 0.0 else "left"


## The exit the rider will take at a junction: their choice, else straight on, else the GPS way.
func _pick_exit(ji: int) -> Dictionary:
	var lab := _label_options(_options(ji, rr, rdir))
	if not pending.is_empty() and pending["j"] == ji and lab.has(pending["choice"]):
		return lab[pending["choice"]]
	if lab.has("straight"):
		return lab["straight"]
	if not lab.is_empty():
		return lab[_gps_choice(lab)]
	return {}


func _take_junction(ji: int) -> void:
	var pick: Dictionary
	if not _turn.is_empty() and _turn["j"] == ji and not _turn["crossed"]:
		pick = _turn["pick"]
		_turn["crossed"] = true
	else:
		pick = _pick_exit(ji)
		_turn = {}
	pending = {}
	_from_j = ji
	if pick.is_empty():
		rdir = -rdir
		return
	rr = pick["road"]
	rs = pick["s"]
	rdir = pick["dir"]


## Where the rider is drawn: on the rail, or on a smooth curve through a junction. Starting TURN_R before
## the junction, the rider follows a Bezier from there, through the corner where the approach lane meets
## the exit lane, to TURN_R along the exit road, while the rail keeps moving underneath; the two meet again
## at the end. Changing the choice mid-curve re-aims the curve from where the rider is now.
func _update_turn(dist: float) -> Array:
	var nj := _next_junction()
	if _turn.is_empty():
		if nj[0] >= 0 and nj[1] <= TURN_R:
			var w := _rail_world()
			_aim_turn(nj[0], w[0], w[1], nj[1])
	else:
		_turn["t"] += dist
		if not _turn["crossed"]:
			var pick := _pick_exit(_turn["j"])
			if pick != _turn["pick"] and not pick.is_empty():
				var cur := _turn_point()
				_aim_turn(_turn["j"], cur[0], cur[1], nj[1])
	if _turn.is_empty():
		return _rail_world()
	if _turn["t"] >= _turn["len"]:
		_turn = {}
		return _rail_world()
	return _turn_point()


func _aim_turn(ji: int, a: Vector2, fa: Vector2, ahead: float) -> void:
	var pick := _pick_exit(ji)
	if pick.is_empty():
		_turn = {}
		return
	var at := _road_at(roads[pick["road"]], float(pick["s"]) + float(pick["dir"]) * TURN_R)
	var fb: Vector2 = at[1] * float(pick["dir"])
	var b: Vector2 = at[0] + Vector2(-fb.y, fb.x) * BIKE_LANE
	# control point: where the approach line meets the exit line (midway if they're nearly parallel)
	var c := (a + b) * 0.5
	var den := fa.cross(fb)
	if absf(den) > 0.15:
		var k := (b - a).cross(fb) / den
		if k > 0.0 and k < a.distance_to(b) * 1.5:
			c = a + fa * k
	_turn = {"j": ji, "pick": pick, "crossed": false, "a": a, "c": c, "b": b, "t": 0.0, "len": ahead + TURN_R}


func _turn_point() -> Array:
	var u := clampf(float(_turn["t"]) / float(_turn["len"]), 0.0, 1.0)
	var a: Vector2 = _turn["a"]
	var c: Vector2 = _turn["c"]
	var b: Vector2 = _turn["b"]
	var tg := (c - a) * (1.0 - u) + (b - c) * u
	return [a.lerp(c, u).lerp(c.lerp(b, u), u), tg.normalized() if tg.length() > 0.0001 else p_fwd]


## Announces the next junction a few seconds ahead and lets the rider pick a direction.
## A single press latches: it sticks until the junction is passed (no need to hold the button),
## and a press made before the junction is announced is queued for it.
func _update_pending() -> void:
	var press := ""
	if Input.is_action_just_pressed("steer_left"):
		press = "left"
	elif Input.is_action_just_pressed("steer_right"):
		press = "right"
	elif Input.is_action_just_pressed("act_up"):
		press = "straight"
	var nj := _next_junction()
	var look := maxf(8.0, p_speed * 5.0)
	if nj[0] < 0:
		pending = {}
	elif not pending.is_empty() and pending["j"] == nj[0]:
		pass  # keep the announced junction (and the rider's choice) until it's passed
	elif nj[1] <= look:
		pending = {}
		var lab := _label_options(_options(nj[0], rr, rdir))
		if lab.size() > 1:
			var gps := _gps_choice(lab)
			pending = {"j": nj[0], "labels": lab, "gps": gps, "choice": "straight" if lab.has("straight") else gps}
			var race_way: String = ((challenge.get("route", {}) as Dictionary).get("picks", {}) as Dictionary).get(nj[0], "")
			if race_way != "" and lab.has(race_way):
				pending["choice"] = race_way   # a race's route: the way its red arrow points
			if queued != "" and lab.has(queued):
				pending["choice"] = queued
			queued = ""
	else:
		pending = {}
	if not pending.is_empty():
		pending["dist"] = nj[1]
		pending["look"] = maxf(float(pending.get("look", look)), nj[1])
		var jp: Vector2 = junctions[pending["j"]]["pos"]
		pending["car"] = false
		for c in cars:
			var rel: Vector2 = jp - c["pos"]
			if rel.length() < 7.0 and rel.dot(c["fwd"]) > 0.0 and absf(c["fwd"].dot(p_fwd)) < 0.8:
				pending["car"] = true
		if press != "" and pending["labels"].has(press):
			pending["choice"] = press
	elif press != "":
		queued = press


func _objective() -> Dictionary:
	if not carry.is_empty():
		return {"has": true, "pos": spots[carry["dest"]]["pos"]}
	var best := 1e9
	var pos := Vector2.ZERO
	for o in orders:
		if o["state"] == "open":
			var w: Vector2 = shops[o["shop"]]["window"]
			var d := p_pos.distance_to(w)
			if d < best:
				best = d
				pos = w
	return {"has": best < 1e8, "pos": pos}


func _path_len(a: Vector2, b: Vector2) -> float:
	var pts := astar.get_point_path(astar.get_closest_point(a), astar.get_closest_point(b))
	if pts.is_empty():
		return a.distance_to(b)
	var total := a.distance_to(pts[0]) + pts[pts.size() - 1].distance_to(b)
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	return total


## Which exit gets closer to the current objective (shown as the GPS hint).
func _gps_choice(lab: Dictionary) -> String:
	var obj := _objective()
	var keys: Array = lab.keys()
	if not obj["has"]:
		return "straight" if lab.has("straight") else keys[0]
	var best: String = keys[0]
	var best_c := 1e9
	for k in keys:
		var o: Dictionary = lab[k]
		var probe: Vector2 = _road_at(roads[o["road"]], float(o["s"]) + float(o["dir"]) * 2.5)[0]
		var c := _path_len(probe, obj["pos"])
		if c < best_c:
			best_c = c
			best = k
	return best


func _update_uturn_hint() -> void:
	var obj := _objective()
	uturn_hint = false
	if not obj["has"] or p_pos.distance_to(obj["pos"]) < 6.0:
		return
	var ahead: Vector2 = _road_at(roads[rr], rs + rdir * 3.0)[0]
	var behind: Vector2 = _road_at(roads[rr], rs - rdir * 3.0)[0]
	uturn_hint = _path_len(behind, obj["pos"]) + 8.0 < _path_len(ahead, obj["pos"])


func _hit_by_car(c: Dictionary) -> void:
	p_fall = 0.0
	p_fall_pizza = not carry.is_empty()
	er_bill = 120 + int(p_speed * 35.0) + randi() % 60
	Game.add_money(-er_bill)
	er_timer = 6.0
	er_text = ER_JOKES.pick_random()
	invuln = 99.0
	p_speed = 0.0
	socks_t = 0.0
	bread_t = 0.0
	roller_t = 0.0
	p_down = 0.0
	if not carry.is_empty():
		Game.toast.emit("The pizza went flying. Order #%d is lost." % carry["id"], Color.ORANGE)
		chef_says(int(carry["shop"]), "flying")
		carry = {}
	Game.toast.emit("HIT BY A CAR!  Medical bill: $%d" % er_bill, Color(1.0, 0.3, 0.3))
	Talk.say_random("er", true)
	c["speed"] = 0.0


func _leave_er() -> void:
	place_on(zone_anchor("er"))
	rdir = 1.0
	invuln = 2.0
	if Game.damage_bike(40.0):   # hit by a car: the bike takes 40 HP
		Talk.say_random("bike_destroyed", true)
	Game.save_game()


## Cars take turns through a junction: the first to reach it claims it (cars right behind it in the same lane follow
## it through) and the others wait at the line until it is clear. Turning cars follow a curve from their lane into the new one (CAR_TURN either side of the junction),
## slowing down for it, and everyone keeps a gap to whatever is right in front of them, on any road.
const CAR_TURN := 1.6        # m before and after a junction a turning car spends on its curve
const CAR_TURN_V := 1.3      # m/s around a corner
const CAR_STOP := 2.0        # m from a busy junction's middle where cars wait their turn
const CAR_BRAKE := 3.0       # m/s² when slowing for a corner or a junction
var j_claim := {}            # junction -> {"cars": the cars crossing it, "from": [road, dir] they came in on}


## A car that's done its part (an emergency vehicle back from a call, a hayride's tractor): it drives on with the
## traffic, lights off, and is taken away once it's out of sight.
func retire_car(c: Dictionary) -> void:
	c["retire"] = true
	c["siren"] = false
	c.erase("park_s")


func _update_cars(delta: float) -> void:
	for k in range(cars.size() - 1, -1, -1):
		if cars[k].get("retire", false) and (cars[k].get("hidden", false) or not on_screen(cars[k]["pos"])):
			cars.remove_at(k)
	for ji in j_claim.keys():
		var jp: Vector2 = junctions[ji]["pos"]
		j_claim[ji]["cars"] = j_claim[ji]["cars"].filter(func(h): return cars.has(h) and (int(h.get("claim", -1)) == ji or (h["pos"] as Vector2).distance_to(jp) < 1.4))
		if j_claim[ji]["cars"].is_empty():
			j_claim.erase(ji)
	var band: Array = (events.parade_spots() + events.ride_spots()) if events != null else []   # the band and group rides have the road
	for c in cars:
		var r: Dictionary = roads[c["road"]]
		if c["wait"] > 0.0:
			c["wait"] -= delta
			continue
		var target: float = c["max"]
		var f: Vector2 = c["fwd"]
		var blocked := false
		for o in cars:
			# (an emergency vehicle on its way to a scene gets past the queue: lights flashing, everyone makes way)
			if o == c or float(o.get("pull", 0.0)) > 0.5 or c.has("park_s"):
				continue
			var need: float = float(c["hl"]) + float(o["hl"])
			if not c.has("curve") and o["road"] == c["road"] and o["dir"] == c["dir"]:
				var gap: float = (o["s"] - c["s"]) * c["dir"]
				if r["closed"]:
					gap = fposmod(gap, float(r["len"]))
				if gap > 0.0 and gap < 2.2 + need:
					target = minf(target, 0.0 if gap < 1.2 + need else float(o["speed"]))
					continue
			# anything right in front: a car that turned in ahead, one crossing the junction
			var rel: Vector2 = o["pos"] - c["pos"]
			var ahead := rel.dot(f)
			if ahead > 0.0 and ahead < 1.0 + need and absf(rel.dot(Vector2(-f.y, f.x))) < 0.55 and (o["fwd"] as Vector2).dot(f) > -0.5:
				target = minf(target, 0.0 if ahead < 0.4 + need else float(o["speed"]))
				blocked = true
		# stuck nose to nose for a while (it happens on a tight corner): creep past
		c["stall"] = float(c.get("stall", 0.0)) + delta if blocked and target <= 0.0 else 0.0
		if c["stall"] > 3.0:
			target = 0.6
		# the marching band has the road: wait for it to go by
		for q in band:
			var rel: Vector2 = q - c["pos"]
			var ahead := rel.dot(f)
			if ahead > -0.2 and ahead < 1.3 + float(c["hl"]) and absf(rel.dot(Vector2(-f.y, f.x))) < 0.75:
				target = 0.0
				break
		if not c.has("curve"):
			var nj := _car_next_j(c, r, 9.0)
			var ji: int = nj[0]
			if ji >= 0:
				var d: float = nj[1]
				if int(c.get("plan_j", -1)) != ji:
					c["plan_j"] = ji
					c["plan"] = _car_plan(c, ji, r)
				if not (c["plan"] as Dictionary).is_empty():
					target = minf(target, sqrt(CAR_TURN_V * CAR_TURN_V + 2.0 * CAR_BRAKE * maxf(0.0, d - CAR_TURN)))
				if int(c.get("claim", -1)) != ji and not c.get("siren", false):
					var room: float = d - CAR_STOP - float(c["hl"])
					var held: Dictionary = j_claim.get(ji, {})
					var lane := [c["road"], c["dir"]]
					if not held.is_empty() and held["from"] != lane and float(c.get("held", 0.0)) < 6.0 and room > -0.4:
						target = minf(target, sqrt(2.0 * CAR_BRAKE * maxf(0.0, room - 0.2)))
						c["held"] = float(c.get("held", 0.0)) + delta
					elif room < 0.8:
						if held.is_empty():
							j_claim[ji] = {"cars": [c], "from": lane}
						else:
							held["cars"].append(c)
						c["claim"] = ji
						c["held"] = 0.0
		if c.has("park_s"):
			# an emergency vehicle stopping at the scene, pulling over onto the kerb as it gets there
			var to_go: float = (float(c["park_s"]) - float(c["s"])) * float(c["dir"])
			if r["closed"]:
				to_go = fposmod(to_go + 1.0, float(r["len"])) - 1.0
			target = minf(target, sqrt(2.0 * CAR_BRAKE * maxf(0.0, to_go - 0.05)))
			c["pull"] = move_toward(float(c.get("pull", 0.0)), 1.0 if to_go < 2.0 else 0.0, delta * 1.5)
		elif float(c.get("pull", 0.0)) > 0.0:
			c["pull"] = move_toward(float(c["pull"]), 0.0, delta)
		# (an emergency vehicle on a call goes round you rather than queueing behind)
		if active and er_timer <= 0.0 and not c.get("hidden", false) and not c.has("park_s"):
			var rel: Vector2 = rail_pos - c["pos"]
			var ahead := rel.dot(f)
			# cars queue behind a rider in their lane, but don't expect riders cutting across a junction (a hot rod won't
			# queue: over the centre line it goes, if nothing's coming)
			if ahead > 0.0 and ahead < 2.4 + float(c["hl"]) and absf(rel.dot(Vector2(-f.y, f.x))) < 0.8 and f.dot(p_fwd) > 0.5:
				if c.get("wild", false) and (c.get("passing", false) or _clear_to_pass(c, r)):
					c["passing"] = true
				else:
					target = 0.0
			# and an oncoming car brakes for a rider coming at it on its side of the road, and waits
			elif ahead > 0.0 and ahead < 4.5 + float(c["hl"]) and absf(rel.dot(Vector2(-f.y, f.x))) < 0.9 and f.dot(p_fwd) < -0.5:
				target = 0.0
		if c.get("wild", false):
			target = _wild_step(c, target, delta)
		c["speed"] = move_toward(c["speed"], target, (4.0 if target > c["speed"] else 2.0 * CAR_BRAKE) * delta)
		var moved: float = c["speed"] * delta
		c["odo"] = float(c.get("odo", randf() * 10.0)) + moved   # distance driven: turns the wheels, bounces the body
		if c.has("curve"):
			_car_curve_step(c, moved)
			continue
		var s0: float = c["s"]
		c["s"] = _wrap_s(r, s0 + c["dir"] * moved)
		_car_junctions(c, r, s0, moved)
		if not c.has("curve"):
			_car_pose(c)
		# through and clear of the junction it claimed
		if int(c.get("claim", -1)) >= 0 and not c.has("curve"):
			var jp: Vector2 = junctions[c["claim"]]["pos"]
			if (jp - (c["pos"] as Vector2)).dot(c["fwd"]) < -0.3:
				c["claim"] = -1


## A hot rod's driving (WILD_VEHICLES): once it's decided to pass you it swings out over the centre line, floors it,
## and cuts back in once you're behind it. Returns the speed it's going for.
func _wild_step(c: Dictionary, target: float, delta: float) -> float:
	if c.get("passing", false):
		var behind: float = (rail_pos - (c["pos"] as Vector2)).dot(c["fwd"])
		if not active or c.has("curve") or behind < -(1.4 + float(c["hl"])) or behind > 5.0:
			c["passing"] = false
		else:
			target = maxf(target, float(c["max"]) * 1.2)
	c["swing"] = move_toward(float(c.get("swing", 0.0)), 2.0 * CAR_LANE if c.get("passing", false) else 0.0, delta * 2.2)
	# and the odd burst of speed, just because
	return target * (1.0 + 0.2 * maxf(0.0, sin(float(c.get("odo", 0.0)) * 0.25)))


## Whether a car can go over the centre line to pass: no junction coming up and nothing coming the other way.
func _clear_to_pass(c: Dictionary, r: Dictionary) -> bool:
	if c.has("curve") or _car_next_j(c, r, 3.0)[0] >= 0:
		return false
	for o in cars:
		if o != c and o["road"] == c["road"] and o["dir"] != c["dir"] and not o.get("hidden", false):
			var d: float = (float(o["s"]) - float(c["s"])) * float(c["dir"])
			if d > -1.5 and d < 14.0:
				return false
	return true


## Knocked flat by something that isn't a rider (the hot rod swerving into you): down on the road for `secs`.
func knock_over(secs: float, text: String) -> void:
	if _is_down(-1) or invuln > 0.0:
		return
	p_down = secs
	p_fall = 0.0
	p_fall_pizza = not carry.is_empty()
	p_speed = 0.0
	Game.toast.emit(text, Color(1.0, 0.45, 0.35))


## The next junction ahead of a car on its road within `reach` m: [junction, distance], or [-1, 0].
func _car_next_j(c: Dictionary, r: Dictionary, reach: float) -> Array:
	var best := -1
	var best_d := reach
	for e in road_js[c["road"]]:
		if int(e[1]) == int(c.get("last_j", -1)):
			continue
		var d: float = (float(e[0]) - float(c["s"])) * float(c["dir"])
		if r["closed"]:
			d = fposmod(d, float(r["len"]))
		if d >= -0.05 and d < best_d:
			best_d = d
			best = e[1]
	return [best, best_d] if best >= 0 else [-1, 0.0]


## What a car will do at the junction ahead: {} to drive straight on, else the exit it turns into. At the end of a
## road it has to turn; elsewhere it sometimes does.
func _car_plan(c: Dictionary, ji: int, r: Dictionary) -> Dictionary:
	var ri: int = c["road"]
	if c.has("park_s") and not (not r["closed"] and absf(_link_s(ji, ri) - (float(r["len"]) if c["dir"] > 0.0 else 0.0)) < 0.6):
		return {}   # heading for the scene: straight on
	var ls := _link_s(ji, ri)
	var at_end: bool = not r["closed"] and (ls < 0.6 or ls > float(r["len"]) - 0.6)
	if not at_end and randf() < 0.55:
		return {}
	var opts := _options(ji, ri, c["dir"])
	if not at_end:
		opts = opts.filter(func(o): return o["road"] != ri)
	return {} if opts.is_empty() else opts.pick_random()


## At CAR_TURN from the junction a turning car leaves its road for a curve into its exit; driving straight on, it
## just carries on. With no way out at all it turns around at the end of the road.
func _car_junctions(c: Dictionary, r: Dictionary, s0: float, moved: float) -> void:
	var nj := _car_next_j(c, r, CAR_TURN)
	var ji: int = nj[0]
	if ji >= 0 and int(c.get("plan_j", -1)) == ji:
		var o: Dictionary = c["plan"]
		if o.is_empty():
			if float(nj[1]) < 0.05:
				c["last_j"] = ji
		else:
			c["last_j"] = ji
			var nr: Dictionary = roads[o["road"]]
			var s_end := _wrap_s(nr, float(o["s"]) + float(o["dir"]) * CAR_TURN)
			_start_curve(c, o["road"], s_end, o["dir"])
		return
	if not r["closed"] and (c["s"] >= float(r["len"]) - 0.01 or c["s"] <= 0.01):
		# a dead end: swing round into the other lane
		c["wait"] = 0.6
		c["last_j"] = -1
		_start_curve(c, c["road"], c["s"], -float(c["dir"]))


## Puts a car on a curve (quadratic, through the point where its lane and the new lane meet) that ends on `road` at
## `s`, heading `dir`. Its road, s and dir are already the new ones, so cars on that road queue behind it.
func _start_curve(c: Dictionary, road: int, s: float, dir: float) -> void:
	var a: Vector2 = c["pos"]
	var f1: Vector2 = c["fwd"]
	var at := _road_at(roads[road], s)
	var f2: Vector2 = at[1] * dir
	var e: Vector2 = at[0] + Vector2(-f2.y, f2.x) * CAR_LANE
	var k: Vector2
	var den := f1.cross(f2)
	if absf(den) > 0.3:
		k = a + f1 * clampf((e - a).cross(f2) / den, 0.0, 4.0)
	else:   # straight ahead, or a U-turn: swing out in front
		k = (a + e) * 0.5 + f1 * (0.3 if f1.dot(f2) > 0.0 else 1.2)
	var length := 0.0
	var prev := a
	for i in range(1, 11):
		var q := _bezier(a, k, e, i / 10.0)
		length += prev.distance_to(q)
		prev = q
	c["curve"] = {"a": a, "k": k, "e": e, "len": maxf(length, 0.1), "u": 0.0}
	c["road"] = road
	c["s"] = s
	c["dir"] = dir


func _bezier(a: Vector2, k: Vector2, e: Vector2, u: float) -> Vector2:
	return a.lerp(k, u).lerp(k.lerp(e, u), u)


func _car_curve_step(c: Dictionary, moved: float) -> void:
	var cv: Dictionary = c["curve"]
	cv["u"] = minf(1.0, float(cv["u"]) + moved / float(cv["len"]))
	var u: float = cv["u"]
	var a: Vector2 = cv["a"]
	var k: Vector2 = cv["k"]
	var e: Vector2 = cv["e"]
	c["pos"] = _bezier(a, k, e, u)
	var tan := (k - a) * (1.0 - u) + (e - k) * u
	if tan.length() > 0.001:
		c["fwd"] = tan.normalized()
	if u >= 1.0:
		c.erase("curve")
		_car_pose(c)


## Street lamps come on one by one as it gets dark (each at its own darkness, flickering as it warms up) and go
## off again in the morning.
func _update_lamps(delta: float) -> void:
	var dark := Skies.dark()
	for p in props:
		if p["kind"] != "lamp":
			continue
		var at: float = 0.25 + fposmod(p["pos"].x * 0.37 + p["pos"].y * 0.91, 1.0) * 0.3
		var want := 1.0 if dark > at and outage_t <= 0.0 else 0.0
		var g: float = move_toward(float(p.get("glow", want)), want, delta * 0.8)
		p["glow"] = g
		p["lit"] = g if g >= 1.0 or g <= 0.0 else g * (0.4 if randf() < 0.3 else 1.0)


## The lights at night for night.gd: lamp pools and bulbs, car headlights, bike lights.
func night_lights() -> Array:
	var out: Array = []
	var dark := Skies.dark()
	var was := Iso.terrain_on
	Iso.terrain_on = true
	for p in props:
		if p["kind"] == "lamp" and float(p.get("lit", 0.0)) > 0.0:
			var base := Iso.to_screen(p["pos"])
			out.append([base, 58.0, float(p["lit"]) * 0.85])
			out.append([base + Vector2(0, -48), 9.0, float(p["lit"])])
	if dark > 0.3:
		var on := clampf((dark - 0.3) * 3.0, 0.0, 1.0)
		for c in cars:
			var f: Vector2 = c["fwd"]
			if not c.get("hidden", false):
				out.append([Iso.to_screen(c["pos"] + f * (float(c["hl"]) + 0.9)), 30.0, 0.75 * on])
		out.append([Iso.to_screen(p_pos + p_fwd * 0.7), 26.0, 0.7 * on])
		for r in rival_state:
			out.append([Iso.to_screen(r["pos"] + Vector2.from_angle(r["head"]) * 0.6), 20.0, 0.55 * on])
	if events != null:
		out.append_array(events.flash_lights())
	Iso.terrain_on = was
	return out


func _update_life(delta: float) -> void:
	var riding := active and er_timer <= 0.0
	for p in peds:
		p["t"] -= delta
		p["cool"] = maxf(0.0, p["cool"] - delta)
		if p["giver"]:
			_update_giver(p, delta, riding)
			continue
		if p.has("going_in"):
			# stepping in at the door: fading out, then in the shop for a while
			p["fade"] = float(p.get("fade", 1.0)) - delta * DOOR_FADE
			if p["fade"] <= 0.0:
				p["inside"] = p["going_in"]
				p.erase("going_in")
			continue
		if float(p.get("inside", 0.0)) <= 0.0:
			p["fade"] = minf(1.0, float(p.get("fade", 1.0)) + delta * DOOR_FADE)
		# townsfolk cheer you on as you ride past: they stop, jump and shout
		if p["cheer"] > 0.0:
			p["cheer"] -= delta
			p["phase"] += delta * 11.0
			continue
		if riding and p["cool"] <= 0.0 and p_pos.distance_to(p["pos"]) < 4.5:
			p["cool"] = randf_range(14.0, 24.0)
			if randf() < 0.45:
				p["cheer"] = 2.6
				p["roll"] = randi()   # the jump or one of their other cheers (Sprites.PASS_MOVES)
				p["shout"] = String(CHEERS.pick_random()).replace("{n}", Game.player_name)
				continue
		# and the rivals, a little less loudly
		if p["cool"] <= 0.0 and int(Engine.get_process_frames() + int(p["phase"] * 10.0)) % 20 == 0:
			for i in rival_state.size():
				if (rival_state[i]["pos"] as Vector2).distance_to(p["pos"]) < 3.5:
					p["cool"] = randf_range(10.0, 20.0)
					if randf() < 0.5:
						p["cheer"] = 2.0
						p["roll"] = 0   # (the jump)
						p["shout"] = ["Go %s!", "Come on %s!", "Faster, %s!", "%s! %s!"].pick_random().replace("%s", Talk.rivals[i]["short"])
					break
			if p["cheer"] > 0.0:
				continue
		p["say_t"] = maxf(0.0, float(p.get("say_t", 0.0)) - delta)
		if float(p.get("inside", 0.0)) > 0.0:
			# in a shop: come back out (fading in at the door) a while later with something to say about it
			p["inside"] -= delta
			if p["inside"] <= 0.0:
				p["fade"] = 0.0
				p["say"] = SHOP_LINES.pick_random()
				p["say_t"] = 2.2
				p["shop_cool"] = randf_range(25.0, 60.0)
			continue
		p["shop_cool"] = maxf(0.0, float(p.get("shop_cool", randf_range(0.0, 20.0))) - delta)
		if int(p["road"]) >= 0:
			var r: Dictionary = roads[p["road"]]
			var s_was: float = p["s"]
			p["s"] = _wrap_s(r, p["s"] + p["dir"] * p["speed"] * delta)
			if p["shop_cool"] <= 0.0 and not p["giver"]:
				for d in _doors(p["road"]):
					if float(d[1]) == float(p["side"]) and (float(d[0]) - s_was) * (float(d[0]) - float(p["s"])) <= 0.0:
						p["shop_cool"] = randf_range(15.0, 40.0)
						if randf() < 0.45:
							p["going_in"] = randf_range(4.0, 12.0)
						break
			if p["t"] <= 0.0 or (not r["closed"] and (p["s"] <= 0.5 or p["s"] >= float(r["len"]) - 0.5)):
				p["dir"] = -p["dir"]
				p["t"] = randf_range(8.0, 25.0)
			var at := _road_at(r, p["s"])
			p["pos"] = at[0] + Vector2(-at[1].y, at[1].x) * p["side"] * (ROAD_HW + 0.5)
			p["face"] = at[1] * float(p["dir"])
			p["phase"] += delta * 8.0
			continue
		var to: Vector2 = p["target"] - p["pos"]
		if to.length() < 0.1 or p["t"] <= 0.0:
			var a := randf() * TAU
			p["target"] = PLAZA + Vector2(cos(a), sin(a)) * randf_range(2.6, 6.2)
			p["t"] = randf_range(4.0, 12.0)
		else:
			p["pos"] += to.normalized() * minf(to.length(), 0.65 * delta)
			p["face"] = to.normalized()
			p["phase"] += delta * 8.0
	for b in boats:
		b["a"] += b["w"] * delta
	# the skiers on the slopes: down the run, then off up the lift and back at the top for another, out of sight
	for e in season_props:
		if e["kind"] == "skier" and e["season"] == Season.current:
			var u: float = e.get("u", e["ph"])
			if u < 1.0:
				u = minf(1.0, u + delta * float(e["speed"]))
			elif not _in_view(_skier_at(e, 1.0)) and not _in_view(_skier_at(e, 0.0)):
				u = 0.0
			e["u"] = u


## The doors along a road that people walking past can go into (shops, hotels, cafes, ...).
func _doors(ri: int) -> Array:
	if not road_doors.has(ri):
		var out: Array = []
		for bi in buildings.size():
			var b: Dictionary = buildings[bi]
			if int(b.get("road", -1)) != ri:
				continue
			var at := _road_at(roads[ri], float(b.get("s", 0.0)))
			var n := Vector2(-at[1].y, at[1].x)
			out.append([float(b.get("s", 0.0)), 1.0 if ((b["door"] as Vector2) - at[0]).dot(n) > 0.0 else -1.0, bi])
		road_doors[ri] = out
	return road_doors[ri]


func _update_rivals(delta: float) -> void:
	for i in rival_state.size():
		var r: Dictionary = rival_state[i]
		r["phase"] += delta * 9.0 if r["state"] != "idle" else 0.0
		r["socks"] = maxf(0.0, r["socks"] - delta)
		r["bread"] = maxf(0.0, r["bread"] - delta)
		r["roller"] = maxf(0.0, r["roller"] - delta)
		if r["pu"] != "":
			r["pu_hold"] += delta
			if _rival_wants(i):
				_use_powerup(i)
		if r["stun"] > 0.0:
			r["stun"] -= delta
			r["fall"] += delta
			continue
		match r["state"]:
			"idle":
				r["idle"] -= delta
				if r["idle"] <= 0.0:
					r["path"] = _route(r["pos"], astar.get_point_position(randi() % astar.get_point_count()), r["off"])
					r["state"] = "wander"
			"wander":
				if _follow(r, delta):
					r["state"] = "idle"
					r["idle"] = randf_range(2.0, 7.0)
			"to_shop":
				var o := _order_by_id(r["order"])
				if o.is_empty() or o["state"] != "open":
					r["state"] = "idle"
					r["idle"] = 1.0
				elif _follow(r, delta):
					r["state"] = "handoff"
					r["wait"] = HANDOFF_TIME
			"handoff":
				r["wait"] -= delta
				if r["wait"] <= 0.0:
					var o := _order_by_id(r["order"])
					if not o.is_empty() and o["state"] == "open":
						o["state"] = "rival"
						o["rival"] = i
						r["path"] = _route(r["pos"], spots[o["dest"]]["pos"], r["off"])
						r["state"] = "to_dest"
						if p_pos.distance_to(shops[o["shop"]]["window"]) < 25.0:
							Talk.say(i, "order_stolen", true)
							Game.feed.emit("%s snagged the %s order!" % [Talk.rivals[i]["short"], shops[o["shop"]]["name"]], Talk.rivals[i]["color"])
					else:
						r["state"] = "idle"
						r["idle"] = 1.0
			"to_dest":
				if randf() < 0.0035 * delta * 6.0:
					r["stun"] = 3.0
					r["fall"] = 0.0
					Talk.say(i, "rival_crash")
				elif _follow(r, delta):
					var o := _order_by_id(r["order"])
					if not o.is_empty():
						o["state"] = "done"
						rival_score[i] += 1
						if int(o["dest"]) == site_spot and events != null:
							events.crew_lunch()
						if randf() < 0.4:
							Talk.say(i, "rival_delivered")
					r["state"] = "idle"
					r["idle"] = randf_range(1.0, 4.0)


const RIVAL_CUT := 0.6   # tiles: how far a rival cuts the corners of its route

## Now and then the news helicopter flies in from the edge of the map, follows you round town for a minute or so (off
## to one side, a little ahead), then heads off again.
func _update_news(delta: float) -> void:
	match news_state:
		"off":
			if not active:
				return
			news_t -= delta
			if news_t <= 0.0:
				news = NewsHeli.new()
				var from := Vector2(N, N) * 0.5 + Vector2.from_angle(randf() * TAU) * N * 0.7
				news.place(from, p_pos - from)
				news_state = "on"
				news_t = randf_range(NEWS_STAY[0], NEWS_STAY[1])
		"on":
			news_t -= delta
			news.update(delta, p_pos + p_fwd * 3.0 + Vector2(3.5, -3.5))
			if news_t <= 0.0 or not active:
				news_state = "leaving"
				news_t = 0.0
				news.set_meta("away", Vector2(N, N) * 0.5 + (news.pos - Vector2(N, N) * 0.5).normalized() * N * 0.9)
		"leaving":
			var away: Vector2 = news.get_meta("away")
			news.update(delta, away)
			if news.pos.distance_to(away) < 3.0:
				news_state = "off"
				news_t = randf_range(NEWS_EVERY[0], NEWS_EVERY[1])


## The Tour de Crankmore champion's visits (see Game.CHAMPION): announced about once an hour, then he waits at Race HQ
## for CHAMPION_WAIT seconds.
func _update_champion(delta: float) -> void:
	if not active:
		return
	if champion_left > 0.0:
		var was := champion_left
		champion_left = maxf(0.0, champion_left - delta)
		if champion_left <= 0.0:
			Game.toast.emit("%s has left town. Maybe next time." % Game.CHAMPION["name"], Color(0.8, 0.85, 1.0))
		elif int(was / 60.0) != int(champion_left / 60.0):
			Game.toast.emit("%s leaves Race HQ in %d minute%s!" % [Game.CHAMPION["name"], int(champion_left / 60.0) + 1, "" if champion_left < 60.0 else "s"], Game.CHAMPION["color"])
		return
	champion_t -= delta
	if champion_t <= 0.0:
		champion_t = randf_range(Game.CHAMPION_EVERY[0], Game.CHAMPION_EVERY[1])
		champion_left = Game.CHAMPION_WAIT
		Game.toast.emit("ANNOUNCEMENT: %s, winner of the Tour de Crankmore, is visiting town! Get to Race HQ within 5 minutes to race him!" % Game.CHAMPION["name"], Game.CHAMPION["color"])


## Moves a rival along its path. Returns true when the path is finished.
## Rivals cruise at the difficulty's share of their FTP (Game.rival_share), so they slow down on climbs and fly down the other side just like you.
func _follow(r: Dictionary, delta: float) -> bool:
	var path: Array = r["path"]
	if not path.is_empty():
		var bk: Dictionary = r["bike"]
		var g := PowerUps.felt_grade(clampf(grade_at(r["pos"], path[0] - r["pos"]), -0.1, 0.1), r["roller"])
		var mps := minf(Game.speed_from_power(float(r["ftp"]) * Game.rival_share(), bk["mass"], bk["cda"], bk["crr"], g, r["mass"]), MAX_TOWN_SPEED)
		if r["socks"] > 0.0:
			mps *= PowerUps.SOCKS_BOOST
		if r["blocked"]:
			mps = minf(mps, 1.2)
		r["speed"] = move_toward(r["speed"], mps * TILES_PER_MS * PACE, 3.0 * delta)
	var step: float = r["speed"] * delta
	while not path.is_empty() and step > 0.0:
		var target: Vector2 = path[0]
		var to: Vector2 = target - r["pos"]
		if path.size() > 1 and to.length() < RIVAL_CUT:
			path.pop_front()   # round the corner: head for the next point already
			continue
		if to.length() <= step:
			r["pos"] = target
			step -= to.length()
			path.pop_front()
		else:
			r["pos"] += to.normalized() * step
			# lean into the new heading over a short distance instead of snapping to it
			r["head"] = lerp_angle(r["head"], to.angle(), 1.0 - exp(-step * 5.0))
			step = 0.0
	return path.is_empty()


func _order_by_id(id: int) -> Dictionary:
	for o in orders:
		if o["id"] == id:
			return o
	return {}


func _update_orders(delta: float) -> void:
	order_clock -= delta
	var open_count := 0
	for o in orders:
		if o["state"] == "open":
			open_count += 1
			o["age"] += delta
			if o["age"] > 90.0:
				o["state"] = "done"
	if order_clock <= 0.0 and open_count < 3:
		_post_order()
		order_clock = randf_range(9.0, 16.0)
	elif order_clock <= 0.0:
		order_clock = 4.0
	for i in range(orders.size() - 1, -1, -1):
		if orders[i]["state"] == "done":
			orders.remove_at(i)
	if not carry.is_empty():
		carry["t_left"] -= delta
		if carry["t_left"] <= 0.0:
			Game.toast.emit("Too slow! The pizza went cold and the customer won't pay. Order #%d lost." % carry["id"], Color(1.0, 0.45, 0.35))
			chef_says(int(carry["shop"]), "cold")
			Talk.say_random("late", true)
			carry["state"] = "done"
			carry = {}


func _post_order() -> void:
	var busy := {}
	for o in orders:
		if o["state"] == "open":
			busy[o["shop"]] = true
	var s := randi() % shops.size()
	for tries in 8:
		if not busy.has(s):
			break
		s = randi() % shops.size()
	if busy.has(s):
		return
	var d := randi() % spots.size()
	var dist: float = shops[s]["window"].distance_to(spots[d]["pos"])
	for tries in 10:
		if dist > 16.0 and dist < 60.0:
			break
		d = randi() % spots.size()
		dist = shops[s]["window"].distance_to(spots[d]["pos"])
	# now and then a party orders a stack of pizzas: five stops, one after the other
	if challenge.is_empty() and randf() < RUSH_CHANCE and not orders.any(func(q): return q.has("rush")):
		var stops: Array = []
		var at: Vector2 = shops[s]["window"]
		for k in CHALLENGES["rush"]["stops"]:
			var best := -1
			for _try in 30:
				var c := randi() % spots.size()
				var dd: float = spots[c]["pos"].distance_to(at)
				if not c in stops and dd > 6.0 and dd < 22.0:
					best = c
					break
			if best < 0:
				break
			stops.append(best)
			at = spots[best]["pos"]
		if stops.size() == CHALLENGES["rush"]["stops"]:
			var o := {"id": next_order_id, "shop": s, "dest": stops[0], "pay": 18 * stops.size(), "rush": stops, "leg": 0,
				"state": "open", "rival": -1, "age": 0.0, "t_left": 0.0, "t_total": 0.0, "quality": 1.0}
			next_order_id += 1
			orders.append(o)
			Game.toast.emit("RING RING!  PIZZA RUSH! %s: %d pizzas for a party, %d stops!" % [shops[s]["name"], stops.size(), stops.size()], Color(1.0, 0.6, 0.2))
			chef_says(s, "rush")
			return
	# now and then it's the construction crew's lunch break
	var crew := site_spot >= 0 and randf() < SITE_ORDER_CHANCE and not orders.any(func(q): return q["dest"] == site_spot and q["state"] != "done")
	if crew:
		d = site_spot
		dist = shops[s]["window"].distance_to(spots[d]["pos"])
	var o := {"id": next_order_id, "shop": s, "dest": d, "pay": 14 + int(dist * 0.8) + randi() % 8,
		"state": "open", "rival": -1, "age": 0.0, "t_left": 0.0, "t_total": 0.0, "quality": 1.0}
	next_order_id += 1
	orders.append(o)
	if crew:
		o["pay"] += 10   # a big order: pizzas for the whole crew
		Game.toast.emit("RING RING!  Hungry builders! %s: $%d to the %s site!" % [shops[s]["name"], o["pay"], spots[d]["name"]], Color(1.0, 0.85, 0.3))
		chef_says(s, "crew")
	else:
		Game.toast.emit("RING RING!  %s: $%d to %s!" % [shops[s]["name"], o["pay"], spots[d]["name"]], Color(1.0, 0.85, 0.3))
		chef_says(s, "ring")
	var hunters := 0
	var idx := range(Talk.rivals.size())
	idx.shuffle()
	for i in idx:
		var r: Dictionary = rival_state[i]
		if r["stun"] > 0.0 or not (r["state"] in ["idle", "wander"]):
			continue
		if hunters < 3 and randf() < 0.55:
			r["order"] = o["id"]
			r["path"] = _route(r["pos"], shops[s]["window"], r["off"])
			r["state"] = "to_shop"
			hunters += 1


func _update_pickups(delta: float) -> void:
	var picking := false
	if carry.is_empty():
		for o in orders:
			if o["state"] != "open":
				continue
			if p_pos.distance_to(shops[o["shop"]]["window"]) < 2.7 and p_speed < 2.0:
				picking = true
				handoff_shop = o["shop"]
				handoff += delta / HANDOFF_TIME
				if handoff >= 1.0:
					_take_order(o)
					handoff = 0.0
				break
	handoff_live = picking
	if not picking:
		handoff = maxf(0.0, handoff - delta * 2.0)
	if not carry.is_empty() and p_pos.distance_to(spots[carry["dest"]]["pos"]) < 2.7 and p_speed < 2.0:
		_deliver()


## What the pizza shops' bakers say (in the message box, with their faces: art/face_chef_<shop>.png).
const CHEF_LINES := {
	"ring": ["Order up! Who's riding?", "Ring ring! Hot one going out!", "Pizza's in the oven, I need a rider!", "Fresh order! Don't let the others grab it!"],
	"rush": ["A PARTY ORDER! Five pizzas! Hurry!", "Big one! Party pizzas, all over town!", "Mamma mia, look at this order!"],
	"crew": ["The builders are hungry! Extra cheese for the crew!", "Lunch for the whole site! Don't drop it!"],
	"pickup": ["Hot and fresh! Go go go!", "Mind the potholes!", "Don't you dare let it go cold!", "Fastest rider in town, eh? Prove it!"],
	"cold": ["You let it go COLD?!", "Cold pizza! In MY town?!", "That was a beautiful pie. Was."],
	"flying": ["My pizza! On the ROAD!", "Was that... my pizza flying?!", "Noooo! The pizza!"],
}
const CHEF_MOODS := {"ring": "happy", "rush": "shocked", "crew": "happy", "pickup": "smug", "cold": "annoyed", "flying": "shocked"}


## Shop `si`'s baker says one of their CHEF_LINES[kind].
func chef_says(si: int, kind: String) -> void:
	if si < 0 or si >= shops.size():
		return
	var sh: Dictionary = shops[si]
	var key := "chef_" + String(sh["name"]).to_lower().replace("'", "").replace(" ", "_")
	Game.racer_says.emit(key, sh["name"], CHEF_LINES[kind].pick_random(), CHEF_MOODS[kind], sh["color"])


func _take_order(o: Dictionary) -> void:
	o["state"] = "player"
	# the deadline: ride the road there at a decent clip or you don't get paid
	var dist := _path_len(shops[o["shop"]]["window"], spots[o["dest"]]["pos"])
	o["t_total"] = 15.0 + dist / (1.6 * PACE)
	o["t_left"] = o["t_total"]
	carry = o
	Game.toast.emit("Got it! Deliver to %s in %ds or no pay!" % [spots[o["dest"]]["name"], int(o["t_total"])], Color(0.5, 1.0, 0.5))
	chef_says(int(o["shop"]), "pickup")
	if o.has("rush"):
		start_challenge("rush", {"stops": o["rush"].size()})
	var best := -1
	var best_d := 1e9
	for i in rival_state.size():
		var r: Dictionary = rival_state[i]
		if r["order"] == o["id"] and r["state"] in ["to_shop", "handoff"]:
			r["state"] = "idle"
			r["idle"] = 1.0
			var dd: float = r["pos"].distance_to(p_pos)
			if dd < best_d:
				best_d = dd
				best = i
	if best >= 0:
		Talk.say(best, "order_won", true)


func _deliver() -> void:
	# a pizza rush: drop this one and head straight on to the next stop
	if carry.has("rush") and int(carry["leg"]) < carry["rush"].size() - 1:
		var leg_pay: int = int(carry["pay"]) / int(carry["rush"].size())
		Game.add_money(leg_pay)
		carry["leg"] = int(carry["leg"]) + 1
		var from: Vector2 = spots[carry["dest"]]["pos"]
		carry["dest"] = carry["rush"][carry["leg"]]
		carry["t_total"] = 15.0 + _path_len(from, spots[carry["dest"]]["pos"]) / (1.6 * PACE)
		carry["t_left"] = carry["t_total"]
		if challenge.get("kind", "") == "rush":
			challenge["done"] = carry["leg"]
		Game.toast.emit("Stop %d of %d: +$%d. Next: %s" % [carry["leg"], carry["rush"].size(), leg_pay, spots[carry["dest"]]["name"]], Color(0.4, 1.0, 0.5))
		return
	if carry.has("rush") and challenge.get("kind", "") == "rush":
		challenge["done"] = carry["rush"].size()
		_end_challenge(float(challenge["p_sum"]) / maxf(float(challenge["p_t"]), 0.1) >= float(challenge_watts()))
	var frac: float = clampf(carry["t_left"] / carry["t_total"], 0.0, 1.0)
	var tip := int(carry["pay"] * 0.6 * frac)
	var base := int(carry["pay"] * carry["quality"])
	Game.add_money(base + tip)
	Game.deliveries += 1
	Game.toast.emit("DELIVERED!  $%d + $%d tip" % [base, tip], Color(0.4, 1.0, 0.5))
	if int(carry["dest"]) == site_spot and events != null:
		events.crew_lunch()
	carry["state"] = "done"
	carry = {}
	Game.save_game()
	if randf() < 0.5:
		Talk.say_random("delivered")


func _on_rival_say(rival: int, text: String) -> void:
	bubbles[rival] = {"text": text, "t": 4.5}


# ======================================================================
# Power-ups (see PowerUps). "who" is -1 for the player, otherwise a rival index; -2 means nobody.
# ======================================================================

func _rider_pos(who: int) -> Vector2:
	return p_pos if who < 0 else rival_state[who]["pos"]


func _rider_fwd(who: int) -> Vector2:
	return p_fwd if who < 0 else Vector2.from_angle(rival_state[who]["head"])


func _rider_name(who: int) -> String:
	return Game.player_name if who < 0 else Talk.rivals[who]["short"]


## On the ground, in the ER or otherwise out of play.
func _is_down(who: int) -> bool:
	if who < 0:
		return not active or er_timer > 0.0 or p_down > 0.0
	return rival_state[who]["stun"] > 0.0


func _is_big(who: int) -> bool:
	return (bread_t if who < 0 else float(rival_state[who]["bread"])) > 0.0


## The closest opponent of `who` within `within` tiles (-2 if none). Rivals go for the player first.
func _nearest_opponent(who: int, within: float, prefer_player := false) -> int:
	var me := _rider_pos(who)
	var player_ok := who >= 0 and not _is_down(-1) and p_pos.distance_to(me) < within
	if player_ok and prefer_player:
		return -1
	var best := -1 if player_ok else -2
	var bd := p_pos.distance_to(me) if player_ok else within
	for i in rival_state.size():
		if i == who or _is_down(i):
			continue
		var d: float = rival_state[i]["pos"].distance_to(me)
		if d < bd:
			best = i
			bd = d
	return best


## The pizza shop with a pizza waiting (an open order) nearest to `p`, or -1.
func _nearest_order_shop(p: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for o in orders:
		if o["state"] == "open":
			var d: float = shops[o["shop"]]["window"].distance_to(p)
			if d < bd:
				bd = d
				best = o["shop"]
	return best


func _knock_down(who: int, secs: float, by: int, how: String) -> void:
	if who < 0:
		p_down = secs
		p_fall = 0.0
		p_fall_pizza = not carry.is_empty()
		p_speed = 0.0
		Game.toast.emit("%s %s! Down for %d s." % [_rider_name(by), how, int(secs)], Color(1.0, 0.45, 0.35))
		if by >= 0:
			Talk.say(by, "pu_hit_player", true)
	else:
		var r: Dictionary = rival_state[who]
		r["stun"] = secs
		r["fall"] = 0.0
		r["speed"] = 0.0
		if by < 0:
			Game.feed.emit("Got %s! Down for %d s." % [Talk.rivals[who]["short"], int(secs)], Color(0.5, 1.0, 0.5))
			Talk.say(who, "pu_ouch", true)


## A power-up person hands one to whoever rides past with empty hands.
# ---- paid challenges ---------------------------------------------------------------
## Things around town that pay if you can ride hard enough: a thief making off on a bike, a runaway dog, a hot rod
## that wants to race. The quarry goes as fast as you would at `pct` of your FTP, so riding above that closes the gap
## (or wins the race) and easing off lets it get away. TownEvents starts them and draws the quarry where
## challenge_pos() says; the HUD shows the target watts and how it's going.
const CHALLENGES := {
	"thief": {"title": "CATCH THE THIEF", "pct": 1.10, "reward": 150, "gap": 12.0, "catch": 2.0, "lose": 45.0, "time": 80.0},
	"bike_thief": {"title": "STOP THE BIKE THIEF", "pct": 1.30, "reward": 300, "gap": 14.0, "catch": 2.0, "lose": 55.0, "time": 100.0},
	"dog": {"title": "CATCH THE DOG", "pct": 0.80, "reward": 50, "gap": 10.0, "catch": 1.5, "lose": 40.0, "time": 75.0},
	"race": {"title": "BEAT THE HOT ROD", "pct": 1.20, "reward": 300, "dist": 220.0, "count": 3.0},
	"kid_race": {"title": "RACE THE KID", "pct": 0.60, "reward": 20, "dist": 260.0, "count": 3.0},
	"rush": {"title": "PIZZA RUSH", "pct": 0.80, "reward": 120, "stops": 5},
	"climb": {"title": "HILL SPRINT", "pct": 1.05, "reward": 60},
	"zombies": {"title": "ZOMBIE KIDS!", "pct": 0.50, "reward": 0, "gap": 6.0, "escape": 25.0, "time": 45.0},
	"gulls": {"title": "SEAGULLS!", "pct": 0.90, "reward": 0, "gap": 15.0, "escape": 40.0, "time": 90.0},   # a head start, and time to get away
}
const RACE_RUNOUT := 40.0    # tiles of route past a race's finish line, for the loser to carry on along
const RUSH_CHANCE := 0.12     # orders that are a pizza rush: five stops, paid a bonus for an 80% FTP average
const CLIMB_EVERY := [150.0, 300.0]   # seconds between hill sprints showing up
var climbs: Array = []        # {road, dir, s0, s1, name, start, end}: the hills a sprint can be on (found at generation)
var climb_t := 90.0
var outage_t := 0.0           # a power cut: the street lamps are out
var challenge := {}   # the one going on: a CHALLENGES entry plus kind, state ("count", "on", "won", "lost"), t, gap / me_m, them_m


## Starts a challenge (extra fields merged in). False if one is already going or you're not out riding.
func start_challenge(kind: String, extra := {}) -> bool:
	if not challenge.is_empty() or not active or er_timer > 0.0:
		return false
	challenge = (CHALLENGES[kind] as Dictionary).duplicate()
	challenge.merge(extra, true)
	challenge["kind"] = kind
	challenge["t"] = 0.0
	challenge["state"] = "count" if challenge.has("dist") else "armed" if kind == "climb" else "on"
	challenge["me_m"] = 0.0
	challenge["them_m"] = 0.0
	challenge["p_sum"] = 0.0
	challenge["p_t"] = 0.0
	challenge["done"] = 0
	if challenge.has("dist"):   # a race to a line along the roads from here
		_race_route()
	return true


## Plots a race's route from where you are now: along the roads, straight on at junctions where it can, else the turn
## that keeps going longest (never into a dead end if there's another way), a bit past the finish line so the loser
## can carry on. Shortens the race if every way runs out.
func _race_route() -> void:
	var tpm := TILES_PER_MS * PACE
	var want := float(challenge["dist"]) * tpm
	var legs: Array = []      # {road, s, dir, len, at}: `at` tiles along the route where the leg starts
	var turns: Array = []     # {j, side, pos, fwd_in, fwd_out, at}: where it turns, for the red arrows
	var picks := {}           # junction -> "left" / "straight" / "right": the way the route goes there
	var road := rr
	var s := rs
	var dir := rdir
	var from_j := _from_j
	var total := 0.0
	for guard in 16:
		var nj := _next_junction_on(road, s, dir, from_j)
		var ahead: float = nj[1]
		if total + ahead >= want + RACE_RUNOUT or int(nj[0]) < 0:
			legs.append({"road": road, "s": s, "dir": dir, "len": minf(ahead, want + RACE_RUNOUT - total), "at": total})
			total += minf(ahead, want + RACE_RUNOUT - total)
			break
		legs.append({"road": road, "s": s, "dir": dir, "len": ahead, "at": total})
		total += ahead
		var ji: int = nj[0]
		var lab := _label_options(_options(ji, road, dir))
		if lab.is_empty():
			break
		var best := ""
		var best_run := -1.0
		for side in ["straight", "left", "right"]:
			if not lab.has(side):
				continue
			var o: Dictionary = lab[side]
			var on := _next_junction_on(o["road"], o["s"], o["dir"], ji)
			var run: float = 1000.0 if int(on[0]) >= 0 else float(on[1])   # a dead end only goes so far
			if run >= want + RACE_RUNOUT - total:
				run = 1000.0
			if run > best_run + 0.5:
				best_run = run
				best = side
		var pick: Dictionary = lab[best]
		picks[ji] = best
		var fin: Vector2 = (_road_at(roads[road], s + dir * (ahead - 1.0))[1] as Vector2) * dir
		if best != "straight" and total < want:
			turns.append({"j": ji, "side": best, "pos": junctions[ji]["pos"], "fwd_in": fin,
				"fwd_out": (_road_at(roads[pick["road"]], pick["s"])[1] as Vector2) * float(pick["dir"]), "at": total})
		road = pick["road"]
		s = pick["s"]
		dir = pick["dir"]
		from_j = ji
	var route := {"legs": legs, "turns": turns, "picks": picks}
	if total - RACE_RUNOUT < want:   # it ran out: a shorter race
		challenge["dist"] = maxf(40.0, (total - RACE_RUNOUT) / tpm)
	challenge["route"] = route
	var fin := route_at(route, float(challenge["dist"]) * tpm, 0.0)
	challenge["finish"] = fin[0]
	challenge["finish_fwd"] = fin[1]


## A point `d` tiles along a race route, `lane` tiles right of the road's middle: [world position, heading].
func route_at(route: Dictionary, d: float, lane: float) -> Array:
	var legs: Array = route["legs"]
	var leg: Dictionary = legs[legs.size() - 1]
	for l in legs:
		if d < float(l["at"]) + float(l["len"]):
			leg = l
			break
	var r: Dictionary = roads[leg["road"]]
	var at := _road_at(r, _wrap_s(r, float(leg["s"]) + float(leg["dir"]) * (d - float(leg["at"]))))
	var fwd: Vector2 = (at[1] as Vector2) * float(leg["dir"])
	return [at[0] + Vector2(-fwd.y, fwd.x) * lane, fwd]


## The route leg `d` tiles along a race.
func _route_leg(route: Dictionary, d: float) -> Dictionary:
	var legs: Array = route["legs"]
	for l in legs:
		if d < float(l["at"]) + float(l["len"]):
			return l
	return legs[legs.size() - 1]


## The quarry's speed (m/s): yours at `pct` of your FTP on this grade.
func _quarry_mps() -> float:
	var bike := Game.bike()
	return minf(Game.speed_from_power(float(challenge["pct"]) * Game.ftp, bike["mass"], bike["cda"], bike["crr"], PowerUps.felt_grade(grade, 0.0)), MAX_TOWN_SPEED)


## The watts a challenge asks for.
func challenge_watts() -> int:
	return int(round(float(challenge.get("pct", 1.0)) * Game.ftp))


func _update_challenge(delta: float) -> void:
	if challenge.is_empty():
		return
	var c := challenge
	c["t"] = float(c["t"]) + delta
	if c["state"] == "won" or c["state"] == "lost":
		c["end"] = float(c.get("end", 3.0)) - delta
		if c["end"] <= 0.0:
			challenge = {}
		return
	if er_timer > 0.0 or not active:
		_end_challenge(false)
		return
	var me := p_speed / (TILES_PER_MS * PACE)
	var them := _quarry_mps()
	c["p_sum"] = float(c["p_sum"]) + Trainer.power() * delta
	c["p_t"] = float(c["p_t"]) + delta
	match "race" if c.has("dist") else c["kind"]:
		"rush":
			pass   # ends at the last stop (see _deliver)
		"climb":
			_update_climb(c)
		"gulls", "zombies":
			c["gap"] = float(c["gap"]) + (me - them) * delta
			if float(c["gap"]) >= float(c["escape"]) or float(c["t"]) > float(c["time"]):
				_end_challenge(true)
			elif float(c["gap"]) <= 0.0:
				_end_challenge(false)
		"race":
			if c["state"] == "count":
				c["count"] = float(c["count"]) - delta
				if c["count"] <= 0.0:
					c["state"] = "on"
					c["t"] = 0.0
					_race_route()   # from the start line, where you are now
					Game.toast.emit("GO!!", Color(1.0, 0.85, 0.3))
				return
			c["me_m"] = float(c["me_m"]) + me * delta
			# off the route: a wrong turn at a junction (a moment's grace while you cross one)
			var leg := _route_leg(c["route"], float(c["me_m"]) * TILES_PER_MS * PACE)
			if rr != int(leg["road"]) or rdir != float(leg["dir"]):
				c["off_t"] = float(c.get("off_t", 0.0)) + delta
				if float(c["off_t"]) > 1.5:
					c["why"] = "Wrong way - you left the race route!"
					_end_challenge(false)
					return
			else:
				c["off_t"] = 0.0
			c["them_m"] = float(c["them_m"]) + minf(them, float(c["t"]) * 4.0) * delta   # it pulls away from a standing start
			if float(c["me_m"]) >= float(c["dist"]):
				_end_challenge(true)
			elif float(c["them_m"]) >= float(c["dist"]):
				_end_challenge(false)
		_:
			c["gap"] = maxf(0.0, float(c["gap"]) - (me - them) * delta)
			if float(c["gap"]) <= float(c["catch"]):
				_end_challenge(true)
			elif float(c["gap"]) >= float(c["lose"]) or float(c["t"]) > float(c["time"]):
				_end_challenge(false)


func _end_challenge(won: bool) -> void:
	challenge["state"] = "won" if won else "lost"
	challenge["end"] = 3.0
	match challenge["kind"]:
		"rush":
			var avg := int(float(challenge["p_sum"]) / maxf(float(challenge["p_t"]), 0.1))
			if won:
				Game.add_money(int(challenge["reward"]))
				Game.toast.emit("PIZZA RUSH DONE! Average %d W - bonus +$%d" % [avg, int(challenge["reward"])], Color(0.4, 1.0, 0.5))
			else:
				Game.toast.emit("Rush done, but you averaged %d W (needed %d W): no bonus" % [avg, challenge_watts()], Color(1.0, 0.7, 0.4))
			return
		"climb":
			if won:
				Game.add_money(int(challenge["reward"]))
				Game.toast.emit("%s in %s! Beat %s: +$%d" % [str(challenge["name"]).to_upper(), _clock(float(challenge["t"])), _clock(float(challenge["target"])), int(challenge["reward"])], Color(0.4, 1.0, 0.5))
			else:
				Game.toast.emit(str(challenge.get("why", "Too slow up %s" % challenge["name"])), Color(1.0, 0.6, 0.5))
			return
		"zombies":
			if won:
				Game.toast.emit("You escaped the zombies!", Color(0.6, 1.0, 0.6))
			else:
				Game.add_money(-10)
				p_speed = 0.0
				Game.toast.emit("The zombies got you! You hand over $10 of candy money.", Color(1.0, 0.6, 0.4))
			return
		"gulls":
			if won:
				Game.toast.emit("You lost the seagulls!", Color(0.6, 0.9, 1.0))
			else:
				if not carry.is_empty():
					carry["state"] = "done"
					carry = {}
					Game.toast.emit("The seagulls stole your pizza! Order lost.", Color(1.0, 0.5, 0.4))
				else:
					Game.toast.emit("The seagulls mobbed you!", Color(1.0, 0.6, 0.5))
			return
	if won:
		Game.add_money(int(challenge["reward"]))
		Game.save_game()
		Game.toast.emit("%s! +$%d" % [{"thief": "You caught the thief", "bike_thief": "You caught the bike thief", "dog": "You caught the dog", "race": "You beat the hot rod", "kid_race": "You beat the kid"}[challenge["kind"]], int(challenge["reward"])], Color(0.4, 1.0, 0.5))
	else:
		Game.toast.emit(str(challenge.get("why", {"thief": "The thief got away...", "bike_thief": "The bike thief got away...", "dog": "The dog got away...", "race": "The hot rod wins. Eat its dust!", "kid_race": "The kid beat you! Ouch."}[challenge["kind"]])), Color(1.0, 0.6, 0.5))


func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## Hill sprints: the climbs in town where the road keeps going up for a while (found once, when the town is made).
## Every few minutes one near you lights up: a START line at the foot and a FINISH at the top, and a time to beat
## that riding it at 105% of your FTP would give.
func _find_climbs() -> void:
	climbs.clear()
	const SUFFIX := ["Wall", "Ramp", "Kicker", "Grind", "Climb", "Hill"]
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var length: float = r["len"]
		for dir in [1.0, -1.0]:
			var s := 1.0
			while s < length - 12.0:
				var s0: float = s if dir > 0.0 else length - s
				var best := -1.0
				var sum := 0.0
				var n := 0
				var q := 0.0
				while q < 40.0:
					var at := _road_at(r, _wrap_s(r, s0 + dir * q))
					sum += grade_at(at[0], at[1] * dir)
					n += 1
					q += 1.0
					if q >= 12.0 and sum / n >= 0.04:
						best = q
				if best > 0.0:
					var a := _road_at(r, s0)
					var b := _road_at(r, _wrap_s(r, s0 + dir * best))
					climbs.append({"road": ri, "dir": dir, "s0": s0, "s1": _wrap_s(r, s0 + dir * best), "len": best,
						"name": "%s %s" % [str(r["name"]), SUFFIX[climbs.size() % SUFFIX.size()]], "start": a[0], "end": b[0],
						"start_fwd": a[1] * dir, "end_fwd": b[1] * dir})
					s += best + 6.0
				else:
					s += 3.0


func _update_climbs(delta: float) -> void:
	climb_t -= delta
	if climb_t > 0.0 or not challenge.is_empty() or not active or climbs.is_empty():
		return
	climb_t = randf_range(CLIMB_EVERY[0], CLIMB_EVERY[1])
	var near: Array = climbs.filter(func(c): return p_pos.distance_to(c["start"]) > 6.0 and p_pos.distance_to(c["start"]) < 30.0)
	if near.is_empty():
		return
	var c: Dictionary = near.pick_random()
	# the time to beat: each tile of it at 105% of your FTP on its grade
	var bike := Game.bike()
	var r: Dictionary = roads[c["road"]]
	var target := 0.0
	var q := 0.0
	while q < float(c["len"]):
		var at := _road_at(r, _wrap_s(r, float(c["s0"]) + float(c["dir"]) * q))
		var g := grade_at(at[0], at[1] * float(c["dir"]))
		target += (1.0 / (TILES_PER_MS * PACE)) / minf(Game.speed_from_power(1.05 * Game.ftp, bike["mass"], bike["cda"], bike["crr"], g), MAX_TOWN_SPEED)
		q += 1.0
	var extra := c.duplicate()
	extra["target"] = target
	extra["armed_t"] = 240.0
	if start_challenge("climb", extra):
		Game.toast.emit("HILL SPRINT: %s - get up it in %s! Find the START line." % [c["name"], _clock(target)], Color(1.0, 0.85, 0.3))


func _update_climb(c: Dictionary) -> void:
	var r: Dictionary = roads[c["road"]]
	var along := (rs - float(c["s0"])) * float(c["dir"])   # how far past the start line you are, if you're on its road
	if r["closed"]:
		along = fposmod(along + 2.0, float(r["len"])) - 2.0
	if c["state"] == "armed":
		c["armed_t"] = float(c["armed_t"]) - get_process_delta_time()
		if rr == int(c["road"]) and rdir == float(c["dir"]) and along >= 0.0 and along < 1.0:
			c["state"] = "on"
			c["t"] = 0.0
			Game.toast.emit("GO! %s" % c["name"], Color(1.0, 0.85, 0.3))
		elif c["armed_t"] <= 0.0 or p_pos.distance_to(c["start"]) > 45.0:
			challenge = {}   # you didn't go for it: it fades away
		return
	if rr != int(c["road"]) or rdir != float(c["dir"]):
		c["why"] = "Off course - %s abandoned" % c["name"]
		_end_challenge(false)
		return
	c["progress"] = clampf(along / float(c["len"]), 0.0, 1.0)
	if along >= float(c["len"]):
		_end_challenge(float(c["t"]) <= float(c["target"]))
	elif float(c["t"]) > float(c["target"]) * 1.6:
		c["why"] = "Too slow up %s" % c["name"]
		_end_challenge(false)


## Where the quarry is: [world position, heading] — the gap ahead of you along your road (the hot rod: its lead over
## you, in the car lane beside you).
func challenge_pos(lane := CAR_LANE) -> Array:
	var tpm := TILES_PER_MS * PACE
	if challenge.get("kind", "") == "race":   # waiting beside you for GO, then along the route (`lane`: where the hot rod's got to)
		if challenge["state"] == "count":
			return _rail_ahead(0.4, lane)
		return route_at(challenge["route"], float(challenge["them_m"]) * tpm + 0.4, lane)
	if challenge.get("kind", "") == "kid_race":   # riding alongside you, nearer the middle of the road
		if challenge["state"] == "count":
			return _rail_ahead(0.0, BIKE_LANE - 0.4)
		return route_at(challenge["route"], float(challenge["them_m"]) * tpm, BIKE_LANE - 0.4)
	if challenge.get("kind", "") == "gulls" or challenge.get("kind", "") == "zombies":
		# they come in from out of sight behind you and close up to where they really are
		var run_in := maxf(0.0, 45.0 - float(challenge["t"]) * 12.0)
		return _rail_ahead(-(float(challenge["gap"]) + run_in) * tpm, 0.6)
	return _rail_ahead(float(challenge.get("gap", 0.0)) * tpm, BIKE_LANE)


## A point `d` tiles ahead of you along your road (behind if negative), `lane` tiles to the right of its middle.
func _rail_ahead(d: float, lane: float) -> Array:
	var r: Dictionary = roads[rr]
	var at := _road_at(r, _wrap_s(r, rs + rdir * d))
	var fwd: Vector2 = at[1] * rdir
	return [at[0] + Vector2(-fwd.y, fwd.x) * lane, fwd]


## The chequered finish line painted across the road for a hot rod race.
func _draw_finish() -> void:
	var kind: String = challenge.get("kind", "")
	if kind == "climb" and challenge["state"] in ["armed", "on"]:
		_draw_line_banner(challenge["start"], challenge["start_fwd"], "START", Color(0.2, 0.75, 0.3))
		_draw_line_banner(challenge["end"], challenge["end_fwd"], "FINISH", Color(0.95, 0.2, 0.2), false)
		return
	if not challenge.has("dist") or challenge["state"] == "lost":
		return
	_draw_line_banner(challenge["finish"], challenge["finish_fwd"], "FINISH", Color(0.95, 0.2, 0.2), false)
	# a big red arrow painted on the road before each turn the route takes
	var done := float(challenge["me_m"]) * TILES_PER_MS * PACE
	for t in (challenge["route"] as Dictionary)["turns"]:
		if float(t["at"]) > done - 1.0:
			_draw_turn_arrow(t["pos"], t["fwd_in"], t["fwd_out"])


## A red arrow painted on the approach to junction `j`: up the right-hand lane, then round into the way out.
func _draw_turn_arrow(j: Vector2, fin: Vector2, fout: Vector2) -> void:
	var rt := Vector2(-fin.y, fin.x)
	var pts: Array = []   # the arrow's middle line, world
	for k in 7:   # straight up the lane
		pts.append(j - fin * (4.2 - k * 0.45) + rt * 0.6)
	var bend: Vector2 = pts[pts.size() - 1]
	for k in range(1, 6):   # curving round into the exit
		var u := k / 5.0
		pts.append(bend + fin * sin(u * PI * 0.5) * 0.9 + fout * (1.0 - cos(u * PI * 0.5)) * 1.3)
	var red := Color(0.9, 0.12, 0.1)
	var edge := Color(0.45, 0.04, 0.04)
	for pass_ in 2:   # a dark edge, then the red over it
		var ww := 0.22 + (0.07 if pass_ == 0 else 0.0)
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in pts.size():   # one ribbon down the middle line, each point pushed out along its corner's normal
			var d: Vector2 = ((pts[mini(i + 1, pts.size() - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
			left.append(pts[i] + d.orthogonal() * ww)
			right.append(pts[i] - d.orthogonal() * ww)
		right.reverse()
		draw_colored_polygon(_to_screen_poly(left + right), edge if pass_ == 0 else red)
		var tip: Vector2 = pts[pts.size() - 1]
		var d: Vector2 = (tip - pts[pts.size() - 2]).normalized()
		var hn := d.orthogonal() * (0.62 + (0.08 if pass_ == 0 else 0.0))
		var head := PackedVector2Array([tip + hn, tip + d * (0.8 + (0.1 if pass_ == 0 else 0.0)), tip - hn])
		draw_colored_polygon(_to_screen_poly(head), edge if pass_ == 0 else red)


## A chequered line across the road at `f`; with `banner`, a banner over it on two poles, its top bar running across
## the road from pole to pole.
func _draw_line_banner(f: Vector2, fwd: Vector2, text: String, col: Color, banner := true) -> void:
	var n := Vector2(-fwd.y, fwd.x)
	# two rows of squares straight across the road, kerb to kerb, centred on the middle of the road
	var squares := 10
	var w := ROAD_HW * 2.0 / squares
	for k in squares:
		for row in 2:
			var c: Vector2 = f + n * (-ROAD_HW + k * w) + fwd * ((row - 1) * 0.15)
			var q := PackedVector2Array([Iso.to_screen(c), Iso.to_screen(c + n * w), Iso.to_screen(c + n * w + fwd * 0.15), Iso.to_screen(c + fwd * 0.15)])
			draw_colored_polygon(q, Color.WHITE if (k + row) % 2 == 0 else Color(0.1, 0.1, 0.12))
	if not banner:   # just the painted line, and its name over the middle of it
		_label(text, Iso.to_screen(f) + Vector2(0, -10), 8, Color.WHITE)
		return
	# a banner on two poles, just outside the kerbs
	var a := Iso.to_screen(f - n * (ROAD_HW + 0.25))
	var b := Iso.to_screen(f + n * (ROAD_HW + 0.25))
	draw_line(a, a + Vector2(0, -40), Iso.OUTLINE, 2.0)
	draw_line(b, b + Vector2(0, -40), Iso.OUTLINE, 2.0)
	var bar := PackedVector2Array([a + Vector2(0, -46), b + Vector2(0, -46), b + Vector2(0, -37), a + Vector2(0, -37)])
	draw_colored_polygon(bar, col)
	draw_polyline(PackedVector2Array([bar[0], bar[1], bar[2], bar[3], bar[0]]), Iso.OUTLINE, 1.0)
	_label(text, (a + b) * 0.5 + Vector2(0, -38), 8, Color.WHITE)


const GIVER_COUNT := 8

## A gift-giver's day: "away" until they turn up at a spot out of sight, then "ready" (on the pavement, holding up the
## power-up they'll hand over, a present on the map). When someone takes it, a moment's "thanks" and they hold up
## another one, a different one at random. They never walk, and never pop up where you can see.
func _update_giver(p: Dictionary, delta: float, riding: bool) -> void:
	p["phase"] = float(p["phase"]) + delta
	p["say_t"] = maxf(0.0, float(p.get("say_t", 0.0)) - delta)
	match p["state"]:
		"ready":
			_try_give(p, riding)
			if p["gcool"] > 0.0:
				p["state"] = "thanks"
				p["t"] = 1.5
		"thanks":
			p["t"] -= delta
			if p["t"] <= 0.0:
				p["state"] = "ready"
				p["gcool"] = 0.0
		"away":
			p["gcool"] = maxf(0.0, p["gcool"] - delta)
			if p["gcool"] <= 0.0:
				if _in_view(p["pos"]):
					_giver_spot(p)   # you're looking right at the spot: pick another
				else:
					p["state"] = "ready"


## Somewhere on a pavement, out of sight of the player.
func _giver_spot(p: Dictionary) -> void:
	for _try in 60:
		var ri := randi() % roads.size()
		var r: Dictionary = roads[ri]
		var s := randf_range(1.0, float(r["len"]) - 1.0)
		var at := _road_at(r, s)
		var side := 1.0 if randf() < 0.5 else -1.0
		var q: Vector2 = at[0] + Vector2(-at[1].y, at[1].x) * side * (ROAD_HW + 0.55)
		var ix := int(q.x)
		var iy := int(q.y)
		if ix < 0 or iy < 0 or ix >= N or iy >= N or solid[iy * N + ix] != 0 or tiles[iy * N + ix] == T.WATER or _in_view(q):
			continue
		p["pos"] = q
		p["road"] = ri
		p["face"] = -Vector2(-at[1].y, at[1].x) * side   # facing the road
		return


## Roughly on screen: around the player (where the camera is or is heading), up or down the hills, or in the camera's
## view right now.
func _in_view(q: Vector2) -> bool:
	var d := Iso.to_screen(q, Iso.ground_z(q)) - Iso.to_screen(p_pos, Iso.ground_z(p_pos))
	return (absf(d.x) < 460.0 and absf(d.y) < 300.0) or on_screen(q)


## Whether something standing at `q` could be seen in the camera's view now (`up`: px it reaches above the ground,
## past a person's height: a balloon, flames on a roof; `wide`: px it spreads out round its spot). Sprites stand up to
## ~150 px tall from their spot, so the view reaches further below the bottom edge.
func on_screen(q: Vector2, up := 0.0, wide := 0.0) -> bool:
	if not is_inside_tree():
		return false
	var vr: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	return vr.grow_individual(80.0 + wide, 70.0 + wide, 80.0 + wide, 170.0 + up + wide).has_point(Iso.to_screen(q, 0.0 if Iso.terrain_on else Iso.ground_z(q)))


func _draw_giver(p: Dictionary, ground: Vector2) -> void:
	if p["state"] == "away":
		return
	var look := Sprites.cast(p, Sprites.givers(), true)
	if look == "":
		return
	draw_colored_polygon(PackedVector2Array([ground + Vector2(-5, 0), ground + Vector2(0, -2.5), ground + Vector2(5, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
	if p["state"] == "ready" or not Sprites.draw_strip(self, "giver_%s_idle" % look, ground, float(p["phase"]), 6.0):
		# holding the present out over the road (after handing it over, without an empty-handed sheet: standing still)
		Sprites.draw_strip(self, "giver_%s_wave" % look, ground, float(p["phase"]) if p["state"] == "ready" else 0.0, 8.0)
	if p["state"] == "thanks" and p["shout"] != "":
		_label(p["shout"], ground + Vector2(0, -52), 8, Color(1.0, 0.95, 0.45))
	elif p["state"] == "ready":
		PowerUps.draw_held(self, ground, p["pu"], float(p["phase"]))


func _try_give(p: Dictionary, riding: bool) -> void:
	if riding and pu == "" and p_down <= 0.0 and p_pos.distance_to(p["pos"]) < 2.0:
		pu = p["pu"]
		p["pu"] = PowerUps.pick(PowerUps.TOWN, pu)
		p["gcool"] = 25.0
		p["cheer"] = 1.5
		p["shout"] = "Catch!"
		Game.toast.emit("POWER-UP: %s! %s. Press Y." % [PowerUps.label(pu), PowerUps.DEFS[pu]["blurb"].capitalize()], PowerUps.col(pu))
		return
	for i in rival_state.size():
		var r: Dictionary = rival_state[i]
		if r["pu"] == "" and r["stun"] <= 0.0 and r["pos"].distance_to(p["pos"]) < 2.0:
			r["pu"] = p["pu"]
			p["pu"] = PowerUps.pick(PowerUps.TOWN, r["pu"])
			r["pu_hold"] = 0.0
			p["gcool"] = 25.0
			if active and p_pos.distance_to(r["pos"]) < 25.0:
				Game.feed.emit("%s grabbed a %s!" % [Talk.rivals[i]["short"], PowerUps.label(r["pu"])], Talk.rivals[i]["color"])
			return


## Uses the power-up `who` is carrying. Returns false (and keeps it) when it can't be used right now.
func _use_powerup(who: int) -> bool:
	var kind: String = pu if who < 0 else rival_state[who]["pu"]
	if kind == "":
		return false
	var me := _rider_pos(who)
	match kind:
		"portal":
			var si := _nearest_order_shop(me)
			if who < 0:
				if not carry.is_empty():
					Game.toast.emit("You already have a pizza on board. Save the portal for later!", Color(1.0, 0.8, 0.5))
					return false
				if si < 0:
					Game.toast.emit("No pizzas waiting anywhere yet. Hang on to the portal!", Color(1.0, 0.8, 0.5))
					return false
				place_on(shops[si])
				invuln = maxf(invuln, 1.0)
				Game.toast.emit("PEPPERONI PORTAL! Whoosh, straight to %s." % shops[si]["name"], PowerUps.col(kind))
			else:
				if si < 0:
					return false
				var r: Dictionary = rival_state[who]
				for o in orders:
					if o["state"] == "open" and o["shop"] == si:
						r["order"] = o["id"]
				r["pos"] = shops[si]["window"]
				r["path"] = []
				r["state"] = "handoff"
				r["wait"] = 0.8
				if active:
					Game.feed.emit("%s portalled to %s!" % [Talk.rivals[who]["short"], shops[si]["name"]], Talk.rivals[who]["color"])
		"wrench":
			if who < 0:
				if Game.bike_hp() >= float(Game.bike()["hp"]):
					Game.toast.emit("Your bike is already in perfect shape. Keep the wrench for later!", Color(1.0, 0.8, 0.5))
					return false
				Game.hp[Game.equipped] = float(Game.bike()["hp"])
				Game.save_game()
				Game.toast.emit("BIKE WRENCH! Clank clank... good as new.", PowerUps.col(kind))
			else:
				rival_state[who]["stun"] = 0.0
		"walkie":
			var v := _nearest_opponent(who, 1e9, who >= 0)
			if v == -2:
				return false
			# the mascot comes dancing in from out of sight up the road
			var from := _rider_pos(v) + _rider_fwd(v) * 3.0
			for d in range(4, 30):
				if not _in_view(from):
					break
				from = _rider_pos(v) + _rider_fwd(v) * d
			mascots.append({"victim": v, "t": PowerUps.MASCOT_TIME, "pos": from, "phase": randf() * TAU})
			if who < 0:
				Game.toast.emit("WALKIE TALKIE! \"Mascot, go dance on %s!\"" % _rider_name(v), PowerUps.col(kind))
			elif v < 0:
				Game.toast.emit("%s radioed a pizza mascot into your way!" % _rider_name(who), Color(1.0, 0.55, 0.45))
		"frisbee":
			var v := _nearest_opponent(who, PowerUps.FRISBEE_RANGE_M / M_PER_TILE)
			if v == -2:
				if who < 0:
					Game.toast.emit("Nobody within %d m. Get closer to a rival, then toss!" % int(PowerUps.FRISBEE_RANGE_M), Color(1.0, 0.8, 0.5))
				return false
			frisbees.append({"from": who, "to": v, "u": 0.0})
			Sprites.start_throw("YOU" if who < 0 else str(Talk.rivals[who]["short"]))
		"mitt":
			if not _carrying(who).is_empty():
				if who < 0:
					Game.toast.emit("Your hands are full: you've got a pizza on board. Save the mitt for later!", Color(1.0, 0.8, 0.5))
				return false
			var v := _mitt_target(who)
			if v == -2:
				if who < 0:
					Game.toast.emit("Nobody carrying a pizza within %d m. Get closer, then grab!" % int(PowerUps.MITT_RANGE_M), Color(1.0, 0.8, 0.5))
				return false
			_snatch_pizza(who, v)
			if who < 0:
				player_bubble = {"text": "Pizza frisbee!", "t": 1.5}
		"socks":
			if who < 0:
				socks_t = PowerUps.SOCKS_TIME
				Game.toast.emit("FIRE SOCKS! 30% faster for 15 s!", PowerUps.col(kind))
			else:
				rival_state[who]["socks"] = PowerUps.SOCKS_TIME
		"breadsticks":
			if who < 0:
				bread_t = PowerUps.BREAD_TIME
				Game.toast.emit("BREADSTICKS! You're HUGE. Run 'em over!", PowerUps.col(kind))
			else:
				rival_state[who]["bread"] = PowerUps.BREAD_TIME
				if active and p_pos.distance_to(me) < 25.0:
					Game.feed.emit("%s ate the breadsticks and got HUGE!" % Talk.rivals[who]["short"], Talk.rivals[who]["color"])
		"roller":
			if who < 0:
				roller_t = PowerUps.ROLLER_TIME
				Game.toast.emit("DOUGH ROLLER! The hills are rolled flat for 15 s!", PowerUps.col(kind))
			else:
				rival_state[who]["roller"] = PowerUps.ROLLER_TIME
	if who < 0:
		pu = ""
	else:
		rival_state[who]["pu"] = ""
	return true


## When a rival fires off what it's carrying.
func _rival_wants(i: int) -> bool:
	var r: Dictionary = rival_state[i]
	var hold: float = r["pu_hold"]
	if hold < 1.5:
		return false
	if r["stun"] > 0.0:
		return r["pu"] == "wrench"
	var near_player := active and not _is_down(-1) and p_pos.distance_to(r["pos"]) < 18.0
	match r["pu"]:
		"portal":
			return r["state"] in ["idle", "wander"] and _nearest_order_shop(r["pos"]) >= 0
		"wrench":
			return hold > 30.0
		"walkie":
			return near_player or hold > 40.0
		"frisbee":
			return _nearest_opponent(i, PowerUps.FRISBEE_RANGE_M / M_PER_TILE) != -2
		"mitt":
			return r["state"] != "to_dest" and _mitt_target(i) != -2
		"socks":
			return r["state"] in ["to_shop", "to_dest"]
		"breadsticks":
			return (near_player and p_pos.distance_to(r["pos"]) < 6.0) or hold > 40.0
		"roller":
			var path: Array = r["path"]
			return r["state"] in ["to_shop", "to_dest"] and not path.is_empty() and grade_at(r["pos"], path[0] - r["pos"]) > 0.03
	return false


## The order `who` is out delivering ({} if none).
func _carrying(who: int) -> Dictionary:
	if who < 0:
		return carry
	var r: Dictionary = rival_state[who]
	return _order_by_id(r["order"]) if r["state"] == "to_dest" else {}


## The nearest rider to `who` within the Oven Mitt's reach who has a pizza on board to snatch (-2 if none). A pizza
## rush's party pizzas are too many to grab.
func _mitt_target(who: int) -> int:
	var me := _rider_pos(who)
	var best := -2
	var bd := PowerUps.MITT_RANGE_M / M_PER_TILE
	for v in range(-1, rival_state.size()):
		if v == who or (v < 0 and (not active or er_timer > 0.0)):
			continue
		var o := _carrying(v)
		if o.is_empty() or o.has("rush"):
			continue
		var d := _rider_pos(v).distance_to(me)
		if d < bd:
			bd = d
			best = v
	return best


## The Oven Mitt: `who` grabs the pizza `from` is carrying and takes it on to the customer themselves.
func _snatch_pizza(who: int, from: int) -> void:
	var o := _carrying(from)
	if from < 0:
		carry = {}
		Game.toast.emit("%s snatched your pizza with an Oven Mitt!" % _rider_name(who), Color(1.0, 0.45, 0.35))
		Talk.say(who, "pu_hit_player", true)
	else:
		var r: Dictionary = rival_state[from]
		r["state"] = "idle"
		r["idle"] = 1.5
		r["path"] = []
		if who < 0 or (active and p_pos.distance_to(r["pos"]) < 25.0):
			Talk.say(from, "pu_ouch", true)
	if who < 0:
		o["state"] = "player"
		o["rival"] = -1
		o["t_total"] = 15.0 + _path_len(p_pos, spots[o["dest"]]["pos"]) / (1.6 * PACE)
		o["t_left"] = o["t_total"]
		carry = o
		Game.toast.emit("OVEN MITT! Snatched %s's pizza. Deliver to %s in %ds!" % [_rider_name(from), spots[o["dest"]]["name"], int(o["t_total"])], PowerUps.col("mitt"))
		player_bubble = {"text": "Mine now!", "t": 1.5}
	else:
		var r: Dictionary = rival_state[who]
		o["state"] = "rival"
		o["rival"] = who
		r["order"] = o["id"]
		r["path"] = _route(r["pos"], spots[o["dest"]]["pos"], r["off"])
		r["state"] = "to_dest"
		if from >= 0 and active and p_pos.distance_to(r["pos"]) < 25.0:
			Game.feed.emit("%s snatched %s's pizza!" % [_rider_name(who), _rider_name(from)], Talk.rivals[who]["color"])


## Pizza mascots dance just in front of their victim, slowing them to a crawl.
func _update_mascots(delta: float) -> void:
	p_blocked = false
	for r in rival_state:
		r["blocked"] = false
	for k in range(mascots.size() - 1, -1, -1):
		var m: Dictionary = mascots[k]
		m["t"] -= delta
		m["phase"] += delta
		var v: int = m["victim"]
		if m["t"] <= 0.0 or v >= rival_state.size():
			# done: off it dances, out of sight
			if not on_screen(m["pos"]):
				mascots.remove_at(k)
			else:
				var away: Vector2 = (m["pos"] as Vector2) - (_rider_pos(v) if v < rival_state.size() else p_pos)
				m["pos"] += (away.normalized() if away.length() > 0.01 else Vector2(1, 0)) * 4.0 * delta
			continue
		var f := _rider_fwd(v)
		var goal := _rider_pos(v) + f * 0.9 + Vector2(-f.y, f.x) * sin(m["phase"] * 2.0) * 0.35
		m["pos"] = m["pos"].move_toward(goal, (9.0 if m["pos"].distance_to(goal) > 3.0 else 6.0) * delta)
		if m["pos"].distance_to(goal) < 0.8:
			if v < 0:
				p_blocked = true
			else:
				rival_state[v]["blocked"] = true


func _update_frisbees(delta: float) -> void:
	for k in range(frisbees.size() - 1, -1, -1):
		var fz: Dictionary = frisbees[k]
		fz["u"] += delta / 0.45
		if fz["u"] >= 1.0:
			frisbees.remove_at(k)
			var to: int = fz["to"]
			if to < rival_state.size() and not _is_down(to) and not (to < 0 and invuln > 0.0):
				_knock_down(to, PowerUps.DOWN_TIME, fz["from"], "beaned you with a Pizza Frisbee")


## A rider on breadsticks flattens anyone they ride into.
func _update_squash() -> void:
	var who: Array = [-1]
	who.append_array(range(rival_state.size()))
	for a in who:
		if not _is_big(a) or _is_down(a):
			continue
		for b in who:
			if b == a or _is_big(b) or _is_down(b) or (b < 0 and invuln > 0.0):
				continue
			if _rider_pos(a).distance_to(_rider_pos(b)) < 0.8:
				_knock_down(b, PowerUps.SQUASH_TIME, a, "flattened you with breadstick power")


func _bread_k(t: float) -> float:
	return 1.0 + (PowerUps.BREAD_SCALE - 1.0) * clampf(minf(PowerUps.BREAD_TIME - t, t) / 0.4, 0.0, 1.0) if t > 0.0 else 1.0


# ======================================================================
# Drawing
# ======================================================================

func _draw() -> void:
	Iso.terrain_on = true
	_draw_world()
	Iso.terrain_on = false


func _draw_world() -> void:
	var inv := get_canvas_transform().affine_inverse()
	var vr: Rect2 = inv * get_viewport_rect()
	_draw_backdrop(vr)
	_draw_ground(vr)
	_draw_lake(vr)
	_draw_roads(vr)
	_draw_finish()
	_draw_beacons()

	var items: Array = []
	var big := vr.grow(260.0)
	for b in buildings:
		if big.has_point(Iso.to_screen(b["pos"] + b["size"] * 0.5)):
			items.append([b["key"], 0, b])
	# what might be on screen: everything stands up from its spot on the ground (trees, the tube man and the big
	# trucks reach 100-150 px up), so things just below the bottom edge still show their tops
	var tv := vr.grow_individual(80.0, 70.0, 80.0, 170.0)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c in [tv.position, tv.position + Vector2(tv.size.x, 0), tv.end, tv.position + Vector2(0, tv.size.y)]:
		var w := Iso.to_world(c)
		lo = lo.min(w)
		hi = hi.max(w)
	for cy in range(floori(lo.y / CHUNK) - 1, floori(hi.y / CHUNK) + 2):
		for cx in range(floori(lo.x / CHUNK) - 1, floori(hi.x / CHUNK) + 2):
			for t in tree_chunks.get(Vector2i(cx, cy), []):
				if tv.has_point(Iso.to_screen(t["pos"])):
					items.append([t["pos"].x + t["pos"].y, 1, t])
	for c in cars:
		if not c.get("hidden", false) and tv.has_point(Iso.to_screen(c["pos"])):
			items.append([c["pos"].x + c["pos"].y, 2, c])
	for i in rival_state.size():
		var r: Dictionary = rival_state[i]
		if tv.has_point(Iso.to_screen(r["pos"])):
			items.append([r["pos"].x + r["pos"].y, 3, i])
	for p in props:
		if p.get("season", Season.current) == Season.current and tv.has_point(Iso.to_screen(p["pos"])):
			items.append([p["pos"].x + p["pos"].y, 5, p])
	for e in season_props:
		if e["season"] == Season.current:
			var sp := _sprop_pos(e)
			if tv.grow(100.0).has_point(Iso.to_screen(sp)):   # (a volleyball game, a picnic, a kite: spread out round it)
				items.append([sp.x + sp.y, 9, e, sp])
	for p in peds:
		if float(p.get("inside", 0.0)) <= 0.0 and tv.has_point(Iso.to_screen(p["pos"])):
			items.append([p["pos"].x + p["pos"].y, 6, p])
	if events != null:
		for a in events.actors():
			# (balloons, flying birds and flames are drawn well above their spot, ropes and pumpkin patches spread out)
			var at := Iso.to_screen(a["pos"])
			if tv.has_point(at) or tv.has_point(at - Vector2(0, float(a.get("lift", 0.0)) + float(a.get("h", 0.0)) + 40.0)) \
				or (a["type"] == "fx" and tv.grow(140.0).has_point(at)):
				items.append([a["pos"].x + a["pos"].y, 10, a])
	for si in shops.size():
		var cp: Vector2 = shops[si]["chef"]
		if tv.has_point(Iso.to_screen(cp)):
			items.append([cp.x + cp.y, 7, si])
	for m in mascots:
		if tv.has_point(Iso.to_screen(m["pos"])):
			items.append([m["pos"].x + m["pos"].y, 8, m])
	items.append([p_pos.x + p_pos.y, 4, null])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		if pops != null:
			pops.begin(it)
		match it[1]:
			0:
				# stand level on the lowest corner; the uphill side sinks into the slope
				var b: Dictionary = it[2]
				var bz := minf(minf(Iso.ground_z(b["pos"]), Iso.ground_z(b["pos"] + b["size"])),
					minf(Iso.ground_z(b["pos"] + Vector2(b["size"].x, 0)), Iso.ground_z(b["pos"] + Vector2(0, b["size"].y))))
				Iso.held(bz, _draw_building.bind(b))
			1: Iso.held(Iso.ground_z(it[2]["pos"]), _draw_tree.bind(it[2]))
			2: Iso.held(Iso.ground_z(it[2]["pos"]), _draw_car.bind(it[2]))
			3: _draw_rival(it[2])
			4: _draw_player()
			5: Iso.held(Iso.ground_z(it[2]["pos"]), _draw_prop.bind(it[2]))
			6: Iso.held(Iso.ground_z(it[2]["pos"]), _draw_ped.bind(it[2]))
			7: Iso.held(Iso.ground_z(shops[it[2]]["chef"]), _draw_chef.bind(it[2]))
			8: PowerUps.draw_mascot(self, Iso.to_screen(it[2]["pos"]), it[2]["phase"])
			9: Iso.held(Iso.ground_z(it[3]), _draw_sprop.bind(it[2], it[3]))
			10:
				Sprites.fade = float(it[2].get("fade", 1.0))   # (stepping out of a door or a van, or in)
				Iso.held(Iso.ground_z(it[2]["pos"]), events.draw_actor.bind(self, it[2]))
				Sprites.fade = 1.0
		if pops != null:
			pops.end()
	if pops != null:
		pops.finish(vr)
	_draw_gondola_cable()
	_draw_lifts(vr)
	_draw_overlays()


func _draw_backdrop(vr: Rect2) -> void:
	# sky bands
	var bands := [Color(0.36, 0.6, 0.95), Color(0.45, 0.72, 0.97), Color(0.58, 0.82, 0.98), Color(0.72, 0.9, 1.0)].map(Season.sky)
	var top := minf(vr.position.y, -1700.0)
	for k in bands.size():
		var y0 := lerpf(top, -500.0, k / float(bands.size()))
		var y1 := lerpf(top, -500.0, (k + 1) / float(bands.size()))
		draw_rect(Rect2(vr.position.x - 10, y0, vr.size.x + 20, y1 - y0 + 1), bands[k])
	draw_rect(Rect2(vr.position.x - 10, -500.0, vr.size.x + 20, maxf(0.0, vr.end.y + 500.0)), bands[3])
	# sun + clouds
	draw_circle(Vector2(900, -1500), 70.0, Color(1.0, 0.95, 0.6))
	draw_circle(Vector2(900, -1500), 58.0, Color(1.0, 0.98, 0.8))
	for k in 6:
		var cp := Vector2(fposmod(k * 520.0 + t_ * 6.0, 3600.0) - 1800.0, -1350.0 + (k % 3) * 120.0)
		Sprites.draw_image(self, "scenery_cloud_%s" % ["a", "b", "c"][k % 3], cp + Vector2(0, 44), false, 1.0, 3.0)
	var base_y := -540.0
	# far range
	var far := PackedVector2Array([Vector2(-3200, base_y)])
	for k in 25:
		far.append(Vector2(-3200 + k * 270.0, base_y - 260.0 - fmod(k * 137.0, 220.0)))
	far.append(Vector2(3500, base_y))
	draw_colored_polygon(far, Color(0.5, 0.6, 0.85).lerp(Season.SNOW, 0.35 if Season.is_("winter") else 0.0))
	# Mt. Crankmore
	var apex := Vector2(-80, base_y - 1150)
	var m := PackedVector2Array([Vector2(-1500, base_y), Vector2(-900, base_y - 520), Vector2(-620, base_y - 640), apex,
		Vector2(420, base_y - 720), Vector2(760, base_y - 560), Vector2(1500, base_y)])
	draw_colored_polygon(m, Color(0.36, 0.42, 0.68))
	draw_colored_polygon(PackedVector2Array([apex, Vector2(420, base_y - 720), Vector2(760, base_y - 560), Vector2(1500, base_y), Vector2(200, base_y)]), Color(0.28, 0.33, 0.56))
	# forested lower slopes
	draw_colored_polygon(PackedVector2Array([Vector2(-1500, base_y), Vector2(-1000, base_y - 260), Vector2(-500, base_y - 330), Vector2(0, base_y - 300),
		Vector2(500, base_y - 360), Vector2(1000, base_y - 240), Vector2(1500, base_y)]), Season.ground(Color(0.2, 0.42, 0.32)))
	for k in 34:
		var tx := -1400.0 + k * 85.0
		var ty := base_y - 40.0 - fmod(k * 53.0, 160.0)
		var tc := Season.leaves(Color(0.16, 0.36, 0.27), k) if k % 3 == 0 and Season.is_("fall") else Color(0.16, 0.36, 0.27)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 22, ty + 30), Vector2(tx, ty - 30), Vector2(tx + 22, ty + 30)]), tc)
		if Season.is_("winter"):
			draw_colored_polygon(PackedVector2Array([Vector2(tx - 9, ty - 6), Vector2(tx, ty - 30), Vector2(tx + 9, ty - 6)]), Season.SNOW)
	# snowcap
	var snow := PackedVector2Array([apex, apex + Vector2(-260, 300), apex + Vector2(-170, 270), apex + Vector2(-110, 330), apex + Vector2(-30, 280),
		apex + Vector2(40, 340), apex + Vector2(120, 270), apex + Vector2(220, 320), apex + Vector2(300, 260)])
	draw_colored_polygon(snow, Color(0.97, 0.98, 1.0))
	draw_colored_polygon(PackedVector2Array([apex, apex + Vector2(120, 270), apex + Vector2(220, 320), apex + Vector2(300, 260)]), Color(0.78, 0.84, 0.96))
	draw_polyline(m, Iso.OUTLINE, 2.0)
	_label("MT. CRANKMORE", apex + Vector2(0, 420), 32, Color(1, 1, 1))


func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


func _draw_ground(vr: Rect2) -> void:
	var cs := [vr.position, vr.position + Vector2(vr.size.x, 0), vr.end, vr.position + Vector2(0, vr.size.y)]
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c in cs:
		var w := Iso.to_world(c)
		lo = lo.min(w)
		hi = hi.max(w)
	var x0 := maxi(floori(lo.x) - 1, -MARGIN)
	var y0 := maxi(floori(lo.y) - 1, -MARGIN)
	var lift := ceili(Iso.ground_z(Iso.to_world(vr.get_center())) / (Iso.TH * 0.5)) + 8
	var x1 := mini(ceili(hi.x) + lift, N + MARGIN)
	var y1 := mini(ceili(hi.y) + lift, N + MARGIN)
	var winter := Season.is_("winter")
	var fall := Season.is_("fall")
	var grass_a := Season.ground(Color(0.4, 0.75, 0.32))
	var grass_b := Season.ground(Color(0.37, 0.71, 0.3))
	var speck_a := Season.ground(Color(0.28, 0.58, 0.24))
	var speck_b := Season.ground(Color(0.5, 0.84, 0.4))
	var tuft_a := Season.ground(Color(0.26, 0.55, 0.22))
	var tuft_b := Season.ground(Color(0.3, 0.6, 0.25))
	var forest_a := Season.ground(Color(0.2, 0.48, 0.27))
	var forest_b := Season.ground(Color(0.18, 0.44, 0.25))
	var forest_speck := Season.ground(Color(0.14, 0.34, 0.2))
	var flower_every: int = {"spring": 3, "summer": 11, "fall": 37, "winter": 0}[Season.current]
	for y in range(y0, y1):
		for x in range(x0, x1):
			var h := _hash(x, y)
			var kind := T.FOREST
			if x >= 0 and y >= 0 and x < N and y < N:
				kind = tiles[y * N + x]
			var tile := Vector2(x, y)
			var lit := _slope_light(tile)
			var band := _contour(x, y)
			# the textured look (see Ground): a stepped light level by slope and a light/dark stripe per contour band
			var gname := _ground_name(kind, winter, fall)
			if Ground.tex(gname) != null:
				var light := Ground.band(lit) * (0.95 if band % 2 != 0 and (kind == T.GRASS or kind == T.FOREST) else 1.0)
				var tint := Color(1.15, 1.16, 1.2) if winter and (kind == T.PLAZA or kind == T.SIDEWALK or kind == T.SAND) else Color.WHITE
				Ground.quad(self, PackedVector2Array([Iso.to_screen(tile), Iso.to_screen(tile + Vector2(1, 0)), Iso.to_screen(tile + Vector2(1, 1)),
					Iso.to_screen(tile + Vector2(0, 1))]), gname, light, Color.WHITE, tint)
				if kind != T.PLAZA and kind != T.SIDEWALK and kind != T.SAND and kind != T.FOREST and not winter:
					var fx := 0.2 + float(h % 60) / 100.0
					var fy := 0.2 + float((h >> 6) % 60) / 100.0
					if flower_every > 0 and h % flower_every == 0:
						var flower: Color = [Color(1.0, 0.5, 0.75), Color(1.0, 0.92, 0.3), Color(1, 1, 1), Color(0.6, 0.6, 1.0), Color(1.0, 0.35, 0.3)][(h >> 8) % 5]
						draw_rect(Rect2(Iso.to_screen(tile + Vector2(fx, 1.0 - fy)), Vector2(2, 2)), flower)
				if fall and h % 5 == 0 and kind != T.FOREST:
					draw_rect(Rect2(Iso.to_screen(tile + Vector2(0.3 + (h % 30) * 0.01, 0.6)), Vector2(2, 1)), Season.FALL_LEAVES[(h >> 4) % 4])
				continue
			match kind:
				T.PLAZA:
					# four cobbles per tile, each slightly different
					for q in 4:
						var off := Vector2(q % 2, q / 2) * 0.5
						var hv := (h >> (q * 3)) % 4
						var col: Color = [Color(0.86, 0.74, 0.58), Color(0.82, 0.7, 0.55), Color(0.88, 0.78, 0.62), Color(0.79, 0.67, 0.52)][hv]
						if winter:
							col = col.lerp(Season.SNOW, 0.5)
						Iso.diamond(self, tile + off, Iso.shade(col, lit), 0.0, Vector2(0.5, 0.5))
						draw_line(Iso.to_screen(tile + off), Iso.to_screen(tile + off + Vector2(0.5, 0)), Color(0.64, 0.53, 0.4), 1.0)
						draw_line(Iso.to_screen(tile + off), Iso.to_screen(tile + off + Vector2(0, 0.5)), Color(0.64, 0.53, 0.4), 1.0)
						draw_rect(Rect2(Iso.to_screen(tile + off + Vector2(0.18, 0.12)), Vector2(2, 1)), Color(0.94, 0.85, 0.7))
					if fall and h % 5 == 0:   # leaves blown across the cobbles
						draw_rect(Rect2(Iso.to_screen(tile + Vector2(0.3 + (h % 30) * 0.01, 0.6)), Vector2(2, 1)), Season.FALL_LEAVES[(h >> 4) % 4])
				T.SIDEWALK:
					Iso.diamond(self, tile, Iso.shade(Color(0.88, 0.86, 0.8), lit))
					_tile_edge(tile, Color(0.72, 0.7, 0.66))
					draw_line(Iso.to_screen(tile + Vector2(0.5, 0)), Iso.to_screen(tile + Vector2(0.5, 1)), Color(0.8, 0.78, 0.74), 1.0)
					if h % 7 == 0:
						draw_rect(Rect2(Iso.to_screen(tile + Vector2(0.3, 0.6)), Vector2(3, 1)), Color(0.7, 0.68, 0.64))
					if fall and h % 4 == 0:
						draw_rect(Rect2(Iso.to_screen(tile + Vector2(0.2 + (h % 50) * 0.01, 0.3)), Vector2(2, 1)), Season.FALL_LEAVES[(h >> 5) % 4])
					elif winter and h % 3 == 0:   # snow shovelled to the edge
						draw_line(Iso.to_screen(tile + Vector2(0, 0.1)), Iso.to_screen(tile + Vector2(0, 0.9)), Season.SNOW, 2.0)
				T.FOREST:
					Iso.diamond(self, tile, Iso.shade(forest_a if h % 3 != 0 else forest_b, lit))
					if h % 4 == 0:
						_speck(tile + Vector2(0.3 + (h % 40) * 0.01, 0.5), forest_speck)
				_:
					Iso.diamond(self, tile, Iso.shade(grass_a if h % 5 != 0 else grass_b, lit))
					var fx := 0.2 + float(h % 60) / 100.0
					var fy := 0.2 + float((h >> 6) % 60) / 100.0
					if winter:
						if h % 3 == 0:   # sparkles on the snow
							draw_rect(Rect2(Iso.to_screen(tile + Vector2(fx, fy)), Vector2(1, 1)), Color(1, 1, 1))
					else:
						_speck(tile + Vector2(fx, fy), speck_a)
						_speck(tile + Vector2(fy, fx), speck_b)
						_tuft(tile + Vector2(1.0 - fx * 0.8, fy * 0.7 + 0.1), tuft_a)
						_tuft(tile + Vector2(fy * 0.6 + 0.2, 1.0 - fx * 0.7), tuft_b)
					if h % 17 == 0:
						var pb := Iso.to_screen(tile + Vector2(0.6, 0.3))
						draw_rect(Rect2(pb, Vector2(3, 2)), Color(0.55, 0.55, 0.52))
						draw_rect(Rect2(pb, Vector2(2, 1)), Season.SNOW if winter else Color(0.75, 0.75, 0.72))
					if flower_every > 0 and h % flower_every == 0:
						var flower: Color = [Color(1.0, 0.5, 0.75), Color(1.0, 0.92, 0.3), Color(1, 1, 1), Color(0.6, 0.6, 1.0), Color(1.0, 0.35, 0.3)][(h >> 8) % 5]
						draw_rect(Rect2(Iso.to_screen(tile + Vector2(fx, 1.0 - fy)), Vector2(2, 2)), flower)
					if fall and h % 3 == 0:
						draw_rect(Rect2(Iso.to_screen(tile + Vector2(fy, 1.0 - fx)), Vector2(2, 1)), Season.FALL_LEAVES[(h >> 7) % 4])
			if kind == T.GRASS or kind == T.FOREST:
				var line_col := Color(0.12, 0.3, 0.12, 0.35)
				if _contour(x + 1, y) != band:
					draw_line(Iso.to_screen(tile + Vector2(1, 0)), Iso.to_screen(tile + Vector2(1, 1)), line_col, 1.0)
				if _contour(x, y + 1) != band:
					draw_line(Iso.to_screen(tile + Vector2(0, 1)), Iso.to_screen(tile + Vector2(1, 1)), line_col, 1.0)


## The ground texture for a kind of tile in this season (see Ground).
func _ground_name(kind: int, winter: bool, fall: bool) -> String:
	match kind:
		T.PLAZA:
			return "plaza"
		T.SIDEWALK:
			return "sidewalk"
		T.SAND:
			return "sand"
		T.WATER:
			return ""
		T.FOREST:
			return "snow" if winter else ("grass_fall" if fall else "grass_forest")
	return "snow" if winter else ("grass_fall" if fall else ("grass_spring" if Season.is_("spring") else "grass_meadow"))


func _tile_edge(tile: Vector2, col: Color) -> void:
	draw_line(Iso.to_screen(tile), Iso.to_screen(tile + Vector2(1, 0)), col, 1.0)
	draw_line(Iso.to_screen(tile), Iso.to_screen(tile + Vector2(0, 1)), col, 1.0)


func _tuft(p: Vector2, col: Color) -> void:
	var s := Iso.to_screen(p)
	draw_line(s, s + Vector2(-2, -3), col, 1.0)
	draw_line(s, s + Vector2(0, -4), col, 1.0)
	draw_line(s, s + Vector2(2, -3), col, 1.0)


func _speck(p: Vector2, col: Color) -> void:
	var s := Iso.to_screen(p)
	draw_rect(Rect2(s, Vector2(3, 1)), col)
	draw_rect(Rect2(s + Vector2(1, -1), Vector2(1, 1)), col)


func _draw_lake(vr: Rect2) -> void:
	if not vr.grow(700.0).has_point(Iso.to_screen(LAKE)):
		return
	var winter := Season.is_("winter")
	if winter or Ground.tex("water_creek") == null:
		draw_colored_polygon(lake_screen["sand"], Color(0.96, 0.86, 0.6).lerp(Season.SNOW, 0.75 if winter else 0.0))
		draw_colored_polygon(lake_screen["wet"], Color(0.86, 0.74, 0.5).lerp(Season.SNOW, 0.6 if winter else 0.0))
		draw_colored_polygon(lake_screen["water"], Season.water(Color(0.3, 0.68, 0.95)))
		draw_colored_polygon(lake_screen["mid"], Season.water(Color(0.22, 0.56, 0.88)))
		draw_colored_polygon(lake_screen["deep"], Season.water(Color(0.16, 0.44, 0.78)))
	else:
		# textured: sand, darker wet sand, then the water in three bands that get deeper (darker) towards the middle
		Ground.fill(self, lake_screen["sand"], "sand", Ground.band(1.06), Color(0.96, 0.86, 0.6))
		Ground.fill(self, lake_screen["wet"], "sand", Ground.band(0.86), Color(0.86, 0.74, 0.5))
		Ground.fill(self, lake_screen["water"], "water_creek", Ground.band(1.08), Color(0.3, 0.68, 0.95))
		Ground.fill(self, lake_screen["mid"], "water_creek", Ground.band(0.92), Color(0.22, 0.56, 0.88))
		Ground.fill(self, lake_screen["deep"], "water_creek", Ground.band(0.78), Color(0.16, 0.44, 0.78))
	var shore: PackedVector2Array = lake_screen["water"].duplicate()
	shore.append(shore[0])
	draw_polyline(shore, Color(0.85, 0.95, 1.0), 2.0)
	if winter:
		# frozen: scratches from the skates instead of ripples, and the boats are ashore
		for k in 30:
			var a := k * 2.39
			var p := LAKE + Vector2(cos(a), sin(a)) * _lake_r(a) * (0.15 + 0.7 * fposmod(k * 0.377, 1.0))
			draw_line(Iso.to_screen(p), Iso.to_screen(p + Vector2(cos(a * 3.0), sin(a * 3.0)) * 0.9), Color(1, 1, 1, 0.7), 1.0)
	for k in (0 if winter else 46):
		var a := k * 2.39
		var rr := 0.12 + 0.78 * fposmod(k * 0.377, 1.0)
		var p := LAKE + Vector2(cos(a), sin(a)) * _lake_r(a) * rr
		if sin(t_ * 2.5 + k * 1.7) > 0.55:
			draw_rect(Rect2(Iso.to_screen(p), Vector2(4, 1)), Color(0.9, 0.97, 1.0))
	# dock
	var dw: Array = lake_screen["dock_world"]
	var dmid: Vector2 = (dw[0] as Vector2).lerp(dw[1], 0.5)
	Sprites.draw_image(self, "scenery_dock", Iso.to_screen(dmid) + Vector2(0, 40), (dw[1] as Vector2).x < (dw[0] as Vector2).x)
	# boats
	for b in ([] if winter else boats):
		var a: float = b["a"]
		var p := LAKE + Vector2(cos(a), sin(a)) * _lake_r(a) * float(b["rf"])
		var s := Iso.to_screen(p) + Vector2(0, sin(t_ * 2.0 + a) * 1.5)
		var heading := Vector2(-sin(a), cos(a)) * signf(float(b["w"]))
		Sprites.draw_vehicle(self, "obj_rowboat" if PIZZA_COLORS.find(b["col"]) % 2 == 0 else "obj_canoe", s, heading, Color.WHITE.lerp(b["col"], 0.25), 0, b)


func _draw_roads(vr: Rect2) -> void:
	var v := vr.grow(60.0)
	var vis: Array = []
	for seg in road_draw:
		if v.has_point(seg[0]):
			vis.append(seg)
	var winter_tint := Color(1.12, 1.13, 1.18) if Season.is_("winter") else Color.WHITE
	for seg in vis:
		Ground.fill(self, seg[1], "sidewalk", 0.92, Color(0.7, 0.68, 0.64), winter_tint)
	for seg in vis:
		Ground.fill(self, seg[2], "asphalt", 1.0, Color(0.33, 0.34, 0.4))
	var v2 := vr.grow(40.0)
	for seg in vis:
		if Ground.tex("asphalt") != null:
			break
		for sp in seg[6]:
			draw_rect(Rect2(sp, Vector2(2, 1)), Color(0.27, 0.28, 0.33))
		if not seg[7].is_empty():
			draw_colored_polygon(seg[7], Color(0.78, 0.76, 0.72))
	for z in zebra:
		if v2.has_point(z[0]):
			draw_colored_polygon(z, Color(0.95, 0.95, 0.92))
	for seg in vis:
		for k in [4, 5]:
			if not seg[k].is_empty():
				draw_colored_polygon(seg[k], Color(0.85, 0.85, 0.82))
		if not seg[3].is_empty():
			draw_colored_polygon(seg[3], Color(1.0, 0.84, 0.25))


func _ring(center: Vector2, radius: float, col: Color, width: float, z: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		pts.append(Iso.to_screen(center + Vector2(cos(a), sin(a)) * radius, z))
	draw_polyline(pts, col, width)


func _beacon(p: Vector2, col: Color, text: String) -> void:
	var pulse := 0.5 + 0.5 * sin(t_ * 5.0)
	_ring(p, 1.0 + pulse * 0.25, col, 2.0)
	_ring(p, 0.55, col.darkened(0.2), 2.0)
	var base := Iso.to_screen(p)
	draw_rect(Rect2(base + Vector2(-2, -96), Vector2(4, 96)), Color(col.r, col.g, col.b, 0.35))
	var top := base + Vector2(0, -102 - pulse * 3.0)
	Iso.poly(self, PackedVector2Array([top + Vector2(0, -7), top + Vector2(6, 0), top + Vector2(0, 7), top + Vector2(-6, 0)]), col)
	_label(text, top + Vector2(0, -12), 9, col)


func _draw_beacons() -> void:
	if not active:
		return
	if not carry.is_empty():
		var d: Dictionary = spots[carry["dest"]]
		_beacon(d["pos"], Color(0.3, 1.0, 0.45), "DELIVER: %s" % d["name"])
	else:
		for o in orders:
			if o["state"] == "open":
				var s: Dictionary = shops[o["shop"]]
				_beacon(s["window"], Color(1.0, 0.7, 0.15), "$%d  %s" % [o["pay"], s["name"]])
	for z in zones:
		var col := Color(0.4, 0.8, 1.0) if z["kind"] == "bike" else (Color(1.0, 0.9, 0.3) if z["kind"] == "race" else Color(1.0, 0.4, 0.4))
		_ring(z["pos"], z["r"] * 0.7, col, 2.0)


func _label(text: String, pos: Vector2, size: int, col: Color) -> void:
	var p := pos - Vector2(150, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, 300.0, size, 4, Iso.OUTLINE)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, 300.0, size, col)


func _hides_player(b: Dictionary) -> bool:
	if not active:
		return false
	if b["key"] < p_pos.x + p_pos.y:
		return false
	var pos: Vector2 = b["pos"]
	var size: Vector2 = b["size"]
	var h: float = b["h"] + b["roof_h"] + 10.0
	var a := Iso.to_screen(pos, h)
	var bb := Iso.to_screen(pos + Vector2(size.x, 0))
	var c := Iso.to_screen(pos + size)
	var d := Iso.to_screen(pos + Vector2(0, size.y))
	return Rect2(Vector2(d.x, a.y), Vector2(bb.x - d.x, c.y - a.y)).grow(6.0).has_point(Iso.to_screen(p_pos, 14.0))


func _draw_building(b: Dictionary) -> void:
	Iso.fade = 0.3 if _hides_player(b) else 1.0
	_draw_building_inner(b)
	Iso.fade = 1.0
	var kind: String = b["kind"]
	var always := kind in ["pizza", "bike", "er", "race", "gondola", "townhall", "site"]
	var center: Vector2 = b["pos"] + b["size"] * 0.5
	if always or (active and p_pos.distance_to(center) < 7.0) or kind == "hotel":
		var col := Color(1.0, 0.95, 0.5) if always else Color(1, 1, 1)
		_label(b["name"], Iso.to_screen(center, b["h"] + b["roof_h"] + 14.0), 9 if always else 8, col)


var _chalet_designs := 0   # how many art/building_chalet_NN.png there are (counted on first use)

## The picture for a building (art/building_*.png), or "" to draw it in code. Every named building has its own design;
## the chalets pick one of CHALET_DESIGNS. Cached in the building.
func _building_art(b: Dictionary) -> String:
	if b.has("art"):
		return b["art"]
	var art := ""
	match b["kind"]:
		"er":
			art = "hospital"
		"race":
			art = "building_race_hq"
		"gondola":
			art = "building_gondola_base"
		"townhall":
			art = "building_town_hall"
		"site":
			art = "building_construction_site"
		"pizza", "bike", "shop", "hotel", "condo":
			art = "building_" + _shop_slug(str(b["name"]).trim_suffix(" II"))
		"chalet":
			if _chalet_designs == 0:
				while Sprites.sheet("building_chalet_%02d" % (_chalet_designs + 1)) != null:
					_chalet_designs += 1
				_chalet_designs = maxi(_chalet_designs, 1)
			art = "building_chalet_%02d" % (1 + int(absf(float(b["key"])) * 13.0) % _chalet_designs)
	if art != "" and Sprites.sheet(art) == null:
		art = ""
	b["art"] = art
	return art


func _draw_building_inner(b: Dictionary) -> void:
	var art := _building_art(b)
	if art != "":
		# a picture standing on the lot's near corner; the entrance is drawn on the right-hand wall, so mirror it for
		# a door on the left (condos are drawn 3x2 and mirrored to 2x3)
		var flip: bool = b["size"].x < b["size"].y if b["kind"] == "condo" else int(b["face"]) == 1
		Sprites.draw_image(self, art, Iso.to_screen(b["pos"] + b["size"]), flip, Iso.fade)
		return
	var pos: Vector2 = b["pos"]
	var size: Vector2 = b["size"]
	var h: float = b["h"]
	var col: Color = b["col"]
	var kind: String = b["kind"]
	var center := pos + size * 0.5
	var inset := Vector2(0.06, 0.06)
	pos += inset
	size -= inset * 2.0
	match kind:
		"chalet", "condo", "hotel", "gondola", "townhall":
			Iso.box(self, pos, size, h, col)
			if kind == "chalet":
				_chalet_trim(pos, size, h)
			else:
				Iso.windows(self, pos, size, h, Color(1.0, 0.93, 0.55))
			if kind == "hotel":
				_balconies(pos, size, h)
			else:
				_stone_base(pos, size, Iso.shade(col, 0.55))
			_door(b, pos, size)
			if kind == "hotel" and int(b["face"]) <= 1:
				var face: int = b["face"]
				var cpos := Vector2(pos.x + size.x, pos.y + size.y * 0.35) if face == 0 else Vector2(pos.x + size.x * 0.35, pos.y + size.y)
				var csz := Vector2(0.55, size.y * 0.3) if face == 0 else Vector2(size.x * 0.3, 0.55)
				Iso.box(self, cpos, csz, 3.0, Color(0.75, 0.15, 0.2), 13.0)
				draw_line(Iso.to_screen(cpos + csz, 0), Iso.to_screen(cpos + csz, 13), Iso.fa(Iso.OUTLINE, Iso.fade), 1.0)
			Iso.gable(self, pos, size, h, b["roof_h"], Season.roof(b["roof"]), col, b["ridge_x"])
			if kind == "chalet":
				var ch := pos + Vector2(size.x * 0.25, size.y * 0.25)
				Iso.box(self, ch, Vector2(0.3, 0.3), b["roof_h"] + 6.0, Color(0.55, 0.35, 0.3), h)
		"shop":
			Iso.box(self, pos, size, h, col)
			_stone_base(pos, size, Iso.shade(col, 0.6))
			Iso.windows(self, pos, size, h, Color(1.0, 0.93, 0.55), 0.0, 18.0)
			Iso.box(self, pos, size, 3.0, Iso.shade(col, 0.85), h, Season.roof(Iso.shade(col, 0.7)))
			_storefront(b, pos, size, b["accent"])
			_hanging_sign(b, pos, size, b["accent"])
		"pizza":
			Iso.box(self, pos, size, h, col, 0.0, Season.roof(b["accent"]))
			_storefront(b, pos, size, b["accent"])
			var top := Iso.to_screen(center, h + 4.0)
			draw_circle(top, 15.0, Iso.OUTLINE)
			draw_circle(top, 14.0, Color(0.95, 0.72, 0.28))
			draw_circle(top, 11.0, Color(1.0, 0.88, 0.45))
			for a in 6:
				draw_circle(top + Vector2(cos(a * 1.05), sin(a * 1.05) * 0.6) * 7.0, 2.0, Color(0.85, 0.15, 0.15))
		"bike":
			Iso.box(self, pos, size, h, col, 0.0, Season.roof(Color(0.2, 0.4, 0.75)))
			_storefront(b, pos, size, Color(1.0, 0.85, 0.2))
			var top := Iso.to_screen(center, h + 2.0)
			draw_arc(top + Vector2(-10, 0), 8.0, 0, TAU, 14, Color.WHITE, 2.0)
			draw_arc(top + Vector2(10, 0), 8.0, 0, TAU, 14, Color.WHITE, 2.0)
			draw_line(top + Vector2(-10, 0), top + Vector2(0, -10), Color.WHITE, 2.0)
			draw_line(top + Vector2(0, -10), top + Vector2(10, 0), Color.WHITE, 2.0)
		"er":
			# St. Pedro's hospital, with its helicopter pad on the roof: a picture standing on the lot's near corner
			Sprites.draw_image(self, "hospital", Iso.to_screen(pos + size))
		"race":
			Iso.box(self, pos, size, h, col, 0.0, Season.roof(Color(0.92, 0.92, 0.92)))
			for cy in int(size.y + 0.5):
				for cx in int(size.x + 0.5):
					if (cx + cy) % 2 == 0:
						Iso.diamond(self, pos + Vector2(cx, cy), Color(0.1, 0.1, 0.12), h + 0.5, Vector2(minf(1.0, size.x - cx), minf(1.0, size.y - cy)))
			_storefront(b, pos, size, Color(1.0, 0.3, 0.3))
			Iso.box(self, pos + Vector2(0.2, 0.2), Vector2(0.2, 0.2), 80.0, Color(0.8, 0.8, 0.8))
			var flag := Iso.to_screen(pos + Vector2(0.3, 0.3), 80.0)
			var wave := sin(t_ * 6.0) * 2.0
			Iso.poly(self, PackedVector2Array([flag, flag + Vector2(26, 6 + wave), flag + Vector2(0, 14)]), Color(1.0, 0.3, 0.3))


## Darker stone course along the foot of the visible walls, with block joints.
func _stone_base(pos: Vector2, size: Vector2, col: Color) -> void:
	var c := pos + size
	for face in 2:
		var a := Vector2(pos.x, c.y) if face == 0 else c
		var b := c if face == 0 else Vector2(c.x, pos.y)
		var f := 0.88 if face == 0 else 0.7
		draw_colored_polygon(PackedVector2Array([Iso.to_screen(a, 0), Iso.to_screen(b, 0), Iso.to_screen(b, 4), Iso.to_screen(a, 4)]), Iso.fa(Iso.shade(col, f), Iso.fade))
		var n := int(a.distance_to(b) * 3.0)
		for k in range(1, n):
			var p := a.lerp(b, k / float(n))
			draw_line(Iso.to_screen(p, 0), Iso.to_screen(p, 4), Iso.fa(Iso.shade(col, f * 0.7), Iso.fade), 1.0)


## A little sign board on a bracket next to the shop door.
func _hanging_sign(b: Dictionary, pos: Vector2, size: Vector2, col: Color) -> void:
	var face: int = b["face"]
	if face > 1:
		return
	var anchor := Vector2(pos.x + size.x, pos.y + size.y * 0.12) if face == 0 else Vector2(pos.x + size.x * 0.12, pos.y + size.y)
	var out := Vector2(0.5, 0) if face == 0 else Vector2(0, 0.5)
	var s0 := Iso.to_screen(anchor, 26.0)
	var s1 := Iso.to_screen(anchor + out, 26.0)
	draw_line(s0, s1, Iso.fa(Iso.OUTLINE, Iso.fade), 1.0)
	var board := PackedVector2Array([Iso.to_screen(anchor + out * 0.25, 25.0), Iso.to_screen(anchor + out, 25.0), Iso.to_screen(anchor + out, 18.0), Iso.to_screen(anchor + out * 0.25, 18.0)])
	Iso.poly(self, board, col)
	var mid := (board[0] + board[2]) * 0.5
	draw_rect(Rect2(mid - Vector2(1, 1), Vector2(2, 2)), Iso.fa(Color(1, 1, 1), Iso.fade))


func _chalet_trim(pos: Vector2, size: Vector2, h: float) -> void:
	# timber planks, shuttered windows with flower boxes, and a white trim band under the eaves
	var c := pos + size
	for face in 2:
		var a := Vector2(pos.x, c.y) if face == 0 else c
		var b := c if face == 0 else Vector2(c.x, pos.y)
		var f := 0.88 if face == 0 else 0.7
		var plank := Iso.fa(Iso.shade(Iso.OUTLINE.lerp(Color(0.5, 0.35, 0.2), 0.7), f), Iso.fade * 0.55)
		var z := 4.0
		while z < h - 2.0:
			draw_line(Iso.to_screen(a, z), Iso.to_screen(b, z), plank, 1.0)
			z += 3.5
		for k in 2:
			var t0 := 0.18 + k * 0.45
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t0 + 0.22)
			var q := PackedVector2Array([Iso.to_screen(p0, 7), Iso.to_screen(p1, 7), Iso.to_screen(p1, 15), Iso.to_screen(p0, 15)])
			Iso.poly(self, q, Iso.shade(Color(1.0, 0.9, 0.55), f))
			draw_line(Iso.to_screen(p0.lerp(p1, 0.5), 7), Iso.to_screen(p0.lerp(p1, 0.5), 15), Iso.fa(Iso.OUTLINE, Iso.fade), 1.0)
			# shutters
			var sl := PackedVector2Array([Iso.to_screen(p0.lerp(p1, -0.28), 7), Iso.to_screen(p0, 7), Iso.to_screen(p0, 15), Iso.to_screen(p0.lerp(p1, -0.28), 15)])
			var sr := PackedVector2Array([Iso.to_screen(p1, 7), Iso.to_screen(p0.lerp(p1, 1.28), 7), Iso.to_screen(p0.lerp(p1, 1.28), 15), Iso.to_screen(p1, 15)])
			Iso.poly(self, sl, Iso.shade(Color(0.25, 0.5, 0.35), f))
			Iso.poly(self, sr, Iso.shade(Color(0.25, 0.5, 0.35), f))
			# flower box
			var fb := PackedVector2Array([Iso.to_screen(p0.lerp(p1, -0.1), 4), Iso.to_screen(p0.lerp(p1, 1.1), 4), Iso.to_screen(p0.lerp(p1, 1.1), 7), Iso.to_screen(p0.lerp(p1, -0.1), 7)])
			Iso.poly(self, fb, Iso.shade(Color(0.55, 0.35, 0.2), f))
			for m in 4:
				var fp := Iso.to_screen(p0.lerp(p1, 0.05 + m * 0.3), 8.0)
				draw_rect(Rect2(fp - Vector2(1, 1), Vector2(2, 2)), Iso.fa([Color(1.0, 0.3, 0.4), Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.8)][m % 3], Iso.fade))
		draw_line(Iso.to_screen(a, h - 3.0), Iso.to_screen(b, h - 3.0), Iso.fa(Iso.shade(Color(0.95, 0.95, 0.9), f), Iso.fade), 2.0)


func _balconies(pos: Vector2, size: Vector2, h: float) -> void:
	var c := pos + size
	var z := 17.0
	while z < h - 8.0:
		draw_line(Iso.to_screen(Vector2(pos.x, c.y), z), Iso.to_screen(c, z), Iso.fa(Color(0.95, 0.95, 0.95), Iso.fade), 2.0)
		draw_line(Iso.to_screen(c, z), Iso.to_screen(Vector2(c.x, pos.y), z), Iso.fa(Color(0.75, 0.75, 0.75), Iso.fade), 2.0)
		z += 13.0


## A door on the face toward the road, if that face is visible: panelled, with a knob and a step.
func _door(b: Dictionary, pos: Vector2, size: Vector2) -> void:
	var q := _face_rect(b["face"], pos, size, 0.42, 0.58, 0.0, 12.0)
	if q.is_empty():
		return
	Iso.poly(self, q, Color(0.5, 0.3, 0.18))
	var inner := _face_rect(b["face"], pos, size, 0.45, 0.55, 2.0, 10.0)
	Iso.poly(self, inner, Color(0.42, 0.25, 0.15))
	var knob := _face_rect(b["face"], pos, size, 0.53, 0.55, 5.5, 6.5)
	draw_colored_polygon(knob, Iso.fa(Color(1.0, 0.85, 0.3), Iso.fade))


func _face_rect(face: int, pos: Vector2, size: Vector2, t0: float, t1: float, z0: float, z1: float) -> PackedVector2Array:
	var a: Vector2
	var b: Vector2
	match face:
		0:
			a = Vector2(pos.x + size.x, pos.y)
			b = pos + size
		1:
			a = Vector2(pos.x, pos.y + size.y)
			b = pos + size
		_:
			return PackedVector2Array()
	var p0 := a.lerp(b, t0)
	var p1 := a.lerp(b, t1)
	return PackedVector2Array([Iso.to_screen(p0, z0), Iso.to_screen(p1, z0), Iso.to_screen(p1, z1), Iso.to_screen(p0, z1)])


## Shop window + striped awning on the road-facing side.
func _storefront(b: Dictionary, pos: Vector2, size: Vector2, awning: Color) -> void:
	var face: int = b["face"]
	if face > 1:
		return
	Iso.poly(self, _face_rect(face, pos, size, 0.15, 0.85, 4.0, 17.0), Color(0.18, 0.2, 0.3))
	draw_colored_polygon(_face_rect(face, pos, size, 0.2, 0.3, 6.0, 15.0), Iso.fa(Color(0.55, 0.7, 0.9), Iso.fade))
	var out := Vector2(0.45, 0.0) if face == 0 else Vector2(0.0, 0.45)
	var a := Vector2(pos.x + size.x, pos.y) if face == 0 else Vector2(pos.x, pos.y + size.y)
	var e := pos + size
	var stripes := 7
	for k in stripes:
		var p0 := a.lerp(e, 0.1 + 0.8 * k / float(stripes))
		var p1 := a.lerp(e, 0.1 + 0.8 * (k + 1) / float(stripes))
		var c := awning if k % 2 == 0 else Color(1, 1, 1)
		draw_colored_polygon(PackedVector2Array([Iso.to_screen(p0, 21), Iso.to_screen(p1, 21), Iso.to_screen(p1 + out, 16), Iso.to_screen(p0 + out, 16)]), Iso.fa(c, Iso.fade))
	var q0 := a.lerp(e, 0.1)
	var q1 := a.lerp(e, 0.9)
	draw_polyline(PackedVector2Array([Iso.to_screen(q0, 21), Iso.to_screen(q1, 21), Iso.to_screen(q1 + out, 16), Iso.to_screen(q0 + out, 16), Iso.to_screen(q0, 21)]), Iso.fa(Iso.OUTLINE, Iso.fade), 1.0)


func _draw_tree(t: Dictionary) -> void:
	var base := Iso.to_screen(t["pos"])
	var s: float = t["s"]
	draw_colored_polygon(PackedVector2Array([base + Vector2(-9, 0) * s, base + Vector2(0, -4) * s, base + Vector2(9, 0) * s, base + Vector2(0, 4) * s]), Color(0, 0, 0, 0.2))
	# the town's own kinds of tree, each mixed with a few related species so the parks don't look planted in rows
	var h := int(absf(t["pos"].x * 92821.0 + t["pos"].y * 68917.0))
	var sp: String = {1: ["pine_light", "fir", "spruce"], 3: ["birch", "aspen", "willow"], 4: ["oak", "maple", "cherry"]}.get(int(t["kind"]), ["pine", "pine", "spruce", "larch"])[h % 3]
	Flora.tree(self, base, t["s"], sp, false, h / 3)


const STALL_ART := ["red", "orange", "green", "purple", "blue"]       # art/scenery_stall_<colour>.png, in PIZZA_COLORS order
const UMBRELLA_ART := ["red", "yellow", "green", "purple", "blue"]    # art/scenery_umbrella_<colour>.png, in PIZZA_COLORS order


## Street lamps, market stalls, beach umbrellas and the plaza fountain: pictures (art/scenery_*.png).
func _draw_prop(p: Dictionary) -> void:
	var base := Iso.to_screen(p["pos"])
	var ci := maxi(0, PIZZA_COLORS.find(p.get("col", PIZZA_COLORS[0])))
	match p["kind"]:
		"lamp":
			Sprites.draw_image(self, "scenery_lamp_post", base)
		"lift_station":
			Sprites.draw_image(self, "ski_chairlift_station", base + Vector2(0, 6))
		"lift_tower":
			Sprites.draw_image(self, "ski_chairlift_tower", base + Vector2(0, 4))
		"stall":
			Sprites.draw_image(self, "scenery_stall_%s" % STALL_ART[ci % STALL_ART.size()], Iso.to_screen(p["pos"] + Vector2(0.5, 0.5)) + Vector2(0, 6))
		"umbrella":
			Sprites.draw_image(self, "scenery_umbrella_%s" % UMBRELLA_ART[ci % UMBRELLA_ART.size()], base + Vector2(0, 8))
		"fountain":
			Sprites.draw_image(self, "scenery_fountain", Iso.to_screen(PLAZA) + Vector2(0, 30))
		"90s":
			Sprites.draw_image(self, "scenery_90s_" + str(p["art"]), base, bool(p.get("flip", false)))
		"tube":
			Sprites.draw_strip(self, "scenery_tube_man", base, t_ + float(p["ph"]), 9.0)


func _draw_ped(p: Dictionary) -> void:
	var ground := Iso.to_screen(p["pos"])
	var cheering: bool = p["cheer"] > 0.0
	if p["giver"]:
		_draw_giver(p, ground)
		return
	# their look: their own, unless someone else on screen already looks like that (see Sprites.cast)
	var design := Sprites.cast(p, p.get("looks", []))
	if design == "":
		return
	Sprites.fade = float(p.get("fade", 1.0))   # (going in at a door, or coming back out)
	draw_colored_polygon(PackedVector2Array([ground + Vector2(-5, 0), ground + Vector2(0, -2.5), ground + Vector2(5, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2 * Sprites.fade))
	if cheering:
		Sprites.draw_any_cheer(self, design, ground, float(p["phase"]) / 11.0, int(p.get("roll", 0)))
		_label(p["shout"], ground + Vector2(0, -52), 8, Color(1.0, 0.95, 0.45))
	else:
		Sprites.draw_person(self, "ped_%s_walk" % design, ground, p.get("face", Vector2(1, 1)), float(p["phase"]) / 8.0, 8.0, Color.WHITE, p)
	Sprites.fade = 1.0
	if float(p.get("say_t", 0.0)) > 0.0:
		_label(p["say"], ground + Vector2(0, -52), 8, Color(0.85, 0.95, 1.0))


## The pizza man outside each shop. With an order waiting he dances with the steaming box held high,
## and when you ride up he hands it over; otherwise he waits, tapping his foot.
## The pizza shop's baker: dancing with a pizza held overhead while an order waits, otherwise tapping a foot.
func _draw_chef(si: int) -> void:
	var sh: Dictionary = shops[si]
	var ground := Iso.to_screen(sh["chef"])
	var waiting := false
	for o in orders:
		if o["state"] == "open" and o["shop"] == si:
			waiting = true
	var throw := _throw_progress(si)
	var giving := throw >= 0.0 or (handoff > 0.0 and handoff_shop == si)
	var t := t_ + si * 0.7
	draw_colored_polygon(PackedVector2Array([ground + Vector2(-6, 0), ground + Vector2(0, -3), ground + Vector2(6, 0), ground + Vector2(0, 3)]), Color(0, 0, 0, 0.22))
	var slug := _shop_slug(sh["name"])
	if waiting and not giving:
		Sprites.draw_strip(self, "chef_%s_dance" % slug, ground, t, 10.0)
		BikeDraw._steam(self, ground + Vector2(0, -50.0), 1.0)
		# music notes drifting up
		for k in 2:
			var u := fposmod(t * 0.6 + k * 0.5, 1.0)
			var np := ground + Vector2(14.0 + k * 4.0 + sin(u * 6.0) * 3.0, -26.0 - u * 18.0)
			var nc := Color(1.0, 0.85, 0.3, 1.0 - u)
			draw_circle(np, 1.6, nc)
			draw_line(np + Vector2(1.4, 0), np + Vector2(1.4, -6), nc, 1.0)
			draw_line(np + Vector2(1.4, -6), np + Vector2(3.4, -4), nc, 1.0)
	elif throw >= 0.0 and Sprites.sheet("chef_%s_throw" % slug) != null:
		# winding up and flinging the pizza (the pizza itself flies off on its own: _draw_thrown_pizza)
		var tex := Sprites.outfit("chef_%s_throw" % slug)
		var n := maxi(1, tex.get_width() / tex.get_height())
		Sprites.draw_strip(self, "chef_%s_throw" % slug, ground, float(mini(n - 1, int(throw / THROW_END * n))) / 10.0, 10.0)
	else:
		# standing around (still while handing over, if there's no throw art)
		Sprites.draw_strip(self, "chef_%s_tap" % slug, ground, 0.0 if giving else t, 8.0)


## "The Cheesy Chairlift" -> "the_cheesy_chairlift": the file name part of a shop's art.
func _shop_slug(shop_name: String) -> String:
	var out := ""
	for ch in shop_name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")


func _draw_car(c: Dictionary) -> void:
	var fwd: Vector2 = c["fwd"]
	var pos: Vector2 = c["pos"]
	var hl: float = c["hl"]
	var hw: float = c["hw"]
	var rt := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(_to_screen_poly(PackedVector2Array([pos + fwd * hl + rt * hw, pos - fwd * hl + rt * hw, pos - fwd * hl - rt * hw, pos + fwd * hl - rt * hw])), Color(0, 0, 0, 0.25))
	var tint := Color.WHITE.lerp(c["col"], 0.7) if c["kind"] in PAINTED_VEHICLES else Color.WHITE
	var odo: float = c.get("odo", 0.0)
	var moving: bool = float(c["speed"]) > 0.3
	# a one-pixel bounce on the suspension while it drives, and the wheels turn with the distance driven
	var at := Iso.to_screen(pos) + Vector2(0, -1 if moving and int(odo * 5.0) % 2 == 0 else 0)
	var frame := int(odo * 6.0)
	if not Sprites.draw_vehicle(self, c.get("art", "vehicle_%s" % c["kind"]), at, fwd, tint, frame, c):
		Sprites.draw_vehicle(self, "vehicle_car", at, fwd, Color.WHITE.lerp(c["col"], 0.7), frame, c)
	if not String(c["kind"]).contains("electric") and not String(c["kind"]).contains("carriage"):
		# exhaust: little puffs from the back that drift up and fade, more when it pulls away
		var rear: Vector2 = pos - fwd * hl
		var puff := clampf(float(c["speed"]) / maxf(float(c["max"]), 0.1), 0.25, 1.0)
		for k in 3:
			var u := fposmod(t_ * 1.4 + k / 3.0 + float(c["hl"]) * 7.0, 1.0)
			var p := Iso.to_screen(rear - fwd * u * 0.7) + Vector2(0, -4.0 - u * 10.0)
			draw_circle(p, 1.2 + u * 2.4, Color(0.85, 0.85, 0.88, (1.0 - u) * 0.35 * puff))
	if c.get("siren", false):
		TownEvents.draw_siren(self, c, Iso.to_screen(pos), t_)


func _draw_player() -> void:
	if er_timer > 0.0:
		# hit by a car: the rider goes down in the road for a moment before the ambulance takes them away
		if p_fall < ER_LIE_TIME:
			_draw_bike(p_pos, p_head, 0.0, p_fall_pizza, "YOU", 0.0, 1.0, p_fall)
		return
	if invuln > 0.0 and invuln < 50.0 and int(t_ * 14.0) % 2 == 0:
		return
	var heat := 0.0 if carry.is_empty() else clampf(float(carry["t_left"]) / float(carry["t_total"]), 0.0, 1.0)
	var k := _bread_k(bread_t)
	if socks_t > 0.0 and p_down <= 0.0:
		PowerUps.draw_flames(self, Iso.to_screen(p_pos), -BikeDraw.world_dir(p_head).normalized(), t_)
	if p_down > 0.0:
		_draw_bike(p_pos, p_head, 0.0, p_fall_pizza, "YOU", heat, k, p_fall)
		_dizzy(Iso.to_screen(p_pos) + Vector2(0, -30))
	else:
		_draw_bike(p_pos, p_head, p_phase, not carry.is_empty(), "YOU", heat, k)
	_label(Game.player_name, Iso.to_screen(p_pos) + Vector2(0, -46 * k), 8, Color(1, 1, 1))
	if handoff > 0.0 and handoff_shop >= 0:
		if handoff_live:   # the baker flings the pizza and it spins through the air into your hands
			_draw_thrown_pizza(handoff_shop, p_pos, handoff)
		draw_arc(Iso.to_screen(p_pos, 18.0) + Vector2(0, -26), 8.0, -PI * 0.5, -PI * 0.5 + TAU * handoff, 16, Color(0.4, 1.0, 0.5), 2.0)


## A pizza in flight from shop `si`'s baker to `to` (a world point), `u` into the handoff: nothing until the baker lets
## go at THROW_RELEASE, then a spinning pizza (art/pizza_spin.png) on a high arc into the catcher's hands.
func _draw_thrown_pizza(si: int, to: Vector2, u: float) -> void:
	if u < THROW_RELEASE:
		return
	var f := clampf((u - THROW_RELEASE) / (1.0 - THROW_RELEASE), 0.0, 1.0)
	var from := Iso.to_screen(shops[si]["chef"]) + Vector2(0, -36)   # (chest height, where the throw lets go)
	var hands := Iso.to_screen(to, 18.0)
	var at := from.lerp(hands, f) + Vector2(0, -sin(f * PI) * 34.0)
	var sh := Iso.to_screen(shops[si]["chef"]).lerp(Iso.to_screen(to), f)   # its shadow on the ground
	draw_colored_polygon(PackedVector2Array([sh + Vector2(-5, 0), sh + Vector2(0, -2), sh + Vector2(5, 0), sh + Vector2(0, 2)]), Color(0, 0, 0, 0.18))
	if not Sprites.draw_strip(self, "pizza_spin", at, t_, 24.0, false):
		draw_circle(at, 6.0, Color(0.95, 0.75, 0.3))


## How far shop `si`'s baker is into throwing a pizza (0-1 of the handoff, to you or a rival), or -1 when not.
func _throw_progress(si: int) -> float:
	if handoff > 0.0 and handoff_shop == si and handoff_live:
		return handoff
	for r in rival_state:
		if r["state"] == "handoff":
			var o := _order_by_id(r["order"])
			if not o.is_empty() and int(o["shop"]) == si:
				return 1.0 - float(r["wait"]) / HANDOFF_TIME
	return -1.0


func _draw_rival(i: int) -> void:
	var r: Dictionary = rival_state[i]
	if r["state"] == "handoff":   # the baker throws them the pizza too
		var o := _order_by_id(r["order"])
		if not o.is_empty():
			_draw_thrown_pizza(int(o["shop"]), r["pos"], 1.0 - float(r["wait"]) / HANDOFF_TIME)
	var info: Dictionary = Talk.rivals[i]
	var k := _bread_k(r["bread"])
	if r["socks"] > 0.0 and r["stun"] <= 0.0:
		PowerUps.draw_flames(self, Iso.to_screen(r["pos"]), -BikeDraw.world_dir(r["head"]).normalized(), t_ + i)
	if r["stun"] > 0.0:
		_label("*ouch*", Iso.to_screen(r["pos"]) + Vector2(0, -38), 8, Color(1, 0.8, 0.3))
		_draw_bike(r["pos"], r["head"], 0.0, r["state"] == "to_dest", info["short"], 1.0, k, r["fall"])
		_dizzy(Iso.to_screen(r["pos"]) + Vector2(0, -28))
	else:
		_draw_bike(r["pos"], r["head"], r["phase"], r["state"] == "to_dest", info["short"], 1.0, k)
	_label(info["short"], Iso.to_screen(r["pos"]) + Vector2(0, -46 * k), 8, info["color"])


## `k` scales the whole rider up (breadsticks). `fall_t` >= 0 plays the wipe-out, that many seconds in.
func _draw_bike(pos: Vector2, head: float, phase: float, has_pizza: bool, who: String = "YOU", heat := 1.0, k := 1.0, fall_t := -1.0) -> void:
	if k == 1.0:
		BikeDraw.draw(self, Iso.to_screen(pos), BikeDraw.world_dir(head), phase, has_pizza, who, heat, true, fall_t)
		return
	draw_set_transform(Iso.to_screen(pos), 0.0, Vector2(k, k))
	BikeDraw.draw(self, Vector2.ZERO, BikeDraw.world_dir(head), phase, has_pizza, who, heat, true, fall_t)
	draw_set_transform(Vector2.ZERO)


## Little stars circling a knocked-down rider's head.
func _dizzy(c: Vector2) -> void:
	for q in 3:
		var a := t_ * 5.0 + q * TAU / 3.0
		var p := c + Vector2(cos(a) * 9.0, sin(a) * 3.0)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Iso.OUTLINE)
		draw_rect(Rect2(p - Vector2(0, 0), Vector2(1, 1)), Color(1.0, 0.95, 0.3))


func _draw_gondola_cable() -> void:
	if gondola_top == Vector2.ZERO:
		return
	var a := Iso.to_screen(gondola_top, 48.0)
	var b := Vector2(-80, -540.0 - 900.0)
	draw_line(a, b, Iso.OUTLINE, 1.0)
	draw_line(a + Vector2(10, 2), b + Vector2(10, 2), Iso.OUTLINE, 1.0)
	for k in 6:
		var f := fposmod(t_ * 0.02 + k / 6.0, 1.0)
		var up := k % 2 == 0
		var p := a.lerp(b, f if up else 1.0 - f) + (Vector2.ZERO if up else Vector2(10, 2))
		Sprites.draw_vehicle(self, "obj_gondola_cabin", p + Vector2(0, 22), Vector2(1, 1), Color.WHITE if up else Color(0.6, 0.75, 1.0))


func _wrap(text: String, width: int) -> Array:
	var lines: Array = []
	var cur := ""
	for w in text.split(" "):
		if cur.length() + w.length() + 1 > width and cur != "":
			lines.append(cur)
			cur = w
		else:
			cur = w if cur == "" else cur + " " + w
	lines.append(cur)
	return lines


func _bubble(anchor: Vector2, text: String, col: Color) -> void:
	var lines := _wrap(text, 28)
	var wmax := 0.0
	for l in lines:
		wmax = maxf(wmax, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var size := Vector2(wmax + 10.0, lines.size() * 10.0 + 6.0).round()
	var tl := (anchor - Vector2(size.x * 0.5, size.y + 6.0)).round()
	draw_rect(Rect2(tl - Vector2(1, 1), size + Vector2(2, 2)), Iso.OUTLINE)
	draw_rect(Rect2(tl, size), Color(1, 1, 1))
	draw_rect(Rect2(tl + Vector2(0, size.y - 2), Vector2(size.x, 2)), col)
	draw_colored_polygon(PackedVector2Array([anchor + Vector2(-4, -6), anchor + Vector2(4, -6), anchor]), Iso.OUTLINE)
	draw_colored_polygon(PackedVector2Array([anchor + Vector2(-3, -7), anchor + Vector2(3, -7), anchor + Vector2(0, -2)]), col)
	for i in lines.size():
		draw_string(font, tl + Vector2(5, 10 + i * 10), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.1, 0.1, 0.15))


## Painted arrows on the road at the coming junction; the chosen exit is big and yellow.
func _draw_junction_arrows() -> void:
	if pending.is_empty():
		return
	var j: Dictionary = junctions[pending["j"]]
	var lab: Dictionary = pending["labels"]
	for k in lab:
		var o: Dictionary = lab[k]
		var sel: bool = k == pending["choice"]
		var pts := PackedVector2Array()
		pts.append(Iso.to_screen(j["pos"]))
		for step in [1.2, 2.4, 3.4]:
			pts.append(Iso.to_screen(_road_at(roads[o["road"]], float(o["s"]) + float(o["dir"]) * step)[0]))
		var col := Color(1.0, 0.9, 0.2) if sel else Color(1, 1, 1, 0.45)
		var w := 5.0 if sel else 2.0
		draw_polyline(pts, Iso.OUTLINE, w + 2.0)
		draw_polyline(pts, col, w)
		var tip := pts[pts.size() - 1]
		var dir := (tip - pts[pts.size() - 2]).normalized()
		var side := Vector2(-dir.y, dir.x) * (7.0 if sel else 4.0)
		var head := PackedVector2Array([tip + dir * (8.0 if sel else 5.0), tip + side, tip - side])
		var mid := (head[0] + head[1] + head[2]) / 3.0
		draw_colored_polygon(PackedVector2Array([mid + (head[0] - mid) * 1.35, mid + (head[1] - mid) * 1.35, mid + (head[2] - mid) * 1.35]), Iso.OUTLINE)
		draw_colored_polygon(head, col)


func _draw_overlays() -> void:
	heli.draw(self)
	if news_state != "off" and Sprites.sheet("heli_news") != null:
		news.draw(self, Iso.to_screen(news.pos), NEWS_ALT)
	for i in bubbles:
		var r: Dictionary = rival_state[i]
		_bubble(Iso.to_screen(r["pos"]) + Vector2(0, -54), bubbles[i]["text"], Talk.rivals[i]["color"])
	if player_bubble["t"] > 0.0:
		_bubble(Iso.to_screen(p_pos) + Vector2(0, -54), player_bubble["text"], Color(0.2, 0.6, 1.0))
	for fz in frisbees:
		var to: int = fz["to"]
		var from: int = fz["from"]
		if to < rival_state.size() and from < rival_state.size():
			PowerUps.draw_frisbee(self, Iso.to_screen(_rider_pos(from), 18.0), Iso.to_screen(_rider_pos(to), 14.0), fz["u"], t_)
	if not active or er_timer > 0.0:
		return
	_draw_junction_arrows()
	var c := Iso.to_screen(p_pos)
	draw_arc(c, 14.0, 0, TAU, 16, Color(1, 1, 1, 0.6), 1.0)
	var tip := c + Vector2(0, -62 + sin(t_ * 6.0) * 2.0)
	Iso.poly(self, PackedVector2Array([tip, tip + Vector2(-5, -7), tip + Vector2(5, -7)]), Color(1.0, 0.95, 0.3))
	# objective arrow
	var target := Vector2.ZERO
	var have := false
	if not carry.is_empty():
		target = spots[carry["dest"]]["pos"]
		have = true
	else:
		var best := 1e9
		for o in orders:
			if o["state"] == "open":
				var w: Vector2 = shops[o["shop"]]["window"]
				var d := p_pos.distance_to(w)
				if d < best:
					best = d
					target = w
					have = true
	if have and p_pos.distance_to(target) > 3.0:
		var from := Iso.to_screen(p_pos, 26.0)
		var dir := (Iso.to_screen(target) - Iso.to_screen(p_pos)).normalized()
		var at := from + dir * 52.0
		var side := Vector2(-dir.y, dir.x) * 6.0
		Iso.poly(self, PackedVector2Array([at, at - dir * 12.0 + side, at - dir * 12.0 - side]), Color(1.0, 0.9, 0.2))


# ======================================================================
# Minimap (drawn by the HUD)
# ======================================================================

func minimap_point(p: Vector2, rect: Rect2) -> Vector2:
	return rect.position + Vector2(rect.size.x * 0.5 + (p.x - p.y) / N * rect.size.x * 0.5, (p.x + p.y) / (2.0 * N) * rect.size.y)


func draw_minimap(ci: CanvasItem, rect: Rect2) -> void:
	var corners := PackedVector2Array([minimap_point(Vector2(0, 0), rect), minimap_point(Vector2(N, 0), rect), minimap_point(Vector2(N, N), rect), minimap_point(Vector2(0, N), rect)])
	ci.draw_colored_polygon(corners, Season.ground(Color(0.3, 0.6, 0.32)))
	var lake := PackedVector2Array()
	for p in lake_poly:
		lake.append(minimap_point(p, rect))
	ci.draw_colored_polygon(lake, Season.water(Color(0.3, 0.6, 0.95)))
	var plaza := PackedVector2Array()
	for k in 12:
		var a := TAU * k / 12.0
		plaza.append(minimap_point(PLAZA + Vector2(cos(a), sin(a)) * (RING_R + 1.5), rect))
	ci.draw_colored_polygon(plaza, Color(0.85, 0.74, 0.58))
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var line := PackedVector2Array()
		for i in range(0, pts.size(), 4):
			line.append(minimap_point(pts[i], rect))
		line.append(minimap_point(pts[pts.size() - 1], rect))
		ci.draw_polyline(line, Color(0.25, 0.25, 0.3), 2.0)
	for b in buildings:
		var col := Color(0, 0, 0, 0)
		match b["kind"]:
			"pizza": col = Color(1.0, 0.3, 0.2)
			"bike": col = Color(0.3, 0.6, 1.0)
			"er": col = Color.WHITE
			"race": col = Color(1.0, 0.9, 0.2)
			"townhall": col = Color(0.75, 0.5, 1.0)
		if col.a > 0.0:
			var mp := minimap_point(b["pos"] + b["size"] * 0.5, rect)
			ci.draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), Iso.OUTLINE)
			ci.draw_rect(Rect2(mp - Vector2(2, 2), Vector2(4, 4)), col)
	ci.draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), Color(1, 1, 1, 0.8), 1.0)
	if int(t_ * 4.0) % 2 == 0:
		for o in orders:
			if o["state"] == "open":
				var mp := minimap_point(shops[o["shop"]]["window"], rect)
				ci.draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.75, 0.1))
	# gift-givers waiting with a present: a little wrapped box
	for p in peds:
		if p["giver"] and p["state"] == "ready":
			var gp := minimap_point(p["pos"], rect).round()
			ci.draw_rect(Rect2(gp - Vector2(3, 3), Vector2(7, 7)), Iso.OUTLINE)
			ci.draw_rect(Rect2(gp - Vector2(2, 2), Vector2(5, 5)), Color(0.95, 0.25, 0.4))
			ci.draw_rect(Rect2(gp - Vector2(0, 2), Vector2(1, 5)), Color(1.0, 0.85, 0.2))
			ci.draw_rect(Rect2(gp - Vector2(2, 0), Vector2(5, 1)), Color(1.0, 0.85, 0.2))
			ci.draw_rect(Rect2(gp - Vector2(1, 4), Vector2(3, 1)), Color(1.0, 0.85, 0.2))
	for i in rival_state.size():
		ci.draw_rect(Rect2(minimap_point(rival_state[i]["pos"], rect) - Vector2(1, 1), Vector2(3, 3)), Talk.rivals[i]["color"])
	# where the pizza you're carrying goes: a green dot with a dark edge and a white ring (it has to show on summer grass
	# too), pulsing rather than blinking off
	if not carry.is_empty():
		var dp := minimap_point(spots[carry["dest"]]["pos"], rect).round()
		var pulse := 1.0 if int(t_ * 3.0) % 2 == 0 else 0.0
		ci.draw_circle(dp, 6.0 + pulse, Iso.OUTLINE)
		ci.draw_circle(dp, 5.0 + pulse, Color.WHITE)
		ci.draw_circle(dp, 3.5 + pulse, Color(0.15, 0.95, 0.3))
	var pp := minimap_point(p_pos, rect)
	ci.draw_circle(pp, 4.0, Iso.OUTLINE)
	ci.draw_circle(pp, 3.0, Color(0.7, 0.25, 1.0))
