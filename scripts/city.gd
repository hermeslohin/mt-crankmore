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

const N := 160
const MARGIN := 18
const TILES_PER_MS := 0.45
## Overall pace of the town (rider, rivals, traffic). 0.7 = 30% slower than the original tuning.
const PACE := 0.7
const CAR_HIT_R := 0.14
const BIKE_LANE := 0.95
const ROAD_HW := 1.0
const TURN_R := 2.2         # how far before / after a junction the rider eases into / out of the turn
const PLAZA := Vector2(72, 76)
const RING_R := 9.5
const LAKE := Vector2(120, 40)
const LAKE_R := 13.0
const BASE := Vector2(26, 28)
## Hills: [centre, radius (tiles), height (m)]. Negative height is a dip. The plaza and the lake stay flat.
const HILLS := [
	[Vector2(30, 34), 30.0, 8.0],     # the gondola side, rising towards Mt. Crankmore
	[Vector2(78, 20), 18.0, 4.5],     # Summit Road / Lookout
	[Vector2(28, 94), 18.0, 4.5],     # Chalet Hill
	[Vector2(50, 134), 16.0, 3.5],    # Pine Hollow
	[Vector2(108, 124), 18.0, 4.5],   # Ridge Road
	[Vector2(148, 90), 14.0, 3.5],    # East shore bluffs
	[Vector2(78, 148), 18.0, -2.5],   # Valley Bottom
]
const PX_PER_M := 10.0                        # screen lift per metre of height
const M_PER_TILE := 1.0 / (TILES_PER_MS * PACE)   # metres of riding per tile, matching the speed model
const MAX_TOWN_SPEED := 13.0                  # m/s cap on descents

enum T { GRASS, PLAZA, SIDEWALK, SAND, WATER, FOREST }

const SHOP_NAMES := ["Sushi Slope", "Ski & Board", "Brew Peak Cafe", "Gear Loft", "Poutine Hut", "Fudge Ridge", "Maple Mart",
	"Gelato Glacier", "Bike Spa", "The Cozy Mug", "Alpine Outfitters", "Fondue Fondue", "Summit Souvenirs", "Bear Paw Bakery",
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
	"truck_logging": [0.9, 0.34, 1.6, 2.2], "van_camper_orange": [0.65, 0.32, 1.8, 2.6], "van_bakery": [0.7, 0.32, 2.0, 2.8]}
const PAINTED_VEHICLES := ["car", "truck"]
const CAR_COUNT := 50    # vehicles in the town's traffic
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
var shops: Array = []     # pizza shops
var zones: Array = []     # interactive doors
var cars: Array = []
var peds: Array = []
var road_doors: Dictionary = {}   # road index -> [[s, side, building index], ...]: the doors people can pop into
var events: TownEvents          # random happenings around the player (see TownEvents)
var boats: Array = []
var astar := AStar2D.new()
var gondola_top := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var _name_i := {"shop": 0, "hotel": 0}

var junctions: Array = []   # {"pos", "links": [[road, s], ...]}
var road_js: Array = []     # per road: sorted [[s, junction], ...]
var zebra: Array = []       # crosswalk stripes [screen centre, polygon]

