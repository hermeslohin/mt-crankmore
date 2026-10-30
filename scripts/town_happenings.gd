class_name TownHappenings
extends TownEvents
## More going on in Crankmore, on top of TownEvents: every five minutes or so something happens near you.
##
## Town: a giant pizza balloon floated round the Plaza Loop, a farmers market, a car-wash fundraiser, a wedding at
## the town hall, a flash mob, cows loose in the street, a hot-air balloon going up at dawn, movie night in the park
## at dusk, a queue outside Pixel Palace for the new game, the Friday rush at Rewind Video, a pizza-eating contest.
## Seasons: winter snowball fights (look out), sledding and the Christmas tree lighting; spring Easter egg hunts
## (ride over an egg: $5) and ducklings crossing; summer beach volleyball, a fishing contest and a lemonade stand
## (stop for a glass); fall trick-or-treaters, a haunted hayride and the harvest festival.
## Chaos, rarely (a few hours apart): a power cut at night, a runaway shopping cart coming at you, a burst hydrant
## flooding the street; and every half hour or so, seagulls after the pizza on your rack (see City.CHALLENGES "gulls").
##
## A happening is a TownEvents event; its actors are people and animals as usual plus "image" (a picture, maybe up in
## the air) and "fx" (drawn by a function: rice, snowballs, ropes, water...).

const EVERY := [60.0, 120.0]          # seconds between happenings (times RARITY)
const CHAOS := {"outage": [7200.0, 14400.0], "cart": [7200.0, 14400.0], "hydrant": [7200.0, 14400.0]}
const GULLS_EVERY := [1500.0, 2100.0]  # seagulls: every half hour or so (when you've a pizza on board)
const KID_RACE_EVERY := [240.0, 480.0]
const SANTA_EVERY := [7200.0, 14400.0]   # Santa flies over on a winter night every few hours and drops you a present  # a kid on a BMX wants a race (60% of your FTP wins $20)
const TOWN := ["parade_float", "market", "car_wash", "wedding", "flash_mob", "cows", "hot_air_balloon", "movie_night",
	"arcade_queue", "video_rush", "eating_contest", "fun_run", "mountain_rescue"]
const RUNNERS := ["jogger", "walkman_jogger", "norm_woman_ponytail_runner_casual", "norm_woman_tracksuit", "norm_man_shorts", "cyclist_fan"]
const RUN_LEN := 18.0                  # tiles of road closed for a fun run
const SEASONAL := {"winter": ["snowball_fight", "sledding", "tree_lighting"], "spring": ["egg_hunt", "duck_crossing"],
	"summer": ["volleyball", "fishing", "lemonade"], "fall": ["trick_or_treat", "hayride", "harvest_festival", "zombie_kids"]}
## Happenings that belong on open ground (a park, the plaza, the beach) rather than at the kerb, and how much room
## they need: [either side along the road, behind, in front towards the road] in tiles (see TownEvents._ground_spot).
const OFF_ROAD := {"market": [2.7, 1.3, 0.5], "harvest_festival": [3.0, 2.9, 0.5], "movie_night": [2.0, 2.6, 2.6],
	"volleyball": [1.8, 1.8, 1.8]}
const ZOMBIES := ["zombie_kid_1", "zombie_kid_2", "zombie_kid_3", "zombie_kid_4"]
const KIDS := ["kid", "bucket_hat_kid", "skater_kid", "norm_boy_kid", "scout", "norm_teen_girl", "norm_teen_boy"]
const EGG_COLS := [Color(1.0, 0.55, 0.75), Color(0.55, 0.8, 1.0), Color(1.0, 0.9, 0.4), Color(0.6, 1.0, 0.6), Color(0.85, 0.6, 1.0)]

var happen_t := randf_range(40.0, 80.0) * RARITY
var chaos_t := {}
var gulls_t := randf_range(GULLS_EVERY[0], GULLS_EVERY[1])
var kid_t := randf_range(90.0, KID_RACE_EVERY[1]) * RARITY
var santa_t := randf_range(SANTA_EVERY[0] * 0.25, SANTA_EVERY[1])
var recent: Array = []                 # the last few kinds, so it doesn't repeat itself


static func all_kinds() -> Array:
	var out: Array = TOWN.duplicate()
	for s in SEASONAL:
		out.append_array(SEASONAL[s])
	out.append_array(CHAOS.keys())
	out.append("seagulls")
	out.append("kid_race")
	out.append("santa")
	return out


func update(delta: float) -> void:
	super.update(delta)
	Skies.outage = city.outage_t > 0.0
	if not city.active:
		return
	happen_t -= delta
	if happen_t <= 0.0:
		happen_t = randf_range(EVERY[0], EVERY[1]) * RARITY
		var kinds: Array = TOWN + SEASONAL.get(Season.current, [])
		kinds = kinds.filter(func(k): return not k in recent and not events.any(func(e): return e["kind"] == k) and _fits(k))
		kinds.shuffle()
		for k in kinds:   # one with nowhere to go now (a market needs open ground) makes way for the next
			var n := events.size()
			_start(k)
			if events.size() > n:
				recent.append(k)
				if recent.size() > 6:
					recent.pop_front()
				break
	for k in CHAOS:
		if not chaos_t.has(k):
			chaos_t[k] = randf_range(CHAOS[k][0] * 0.3, CHAOS[k][1])
		chaos_t[k] -= delta
		if chaos_t[k] <= 0.0 and _fits(k):
			chaos_t[k] = randf_range(CHAOS[k][0], CHAOS[k][1])
			_start(k)
	santa_t -= delta
	if santa_t <= 0.0 and Season.current == "winter" and Skies.dark() > 0.6:
		santa_t = randf_range(SANTA_EVERY[0], SANTA_EVERY[1])
		_start("santa")
	kid_t -= delta
	if kid_t <= 0.0 and city.challenge.is_empty() and city.p_speed > 0.5:
		kid_t = randf_range(KID_RACE_EVERY[0], KID_RACE_EVERY[1]) * RARITY
		_start("kid_race")
	gulls_t -= delta
	if gulls_t <= 0.0 and not city.carry.is_empty() and city.challenge.is_empty():
		gulls_t = randf_range(GULLS_EVERY[0], GULLS_EVERY[1])
		_start("seagulls")


## Whether a happening can go ahead now: the right time of day, somewhere suitable near you, and (for one with a
## fixed place) that place out of sight, so nobody pops up in front of you.
func _fits(k: String) -> bool:
	var h: float = Skies.hour
	var p: Vector2 = city.p_pos
	var hidden := func(q: Vector2) -> bool: return allow_in_view or not city._in_view(q)
	match k:
		"hot_air_balloon":
			return h >= 5.5 and h <= 9.5
		"movie_night":
			return h >= 19.0 and h <= 23.5
		"tree_lighting":
			return h >= 16.0 and h <= 23.0 and p.distance_to(city.PLAZA) < 30.0 and hidden.call(city.PLAZA + Vector2(-4.5, 3.5))
		"trick_or_treat":
			return h >= 16.5 or h < 1.0
		"parade_float":
			return p.distance_to(city.PLAZA) < 30.0
		"flash_mob":
			return p.distance_to(city.PLAZA) < 30.0 and hidden.call(city.PLAZA + Vector2(3, 3))
		"wedding":
			var b := _named_near("Town Hall", 25.0)
			return not b.is_empty() and hidden.call(b["door"])
		"arcade_queue":
			var b := _named_near("Pixel Palace", 25.0)
			return not b.is_empty() and hidden.call(b["door"])
		"video_rush":
			var b := _named_near("Rewind Video", 25.0)
			return not b.is_empty() and hidden.call(b["door"])
		"eating_contest":
			var sh := _pizza_near()
			return not sh.is_empty() and hidden.call(sh["window"])
		"fishing":
			return p.distance_to(city.LAKE) < 35.0
		"outage":
			return Skies.dark() > 0.6
		"cart", "hydrant":
			return city.p_speed > 0.5
		"mountain_rescue":
			var l := _lift_near()
			return not l.is_empty() and hidden.call(l["base"])
	return true


func _named_near(part: String, r: float) -> Dictionary:
	for b in city.buildings:
		if str(b.get("name", "")).contains(part) and (b["door"] as Vector2).distance_to(city.p_pos) < r and int(b.get("road", -1)) >= 0:
			return b
	return {}


func _lift_near() -> Dictionary:
	for l in city.lifts:
		if (l["base"] as Vector2).distance_to(city.p_pos) < 25.0:
			return l
	return {}


## Where the ski patroller calling for help is (Vector2.INF when nobody is): City offers the rescue there.
func rescue_call() -> Vector2:
	for e in events:
		if e["kind"] == "mountain_rescue" and not e.get("taken", false):
			return e["actors"][0]["pos"]
	return Vector2.INF


## You took the rescue on: the patroller's call is answered.
func rescue_taken() -> void:
	for e in events:
		if e["kind"] == "mountain_rescue":
			e["taken"] = true
			e["t"] = minf(float(e["t"]), 1.0)


func _pizza_near() -> Dictionary:
	for sh in city.shops:
		if (sh["window"] as Vector2).distance_to(city.p_pos) < 25.0:
			return sh
	return {}


# ---------------------------------------------------------------------
# Starting
# ---------------------------------------------------------------------

func _start(kind: String) -> void:
	if not kind in all_kinds():
		super._start(kind)
		return
	var sp := _ground_spot(OFF_ROAD[kind][0], OFF_ROAD[kind][1], OFF_ROAD[kind][2]) if OFF_ROAD.has(kind) else _spot()
	var e := {"kind": kind, "t": 60.0, "actors": [], "clock": 0.0, "stage": ""}
	if not sp.is_empty():
		e.merge({"pos": sp[0], "road": sp[1], "s": sp[2], "side": sp[3], "along": sp[4], "across": ((sp[5] as Vector2) - (sp[0] as Vector2)).normalized()})
	if _begin(kind, e, sp):
		events.append(e)


