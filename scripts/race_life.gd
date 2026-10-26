class_name RaceLife
extends RefCounted
## The race-day dressing of the mountain and the things that move with the race:
##   * sponsor tents, bunting, crowd barriers and a crowd at the start and the finish;
##   * a crowd and a marshal inside every hairpin, hay bales round the outside;
##   * cowbell fans, flag wavers and sign holders lining the steep ramps, photographers by the jumps;
##   * a feed zone with helpers holding out bottles, camper vans and portaloos where the fans camp;
##   * a devil superfan who runs alongside you up one of the climbs;
##   * a TV moto and a marshal moto ahead of the leader, a team car behind the last rider, a TV helicopter overhead;
##   * a mountain cog railway straight down the hillside, with level crossings and a train that comes by now and then.
## Static things go into the race's statics (drawn by Race._draw_deco); the moving ones come from movers() each frame.

const RACE_FANS := ["fan_sign", "fan_flag", "fan_cowbell", "fan_highfive_kid"]
const FAN_SHOUTS := ["ALLEZ!", "GO GO GO!", "Dig deep!", "Venga!", "Allez allez!", "You got this!", "Hup hup!", "Pedal!"]
const TRAIN_SPEED := 4.5      # tiles per second
const TRAIN_GAP := 2.6        # tiles between the cars
const TRAIN_CYCLE := 75.0     # seconds between trains

var race                       # the Race node
var rail_x := -1.0             # world x of the railway (-1 = none)
var rail_y0 := 0.0
var rail_y1 := 0.0
var crossings: Array = []      # {s, y}: where the railway crosses the road
var devil := {}                # {s0, s1, side}
var t_ := 0.0


func _init(r) -> void:
	race = r


func build(rng: RandomNumberGenerator) -> void:
	var length: float = race.course["length"]
	_build_start_finish(rng, length)
	_build_hairpins(rng)
	_build_ramps(rng, length)
	_build_feed_zone(rng, length)
	_build_camps(rng, length)
	_build_devil(rng, length)
	_build_railway(rng, length)


func _fan_design(rng: RandomNumberGenerator) -> String:
	var peds: Array = Sprites.pedestrians()
	if rng.randf() < 0.45:
		var have: Array = RACE_FANS.filter(func(d): return Sprites.sheet("ped_%s_cheer" % d) != null)
		if not have.is_empty():
			return have[rng.randi() % have.size()]
	return peds[rng.randi() % peds.size()]


func _sprite(name: String, s: float, lat: float, flip := false) -> void:
	if Sprites.sheet(name) == null:
		return
	var p: Vector2 = race._pose(s, lat)["pos"]
	race._put_static(2, {"kind": "sprite", "name": name, "pos": p, "z": race._tz(p), "flip": flip}, [])


func _fan(s: float, lat: float, rng: RandomNumberGenerator, design := "") -> void:
	var p: Vector2 = race._pose(s, lat)["pos"]
	race._put_static(2, {"kind": "fan", "s": s, "pos": p, "z": race._tz(p), "design": design if design != "" else _fan_design(rng),
		"col": Color.from_hsv(rng.randf(), 0.7, 0.95)}, [])


func _build_start_finish(rng: RandomNumberGenerator, length: float) -> void:
	var tents := ["race_sponsor_tent_red", "race_sponsor_tent_blue", "race_sponsor_tent_yellow"]
	for end in [0, 1]:
		var base := 12.0 if end == 0 else length - 12.0
		var dir := 1.0 if end == 0 else -1.0
		for k in 3:
			_sprite(tents[(k + end) % 3], base + dir * k * 14.0, (3.4 if k % 2 == 0 else -3.6), k % 2 == 1)
		_sprite("race_bunting_flags", base - dir * 6.0, 2.3)
		_sprite("race_bunting_flags", base - dir * 6.0, -2.3, true)
		var s := base - dir * 12.0
		for k in 8:
			_sprite("race_crowd_barrier", s + dir * k * 4.0, 1.45)
			_sprite("race_crowd_barrier", s + dir * k * 4.0, -1.45, true)
			if k % 2 == 0:
				_fan(s + dir * k * 4.0 + 1.0, 2.1, rng)
				_fan(s + dir * k * 4.0 + 2.0, -2.1, rng)
	_fan(30.0, 1.2, rng, "fan_highfive_kid")
	_fan(length - 40.0, -1.2, rng, "fan_highfive_kid")