var rr := 0                 # rail state: road, distance along it, direction
var rs := 0.0
var rdir := 1.0
var rail_pos := Vector2.ZERO
var p_lat := 0.0              # tiles across your lane from the usual line (- towards the centre line, + the kerb)
var p_fwd := Vector2.RIGHT
var pending: Dictionary = {}  # the upcoming junction choice
var queued := ""              # a turn pressed before the junction was announced; used at the next real junction
var uturn_hint := false
var _from_j := -1             # the junction the rider just rode through (so it isn't taken twice)
var _turn: Dictionary = {}    # the curve the rider is following through a junction (see _update_turn)
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
	_spawn_rivals()
	_spawn_life()
	events = TownEvents.new(self)
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
	h *= smoothstep(RING_R + 3.0, RING_R + 22.0, p.distance_to(PLAZA))
	h *= smoothstep(LAKE_R + 2.0, LAKE_R + 18.0, p.distance_to(LAKE))
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
			elif c.distance_to(PLAZA) < RING_R + 1.9:
				tiles[i] = T.PLAZA
				reserved[i] = 1
			elif road_d[i] < 2.1 and c.distance_to(PLAZA) < 28.0:
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
	for t in trees:
		var key := Vector2i(floori(t["pos"].x / CHUNK), floori(t["pos"].y / CHUNK))
		if not tree_chunks.has(key):
			tree_chunks[key] = []
		tree_chunks[key].append(t)
	_place_season()


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
				if reserved[i] != 0 or not (tiles[i] == T.GRASS or tiles[i] == T.SIDEWALK) or road_d[i] < 1.9:
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
	if kind in ["shop", "hotel", "chalet", "condo"]:
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
		["townhall", "Mt. Crankmore Town Hall", PLAZA + Vector2(9, -9), Vector2(3, 3)],
	]
	var pizza_i := 0
	for sp in specials:
		var target: Vector2 = sp[2]
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
	if p.distance_to(PLAZA) < 22.0:
		if r < 0.78:
			return ["shop", Vector2(2, 2)]
		return ["hotel", Vector2(3, 3)]
	if p.distance_to(LAKE) < 26.0 or p.distance_to(BASE) < 15.0:
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
			var core := p.distance_to(PLAZA) < 22.0
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
			elif tiles[i] == T.GRASS and reserved[i] == 0 and road_d[i] > 2.4:
				var near_building := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var xx := x + dx
						var yy := y + dy
						if xx >= 0 and yy >= 0 and xx < N and yy < N and reserved[yy * N + xx] == 2:
							near_building = true
				if near_building:
					continue
				prob = clampf((Vector2(x, y).distance_to(PLAZA) - 12.0) / 50.0, 0.03, 0.3)
			if prob > 0.0 and rng.randf() < prob:
				trees.append(_make_tree(Vector2(x + rng.randf_range(0.2, 0.8), y + rng.randf_range(0.2, 0.8))))
	for y in range(-MARGIN, N + MARGIN):
		for x in range(-MARGIN, N + MARGIN):
			if x >= 0 and x < N and y >= 0 and y < N:
				continue
			if rng.randf() < 0.42:
				trees.append(_make_tree(Vector2(x + rng.randf(), y + rng.randf()), 1.25))
	# lamps around the plaza and along the village end of Valley Road
	for r in roads:
		var s := 1.0
		while s < float(r["len"]):
			var at := _road_at(r, s)
			var p: Vector2 = at[0]
			if p.distance_to(PLAZA) < 24.0:
				var tv: Vector2 = at[1]
				var n := Vector2(-tv.y, tv.x)
				for side in [1.0, -1.0]:
					var lp: Vector2 = p + n * side * (ROAD_HW + 0.55)
					var ix := int(lp.x)
					var iy := int(lp.y)
					if ix >= 0 and iy >= 0 and ix < N and iy < N and reserved[iy * N + ix] != 2:
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
	if tiles[i] != T.GRASS or reserved[i] != 0 or solid[i] != 0 or road_d[i] < 1.7 or road_d[i] > road_max:
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


func _season_spots(sr: RandomNumberGenerator, n: int, rmin: float, rmax: float, road_max: float) -> Array:
	var taken: Array = season_props.map(func(e): return e["pos"])
	var out: Array = []
	for tries in n * 80:
		if out.size() >= n:
			break
		var a := sr.randf() * TAU
		var p := PLAZA + Vector2(cos(a), sin(a)) * sr.randf_range(rmin, rmax)
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