## A person standing about at `q` facing `look_at` (anyone, from the cast, unless `design` or `looks` says).
func _extra(e: Dictionary, q: Vector2, look_at: Vector2, design := "", looks: Array = []) -> Dictionary:
	var a := _person(q, design, (look_at - q).normalized() if look_at != q else Vector2(1, 1))
	a["anim"] = "idle"
	if not looks.is_empty():
		a["looks"] = looks.filter(func(d): return _has("ped_%s_walk" % d))
	e["actors"].append(a)
	return a


func _image(e: Dictionary, q: Vector2, name: String, lift := 0.0, flip := false) -> Dictionary:
	var a := {"type": "image", "name": name, "pos": q, "lift": lift, "flip": flip, "phase": 0.0, "label_t": 0.0}
	e["actors"].append(a)
	return a


func _fx(e: Dictionary, q: Vector2, fn: Callable) -> Dictionary:
	var a := {"type": "fx", "fn": fn, "pos": q, "phase": 0.0, "label_t": 0.0}
	e["actors"].append(a)
	return a


func _begin(kind: String, e: Dictionary, sp: Array) -> bool:
	var needs_spot := not kind in ["parade_float", "flash_mob", "tree_lighting", "wedding", "arcade_queue", "video_rush",
		"eating_contest", "fishing", "volleyball", "outage", "cart", "seagulls", "hot_air_balloon", "kid_race", "mountain_rescue", "zombie_kids", "santa"]
	if needs_spot and sp.is_empty():
		return false
	var pos: Vector2 = e.get("pos", city.p_pos)
	var along: Vector2 = e.get("along", Vector2(1, 0))
	var across: Vector2 = e.get("across", Vector2(0, 1))   # from the pavement towards the road
	match kind:
		"parade_float":
			# the giant inflatable pizza, walked round the Plaza Loop by four handlers on ropes
			var r: Dictionary = city.roads[0]
			var s := 0.0
			var best := 1e9
			var q := 0.0
			while q < float(r["len"]):   # the nearest point of the loop out of sight: it floats into view
				var at: Vector2 = city._road_at(r, q)[0]
				var dd: float = at.distance_to(city.p_pos)
				if dd < best and (allow_in_view or not city._in_view(at)):
					best = dd
					s = q
				q += 0.5
			e["road"] = 0
			e["s"] = s
			e["dir"] = 1.0 if randf() < 0.5 else -1.0
			e["t"] = float(r["len"]) / 0.55
			pos = city._road_at(r, s)[0]
			for k in 4:
				var h := _extra(e, pos, pos)
				h["handler"] = k
				h["anim"] = "walk"
				h["moving"] = true
			var bal := _image(e, pos, "scenery_parade_pizza_balloon", 54.0)
			bal["balloon"] = true
			_fx(e, pos, _draw_ropes.bind(e))
			Game.toast.emit("The giant pizza balloon is floating round the plaza!", Color(1.0, 0.8, 0.4))
		"market":
			e["t"] = 100.0
			var back := -across
			for k in 3:
				var q := pos + along * (k - 1) * 1.6 + back * 0.9
				_image(e, q, ["scenery_market_stall_veg", "scenery_market_stall_fruit", "scenery_stall_green"][k] if _has(["scenery_market_stall_veg", "scenery_market_stall_fruit", "scenery_stall_green"][k]) else "scenery_stall_orange")
			for k in 6:
				var sh := _extra(e, pos + along * randf_range(-2.0, 2.0), pos + back)
				sh["shopper"] = true
				sh["wait"] = randf_range(0.0, 4.0)
			e["spill"] = randf_range(15.0, 40.0)
		"car_wash":
			e["t"] = 70.0
			var kinds: Array = ["vehicle_sedan_retro_teal", "vehicle_car_c1", "vehicle_sedan_wagon_green", "vehicle_car"].filter(func(n): return _has(n))
			var cpos: Vector2 = pos + across * (city.ROAD_HW + 0.6 - city.CAR_LANE * 0.0) * 0.9
			if not kinds.is_empty():
				e["actors"].append({"type": "vehicle", "name": kinds[0], "pos": cpos, "face": along, "phase": 0.0, "label_t": 0.0})
			if _has("scenery_car_wash_sign"):
				_image(e, pos - across * 0.6 + along * 1.2, "scenery_car_wash_sign")
			for k in 3:
				var t := _extra(e, cpos + along * (k - 1) * 0.9 - across * 0.45, cpos, "", KIDS)
				t["washer"] = true
			_say(e["actors"][-1], "Car wash! Five bucks!", 3.0)
			_fx(e, cpos, _draw_suds.bind(cpos))
		"wedding":
			var b := _named_near("Town Hall", 25.0)
			if b.is_empty():
				return false
			e["t"] = 70.0
			e["stage"] = "rice"
			var door: Vector2 = b["door"]
			var side := _door_side(b)
			var kerb: Array = _kerb(b["road"], float(b["s"]), side)
			e["kerb"] = kerb[0]
			var bride := _extra(e, door, kerb[0], "bride" if _has("ped_bride_walk") else "", ["norm_woman_sundress", "lady"])
			bride["couple"] = true
			var groom := _extra(e, door + (kerb[1] as Vector2) * 0.5, kerb[0], "groom" if _has("ped_groom_walk") else "", ["norm_man_suit_casual"])
			groom["couple"] = true
			for k in 6:
				var q: Vector2 = door.lerp(kerb[0], 0.5) + (kerb[1] as Vector2) * (1.0 if k % 2 == 0 else -1.0) * (0.9 + 0.3 * (k / 2))
				var g := _extra(e, q, door.lerp(kerb[0], 0.5))
				g["anim"] = "cheer"
			var cars: Array = ["vehicle_sedan_limo", "vehicle_sedan_pink_convertible", "vehicle_car"].filter(func(n): return _has(n))
			if not cars.is_empty():
				var car := {"type": "vehicle", "name": cars[0], "pos": (kerb[0] as Vector2) + ((kerb[0] as Vector2) - door).normalized() * 0.4, "face": kerb[1],
					"phase": 0.0, "label_t": 0.0, "wedding_car": true}
				e["actors"].append(car)
				_fx(e, car["pos"], _draw_cans.bind(car))
			_fx(e, door.lerp(kerb[0], 0.5), _draw_rice.bind(e))
			_say(groom, "We did it!", 3.0)
			Game.toast.emit("Wedding bells at the town hall!", Color(1.0, 0.85, 0.95))
		"flash_mob":
			e["t"] = 40.0
			e["stage"] = "gather"
			var c: Vector2 = city.PLAZA + Vector2(3.0, 3.0)
			for k in 10:
				var home: Vector2 = c + Vector2(k % 4 - 1.5, k / 4 - 1.0) * 0.8
				var a := _extra(e, c + Vector2.from_angle(randf() * TAU) * randf_range(4.0, 6.0), home)
				a["to"] = home
				a["speed"] = 1.0
				a["moving"] = true
				a["anim"] = "walk"
				a["dancer"] = true
		"cows":
			e["t"] = 70.0
			var beast := "cow" if _has("animal_cow_run") else ("ram_lamb" if _has("animal_ram_lamb_run") else "goat")
			for k in 4:
				var q: Vector2 = pos + along * (k - 1.5) * 1.1 + across * randf_range(0.0, 1.6)
				e["actors"].append({"type": "animal", "name": beast, "pos": q, "face": along * (1.0 if k % 2 == 0 else -1.0), "anim": "idle",
					"phase": randf() * 3.0, "label_t": 0.0, "cow": true, "wait": randf_range(1.0, 4.0)})
			var farmer := _extra(e, pos - along * 3.0, pos, "farmer" if _has("ped_farmer_walk") else "", ["norm_man_overalls", "gardener"])
			_say(farmer, "Get back here, Daisy!", 3.0)
			Game.toast.emit("Cows loose in the street!", Color(0.9, 0.95, 0.7))
		"hot_air_balloon":
			e["t"] = 110.0
			var at: Vector2 = pos - across * 3.0 if not sp.is_empty() else city.p_pos + city.p_fwd * 5.0
			if city.p_pos.distance_to(city.LAKE) < 35.0:
				for k in 12:   # on the lake shore, round from where you can see
					var ang: float = (city.p_pos - city.LAKE).angle() + 0.35 * (k + 1) * (1.0 if k % 2 == 0 else -1.0)
					var q: Vector2 = city.LAKE + Vector2.from_angle(ang) * (city._lake_r(ang) + 2.0)
					if allow_in_view or not city._in_view(q):
						at = q
						break
			var bal := _image(e, at, "scenery_hot_air_balloon", 0.0)
			bal["hab"] = true
			bal["drift"] = Vector2(randf_range(-0.5, 0.5), randf_range(-0.6, -0.2))
			for k in 3:
				var w := _extra(e, at + Vector2(1.2 + k * 0.5, 0.8 - k * 0.3), at)
				w["anim"] = "cheer"
			Game.toast.emit("A hot-air balloon is going up!", Color(1.0, 0.85, 0.6))
		"movie_night":
			e["t"] = 120.0
			var back := -across
			var sc_pos: Vector2 = pos + back * 2.2
			var scr := _image(e, sc_pos, "scenery_movie_screen")
			scr["screen"] = true
			for k in 8:
				var q: Vector2 = sc_pos + across * (1.6 + (k / 4) * 0.7) + along * ((k % 4) - 1.5) * 0.7
				var v := _extra(e, q, sc_pos)
				v["seated"] = true
			_say(e["actors"][2], ["Shhh!", "Pass the popcorn!", "It's starting!"].pick_random(), 2.5)
		"arcade_queue", "video_rush":
			var b := _named_near("Pixel Palace" if kind == "arcade_queue" else "Rewind Video", 25.0)
			if b.is_empty():
				return false
			e["t"] = 60.0
			e["b"] = b
			var side := _door_side(b)
			for k in 6:
				var q: Array = _kerb(b["road"], float(b["s"]) + (k + 1) * 0.65, side)
				var a := _extra(e, (q[0] as Vector2).lerp(b["door"], 0.35), b["door"], "", KIDS if kind == "arcade_queue" else [])
				a["queue"] = true
			var lines: Array = ["Is it out yet?!", "I camped out since 6am!", "Sonic or Mario?", "Cowabunga!"] if kind == "arcade_queue" \
				else ["Be kind, rewind!", "Is Jurassic Park back in?", "Two-for-one Fridays!", "I'm getting Home Alone. Again."]
			e["lines"] = lines
		"eating_contest":
			var sh := _pizza_near()
			if sh.is_empty():
				return false
			e["t"] = 70.0
			var b: Dictionary = city.buildings[sh["b"]]
			var side := _door_side(b)
			var kerb: Array = _kerb(b["road"], float(b["s"]) + 1.6, side)
			var table: Vector2 = (kerb[0] as Vector2).lerp(b["door"], 0.4)
			if _has("scenery_contest_table"):
				_image(e, table, "scenery_contest_table")
			for k in 4:
				var c := _extra(e, table - (kerb[1] as Vector2) * 0.1 + (kerb[1] as Vector2) * (k - 1.5) * 0.55 - ((kerb[0] as Vector2) - (b["door"] as Vector2)).normalized() * 0.35, kerb[0])
				c["eater"] = k
			for k in 4:
				var f := _extra(e, table + ((kerb[0] as Vector2) - (b["door"] as Vector2)).normalized() * 1.0 + (kerb[1] as Vector2) * (k - 1.5) * 0.7, table)
				f["anim"] = "cheer"
			Game.toast.emit("Pizza-eating contest at %s!" % str(sh["name"]), Color(1.0, 0.75, 0.3))
		"mountain_rescue":
			# a ski patroller at the bottom of the chairlift: someone's hurt up the mountain. Ride over and press A to
			# take the medical kit up Mt. Crankmore (see main._start_rescue).
			var l := _lift_near()
			if l.is_empty():
				return false
			e["t"] = 90.0
			var patrol := _extra(e, (l["base"] as Vector2) + Vector2(1.2, 1.2), city.p_pos, "ski_patrol")
			patrol["anim"] = "cheer"
			_say(patrol, "HELP! Someone's hurt up on Mt. Crankmore!", 4.0)
			Game.toast.emit("SAVE A PERSON ON MT. CRANKMORE! Ride to the chairlift and press A", Color(1.0, 0.4, 0.4))
		"fun_run":
			# a stretch of road closed for a fun run: barriers at both ends, four runners, people cheering. You can
			# still ride through; cars wait at the barriers.
			var r: Dictionary = city.roads[sp[1]]
			var dir := 1.0 if r["closed"] or float(sp[2]) < float(r["len"]) - RUN_LEN - 2.0 else -1.0
			if not r["closed"] and (float(sp[2]) + dir * (RUN_LEN + 1.0) < 0.5 or float(sp[2]) + dir * (RUN_LEN + 1.0) > float(r["len"]) - 0.5):
				return false
			e["t"] = 75.0
			e["dir"] = dir
			e["s0"] = float(sp[2])
			for k in 4:
				var rn := _extra(e, pos, pos, "", RUNNERS)
				rn["runner"] = k
				rn["run_s"] = -k * 0.6
				rn["pace"] = randf_range(1.5, 2.0)
				rn["anim"] = "walk"
				rn["moving"] = true
				rn["fps"] = 14.0
			for k in 4:
				var q: Array = _kerb(sp[1], float(sp[2]) + dir * (3.0 + k * 4.0), float(sp[3]) * (1.0 if k % 2 == 0 else -1.0))
				var fan := _extra(e, q[0], (q[0] as Vector2) - (q[1] as Vector2).orthogonal() * float(sp[3]))
				fan["anim"] = "cheer"
			_fx(e, pos, _draw_closure.bind(e))
			Game.toast.emit("Road closed for the Crankmore Fun Run!", Color(0.5, 0.9, 1.0))
		# ---- seasons ----
		"snowball_fight":
			e["t"] = 60.0
			var road_w: float = (city.ROAD_HW + 0.6) * 2.0
			var teams: Array = []
			for k in 4:
				var q: Vector2 = pos + along * (k % 2 - 0.5) * 1.2 + (across * road_w if k >= 2 else Vector2.ZERO)
				var kid := _extra(e, q, pos + across * road_w * (0.0 if k >= 2 else 1.0), "", KIDS)
				kid["thrower"] = k
				teams.append(kid)
			e["balls"] = []
			_fx(e, pos + across * road_w * 0.5, _draw_snowballs.bind(e))
		"sledding":
			e["t"] = 70.0
			e["sleds"] = []
			for k in 3:
				var q: Vector2 = pos - across * randf_range(2.0, 4.0) + along * (k - 1) * 1.5
				var g := Vector2(city.height_m(q + Vector2(0.5, 0)) - city.height_m(q - Vector2(0.5, 0)), city.height_m(q + Vector2(0, 0.5)) - city.height_m(q - Vector2(0, 0.5)))
				var down := -g.normalized() if g.length() > 0.01 else -across
				var sl := {"type": "sled", "pos": q, "top": q, "face": down, "phase": randf() * 3.0, "label_t": 0.0, "look": {}}
				e["actors"].append(sl)
		"tree_lighting":
			e["t"] = 75.0
			e["stage"] = "count"
			var tq: Vector2 = city.PLAZA + Vector2(-4.5, 3.5)
			var tree := _image(e, tq, "scenery_christmas_tree_big")
			tree["xmas"] = true
			e["tree"] = tree
			for k in 8:
				var a := _extra(e, tq + Vector2.from_angle(PI * 0.1 + k * 0.35) * randf_range(2.0, 3.2), tq)
				a["crowd"] = true
				_arrive(a)
			Game.toast.emit("Christmas tree lighting in the plaza!", Color(0.6, 1.0, 0.6))
		"egg_hunt":
			e["t"] = 80.0
			e["eggs"] = []
			for k in 8:
				var q: Vector2 = pos + along * randf_range(-5.0, 5.0) + across * randf_range(-1.5, 0.4)
				if _free(q):
					e["eggs"].append({"pos": q, "col": EGG_COLS.pick_random()})
			for k in 3:
				var kid := _extra(e, pos + along * (k - 1) * 1.5 - across * 0.5, pos, "", KIDS)
				kid["hunter"] = true
			_fx(e, pos, _draw_eggs.bind(e))
			Game.toast.emit("Easter egg hunt! Ride over an egg to grab it.", Color(1.0, 0.75, 0.9))
		"duck_crossing":
			e["t"] = 40.0
			e["from"] = pos
			e["to"] = pos + across * (city.ROAD_HW + 0.6) * 2.0
			var d := _fx(e, pos, _draw_ducks.bind(e))
			d["duck"] = true
		"volleyball":
			e["t"] = 80.0
			var at: Vector2 = pos
			if city.p_pos.distance_to(city.LAKE) < 40.0:
				at = city.LAKE + Vector2.from_angle(2.6) * (city._lake_r(2.6) + 2.4)
			elif sp.is_empty():
				return false
			_image(e, at, "scenery_volleyball_net")
			for k in 4:
				var side := -1.0 if k < 2 else 1.0
				var pl := _extra(e, at + Vector2(side * 1.4, (k % 2 - 0.5) * 1.2), at)
				pl["anim"] = "cheer" if randf() < 0.3 else "idle"
			e["ball_at"] = at
			_fx(e, at, _draw_volley.bind(e))
		"fishing":
			e["t"] = 90.0
			var ang: float = (city.p_pos - city.LAKE).angle()
			for k in 12:   # a stretch of shore round from where you can see it
				var a3: float = ang + 0.3 * (k + 1) * (1.0 if k % 2 == 0 else -1.0)
				if allow_in_view or not city._in_view(city.LAKE + Vector2.from_angle(a3) * city._lake_r(a3)):
					ang = a3
					break
			for k in 4:
				var a2: float = ang + (k - 1.5) * 0.08
				var q: Vector2 = city.LAKE + Vector2.from_angle(a2) * (city._lake_r(a2) + 1.0)
				var f := _extra(e, q, city.LAKE)
				f["angler"] = city.LAKE + Vector2.from_angle(a2) * (city._lake_r(a2) - 1.2)
				_fx(e, q, _draw_rod.bind(f))
			_say(e["actors"][0], "Biggest trout wins!", 3.0)
		"lemonade":
			e["t"] = 90.0
			if _has("scenery_lemonade_stand"):
				_image(e, pos - across * 0.4, "scenery_lemonade_stand")
			var kid := _extra(e, pos - across * 0.9, pos + across, "", KIDS)
			_say(kid, "Lemonade! 25 cents!", 3.0)
			e["stand"] = pos
		"santa":
			# Santa's sleigh crosses the night sky and drops a present on a parachute just ahead of you: ride over it to
			# unwrap a Hoofy Bike (or, if you have one, some cash). The sky part is drawn by draw_sky, over the dark.
			e["t"] = 90.0
			e["stage"] = "fly"
			var land: Vector2 = city._rail_ahead(5.0, city.ROAD_HW + 0.5)[0]
			e["land"] = land
			var base: Vector2 = Iso.to_screen(city.p_pos, Iso.ground_z(city.p_pos))
			e["sky_y"] = base.y - 175.0
			e["x0"] = base.x - 560.0
			e["x"] = e["x0"]
			e["drop_x"] = Iso.to_screen(land, Iso.ground_z(land)).x - 60.0
			e["fall"] = -1.0
			Game.toast.emit("Ho ho ho! Look up!", Color(1.0, 0.3, 0.3))
		"zombie_kids":
			# kids in zombie costumes lurch out after you: half your FTP gets you away (City.CHALLENGES "zombies")
			if not city.start_challenge("zombies"):
				return false
			e["t"] = 60.0
			var have: Array = ZOMBIES.filter(func(d): return _has("ped_%s_walk" % d))
			var from: Vector2 = city.challenge_pos()[0]   # (out of sight behind you, closing in)
			for k in 4:
				var z: Dictionary
				if k < have.size():
					z = _person(from, have[k], city.p_fwd)
				else:   # no zombie art yet: trick-or-treaters gone a bit green
					z = _person(from, "", city.p_fwd)
					z["looks"] = (["tot_ghost", "tot_witch", "tot_pumpkin", "tot_skeleton"] + KIDS).filter(func(d): return _has("ped_%s_walk" % d))
					z["tint"] = Color(0.7, 1.0, 0.65)
				z["zombie"] = k
				z["anim"] = "walk"
				z["moving"] = true
				z["fps"] = 7.0
				e["actors"].append(z)
			_say(e["actors"][0], "BRAAAAINS!", 2.5)
			Game.toast.emit("ZOMBIE KIDS! Get away from them (50% of your FTP)!", Color(0.6, 1.0, 0.5))
		"trick_or_treat":
			e["t"] = 70.0
			e["dir"] = 1.0 if randf() < 0.5 else -1.0
			var tots: Array = ["tot_ghost", "tot_witch", "tot_pumpkin", "tot_skeleton"].filter(func(d): return _has("ped_%s_walk" % d))
			for k in 4:
				var t := _extra(e, pos, pos, tots[k] if k < tots.size() else "", KIDS)
				t["tot"] = k
				t["anim"] = "walk"
				t["moving"] = true
			var mum := _extra(e, pos, pos)
			mum["tot"] = 4
			mum["anim"] = "walk"
			mum["moving"] = true
		"hayride":
			var lead := {"road": sp[1], "s": sp[2], "dir": 1.0 if randf() < 0.5 else -1.0, "speed": 0.0, "max": 1.0, "col": Color.WHITE,
				"kind": "truck_tractor", "art": "vehicle_truck_tractor", "hl": 0.6, "hw": 0.32, "wait": 0.0, "pos": Vector2.ZERO, "fwd": Vector2.RIGHT, "last_j": -1}
			if not _has("vehicle_truck_tractor"):
				lead["hidden"] = true
			city._car_pose(lead)
			city.cars.append(lead)
			e["car"] = lead
			e["trail"] = [[lead["pos"], lead["fwd"]]]
			e["t"] = 60.0
			var wagon := _image(e, lead["pos"], "scenery_hay_wagon" if _has("scenery_hay_wagon") else "scenery_haybale")
			wagon["wagon"] = true
			for k in 3:
				var rider := _extra(e, lead["pos"], lead["pos"])
				rider["rider_k"] = k
				rider["lift"] = 27.0      # up on the wagon's bed (art/scenery_hay_wagon.png: the bed is ~30 px up)
				rider["seated"] = true
				rider["anim"] = "cheer" if k == 1 else "idle"
			Game.toast.emit("All aboard the haunted hayride!", Color(1.0, 0.6, 0.2))
		"harvest_festival":
			e["t"] = 100.0
			var back := -across
			for k in 3:
				_image(e, pos + back * 1.2 + along * (k - 1) * 1.7, ["scenery_stall_orange", "scenery_stall_red", "scenery_stall_green"][k])
			_image(e, pos + back * 0.2 + along * 2.8, "scenery_haystack")
			_image(e, pos + back * 2.4 + along * -2.6, "scenery_scarecrow")
			e["pumpkins"] = [pos + along * -2.2 + back * 0.2, pos + along * 0.8 + back * 2.3]
			_fx(e, pos, _draw_pumpkins.bind(e))
			for k in 7:
				var sh := _extra(e, pos + along * randf_range(-2.5, 2.5) + back * randf_range(0.0, 0.8), pos + back)
				sh["shopper"] = true
				sh["wait"] = randf_range(0.0, 4.0)
			Game.toast.emit("The harvest festival is on!", Color(1.0, 0.65, 0.25))
		# ---- chaos ----
		"outage":
			city.outage_t = 75.0
			e["t"] = 75.0
			Game.toast.emit("POWER CUT! The street lights are out...", Color(1.0, 0.6, 0.4))
		"cart":
			e["t"] = 14.0
			var at: Array = city._rail_ahead(14.0, city.BIKE_LANE)
			var cart := {"type": "cart", "pos": at[0], "face": -(at[1] as Vector2), "phase": 0.0, "label_t": 0.0, "d": 14.0, "spin": 0.0}
			e["actors"].append(cart)
			_say(cart, "LOOK OUT!", 2.0)
			Game.toast.emit("A runaway shopping cart is rolling straight at you!", Color(1.0, 0.6, 0.4))
		"hydrant":
			e["t"] = 90.0
			var hq: Vector2 = pos - across * 0.2
			if _has("scenery_fire_hydrant"):
				_image(e, hq, "scenery_fire_hydrant")
			e["pool"] = pos + across * (city.ROAD_HW + 0.6) * 0.8
			_fx(e, hq, _draw_flood.bind(e))
			for k in 3:
				var kid := _extra(e, pos + along * (k - 1) * 1.0 + across * 0.6, hq, "", KIDS)
				kid["anim"] = "cheer"
			Game.toast.emit("A hydrant's burst - the street's flooded!", Color(0.6, 0.85, 1.0))
		"kid_race":
			# a kid pulls up beside you on a BMX: "race you to the corner!"
			if not city.start_challenge("kid_race"):
				return false
			e["t"] = 80.0
			var at: Array = city._rail_ahead(-16.0, city.BIKE_LANE - 0.4)   # (pedals up from behind you)
			var kid := {"type": "rider", "who": "kid" if Sprites.sheet("bike_kid") != null else "", "design": "", "looks": KIDS,
				"k": 0, "pos": at[0], "face": at[1], "phase": 0.0, "pedal": 0.0, "label_t": 0.0}
			e["actors"].append(kid)
			_give_face(kid, "kid", "Kid", Color(1.0, 0.35, 0.3))
			_say(kid, ["Race you to that line! Loser's a slowpoke!", "Bet I can beat you! First to the line!", "Hey! Race me!"].pick_random(), 3.0)
		"seagulls":
			if not city.start_challenge("gulls"):
				return false
			e["t"] = 100.0   # as long as the chase can last
			var from: Array = city.challenge_pos()   # (out of sight behind you, closing in)
			for k in 4:
				e["actors"].append({"type": "gull", "k": k, "pos": from[0], "face": from[1], "phase": randf() * 2.0, "label_t": 0.0})
			_say(e["actors"][0], "MINE! MINE!", 2.0)
			Game.toast.emit("SEAGULLS! They want your pizza - get away (90% of your FTP)!", Color(1.0, 0.85, 0.4))
	return true


