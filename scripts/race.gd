extends Node2D
## Mt. Crankmore hill-climb: a spiral road up an isometric heightfield mountain.
## Player power drives speed through a real power/grade/drag model; the trainer gets the grade.

signal finished(result: Dictionary)

const R0 := 20.0
const RTOP := 3.5
const M := 500            # road samples
const G := 48             # terrain cells per side
const OX := -24.0         # terrain origin (world tiles)
const COURSES := [
	{"name": "Foothill Gravel Grind", "length": 6000.0, "grade": 0.04, "turns": 3.0, "entry": 40, "prize": 500,
		"blurb": "6 km of rolling gravel, about 20 minutes for the front of the pack. Full of squirrels."},
	{"name": "Summit Gravel Showdown", "length": 4400.0, "grade": 0.065, "turns": 4.0, "entry": 100, "prize": 1200,
		"blurb": "4.4 km of steep gravel to the top of Mt. Crankmore with ramps up to 10%, about 20 minutes. Legends are made here. So are blisters."},
]
const MAX_GRADE := 0.10
const A0 := 2.4

var active := false
var course: Dictionary = {}
var s_m := PackedFloat32Array()
var elev := PackedFloat32Array()
var grade_a := PackedFloat32Array()
var vz := 4.0
var spacing := 5.0
var gain := 100.0
var zgrid := PackedFloat32Array()
var trees: Array = []
var deco: Array = []
var road_segs: Array = []
var road_buckets: Dictionary = {}
var riders: Array = []
var clock := 0.0
var countdown := 0.0
var over := false
var over_clock := 0.0
var finish_count := 0
var boost_left := 0.0
var boost_charge := 1.0
var stamina := 1.0
var bubbles: Dictionary = {}
var font: Font
var player_finish_time := 0.0
var last_swap := {}
var lead_clock := 0.0
var t_ := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	Game.rival_say.connect(func(rival: int, text: String): bubbles[rival + 1] = {"text": text, "t": 4.5})


func cam_target() -> Vector2:
	if riders.is_empty():
		return Iso.to_screen(_pose(0.0, 0.0)["pos"], 120.0)
	var p := _pose(riders[0]["s"], riders[0]["lat"])
	return Iso.to_screen(p["pos"], p["z"] + 30.0)


# ---------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------

func setup(course_id: int) -> void:
	course = COURSES[course_id]
	spacing = (R0 - RTOP) / float(course["turns"])
	_build_road()
	_build_terrain()
	_build_riders()
	clock = 0.0
	countdown = 4.0
	over = false
	over_clock = 0.0
	finish_count = 0
	boost_left = 0.0
	boost_charge = 1.0
	stamina = 1.0
	lead_clock = 0.0
	last_swap.clear()
	bubbles.clear()
	player_finish_time = 0.0
	# pre-race jabber
	var ids := range(Talk.rivals.size())
	ids.shuffle()
	for k in mini(3, ids.size()):
		get_tree().create_timer(1.0 + k * 1.2).timeout.connect(Talk.say.bind(ids[k], "race_start", true))


func _build_road() -> void:
	s_m.resize(M)
	elev.resize(M)
	grade_a.resize(M)
	var cum := 0.0
	var prev := Vector2(cos(A0), sin(A0)) * R0
	var tiles_cum := PackedFloat32Array()
	tiles_cum.resize(M)
	for i in M:
		var t := i / float(M - 1)
		var r := lerpf(R0, RTOP, t)
		var a := A0 + float(course["turns"]) * TAU * t
		var p := Vector2(cos(a), sin(a)) * r
		cum += p.distance_to(prev)
		prev = p
		tiles_cum[i] = cum
	var mpt: float = float(course["length"]) / cum
	var e := 0.0
	for i in M:
		s_m[i] = tiles_cum[i] * mpt
		var f := s_m[i] / float(course["length"])
		var g: float = float(course["grade"]) * (1.0 + 0.45 * sin(f * TAU * 2.5) + 0.2 * sin(f * TAU * 6.1 + 1.0))
		g = clampf(g, 0.012, MAX_GRADE)
		grade_a[i] = g
		if i > 0:
			e += g * (s_m[i] - s_m[i - 1])
		elev[i] = e
	gain = elev[M - 1]
	vz = 430.0 / gain