func _place_season() -> void:
	var sr := RandomNumberGenerator.new()
	sr.seed = 1717
	var jackets := [Color(0.95, 0.25, 0.25), Color(0.2, 0.55, 0.95), Color(1.0, 0.8, 0.15), Color(0.3, 0.8, 0.45), Color(0.85, 0.35, 0.85), Color(1.0, 0.55, 0.15)]
	# winter: snowmen by the roads, skiers down the hills, skaters on the frozen lake
	for p in _season_spots(sr, 26, 7.0, 62.0, 4.0):
		season_props.append({"season": "winter", "kind": "snowman", "pos": p, "sd": sr.randi() % 100})
	var skiers := 0
	for p in _season_spots(sr, 80, 8.0, 70.0, 99.0):
		if skiers >= 14:
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
			if road_d[qi] < 1.4 or solid[qi] != 0 or tiles[qi] == T.WATER or reserved[qi] == 2:
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
		return tiles[qi] == T.GRASS and solid[qi] == 0 and reserved[qi] != 2 and road_d[qi] > 1.4
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
		if ix >= 0 and iy >= 0 and ix < N and iy < N and tiles[iy * N + ix] == T.SAND and road_d[iy * N + ix] > 2.5:
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
			var u := fposmod(t_ * float(e["speed"]) + float(e["ph"]), 1.0)
			var d: Vector2 = e["dir"]
			return e["origin"] + d * float(e["run"]) * u + Vector2(-d.y, d.x) * sin(u * TAU * 3.0) * 0.7
		"skater", "ducks":
			var a: float = e["a0"] + t_ * float(e["w"])
			return LAKE + Vector2(cos(a), sin(a)) * _lake_r(a) * float(e["rf"])
		"butterfly":
			var ph: float = e["ph"]
			return e["origin"] + Vector2(cos(t_ * 0.6 + ph) * 1.6, sin(t_ * 0.9 + ph * 1.3) * 1.1)
	return e["pos"]


func _draw_sprop(e: Dictionary, at: Vector2) -> void:
	var b := Iso.to_screen(at)
	match e["kind"]:
		"snowman":
			Season.snowman(self, b, e["sd"])
		"skier":
			var u := fposmod(t_ * float(e["speed"]) + float(e["ph"]), 1.0)
			if u > 0.96:
				return   # off to the lift
			var d: Vector2 = e["dir"]
			var vel: Vector2 = d * float(e["run"]) + Vector2(-d.y, d.x) * cos(u * TAU * 3.0) * 0.7 * TAU * 3.0
			Sprites.draw_person(self, "person_skier", b, vel, 0.0)
		"skater":
			var a: float = e["a0"] + t_ * float(e["w"])
			var tan := Vector2(-sin(a), cos(a)) * signf(e["w"])
			Sprites.draw_person(self, "person_skater", b, tan, 0.0)
		"pumpkins":
			for k in int(e["n"]):
				Season.pumpkin(self, b + Vector2(k * 7.0 - (int(e["n"]) - 1) * 3.5, (k % 2) * 3.0), 1.3 if k == 0 else 0.9, int(e["sd"]) + k)
		"leafpile":
			Season.leaf_pile(self, b, e["sd"])
			# a kid takes a run and jumps in every few seconds; leaves fly
			var c := fposmod(t_ + float(e["ph"]), 5.0)
			if c < 1.2:
				var kid: Dictionary = e["kid"]
				kid["cheer"] = 1.0
				kid["phase"] = 0.0
				Iso.hold_z += sin(c / 1.2 * PI) * 14.0
				_draw_ped(kid)
				Iso.hold_z -= sin(c / 1.2 * PI) * 14.0
				if c > 0.9:
					for k in 8:
						var hk := int(e["sd"]) * 13 + k * 7
						var fly := (c - 0.9) * 40.0
						draw_rect(Rect2(b + Vector2(float(hk % 21) - 10.0, -fly - float(hk % 7)) + Vector2(float(k - 4) * fly * 0.3, 0), Vector2(2, 1)), Season.FALL_LEAVES[hk % 4])
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
			var cut_l := _in_mouth(mid + nm * 0.82, ri) or _in_mouth(mid + nm * 1.18, ri)
			var cut_r := _in_mouth(mid - nm * 0.82, ri)
			var specks := PackedVector2Array()
			for k in 3:
				specks.append(Iso.to_screen(a.lerp(b, rng.randf()) + na * rng.randf_range(-0.85, 0.85)))
			road_draw.append([Iso.to_screen((a + b) * 0.5), _ribbon(a, b, na, nb, 1.3), _ribbon(a, b, na, nb, ROAD_HW), dash,
				empty if cut_l else _ribbon(a + na * 0.82, b + nb * 0.82, na, nb, 0.05), empty if cut_r else _ribbon(a - na * 0.82, b - nb * 0.82, na, nb, 0.05), specks,
				empty if cut_l else _ribbon(a + na * 1.18, b + nb * 1.18, na, nb, 0.12)])
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
					var c: Vector2 = at[0] + n * (-0.72 + k * 0.36)
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
		var c := {"road": ri, "s": randf_range(3.0, float(r["len"]) - 3.0), "dir": 1.0 if randf() < 0.5 else -1.0,
			"speed": 0.0, "max": randf_range(d[2], d[3]) * PACE, "col": CAR_COLORS[randi() % CAR_COLORS.size()], "kind": kind, "art": kinds[k][1],
			"hl": d[0], "hw": d[1], "wait": 0.0, "pos": Vector2.ZERO, "fwd": Vector2.RIGHT}
		_car_pose(c)
		cars.append(c)


