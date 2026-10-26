class_name TownEvents
extends RefCounted
## Random happenings around town, set off near the player every so often so there is always something going on: a
## crowd cheering on a corner, a dog that chases you, pigeons that scatter, a marching band, a busker or a mime with
## an audience, an ice-cream or food truck with a queue, a kid chasing a ball across the road, a balloon floating
## away, a cat darting over the road and fire engines, ambulances and police cars racing past with their sirens on.
## There are also critters living in the parks and woods all the time (squirrels, rabbits, hedgehogs, foxes, cats, ...)
## that potter about and bolt when you ride close.
## Bigger happenings come round on their own clocks (see SPECIALS): a soapbox speaker with hecklers, a club group ride,
## a fire with the fire brigade, someone hurt and an ambulance, a robber chased by the police (ride into him to stop
## him), and fireworks once a night.
## Every few minutes the whole Crankmore Marching Band parades round the Plaza Loop (see PARADE): the drum major
## out in front, flags and batons, then the brass, woodwinds and drums, sousaphones at the back, in their own lane,
## with the traffic queueing behind and the townsfolk cheering them on.
## The crew at the Crankmore Heights construction site is always about: walking the site, stopping to work, calling
## out to each other, and cheering when their pizza turns up (the site orders now and then; see City._post_order).
## Each happening is a handful of actors (people, animals, a parked vehicle, a ball or a balloon) that City sorts into
## its drawing like everything else (see actors()). Anything without art is skipped.

const GAP_MIN := 20.0         # seconds between happenings
const GAP_MAX := 40.0
const MAX_LIVE := 2           # happenings going on at once
var near := 7.0               # tiles from the player a happening starts (not under your wheels, but in view)
var far := 15.0
const SIREN_KINDS := ["truck_firetruck", "van_ambulance", "sedan_police"]
const DOGS := ["town_dog_corgi", "town_dog_dalmatian", "town_dog_poodle"]
const BALLOON_COLS := [Color(1.0, 0.3, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.5, 0.9, 0.4), Color(0.95, 0.5, 0.95)]
const CROWD_SHOUTS := ["Go {n}!", "PIZZA!", "Woooo!", "Faster!", "Legend!", "We love you!", "Ring the bell!", "Extra cheese!"]

var city                       # the City node (untyped: City has no class_name)
var events: Array = []         # {kind, t (seconds left), actors: [...], ...}
var next_t := 6.0
var t_ := 0.0
var critters: Array = []
var crew: Array = []          # the construction site's workers (see _step_crew)
const CREW_SIZE := 4
const CREW_LINES := ["*clang* *clang*", "Measure twice!", "Lunch yet?", "Watch your head!", "Hand me that wrench!",
	"Pizza later?", "Easy... easy...", "Who ordered the anchovies?", "Hard hats on!", "BEEP BEEP BEEP"]
var parade_t := randf_range(60.0, 150.0)   # seconds until the band next marches
const PARADE_EVERY := [300.0, 540.0]
const PARADE_SPEED := 0.75     # m/s, a brisk march
const PARADE_LAPS := 2.0
const PARADE_ROW := 0.85       # m between rows
## The band, front to back, one row per line (three across, or one); designs without art are left out.
const PARADE := [
	["band_major"],
	["band_flag", "band_baton", "band_flag"],
	["trumpeter", "trumpeter", "trumpeter"],
	["band_trombone", "band_trombone", "band_trombone"],
	["band_clarinet", "band_sax", "band_clarinet"],
	["drummer", "drummer", "drummer"],
	["band_bass_drum", "band_cymbals", "band_bass_drum"],
	["band_sousaphone", "band_sousaphone", "band_sousaphone"],
]
const PARADE_SHOUTS := ["Go band!", "Woo!", "76 trombones!", "Encore!", "Ba-dum-tss!", "Strike up the band!", "Bravo!"]
const CRITTERS := ["squirrel", "squirrel", "rabbit", "rabbit", "chipmunk", "hedgehog", "raccoon", "skunk", "fox", "town_cat_ginger",
	"town_dog_corgi", "town_pigeon", "town_pigeon", "marmot"]
const CRITTER_COUNT := 18


func _init(c) -> void:
	city = c


func clear() -> void:
	events.clear()
	critters.clear()
	next_t = 6.0


func _spawn_critters() -> void:
	var kinds: Array = CRITTERS.filter(func(k): return _has("animal_%s_idle" % k))
	if kinds.is_empty():
		return
	for _try in 3000:
		if critters.size() >= CRITTER_COUNT:
			break
		var x: int = randi() % int(city.N)
		var y: int = randi() % int(city.N)
		var tile: int = city.tiles[y * city.N + x]
		if city.solid[y * city.N + x] != 0 or (tile != city.T.GRASS and tile != city.T.FOREST):
			continue
		var pos := Vector2(x + randf(), y + randf())
		var kind: String = kinds.pick_random()
		critters.append({"type": "animal", "name": kind, "pos": pos, "home": pos, "face": Vector2(1, 0).rotated(randf() * TAU), "anim": "idle",
			"state": "idle", "wait": randf_range(1.0, 8.0), "phase": randf() * 3.0, "small": true, "lift": 0.0})


func _step_critters(delta: float) -> void:
	var p: Vector2 = city.p_pos
	var riding: bool = city.active and city.er_timer <= 0.0
	for a in critters:
		a["phase"] = float(a["phase"]) + delta
		if a.get("gone", false):
			# a pigeon that flew off comes back to its spot after a while
			a["wait"] -= delta
			if a["wait"] <= 0.0:
				a["gone"] = false
				a["lift"] = 0.0
				a["pos"] = a["home"]
				a["state"] = "idle"
				a["anim"] = "idle"
			continue
		var d: float = p.distance_to(a["pos"])
		if riding and d < 2.6 and a["state"] != "flee":
			a["state"] = "flee"
			a["wait"] = randf_range(1.0, 1.8)
			var away: Vector2 = ((a["pos"] as Vector2) - p).normalized().rotated(randf_range(-0.5, 0.5))
			a["vel"] = away * (2.6 if a["name"] != "town_pigeon" else 2.2)
			a["face"] = away
			a["anim"] = "fly" if a["name"] == "town_pigeon" and _has("animal_town_pigeon_fly") else "run"
		match a["state"]:
			"idle":
				a["wait"] -= delta
				if a["wait"] <= 0.0:
					var to: Vector2 = a["home"] + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
					if _free(to):
						a["to"] = to
						a["state"] = "potter"
						a["anim"] = "run"
					a["wait"] = randf_range(2.0, 9.0)
			"potter":
				var to: Vector2 = a["to"] - a["pos"]
				if to.length() < 0.05:
					a["state"] = "idle"
					a["anim"] = "idle"
				else:
					a["pos"] += to.normalized() * minf(to.length(), 0.9 * delta)
					a["face"] = to.normalized()
			"flee":
				a["wait"] -= delta
				if a["name"] == "town_pigeon":
					a["pos"] += a["vel"] * delta
					a["lift"] = float(a["lift"]) + 60.0 * delta
					if a["lift"] > 200.0:
						a["gone"] = true
						a["wait"] = randf_range(15.0, 30.0)
				else:
					var np: Vector2 = a["pos"] + a["vel"] * delta
					if _free(np):
						a["pos"] = np
					if a["wait"] <= 0.0:
						a["state"] = "idle"
						a["anim"] = "idle"
						a["home"] = a["pos"]
						a["wait"] = randf_range(2.0, 6.0)


## Where the marching band is, for the traffic to stop for (empty when it isn't out).
func parade_spots() -> Array:
	for e in events:
		if e["kind"] == "parade":
			return e["actors"].map(func(a): return a["pos"])
	return []


## Every actor of every happening, to be sorted and drawn with the rest of the town.
func actors() -> Array:
	var out: Array = []
	for a in critters:
		if not a.get("gone", false):
			out.append(a)
	out.append_array(crew)
	for e in events:
		for a in e["actors"]:
			if not a.get("gone", false):
				out.append(a)
	return out


func update(delta: float) -> void:
	t_ += delta
	if critters.is_empty() and t_ < 1.0:
		_spawn_critters()
	_step_critters(delta)
	_step_crew(delta)
	_update_specials(delta)
	parade_t -= delta
	if parade_t <= 0.0 and city.active:
		parade_t = randf_range(PARADE_EVERY[0], PARADE_EVERY[1])
		if not events.any(func(e): return e["kind"] == "parade"):
			_start_parade()
	next_t -= delta
	if next_t <= 0.0 and events.filter(func(e): return e["kind"] != "parade" and e["kind"] != "fireworks" and not SPECIALS.has(e["kind"])).size() < MAX_LIVE and city.active:
		next_t = randf_range(GAP_MIN, GAP_MAX)
		_start(_pick_kind())
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		e["t"] -= delta
		_step(e, delta)
		for a in e["actors"]:
			a["phase"] = float(a.get("phase", 0.0)) + delta
			a["label_t"] = maxf(0.0, float(a.get("label_t", 0.0)) - delta)
		if e["t"] <= 0.0:
			_end(e)
			events.remove_at(i)


