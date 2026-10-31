class_name RaceLife
extends RefCounted
## The race-day dressing of the mountain and the things that move with the race:
##   * sponsor tents, bunting, crowd barriers and a crowd at the start and the finish;
##   * a crowd and a marshal inside every hairpin, hay bales round the outside;
##   * cowbell fans, flag wavers and sign holders lining the steep ramps, photographers by the jumps;
##   * a feed zone with helpers holding out bottles, camper vans and portaloos where the fans camp;
##   * a devil superfan who runs alongside you up one of the climbs, and roadside fans who chase after you for a few
##     seconds as you go by, then stop, cheer and walk back to their spot;
##   * a TV moto and a marshal moto ahead of the leader, a team car behind the last rider, the Channel 9 news helicopter
##     following the race (you or the leader), and now and then St. Pedro's air ambulance flying over;
##   * drone pilots at the roadside: as you go by, their camera drone takes off and follows you for a while, then flies
##     back and lands by them;
##   * a mountain cog railway straight down the hillside, with level crossings and a train that comes by now and then;
##   * up in the snow, a ski area: skiers and snowboarders carving down, a ski school snake, ski patrol, chairlifts with
##     its chairs going round, the lodge, a cocoa stand, racks, slalom gates, a snowcat grooming and a snowmobile.
## Static things go into the race's statics (drawn by Race._draw_deco); the moving ones come from movers() each frame.

const RACE_FANS := ["fan_sign", "fan_flag", "fan_cowbell", "fan_highfive_kid"]
const FAN_SHOUTS := ["ALLEZ!", "GO GO GO!", "Dig deep!", "Venga!", "Allez allez!", "You got this!", "Hup hup!", "Pedal!"]
const RUN_CHANCE := 0.35      # share of the roadside fans who run along with you as you go by
const RUN_MAX := 6.8          # m/s: a fan flat out
const RUN_LAT := 1.7          # tiles from the middle of the road they run at, just off the gravel (plus Race.ROAD_GROW)
const NO_RUN := ["photographer_kneel", "feed_helper"]   # busy: they stay put
const MedHeli := preload("res://scripts/med_heli.gd")
const NewsHeli := preload("res://scripts/news_heli.gd")
const NEWS_ALT := 165.0       # px the news helicopter hovers over the riders
const NEWS_SWITCH := [20.0, 40.0]   # seconds on one rider before it goes to film the other (you / the leader)
const DRONE_SPOTS := 3        # drone pilots along a course
const DRONE_ALT := 46.0       # px up while it follows you
const DRONE_FOLLOW := [12.0, 18.0]   # seconds it keeps up with you
const DRONE_SPEED := 9.0      # tiles a second, flying back
const FLYOVER_EVERY := [90.0, 240.0]   # seconds between the air ambulance flying over
const FLYOVER_SPEED := 9.0    # tiles a second
const FLYOVER_ALT := 190.0    # px up
const FLYOVER_HALF := 34.0    # tiles: it comes in from this far off to one side of you and goes as far off the other
const TRAIN_SPEED := 4.5      # tiles per second
const TRAIN_GAP := 2.6        # tiles between the cars
const TRAIN_CYCLE := 75.0     # seconds between trains

var race                       # the Race node
var rail_x := -1.0             # world x of the railway (-1 = none)
var rail_y0 := 0.0
var rail_y1 := 0.0
var crossings: Array = []      # {s, y}: where the railway crosses the road
var devil := {}                # {s0, s1, side}
var news                       # the news helicopter (NewsHeli)
var news_on := 0               # who it's filming: 0 you, 1 the leader
var news_t := 0.0              # seconds until it switches
var pilots: Array = []         # drone pilots: {s, lat, pos, drone: {state, pos, alt, dir, t, turn}}
var flyover := {}              # the air ambulance on its way over: {pos, dir, left}
var flyover_t := 0.0           # seconds until the next one
var run_fans: Array = []       # the fans (their statics' data) who'll run with you; "run" in one says where they're at
var skiers: Array = []         # {design, p0, len, amp, speed, ph}: each carves down its own run and starts again
var lift := {}                 # {x, y0, y1, towers: [y...]}: the main chairlift (bottom y0 is the lower end, nearer the camera)
var lifts: Array = []          # every chairlift up the mountain (the main one first)
const SKIER_COUNT := 40
var groomers: Array = []       # {name, a, b, speed, ph}: snowcat and snowmobile going back and forth
const SKIER_DESIGNS := ["skier_red", "skier_blue", "skier_kid", "skier_retro", "snowboarder_green", "snowboarder_pink", "ski_patrol"]
const CHAIR_SPACING := 3.2     # tiles between chairs
const LIFT_SPEED := 1.1        # tiles per second
var t_ := 0.0


func _init(r) -> void:
	race = r


func build(rng: RandomNumberGenerator) -> void:
	var length: float = race.course["length"]
	run_fans.clear()
	flyover = {}
	flyover_t = rng.randf_range(30.0, FLYOVER_EVERY[1])
	news = NewsHeli.new()
	news.place(race._pose(0.0, -(race.ROAD_HW + 6.0))["pos"], Vector2(1, 1))
	news_on = 0
	news_t = rng.randf_range(NEWS_SWITCH[0], NEWS_SWITCH[1])
	_build_pilots(rng, length)
	_build_start_finish(rng, length)
	if race.lap > 0.0:   # a crit round town: the whole loop lined with townsfolk, and none of the mountain's extras
		_build_crit_crowd(rng, length)
		return
	_build_hairpins(rng)
	_build_ramps(rng, length)
	_build_feed_zone(rng, length)
	_build_camps(rng, length)
	_build_devil(rng, length)
	_build_railway(rng, length)
	_build_ski_area(rng)


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
	var e := {"kind": "fan", "s": s, "lat": lat, "pos": p, "z": race._tz(p), "design": design if design != "" else _fan_design(rng),
		"col": Color.from_hsv(rng.randf(), 0.7, 0.95)}
	race._put_static(2, e, [])
	if rng.randf() < RUN_CHANCE and not e["design"] in NO_RUN and Sprites.sheet("ped_%s_walk" % e["design"]) != null:
		run_fans.append(e)