func _car_pose(c: Dictionary) -> void:
	var at := _road_at(roads[c["road"]], c["s"])
	var fwd: Vector2 = at[1] * c["dir"]
	c["pos"] = at[0] + Vector2(-fwd.y, fwd.x) * 0.5
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
	for k in 18:
		var a := randf() * TAU
		peds.append({"pos": PLAZA + Vector2(cos(a), sin(a)) * randf_range(2.6, 6.0), "target": PLAZA, "col": shirts[k % shirts.size()],
			"hair": hairs[k % hairs.size()], "skin": skins[k % skins.size()], "t": randf() * 5.0, "phase": randf() * TAU, "road": -1, "look": randi() % Sprites.pedestrians().size(), "face": Vector2(1, 1),
			"cheer": 0.0, "cool": 0.0, "shout": "", "skis": randf() < 0.3})
	# townsfolk strolling the pavements all over town
	var made := 0
	for tries in 4000:
		if made >= 150:
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
	# 1 in 8 of them hand out power-ups to whoever rides past
	var idx := range(peds.size())
	idx.shuffle()
	for k in peds.size():
		peds[idx[k]]["giver"] = k < mini(ceili(peds.size() / float(PowerUps.GIVER_ODDS)), 18)   # the crowd grew; the gifts didn't
		peds[idx[k]]["gcool"] = 0.0
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
	_update_cars(delta)
	_update_rivals(delta)
	_update_life(delta)
	if events != null:
		events.update(delta)
	_update_mascots(delta)
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
		p_speed *= 0.4
		Game.toast.emit("U-turn!", Color(0.8, 0.9, 1.0))
	_rail_step(p_speed * delta)
	_update_pending()
	var w := _update_turn(p_speed * delta)
	p_fwd = p_fwd.slerp(w[1], 1.0 - exp(-10.0 * delta)).normalized()
	# the paddles slide you across your lane; turns are picked with the D-pad / arrows only
	p_lat = clampf(p_lat + Input.get_axis("lane_left", "lane_right") * 0.9 * delta, -0.75, 0.0)
	rail_pos = w[0] + Vector2(-p_fwd.y, p_fwd.x) * p_lat
	if p_pos.distance_to(rail_pos) > 3.0:
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

	if Input.is_action_just_pressed("honk"):
		player_bubble = {"text": HONKS.pick_random(), "t": 2.2}
		if randf() < 0.5:
			Talk.say(randi() % Talk.rivals.size(), "banter", true)

	if invuln <= 0.0:
		for c in cars:
			var rel: Vector2 = rail_pos - c["pos"]
			var f: Vector2 = c["fwd"]
			if absf(rel.dot(f)) < float(c["hl"]) + CAR_HIT_R and absf(rel.dot(Vector2(-f.y, f.x))) < float(c["hw"]) + CAR_HIT_R:
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
	var r: Dictionary = roads[rr]
	var length: float = r["len"]
	var best := -1
	var best_d := 1e9
	for e in road_js[rr]:
		var d: float = (e[0] - rs) * rdir
		if r["closed"]:
			d = fposmod(d, length)
		if e[1] == _from_j and d < 0.5:
			continue
		if d >= 0.0 and d < best_d:
			best_d = d
			best = e[1]
	if best < 0 and not r["closed"]:
		return [-1, (length - rs) if rdir > 0.0 else rs]
	if not r["closed"]:
		var to_end := (length - rs) if rdir > 0.0 else rs
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
		carry = {}
	Game.toast.emit("HIT BY A CAR!  Medical bill: $%d" % er_bill, Color(1.0, 0.3, 0.3))
	Talk.say_random("er", true)
	c["speed"] = 0.0