func _pick_kind() -> String:
	var kinds := ["crowd", "crowd", "siren", "ball", "balloon", "truck"]
	if _has("animal_%s_run" % DOGS[0]) or _has("animal_%s_run" % DOGS[1]):
		kinds.append_array(["dog", "dog"])
	if _has("animal_town_pigeon_idle"):
		kinds.append_array(["pigeons", "pigeons"])
	if _has("animal_town_cat_ginger_run"):
		kinds.append("cat")
	if _has("ped_drummer_walk") and _has("ped_trumpeter_walk"):
		kinds.append_array(["band", "band"])
	if _has("ped_busker_perform"):
		kinds.append("busker")
	if _has("ped_mime_perform"):
		kinds.append("mime")
	for e in events:   # not two of the same kind at once
		kinds.erase(e["kind"])
	return kinds.pick_random() if not kinds.is_empty() else ""


func _has(sheet: String) -> bool:
	return Sprites.sheet(sheet) != null


# ---------------------------------------------------------------------
# Starting and running each kind
# ---------------------------------------------------------------------

## A spot on a pavement near the player: [pos, road index, s, side, road direction] or [] if none.
func _spot() -> Array:
	var p: Vector2 = city.p_pos
	var cands: Array = []
	for ri in city.roads.size():
		var r: Dictionary = city.roads[ri]
		var s := 0.5
		while s < float(r["len"]) - 0.5:
			var at: Array = city._road_at(r, s)
			var d: float = (at[0] as Vector2).distance_to(p)
			# ahead of you, where you'll see it (or anywhere while you stand still)
			var ahead: bool = city.p_fwd == Vector2.ZERO or ((at[0] as Vector2) - p).dot(city.p_fwd) > d * 0.3
			if d > near and d < far and ahead:
				cands.append([ri, s, at])
			s += 2.0
	for _try in 12:
		if cands.is_empty():
			return []
		var c: Array = cands.pick_random()
		var at: Array = c[2]
		var side := 1.0 if randf() < 0.5 else -1.0
		var n := Vector2(-at[1].y, at[1].x)
		var pos: Vector2 = at[0] + n * side * (city.ROAD_HW + 0.6)
		if _free(pos):
			return [pos, c[0], c[1], side, at[1], at[0]]
	return []


func _free(pos: Vector2) -> bool:
	var ix := int(pos.x)
	var iy := int(pos.y)
	if ix < 0 or iy < 0 or ix >= city.N or iy >= city.N:
		return false
	return city.solid[iy * city.N + ix] == 0 and city.tiles[iy * city.N + ix] != city.T.WATER


func _design() -> String:
	return Sprites.pedestrians().pick_random()


func _person(pos: Vector2, design: String, face: Vector2) -> Dictionary:
	return {"type": "person", "design": design, "pos": pos, "face": face, "anim": "walk", "phase": randf() * 3.0, "moving": false, "label_t": 0.0}


## Starts a happening of `kind` ("crowd", "dog", "pigeons", ...) near the player (also used by the events debug mode).
func start(kind: String) -> void:
	_start(kind)


func _start(kind: String) -> void:
	if kind == "":
		return
	if kind == "siren":
		_start_siren()
		return
	if kind == "parade":
		_start_parade(city.p_pos)
		return
	if kind in ["fireworks", "fire", "crime"]:   # these find their own place
		var e0 := {"kind": kind, "t": 30.0, "actors": []}
		if _start_special(kind, e0, []):
			events.append(e0)
		return
	var sp := _spot()
	if sp.is_empty():
		return
	var pos: Vector2 = sp[0]
	var along: Vector2 = sp[4]
	var across: Vector2 = (sp[5] as Vector2 - pos).normalized()   # from the pavement towards the road
	var e := {"kind": kind, "t": 30.0, "actors": [], "pos": pos, "along": along, "across": across, "road": sp[1], "s": sp[2], "side": sp[3]}
	if SPECIALS.has(kind):
		if _start_special(kind, e, sp):
			events.append(e)
		return
	match kind:
		"crowd":
			# five to eight fans along the kerb, cheering whenever you are close
			e["t"] = 45.0
			for k in randi_range(3, 5):
				var a := _person(pos + along * (k - 2.0) * 0.55 - across * randf_range(0.0, 0.5), _design(), across)
				a["anim"] = "cheer"
				a["fan"] = true
				e["actors"].append(a)
		"dog":
			var dog: String = DOGS.filter(func(d): return _has("animal_%s_run" % d)).pick_random()
			var owner := _person(pos - across * 0.4, "dogwalker" if _has("ped_dogwalker_walk") else _design(), across)
			e["actors"].append(owner)
			e["actors"].append({"type": "animal", "name": dog, "pos": pos + along * 0.7, "home": pos + along * 0.7, "face": along, "anim": "idle", "state": "wait", "phase": 0.0})
			e["t"] = 40.0
		"pigeons":
			for k in randi_range(3, 6):
				var q := pos + along * randf_range(-1.6, 1.6) - across * randf_range(-0.3, 0.6)
				e["actors"].append({"type": "animal", "name": "town_pigeon", "pos": q, "face": along * (1.0 if randf() < 0.5 else -1.0), "anim": "idle",
					"state": "peck", "phase": randf() * 2.0, "lift": 0.0, "small": true})
			e["t"] = 40.0
		"cat":
			# darts across the road in front of you
			var start: Vector2 = pos
			var to: Vector2 = pos + across * (city.ROAD_HW * 2.0 + 1.2)
			e["actors"].append({"type": "animal", "name": "town_cat_ginger", "pos": start, "to": to, "face": across, "anim": "run", "state": "run", "phase": 0.0, "speed": 3.2, "small": true})
			e["t"] = 6.0
		"band":
			# a marching band (drummers and trumpeters) and a few fans following it down the pavement
			e["t"] = 40.0
			e["dir"] = 1.0 if randf() < 0.5 else -1.0
			for k in 4:
				var design := "drummer" if k % 2 == 0 else "trumpeter"
				if k >= 3:
					design = _design()
				var a := _person(pos, design, along * e["dir"])
				a["lane"] = k
				a["moving"] = true
				e["actors"].append(a)
		"busker", "mime":
			e["t"] = 45.0
			var star := _person(pos - across * 0.3, kind, across)
			star["anim"] = "perform"
			e["actors"].append(star)
			for k in randi_range(2, 3):
				var ang := PI * (0.15 + 0.7 * k / 4.0)
				var off := (-across * cos(ang) * 0.0 + along * cos(ang)) * 1.3 + across * sin(ang) * 0.9
				var a := _person(star["pos"] + off, _design(), -off.normalized())
				a["anim"] = "walk"
				a["audience"] = true
				e["actors"].append(a)
		"truck":
			# an ice-cream van (or food truck) parked at the kerb, with a queue
			var kinds: Array = ["truck_icecream", "van_foodtruck", "van_bakery"].filter(func(k): return _has("vehicle_%s" % k))
			if kinds.is_empty():
				return
			e["t"] = 40.0
			var vpos: Vector2 = sp[5] + (pos - sp[5]).normalized() * 0.4
			e["actors"].append({"type": "vehicle", "name": "vehicle_%s" % kinds.pick_random(), "pos": vpos, "face": along, "phase": 0.0})
			e["actors"][0]["label"] = "Ding-a-ling!" if String(e["actors"][0]["name"]).ends_with("icecream") else "Hot food!"
			e["actors"][0]["label_t"] = 3.0
			for k in randi_range(2, 3):
				var a := _person(pos - across * 0.4 + along * (k + 1) * 0.6, _design(), -along)
				a["queue"] = k
				e["actors"].append(a)
		"ball":
			# a ball bounces across the road and a kid runs after it
			var kid := "skater_kid" if _has("ped_skater_kid_walk") else "kid"
			var to: Vector2 = pos + across * (city.ROAD_HW * 2.0 + 1.2)
			e["actors"].append({"type": "ball", "pos": pos, "to": to, "face": across, "phase": 0.0, "speed": 2.4, "col": BALLOON_COLS.pick_random()})
			var a := _person(pos - across * 0.8, kid, across)
			a["moving"] = true
			a["to"] = to - across * 0.2
			a["speed"] = 1.4
			a["delay"] = 0.7
			e["actors"].append(a)
			e["t"] = 9.0
		"balloon":
			var vendor := _person(pos, "balloon_vendor" if _has("ped_balloon_vendor_walk") else _design(), across)
			e["actors"].append(vendor)
			var kid := _person(pos + along * 0.6, "kid", across)
			e["actors"].append(kid)
			e["actors"].append({"type": "balloon", "pos": pos + along * 0.6, "lift": 22.0, "face": across, "phase": 0.0, "col": BALLOON_COLS.pick_random(), "free": false})
			e["t"] = 16.0
	events.append(e)