func _build_start_finish(rng: RandomNumberGenerator, length: float) -> void:
	var tents := ["race_sponsor_tent_red", "race_sponsor_tent_blue", "race_sponsor_tent_yellow"]
	for end in [0, 1]:
		var base := 12.0 if end == 0 else length - 12.0
		var dir := 1.0 if end == 0 else -1.0
		var g: float = race.ROAD_GROW   # everything here stands this much further out, beside the wider road
		for k in 3:
			_sprite(tents[(k + end) % 3], base + dir * k * 14.0, (3.4 + g if k % 2 == 0 else -3.6 - g), k % 2 == 1)
		_sprite("race_bunting_flags", base - dir * 6.0, 2.3 + g)
		_sprite("race_bunting_flags", base - dir * 6.0, -2.3 - g, true)
		var s := base - dir * 12.0
		for k in 8:
			_sprite("race_crowd_barrier", s + dir * k * 4.0, 1.45 + g)
			_sprite("race_crowd_barrier", s + dir * k * 4.0, -1.45 - g, true)
			if k % 2 == 0:
				_fan(s + dir * k * 4.0 + 1.0, 2.1 + g, rng)
				_fan(s + dir * k * 4.0 + 2.0, -2.1 - g, rng)
	_fan(30.0, 1.2 + race.ROAD_GROW, rng, "fan_highfive_kid")
	_fan(length - 40.0, -1.2 - race.ROAD_GROW, rng, "fan_highfive_kid")


## The Crusty Crit's crowd: barriers along both sides of the whole loop (bar the start/finish, which has its own),
## townsfolk standing along them, now and then two or three deep, and a thinner crowd in the infield.
## Nothing is put down where the circuit doubles back close by (`clear`: tiles it needs from any road).
func _build_crit_crowd(rng: RandomNumberGenerator, length: float) -> void:
	var g: float = race.ROAD_GROW
	var put := func(s: float, lat: float, clear: float, barrier := false) -> void:
		if race._rd(race._pose(s, lat)["pos"]) < clear + g:
			return
		if barrier:
			_sprite("race_crowd_barrier", s, lat, lat < 0.0)
		else:
			_fan(s, lat, rng)
	var s := 50.0
	while s < length - 50.0:
		put.call(s, 1.45 + g, 1.3, true)
		put.call(s, -1.45 - g, 1.3, true)
		for row in 2:
			if rng.randf() < 0.42:
				put.call(s + rng.randf_range(-1.5, 1.5), 2.1 + g + row * 0.9 + rng.randf_range(0.0, 0.3), 1.9)
		if rng.randf() < 0.15:
			put.call(s + rng.randf_range(-1.5, 1.5), 3.9 + g + rng.randf_range(0.0, 0.4), 1.9)
		if rng.randf() < 0.27:
			put.call(s + rng.randf_range(-1.5, 1.5), -2.1 - g - rng.randf_range(0.0, 0.6), 1.9)
		s += 4.0


func _build_hairpins(rng: RandomNumberGenerator) -> void:
	for h in race.hairpins:
		if float(h["s"]) > float(race.course["length"]):
			continue
		var c: Vector2 = h["c"]
		var dx: float = h["dx"]
		for fr in [0.26, 0.42, 0.58, 0.74]:   # hay bales round the outside, between the chevrons
			var a: float = PI * fr
			var p: Vector2 = c + Vector2(sin(a) * dx, cos(a)) * (race.HAIRPIN_R + 0.95 + race.ROAD_GROW)
			if Sprites.sheet("race_hay_bale_barrier") != null:
				race._put_static(2, {"kind": "sprite", "name": "race_hay_bale_barrier", "pos": p, "z": race._tz(p), "flip": rng.randf() < 0.5}, [])
		# the crowd packs the inside of the bend, with a marshal at the apex
		for k in rng.randi_range(4, 7):
			var a: float = PI * rng.randf_range(0.15, 0.85)
			var p: Vector2 = c + Vector2(sin(a) * dx, cos(a)) * (race.HAIRPIN_R - rng.randf_range(1.3, 2.6) - race.ROAD_GROW)
			race._put_static(2, {"kind": "fan", "s": float(h["s"]), "pos": p, "z": race._tz(p), "design": _fan_design(rng), "col": Color.WHITE}, [])
		var m: Vector2 = c + Vector2(dx, 0.0) * (race.HAIRPIN_R - 1.1 - race.ROAD_GROW)
		race._put_static(2, {"kind": "fan", "s": float(h["s"]), "pos": m, "z": race._tz(m), "design": "marshal_flag", "col": Color.WHITE}, [])