func _leave_er() -> void:
	place_on(zone_anchor("er"))
	rdir = 1.0
	invuln = 2.0
	if Game.damage_bike(26.0):
		Talk.say_random("bike_destroyed", true)
	Game.save_game()


func _update_cars(delta: float) -> void:
	for c in cars:
		var r: Dictionary = roads[c["road"]]
		if c["wait"] > 0.0:
			c["wait"] -= delta
			continue
		var target: float = c["max"]
		for o in cars:
			if o == c or o["road"] != c["road"] or o["dir"] != c["dir"]:
				continue
			var gap: float = (o["s"] - c["s"]) * c["dir"]
			if r["closed"]:
				gap = fposmod(gap, float(r["len"]))
			var need: float = float(c["hl"]) + float(o["hl"])
			if gap > 0.0 and gap < 2.2 + need:
				target = minf(target, 0.0 if gap < 1.2 + need else float(o["speed"]))
		if active and er_timer <= 0.0:
			var rel: Vector2 = rail_pos - c["pos"]
			var f: Vector2 = c["fwd"]
			var ahead := rel.dot(f)
			# cars queue behind a rider in their lane, but don't expect riders cutting across a junction
			if ahead > 0.0 and ahead < 2.4 + float(c["hl"]) and absf(rel.dot(Vector2(-f.y, f.x))) < 0.8 and f.dot(p_fwd) > 0.5:
				target = 0.0
		c["speed"] = move_toward(c["speed"], target, 4.0 * delta)
		var moved: float = c["speed"] * delta
		var s0: float = c["s"]
		c["s"] = _wrap_s(r, s0 + c["dir"] * moved)
		_car_junctions(c, r, s0, moved)
		var was: Vector2 = c["pos"]
		var was_f: Vector2 = c["fwd"]
		_car_pose(c)
		c["blend"] = maxf(0.0, float(c.get("blend", 0.0)) - delta)
		if c["blend"] > 0.0:
			# ease across lanes after a turn instead of jumping
			c["pos"] = was.lerp(c["pos"], 1.0 - exp(-9.0 * delta))
			c["fwd"] = was_f.slerp(c["fwd"], 1.0 - exp(-9.0 * delta)).normalized()


## Cars drive through junctions: at the end of a road they must pick an exit, elsewhere they sometimes turn off.
## Only as a last resort (no way out at all) do they stop and turn around.
func _car_junctions(c: Dictionary, r: Dictionary, s0: float, moved: float) -> void:
	var ri: int = c["road"]
	var length: float = r["len"]
	for e in road_js[ri]:
		var ji: int = e[1]
		if ji == int(c.get("last_j", -1)):
			continue
		var d: float = (float(e[0]) - s0) * float(c["dir"])
		if r["closed"]:
			d = fposmod(d, length)
		if d < 0.0 or d > moved + 0.001:
			continue
		var at_end: bool = not r["closed"] and (float(e[0]) < 0.6 or float(e[0]) > length - 0.6)
		c["last_j"] = ji
		if not at_end and randf() < 0.55:
			return
		var opts := _options(ji, ri, c["dir"])
		if not at_end:
			opts = opts.filter(func(o): return o["road"] != ri)
		if opts.is_empty():
			break
		var o: Dictionary = opts.pick_random()
		c["road"] = o["road"]
		c["s"] = o["s"]
		c["dir"] = o["dir"]
		c["blend"] = 0.8
		return
	if not r["closed"] and (c["s"] >= length - 0.01 or c["s"] <= 0.01):
		c["dir"] = -c["dir"]
		c["wait"] = 1.0
		c["speed"] = 0.0
		c["last_j"] = -1