## A fire engine, ambulance or police car joins the traffic for a while, fast, lights flashing.
func _start_siren() -> void:
	var kinds: Array = SIREN_KINDS.filter(func(k): return _has("vehicle_%s" % k))
	if kinds.is_empty():
		return
	var sp := _spot()
	if sp.is_empty():
		return
	var kind: String = kinds.pick_random()
	var d: Array = city.VEHICLE_DIMS[kind]
	var r: Dictionary = city.roads[sp[1]]
	var c := {"road": sp[1], "s": sp[2], "dir": 1.0 if randf() < 0.5 else -1.0, "speed": 0.0, "max": float(d[3]) * 1.6 * city.PACE,
		"col": Color.WHITE, "kind": kind, "hl": d[0], "hw": d[1], "wait": 0.0, "pos": Vector2.ZERO, "fwd": Vector2.RIGHT, "siren": true}
	c["s"] = clampf(float(c["s"]), 1.0, float(r["len"]) - 1.0)
	city._car_pose(c)
	city.cars.append(c)
	events.append({"kind": "siren", "t": 25.0, "actors": [], "car": c})


## The marching band sets off round the Plaza Loop, in the right-hand lane, starting where the player will see it
## (`near`: the point on the loop closest to it), else anywhere.
## Walking spots for the crew: just outside the construction lot's two near sides, in view.
func _crew_spot(b: Dictionary) -> Vector2:
	var pos: Vector2 = b["pos"]
	var size: Vector2 = b["size"]
	if randf() < 0.5:
		return Vector2(pos.x + size.x + 0.35, pos.y + randf_range(0.3, size.y - 0.2))
	return Vector2(pos.x + randf_range(0.3, size.x - 0.2), pos.y + size.y + 0.35)


func _step_crew(delta: float) -> void:
	var site := -1
	for i in city.buildings.size():
		if city.buildings[i]["kind"] == "site":
			site = i
	if site < 0 or not _has("ped_construction_walk"):
		return
	var b: Dictionary = city.buildings[site]
	if crew.is_empty():
		for k in CREW_SIZE:
			var a := _person(_crew_spot(b), "construction", Vector2(1, 1))
			a["anim"] = "idle"
			a["wait"] = randf_range(0.0, 5.0)
			crew.append(a)
	for a in crew:
		a["phase"] = float(a["phase"]) + delta
		a["label_t"] = maxf(0.0, float(a.get("label_t", 0.0)) - delta)
		if float(a.get("lunch", 0.0)) > 0.0:
			a["lunch"] -= delta
			a["anim"] = "cheer"
			a["moving"] = false
			continue
		if a.get("moving", false):
			var to: Vector2 = a["to"] - a["pos"]
			if to.length() < 0.05:
				a["moving"] = false
				a["anim"] = "idle"
				a["wait"] = randf_range(3.0, 9.0)
			else:
				a["pos"] += to.normalized() * minf(to.length(), 0.6 * delta)
				a["face"] = to.normalized()
				a["anim"] = "walk"
			continue
		a["wait"] = float(a["wait"]) - delta
		if a["wait"] <= 0.0:
			a["to"] = _crew_spot(b)
			a["moving"] = true
		elif a["label_t"] <= 0.0 and randf() < delta * 0.06:
			a["label"] = CREW_LINES.pick_random()
			a["label_t"] = 2.2


## The crew's pizza has arrived: everyone downs tools and cheers.
func crew_lunch() -> void:
	for a in crew:
		a["lunch"] = 4.0
		a["moving"] = false
	if not crew.is_empty():
		crew[0]["label"] = ["PIZZA'S HERE!", "LUNCH BREAK!", "Finally!", "Extra cheese, nice!"].pick_random()
		crew[0]["label_t"] = 3.0


func _start_parade(near_p := Vector2.INF) -> void:
	var rows: Array = []
	for row in PARADE:
		var have: Array = row.filter(func(d): return _has("ped_%s_walk" % d))
		if not have.is_empty():
			rows.append(have)
	if rows.size() < 4:
		return
	var r: Dictionary = city.roads[0]
	var s := randf() * float(r["len"])
	if near_p != Vector2.INF:
		var best := 1e9
		var q := 0.0
		while q < float(r["len"]):
			var d: float = (city._road_at(r, q)[0] as Vector2).distance_to(near_p)
			if d < best:
				best = d
				s = q
			q += 0.5
	var dir := 1.0 if randf() < 0.5 else -1.0
	var e := {"kind": "parade", "t": PARADE_LAPS * float(r["len"]) / PARADE_SPEED, "actors": [], "road": 0, "s": s, "dir": dir}
	for ri in rows.size():
		var row: Array = rows[ri]
		for k in row.size():
			var a := _person(Vector2.ZERO, row[k], Vector2.RIGHT)
			a["row"] = ri
			a["lat"] = 0.55 if row.size() == 1 else 0.2 + 0.35 * k   # across the lane, from the middle line out
			a["moving"] = true
			a["band"] = true
			a["phase"] = 0.0   # in step
			e["actors"].append(a)
	events.append(e)
	_step(e, 0.0)
	Game.toast.emit("The Crankmore Marching Band is parading round the plaza!", Color(1.0, 0.85, 0.35))


func _end(e: Dictionary) -> void:
	if e.has("car") and not (e["car"] as Dictionary).is_empty():
		city.cars.erase(e["car"])