func _elev_at_t(t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * (M - 1)
	var i := mini(int(f), M - 2)
	return lerpf(elev[i], elev[i + 1], f - i)


func road_dist(x: float, y: float) -> float:
	var r := sqrt(x * x + y * y)
	if r > R0 + 0.8 or r < RTOP - 0.8:
		return 99.0
	var a := atan2(y, x)
	var u := (R0 - r) / spacing - (a - A0) / TAU
	return absf(u - roundf(u)) * spacing


func terrain_z(x: float, y: float) -> float:
	var r := sqrt(x * x + y * y)
	var e := 0.0
	if r >= R0:
		e = -maxf(0.0, r - R0) * 1.5 * vz * 0.3
	elif r > RTOP:
		e = _elev_at_t((R0 - r) / (R0 - RTOP)) * vz
	else:
		e = gain * vz + (RTOP - r) * 16.0
	var rd := road_dist(x, y)
	var amp := 9.0 * smoothstep(1.3, 4.5, rd)
	e += (sin(x * 0.9) * cos(y * 0.7) + 0.5 * sin(x * 1.9 + y * 1.3)) * amp
	return e


func _build_terrain() -> void:
	zgrid.resize((G + 1) * (G + 1))
	for j in G + 1:
		for i in G + 1:
			zgrid[j * (G + 1) + i] = terrain_z(OX + i, OX + j)
	trees.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var peak := gain * vz
	for j in G:
		for i in G:
			if rng.randf() > 0.2:
				continue
			var x := OX + i + rng.randf()
			var y := OX + j + rng.randf()
			var z := terrain_z(x, y)
			if road_dist(x, y) < 1.9 or z > peak * 0.72:
				continue
			trees.append({"pos": Vector2(x, y), "z": z, "s": rng.randf_range(0.8, 1.4), "kind": rng.randi() % 4})
	_build_road_geometry()
	deco.clear()
	deco.append({"kind": "arch", "s": 0.0, "label": "START"})
	deco.append({"kind": "arch", "s": float(course["length"]) - 2.0, "label": "FINISH"})
	var km := 500.0
	while km < float(course["length"]) - 60.0:
		deco.append({"kind": "sign", "s": km, "label": "%.2f km" % (km / 1000.0)})
		km += 500.0
	for k in 14:
		deco.append({"kind": "fan", "s": rng.randf_range(0.0, 25.0) if k < 7 else float(course["length"]) - rng.randf_range(0.0, 25.0),
			"side": 1.0 if rng.randf() < 0.5 else -1.0, "off": rng.randf_range(1.1, 2.2), "col": Color.from_hsv(rng.randf(), 0.7, 0.95)})


## Road as a smooth ribbon, pre-projected to screen space and bucketed by depth diagonal.
func _build_road_geometry() -> void:
	road_segs.clear()
	road_buckets.clear()
	for i in M - 1:
		var t0 := i / float(M - 1)
		var t1 := (i + 1) / float(M - 1)
		var pa := _road_point(t0)
		var pb := _road_point(t1)
		var ua := Vector2(cos(pa["a"]), sin(pa["a"]))
		var ub := Vector2(cos(pb["a"]), sin(pb["a"]))
		var za: float = pa["z"] + 1.5
		var zb: float = pb["z"] + 1.5
		var edge := PackedVector2Array([Iso.to_screen(pa["pos"] - ua * 0.64, za), Iso.to_screen(pb["pos"] - ub * 0.64, zb),
			Iso.to_screen(pb["pos"] + ub * 0.64, zb), Iso.to_screen(pa["pos"] + ua * 0.64, za)])
		var asphalt := PackedVector2Array([Iso.to_screen(pa["pos"] - ua * 0.52, za + 0.3), Iso.to_screen(pb["pos"] - ub * 0.52, zb + 0.3),
			Iso.to_screen(pb["pos"] + ub * 0.52, zb + 0.3), Iso.to_screen(pa["pos"] + ua * 0.52, za + 0.3)])
		var ruts: Array = []
		for off in [-0.25, 0.25]:
			ruts.append(PackedVector2Array([Iso.to_screen(pa["pos"] + ua * (off - 0.05), za + 0.5), Iso.to_screen(pb["pos"] + ub * (off - 0.05), zb + 0.5),
				Iso.to_screen(pb["pos"] + ub * (off + 0.05), zb + 0.5), Iso.to_screen(pa["pos"] + ua * (off + 0.05), za + 0.5)]))
		var pebbles := PackedVector2Array()
		for k in 4:
			var f := fposmod(i * 0.618 + k * 0.29, 1.0)
			var lat := fposmod(i * 0.377 + k * 0.53, 1.0) * 1.0 - 0.5
			var pp: Vector2 = (pa["pos"] as Vector2).lerp(pb["pos"], f) + ua * lat
			pebbles.append(Iso.to_screen(pp, lerpf(za, zb, f) + 0.6))
		road_segs.append({"edge": edge, "asphalt": asphalt, "ruts": ruts, "pebbles": pebbles, "shade": 0.92 + 0.08 * float(i % 2)})
		var d := _diag((pa["pos"] + pb["pos"]) * 0.5)
		if not road_buckets.has(d):
			road_buckets[d] = []
		road_buckets[d].append(i)


func _road_point(t: float) -> Dictionary:
	var r := lerpf(R0, RTOP, t)
	var a := A0 + float(course["turns"]) * TAU * t
	return {"pos": Vector2(cos(a), sin(a)) * r, "z": _elev_at_t(t) * vz, "a": a}


func _build_riders() -> void:
	riders.clear()
	var b := Game.bike()
	riders.append({"name": Game.player_name, "color": Color(0.95, 0.95, 0.95), "frame": b["color"], "s": 0.0, "v": 0.0, "lat": 0.0,
		"bike": b, "player": true, "phase": 0.0, "done": false, "time": 0.0, "mass": Game.weight_kg, "power": 0.0})
	var n := Talk.rivals.size()
	for i in n:
		var info: Dictionary = Talk.rivals[i]
		var mass := Game.rival_mass(i)
		var lane := (i - (n - 1) * 0.5) * 0.1 + 0.05
		riders.append({"name": info["name"], "short": info["short"], "color": info["color"], "frame": Color(info["color"]).lerp(Color.WHITE, 0.2),
			"s": 0.0, "v": 0.0, "lat": lane, "lane": lane, "bike": Game.rival_bike(info), "player": false,
			"phase": randf() * TAU, "done": false, "time": 0.0, "mass": mass, "ftp": Game.rival_ftp(info, mass), "idx": i,
			"surge": 0.0, "surge_in": randf_range(25.0, 50.0), "power": 0.0, "wiggle": randf() * TAU})


# ---------------------------------------------------------------------
# Pose helpers
# ---------------------------------------------------------------------

func _t_of_s(s: float) -> float:
	var sc := clampf(s, 0.0, s_m[M - 1])
	var i := clampi(s_m.bsearch(sc), 1, M - 1)
	var f := inverse_lerp(s_m[i - 1], s_m[i], sc)
	return (i - 1 + clampf(f, 0.0, 1.0)) / float(M - 1)


func _grade_at(s: float) -> float:
	var sc := clampf(s, 0.0, s_m[M - 1])
	return grade_a[clampi(s_m.bsearch(sc), 0, M - 1)]


func _pose(s: float, lat: float) -> Dictionary:
	var t := _t_of_s(s)
	var r := lerpf(R0, RTOP, t) + lat
	var a := A0 + float(course["turns"]) * TAU * t
	var p := Vector2(cos(a), sin(a)) * r
	return {"pos": p, "z": _elev_at_t(t) * vz, "t": t, "a": a, "r": r}


# ---------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	t_ += delta
	if not active:
		return
	if countdown > 0.0:
		countdown -= delta
		if countdown <= 0.0:
			Game.toast.emit("GO GO GO!", Color(0.4, 1.0, 0.4))
	else:
		clock += delta
		_step_riders(delta)
		_banter()
	for k in bubbles.keys():
		bubbles[k]["t"] -= delta
		if bubbles[k]["t"] <= 0.0:
			bubbles.erase(k)
	var me: Dictionary = riders[0]
	Zwift.send_grade(_grade_at(me["s"]) * 100.0 if countdown <= 0.0 and not me["done"] else 0.0)
	queue_redraw()


func _step_riders(delta: float) -> void:
	var length: float = float(course["length"])
	# player
	var me: Dictionary = riders[0]
	if not me["done"]:
		var g := _grade_at(me["s"])
		var p := Zwift.power()
		if not Zwift.trainer_live:
			if p > Game.ftp * 1.1:
				stamina = maxf(0.0, stamina - delta * 0.1)
				if stamina <= 0.0:
					p = Game.ftp
			else:
				stamina = minf(1.0, stamina + delta * 0.06)
		me["power"] = p
		var b: Dictionary = me["bike"]
		var vt := Game.speed_from_power(p, b["mass"], b["cda"], _crr(b), g)
		if Game.hp_ratio() < 0.3:
			vt *= 0.92
		vt *= 1.0 + _draft(0)
		if Input.is_action_just_pressed("boost") and boost_charge >= 1.0:
			boost_left = 6.0
			boost_charge = 0.0
			Game.toast.emit("TURBO CHEESE!", Color(1.0, 0.8, 0.2))
		if boost_left > 0.0:
			boost_left -= delta
			vt *= 1.28
		else:
			boost_charge = minf(1.0, boost_charge + delta / 40.0)
		me["v"] += (vt - me["v"]) * (1.0 - exp(-1.5 * delta))
		me["lat"] = clampf(me["lat"] + Input.get_axis("steer_left", "steer_right") * 1.1 * delta, -0.4, 0.4)
		me["s"] += me["v"] * delta
		me["phase"] += (Zwift.cadence() if Zwift.cadence() > 1.0 else me["v"] * 14.0) / 60.0 * TAU * delta
		if me["s"] >= length:
			_finish(0)
	# rivals
	var lead := 0.0
	for r in riders:
		lead = maxf(lead, r["s"])
	for k in range(1, riders.size()):
		var r: Dictionary = riders[k]
		if r["done"]:
			r["s"] += 3.0 * delta
			r["phase"] += 6.0 * delta
			continue
		r["surge_in"] -= delta
		if r["surge_in"] <= 0.0:
			r["surge"] = 6.0
			r["surge_in"] = randf_range(30.0, 60.0)
		var pw: float = r["ftp"] * (0.95 + 0.04 * sin(clock * 0.21 + r["wiggle"]))
		pw *= 1.0 - 0.00001 * r["s"]  # slow fade
		if r["surge"] > 0.0:
			r["surge"] -= delta
			pw *= 1.15
		var gap: float = r["s"] - me["s"]
		if gap > 300.0:
			pw *= 0.95
		elif gap < -300.0:
			pw *= 1.05
		r["power"] = pw
		var bk: Dictionary = r["bike"]
		var vt := Game.speed_from_power(pw, bk["mass"], bk["cda"], _crr(bk), _grade_at(r["s"]), r["mass"])
		r["v"] += (vt - r["v"]) * (1.0 - exp(-1.5 * delta))
		r["s"] += r["v"] * delta
		r["lat"] = r["lane"] + sin(clock * 0.6 + r["wiggle"]) * 0.08
		r["phase"] += r["v"] * 14.0 / 60.0 * TAU * delta
		if r["s"] >= length:
			_finish(k)
	if finish_count > 0 and not over:
		over_clock += delta
	if not over and (finish_count >= riders.size() or (me["done"] and over_clock > 10.0) or over_clock > 420.0):
		_end_race()


func _crr(b: Dictionary) -> float:
	return float(b["crr"]) + Game.GRAVEL_EXTRA_CRR * float(b.get("gravel", 1.0))


func _draft(i: int) -> float:
	var me: Dictionary = riders[i]
	for k in riders.size():
		if k == i:
			continue
		var o: Dictionary = riders[k]
		var d: float = o["s"] - me["s"]
		if d > 1.0 and d < 9.0 and absf(o["lat"] - me["lat"]) < 0.35:
			return 0.05
	return 0.0


func _finish(i: int) -> void:
	var r: Dictionary = riders[i]
	if r["done"]:
		return
	r["done"] = true
	r["time"] = clock
	finish_count += 1
	r["place"] = finish_count
	if i == 0:
		player_finish_time = clock
		Game.toast.emit("FINISHED!  Place #%d" % finish_count, Color(1.0, 0.9, 0.3))
		if finish_count == 1:
			for k in 2:
				Talk.say(randi() % Talk.rivals.size(), "race_win_player", true)
		else:
			for o in riders:
				if o.get("place", 0) == 1 and not o["player"]:
					Talk.say(int(o["idx"]), "race_lose_player", true)
	elif finish_count == 1:
		Talk.say(int(r["idx"]), "race_win_rival", true)


func _banter() -> void:
	var me: Dictionary = riders[0]
	if me["done"]:
		return
	var leader := true
	for k in range(1, riders.size()):
		var r: Dictionary = riders[k]
		if r["s"] > me["s"]:
			leader = false
		var sign_now: bool = r["s"] > me["s"]
		if last_swap.has(k) and last_swap[k]["ahead"] != sign_now and clock - last_swap[k]["t"] > 6.0 and absf(r["s"] - me["s"]) < 20.0:
			last_swap[k] = {"ahead": sign_now, "t": clock}
			if sign_now:
				Talk.say(int(r["idx"]), "race_pass_player")
			else:
				Talk.say(int(r["idx"]), "race_player_pass")
		elif not last_swap.has(k):
			last_swap[k] = {"ahead": sign_now, "t": clock}
	if leader:
		lead_clock += get_process_delta_time()
		if lead_clock > 12.0:
			lead_clock = 0.0
			Talk.say_random("race_leading")
	else:
		lead_clock = 0.0


func _end_race() -> void:
	over = true
	active = false
	Zwift.send_grade(0.0)
	var order := riders.duplicate()
	order.sort_custom(func(a, b):
		if a["done"] and b["done"]:
			return a["time"] < b["time"]
		if a["done"] != b["done"]:
			return a["done"]
		return a["s"] > b["s"])
	var place := order.find(riders[0]) + 1
	var shares := [1.0, 0.5, 0.3, 0.15, 0.0, 0.0, 0.0, 0.0]
	var prize := int(float(course["prize"]) * shares[place - 1])
	var names: Array = []
	for r in order:
		names.append(r["name"])
	if place == 1:
		Game.race_wins += 1
	Game.add_money(prize)
	Game.damage_bike(12.0)
	Game.save_game()
	finished.emit({"place": place, "time": riders[0]["time"] if riders[0]["done"] else clock, "prize": prize, "order": names, "course": course["name"]})


# ---------------------------------------------------------------------
# HUD data
# ---------------------------------------------------------------------

func standings() -> Array:
	var order := riders.duplicate()
	order.sort_custom(func(a, b): return a["s"] > b["s"])
	return order


func player_place() -> int:
	return standings().find(riders[0]) + 1


func time_gap(r: Dictionary) -> float:
	var me: Dictionary = riders[0]
	var v := maxf(me["v"], 2.0)
	return (r["s"] - me["s"]) / v


# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------

func _draw() -> void:
	if course.is_empty():
		return
	var inv := get_canvas_transform().affine_inverse()
	var vr: Rect2 = inv * get_viewport_rect()
	_draw_sky(vr)

	# bucket riders / trees / deco by diagonal
	var buckets := {}
	for k in riders.size():
		var r: Dictionary = riders[k]
		var pz := _pose(r["s"], r["lat"])
		var d := _diag(pz["pos"])
		if not buckets.has(d):
			buckets[d] = []
		buckets[d].append([0, k, pz])
	for t in trees:
		var d := _diag(t["pos"])
		if not buckets.has(d):
			buckets[d] = []
		buckets[d].append([1, t])
	for e in deco:
		var pz := _pose(e["s"], 0.0)
		var d := _diag(pz["pos"])
		if not buckets.has(d):
			buckets[d] = []
		buckets[d].append([2, e, pz])

	var peak := gain * vz
	var big := vr.grow(160.0)
	for d in range(0, 2 * G - 1):
		for i in range(maxi(0, d - G + 1), mini(G - 1, d) + 1):
			var j := d - i
			var z00 := zgrid[j * (G + 1) + i]
			var z10 := zgrid[j * (G + 1) + i + 1]
			var z11 := zgrid[(j + 1) * (G + 1) + i + 1]
			var z01 := zgrid[(j + 1) * (G + 1) + i]
			var wx := OX + i
			var wy := OX + j
			var center := Iso.to_screen(Vector2(wx + 0.5, wy + 0.5), (z00 + z11) * 0.5)
			if not big.has_point(center):
				continue
			var cx := wx + 0.5
			var cy := wy + 0.5
			var col := _cell_color(cx, cy, (z00 + z10 + z11 + z01) * 0.25, peak)
			var sh := 1.0 + clampf(((z10 - z00) + (z11 - z01) + (z01 - z00) + (z11 - z10)) * 0.006, -0.35, 0.35)
			col = Iso.shade(col, sh)
			draw_colored_polygon(PackedVector2Array([Iso.to_screen(Vector2(wx, wy), z00), Iso.to_screen(Vector2(wx + 1, wy), z10),
				Iso.to_screen(Vector2(wx + 1, wy + 1), z11), Iso.to_screen(Vector2(wx, wy + 1), z01)]), col)
			_cell_detail(i, j, center, (z00 + z11) * 0.5 / maxf(peak, 1.0), col)
		if road_buckets.has(d):
			for si in road_buckets[d]:
				var seg: Dictionary = road_segs[si]
				var e: PackedVector2Array = seg["edge"]
				if not big.has_point(e[0]):
					continue
				draw_colored_polygon(e, Color(0.5, 0.42, 0.33))
				draw_colored_polygon(seg["asphalt"], Iso.shade(Color(0.72, 0.64, 0.52), seg["shade"]))
				for rut in seg["ruts"]:
					draw_colored_polygon(rut, Color(0.6, 0.52, 0.42))
				var pi_ := 0
				for pb in seg["pebbles"]:
					draw_rect(Rect2(pb, Vector2(2, 1)), Color(0.5, 0.44, 0.36) if pi_ % 2 == 0 else Color(0.86, 0.8, 0.68))
					pi_ += 1
		if buckets.has(d):
			for it in buckets[d]:
				match it[0]:
					0: _draw_rider(it[1], it[2])
					1: _draw_tree(it[1])
					2: _draw_deco(it[1], it[2])
	# bubbles on top
	for k in bubbles:
		if k < riders.size():
			var r: Dictionary = riders[k]
			var pz := _pose(r["s"], r["lat"])
			_bubble(Iso.to_screen(pz["pos"], pz["z"]) + Vector2(0, -64), bubbles[k]["text"], r["color"])
	if countdown > 0.0:
		var n := int(ceilf(countdown)) - 1
		var txt := "GO!" if n <= 0 else str(n)
		var c := vr.get_center()
		var sz := 48
		draw_string_outline(font, c + Vector2(-150, -30), txt, HORIZONTAL_ALIGNMENT_CENTER, 300.0, sz, 6, Iso.OUTLINE)
		draw_string(font, c + Vector2(-150, -30), txt, HORIZONTAL_ALIGNMENT_CENTER, 300.0, sz, Color(1.0, 0.9, 0.2))


func _diag(p: Vector2) -> int:
	return clampi(floori(p.x - OX) + floori(p.y - OX), 0, 2 * G - 2)


func _draw_sky(vr: Rect2) -> void:
	var c := vr.get_center()
	var top := Color(0.4, 0.68, 0.95)
	var bottom := Color(0.8, 0.92, 1.0)
	draw_polygon(PackedVector2Array([vr.position - Vector2(50, 50), vr.position + Vector2(vr.size.x + 50, -50), vr.end + Vector2(50, 50), vr.position + Vector2(-50, vr.size.y + 50)]),
		PackedColorArray([top, top, bottom, bottom]))
	draw_circle(c + Vector2(vr.size.x * 0.32, -vr.size.y * 0.32), 70.0, Color(1.0, 0.96, 0.7))
	for k in 5:
		var cp := c + Vector2(fposmod(k * 380.0 + t_ * 8.0, vr.size.x + 400.0) - vr.size.x * 0.5 - 200.0, -vr.size.y * 0.3 + k * 28.0 - 40.0)
		draw_circle(cp, 34.0, Color(1, 1, 1, 0.85))
		draw_circle(cp + Vector2(30, 6), 26.0, Color(1, 1, 1, 0.85))
		draw_circle(cp + Vector2(-30, 8), 24.0, Color(1, 1, 1, 0.85))


## Small pixel details per terrain cell: grass tufts and flowers low down, rocks on the scree.
func _cell_detail(i: int, j: int, center: Vector2, f: float, col: Color) -> void:
	var h := ((i * 73856093) ^ (j * 19349663)) & 0x7fffffff
	var o := Vector2(float(h % 17) - 8.0, float((h >> 5) % 9) - 4.0)
	if f < 0.62:
		for k in 3:
			var p := center + o + Vector2((k - 1) * 9.0, float((h >> (k + 2)) % 5) - 2.0)
			var tc := Iso.shade(col, 0.72)
			draw_line(p, p + Vector2(-2, -3), tc, 1.0)
			draw_line(p, p + Vector2(0, -4), tc, 1.0)
			draw_line(p, p + Vector2(2, -3), tc, 1.0)
		if h % 9 == 0 and f < 0.4:
			draw_rect(Rect2(center - o, Vector2(2, 2)), [Color(1.0, 0.5, 0.75), Color(1.0, 0.92, 0.3), Color(1, 1, 1)][h % 3])
	elif f < 0.86 and h % 3 == 0:
		var rp := center + o
		draw_rect(Rect2(rp - Vector2(3, 2), Vector2(6, 4)), Iso.OUTLINE)
		draw_rect(Rect2(rp - Vector2(2, 1), Vector2(4, 2)), Color(0.68, 0.65, 0.62))
		draw_rect(Rect2(rp - Vector2(2, 1), Vector2(2, 1)), Color(0.85, 0.83, 0.8))


func _cell_color(x: float, y: float, z: float, peak: float) -> Color:
	var f := z / maxf(peak, 1.0)
	if f > 0.86:
		return Color(0.96, 0.97, 1.0)
	if f > 0.66:
		return Color(0.6, 0.57, 0.55).lerp(Color(0.96, 0.97, 1.0), (f - 0.66) / 0.2 * 0.6)
	if f > 0.4:
		return Color(0.2, 0.5, 0.3).lerp(Color(0.6, 0.57, 0.55), (f - 0.4) / 0.26)
	if f < 0.0:
		return Color(0.45, 0.7, 0.4)
	return Color(0.42, 0.78, 0.36).lerp(Color(0.2, 0.5, 0.3), f / 0.4)


func _draw_tree(t: Dictionary) -> void:
	var base := Iso.to_screen(t["pos"], t["z"])
	var s: float = t["s"]
	draw_rect(Rect2(base + Vector2(-2, -9) * s, Vector2(4, 9) * s), Color(0.4, 0.25, 0.15))
	if t["kind"] == 3:
		draw_circle(base + Vector2(0, -20) * s, 10.0 * s, Color(0.75, 0.88, 0.3))
		return
	var g := Color(0.1, 0.45, 0.28)
	for i in 3:
		var y := -9.0 - i * 10.0
		var w := (13.0 - i * 3.5) * s
		var tri := PackedVector2Array([base + Vector2(-w, y * s), base + Vector2(w, y * s), base + Vector2(0, (y - 18.0) * s)])
		draw_colored_polygon(tri, Iso.shade(g, 1.0 + i * 0.15))
		draw_colored_polygon(PackedVector2Array([tri[0], base + Vector2(-w * 0.1, y * s), tri[2]]), Iso.shade(g, 1.35 + i * 0.15))
		tri.append(tri[0])
		draw_polyline(tri, Iso.OUTLINE, 1.0)


func _draw_deco(e: Dictionary, pz: Dictionary) -> void:
	var a: float = pz["a"]
	var radial := Vector2(cos(a), sin(a))
	match e["kind"]:
		"arch":
			var p0: Vector2 = pz["pos"] - radial * 1.1
			var p1: Vector2 = pz["pos"] + radial * 1.1
			var z: float = pz["z"]
			var b0 := Iso.to_screen(p0, z)
			var b1 := Iso.to_screen(p1, z)
			for bp in [b0, b1]:
				draw_line(bp, bp + Vector2(0, -92), Iso.OUTLINE, 5.0)
				draw_line(bp, bp + Vector2(0, -92), Color(0.9, 0.9, 0.95), 3.0)
			var banner := PackedVector2Array([b0 + Vector2(0, -92), b1 + Vector2(0, -92), b1 + Vector2(0, -70), b0 + Vector2(0, -70)])
			draw_colored_polygon(banner, Color(0.95, 0.2, 0.25) if e["label"] == "START" else Color(0.15, 0.15, 0.2))
			var bo := banner.duplicate()
			bo.append(bo[0])
			draw_polyline(bo, Iso.OUTLINE, 1.0)
			var mid := (b0 + b1) * 0.5 + Vector2(-60, -76)
			draw_string(font, mid + Vector2(0, -2), e["label"], HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12, Color.WHITE)
		"sign":
			var b := Iso.to_screen(pz["pos"] + radial * 1.1, pz["z"])
			draw_line(b, b + Vector2(0, -26), Color(0.4, 0.3, 0.2), 3.0)
			draw_rect(Rect2(b + Vector2(-24, -42), Vector2(48, 18)), Color(1.0, 0.85, 0.2))
			draw_string(font, b + Vector2(-24, -29), e["label"], HORIZONTAL_ALIGNMENT_CENTER, 48.0, 8, Color(0.1, 0.1, 0.15))
		"fan":
			var p: Vector2 = pz["pos"] + radial * float(e["side"]) * float(e["off"])
			var b := Iso.to_screen(p, _fan_z(p))
			draw_line(b, b + Vector2(0, -14), e["col"], 5.0)
			draw_circle(b + Vector2(0, -19), 4.0, Color(0.95, 0.8, 0.65))
			var wave := sin(t_ * 8.0 + p.x * 3.0) * 5.0
			draw_line(b + Vector2(0, -13), b + Vector2(7, -24 + wave), e["col"], 2.0)


func _fan_z(p: Vector2) -> float:
	return terrain_z(p.x, p.y)


## A rival's name is hidden when another rider (or you) is within a few metres, to keep the pack readable.
func _crowded(k: int) -> bool:
	for o in riders.size():
		if o != k and absf(float(riders[o]["s"]) - float(riders[k]["s"])) < 4.0 and (o < k or riders[o]["player"]):
			return true
	return false


func _draw_rider(k: int, pz: Dictionary) -> void:
	var r: Dictionary = riders[k]
	var s: float = r["s"]
	var pa := _pose(s - 0.8, r["lat"])
	var pb := _pose(s + 0.8, r["lat"])
	var sa := Iso.to_screen(pa["pos"], pa["z"])
	var sb := Iso.to_screen(pb["pos"], pb["z"])
	var ds := (sb - sa)
	if ds.length() < 0.01:
		ds = Vector2(1, 0.3)
	var c := Iso.to_screen(pz["pos"], pz["z"])
	BikeDraw.draw(self, c, ds, r["frame"], r["color"], r["phase"], true, "YOU" if r["player"] else r["short"])
	if r["player"] or not _crowded(k):
		var label: String = "YOU" if r["player"] else r["short"]
		var outline_col: Color = Color(1, 1, 1) if r["player"] else r["color"]
		var p := c + Vector2(-100, -54)
		draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8, 4, Iso.OUTLINE)
		draw_string(font, p, label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8, outline_col)
	var dust := clampf(float(r["v"]) / 5.0, 0.0, 1.0)
	for q in 3:
		var puff := c - ds.normalized() * (16.0 + q * 11.0) + Vector2(0, -6 - q * 5 - sin(t_ * 4.0 + q + k) * 2.0)
		draw_circle(puff, 5.0 + q * 2.5, Color(0.8, 0.72, 0.58, 0.32 * dust * (1.0 - q * 0.28)))
	if boost_left > 0.0 and r["player"]:
		for q in 4:
			draw_circle(c - ds.normalized() * (20.0 + q * 9.0) + Vector2(0, -14), 5.0 - q, Color(1.0, 0.8 - q * 0.15, 0.2, 0.8))


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
	draw_colored_polygon(PackedVector2Array([anchor + Vector2(-3, -7), anchor + Vector2(3, -7), anchor + Vector2(0, -2)]), col)
	for i in lines.size():
		draw_string(font, tl + Vector2(5, 10 + i * 10), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.1, 0.1, 0.15))