# ---------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------

func _step(e: Dictionary, delta: float) -> void:
	if not e["kind"] in all_kinds():
		super._step(e, delta)
		return
	e["clock"] = float(e["clock"]) + delta
	var p: Vector2 = city.p_pos
	var riding: bool = city.active and city.er_timer <= 0.0
	match e["kind"]:
		"parade_float":
			var r: Dictionary = city.roads[0]
			e["s"] = city._wrap_s(r, float(e["s"]) + float(e["dir"]) * 0.55 * delta)
			var at: Array = city._road_at(r, e["s"])
			var f: Vector2 = at[1] * float(e["dir"])
			var mid: Vector2 = at[0] + Vector2(-f.y, f.x) * 0.5
			for a in e["actors"]:
				if a.has("handler"):
					var k: int = a["handler"]
					a["pos"] = mid + f * (0.9 if k < 2 else -0.9) + Vector2(-f.y, f.x) * (0.45 if k % 2 == 0 else -0.45)
					a["face"] = f
				elif a.get("balloon", false) or a["type"] == "fx":
					a["pos"] = mid
		"market", "harvest_festival":
			for a in e["actors"]:
				if a.get("shopper", false):
					if a.get("moving", false):
						_walk_to(a, delta)
					else:
						a["wait"] = float(a["wait"]) - delta
						if a["wait"] <= 0.0:
							a["to"] = (e["pos"] as Vector2) + (e["along"] as Vector2) * randf_range(-2.5, 2.5) - (e["across"] as Vector2) * randf_range(0.0, 0.6)
							a["speed"] = 0.5
							a["moving"] = true
							a["anim"] = "walk"
							a["wait"] = randf_range(3.0, 7.0)
						elif a["label_t"] <= 0.0 and randf() < delta * 0.05:
							_say(a, ["Fresh corn!", "Look at these tomatoes!", "Two for one!", "Smells amazing.", "Got any squash?"].pick_random(), 2.0)
			if e["kind"] == "market":
				e["spill"] = float(e["spill"]) - delta
				if e["spill"] <= 0.0:
					e["spill"] = 999.0
					var who: Dictionary = e["actors"].filter(func(a): return a.get("shopper", false))[0]
					_say(who, "Oh no, my apples!", 2.5)
					e["apples"] = {"from": who["pos"], "t": 0.0}
					_fx(e, who["pos"], _draw_apples.bind(e))
				if e.has("apples"):
					e["apples"]["t"] = float(e["apples"]["t"]) + delta
		"car_wash":
			for a in e["actors"]:
				if a.get("washer", false) and randf() < delta * 0.3:
					a["anim"] = "cheer" if a["anim"] == "idle" else "idle"
		"wedding":
			var couple: Array = e["actors"].filter(func(a): return a.get("couple", false))
			var car: Dictionary = {}
			for a in e["actors"]:
				if a.get("wedding_car", false):
					car = a
			match e["stage"]:
				"rice":
					if e["clock"] > 8.0:
						e["stage"] = "walk"
						for a in couple:
							a["to"] = car["pos"] if not car.is_empty() else e["kerb"]
							a["speed"] = 0.7
							a["moving"] = true
							a["anim"] = "walk"
				"walk":
					var there := true
					for a in couple:
						_walk_to(a, delta)
						if a.get("moving", false):
							there = false
					if there:
						for a in couple:
							a["gone"] = true
						e["stage"] = "drive"
						e["clock"] = 0.0
						if not car.is_empty():
							_say(car, "JUST MARRIED!", 4.0)
				"drive":
					if not car.is_empty():
						car["pos"] = (car["pos"] as Vector2) + (car["face"] as Vector2) * minf(float(e["clock"]) * 1.5, 3.0) * delta
						car["moving"] = true
					if e["clock"] > 6.0:
						e["t"] = minf(float(e["t"]), 0.5)
		"flash_mob":
			match e["stage"]:
				"gather":
					var all_there := true
					for a in e["actors"]:
						_walk_to(a, delta)
						if a.get("moving", false):
							all_there = false
					if all_there or e["clock"] > 12.0:
						e["stage"] = "dance"
						e["clock"] = 0.0
						for a in e["actors"]:
							a["moving"] = false
							a["anim"] = "cheer"
							a["phase"] = 0.0   # all in step
							a["face"] = Vector2(1, 1)
						Game.toast.emit("FLASH MOB!", Color(1.0, 0.5, 0.9))
				"dance":
					for a in e["actors"]:
						if a["label_t"] <= 0.0 and randf() < delta * 0.1:
							_say(a, ["Five, six, seven, eight!", "Woo!", "And spin!"].pick_random(), 1.5)
					if e["clock"] > 14.0:
						e["stage"] = "leave"
						for a in e["actors"]:
							a["to"] = (a["pos"] as Vector2) + Vector2.from_angle(randf() * TAU) * 6.0
							a["speed"] = 0.8
							a["moving"] = true
							a["anim"] = "walk"
							a["label_t"] = 0.0
				"leave":
					for a in e["actors"]:
						_walk_to(a, delta)
		"cows":
			for a in e["actors"]:
				if a.get("cow", false):
					if a.has("to") and a.get("moving", false):
						var to: Vector2 = a["to"] - a["pos"]
						if to.length() < 0.05:
							a["moving"] = false
							a["anim"] = "idle"
						else:
							a["pos"] += to.normalized() * minf(to.length(), 0.45 * delta)
							a["face"] = to.normalized()
							a["anim"] = "run"
					else:
						a["wait"] = float(a["wait"]) - delta
						if a["wait"] <= 0.0:
							a["wait"] = randf_range(2.0, 5.0)
							a["to"] = (e["pos"] as Vector2) + (e["along"] as Vector2) * randf_range(-2.5, 2.5) + (e["across"] as Vector2) * randf_range(-0.5, 2.0)
							a["moving"] = true
						elif a["label_t"] <= 0.0 and randf() < delta * 0.08:
							_say(a, "Mooo!", 1.4)
				elif a["type"] == "person" and a["label_t"] <= 0.0 and randf() < delta * 0.15:
					_say(a, ["Come on, girls!", "Shoo! Off the road!", "Sorry, folks!", "Daisy, NO!"].pick_random(), 2.0)
		"hot_air_balloon":
			for a in e["actors"]:
				if a.get("hab", false):
					a["lift"] = minf(float(a["lift"]) + delta * (6.0 if e["clock"] > 4.0 else 0.0), 420.0)
					a["pos"] = (a["pos"] as Vector2) + (a["drift"] as Vector2) * delta * clampf(float(a["lift"]) / 80.0, 0.0, 1.0)
		"movie_night":
			for a in e["actors"]:
				if a.get("seated", false) and a["label_t"] <= 0.0 and randf() < delta * 0.02:
					_say(a, ["Ooh!", "Don't open the door!", "Ha ha!", "*crunch*", "Shhh!"].pick_random(), 1.5)
		"arcade_queue", "video_rush":
			for a in e["actors"]:
				if a.get("queue", false):
					if a.get("moving", false):
						_walk_to(a, delta)
						if not a.get("moving", false):
							a["gone"] = true
					elif a["label_t"] <= 0.0 and randf() < delta * 0.06:
						_say(a, (e["lines"] as Array).pick_random(), 2.0)
			if e["clock"] > 45.0 and e["stage"] == "":
				e["stage"] = "open"
				var first: Dictionary = e["actors"][0]
				_say(first, "THE DOORS ARE OPEN!", 2.5)
				for a in e["actors"]:
					a["to"] = e["b"]["door"]
					a["speed"] = 1.4
					a["moving"] = true
					a["anim"] = "run"
		"eating_contest":
			for a in e["actors"]:
				if a.has("eater"):
					a["lift"] = absf(sin(float(e["clock"]) * 8.0 + int(a["eater"]))) * 2.0   # chomping away
			if e["clock"] > 40.0 and e["stage"] == "":
				e["stage"] = "won"
				var eaters: Array = e["actors"].filter(func(a): return a.has("eater"))
				var champ: Dictionary = eaters.pick_random()
				champ["anim"] = "cheer"
				_say(champ, "CHAMPION! 23 slices!", 4.0)
				for a in eaters:
					a["lift"] = 0.0
					if a != champ and not eaters.any(func(o): return o.get("ill", false)):
						a["ill"] = true
						a["tint"] = Color(0.75, 1.0, 0.7)
						_say(a, "Urgh... no more...", 4.0)
		"snowball_fight":
			var balls: Array = e["balls"]
			for b in balls:
				b["t"] = float(b["t"]) + delta / float(b["dur"])
			e["balls"] = balls.filter(func(b): return b["t"] < 1.0)
			for a in e["actors"]:
				if a.has("thrower") and randf() < delta * 0.7:
					var at_you: bool = riding and p.distance_to(a["pos"]) < 4.5 and randf() < 0.5
					var foes: Array = e["actors"].filter(func(o): return o.has("thrower") and (int(o["thrower"]) >= 2) != (int(a["thrower"]) >= 2))
					var to: Vector2 = p if at_you else (foes.pick_random()["pos"] if not foes.is_empty() else a["pos"])
					e["balls"].append({"from": a["pos"], "to": to, "t": 0.0, "dur": 0.7, "you": at_you})
					a["anim"] = "cheer"
					a["phase"] = 0.0
					if at_you:
						_say(a, ["Gotcha!", "Incoming!", "SNOWBALL!"].pick_random(), 1.2)
			for b in e["balls"]:
				if b["you"] and float(b["t"]) > 0.95 and not b.get("hit", false):
					b["hit"] = true
					city.player_bubble = {"text": "SPLAT!", "t": 1.2}
		"sledding":
			for a in e["actors"]:
				if a["type"] == "sled":
					# down the slope (4 s), then off the sled and back up the hill with it (6 s)
					if not a.has("ph0"):
						a["ph0"] = a["phase"]
					var c := fposmod(float(e["clock"]) * 0.1 + float(a["ph0"]), 1.0)
					var u := c / 0.4 if c < 0.4 else 1.0 - (c - 0.4) / 0.6
					a["pos"] = (a["top"] as Vector2) + (a["face"] as Vector2) * u * 5.0
					a["u"] = u
					a["climb"] = c >= 0.4
		"tree_lighting":
			var tree: Dictionary = e["tree"]
			if e["stage"] == "count":
				var n := 3 - int(float(e["clock"]) - 6.0)
				if e["clock"] > 6.0 and n >= 1 and n != int(e.get("said", 0)):
					e["said"] = n
					for a in e["actors"]:
						if a.get("crowd", false):
							_say(a, "%d!" % n, 0.9)
							break
				if e["clock"] > 9.0:
					e["stage"] = "lit"
					tree["lit"] = true
					for a in e["actors"]:
						if a.get("crowd", false):
							a["anim"] = "cheer"
					Game.toast.emit("The Christmas tree is lit!", Color(1.0, 0.9, 0.4))
		"egg_hunt":
			var eggs: Array = e["eggs"]
			for egg in eggs:
				if riding and p.distance_to(egg["pos"]) < 0.9:
					egg["got"] = true
					Game.add_money(5)
					Game.toast.emit("Found an egg! +$5", egg["col"])
			for a in e["actors"]:
				if a.get("hunter", false):
					var left: Array = eggs.filter(func(g): return not g.get("got", false))
					if left.is_empty():
						continue
					if not a.get("moving", false):
						var target: Dictionary = left.pick_random()
						a["egg"] = target
						a["to"] = target["pos"]
						a["speed"] = 0.7
						a["moving"] = true
					_walk_to(a, delta)
					if not a.get("moving", false) and a.has("egg"):
						a["egg"]["got"] = true
						a["anim"] = "cheer"
						_say(a, "I found one!", 1.5)
						a.erase("egg")
			e["eggs"] = eggs.filter(func(g): return not g.get("got", false))
		"duck_crossing":
			e["u"] = clampf(float(e["clock"]) / 30.0, 0.0, 1.0)
		"fishing":
			for a in e["actors"]:
				if a.has("angler") and a["label_t"] <= 0.0 and randf() < delta * 0.04:
					_say(a, ["I got one!", "It's a boot...", "Whoa, a big one!", "Nibble nibble...", "It got away!"].pick_random(), 2.0)
					a["anim"] = "cheer" if randf() < 0.5 else "idle"
		"lemonade":
			if not e.get("sold", false) and riding and p.distance_to(e["stand"]) < 2.2 and city.p_speed < 0.6:
				e["sold"] = true
				Game.add_money(10)
				Game.toast.emit("You stopped for lemonade! The kid's mum tips you $10 for the business.", Color(1.0, 0.95, 0.4))
				var kid: Dictionary = e["actors"].filter(func(a): return a["type"] == "person")[0]
				_say(kid, "Thank you! Come again!", 3.0)
				kid["anim"] = "cheer"
		"trick_or_treat":
			var r: Dictionary = city.roads[e["road"]]
			e["s"] = city._wrap_s(r, float(e["s"]) + float(e["dir"]) * 0.35 * delta)
			for a in e["actors"]:
				if a.has("tot"):
					var k: int = a["tot"]
					var q: Array = _kerb(e["road"], float(e["s"]) - float(e["dir"]) * k * 0.55, float(e["side"]))
					a["pos"] = q[0]
					a["face"] = (q[1] as Vector2) * float(e["dir"])
					if a["label_t"] <= 0.0 and randf() < delta * 0.08:
						_say(a, ["Trick or treat!", "Candy!", "Boo!", "I'm a ghost! Whooo!"].pick_random() if k < 4 else "Stay together, kids!", 1.8)
		"hayride":
			var lead: Dictionary = e["car"]
			var trail: Array = e["trail"]
			if (trail[-1][0] as Vector2).distance_to(lead["pos"]) > 0.12:
				trail.append([lead["pos"], lead["fwd"]])
				if trail.size() > 60:
					trail.pop_front()
			var back := func(d: float) -> Array:
				var i := trail.size() - 1
				var run := 0.0
				while i > 0 and run < d:
					run += (trail[i][0] as Vector2).distance_to(trail[i - 1][0])
					i -= 1
				return trail[i]
			for a in e["actors"]:
				if a.get("wagon", false):
					var w: Array = back.call(1.5)
					a["pos"] = w[0]
					a["flip"] = Iso.to_screen(w[1]).x < 0.0
				elif a.has("rider_k"):
					# sitting on the hay, spread along the wagon, drawn just after it so they're on top of it
					var w: Array = back.call(1.5)
					a["pos"] = (w[0] as Vector2) + (w[1] as Vector2) * (float(a["rider_k"]) - 1.0) * 0.45 + Vector2(0.06, 0.06)
					a["face"] = w[1]
					if a["label_t"] <= 0.0 and randf() < delta * 0.1:
						_say(a, ["Boo!", "Wheee!", "Spooky!", "Hold on to your hats!"].pick_random(), 1.5)
		"mountain_rescue":
			var patrol: Dictionary = e["actors"][0]
			patrol["face"] = (city.p_pos - (patrol["pos"] as Vector2)).normalized()
			if patrol["label_t"] <= 0.0:
				_say(patrol, ["HELP! A skier's hurt up the mountain!", "We need someone fast! Grab the medical kit!", "Over here! Press A to help!"].pick_random(), 3.0)
			if int(e["clock"]) % 15 == 14 and e.get("nagged", -1) != int(e["clock"]):
				e["nagged"] = int(e["clock"])
				Game.toast.emit("SAVE A PERSON ON MT. CRANKMORE! Ride to the chairlift and press A", Color(1.0, 0.4, 0.4))
		"fun_run":
			var r: Dictionary = city.roads[e["road"]]
			var all_in := true
			for a in e["actors"]:
				if a.has("runner"):
					a["run_s"] = float(a["run_s"]) + float(a["pace"]) * delta
					var along := clampf(float(a["run_s"]), 0.0, RUN_LEN)
					var at: Array = city._road_at(r, city._wrap_s(r, float(e["s0"]) + float(e["dir"]) * along))
					var f: Vector2 = (at[1] as Vector2) * float(e["dir"])
					a["pos"] = (at[0] as Vector2) + f.orthogonal() * ((int(a["runner"]) - 1.5) * 0.3)
					a["face"] = f
					if float(a["run_s"]) < RUN_LEN:
						all_in = false
						a["moving"] = true
					else:
						a["moving"] = false
						a["anim"] = "cheer"
					if a["label_t"] <= 0.0 and randf() < delta * 0.06:
						_say(a, ["Keep going!", "Almost there!", "My legs!", "Personal best!", "Water!"].pick_random(), 1.6)
			if all_in and e["stage"] == "":
				e["stage"] = "done"
				e["t"] = minf(float(e["t"]), 6.0)
		"cart":
			for a in e["actors"]:
				if a["type"] == "cart":
					a["d"] = float(a["d"]) - delta * 2.6 - city.p_speed * delta
					var at: Array = city._rail_ahead(float(a["d"]), city.BIKE_LANE)
					a["pos"] = at[0]
					a["face"] = -(at[1] as Vector2)
					a["spin"] = float(a["spin"]) + delta * 6.0
					if riding and not e.get("hit", false) and p.distance_to(a["pos"]) < 0.55 and city.invuln <= 0.0:
						e["hit"] = true
						city.p_speed *= 0.25
						city.invuln = 1.5
						Game.toast.emit("OOF! Clobbered by a runaway shopping cart!", Color(1.0, 0.5, 0.4))
					if float(a["d"]) < -6.0:
						a["gone"] = true
						e["t"] = minf(float(e["t"]), 0.3)
		"hydrant":
			if riding and p.distance_to(e["pool"]) < 1.6:
				city.p_speed *= 1.0 - 1.2 * delta   # wading through
				if randf() < delta * 2.0:
					city.player_bubble = {"text": "SPLOOSH!", "t": 0.8}
		"kid_race":
			var c: Dictionary = city.challenge
			var kid: Dictionary = e["actors"][0]
			if c.is_empty() or c["kind"] != "kid_race":
				# pedals off on along the race route (or up the road, if it never got going)
				if not e.has("leave_d"):
					e["leave_d"] = float(e["route_d"]) if e.has("route") else ((kid["pos"] as Vector2) - city.p_pos).dot(city.p_fwd)
				e["leave_d"] = float(e["leave_d"]) + ((1.5 if e.has("route") else city.p_speed + 1.5)) * delta
				var at: Array = city.route_at(e["route"], float(e["leave_d"]), city.BIKE_LANE - 0.4) if e.has("route") \
					else city._rail_ahead(float(e["leave_d"]), city.BIKE_LANE - 0.4)
				_place(kid, at[0])
				kid["face"] = at[1]
				e["t"] = minf(float(e["t"]), 3.0)
				return
			var at: Array = city.challenge_pos()
			var u: float = clampf(1.0 - float(c.get("count", 0.0)) / 3.0, 0.0, 1.0)
			if c["state"] == "count":   # pedals up from out of sight behind you while counting down
				at = city._rail_ahead(lerpf(-16.0, 0.0, u * (2.0 - u)), city.BIKE_LANE - 0.4)
			_place(kid, at[0])
			kid["face"] = at[1]
			kid["pedal"] = float(kid["pedal"]) + delta * 8.0
			if c["state"] != "count":   # where it is on the route, for riding off afterwards
				e["route"] = c["route"]
				e["route_d"] = float(c["them_m"]) * city.TILES_PER_MS * city.PACE
			if c["state"] == "count":
				if kid["label_t"] <= 0.0 and u > 0.6:
					_say(kid, str(int(ceil(float(c["count"])))) + "...", 0.9, "")
			elif c["state"] == "won" and not e.get("said", false):
				e["said"] = true
				_say(kid, ["No fair! You've got gears!", "Aww... here's your $20.", "Rematch tomorrow!"].pick_random(), 3.0, "annoyed")
			elif c["state"] == "lost" and not e.get("said", false):
				e["said"] = true
				_say(kid, ["HA! Beat you!", "Too slow, pizza person!", "Woo-hoo! I win!"].pick_random(), 3.0, "happy")
		"santa":
			e["x"] = float(e["x"]) + 190.0 * delta
			if float(e["fall"]) < 0.0 and float(e["x"]) >= float(e["drop_x"]):
				e["fall"] = 0.0   # present away!
				e["from"] = Vector2(float(e["x"]) + 20.0, float(e["sky_y"]) + 30.0)
			if float(e["fall"]) >= 0.0 and e["stage"] == "fly":
				e["fall"] = float(e["fall"]) + delta / 3.5
				if float(e["fall"]) >= 1.0:
					e["stage"] = "landed"
					var gift := _image(e, e["land"], "scenery_present_big")
					gift["gift"] = true
			if e["stage"] == "landed" and riding and p.distance_to(e["land"]) < 1.4:
				e["stage"] = "opened"
				for a in e["actors"]:
					if a.get("gift", false):
						a["gone"] = true
				if Game.give_bike(Game.HOOFY):
					Game.toast.emit("A HOOFY BIKE from Santa! You're riding it now (switch bikes in the pause menu: My bikes).", Color(1.0, 0.35, 0.35))
				else:
					Game.add_money(100)
					Game.save_game()
					Game.toast.emit("Santa's present: $100! (You've already got the Hoofy Bike.)", Color(1.0, 0.35, 0.35))
				city.player_bubble = {"text": "Thanks, Santa!", "t": 2.5}
				e["t"] = minf(float(e["t"]), 2.0)
		"zombie_kids":
			var c: Dictionary = city.challenge
			if c.is_empty() or c["kind"] != "zombies" or c["state"] in ["won", "lost"]:
				# give up the chase (or crowd round you, cheering, if they caught you)
				var caught: bool = not c.is_empty() and c["kind"] == "zombies" and c["state"] == "lost"
				for a in e["actors"]:
					if caught:
						a["moving"] = false
						a["anim"] = "cheer"
						if a["label_t"] <= 0.0:
							_say(a, ["Trick or treat!", "Gotcha!", "Candy tax!"].pick_random(), 2.0)
					else:
						a["moving"] = false
						a["anim"] = "idle"
				if not e.get("ending", false):
					e["ending"] = true
					e["t"] = minf(float(e["t"]), 4.0)
				return
			var at: Array = city.challenge_pos()
			for a in e["actors"]:
				var k: int = a["zombie"]
				var f: Vector2 = at[1]
				a["pos"] = (at[0] as Vector2) - f * (k / 2) * 0.6 + f.orthogonal() * ((k % 2) * 0.6 - 0.3)
				a["face"] = f
				a["moving"] = true
				if a["label_t"] <= 0.0 and randf() < delta * 0.3:
					_say(a, ["BRAAAINS!", "Uuuurgh...", "Trick or treat... or BRAINS!", "Come back, pizza!", "Graaawr!"].pick_random(), 1.6)
		"seagulls":
			var c: Dictionary = city.challenge
			if c.is_empty() or c["kind"] != "gulls" or c["state"] in ["won", "lost"]:
				for a in e["actors"]:
					a["pos"] = (a["pos"] as Vector2) - (a["face"] as Vector2) * 3.0 * delta
				if e.get("ending", 0.0) == 0.0:
					e["ending"] = 1.0
					e["t"] = minf(float(e["t"]), 3.0)
				return
			var at: Array = city.challenge_pos()
			for a in e["actors"]:
				var k: int = a["k"]
				a["pos"] = (at[0] as Vector2) + Vector2(sin(e["clock"] * 2.0 + k * 1.7), cos(e["clock"] * 1.6 + k * 2.3)) * 0.5
				a["face"] = at[1]
				if a["label_t"] <= 0.0 and randf() < delta * 0.25:
					_say(a, ["MINE!", "MINE! MINE!", "SQUAWK!", "Pizza!"].pick_random(), 1.2)