func _step(e: Dictionary, delta: float) -> void:
	if SPECIALS.has(e["kind"]) or e["kind"] == "fireworks":
		_step_special(e, delta)
		return
	var p: Vector2 = city.p_pos
	var riding: bool = city.active and city.er_timer <= 0.0
	match e["kind"]:
		"crowd":
			for a in e["actors"]:
				var near := riding and p.distance_to(a["pos"]) < 6.0
				a["anim"] = "cheer" if near or fmod(t_ + float(a["phase"]), 7.0) < 1.6 else "idle"
				if near and a["label_t"] <= 0.0 and randf() < delta * 0.6:
					a["label"] = String(CROWD_SHOUTS.pick_random()).replace("{n}", Game.player_name)
					a["label_t"] = 1.8
		"dog":
			var dog: Dictionary = e["actors"][1]
			match dog["state"]:
				"wait":
					if riding and p.distance_to(dog["pos"]) < 4.0:
						dog["state"] = "chase"
						dog["chase_t"] = randf_range(5.0, 9.0)
						dog["label"] = "WOOF! WOOF!"
						dog["label_t"] = 1.5
						e["actors"][0]["label"] = ["Rex, NO!", "Come back!", "Bad dog!", "He just wants pizza!"].pick_random()
						e["actors"][0]["label_t"] = 2.0
				"chase":
					dog["chase_t"] -= delta
					var to: Vector2 = p - dog["pos"]
					if to.length() > 0.8:
						dog["pos"] += to.normalized() * minf(to.length(), 3.4 * city.PACE * delta * 2.0)
					dog["face"] = to.normalized() if to.length() > 0.01 else dog["face"]
					dog["anim"] = "run"
					if randf() < delta * 0.5:
						dog["label"] = ["WOOF!", "ARF ARF!", "BARK!", "Yip yip!"].pick_random()
						dog["label_t"] = 1.0
					if dog["chase_t"] <= 0.0 or not riding:
						dog["state"] = "home"
				"home":
					var to: Vector2 = dog["home"] - dog["pos"]
					if to.length() < 0.1:
						dog["state"] = "done"
						dog["anim"] = "idle"
					else:
						dog["pos"] += to.normalized() * minf(to.length(), 1.6 * delta)
						dog["face"] = to.normalized()
						dog["anim"] = "run"
		"pigeons":
			for a in e["actors"]:
				if a["state"] == "peck":
					if riding and p.distance_to(a["pos"]) < 3.2:
						a["state"] = "fly"
						a["vel"] = ((a["pos"] as Vector2) - p).normalized().rotated(randf_range(-0.6, 0.6)) * randf_range(2.0, 3.2)
						a["anim"] = "fly"
						a["face"] = a["vel"]
					elif randf() < delta * 0.3:
						a["face"] = -(a["face"] as Vector2)
				elif a["state"] == "fly":
					a["pos"] += a["vel"] * delta
					a["lift"] = float(a["lift"]) + 40.0 * delta
					if a["lift"] > 260.0:
						a["gone"] = true
		"cat":
			for a in e["actors"]:
				_walk_to(a, delta)
		"parade":
			var r: Dictionary = city.roads[e["road"]]
			e["s"] = city._wrap_s(r, float(e["s"]) + float(e["dir"]) * PARADE_SPEED * delta)
			for a in e["actors"]:
				var s: float = city._wrap_s(r, float(e["s"]) - float(e["dir"]) * float(a["row"]) * PARADE_ROW)
				var at: Array = city._road_at(r, s)
				var f: Vector2 = at[1] * float(e["dir"])
				a["pos"] = at[0] + Vector2(-f.y, f.x) * float(a["lat"])
				a["face"] = f
				a["anim"] = "walk"
			# townsfolk along the way stop and cheer
			var head: Vector2 = e["actors"][0]["pos"]
			for q in city.peds:
				if q["cheer"] <= 0.0 and q["cool"] <= 0.0 and (q["pos"] as Vector2).distance_to(head) < 3.0:
					q["cool"] = randf_range(12.0, 20.0)
					q["cheer"] = 3.0
					q["shout"] = PARADE_SHOUTS.pick_random()
		"band":
			var r: Dictionary = city.roads[e["road"]]
			e["s"] = city._wrap_s(r, float(e["s"]) + float(e["dir"]) * 0.45 * delta)
			for a in e["actors"]:
				var s: float = city._wrap_s(r, float(e["s"]) - float(e["dir"]) * a["lane"] * 0.7)
				var at: Array = city._road_at(r, s)
				var n := Vector2(-at[1].y, at[1].x)
				a["pos"] = at[0] + n * float(e["side"]) * (city.ROAD_HW + 0.6 + 0.35 * float(int(a["lane"]) % 2))
				a["face"] = at[1] * float(e["dir"])
				a["moving"] = true
				a["anim"] = "walk"
				if int(a["lane"]) >= 3 and riding and p.distance_to(a["pos"]) < 5.0:
					a["anim"] = "cheer"
					a["moving"] = false
			if not (city.roads[e["road"]]["closed"]) and (float(e["s"]) < 1.0 or float(e["s"]) > float(r["len"]) - 1.0):
				e["t"] = minf(e["t"], 0.5)
		"busker", "mime":
			var star: Dictionary = e["actors"][0]
			for k in range(1, e["actors"].size()):
				var a: Dictionary = e["actors"][k]
				a["anim"] = "cheer" if fmod(t_ + float(a["phase"]), 6.0) < 1.2 else "idle"
			if riding and p.distance_to(star["pos"]) < 5.0 and star["label_t"] <= 0.0 and randf() < delta * 0.4:
				star["label"] = ("Tips welcome!" if e["kind"] == "busker" else "...") if randf() < 0.5 else ("Ta-daa!" if e["kind"] == "busker" else "(waves silently)")
				star["label_t"] = 2.0
		"truck":
			for k in range(1, e["actors"].size()):
				var a: Dictionary = e["actors"][k]
				a["anim"] = "cheer" if fmod(t_ + k * 1.7, 9.0) < 1.0 else "idle"
		"ball":
			_walk_to(e["actors"][0], delta)
			var kid: Dictionary = e["actors"][1]
			kid["delay"] = float(kid["delay"]) - delta
			if kid["delay"] <= 0.0:
				_walk_to(kid, delta)
				if kid["label_t"] <= 0.0 and kid.get("said", false) == false:
					kid["said"] = true
					kid["label"] = "My ball!"
					kid["label_t"] = 1.6
		"balloon":
			var b: Dictionary = e["actors"][2]
			if not b["free"] and e["t"] < 12.0:
				b["free"] = true
				e["actors"][1]["label"] = "My balloon!"
				e["actors"][1]["label_t"] = 2.0
				e["actors"][1]["anim"] = "cheer"
			if b["free"]:
				b["lift"] = float(b["lift"]) + 26.0 * delta
				b["pos"] += Vector2(0.25, -0.25) * delta
				if b["lift"] > 400.0:
					b["gone"] = true


## Moves an actor with a "to" and a "speed" towards it; it stops (idle) when it gets there.
func _walk_to(a: Dictionary, delta: float) -> void:
	if not a.has("to"):
		return
	var to: Vector2 = a["to"] - a["pos"]
	if to.length() < 0.05:
		a["moving"] = false
		if a["type"] == "animal":
			a["gone"] = true
		elif a["type"] == "person":
			a["anim"] = "idle"
		return
	a["pos"] += to.normalized() * minf(to.length(), float(a["speed"]) * delta)
	a["face"] = to.normalized()
	a["moving"] = true


# ---------------------------------------------------------------------
# Drawing (City calls this with itself as the canvas)
# ---------------------------------------------------------------------