func _build_hairpins(rng: RandomNumberGenerator) -> void:
	for h in race.hairpins:
		if float(h["s"]) > float(race.course["length"]):
			continue
		var c: Vector2 = h["c"]
		var dx: float = h["dx"]
		for fr in [0.26, 0.42, 0.58, 0.74]:   # hay bales round the outside, between the chevrons
			var a: float = PI * fr
			var p: Vector2 = c + Vector2(sin(a) * dx, cos(a)) * (race.HAIRPIN_R + 0.95)
			if Sprites.sheet("race_hay_bale_barrier") != null:
				race._put_static(2, {"kind": "sprite", "name": "race_hay_bale_barrier", "pos": p, "z": race._tz(p), "flip": rng.randf() < 0.5}, [])
		# the crowd packs the inside of the bend, with a marshal at the apex
		for k in rng.randi_range(4, 7):
			var a: float = PI * rng.randf_range(0.15, 0.85)
			var p: Vector2 = c + Vector2(sin(a) * dx, cos(a)) * (race.HAIRPIN_R - rng.randf_range(1.3, 2.6))
			race._put_static(2, {"kind": "fan", "s": float(h["s"]), "pos": p, "z": race._tz(p), "design": _fan_design(rng), "col": Color.WHITE}, [])
		var m: Vector2 = c + Vector2(dx, 0.0) * (race.HAIRPIN_R - 1.1)
		race._put_static(2, {"kind": "fan", "s": float(h["s"]), "pos": m, "z": race._tz(m), "design": "marshal_flag", "col": Color.WHITE}, [])


func _build_ramps(rng: RandomNumberGenerator, length: float) -> void:
	for r in race.ramps:
		if not r["up"]:
			continue
		var s: float = r["s0"]
		while s < float(r["s1"]) and s < length - 30.0:
			if not race._in_tunnel(s, 6.0):
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				_fan(s, side * rng.randf_range(1.3, 1.9), rng, ["fan_cowbell", "fan_flag", "fan_sign", ""][rng.randi() % 4])
				if rng.randf() < 0.4:
					_sprite("race_cowbell_post", s + 2.0, -side * 1.6)
			s += rng.randf_range(10.0, 18.0)
	for ob in race.obstacles:
		if ob["kind"] == "jump":
			_fan(float(ob["s"]) + 7.0, 1.4, rng, "photographer_kneel")


func _build_feed_zone(rng: RandomNumberGenerator, length: float) -> void:
	var s := length * 0.5
	for _try in 40:
		if race._grade_at(s) < 0.035 and race._clear_of(s, 30.0):
			break
		s = length * rng.randf_range(0.35, 0.65)
	_sprite("race_water_table", s, 2.1)
	for k in 3:
		_fan(s - 6.0 + k * 6.0, 1.25, rng, "feed_helper")
	race._put_static(2, {"kind": "board", "s": s - 60.0, "icon": "up", "l1": "FEED", "l2": "ZONE", "side": 1.0}, [])


func _build_camps(rng: RandomNumberGenerator, length: float) -> void:
	for k in 4:
		var s := length * (0.15 + 0.2 * k) + rng.randf_range(-40.0, 40.0)
		if race._in_tunnel(s, 20.0):
			continue
		var side := 1.0 if k % 2 == 0 else -1.0
		_sprite("race_campervan_fans", s, side * 3.8, side < 0.0)
		_sprite("race_portaloo", s + 7.0, side * 3.2)
		_fan(s - 3.0, side * 2.2, rng)
		_fan(s + 2.0, side * 2.0, rng)


func _build_devil(rng: RandomNumberGenerator, length: float) -> void:
	devil = {}
	if Sprites.sheet("ped_fan_devil_walk") == null:
		return
	var best: Dictionary = {}
	for r in race.ramps:
		if r["up"] and float(r["s0"]) > 300.0 and float(r["s0"]) < length - 300.0 and (best.is_empty() or float(r["s1"]) - float(r["s0"]) > float(best["s1"]) - float(best["s0"])):
			best = r
	var s0: float = best["s0"] if not best.is_empty() else length * rng.randf_range(0.4, 0.6)
	devil = {"s0": s0 - 20.0, "s1": s0 + 140.0, "side": -1.0 if rng.randf() < 0.5 else 1.0}


# ---------------------------------------------------------------------
# The railway
# ---------------------------------------------------------------------