func _update_life(delta: float) -> void:
	var riding := active and er_timer <= 0.0
	for p in peds:
		p["t"] -= delta
		p["cool"] = maxf(0.0, p["cool"] - delta)
		if p["giver"]:
			p["gcool"] = maxf(0.0, p["gcool"] - delta)
			if p["gcool"] <= 0.0:
				_try_give(p, riding)
		# townsfolk cheer you on as you ride past: they stop, jump and shout
		if p["cheer"] > 0.0:
			p["cheer"] -= delta
			p["phase"] += delta * 11.0
			continue
		if riding and p["cool"] <= 0.0 and p_pos.distance_to(p["pos"]) < 4.5:
			p["cool"] = randf_range(14.0, 24.0)
			if randf() < 0.45:
				p["cheer"] = 2.6
				p["shout"] = String(CHEERS.pick_random()).replace("{n}", Game.player_name)
				continue
		# and the rivals, a little less loudly
		if p["cool"] <= 0.0 and int(Engine.get_process_frames() + int(p["phase"] * 10.0)) % 20 == 0:
			for i in rival_state.size():
				if (rival_state[i]["pos"] as Vector2).distance_to(p["pos"]) < 3.5:
					p["cool"] = randf_range(10.0, 20.0)
					if randf() < 0.5:
						p["cheer"] = 2.0
						p["shout"] = ["Go %s!", "Come on %s!", "Faster, %s!", "%s! %s!"].pick_random().replace("%s", Talk.rivals[i]["short"])
					break
			if p["cheer"] > 0.0:
				continue
		p["say_t"] = maxf(0.0, float(p.get("say_t", 0.0)) - delta)
		if float(p.get("inside", 0.0)) > 0.0:
			# in a shop: come back out a while later with something to say about it
			p["inside"] -= delta
			if p["inside"] <= 0.0:
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
							p["inside"] = randf_range(4.0, 12.0)
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
					r["wait"] = 0.8
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
						if randf() < 0.4:
							Talk.say(i, "rival_delivered")
					r["state"] = "idle"
					r["idle"] = randf_range(1.0, 4.0)


## Moves a rival along its path. Returns true when the path is finished.
## Rivals cruise at 75% of their FTP, so they slow down on climbs and fly down the other side just like you.
func _follow(r: Dictionary, delta: float) -> bool:
	var path: Array = r["path"]
	if not path.is_empty():
		var bk: Dictionary = r["bike"]
		var g := PowerUps.felt_grade(clampf(grade_at(r["pos"], path[0] - r["pos"]), -0.1, 0.1), r["roller"])
		var mps := minf(Game.speed_from_power(float(r["ftp"]) * 0.75, bk["mass"], bk["cda"], bk["crr"], g, r["mass"]), MAX_TOWN_SPEED)
		if r["socks"] > 0.0:
			mps *= PowerUps.SOCKS_BOOST
		if r["blocked"]:
			mps = minf(mps, 1.2)
		r["speed"] = move_toward(r["speed"], mps * TILES_PER_MS * PACE, 3.0 * delta)
	var step: float = r["speed"] * delta
	while not path.is_empty() and step > 0.0:
		var target: Vector2 = path[0]
		var to: Vector2 = target - r["pos"]
		if to.length() <= step:
			r["pos"] = target
			step -= to.length()
			path.pop_front()
		else:
			r["pos"] += to.normalized() * step
			r["head"] = to.angle()
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
	var o := {"id": next_order_id, "shop": s, "dest": d, "pay": 14 + int(dist * 0.8) + randi() % 8,
		"state": "open", "rival": -1, "age": 0.0, "t_left": 0.0, "t_total": 0.0, "quality": 1.0}
	next_order_id += 1
	orders.append(o)
	Game.toast.emit("RING RING!  %s: $%d to %s!" % [shops[s]["name"], o["pay"], spots[d]["name"]], Color(1.0, 0.85, 0.3))
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
				handoff += delta / 0.8
				if handoff >= 1.0:
					_take_order(o)
					handoff = 0.0
				break
	if not picking:
		handoff = maxf(0.0, handoff - delta * 2.0)
	if not carry.is_empty() and p_pos.distance_to(spots[carry["dest"]]["pos"]) < 2.7 and p_speed < 2.0:
		_deliver()