func _end(e: Dictionary) -> void:
	if e["kind"] == "outage":
		city.outage_t = 0.0
		Game.toast.emit("The power's back on.", Color(1.0, 0.95, 0.6))
	super._end(e)


## Cows are solid: ride up to one and you stop until it wanders out of your way (it lets you know).
func blocks_rider(pos: Vector2, fwd: Vector2) -> bool:
	for e in events:
		if e["kind"] != "cows":
			continue
		for a in e["actors"]:
			if not a.get("cow", false):
				continue
			var rel: Vector2 = (a["pos"] as Vector2) - pos
			var ahead := rel.dot(fwd)
			if ahead > -0.1 and ahead < 0.95 and absf(rel.dot(fwd.orthogonal())) < 0.6:
				if a["label_t"] <= 0.0:
					_say(a, ["MOOO!", "Moo?", "*chews*", "Mooo. (not moving)"].pick_random(), 1.6)
				return true
	return false


## The cows, ducks and the giant balloon's handlers have the road: cars wait for them (with the band and group rides).
func ride_spots() -> Array:
	var out: Array = super.ride_spots()
	for e in events:
		match e["kind"]:
			"cows", "parade_float":
				for a in e["actors"]:
					if a.get("cow", false) or a.has("handler"):
						out.append(a["pos"])
			"duck_crossing":
				out.append((e["from"] as Vector2).lerp(e["to"], float(e.get("u", 0.0))))
			"fun_run":
				var r: Dictionary = city.roads[e["road"]]
				for end in [-1.0, RUN_LEN + 1.0]:
					var at: Array = city._road_at(r, city._wrap_s(r, float(e["s0"]) + float(e["dir"]) * end))
					for lane in [-0.42, 0.42]:
						out.append((at[0] as Vector2) + (at[1] as Vector2).orthogonal() * lane)
	return out