func _build_railway(rng: RandomNumberGenerator, length: float) -> void:
	rail_x = -1.0
	crossings.clear()
	if race.course.get("flowers", false):
		return
	rail_y0 = float(race.oy) + 3.0
	rail_y1 = float(race.oy + race.gh) - 3.0
	for f in [0.62, 0.38, 0.74, 0.26, 0.5]:
		var x: float = race.leg_len * float(f)
		var found: Array = []
		var ok := true
		for i in race.M - 1:
			var a: Vector2 = race.pts[i]
			var b: Vector2 = race.pts[i + 1]
			if race.road_leg[i] < 0 or (a.x - x) * (b.x - x) > 0.0:
				continue
			var s: float = race.s_m[i]
			if race._in_tunnel(s, 25.0) or race._near_ford(s, 25.0) or race._stream_d(x, a.y) < 3.0:
				ok = false
				break
			found.append({"s": s, "y": a.y, "lat": 0.0})
		if ok and not found.is_empty():
			rail_x = x
			crossings = found
			break
	if rail_x < 0.0:
		return
	for c in crossings:
		var s: float = c["s"]
		if s < length:
			for side in [-1.0, 1.0]:
				var p: Vector2 = Vector2(rail_x + side * 1.0, float(c["y"]) + side * 1.25)
				race._put_static(2, {"kind": "crossing", "pos": p, "z": race._tz(p), "c": c}, [])
			race._put_static(2, {"kind": "board", "s": s - 80.0, "icon": "train", "l1": "RAILWAY", "l2": "CROSSING", "side": 1.0}, [])
	# a little halt half way up
	var sy: float = lerpf(rail_y0, rail_y1, 0.45)
	var sp := Vector2(rail_x + 2.2, sy)
	if race._rd(sp) > 3.0 and Sprites.sheet("race_rail_station") != null:
		race._put_static(2, {"kind": "sprite", "name": "race_rail_station", "pos": sp, "z": race._tz(sp), "flip": false}, [])


## Where the front of the train is (world y), or -1 when no train is out.
func train_y() -> float:
	if rail_x < 0.0:
		return -1.0
	var u := fposmod(t_, TRAIN_CYCLE)
	var run := (rail_y1 - rail_y0 + TRAIN_GAP * 3.0) / TRAIN_SPEED
	if u > run:
		return -1.0
	return rail_y0 + u * TRAIN_SPEED


## True while a train is close to the crossing at `y`: the lights flash.
func crossing_live(y: float) -> bool:
	var ty := train_y()
	return ty >= 0.0 and ty > y - 7.0 and ty - TRAIN_GAP * 3.0 < y + 2.0


## The railway on the ground: sleepers and two rails, drawn after the road so it crosses over it.
func draw_rails(ci: CanvasItem, vr: Rect2) -> void:
	if rail_x < 0.0:
		return
	var y := rail_y0
	var sleeper := Color(0.36, 0.25, 0.16)
	var rail := Color(0.62, 0.64, 0.7)
	var prev_l := Vector2.ZERO
	var prev_r := Vector2.ZERO
	while y <= rail_y1:
		var zl: float = race._tz(Vector2(rail_x, y)) + 1.0
		var a := Iso.to_screen(Vector2(rail_x - 0.5, y), zl)
		if vr.grow(80.0).has_point(a):
			var b := Iso.to_screen(Vector2(rail_x + 0.5, y), zl)
			ci.draw_line(a, b, Iso.OUTLINE, 4.0)
			ci.draw_line(a, b, sleeper, 2.0)
			var l := Iso.to_screen(Vector2(rail_x - 0.28, y), zl + 1.0)
			var r := Iso.to_screen(Vector2(rail_x + 0.28, y), zl + 1.0)
			if prev_l != Vector2.ZERO:
				ci.draw_line(prev_l, l, rail, 1.5)
				ci.draw_line(prev_r, r, rail, 1.5)
			prev_l = l
			prev_r = r
		else:
			prev_l = Vector2.ZERO
		y += 0.45


# ---------------------------------------------------------------------
# Moving things
# ---------------------------------------------------------------------

func update(delta: float) -> void:
	t_ += delta


## [world position, draw callable] for everything that moves this frame.
func movers() -> Array:
	var out: Array = []
	if race.riders.is_empty():
		return out
	var length: float = race.course["length"]
	var me: Dictionary = race.riders[0]
	var lead := 0.0
	var last := 1e9
	for r in race.riders:
		lead = maxf(lead, float(r["s"]))
		last = minf(last, float(r["s"]))
	# the motos ahead of the leader, the team car behind the last rider
	if lead < length - 20.0:
		_add_vehicle(out, "vehicle_tv_moto", lead + 9.0, -0.5)
		_add_vehicle(out, "vehicle_marshal_moto", lead + 22.0, 0.45)
	if last > 20.0 and last < length:
		_add_vehicle(out, "vehicle_team_car", last - 13.0, -0.35)
	# the devil
	if not devil.is_empty():
		var s: float = me["s"]
		var lat: float = 1.6 * float(devil["side"])
		var running: bool = s > float(devil["s0"]) and s < float(devil["s1"]) and race.countdown <= 0.0
		var ds: float = clampf(s + 2.4, float(devil["s0"]), float(devil["s1"])) if running else (float(devil["s0"]) if s <= float(devil["s0"]) else float(devil["s1"]))
		var pz: Dictionary = race._pose(ds, lat)
		out.append([pz["pos"], _draw_devil.bind(pz, running)])
	# the train
	var ty := train_y()
	if ty >= 0.0:
		for k in 3:
			var y := ty - k * TRAIN_GAP
			if y < rail_y0 or y > rail_y1:
				continue
			var p := Vector2(rail_x, y)
			out.append([p, _draw_train_car.bind(p, k == 0)])
	return out