func _take_order(o: Dictionary) -> void:
	o["state"] = "player"
	# the deadline: ride the road there at a decent clip or you don't get paid
	var dist := _path_len(shops[o["shop"]]["window"], spots[o["dest"]]["pos"])
	o["t_total"] = 15.0 + dist / (1.6 * PACE)
	o["t_left"] = o["t_total"]
	carry = o
	Game.toast.emit("Got it! Deliver to %s in %ds or no pay!" % [spots[o["dest"]]["name"], int(o["t_total"])], Color(0.5, 1.0, 0.5))
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
	var frac: float = clampf(carry["t_left"] / carry["t_total"], 0.0, 1.0)
	var tip := int(carry["pay"] * 0.6 * frac)
	var base := int(carry["pay"] * carry["quality"])
	Game.add_money(base + tip)
	Game.deliveries += 1
	Game.toast.emit("DELIVERED!  $%d + $%d tip" % [base, tip], Color(0.4, 1.0, 0.5))
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
func _try_give(p: Dictionary, riding: bool) -> void:
	if riding and pu == "" and p_down <= 0.0 and p_pos.distance_to(p["pos"]) < 2.0:
		pu = PowerUps.pick(PowerUps.TOWN)
		p["gcool"] = 25.0
		p["cheer"] = 1.5
		p["shout"] = "Catch!"
		Game.toast.emit("POWER-UP: %s! %s. Press Y." % [PowerUps.label(pu), PowerUps.DEFS[pu]["blurb"].capitalize()], PowerUps.col(pu))
		return
	for i in rival_state.size():
		var r: Dictionary = rival_state[i]
		if r["pu"] == "" and r["stun"] <= 0.0 and r["pos"].distance_to(p["pos"]) < 2.0:
			r["pu"] = PowerUps.pick(PowerUps.TOWN)
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
			mascots.append({"victim": v, "t": PowerUps.MASCOT_TIME, "pos": _rider_pos(v) + _rider_fwd(v) * 3.0, "phase": randf() * TAU})
			if who < 0:
				Game.toast.emit("WALKIE TALKIE! \"Mascot, go dance on %s!\"" % _rider_name(v), PowerUps.col(kind))
			elif v < 0:
				Game.toast.emit("%s radioed a pizza mascot into your way!" % _rider_name(who), Color(1.0, 0.55, 0.45))
		"frisbee":
			var v := _nearest_opponent(who, PowerUps.FRISBEE_RANGE_M / M_PER_TILE)
			if v == -2:
				if who < 0:
					Game.toast.emit("Nobody within 5 m. Get closer to a rival, then toss!", Color(1.0, 0.8, 0.5))
				return false
			frisbees.append({"from": who, "to": v, "u": 0.0})
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
		"socks":
			return r["state"] in ["to_shop", "to_dest"]
		"breadsticks":
			return (near_player and p_pos.distance_to(r["pos"]) < 6.0) or hold > 40.0
		"roller":
			var path: Array = r["path"]
			return r["state"] in ["to_shop", "to_dest"] and not path.is_empty() and grade_at(r["pos"], path[0] - r["pos"]) > 0.03
	return false


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
			mascots.remove_at(k)
			continue
		var f := _rider_fwd(v)
		var goal := _rider_pos(v) + f * 0.9 + Vector2(-f.y, f.x) * sin(m["phase"] * 2.0) * 0.35
		m["pos"] = m["pos"].move_toward(goal, 6.0 * delta)
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
	_draw_beacons()

	var items: Array = []
	var big := vr.grow(260.0)
	for b in buildings:
		if big.has_point(Iso.to_screen(b["pos"] + b["size"] * 0.5)):
			items.append([b["key"], 0, b])
	var tv := vr.grow(60.0)
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
		if tv.has_point(Iso.to_screen(c["pos"])):
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
			if tv.has_point(Iso.to_screen(sp)):
				items.append([sp.x + sp.y, 9, e, sp])
	for p in peds:
		if float(p.get("inside", 0.0)) <= 0.0 and tv.has_point(Iso.to_screen(p["pos"])):
			items.append([p["pos"].x + p["pos"].y, 6, p])
	if events != null:
		for a in events.actors():
			if tv.has_point(Iso.to_screen(a["pos"])):
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
			10: Iso.held(Iso.ground_z(it[2]["pos"]), events.draw_actor.bind(self, it[2]))
	_draw_gondola_cable()
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
		Sprites.draw_vehicle(self, "obj_rowboat" if PIZZA_COLORS.find(b["col"]) % 2 == 0 else "obj_canoe", s, heading, Color.WHITE.lerp(b["col"], 0.25))


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
	var always := kind in ["pizza", "bike", "er", "race", "gondola", "townhall"]
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
		"stall":
			Sprites.draw_image(self, "scenery_stall_%s" % STALL_ART[ci % STALL_ART.size()], Iso.to_screen(p["pos"] + Vector2(0.5, 0.5)) + Vector2(0, 6))
		"umbrella":
			Sprites.draw_image(self, "scenery_umbrella_%s" % UMBRELLA_ART[ci % UMBRELLA_ART.size()], base + Vector2(0, 8))
		"fountain":
			Sprites.draw_image(self, "scenery_fountain", Iso.to_screen(PLAZA) + Vector2(0, 30))