## Santa's sleigh and the present floating down on its parachute, in the sky over the dark (sky_fx.gd).
func draw_sky(ci: CanvasItem) -> void:
	super.draw_sky(ci)
	for e in events:
		if e["kind"] != "santa":
			continue
		var at := Vector2(float(e["x"]), float(e["sky_y"]) + sin(float(e["clock"]) * 2.0) * 4.0)
		var tex := Sprites.sheet("santa_sleigh_fly")
		if tex != null:
			var fh := float(tex.get_height())
			var fw := fh * 2.0
			var n := maxi(1, int(tex.get_width() / fw))
			var f := int(float(e["clock"]) * 10.0) % n
			ci.draw_texture_rect_region(tex, Rect2(at - Vector2(fw, fh) * 0.5, Vector2(fw, fh)), Rect2(f * fw, 0, fw, fh))
		else:   # no art: a red sleigh and a line of reindeer, the leader's nose glowing
			ci.draw_rect(Rect2(at + Vector2(-24, -6), Vector2(30, 12)), Color(0.85, 0.12, 0.12))
			ci.draw_circle(at + Vector2(-12, -12), 6.0, Color(0.85, 0.12, 0.12))
			ci.draw_circle(at + Vector2(-12, -18), 4.0, Color(0.98, 0.85, 0.75))
			for k in 4:
				var d := at + Vector2(16 + k * 16, -2 + sin(float(e["clock"]) * 9.0 + k) * 2.0)
				ci.draw_rect(Rect2(d + Vector2(-6, -4), Vector2(12, 6)), Color(0.5, 0.32, 0.18))
				ci.draw_line(d + Vector2(-4, 2), d + Vector2(-6, 7), Color(0.4, 0.25, 0.12), 1.0)
				ci.draw_line(d + Vector2(4, 2), d + Vector2(6, 7), Color(0.4, 0.25, 0.12), 1.0)
				if k == 3:
					ci.draw_circle(d + Vector2(7, -3), 2.0, Color(1.0, 0.2, 0.2))
		if fmod(float(e["clock"]), 2.0) < 1.0:
			ci.draw_string(ThemeDB.fallback_font, at + Vector2(-30, -30), "HO HO HO!", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 9, Color(1.0, 0.95, 0.95))
		# the present on its way down
		var u := float(e["fall"])
		if u >= 0.0 and u < 1.0:
			var land: Vector2 = Iso.to_screen(e["land"], Iso.ground_z(e["land"]))
			var q: Vector2 = (e["from"] as Vector2).lerp(land, u * u * 0.3 + u * 0.7) + Vector2(sin(u * 9.0) * 6.0, 0)
			if not Sprites.draw_image(ci, "scenery_parachute_present", q):
				ci.draw_arc(q + Vector2(0, -26), 12.0, PI, TAU, 10, Color(1, 1, 1), 2.0)
				ci.draw_line(q + Vector2(-12, -26), q + Vector2(-4, -8), Color(0.9, 0.9, 0.9), 1.0)
				ci.draw_line(q + Vector2(12, -26), q + Vector2(4, -8), Color(0.9, 0.9, 0.9), 1.0)
				ci.draw_rect(Rect2(q + Vector2(-6, -9), Vector2(12, 9)), Color(0.85, 0.15, 0.15))
				ci.draw_rect(Rect2(q + Vector2(-1, -9), Vector2(2, 9)), Color(1.0, 0.85, 0.2))