func _build_ramps(rng: RandomNumberGenerator, length: float) -> void:
	for r in race.ramps:
		if not r["up"]:
			continue
		var s: float = r["s0"]
		while s < float(r["s1"]) and s < length - 30.0:
			if not race._in_tunnel(s, 6.0):
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				_fan(s, side * (rng.randf_range(1.3, 1.9) + race.ROAD_GROW), rng, ["fan_cowbell", "fan_flag", "fan_sign", ""][rng.randi() % 4])
				if rng.randf() < 0.4:
					_sprite("race_cowbell_post", s + 2.0, -side * (1.6 + race.ROAD_GROW))
			s += rng.randf_range(10.0, 18.0)
	for ob in race.obstacles:
		if ob["kind"] == "jump":
			_fan(float(ob["s"]) + 7.0, 1.4 + race.ROAD_GROW, rng, "photographer_kneel")


func _build_feed_zone(rng: RandomNumberGenerator, length: float) -> void:
	var s := length * 0.5
	for _try in 40:
		if race._grade_at(s) < 0.035 and race._clear_of(s, 30.0):
			break
		s = length * rng.randf_range(0.35, 0.65)
	_sprite("race_water_table", s, 2.1 + race.ROAD_GROW)
	for k in 3:
		_fan(s - 6.0 + k * 6.0, 1.25 + race.ROAD_GROW, rng, "feed_helper")
	race._put_static(2, {"kind": "board", "s": s - 60.0, "icon": "up", "l1": "FEED", "l2": "ZONE", "side": 1.0}, [])


func _build_camps(rng: RandomNumberGenerator, length: float) -> void:
	for k in 4:
		var s := length * (0.15 + 0.2 * k) + rng.randf_range(-40.0, 40.0)
		if race._in_tunnel(s, 20.0):
			continue
		var side := 1.0 if k % 2 == 0 else -1.0
		var g: float = race.ROAD_GROW
		_sprite("race_campervan_fans", s, side * (3.8 + g), side < 0.0)
		_sprite("race_portaloo", s + 7.0, side * (3.2 + g))
		_fan(s - 3.0, side * (2.2 + g), rng)
		_fan(s + 2.0, side * (2.0 + g), rng)


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
	var tries: Array = [0.62, 0.38, 0.74, 0.26, 0.5]
	for q in 26:   # with the hairpins stacked high there are many more legs to cross clear of creeks and cliffs
		tries.append(0.25 + 0.02 * q)
	# the line runs down the hillside over as many legs in a row as it can cross cleanly; if a creek, tunnel or cliff
	# is in the way it stops short at a halt between two legs instead
	var best: Array = []
	var best_x := -1.0
	var best_cut := [false, false]   # [stops short at the top, stops short at the bottom]
	for f in tries:
		var x: float = race.leg_len * float(f)
		var all: Array = []   # [crossing, clear?] bottom to top
		for i in race.M - 1:
			var a: Vector2 = race.pts[i]
			var b: Vector2 = race.pts[i + 1]
			if race.road_leg[i] < 0 or (a.x - x) * (b.x - x) > 0.0:
				continue
			var s: float = race.s_m[i]
			var clear: bool = not (race._in_tunnel(s, 25.0) or race._near_ford(s, 25.0) or race._stream_d(x, a.y) < 3.0 or race._in_cliff(s, 15.0))
			all.append([{"s": s, "y": a.y, "lat": 0.0}, clear])
		var q0 := 0
		while q0 < all.size():
			if not all[q0][1]:
				q0 += 1
				continue
			var q1 := q0
			while q1 + 1 < all.size() and all[q1 + 1][1]:
				q1 += 1
			if q1 - q0 + 1 > best.size():
				best = all.slice(q0, q1 + 1).map(func(e): return e[0])
				best_x = x
				best_cut = [q1 < all.size() - 1, q0 > 0]
			q0 = q1 + 1
		if best.size() == all.size() and not all.is_empty():
			break
	if best.size() >= 3:
		rail_x = best_x
		crossings = best
		if best_cut[0]:
			rail_y0 = float(crossings[-1]["y"]) - race.leg_gap * 0.5
		if best_cut[1]:
			rail_y1 = float(crossings[0]["y"]) + race.leg_gap * 0.5
	if rail_x < 0.0:
		return
	for c in crossings:
		var s: float = c["s"]
		if s < length:
			for side in [-1.0, 1.0]:
				var p: Vector2 = Vector2(rail_x + side * 1.0, float(c["y"]) + side * (1.25 + race.ROAD_GROW))
				race._put_static(2, {"kind": "crossing", "pos": p, "z": race._tz(p), "c": c}, [])
			# a warning board, unless a hairpin's board already stands there (the hairpins come thick and fast)
			if not race.hairpins.any(func(h): return absf(float(h["s"]) - 105.0 - (s - 80.0)) < 45.0):
				race._put_static(2, {"kind": "board", "s": s - 80.0, "icon": "train", "l1": "RAILWAY", "l2": "CROSSING", "side": 1.0}, [])
	# a little halt half way up
	var sy: float = lerpf(rail_y0, rail_y1, 0.45)
	var sp := Vector2(rail_x + 2.2, sy)
	if race._rd(sp) > 3.0 + race.ROAD_GROW and Sprites.sheet("race_rail_station") != null:
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
# The ski area
# ---------------------------------------------------------------------

func _snowy(p: Vector2) -> bool:
	return race._snow_cover(p.x, p.y, race._tz(p) / race.peak) > 0.6


func _sprite_at(name: String, p: Vector2, flip := false) -> void:
	if Sprites.sheet(name) != null and race._rd(p) > 2.2 + race.ROAD_GROW:
		race._put_static(2, {"kind": "sprite", "name": name, "pos": p, "z": race._tz(p), "flip": flip}, [])