func draw_actor(ci: CanvasItem, a: Dictionary) -> void:
	var ground := Iso.to_screen(a["pos"])
	var ph: float = a["phase"]
	match a["type"]:
		"person":
			ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-5, 0), ground + Vector2(0, -2.5), ground + Vector2(5, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
			var d: String = a["design"]
			var anim: String = a["anim"]
			ground.y -= float(a.get("lift", 0.0))   # standing on a soapbox
			if a.get("down", false):
				# lying on the pavement: the standing sprite turned on its side
				ci.draw_set_transform(ground + Vector2(14, -3), -PI * 0.5, Vector2.ONE)
				Sprites.draw_person(ci, "ped_%s_walk" % d, Vector2.ZERO, Vector2(1, 1), 0.0, 0.0)
				ci.draw_set_transform(Vector2.ZERO)
			elif anim == "run":
				if not Sprites.draw_person(ci, "ped_%s_run" % d, ground, a["face"], ph, 12.0):
					Sprites.draw_person(ci, "ped_%s_walk" % d, ground, a["face"], ph, 14.0)
			elif anim == "walk" and a.get("moving", false):
				Sprites.draw_person(ci, "ped_%s_walk" % d, ground, a["face"], ph, float(a.get("fps", 8.0)))
			elif anim == "cheer" or anim == "perform":
				if anim == "cheer" or not Sprites.draw_strip(ci, "ped_%s_perform" % d, ground, ph, 10.0):
					Sprites.draw_cheer(ci, "ped_%s_cheer" % d, ground, ph)
			else:   # standing about: shifting their weight now and then
				Sprites.draw_person(ci, "ped_%s_walk" % d, ground + Vector2(0, -1 if int(ph * 1.3) % 3 == 0 else 0), a["face"], 0.0, 0.0)
			if (d == "drummer" or d == "trumpeter" or d.begins_with("band_") or anim == "perform") and int(ph * 3.0 + float(a.get("row", 0)) * 0.5) % 2 == 0:
				_note(ci, ground + Vector2(10, -46 - fmod(ph * 20.0, 14.0)))
			if a.has("spray_to"):
				# the hose: an arc of water from the nozzle to the flames
				var from := ground + Vector2(0, -18)
				var to := Iso.to_screen(a["spray_to"], float(a["spray_h"]))
				for k in 14:
					var u := fposmod(k / 14.0 + ph * 1.8, 1.0)
					var q := from.lerp(to, u) + Vector2(0, -sin(u * PI) * 26.0)
					ci.draw_rect(Rect2(q.round(), Vector2(2, 2)), Color(0.65, 0.85, 1.0, 0.85))
		"crate":
			# a wooden soapbox
			ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-8, 0), ground + Vector2(0, 4), ground + Vector2(8, 0), ground + Vector2(0, -4)]), Color(0, 0, 0, 0.25))
			ci.draw_rect(Rect2(ground + Vector2(-7, -8), Vector2(14, 8)), Color(0.55, 0.36, 0.2))
			ci.draw_rect(Rect2(ground + Vector2(-7, -9), Vector2(14, 2)), Color(0.72, 0.5, 0.3))
			ci.draw_rect(Rect2(ground + Vector2(-7, -8), Vector2(14, 8)), Iso.OUTLINE, false, 1.0)
			ci.draw_line(ground + Vector2(-6, -4), ground + Vector2(6, -4), Color(0.4, 0.25, 0.14), 1.0)
		"rider":
			ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-7, 0), ground + Vector2(0, -3), ground + Vector2(7, 0), ground + Vector2(0, 3)]), Color(0, 0, 0, 0.2))
			Sprites.draw_rider(ci, ground, a["face"], a["pedal"], false, a["who"], false)
		"fire":
			_draw_fire(ci, a, ground, ph)
		"animal":
			var flip := Iso.to_screen(a["face"]).x < 0.0
			var lift: float = a.get("lift", 0.0)
			if lift <= 0.0:
				ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-6, 0), ground + Vector2(0, -2.5), ground + Vector2(6, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
			var name := "animal_%s_%s" % [a["name"], a["anim"]]
			if not Sprites.draw_strip(ci, name, ground + Vector2(0, -lift), ph, 12.0 if a["anim"] == "run" else 8.0, true, flip):
				Sprites.draw_strip(ci, "animal_%s_idle" % a["name"], ground + Vector2(0, -lift), ph, 8.0, true, flip)
		"vehicle":
			Sprites.draw_vehicle(ci, a["name"], ground, a["face"], Color.WHITE, int(ph * 6.0))
		"ball":
			var hop := absf(sin(ph * 9.0)) * 7.0
			ci.draw_circle(ground, 2.5, Color(0, 0, 0, 0.25))
			ci.draw_circle(ground + Vector2(0, -3 - hop), 3.0, Iso.OUTLINE)
			ci.draw_circle(ground + Vector2(0, -3 - hop), 2.2, a["col"])
			ci.draw_rect(Rect2(ground + Vector2(-1, -5 - hop), Vector2(1, 1)), Color(1, 1, 1))
		"balloon":
			var lift: float = a["lift"]
			var top := ground + Vector2(sin(ph * 1.7) * 3.0, -26.0 - lift)
			ci.draw_line(ground + Vector2(0, -22.0 - (lift - 22.0 if a["free"] else 0.0)), top + Vector2(0, 6), Color(0.9, 0.9, 0.9), 1.0)
			ci.draw_circle(top, 5.0, Iso.OUTLINE)
			ci.draw_circle(top, 4.2, a["col"])
			ci.draw_rect(Rect2(top + Vector2(-2, -3), Vector2(1, 2)), Color(1, 1, 1, 0.8))
	if a.get("label_t", 0.0) > 0.0 and a.has("label"):
		city._label(a["label"], ground + Vector2(0, -56 - float(a.get("lift", 0.0))), 8, Color(1.0, 0.95, 0.45))


## Flames on a roof (shrinking as `power` drops) and a column of smoke (fading with `smoke` once it's out).
func _draw_fire(ci: CanvasItem, a: Dictionary, ground: Vector2, ph: float) -> void:
	var top := ground + Vector2(0, -float(a["h"]))
	var pw: float = a["power"]
	var smoke: float = float(a.get("smoke", 1.0))
	for k in 7:
		var u := fposmod(ph * 0.35 + k / 7.0, 1.0)
		var sp := top + Vector2(sin(k * 1.7 + ph) * 6.0 + u * 14.0, -10.0 - u * 70.0)
		var g := 0.25 + 0.2 * pw
		ci.draw_circle(sp, 5.0 + u * 10.0, Color(g, g, g + 0.03, (1.0 - u) * 0.55 * maxf(pw, smoke * 0.6)))
	if pw <= 0.0:
		return
	for k in 6:
		var flick := absf(sin(ph * 9.0 + k * 2.1))
		var off := Vector2((k - 2.5) * 8.0, absf(k - 2.5) * 2.0)
		var hgt := (16.0 + flick * 16.0) * pw
		ci.draw_colored_polygon(PackedVector2Array([top + off + Vector2(-7 * pw, 2), top + off + Vector2(0, -hgt), top + off + Vector2(7 * pw, 2)]), Color(0.95, 0.25, 0.08, 0.95))
		ci.draw_colored_polygon(PackedVector2Array([top + off + Vector2(-4.5 * pw, 2), top + off + Vector2(0, -hgt * 0.75), top + off + Vector2(4.5 * pw, 2)]), Color(1.0, 0.6, 0.15, 0.95))
		ci.draw_colored_polygon(PackedVector2Array([top + off + Vector2(-2 * pw, 2), top + off + Vector2(0, -hgt * 0.4), top + off + Vector2(2 * pw, 2)]), Color(1.0, 0.95, 0.5))


static func _note(ci: CanvasItem, at: Vector2) -> void:
	ci.draw_line(at, at + Vector2(0, -6), Iso.OUTLINE, 1.0)
	ci.draw_circle(at + Vector2(-1, 0), 1.8, Iso.OUTLINE)
	ci.draw_line(at + Vector2(0, -6), at + Vector2(3, -4), Iso.OUTLINE, 1.0)


## Flashing red and blue lights on a vehicle with its siren on, and the odd WEE-OO.
static func draw_siren(ci: CanvasItem, c: Dictionary, at: Vector2, t: float) -> void:
	var on := int(t * 8.0) % 2 == 0
	var top := at + Vector2(0, -24)
	ci.draw_circle(top + Vector2(-4, 0), 3.5 if on else 2.0, Color(1.0, 0.15, 0.15, 0.9 if on else 0.5))
	ci.draw_circle(top + Vector2(4, 0), 2.0 if on else 3.5, Color(0.2, 0.45, 1.0, 0.5 if on else 0.9))
	ci.draw_circle(top + Vector2(-4 if on else 4, 0), 9.0, Color(1.0, 0.3, 0.3, 0.15) if on else Color(0.3, 0.5, 1.0, 0.15))
	if fmod(t + float(c["s"]), 3.0) < 1.0:
		var font := ThemeDB.fallback_font
		ci.draw_string_outline(font, top + Vector2(-30, -10), "WEE-OO!", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 8, 3, Iso.OUTLINE)
		ci.draw_string(font, top + Vector2(-30, -10), "WEE-OO!", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 8, Color(1.0, 0.9, 0.3))


# ---------------------------------------------------------------------
# The bigger happenings, each on its own clock (SPECIALS): a soapbox speaker, a club group ride, a fire, an
# ambulance call-out and a robbery, plus fireworks once a night.
# ---------------------------------------------------------------------

const SPECIALS := {"soapbox": [120.0, 240.0], "group_ride": [150.0, 300.0], "fire": [360.0, 600.0],
	"ambulance": [300.0, 540.0], "crime": [240.0, 480.0]}
var special_t := {}             # kind -> seconds until it next happens
var fw_wait := -1.0             # seconds into the night until the fireworks (-1: not tonight yet)
var fw_done := false            # had tonight's show

const SOAPBOX_TOPICS := [
	["Pineapple belongs on pizza!", "It's sweet! It's savoury!", "Wake up, Crankmore!", "The Hawaiian is the people's pizza!"],
	["Flatten Mt. Crankmore!", "Why climb when you could... not?", "A mountain is just a hill with an ego!", "Bulldozers now!"],
	["Bike lanes for all!", "Two wheels good!", "Cars are just very heavy shoes!", "Ring your bells, citizens!"],
	["The gondola is watching us!", "Why does it go up AND down?", "Who controls the cables?", "Open your eyes!"],
	["Vote Marmot for mayor!", "He sleeps all winter! Like a true leader!", "No promises! No problems!", "Marmot 2026!"],
	["Free cheese is a human right!", "Mozzarella for the masses!", "They hoard the parmesan!", "Grate it! Share it!"],
	["Repent! Ski season is nigh!", "The lifts are coming!", "Wax your skis!", "The end... of summer!"],
]
const HECKLES := ["Hear, hear!", "Boo!", "Preach!", "Get off the box!", "Says who?", "Ha!", "Louder!", "Tell 'em!", "Who let him up there?"]
const RIDE_LINES := ["On your left!", "Car back!", "Hold your line!", "Nice pull!", "Coffee stop?", "Who's on the front?",
	"Easy on the climb!", "Hole!", "Sprint to the sign!", "Is that the pizza kid?"]
const FW_COLS := [Color(1.0, 0.3, 0.35), Color(0.35, 0.65, 1.0), Color(1.0, 0.85, 0.3), Color(0.45, 1.0, 0.5),
	Color(0.95, 0.5, 1.0), Color(1.0, 1.0, 1.0)]
const FW_CROWD := ["Ooooh!", "Aaaah!", "Pretty!", "BOOM!", "Whoa!", "Did you see that one?!", "Encore!"]
const CLUB := ["Carl", "Sarah", "Carla", "Wanda", "Gus", "Maya", "Tony", "Kim"]


func _update_specials(delta: float) -> void:
	if not city.active:
		return
	for k in SPECIALS:
		if not special_t.has(k):
			special_t[k] = randf_range(30.0, float(SPECIALS[k][0]))
		special_t[k] -= delta
		if special_t[k] <= 0.0:
			special_t[k] = randf_range(SPECIALS[k][0], SPECIALS[k][1])
			if not events.any(func(e): return e["kind"] == k):
				_start(k)
	# fireworks: once a night, a while after it gets properly dark
	var dark := Skies.dark()
	if dark < 0.2:
		fw_done = false
		fw_wait = -1.0
	elif dark > 0.75 and not fw_done:
		if fw_wait < 0.0:
			fw_wait = randf_range(20.0, 240.0)
		fw_wait -= delta
		if fw_wait <= 0.0:
			fw_done = true
			_start("fireworks")


## An emergency vehicle (one of `kinds`) on its way to `park_s` on `road`, lights flashing; it stops there, pulled
## over onto the kerb. {} when there's no art.
func _responder(kinds: Array, road: int, park_s: float) -> Dictionary:
	var have: Array = kinds.filter(func(k): return _has("vehicle_%s" % k))
	if have.is_empty() or road < 0:
		return {}
	var kind: String = have.pick_random()
	var d: Array = city.VEHICLE_DIMS[kind]
	var r: Dictionary = city.roads[road]
	var length: float = r["len"]
	# come from whichever end has more room, ~14 m back
	var dir := 1.0 if r["closed"] or park_s > length * 0.5 else -1.0
	var s: float = city._wrap_s(r, park_s - dir * 14.0) if r["closed"] else clampf(park_s - dir * 14.0, 0.5, length - 0.5)
	var c := {"road": road, "s": s, "dir": dir, "speed": 0.0, "max": float(d[3]) * 1.5 * city.PACE, "col": Color.WHITE, "kind": kind,
		"hl": d[0], "hw": d[1], "wait": 0.0, "pos": Vector2.ZERO, "fwd": Vector2.RIGHT, "siren": true, "park_s": park_s, "last_j": -1}
	city._car_pose(c)
	city.cars.append(c)
	return c


func _parked(c: Dictionary) -> bool:
	return not c.is_empty() and float(c.get("pull", 0.0)) > 0.95 and float(c["speed"]) < 0.05


## The vehicle drives off again (lights off) and the event wraps up a little later, once it's out of sight.
func _drive_off(e: Dictionary) -> void:
	var c: Dictionary = e.get("car", {})
	if not c.is_empty():
		c.erase("park_s")
		c["siren"] = false
	e["t"] = minf(float(e["t"]), 12.0)


## The pavement beside a road at `s` on its `side`: [position, direction along the road].
func _kerb(road: int, s: float, side: float) -> Array:
	var r: Dictionary = city.roads[road]
	var at: Array = city._road_at(r, city._wrap_s(r, s))
	var t: Vector2 = at[1]
	return [at[0] + Vector2(-t.y, t.x) * side * (city.ROAD_HW + 0.6), t]


## Which side of its road a building's door is on (+1 / -1).
func _door_side(b: Dictionary) -> float:
	var at: Array = city._road_at(city.roads[b["road"]], float(b["s"]))
	var t: Vector2 = at[1]
	return signf(Vector2(-t.y, t.x).dot(Vector2(b["door"]) - Vector2(at[0])))


## A building of one of `kinds` in view of the player (not right on top of them), or {}.
func _building_near(kinds: Array) -> Dictionary:
	var p: Vector2 = city.p_pos
	var cands: Array = city.buildings.filter(func(b): return b["kind"] in kinds and int(b.get("road", -1)) >= 0 \
		and (b["door"] as Vector2).distance_to(p) > 3.0 and (b["door"] as Vector2).distance_to(p) < 9.0)
	return {} if cands.is_empty() else cands.pick_random()


func _say(a: Dictionary, text: String, t := 2.2) -> void:
	a["label"] = text
	a["label_t"] = t


func _start_special(kind: String, e: Dictionary, sp: Array) -> bool:
	var pos: Vector2 = sp[0] if not sp.is_empty() else Vector2.ZERO
	match kind:
		"fireworks":
			# set off just in front of you, so the bursts fill the sky over your head
			var p: Vector2 = city.p_pos
			var at: Vector2 = p + city.p_fwd * 3.0 + Vector2(1.5, 1.5)
			e["at"] = at
			e["base"] = Iso.to_screen(at, Iso.ground_z(at))
			e["shells"] = []
			e["sparks"] = []
			e["bursts"] = []
			e["next"] = 0.6
			e["t"] = 75.0
			for k in 6:
				var a := randf() * TAU
				var q: Vector2 = (p if p.distance_to(at) < 12.0 else at) + Vector2(cos(a), sin(a)) * randf_range(2.0, 4.0)
				if _free(q):
					var fan := _person(q, _design(), Vector2(1, -1).normalized())
					fan["anim"] = "idle"
					e["actors"].append(fan)
			Game.toast.emit("Fireworks over Crankmore!", Color(1.0, 0.75, 0.95))
		"soapbox":
			var across: Vector2 = (sp[5] as Vector2 - pos).normalized()
			var along: Vector2 = sp[4]
			e["t"] = 50.0
			e["topic"] = SOAPBOX_TOPICS.pick_random()
			e["line"] = 0
			e["next"] = 0.5
			e["actors"].append({"type": "crate", "pos": pos, "phase": 0.0, "label_t": 0.0})
			var speaker := _person(pos + Vector2(0.01, 0.01), ["grandpa", "lady", "hiker", "norm_man_suit_casual", "grunge_teen", "mullet_dad"].filter(func(d): return _has("ped_%s_walk" % d)).pick_random(), across)
			speaker["anim"] = "idle"
			speaker["lift"] = 7.0
			speaker["speaker"] = true
			e["actors"].append(speaker)
			for k in randi_range(3, 4):
				var off: Vector2 = along * (1.0 if k % 2 == 0 else -1.0) * (0.9 + 0.5 * float(k / 2)) - across * randf_range(0.0, 0.4)
				var a := _person(pos + off, _design(), -off.normalized())
				a["anim"] = "idle"
				e["actors"].append(a)
		"group_ride":
			var lead := {"road": sp[1], "s": sp[2], "dir": 1.0 if randf() < 0.5 else -1.0, "speed": 2.0, "max": 3.0, "col": Color.WHITE,
				"kind": "car", "hl": 0.45, "hw": 0.3, "wait": 0.0, "pos": Vector2.ZERO, "fwd": Vector2.RIGHT, "hidden": true, "last_j": -1}
			city._car_pose(lead)
			city.cars.append(lead)
			e["car"] = lead
			e["trail"] = [[lead["pos"], lead["fwd"]]]
			e["t"] = 45.0
			var have: Array = CLUB.filter(func(n): return Sprites.sheet("bike_" + n.to_lower()) != null)
			var free_: Array = have.filter(func(n): return not Talk.rivals.any(func(rv): return str(rv["short"]) == n))
			var names: Array = free_ if free_.size() >= 3 else have
			if names.is_empty():
				return false
			names.shuffle()
			for k in randi_range(6, 9):
				e["actors"].append({"type": "rider", "who": names[k % names.size()], "k": k, "pos": lead["pos"], "face": lead["fwd"],
					"phase": 0.0, "pedal": randf() * TAU, "label_t": 0.0})
			Game.toast.emit("Group ride! The Crankmore Wheelers are out.", Color(0.6, 0.9, 1.0))
		"fire":
			var b := _building_near(["shop", "chalet", "condo", "hotel"])
			if b.is_empty():
				return false
			e["b"] = b
			e["t"] = 120.0
			e["stage"] = "burning"
			var center: Vector2 = b["pos"] + b["size"] * 0.5
			e["actors"].append({"type": "fire", "pos": center + Vector2(0.05, 0.05), "h": float(b["h"]) + float(b["roof_h"]) * 0.6, "power": 1.0, "phase": 0.0, "label_t": 0.0})
			var side := _door_side(b)
			var witness := _person((b["door"] as Vector2) + (_kerb(b["road"], float(b["s"]) + 1.2, side)[0] - (b["door"] as Vector2)) * 0.5, _design(), (center - (b["door"] as Vector2)).normalized())
			witness["anim"] = "idle"
			_say(witness, "FIRE! FIRE!", 3.0)
			e["actors"].append(witness)
			e["car"] = _responder(["truck_firetruck"], b["road"], float(b["s"]))
			Game.toast.emit("Smoke over %s! The fire brigade is on its way." % str(b.get("name", "town")), Color(1.0, 0.55, 0.3))
		"ambulance":
			e["t"] = 90.0
			e["stage"] = "down"
			var patient := _person(pos, _design(), sp[4])
			patient["anim"] = "idle"
			patient["down"] = true
			_say(patient, ["Ow! My ankle!", "I'm fine... I'm not fine.", "Too much pizza...", "Did anyone get that bike's number?"].pick_random(), 3.0)
			e["actors"].append(patient)
			var helper := _person(pos + (sp[4] as Vector2) * 0.8, _design(), -(sp[4] as Vector2))
			helper["anim"] = "idle"
			_say(helper, "Someone call an ambulance!", 3.0)
			e["actors"].append(helper)
			e["car"] = _responder(["van_ambulance"], sp[1], float(sp[2]))
		"crime":
			var b := _building_near(["shop"])
			if b.is_empty():
				return false
			var side := _door_side(b)
			var dir := 1.0 if randf() < 0.5 else -1.0
			e["t"] = 80.0
			e["stage"] = "run"
			e["road"] = b["road"]
			e["side"] = side
			e["dir"] = dir
			e["rs"] = float(b["s"])            # where the robber is along the road
			e["cs"] = float(b["s"]) - dir * 4.0  # and the cop
			var keeper := _person(b["door"], ["barista", "baker", "lady", "norm_woman_office"].filter(func(d): return _has("ped_%s_walk" % d)).pick_random(), Vector2(1, 1))
			keeper["anim"] = "cheer"
			_say(keeper, "STOP, THIEF!", 4.0)
			e["actors"].append(keeper)
			var robber := _person(b["door"], "robber" if _has("ped_robber_walk") else "grunge_teen", Vector2(1, 0))
			robber["robber"] = true
			robber["fps"] = 14.0
			robber["moving"] = true
			e["actors"].append(robber)
			var cop := _person(_kerb(b["road"], e["cs"], side)[0], "police", Vector2(1, 0))
			cop["cop"] = true
			cop["fps"] = 14.0
			cop["moving"] = true
			_say(cop, "Halt! Police!", 2.5)
			e["actors"].append(cop)
			Game.toast.emit("Robbery at %s! Stop that thief!" % str(b.get("name", "the shop")), Color(1.0, 0.45, 0.45))
	return true


func _step_special(e: Dictionary, delta: float) -> void:
	var p: Vector2 = city.p_pos
	var riding: bool = city.active and city.er_timer <= 0.0
	match e["kind"]:
		"fireworks":
			_step_fireworks(e, delta)
			for a in e["actors"]:
				if a["label_t"] <= 0.0 and randf() < delta * 0.25:
					_say(a, FW_CROWD.pick_random(), 1.6)
					a["anim"] = "cheer" if randf() < 0.5 else "idle"
		"soapbox":
			e["next"] -= delta
			var speaker: Dictionary = e["actors"][1]
			if e["next"] <= 0.0:
				e["next"] = 3.6
				var lines: Array = e["topic"]
				if riding and p.distance_to(speaker["pos"]) < 5.0 and not e.get("hailed", false):
					e["hailed"] = true
					_say(speaker, "YOU! Pizza rider! Join the cause!", 3.0)
				else:
					_say(speaker, lines[int(e["line"]) % lines.size()], 3.2)
					e["line"] = int(e["line"]) + 1
			for k in range(2, e["actors"].size()):
				var a: Dictionary = e["actors"][k]
				if a["label_t"] <= 0.0 and randf() < delta * 0.12:
					_say(a, HECKLES.pick_random(), 1.8)
					a["anim"] = "cheer" if randf() < 0.4 else "idle"
				elif a["label_t"] <= 0.0:
					a["anim"] = "idle"
		"group_ride":
			_step_ride(e, delta)
		"fire":
			_step_fire(e, delta)
		"ambulance":
			_step_ambulance(e, delta)
		"crime":
			_step_crime(e, delta, p, riding)


func _step_fireworks(e: Dictionary, delta: float) -> void:
	var base: Vector2 = e["base"]
	e["next"] -= delta
	if e["next"] <= 0.0 and e["t"] > 4.0:
		var finale: bool = e["t"] < 14.0
		e["next"] = randf_range(0.1, 0.3) if finale else randf_range(0.5, 1.5)
		e["shells"].append({"pos": base + Vector2(randf_range(-50.0, 50.0), -4.0), "vel": Vector2(randf_range(-18.0, 18.0), -randf_range(115.0, 145.0)),
			"fuse": randf_range(0.8, 1.1), "col": FW_COLS.pick_random(), "type": ["peony", "peony", "ring", "willow"].pick_random()})
	for sh in e["shells"]:
		sh["pos"] += sh["vel"] * delta
		sh["vel"].y += 60.0 * delta
		sh["fuse"] -= delta
		if sh["fuse"] <= 0.0:
			var n := 40 if sh["type"] != "willow" else 55
			for k in n:
				var a: float = TAU * k / n if sh["type"] == "ring" else randf() * TAU
				var v: float = 95.0 if sh["type"] == "ring" else randf_range(25.0, 110.0) if sh["type"] == "peony" else randf_range(40.0, 75.0)
				var willow: bool = sh["type"] == "willow"
				e["sparks"].append({"pos": sh["pos"], "vel": Vector2(cos(a), sin(a) * 0.8) * v, "life": 2.6 if willow else 1.5,
					"life0": 2.6 if willow else 1.5, "col": Color(1.0, 0.8, 0.35) if willow else sh["col"], "g": 55.0 if willow else 30.0})
			e["bursts"].append({"pos": sh["pos"], "t": 0.0, "col": sh["col"]})
	e["shells"] = e["shells"].filter(func(sh): return sh["fuse"] > 0.0)
	for sp in e["sparks"]:
		sp["pos"] += sp["vel"] * delta
		sp["vel"] *= 1.0 - 1.4 * delta
		sp["vel"].y += float(sp["g"]) * delta
		sp["life"] -= delta
	e["sparks"] = e["sparks"].filter(func(sp): return sp["life"] > 0.0)
	for bu in e["bursts"]:
		bu["t"] += delta
	e["bursts"] = e["bursts"].filter(func(bu): return bu["t"] < 0.7)


func _step_ride(e: Dictionary, delta: float) -> void:
	var lead: Dictionary = e["car"]
	var trail: Array = e["trail"]
	if (trail[-1][0] as Vector2).distance_to(lead["pos"]) > 0.12:
		trail.append([lead["pos"], lead["fwd"]])
		if trail.size() > 160:
			trail.pop_front()
	for a in e["actors"]:
		# two by two behind the (invisible) lead line, each pair ~0.9 m behind the one in front
		var back := 0.5 + float(int(a["k"]) / 2) * 0.9
		var i := trail.size() - 1
		var run := 0.0
		while i > 0 and run < back:
			run += (trail[i][0] as Vector2).distance_to(trail[i - 1][0])
			i -= 1
		var f: Vector2 = trail[i][1]
		a["pos"] = (trail[i][0] as Vector2) + Vector2(-f.y, f.x) * (0.12 if int(a["k"]) % 2 == 0 else -0.22)
		a["face"] = f
		a["pedal"] = float(a["pedal"]) + float(lead["speed"]) * delta * 2.6
		if a["label_t"] <= 0.0 and randf() < delta * 0.03:
			_say(a, RIDE_LINES.pick_random(), 1.8)


func _step_fire(e: Dictionary, delta: float) -> void:
	var b: Dictionary = e["b"]
	var fire: Dictionary = e["actors"][0]
	var truck: Dictionary = e.get("car", {})
	var center: Vector2 = b["pos"] + b["size"] * 0.5
	match e["stage"]:
		"burning":
			if truck.is_empty():
				fire["power"] = maxf(0.0, float(fire["power"]) - delta * 0.03)   # no truck art: it burns itself out
				if fire["power"] <= 0.0:
					e["stage"] = "out"
					e["t"] = 8.0
			elif _parked(truck):
				e["stage"] = "spray"
				for k in 2:
					var ff := _person(truck["pos"], "firefighter" if _has("ped_firefighter_walk") else "construction", Vector2(1, 1))
					ff["to"] = (b["door"] as Vector2) + (truck["pos"] - (b["door"] as Vector2)) * 0.35 + Vector2(k * 0.5 - 0.25, 0.25 - k * 0.5)
					ff["speed"] = 1.2
					ff["moving"] = true
					ff["firefighter"] = true
					e["actors"].append(ff)
				_say(e["actors"][1], "Over here!", 2.0)
		"spray":
			var spraying := false
			for a in e["actors"]:
				if a.get("firefighter", false):
					_walk_to(a, delta)
					if not a.get("moving", false):
						a["face"] = (center - (a["pos"] as Vector2)).normalized()
						a["spray_to"] = center
						a["spray_h"] = fire["h"]
						spraying = true
			if spraying:
				fire["power"] = maxf(0.0, float(fire["power"]) - delta * 0.07)
			if fire["power"] <= 0.0:
				e["stage"] = "out"
				for a in e["actors"]:
					if a.get("firefighter", false):
						a.erase("spray_to")
						a["to"] = truck["pos"]
						a["moving"] = true
				_say(e["actors"][1], "Thank you, Crankmore FD!", 3.0)
				e["actors"][1]["anim"] = "cheer"
		"out":
			fire["smoke"] = maxf(0.0, float(fire.get("smoke", 1.0)) - delta * 0.2)
			var back := true
			for a in e["actors"]:
				if a.get("firefighter", false):
					_walk_to(a, delta)
					if a.get("moving", false):
						back = false
					else:
						a["gone"] = true
			if back and not e.get("leaving", false):
				e["leaving"] = true
				_drive_off(e)


func _step_ambulance(e: Dictionary, delta: float) -> void:
	var van: Dictionary = e.get("car", {})
	var patient: Dictionary = e["actors"][0]
	match e["stage"]:
		"down":
			if van.is_empty():
				e["stage"] = "up"
				e["clock"] = 4.0
			elif _parked(van):
				e["stage"] = "treat"
				e["clock"] = 7.0
				for k in 2:
					var m := _person(van["pos"], "paramedic" if _has("ped_paramedic_walk") else "nurse", Vector2(1, 1))
					m["to"] = (patient["pos"] as Vector2) + Vector2(0.5 - k, -0.4 + k * 0.8) * 0.6
					m["speed"] = 1.4
					m["moving"] = true
					m["medic"] = true
					e["actors"].append(m)
		"treat":
			var there := true
			for a in e["actors"]:
				if a.get("medic", false):
					_walk_to(a, delta)
					if a.get("moving", false):
						there = false
					else:
						a["face"] = ((patient["pos"] as Vector2) - (a["pos"] as Vector2)).normalized()
			if there:
				if not e.get("said", false):
					e["said"] = true
					var medics: Array = e["actors"].filter(func(a): return a.get("medic", false))
					_say(medics[0], ["Let's take a look.", "Where does it hurt?", "Just a sprain!"].pick_random(), 2.5)
				e["clock"] -= delta
				if e["clock"] <= 0.0:
					e["stage"] = "up"
					e["clock"] = 2.0
					patient["down"] = false
					_say(patient, ["Thanks, doc!", "I feel great!", "Can I still get pizza?"].pick_random(), 2.5)
		"up":
			e["clock"] -= delta
			if e["clock"] <= 0.0:
				e["stage"] = "board"
				for a in e["actors"]:
					if a.get("medic", false) or a == patient:
						a["to"] = van["pos"] if not van.is_empty() else (a["pos"] as Vector2) + Vector2(2, 0)
						a["speed"] = 1.0
						a["moving"] = true
		"board":
			var aboard := true
			for a in e["actors"]:
				if a.has("to") and not a.get("gone", false):
					_walk_to(a, delta)
					if a.get("moving", false):
						aboard = false
					else:
						a["gone"] = true
			if aboard and not e.get("leaving", false):
				e["leaving"] = true
				_drive_off(e)


func _step_crime(e: Dictionary, delta: float, p: Vector2, riding: bool) -> void:
	var r: Dictionary = city.roads[e["road"]]
	var robber: Dictionary = e["actors"][1]
	var cop: Dictionary = e["actors"][2]
	var dir: float = e["dir"]
	var side: float = e["side"]
	match e["stage"]:
		"run":
			var rs: float = float(e["rs"]) + dir * 1.45 * delta
			if not r["closed"]:
				rs = clampf(rs, 0.5, float(r["len"]) - 0.5)
			e["rs"] = rs
			e["cs"] = float(e["cs"]) + dir * 1.75 * delta
			# the robber dashes from the door to the pavement, then down it
			var k: Array = _kerb(e["road"], rs, side)
			robber["pos"] = (robber["pos"] as Vector2).move_toward(k[0], 2.5 * delta) if (robber["pos"] as Vector2).distance_to(k[0]) > 0.3 else k[0]
			robber["face"] = (k[1] as Vector2) * dir
			robber["anim"] = "run"
			var kc: Array = _kerb(e["road"], e["cs"], side)
			cop["pos"] = kc[0]
			cop["face"] = (kc[1] as Vector2) * dir
			cop["anim"] = "walk"
			if robber["label_t"] <= 0.0 and randf() < delta * 0.5:
				_say(robber, ["Ha ha!", "You'll never catch me!", "Out of my way!", "Five-finger discount!"].pick_random(), 1.6)
			var gap: float = (float(e["rs"]) - float(e["cs"])) * dir
			if r["closed"]:
				gap = fposmod(gap, float(r["len"]))
			if riding and p.distance_to(robber["pos"]) < 0.8:
				# you rode right into him
				Game.add_money(25)
				Game.toast.emit("You stopped the thief! Reward: $25", Color(0.4, 1.0, 0.5))
				_say(robber, "Foiled by a pizza courier!", 2.8)
				e["stage"] = "caught"
			elif gap < 0.5:
				e["stage"] = "caught"
				_say(cop, ["BUSTED!", "Gotcha!", "You're nicked!"].pick_random(), 2.5)
				_say(robber, ["It was like that when I got here!", "I want my lawyer!", "Aw, nuts."].pick_random(), 2.8)
			if e["stage"] == "caught":
				robber["anim"] = "idle"
				robber["moving"] = false
				e["car"] = _responder(["sedan_police"], e["road"], float(e["rs"]))
				e["clock"] = 4.0
		"caught":
			# the cop catches up and holds on to him until the police car comes
			var near: Vector2 = (robber["pos"] as Vector2) - (robber["face"] as Vector2) * 0.45
			cop["pos"] = (cop["pos"] as Vector2).move_toward(near, 1.75 * delta)
			cop["moving"] = (cop["pos"] as Vector2).distance_to(near) > 0.05
			cop["anim"] = "walk" if cop["moving"] else "idle"
			robber["anim"] = "idle"
			var car: Dictionary = e.get("car", {})
			e["clock"] -= delta
			if (car.is_empty() and e["clock"] <= 0.0) or _parked(car):
				e["stage"] = "board"
				for a in [robber, cop]:
					a["to"] = car["pos"] if not car.is_empty() else (a["pos"] as Vector2) + (a["face"] as Vector2) * 2.0
					a["speed"] = 1.0
					a["moving"] = true
					a["fps"] = 8.0
		"board":
			var aboard := true
			for a in [robber, cop]:
				if a.get("gone", false):
					continue
				_walk_to(a, delta)
				if a.get("moving", false):
					aboard = false
				else:
					a["gone"] = true
			if aboard and not e.get("leaving", false):
				e["leaving"] = true
				e["actors"][0]["anim"] = "idle"
				_drive_off(e)


## The group riders (traffic gives them room like the band).
func ride_spots() -> Array:
	var out: Array = []
	for e in events:
		if e["kind"] == "group_ride":
			for a in e["actors"]:
				out.append(a["pos"])
	return out


## Light from the fireworks bursts on the ground, and the group riders' bike lights, for the night (see night.gd).
func flash_lights() -> Array:
	var out: Array = []
	for e in events:
		if e["kind"] == "fireworks":
			var base: Vector2 = e["base"]
			for bu in e["bursts"]:
				out.append([Vector2(bu["pos"].x, base.y), 150.0, (1.0 - float(bu["t"]) / 0.7) * 0.9])
		elif e["kind"] == "fire" and float(e["actors"][0]["power"]) > 0.0:
			# the blaze lights up the street (and the roof it's on)
			var f: Dictionary = e["actors"][0]
			var flick := 0.85 + 0.15 * sin(t_ * 13.0)
			out.append([Iso.to_screen(f["pos"]), 110.0, float(f["power"]) * flick])
			out.append([Iso.to_screen(f["pos"], float(f["h"])), 40.0, float(f["power"])])
		elif e["kind"] == "group_ride" and Skies.dark() > 0.4:
			for a in e["actors"]:
				out.append([Iso.to_screen((a["pos"] as Vector2) + (a["face"] as Vector2) * 0.6), 18.0, 0.5])
	return out


## The fireworks themselves, drawn over the dark (sky_fx.gd calls this with the world's canvas transform set).
func draw_sky(ci: CanvasItem) -> void:
	for e in events:
		if e["kind"] != "fireworks":
			continue
		for bu in e["bursts"]:
			var k: float = 1.0 - float(bu["t"]) / 0.7
			ci.draw_circle(bu["pos"], 40.0 * (1.0 - k * 0.5), Color(bu["col"].r, bu["col"].g, bu["col"].b, 0.12 * k))
		for sh in e["shells"]:
			var q: Vector2 = sh["pos"]
			ci.draw_line(q, q - (sh["vel"] as Vector2) * 0.06, Color(1.0, 0.85, 0.6, 0.6), 1.0)
			ci.draw_rect(Rect2(q.round() - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.95, 0.8))
		for sp in e["sparks"]:
			var a: float = clampf(float(sp["life"]) / float(sp["life0"]), 0.0, 1.0)
			var c: Color = sp["col"]
			# twinkle as they fade
			if a < 0.35 and randf() < 0.4:
				continue
			ci.draw_rect(Rect2((sp["pos"] as Vector2).round(), Vector2(2, 2)), Color(c.r, c.g, c.b, a))
			ci.draw_rect(Rect2(((sp["pos"] as Vector2) - (sp["vel"] as Vector2) * 0.05).round(), Vector2(1, 1)), Color(c.r, c.g, c.b, a * 0.5))
