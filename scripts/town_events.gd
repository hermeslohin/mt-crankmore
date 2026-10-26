class_name TownEvents
extends RefCounted
## Random happenings around town, set off near the player every so often so there is always something going on: a
## crowd cheering on a corner, a dog that chases you, pigeons that scatter, a marching band, a busker or a mime with
## an audience, an ice-cream or food truck with a queue, a kid chasing a ball across the road, a balloon floating
## away, a cat darting over the road and fire engines, ambulances and police cars racing past with their sirens on.
## There are also critters living in the parks and woods all the time (squirrels, rabbits, hedgehogs, foxes, cats, ...)
## that potter about and bolt when you ride close.
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


## Every actor of every happening, to be sorted and drawn with the rest of the town.
func actors() -> Array:
	var out: Array = []
	for a in critters:
		if not a.get("gone", false):
			out.append(a)
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
	next_t -= delta
	if next_t <= 0.0 and events.size() < MAX_LIVE and city.active:
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
			if d > near and d < far:
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
	return {"type": "person", "design": design, "pos": pos, "face": face, "anim": "walk", "phase": randf() * 3.0, "moving": false}


## Starts a happening of `kind` ("crowd", "dog", "pigeons", ...) near the player (also used by the events debug mode).
func start(kind: String) -> void:
	_start(kind)


func _start(kind: String) -> void:
	if kind == "":
		return
	if kind == "siren":
		_start_siren()
		return
	var sp := _spot()
	if sp.is_empty():
		return
	var pos: Vector2 = sp[0]
	var along: Vector2 = sp[4]
	var across: Vector2 = (sp[5] as Vector2 - pos).normalized()   # from the pavement towards the road
	var e := {"kind": kind, "t": 30.0, "actors": [], "pos": pos, "along": along, "across": across, "road": sp[1], "s": sp[2], "side": sp[3]}
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


func _end(e: Dictionary) -> void:
	if e["kind"] == "siren":
		city.cars.erase(e["car"])


func _step(e: Dictionary, delta: float) -> void:
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
			if anim == "walk" and a.get("moving", false):
				Sprites.draw_person(ci, "ped_%s_walk" % d, ground, a["face"], ph, 8.0)
			elif anim == "cheer" or anim == "perform":
				if not Sprites.draw_strip(ci, "ped_%s_%s" % [d, anim], ground, ph, 10.0):
					Sprites.draw_strip(ci, "ped_%s_cheer" % d, ground, ph, 10.0)
			else:
				Sprites.draw_person(ci, "ped_%s_walk" % d, ground, a["face"], 0.0, 0.0)
			if (d == "drummer" or d == "trumpeter" or anim == "perform") and int(ph * 3.0) % 2 == 0:
				_note(ci, ground + Vector2(10, -46 - fmod(ph * 20.0, 14.0)))
		"animal":
			var flip := Iso.to_screen(a["face"]).x < 0.0
			var lift: float = a.get("lift", 0.0)
			if lift <= 0.0:
				ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-6, 0), ground + Vector2(0, -2.5), ground + Vector2(6, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
			var name := "animal_%s_%s" % [a["name"], a["anim"]]
			if not Sprites.draw_strip(ci, name, ground + Vector2(0, -lift), ph, 12.0 if a["anim"] == "run" else 8.0, true, flip):
				Sprites.draw_strip(ci, "animal_%s_idle" % a["name"], ground + Vector2(0, -lift), ph, 8.0, true, flip)
		"vehicle":
			Sprites.draw_vehicle(ci, a["name"], ground, a["face"])
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