func _build_ski_area(rng: RandomNumberGenerator) -> void:
	skiers.clear()
	groomers.clear()
	lift = {}
	lifts.clear()
	if Sprites.sheet("ped_skier_red_ski") == null:
		return
	# snowy ground away from the road
	var snow: Array = []
	for j in range(0, race.gh, 2):
		for i in range(0, race.gw, 2):
			var p := Vector2(race.ox + i + 0.5, race.oy + j + 0.5)
			if _snowy(p) and race._rd(p) > 3.0 + race.ROAD_GROW:
				snow.append(p)
	if snow.size() < 30:
		return
	# skiers: each picks a run that stays in the snow, carving down towards the camera (+y)
	for k in SKIER_COUNT:
		for _try in 20:
			var p0: Vector2 = snow[rng.randi() % snow.size()]
			var run := rng.randf_range(6.0, 12.0)
			if _snowy(p0 + Vector2(0, run)) and _snowy(p0 + Vector2(0, run * 0.5)):
				var design: String = SKIER_DESIGNS[k % SKIER_DESIGNS.size()]
				var board := design.begins_with("snowboarder")
				skiers.append({"design": design, "p0": p0, "len": run, "amp": rng.randf_range(0.8, 1.6) * (1.6 if board else 1.0),
					"speed": rng.randf_range(0.9, 1.5) * (0.5 if design == "ski_patrol" else 1.0), "ph": rng.randf() * 10.0, "lag": 0.0})
				break
	# ski schools: an instructor and three kids following in a snake
	if not snow.is_empty() and Sprites.sheet("ped_ski_instructor_ski") != null:
		for school in 2:
			var p0: Vector2 = snow[rng.randi() % snow.size()]
			var ph := rng.randf() * 10.0
			for k in 4:
				skiers.append({"design": "ski_instructor" if k == 0 else "skier_kid", "p0": p0, "len": 9.0, "amp": 1.3, "speed": 0.55, "ph": ph, "lag": k * 0.9})
	# chairlifts up the mountain: the snowy columns with the longest runs of snow, well apart (the longest first)
	var runs: Array = []   # [length, x, bottom y, top y]
	for f in [0.12, 0.2, 0.28, 0.36, 0.45, 0.55, 0.64, 0.72, 0.8, 0.88]:
		var x: float = race.leg_len * float(f)
		if race.life == self and rail_x >= 0.0 and absf(x - rail_x) < 6.0:
			continue
		var best := [0.0, 0.0]
		var y := float(race.oy + race.gh) - 2.0
		var run_start := -1.0
		while y > race.oy + 2.0:
			if _snowy(Vector2(x, y)):
				if run_start < 0.0:
					run_start = y
				if run_start - y > best[0] - best[1]:
					best = [run_start, y]
			else:
				run_start = -1.0
			y -= 1.0
		if best[0] - best[1] > 14.0:
			runs.append([best[0] - best[1], x, best[0], best[1]])
	runs.sort_custom(func(a, b): return a[0] > b[0])
	for rn in runs:
		if lifts.size() >= 3 or lifts.any(func(l): return absf(float(l["x"]) - float(rn[1])) < 9.0):
			continue
		var bx: float = rn[1]
		var towers: Array = []
		var ty: float = float(rn[2]) - 2.0
		while ty > float(rn[3]) + 2.0:
			if race._rd(Vector2(bx, ty)) > 1.4 + race.ROAD_GROW and not race._on_cliff(Vector2(bx, ty), true):   # the cable spans the cliffs
				towers.append(ty)
			ty -= 7.0
		lifts.append({"x": bx, "y0": rn[2], "y1": rn[3], "towers": towers, "ph": rng.randf() * 10.0})
		for t in towers:
			_sprite_at("ski_chairlift_tower", Vector2(bx, t))
		_sprite_at("ski_chairlift_station", Vector2(bx + 0.4, float(rn[2]) + 1.5))
		_sprite_at("ski_chairlift_station", Vector2(bx + 0.4, float(rn[3]) - 1.0), true)
	if not lifts.is_empty():
		lift = lifts[0]
		var best_x: float = lift["x"]
		var best := [float(lift["y0"]), float(lift["y1"])]
		# the base area by the bottom station
		var base := Vector2(best_x + 4.5, best[0] + 1.0)
		_sprite_at("ski_ski_lodge", base + Vector2(2.0, 1.0))
		_sprite_at("ski_cocoa_stand", base + Vector2(-1.5, 2.5))
		_sprite_at("ski_ticket_booth", base + Vector2(-3.0, 0.2))
		_sprite_at("ski_ski_rack", base + Vector2(-0.5, -1.5))
		_sprite_at("ski_ski_rack", base + Vector2(0.8, -1.2), true)
		_sprite_at("ski_trail_sign_green_circle", base + Vector2(-4.0, -2.0))
	# bits and pieces around the snow
	var bits := ["ski_slalom_gates", "ski_slalom_gates", "ski_snow_fence", "ski_snow_fence", "ski_igloo", "ski_snow_pile", "ski_snow_pile",
		"ski_snow_angel", "ski_trail_sign_blue_square", "ski_trail_sign_black_diamond", "ski_ski_jump_ramp"]
	for b in bits:
		_sprite_at(b, snow[rng.randi() % snow.size()] + Vector2(rng.randf(), rng.randf()), rng.randf() < 0.5)
	# a snowcat grooming across the slope and a snowmobile buzzing about
	for g in [["vehicle_snowcat", 0.6], ["vehicle_snowmobile", 2.2]]:
		for _try in 30:
			var a: Vector2 = snow[rng.randi() % snow.size()]
			var b := a + Vector2(rng.randf_range(8.0, 14.0), rng.randf_range(-2.0, 2.0))
			if _snowy(b) and _snowy((a + b) * 0.5):
				groomers.append({"name": g[0], "a": a, "b": b, "speed": g[1], "ph": rng.randf() * 20.0})
				break