## Extra light at night: the movie screen and the lit Christmas tree.
func flash_lights() -> Array:
	var out: Array = super.flash_lights()
	for e in events:
		if e["kind"] == "santa" and e["stage"] == "landed":
			out.append([Iso.to_screen(e["land"]), 60.0, 0.9])   # the present glowing in the snow
	for e in events:
		for a in e["actors"]:
			if a.get("screen", false):
				out.append([Iso.to_screen(a["pos"], 30.0), 70.0, 0.8])
			elif a.get("lit", false):
				out.append([Iso.to_screen(a["pos"]), 90.0, 0.85])
	return out


# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------

func draw_actor(ci: CanvasItem, a: Dictionary) -> void:
	var ground := Iso.to_screen(a["pos"])
	var ph: float = a["phase"]
	match a["type"]:
		"image":
			var lift: float = a.get("lift", 0.0)
			var bob := sin(ph * 1.4) * 2.0 if lift > 0.0 else 0.0
			if lift > 0.0:
				ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-10, 0), ground + Vector2(0, -4), ground + Vector2(10, 0), ground + Vector2(0, 4)]), Color(0, 0, 0, 0.18))
			if a.get("hab", false):
				# the burner flaring now and then
				if int(ph * 2.0) % 3 == 0:
					ci.draw_circle(ground + Vector2(0, -lift - 34), 3.0, Color(1.0, 0.7, 0.2, 0.9))
			if not Sprites.draw_image(ci, a["name"], ground + Vector2(0, -lift + bob), bool(a.get("flip", false))):
				_draw_stand_in(ci, a, ground + Vector2(0, -lift + bob))
			if a.get("xmas", false) and a.get("lit", false):
				for k in 18:
					var q := ground + Vector2(sin(k * 2.39) * (4.0 + k * 1.3), -10.0 - k * 4.0)
					var on := int(ph * 3.0 + k) % 3 != 0
					ci.draw_rect(Rect2(q.round(), Vector2(2, 2)), [Color(1, 0.3, 0.3), Color(1, 0.9, 0.3), Color(0.4, 0.8, 1), Color(0.5, 1, 0.5)][k % 4] if on else Color(0.3, 0.3, 0.3))
			if a.get("screen", false):
				# the film flickering on the screen
				var c := Color.from_hsv(fposmod(ph * 0.13, 1.0), 0.35, 1.0, 0.55)
				ci.draw_rect(Rect2(ground + Vector2(-26, -58), Vector2(52, 28)), c)
		"fx":
			(a["fn"] as Callable).call(ci, a, ground)
		"sled":
			var climb: bool = a.get("climb", false)
			var look := Sprites.cast(a["look"], KIDS, true)   # (kept all the way down, for the walk back up)
			if climb or not Sprites.draw_vehicle(ci, "obj_sled_kid", ground, a["face"], Color.WHITE, 0, a):
				# (walking it back up the hill, or no sled art: a kid on a red sled)
				if look != "":
					var back := Iso.to_screen(a["pos"] + (a["face"] as Vector2) * 0.35) if climb else ground
					ci.draw_rect(Rect2(back + Vector2(-7, -3), Vector2(14, 4)), Color(0.8, 0.2, 0.15))
					if climb:
						Sprites.draw_person(ci, "ped_%s_walk" % look, ground, -(a["face"] as Vector2), ph, 6.0)
					else:
						Sprites.draw_person(ci, "ped_%s_walk" % look, ground + Vector2(0, -3), a["face"], 0.0, 0.0)
		"cart":
			if not Sprites.draw_vehicle(ci, "obj_shopping_cart", ground, Vector2.from_angle(float(a["spin"])), Color.WHITE, 0, a):
				ci.draw_rect(Rect2(ground + Vector2(-6, -10), Vector2(12, 8)), Color(0.75, 0.78, 0.82), false, 1.0)
				ci.draw_line(ground + Vector2(-6, -10), ground + Vector2(-9, -14), Color(0.3, 0.3, 0.35), 1.0)
				ci.draw_circle(ground + Vector2(-4, -1), 1.5, Iso.OUTLINE)
				ci.draw_circle(ground + Vector2(4, -1), 1.5, Iso.OUTLINE)
		"gull":
			var up := ground + Vector2(0, -22.0 - sin(ph * 3.0) * 4.0)
			var flip := Iso.to_screen(a["face"]).x < 0.0
			if not Sprites.draw_strip(ci, "animal_seagull_fly", up, ph, 10.0, false, flip):
				Sprites.draw_strip(ci, "animal_town_pigeon_fly", up, ph, 10.0, false, flip, Color(1.6, 1.6, 1.6))
		_:
			super.draw_actor(ci, a)
			return
	if a.get("label_t", 0.0) > 0.0 and a.has("label"):
		city._label(a["label"], ground + Vector2(0, -56 - float(a.get("lift", 0.0))), 8, Color(1.0, 0.95, 0.45))