func _draw_ped(p: Dictionary) -> void:
	var ground := Iso.to_screen(p["pos"])
	var cheering: bool = p["cheer"] > 0.0
	draw_colored_polygon(PackedVector2Array([ground + Vector2(-5, 0), ground + Vector2(0, -2.5), ground + Vector2(5, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
	var look := int(p.get("look", int(absf(p["pos"].x * 7.0 + p["pos"].y * 3.0)))) % Sprites.pedestrians().size()
	var design: String = Sprites.pedestrians()[look]
	if cheering:
		Sprites.draw_strip(self, "ped_%s_cheer" % design, ground, float(p["phase"]) / 11.0, 10.0)
		_label(p["shout"], ground + Vector2(0, -52), 8, Color(1.0, 0.95, 0.45))
	elif p["giver"] and p["gcool"] <= 0.0:
		# holding a power-up gift out over the road
		Sprites.draw_strip(self, "giver_%s_wave" % ("red" if look % 2 == 0 else "blue"), ground, t_ + float(p["phase"]), 8.0)
	else:
		Sprites.draw_person(self, "ped_%s_walk" % design, ground, p.get("face", Vector2(1, 1)), float(p["phase"]) / 8.0, 8.0)
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
	var giving := handoff > 0.0 and handoff_shop == si
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
	else:
		# standing around; while handing the pizza out they hold still (the box itself is drawn flying to the rider)
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
	if not Sprites.draw_vehicle(self, c.get("art", "vehicle_%s" % c["kind"]), Iso.to_screen(pos), fwd, tint):
		Sprites.draw_vehicle(self, "vehicle_car", Iso.to_screen(pos), fwd, Color.WHITE.lerp(c["col"], 0.7))
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
		# the pizza slides out of the window into your hands
		var hatch := Iso.to_screen(shops[handoff_shop]["chef"], 22.0)
		var hands := Iso.to_screen(p_pos, 18.0)
		var bp := hatch.lerp(hands, clampf(handoff, 0.0, 1.0))
		Iso.poly(self, PackedVector2Array([bp + Vector2(-7, -2), bp + Vector2(0, -5), bp + Vector2(7, -2), bp + Vector2(0, 1)]), Color(0.97, 0.95, 0.88))
		draw_rect(Rect2(bp + Vector2(-2, -3), Vector2(4, 1)), Color(0.9, 0.2, 0.2))
		draw_arc(hands + Vector2(0, -26), 8.0, -PI * 0.5, -PI * 0.5 + TAU * handoff, 16, Color(0.4, 1.0, 0.5), 2.0)


func _draw_rival(i: int) -> void:
	var r: Dictionary = rival_state[i]
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
		if not carry.is_empty():
			var mp := minimap_point(spots[carry["dest"]]["pos"], rect)
			ci.draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 1.0, 0.4))
	for i in rival_state.size():
		ci.draw_rect(Rect2(minimap_point(rival_state[i]["pos"], rect) - Vector2(1, 1), Vector2(3, 3)), Talk.rivals[i]["color"])
	var pp := minimap_point(p_pos, rect)
	ci.draw_circle(pp, 4.0, Iso.OUTLINE)
	ci.draw_circle(pp, 3.0, Color(0.7, 0.25, 1.0))