func _skier_pos(sk: Dictionary, t: float) -> Array:
	var run: float = sk["len"]
	var u := fposmod((t - float(sk["lag"])) * float(sk["speed"]) / run + float(sk["ph"]), 1.0)
	var p0: Vector2 = sk["p0"]
	var w := TAU * 1.5
	var p := p0 + Vector2(sin(u * w) * float(sk["amp"]), u * run)
	var dp := Vector2(cos(u * w) * float(sk["amp"]) * w, run)
	return [p, dp.normalized(), u]


func _draw_skier(sk: Dictionary, p: Vector2, dir: Vector2, u: float) -> void:
	var at := Iso.to_screen(p, race._tz(p))
	var a := clampf(minf(u, 1.0 - u) * 12.0, 0.0, 1.0)   # fade in at the top and out at the bottom of the run
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 0), at + Vector2(0, -2.5), at + Vector2(6, 0), at + Vector2(0, 2.5)]), Color(0.3, 0.35, 0.5, 0.25 * a))
	# a different skier for everyone on screen (the ski school's kids from the little ones, the instructor is the instructor)
	var look := Sprites.cast(sk, ["ski_instructor"] if sk["design"] == "ski_instructor" else Sprites.skiers(sk["design"] == "skier_kid" and float(sk["lag"]) > 0.0))
	if look == "":
		return
	Sprites.draw_person(race, "ped_%s_ski" % look, at, dir, t_ + float(sk["ph"]), 8.0, Color(1, 1, 1, a), sk)


## [position, going up?, the lift] for every chair on every lift.
func _chairs() -> Array:
	var out: Array = []
	for l in lifts:
		var y0: float = l["y0"]
		var y1: float = l["y1"]
		var span := y0 - y1
		var loop := span * 2.0
		var n := int(loop / CHAIR_SPACING)
		for k in n:
			var u := fposmod((t_ + float(l["ph"])) * LIFT_SPEED + k * CHAIR_SPACING, loop)
			var up := u < span
			var y := y0 - u if up else y1 + (u - span)
			var p := Vector2(float(l["x"]) + (-0.45 if up else 0.45), y)
			out.append([p, up, l])
	return out


func _cable_z(l: Dictionary, y: float) -> float:
	# the cable hangs between the towers, about 70 px above the ground under it
	return race._tz(Vector2(float(l["x"]), y)) + 70.0 - 8.0 * absf(sin(y / 7.0 * PI))


func _draw_chair(p: Vector2, up: bool, l: Dictionary) -> void:
	var z := _cable_z(l, p.y)
	var top := Iso.to_screen(p, z)
	race.draw_line(top, top + Vector2(0, 12), Color(0.2, 0.2, 0.25), 1.0)
	Sprites.draw_vehicle(race, "obj_chairlift_chair_riders" if up else "obj_chairlift_chair", top + Vector2(0, 26), Vector2(0, -1) if up else Vector2(0, 1))


## The chairlift cables, drawn over everything (they are high up).
func draw_lift_cables(ci: CanvasItem) -> void:
	for l in lifts:
		for side in [-0.45, 0.45]:
			var pts := PackedVector2Array()
			var y: float = l["y1"]
			while y <= float(l["y0"]):
				pts.append(Iso.to_screen(Vector2(float(l["x"]) + side, y), _cable_z(l, y)))
				y += 1.0
			if pts.size() > 1:
				ci.draw_polyline(pts, Color(0.18, 0.18, 0.22, 0.85), 1.0)


# ---------------------------------------------------------------------
# Moving things
# ---------------------------------------------------------------------

func update(delta: float) -> void:
	t_ += delta
	_step_runners(delta)
	_step_flyover(delta)
	_step_news(delta)
	_step_pilots(delta)


func _build_pilots(rng: RandomNumberGenerator, length: float) -> void:
	pilots.clear()
	if Sprites.sheet("drone") == null:
		return
	for k in DRONE_SPOTS:
		var s := length * (0.2 + 0.6 * (k + rng.randf_range(0.2, 0.8)) / DRONE_SPOTS)
		if race._in_tunnel(s, 20.0):
			continue
		var lat: float = (1.0 if rng.randf() < 0.5 else -1.0) * (race.ROAD_HW + 1.1)
		var p: Vector2 = race._pose(s, lat)["pos"]
		pilots.append({"s": s, "lat": lat, "pos": p, "drone": {"state": "parked", "pos": p + Vector2(0.4, 0.4), "alt": 0.0,
			"dir": Vector2(1, 0), "t": 0.0, "turn": {}}})


## The news helicopter films the race: hovering off to the side of you or the leader, a little ahead, and now and then
## heading over to the other one.
func _step_news(delta: float) -> void:
	if race.riders.is_empty():
		return
	news_t -= delta
	if news_t <= 0.0:
		news_t = randf_range(NEWS_SWITCH[0], NEWS_SWITCH[1])
		news_on = 1 - news_on
	var who: Dictionary = race.riders[0]
	if news_on == 1:
		for r in race.riders:
			if float(r["s"]) > float(who["s"]) and not r["done"]:
				who = r
	var s := minf(float(who["s"]) + 5.0, race.goal_s())
	news.update(delta, race._pose(s, -(race.ROAD_HW + 3.0))["pos"])