## A picture we have no art for yet: a simple shape so the happening still reads.
func _draw_stand_in(ci: CanvasItem, a: Dictionary, at: Vector2) -> void:
	match a["name"]:
		"scenery_parade_pizza_balloon":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-22, -40), at + Vector2(22, -40), at + Vector2(0, 0)]), Color(1.0, 0.8, 0.3))
			ci.draw_rect(Rect2(at + Vector2(-23, -46), Vector2(46, 7)), Color(0.75, 0.45, 0.2))
			for k in 4:
				ci.draw_circle(at + Vector2(-10 + k * 7, -30 + (k % 2) * 8), 3.0, Color(0.85, 0.2, 0.15))
		"scenery_hot_air_balloon":
			for k in 5:
				ci.draw_circle(at + Vector2(0, -48), 18.0 - k * 3.0, [Color(1, 0.3, 0.3), Color(1, 0.8, 0.2), Color(0.3, 0.8, 0.4), Color(0.3, 0.5, 1), Color(0.8, 0.4, 1)][k])
			ci.draw_rect(Rect2(at + Vector2(-5, -12), Vector2(10, 8)), Color(0.6, 0.4, 0.2))
		"scenery_christmas_tree_big":
			for k in 4:
				ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-22 + k * 4, -8 - k * 18), at + Vector2(22 - k * 4, -8 - k * 18), at + Vector2(0, -34 - k * 18)]), Color(0.15, 0.5, 0.25))
			ci.draw_rect(Rect2(at + Vector2(-3, -8), Vector2(6, 8)), Color(0.4, 0.25, 0.1))
		"scenery_movie_screen":
			ci.draw_rect(Rect2(at + Vector2(-30, -62), Vector2(60, 36)), Color(0.95, 0.95, 0.95))
			ci.draw_rect(Rect2(at + Vector2(-30, -62), Vector2(60, 36)), Iso.OUTLINE, false, 1.0)
			ci.draw_line(at + Vector2(-24, -26), at + Vector2(-24, 0), Iso.OUTLINE, 2.0)
			ci.draw_line(at + Vector2(24, -26), at + Vector2(24, 0), Iso.OUTLINE, 2.0)
		_:
			Sprites.draw_image(ci, "scenery_haybale", at)