func _add_vehicle(out: Array, name: String, s: float, lat: float) -> void:
	if Sprites.sheet(name) == null:
		return
	var pz: Dictionary = race._pose(s, lat)
	out.append([pz["pos"], _draw_vehicle.bind(name, pz)])


func _draw_vehicle(name: String, pz: Dictionary) -> void:
	var n: Vector2 = pz["n"]
	var along := Vector2(-n.y, n.x)
	var at := Iso.to_screen(pz["pos"], pz["z"] + 1.5)
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-12, 0), at + Vector2(0, -5), at + Vector2(12, 0), at + Vector2(0, 5)]), Color(0, 0, 0, 0.2))
	Sprites.draw_vehicle(race, name, at + Vector2(0, -1 if int(t_ * 8.0) % 2 == 0 else 0), along, Color.WHITE, int(t_ * 8.0))


func _draw_devil(pz: Dictionary, running: bool) -> void:
	var at := Iso.to_screen(pz["pos"], pz["z"])
	var n: Vector2 = pz["n"]
	if running:
		Sprites.draw_person(race, "ped_fan_devil_walk", at, Vector2(-n.y, n.x), t_, 12.0)
		if int(t_ * 1.5) % 3 == 0:
			_shout(at + Vector2(0, -58), ["ALLEZ ALLEZ!", "GO GO GO!", "DIG DEEP!", "FASTER!"][int(t_ / 2.0) % 4], Color(1.0, 0.35, 0.3))
	else:
		Sprites.draw_strip(race, "ped_fan_devil_cheer", at, t_, 10.0)


func _draw_train_car(p: Vector2, loco: bool) -> void:
	var at := Iso.to_screen(p, race._tz(p) + 2.0)
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-20, 0), at + Vector2(0, -9), at + Vector2(20, 0), at + Vector2(0, 9)]), Color(0, 0, 0, 0.22))
	Sprites.draw_vehicle(race, "obj_train_loco" if loco else "obj_train_carriage", at + Vector2(0, -6), Vector2(0, 1))
	if loco and int(t_ * 2.0) % 4 == 0:
		_shout(at + Vector2(0, -60), "TOOT TOOT!", Color(1.0, 0.95, 0.5))


## The flashing lights on a level crossing (drawn by Race._draw_deco with the crossing sign).
func draw_crossing(ci: CanvasItem, e: Dictionary) -> void:
	var at := Iso.to_screen(e["pos"], e["z"])
	if not Sprites.draw_image(ci, "race_rail_crossing", at):
		ci.draw_line(at, at + Vector2(0, -26), Iso.OUTLINE, 2.0)
	if crossing_live(float(e["c"]["y"])):
		var on := int(t_ * 4.0) % 2 == 0
		ci.draw_circle(at + Vector2(-4, -22), 3.0 if on else 2.0, Color(1.0, 0.15, 0.1, 1.0 if on else 0.4))
		ci.draw_circle(at + Vector2(4, -22), 2.0 if on else 3.0, Color(1.0, 0.15, 0.1, 0.4 if on else 1.0))
		if on:
			_shout(at + Vector2(0, -40), "DING DING", Color(1.0, 0.85, 0.3))


## A TV helicopter hanging over the leader, rotor flickering.
func draw_helicopter(ci: CanvasItem) -> void:
	if race.riders.is_empty() or Sprites.sheet("race_helicopter_tv") == null:
		return
	var lead: Dictionary = race.riders[0]
	for r in race.riders:
		if float(r["s"]) > float(lead["s"]):
			lead = r
	if float(lead["s"]) > float(race.course["length"]):
		return
	var pz: Dictionary = race._pose(float(lead["s"]) + 6.0, -3.0)
	var at := Iso.to_screen(pz["pos"], pz["z"]) + Vector2(sin(t_ * 0.7) * 20.0, -170.0 + sin(t_ * 1.3) * 6.0)
	Sprites.draw_image(ci, "race_helicopter_tv", at, false, 1.0, 0.8)
	var w := 34.0 if int(t_ * 20.0) % 2 == 0 else 26.0
	ci.draw_line(at + Vector2(-w, -44), at + Vector2(w, -44), Color(0.15, 0.15, 0.2, 0.6), 1.0)


func _shout(at: Vector2, text: String, col: Color) -> void:
	var font: Font = race.font
	race.draw_string_outline(font, at + Vector2(-50, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 9, 4, Iso.OUTLINE)
	race.draw_string(font, at + Vector2(-50, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 9, col)