## Drone pilots: as you go by, the drone lifts off and follows you, beside you and a little ahead, for a while; then
## it flies back and lands at the pilot's feet. Once a race each.
func _step_pilots(delta: float) -> void:
	if race.riders.is_empty() or race.countdown > 0.0:
		return
	var me: Dictionary = race.riders[0]
	var ms: float = me["s"]
	for pl in pilots:
		var d: Dictionary = pl["drone"]
		d["t"] = float(d["t"]) - delta
		match d["state"]:
			"parked":
				if not pl.get("flown", false) and ms > float(pl["s"]) - 3.0 and ms < float(pl["s"]) + 1.0:
					pl["flown"] = true
					d["state"] = "up"
					d["t"] = 1.2
			"up":
				d["alt"] = DRONE_ALT * (1.0 - maxf(0.0, float(d["t"])) / 1.2)
				if float(d["t"]) <= 0.0:
					d["state"] = "follow"
					d["t"] = randf_range(DRONE_FOLLOW[0], DRONE_FOLLOW[1])
			"follow":
				var side := signf(float(pl["lat"]))
				var goal: Vector2 = race._pose(ms + 1.6, side * (race.ROAD_HW + 0.2))["pos"]
				var step := (goal - (d["pos"] as Vector2))
				var v := maxf(float(me["v"]) * 1.4, 3.0)
				d["pos"] = (d["pos"] as Vector2) + step.limit_length(v * delta * 1.6)
				if step.length() > 0.05:
					d["dir"] = (d["dir"] as Vector2).lerp(step.normalized(), minf(1.0, delta * 4.0)).normalized()
				if float(d["t"]) <= 0.0 or me["done"]:
					d["state"] = "home"
			"home":
				var to: Vector2 = (pl["pos"] as Vector2) + Vector2(0.4, 0.4) - d["pos"]
				if to.length() <= DRONE_SPEED * delta:
					d["pos"] = (pl["pos"] as Vector2) + Vector2(0.4, 0.4)
					d["state"] = "down"
					d["t"] = 1.2
				else:
					d["pos"] = (d["pos"] as Vector2) + to.normalized() * DRONE_SPEED * delta
					d["dir"] = to.normalized()
			"down":
				d["alt"] = DRONE_ALT * maxf(0.0, float(d["t"])) / 1.2
				if float(d["t"]) <= 0.0:
					d["state"] = "parked"
					d["alt"] = 0.0


func _draw_pilot(pl: Dictionary) -> void:
	var p: Vector2 = pl["pos"]
	var at := Iso.to_screen(p, race._tz(p))
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(0, -2.5), at + Vector2(5, 0), at + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
	var flying: bool = pl["drone"]["state"] != "parked"
	if not (flying and Sprites.draw_strip(race, "ped_drone_operator_fly", at, t_, 8.0)):
		Sprites.draw_person(race, "ped_drone_operator_walk", at, Vector2(1, 1), 0.0, 0.0)


func _draw_drone(d: Dictionary) -> void:
	var p: Vector2 = d["pos"]
	var ground := Iso.to_screen(p, race._tz(p))
	var alt := float(d["alt"])
	if alt > 2.0:
		race.draw_colored_polygon(PackedVector2Array([ground + Vector2(-7, 0), ground + Vector2(0, -2.5), ground + Vector2(7, 0), ground + Vector2(0, 2.5)]), Color(0, 0, 0, 0.18))
	var at := ground + Vector2(0.0, -alt - 6.0 + (sin(t_ * 6.0) * 1.0 if alt > 2.0 else 0.0))
	var tex := Sprites.sheet("drone")
	var per := maxi(1, tex.get_width() / (tex.get_height() / Sprites.DIRS))
	Sprites.draw_vehicle(race, "drone", at, d["dir"], Color.WHITE, int(t_ * 24.0) % per if alt > 0.5 else 0, d["turn"])


## Now and then the air ambulance flies over: across the course near you, from well off one side to well off the other.
func _step_flyover(delta: float) -> void:
	if race.riders.is_empty() or Sprites.sheet("heli_medical") == null:
		return
	var me_p: Vector2 = race._pose(race.riders[0]["s"], 0.0)["pos"]
	if flyover.is_empty():
		flyover_t -= delta
		if flyover_t <= 0.0:
			flyover_t = randf_range(FLYOVER_EVERY[0], FLYOVER_EVERY[1])
			var dir := Vector2.from_angle(randf() * TAU)
			flyover = {"pos": me_p - dir * FLYOVER_HALF + dir.orthogonal() * randf_range(-6.0, 6.0), "dir": dir, "left": FLYOVER_HALF * 2.0, "turn": {}}
		return
	var step := FLYOVER_SPEED * delta
	flyover["pos"] = (flyover["pos"] as Vector2) + (flyover["dir"] as Vector2) * step
	flyover["left"] = float(flyover["left"]) - step
	if float(flyover["left"]) <= 0.0:
		flyover = {}


func _draw_flyover(ci: CanvasItem) -> void:
	if flyover.is_empty():
		return
	var p: Vector2 = flyover["pos"]
	var ground := Iso.to_screen(p, race._tz(p))
	ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-16, 0), ground + Vector2(0, -5), ground + Vector2(16, 0), ground + Vector2(0, 5)]), Color(0, 0, 0, 0.16))
	var at := Iso.to_screen(p, race._tz(race._pose(race.riders[0]["s"], 0.0)["pos"]) + FLYOVER_ALT) + Vector2(0.0, MedHeli.SKIDS + sin(t_ * 2.3) * 2.0)
	MedHeli.draw_heli(ci, "heli_medical", at, flyover["dir"], MedHeli.TILT["nose_down"], t_, 1.0, flyover["turn"])   # cruising, nose down