func _draw_ropes(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	var top := ground + Vector2(0, -54)
	for h in e["actors"]:
		if h.has("handler"):
			ci.draw_line(Iso.to_screen(h["pos"]) + Vector2(0, -24), top, Color(0.95, 0.95, 0.9, 0.9), 1.0)


func _draw_suds(ci: CanvasItem, a: Dictionary, ground: Vector2, cpos: Vector2) -> void:
	for k in 10:
		var u := fposmod(float(a["phase"]) * 0.5 + k / 10.0, 1.0)
		var q := ground + Vector2(sin(k * 2.1) * 16.0, -6.0 - u * 18.0)
		ci.draw_circle(q, 1.5 + u * 1.5, Color(1, 1, 1, (1.0 - u) * 0.8))
	ci.draw_circle(ground + Vector2(0, 3), 14.0, Color(0.5, 0.7, 1.0, 0.18))


func _draw_cans(ci: CanvasItem, a: Dictionary, ground: Vector2, car: Dictionary) -> void:
	a["pos"] = car["pos"]
	var back: Vector2 = -(car["face"] as Vector2)
	for k in 4:
		var q := Iso.to_screen((car["pos"] as Vector2) + back * (0.9 + k * 0.18) + Vector2(-back.y, back.x) * (k - 1.5) * 0.12)
		ci.draw_line(Iso.to_screen((car["pos"] as Vector2) + back * 0.6), q, Color(0.8, 0.8, 0.8), 1.0)
		ci.draw_rect(Rect2(q + Vector2(-1, -2 - absf(sin(float(a["phase"]) * 9.0 + k)) * 2.0), Vector2(3, 3)), Color(0.75, 0.78, 0.8))


func _draw_rice(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	if e["stage"] == "drive":
		return
	for k in 24:
		var u := fposmod(float(a["phase"]) * 0.8 + k / 24.0, 1.0)
		var q := ground + Vector2(sin(k * 1.9) * 26.0 * u, -30.0 + u * 34.0 - sin(u * PI) * 12.0)
		ci.draw_rect(Rect2(q.round(), Vector2(1, 1)), Color(1, 1, 1, 1.0 - u * 0.5))


func _draw_apples(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	var t: float = e["apples"]["t"]
	for k in 6:
		var q := ground + Vector2(sin(k * 1.3) * minf(t, 3.0) * 7.0 + k, minf(t, 3.0) * 3.0 * cos(k * 0.9))
		ci.draw_circle(q, 1.8, Color(0.85, 0.15, 0.15))


func _draw_snowballs(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	for b in e["balls"]:
		var t: float = b["t"]
		var from := Iso.to_screen(b["from"]) + Vector2(0, -20)
		var to := Iso.to_screen(b["to"]) + Vector2(0, -14)
		var q := from.lerp(to, t) + Vector2(0, -sin(t * PI) * 22.0)
		ci.draw_circle(q, 2.0, Color(1, 1, 1))
		ci.draw_arc(q, 2.0, 0.0, TAU, 8, Color(0.6, 0.7, 0.85), 1.0)
		if t > 0.9:
			for k in 5:
				ci.draw_rect(Rect2((to + Vector2.from_angle(k * 1.25) * 4.0 * (t - 0.9) * 10.0).round(), Vector2(1, 1)), Color(1, 1, 1))


func _draw_eggs(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	for egg in e["eggs"]:
		var q := Iso.to_screen(egg["pos"])
		var glow := 0.5 + 0.5 * sin(float(a["phase"]) * 4.0 + q.x)
		ci.draw_circle(q + Vector2(0, -3), 6.0, Color(1, 1, 0.8, 0.15 * glow))
		ci.draw_colored_polygon(PackedVector2Array([q + Vector2(-2, -1), q + Vector2(-2, -4), q + Vector2(0, -6), q + Vector2(2, -4), q + Vector2(2, -1), q]), egg["col"])
		ci.draw_rect(Rect2(q + Vector2(-2, -3), Vector2(4, 1)), Color(1, 1, 1, 0.8))


func _draw_ducks(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	var u: float = e.get("u", 0.0)
	var from: Vector2 = e["from"]
	var to: Vector2 = e["to"]
	var facing := 1.0 if Iso.to_screen(to - from).x > 0.0 else -1.0
	for k in 5:
		var q := from.lerp(to, clampf(u - k * 0.05, 0.0, 1.0))
		a["pos"] = from.lerp(to, u)
		Season.duck(ci, Iso.to_screen(q) + Vector2(0, sin(float(a["phase"]) * 8.0 + k) * 0.6), facing, k > 0)
	if int(float(a["phase"]) * 0.7) % 4 == 0:
		city._label("Quack!", Iso.to_screen(from.lerp(to, u)) + Vector2(0, -18), 8, Color(1, 1, 0.7))


func _draw_volley(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	var u := fposmod(float(a["phase"]) * 0.45, 2.0)
	var x := (u if u < 1.0 else 2.0 - u) * 2.0 - 1.0
	var at: Vector2 = e["ball_at"]
	var q := Iso.to_screen(at + Vector2(x * 1.4, 0)) + Vector2(0, -20 - (1.0 - x * x) * 26.0)
	ci.draw_circle(q, 2.5, Color(1, 1, 1))
	ci.draw_arc(q, 2.5, 0.0, TAU, 8, Color(1.0, 0.8, 0.2), 1.0)


func _draw_rod(ci: CanvasItem, a: Dictionary, ground: Vector2, f: Dictionary) -> void:
	a["pos"] = f["pos"]
	var tip := ground + Vector2(10, -34)
	ci.draw_line(ground + Vector2(2, -18), tip, Color(0.4, 0.25, 0.12), 1.0)
	var bob := Iso.to_screen(f["angler"]) + Vector2(0, sin(float(a["phase"]) * 2.5) * 1.2)
	ci.draw_line(tip, bob, Color(0.9, 0.9, 0.9, 0.7), 1.0)
	ci.draw_circle(bob, 1.5, Color(1.0, 0.3, 0.3))


func _draw_pumpkins(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	for k in e["pumpkins"].size():
		Season.pumpkin(ci, Iso.to_screen(e["pumpkins"][k]), 1.2, k * 7)


## The fun run: barriers across both ends of the closed stretch and a finish banner.
func _draw_closure(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	var r: Dictionary = city.roads[e["road"]]
	for end in [-1.0, RUN_LEN + 1.0]:
		var at: Array = city._road_at(r, city._wrap_s(r, float(e["s0"]) + float(e["dir"]) * end))
		var n: Vector2 = (at[1] as Vector2).orthogonal()
		for k in 3:
			var q := Iso.to_screen((at[0] as Vector2) + n * (k - 1) * 0.7)
			ci.draw_line(q + Vector2(-5, 0), q + Vector2(-3, -9), Iso.OUTLINE, 1.0)
			ci.draw_line(q + Vector2(5, 0), q + Vector2(3, -9), Iso.OUTLINE, 1.0)
			ci.draw_rect(Rect2(q + Vector2(-7, -11), Vector2(14, 4)), Color(1.0, 0.5, 0.1))
			ci.draw_rect(Rect2(q + Vector2(-4, -11), Vector2(3, 4)), Color.WHITE)
			ci.draw_rect(Rect2(q + Vector2(2, -11), Vector2(3, 4)), Color.WHITE)
		city._label("ROAD CLOSED", Iso.to_screen(at[0]) + Vector2(0, -20), 8, Color(1.0, 0.6, 0.2))
	var fin: Array = city._road_at(r, city._wrap_s(r, float(e["s0"]) + float(e["dir"]) * RUN_LEN))
	city._draw_line_banner(fin[0], (fin[1] as Vector2) * float(e["dir"]), "FINISH", Color(0.2, 0.5, 0.95))


func _draw_flood(ci: CanvasItem, a: Dictionary, ground: Vector2, e: Dictionary) -> void:
	# the puddle across the road and the fountain from the hydrant
	var pool := Iso.to_screen(e["pool"])
	var pts := PackedVector2Array()
	for k in 16:
		var ang := TAU * k / 16.0
		pts.append(pool + Vector2(cos(ang) * 46.0, sin(ang) * 22.0))
	ci.draw_colored_polygon(pts, Color(0.45, 0.65, 0.95, 0.35))
	for k in 16:
		var u := fposmod(float(a["phase"]) * 1.2 + k / 16.0, 1.0)
		var q := ground + Vector2(0, -8).lerp(pool - ground + Vector2(sin(k * 1.7) * 16.0, 0), u) + Vector2(0, -sin(u * PI) * 26.0)
		ci.draw_rect(Rect2(q.round(), Vector2(2, 2)), Color(0.7, 0.85, 1.0, 0.9))