## Fans running with you: as you reach one they set off from their spot and sprint along the roadside beside you
## (as fast as you, up to RUN_MAX) for a few seconds, then pull up, cheer, and walk back. Once a race each.
func _step_runners(delta: float) -> void:
	if race.riders.is_empty() or race.countdown > 0.0:
		return
	var me: Dictionary = race.riders[0]
	var ms: float = me["s"]
	var mv: float = me["v"]
	for e in run_fans:
		var st: String = e.get("run", "")
		var home: float = e["s"]
		if st == "":
			if not e.get("ran", false) and ms > home - 2.5 and ms < home + 0.5 and mv > 2.0 and float(me["down"]) <= 0.0:
				e["ran"] = true
				e["run"] = "run"
				e["rs"] = home
				e["rlat"] = float(e["lat"])
				e["rv"] = 0.0
				e["rt"] = randf_range(3.0, 6.0)
				e["say"] = FAN_SHOUTS.pick_random()
			continue
		var side := signf(float(e["lat"]))
		match st:
			"run":
				# stay level with you or just behind, never out in front
				var want := minf(minf(mv + 0.6, RUN_MAX), RUN_MAX if float(e["rs"]) < ms - 0.8 else mv)
				e["rv"] = move_toward(float(e["rv"]), want, 7.0 * delta)
				e["rt"] = float(e["rt"]) - delta
				if float(e["rt"]) <= 0.0 or float(me["down"]) > 0.0:
					e["run"] = "stop"
					e["rt"] = 1.8
					e["roll"] = randi()
			"stop":
				e["rv"] = move_toward(float(e["rv"]), 0.0, 6.0 * delta)
				e["rt"] = float(e["rt"]) - delta
				if float(e["rt"]) <= 0.0:
					e["run"] = "back"
			"back":
				e["rv"] = -1.3
				if float(e["rs"]) <= home:
					e["run"] = ""
					continue
		e["rs"] = maxf(home, float(e["rs"]) + float(e["rv"]) * delta)
		var to_lat := float(e["lat"]) if st == "back" and float(e["rs"]) - home < 2.0 else side * (RUN_LAT + float(race.ROAD_GROW))
		e["rlat"] = move_toward(float(e["rlat"]), to_lat, 1.5 * delta)


func _draw_runner(e: Dictionary, pz: Dictionary) -> void:
	var at := Iso.to_screen(pz["pos"], pz["z"])
	var n: Vector2 = pz["n"]
	var along := Vector2(n.y, -n.x)   # the way the race goes
	var design := Sprites.cast(e, e.get("looks", []))
	if design == "":
		return
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(0, -2.5), at + Vector2(5, 0), at + Vector2(0, 2.5)]), Color(0, 0, 0, 0.2))
	match e["run"]:
		"run":
			Sprites.draw_person(race, "ped_%s_walk" % design, at, along, t_ + float(e["s"]), 16.0)
			if fmod(t_ + float(e["s"]), 2.4) < 1.4:
				_shout(at + Vector2(0, -52), e["say"], Color(1.0, 0.95, 0.45))
		"stop":
			Sprites.draw_any_cheer(race, design, at, t_, int(e["roll"]))
		"back":
			Sprites.draw_person(race, "ped_%s_walk" % design, at, -along, t_ + float(e["s"]), 8.0)


## [world position, draw callable] for everything that moves this frame.
func movers() -> Array:
	var out: Array = []
	if race.riders.is_empty():
		return out
	if race.rescue:   # the injured skier and the patroller waving you in
		var pz: Dictionary = race._pose(race.rescue_s, 2.2 + race.ROAD_GROW)
		out.append([pz["pos"], _draw_casualty.bind(pz)])
	var me: Dictionary = race.riders[0]
	var lead := 0.0
	var last := 1e9
	for r in race.riders:
		lead = maxf(lead, float(r["s"]))
		last = minf(last, float(r["s"]))
	# the motos ahead of the leader, the team car behind the last rider
	if lead < race.goal_s() - 20.0:
		_add_vehicle(out, "vehicle_tv_moto", lead + 9.0, -0.5 * race.ROAD_W)
		_add_vehicle(out, "vehicle_marshal_moto", lead + 22.0, 0.45 * race.ROAD_W)
	if last > 20.0 and last < race.goal_s():
		_add_vehicle(out, "vehicle_team_car", last - 13.0, -0.35 * race.ROAD_W)
	# fans running with you
	for e in run_fans:
		if e.get("run", "") != "":
			var pz: Dictionary = race._pose(e["rs"], e["rlat"])
			out.append([pz["pos"], _draw_runner.bind(e, pz)])
	# drone pilots and their drones
	for pl in pilots:
		if absf(float(pl["s"]) - float(me["s"])) < 120.0 or pl["drone"]["state"] != "parked":
			out.append([pl["pos"], _draw_pilot.bind(pl)])
			var d: Dictionary = pl["drone"]
			out.append([(d["pos"] as Vector2) + Vector2(0.01, 0.01), _draw_drone.bind(d)])
	# the devil
	if not devil.is_empty():
		var s: float = me["s"]
		var lat: float = (1.6 + race.ROAD_GROW) * float(devil["side"])
		var running: bool = s > float(devil["s0"]) and s < float(devil["s1"]) and race.countdown <= 0.0
		var ds: float = clampf(s + 2.4, float(devil["s0"]), float(devil["s1"])) if running else (float(devil["s0"]) if s <= float(devil["s0"]) else float(devil["s1"]))
		var pz: Dictionary = race._pose(ds, lat)
		out.append([pz["pos"], _draw_devil.bind(pz, running)])
	# the ski area
	for sk in skiers:
		var r := _skier_pos(sk, t_)
		out.append([r[0], _draw_skier.bind(sk, r[0], r[1], r[2])])
	for c in _chairs():
		out.append([c[0], _draw_chair.bind(c[0], c[1], c[2])])
	for g in groomers:
		var span := (g["b"] as Vector2).distance_to(g["a"])
		var u := fposmod(t_ * float(g["speed"]) / span + float(g["ph"]), 2.0)
		var fwd := u < 1.0
		var p: Vector2 = (g["a"] as Vector2).lerp(g["b"], u if fwd else 2.0 - u)
		var dir: Vector2 = ((g["b"] as Vector2) - (g["a"] as Vector2)).normalized() * (1.0 if fwd else -1.0)
		out.append([p, _draw_groomer.bind(g["name"], p, dir)])
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
	var along := Vector2(n.y, -n.x)   # along the road, the way the race goes
	var at := Iso.to_screen(pz["pos"], pz["z"] + 1.5)
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-12, 0), at + Vector2(0, -5), at + Vector2(12, 0), at + Vector2(0, 5)]), Color(0, 0, 0, 0.2))
	Sprites.draw_vehicle(race, name, at + Vector2(0, -1 if int(t_ * 8.0) % 2 == 0 else 0), along, Color.WHITE, int(t_ * 8.0), Sprites.turn_state("race/" + name))


func _draw_groomer(name: String, p: Vector2, dir: Vector2) -> void:
	var at := Iso.to_screen(p, race._tz(p) + 1.5)
	race.draw_colored_polygon(PackedVector2Array([at + Vector2(-14, 0), at + Vector2(0, -6), at + Vector2(14, 0), at + Vector2(0, 6)]), Color(0.3, 0.35, 0.5, 0.25))
	Sprites.draw_vehicle(race, name, at + Vector2(0, -1 if int(t_ * 6.0) % 2 == 0 else 0), dir, Color.WHITE, int(t_ * 6.0), Sprites.turn_state("race/" + name))


## The rescue: an injured skier on a stretcher in the snow beside the road, a ski patroller waving you in, a red cross
## flag so you can see where from down the road.
func _draw_casualty(pz: Dictionary) -> void:
	var at := Iso.to_screen(pz["pos"], pz["z"])
	var n: Vector2 = pz["n"]
	if not Sprites.draw_vehicle(race, "obj_stretcher_patient", at + Vector2(0, -4), Vector2(-n.y, n.x)):
		race.draw_rect(Rect2(at + Vector2(-10, -6), Vector2(20, 5)), Color(0.85, 0.2, 0.2))
	var patrol := at + Vector2(14, -2)
	if not Sprites.draw_cheer(race, "ped_ski_patrol_cheer", patrol, t_):
		Sprites.draw_cheer(race, "ped_nurse_cheer", patrol, t_)
	# the flag
	var pole := at + Vector2(-16, 0)
	race.draw_line(pole, pole + Vector2(0, -44), Iso.OUTLINE, 2.0)
	race.draw_rect(Rect2(pole + Vector2(1, -44), Vector2(16, 11)), Color.WHITE)
	race.draw_rect(Rect2(pole + Vector2(7, -42), Vector2(4, 7)), Color(0.9, 0.15, 0.15))
	race.draw_rect(Rect2(pole + Vector2(5, -40), Vector2(8, 3)), Color(0.9, 0.15, 0.15))
	if int(t_ * 1.5) % 2 == 0:
		_shout(patrol + Vector2(0, -58), "OVER HERE! HURRY!", Color(1.0, 0.4, 0.4))


func _draw_devil(pz: Dictionary, running: bool) -> void:
	var at := Iso.to_screen(pz["pos"], pz["z"])
	var n: Vector2 = pz["n"]
	Sprites.cast(devil, ["fan_devil"], true)   # the one and only devil: no fan in the same costume next to him
	if running:
		Sprites.draw_person(race, "ped_fan_devil_walk", at, Vector2(n.y, -n.x), t_, 12.0)
		if int(t_ * 1.5) % 3 == 0:
			_shout(at + Vector2(0, -58), ["ALLEZ ALLEZ!", "GO GO GO!", "DIG DEEP!", "FASTER!"][int(t_ / 2.0) % 4], Color(1.0, 0.35, 0.3))
	else:
		Sprites.draw_cheer(race, "ped_fan_devil_cheer", at, t_)


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
	_draw_flyover(ci)
	if race.riders.is_empty():
		return
	if Sprites.sheet("heli_news") != null:
		var p: Vector2 = news.pos
		var me_z: float = race._tz(race._pose(race.riders[0]["s"], 0.0)["pos"])
		news.draw(ci, Iso.to_screen(p, race._tz(p)), NEWS_ALT + me_z - race._tz(p))
	elif Sprites.sheet("race_helicopter_tv") != null:   # (the old TV helicopter picture, until the news one's art is in)
		var pz: Dictionary = race._pose(float(race.riders[0]["s"]) + 6.0, -3.0)
		Sprites.draw_image(ci, "race_helicopter_tv", Iso.to_screen(pz["pos"], pz["z"]) + Vector2(0.0, -170.0), false, 1.0, 0.8)


func _shout(at: Vector2, text: String, col: Color) -> void:
	var font: Font = race.font
	race.draw_string_outline(font, at + Vector2(-50, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 9, 4, Iso.OUTLINE)
	race.draw_string(font, at + Vector2(-50, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 9, col)
