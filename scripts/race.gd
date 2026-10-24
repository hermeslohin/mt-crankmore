extends Node2D
## Mt. Crankmore gravel race: long switchbacks zig-zag up a big isometric mountainside, with rolling ups and downs,
## jumps, fallen trees, creek fords and wildlife. The map is built at about the town's scale (a few metres per tile),
## so riding speed looks the same as in town. Player power drives speed through a real power/grade/drag model;
## the trainer gets the grade (plus a kick over logs and through creeks).

signal finished(result: Dictionary)

const COURSES := [
	{"name": "Foothill Gravel Grind", "length": 6000.0, "grade": 0.04, "roll": 1.3, "entry": 40, "prize": 500, "seed": 7,
		"blurb": "6 km of rolling gravel switchbacks with jumps, creek crossings and fallen trees, about 20 minutes for the front of the pack. Full of squirrels. And deer. And a bear or two."},
	{"name": "Summit Gravel Showdown", "length": 4400.0, "grade": 0.065, "roll": 1.2, "entry": 100, "prize": 1200, "seed": 21,
		"blurb": "4.4 km of steep gravel to the top of Mt. Crankmore with ramps up to 12%, short plunges, logs and bears, about 20 minutes. Legends are made here. So are blisters."},
]
const MAX_GRADE := 0.12
const MIN_GRADE := -0.07
const M_PER_TILE := 3.3       # metres of road per tile (the town is about 3.2), so speeds look the same
const PX_PER_M := 12.0        # screen lift per metre of height
const LEG_GAP := 16.0         # tiles between switchback legs
const HAIRPIN_R := 8.0
const STEP := 0.5             # road sample spacing (tiles)
const VIEW_R := 17            # terrain cells drawn around the player
const MAX_SPEED := 16.0       # m/s cap on the descents
const FORD_HALF := 2.5        # metres of water either side of a ford's centre
const FORD_CRR := 0.05        # extra rolling resistance while wading
const WATER := Color(0.3, 0.62, 0.92)

var active := false
var course: Dictionary = {}
var M := 2                    # road samples
var pts := PackedVector2Array()       # road centre line (world tiles)
var nrm := PackedVector2Array()       # unit normal of the road at each sample
var s_m := PackedFloat32Array()
var elev := PackedFloat32Array()      # metres, lowest point = 0
var grade_a := PackedFloat32Array()
var ds_m := 1.0                       # metres between road samples
var vz := PX_PER_M
var gain := 100.0                     # highest road elevation (m)
var legs_n := 3
var leg_len := 100.0
var leg_wob: Array = []
var leg_elev: Array = []              # per leg: road elevation (m) per grid column
var gw := 1
var gh := 1
var ox := 0
var oy := 0
var zgrid := PackedFloat32Array()     # terrain height (px) at cell corners
var rdist := PackedFloat32Array()     # tiles to the road at cell corners (99 = far)
var cell_col := PackedColorArray()
var cell_kind := PackedByteArray()    # 0 bare, 1 meadow, 2 forest floor, 3 scree
var peak := 1.0
var streams: Array = []
var stream_buckets: Dictionary = {}
var road_segs: Array = []
var road_buckets: Dictionary = {}
var statics: Dictionary = {}          # depth diagonal -> [[type, data, cell x], ...]
var obstacles: Array = []             # {kind: jump | log | ford, s}, sorted by s
var fords := PackedFloat32Array()
var animals: Array = []
var pops: Array = []
var riders: Array = []
var clock := 0.0
var countdown := 0.0
var over := false
var over_clock := 0.0
var finish_count := 0
var givers: Array = []                # power-up people along the course {s, lat, shirt, skin, hair, phase}, sorted by s
var frisbees: Array = []              # pizzas in flight {"from", "to", "u"} (rider indices)
var stamina := 1.0
var kick_t := 0.0
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
	var rng := RandomNumberGenerator.new()
	rng.seed = int(course["seed"])
	_build_road(rng)
	_build_streams(rng)
	_build_terrain()
	_build_features(rng)
	_build_flora(rng)
	_build_stream_geometry()
	_build_road_geometry()
	_build_animals(rng)
	_build_givers(rng)
	_build_riders()
	clock = 0.0
	countdown = 4.0
	over = false
	over_clock = 0.0
	finish_count = 0
	frisbees.clear()
	stamina = 1.0
	kick_t = 0.0
	lead_clock = 0.0
	last_swap.clear()
	bubbles.clear()
	pops.clear()
	player_finish_time = 0.0
	# pre-race jabber
	var ids := range(Talk.rivals.size())
	ids.shuffle()
	for k in mini(3, ids.size()):
		get_tree().create_timer(1.0 + k * 1.2).timeout.connect(Talk.say.bind(ids[k], "race_start", true))


## Switchbacks: legs run along +x / -x, each one LEG_GAP tiles further up the mountain (towards -y, away from the
## camera, so the slope never hides you), joined by hairpins. Leg 0 is at the bottom.
func _build_road(rng: RandomNumberGenerator) -> void:
	var length: float = course["length"]
	var target := length / M_PER_TILE
	legs_n = maxi(3, roundi(target / 185.0))
	leg_len = (target - (legs_n - 1) * PI * HAIRPIN_R) / (legs_n * 1.04)
	leg_wob.clear()
	for k in legs_n:
		leg_wob.append([rng.randf_range(1.6, 2.8), rng.randf_range(0.045, 0.08), rng.randf() * TAU,
			rng.randf_range(0.5, 1.2), rng.randf_range(0.13, 0.2), rng.randf() * TAU])
	var poly := PackedVector2Array()
	var poly_leg := PackedInt32Array()
	for k in legs_n:
		var fwd := k % 2 == 0
		var n := int(leg_len * 2.0)
		for q in n + 1:
			var x := leg_len * (q / float(n) if fwd else 1.0 - q / float(n))
			poly.append(Vector2(x, leg_y(k, x)))
			poly_leg.append(k)
		if k < legs_n - 1:
			var c := Vector2(leg_len if fwd else 0.0, _leg_base(k) - HAIRPIN_R)
			for q in range(1, 48):
				var a := PI * q / 48.0
				poly.append(c + Vector2(sin(a) * HAIRPIN_R * (1.0 if fwd else -1.0), cos(a) * HAIRPIN_R))
				poly_leg.append(-1)
	var cum := PackedFloat32Array()
	cum.resize(poly.size())
	for i in range(1, poly.size()):
		cum[i] = cum[i - 1] + poly[i].distance_to(poly[i - 1])
	var total := cum[poly.size() - 1]
	M = int(total / STEP) + 2
	pts.resize(M)
	nrm.resize(M)
	s_m.resize(M)
	elev.resize(M)
	grade_a.resize(M)
	var sample_leg := PackedInt32Array()
	sample_leg.resize(M)
	var j := 0
	for i in M:
		var d := total * i / float(M - 1)
		while j < poly.size() - 2 and cum[j + 1] < d:
			j += 1
		pts[i] = poly[j].lerp(poly[j + 1], clampf(inverse_lerp(cum[j], cum[j + 1], d), 0.0, 1.0))
		sample_leg[i] = poly_leg[j] if poly_leg[j] == poly_leg[j + 1] else -1
	for i in M:
		var tng := (pts[mini(i + 1, M - 1)] - pts[maxi(i - 1, 0)]).normalized()
		nrm[i] = Vector2(-tng.y, tng.x)
	# rolling profile: long climbs broken up by short plunges and steep kickers
	ds_m = length / float(M - 1)
	var g0: float = course["grade"]
	var amp: float = course["roll"]
	var p0 := rng.randf() * TAU
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var e := 0.0
	var lo := 0.0
	for i in M:
		var s := i * ds_m
		s_m[i] = s
		var g := g0 * (1.0 + amp * sin(TAU * s / 650.0 + p0) + 0.45 * amp * sin(TAU * s / 230.0 + p1) + 0.25 * sin(TAU * s / 97.0 + p2))
		g = lerpf(0.01, clampf(g, MIN_GRADE, MAX_GRADE), smoothstep(0.0, 120.0, s))
		grade_a[i] = g
		if i > 0:
			e += g * ds_m
		elev[i] = e
		lo = minf(lo, e)
	gain = 1.0
	for i in M:
		elev[i] -= lo
		gain = maxf(gain, elev[i])
	vz = PX_PER_M
	# terrain grid around the switchbacks
	ox = -int(HAIRPIN_R) - 14
	oy = -18
	gw = int(leg_len) + 2 * (int(HAIRPIN_R) + 14) + 1
	gh = int((legs_n - 1) * LEG_GAP) + 34
	# road elevation of each leg per grid column, for the hillside between legs
	leg_elev.clear()
	for k in legs_n:
		var a := PackedFloat32Array()
		a.resize(gw + 1)
		a.fill(-1.0e9)
		for i in M:
			if sample_leg[i] == k:
				a[clampi(roundi(pts[i].x - ox), 0, gw)] = elev[i]
		var first := 0
		while first < gw and a[first] < -1.0e8:
			first += 1
		for c in gw + 1:
			if c < first:
				a[c] = a[first]
			elif a[c] < -1.0e8:
				a[c] = a[c - 1]
		leg_elev.append(a)


func _leg_base(k: int) -> float:
	return (legs_n - 1 - k) * LEG_GAP


func leg_y(k: int, x: float) -> float:
	var w: Array = leg_wob[k]
	var win := smoothstep(0.0, 16.0, x) * smoothstep(0.0, 16.0, leg_len - x)
	return _leg_base(k) + win * (float(w[0]) * sin(x * float(w[1]) + float(w[2])) + float(w[3]) * sin(x * float(w[4]) + float(w[5])))


func _leg_e(k: int, ci: int, cf: float) -> float:
	var a: PackedFloat32Array = leg_elev[k]
	return lerpf(a[ci], a[ci + 1], cf)


## Hillside height (m) without the bumps: blends between the legs above and below, falls away under the start
## and climbs to the summit above the finish.
func _base_m(x: float, y: float) -> float:
	var xc := clampf(x, 0.0, leg_len)
	var c := clampf(x - ox, 0.0, gw - 0.001)
	var ci := int(c)
	var cf := c - ci
	var y0 := leg_y(0, xc)
	if y >= y0:
		return _leg_e(0, ci, cf) - (y - y0) * 1.1
	var top := legs_n - 1
	var yt := leg_y(top, xc)
	if y <= yt:
		return _leg_e(top, ci, cf) + (yt - y) * 1.4
	var k := clampi(int(((legs_n - 1) * LEG_GAP - y) / LEG_GAP), 0, legs_n - 2)
	while k > 0 and y > leg_y(k, xc):
		k -= 1
	while k < legs_n - 2 and y < leg_y(k + 1, xc):
		k += 1
	var ya := leg_y(k, xc)
	var yb := leg_y(k + 1, xc)
	return lerpf(_leg_e(k, ci, cf), _leg_e(k + 1, ci, cf), clampf((ya - y) / maxf(ya - yb, 0.1), 0.0, 1.0))


## Knolls, hollows and crags (m).
func _noise_m(x: float, y: float) -> float:
	return 1.6 * sin(x * 0.21 + y * 0.13) * cos(y * 0.24 - x * 0.09) + 0.8 * sin(x * 0.57 + 1.7) * sin(y * 0.49 + 0.3) \
		+ 0.35 * sin(x * 1.3 + y * 1.1)


## > 0 forest, < 0 open meadow.
func _biome(x: float, y: float) -> float:
	return sin(x * 0.083 + 1.3) * cos(y * 0.11 - 0.4) + 0.6 * sin((x + y) * 0.047 + 2.0) + 0.3 * sin(x * 0.23 - y * 0.19)


## Creeks run straight down the mountain (towards the camera) from a spring, crossing every leg below it.
func _build_streams(rng: RandomNumberGenerator) -> void:
	streams.clear()
	for q in 2:
		var ks := rng.randi_range(mini(3, legs_n - 1), mini(6, legs_n - 1))
		streams.append({"x0": leg_len * (rng.randf_range(0.14, 0.42) if q == 0 else rng.randf_range(0.58, 0.86)),
			"a": rng.randf_range(1.5, 2.6), "f": rng.randf_range(0.18, 0.28), "p": rng.randf() * TAU,
			"y0": _leg_base(ks) - LEG_GAP * 0.5, "y1": float(oy + gh)})


func _stream_x(st: Dictionary, y: float) -> float:
	return float(st["x0"]) + float(st["a"]) * sin(y * float(st["f"]) + float(st["p"])) + 0.8 * sin(y * 0.53 + float(st["p"]) * 2.0)


func _stream_d(x: float, y: float) -> float:
	var d := 99.0
	for st in streams:
		if y >= float(st["y0"]) - 0.5 and y <= float(st["y1"]):
			d = minf(d, absf(x - _stream_x(st, y)))
	return d


func _build_terrain() -> void:
	var n1 := gw + 1
	var count := n1 * (gh + 1)
	zgrid.resize(count)
	rdist.resize(count)
	rdist.fill(99.0)
	var re := PackedFloat32Array()
	re.resize(count)
	# distance to the road (and the road's height there) at every corner near it
	for i in range(0, M - 1, 2):
		var a := pts[i]
		var i2 := mini(i + 2, M - 1)
		var b := pts[i2]
		var x0 := clampi(floori(minf(a.x, b.x) - 3.5) - ox, 0, gw)
		var x1 := clampi(ceili(maxf(a.x, b.x) + 3.5) - ox, 0, gw)
		var y0 := clampi(floori(minf(a.y, b.y) - 3.5) - oy, 0, gh)
		var y1 := clampi(ceili(maxf(a.y, b.y) + 3.5) - oy, 0, gh)
		var ab := maxf(a.distance_to(b), 0.001)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var p := Vector2(ox + cx, oy + cy)
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := p.distance_to(q)
				var idx := cy * n1 + cx
				if d < rdist[idx]:
					rdist[idx] = d
					re[idx] = lerpf(elev[i], elev[i2], a.distance_to(q) / ab)
	peak = 1.0
	for cy in gh + 1:
		for cx in n1:
			var x := float(ox + cx)
			var y := float(oy + cy)
			var idx := cy * n1 + cx
			var d := rdist[idx]
			var e := _base_m(x, y) + _noise_m(x, y) * smoothstep(1.0, 4.0, d)
			e -= 0.45 * (1.0 - smoothstep(0.2, 1.6, _stream_d(x, y))) * smoothstep(0.9, 2.5, d)
			if d < 3.5:
				e = lerpf(re[idx], e, smoothstep(0.75, 3.2, d))
			zgrid[idx] = e * vz
			peak = maxf(peak, zgrid[idx])
	cell_col.resize(gw * gh)
	cell_kind.resize(gw * gh)
	for j in gh:
		for i in gw:
			var z00 := zgrid[j * n1 + i]
			var z10 := zgrid[j * n1 + i + 1]
			var z11 := zgrid[(j + 1) * n1 + i + 1]
			var z01 := zgrid[(j + 1) * n1 + i]
			var x := ox + i + 0.5
			var y := oy + j + 0.5
			var zc := (z00 + z10 + z11 + z01) * 0.25
			var f := zc / peak
			var b := _biome(x, y)
			var col: Color
			var kind := 0
			if f > 0.975:
				col = Color(0.96, 0.97, 1.0)
			elif f > 0.93:
				col = Color(0.6, 0.57, 0.55).lerp(Color(0.96, 0.97, 1.0), (f - 0.93) / 0.045 * 0.6)
				kind = 3
			else:
				col = Color(0.46, 0.78, 0.36).lerp(Color(0.22, 0.52, 0.3), smoothstep(-0.4, 0.5, b))
				kind = 2 if b > 0.1 else 1
				if f > 0.88:
					col = Color(0.58, 0.64, 0.38).lerp(Color(0.6, 0.57, 0.55), (f - 0.88) / 0.05)
					kind = 3
				elif f > 0.6:
					col = col.lerp(Color(0.58, 0.64, 0.38), (f - 0.6) / 0.28)
				if _stream_d(x, y) < 1.8:
					col = col.lerp(Color(0.24, 0.56, 0.36), 0.5)
			var sh := 1.0 + clampf(((z10 - z00) + (z11 - z01) + (z01 - z00) + (z11 - z10)) * 0.004, -0.35, 0.35)
			cell_col[j * gw + i] = Iso.shade(col, sh)
			cell_kind[j * gw + i] = kind


## Terrain height (px) anywhere, bilinear over the corner grid.
func _tz(p: Vector2) -> float:
	var fx := clampf(p.x - ox, 0.0, gw - 0.001)
	var fy := clampf(p.y - oy, 0.0, gh - 0.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var i := iy * (gw + 1) + ix
	return lerpf(lerpf(zgrid[i], zgrid[i + 1], tx), lerpf(zgrid[i + gw + 1], zgrid[i + gw + 2], tx), ty)


func _rd(p: Vector2) -> float:
	var fx := clampf(p.x - ox, 0.0, gw - 0.001)
	var fy := clampf(p.y - oy, 0.0, gh - 0.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var i := iy * (gw + 1) + ix
	return lerpf(lerpf(rdist[i], rdist[i + 1], tx), lerpf(rdist[i + gw + 1], rdist[i + gw + 2], tx), ty)


func _clear_of(s: float, gap: float, kind: String = "") -> bool:
	for ob in obstacles:
		if (kind == "" or ob["kind"] == kind) and absf(float(ob["s"]) - s) < gap:
			return false
	return true


## Fords where the creeks cross, jumps on the descents, fallen trees, and the signs, arches and fans.
func _build_features(rng: RandomNumberGenerator) -> void:
	var length: float = course["length"]
	obstacles.clear()
	for st in streams:
		for i in M - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if a.y < float(st["y0"]) or a.y > float(st["y1"]):
				continue
			var fa := a.x - _stream_x(st, a.y)
			var fb := b.x - _stream_x(st, b.y)
			if (fa < 0.0) != (fb < 0.0):
				var s := lerpf(s_m[i], s_m[i + 1], fa / (fa - fb))
				if s > 60.0 and s < length - 40.0 and _clear_of(s, 20.0):
					obstacles.append({"kind": "ford", "s": s})
	var cands: Array = []
	var s := 150.0
	while s < length - 100.0:
		if _grade_at(s) < -0.01 and _grade_at(s + 12.0) < -0.01:
			cands.append(s)
		s += 10.0
	var want := int(length / 700.0)
	var placed := 0
	for _pass in 2:
		while not cands.is_empty() and placed < want:
			var c: float = cands.pop_at(rng.randi() % cands.size())
			if _clear_of(c, 200.0, "jump") and _clear_of(c, 35.0):
				obstacles.append({"kind": "jump", "s": c})
				placed += 1
		# not enough downhill: also build kickers on the flatter bits
		s = 150.0
		while s < length - 100.0:
			if _grade_at(s) < 0.03:
				cands.append(s)
			s += 10.0
	want = int(length / 550.0)
	placed = 0
	for _try in 400:
		if placed >= want:
			break
		var c := rng.randf_range(180.0, length - 90.0)
		if _clear_of(c, 110.0, "log") and _clear_of(c, 35.0):
			obstacles.append({"kind": "log", "s": c, "flip": rng.randf() < 0.5})
			placed += 1
	obstacles.sort_custom(func(a, b): return a["s"] < b["s"])
	fords = PackedFloat32Array()
	for ob in obstacles:
		if ob["kind"] == "ford":
			fords.append(ob["s"])

	statics.clear()
	for ob in obstacles:
		_put_static(4, ob, [])
		var side := 1.0 if int(float(ob["s"])) % 2 == 0 else -1.0
		_put_static(2, {"kind": "warn", "s": float(ob["s"]) - 30.0, "icon": ob["kind"], "side": side}, [])
		if ob["kind"] == "jump":
			for k in 4:
				_put_fan(float(ob["s"]) + rng.randf_range(-6.0, 6.0), (1.0 if k % 2 == 0 else -1.0) * rng.randf_range(1.2, 2.0), rng)
	_put_static(2, {"kind": "arch", "s": 0.0, "label": "START"}, [])
	_put_static(2, {"kind": "arch", "s": length - 2.0, "label": "FINISH"}, [])
	var km := 500.0
	while km < length - 60.0:
		_put_static(2, {"kind": "sign", "s": km, "label": "%.1f km" % (km / 1000.0)}, [])
		km += 500.0
	for k in 18:
		_put_fan(rng.randf_range(0.0, 30.0) if k < 9 else length - rng.randf_range(0.0, 30.0),
			(1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(1.1, 2.4), rng)


func _put_fan(s: float, off: float, rng: RandomNumberGenerator) -> void:
	var p: Vector2 = _pose(s, off)["pos"]
	_put_static(2, {"kind": "fan", "s": s, "pos": p, "z": _tz(p), "col": Color.from_hsv(rng.randf(), 0.7, 0.95)}, [])


## Static things go in the bucket of their depth diagonal (or the deepest one of `shape`).
func _put_static(type: int, data: Dictionary, shape: Array) -> void:
	var p: Vector2 = data["pos"] if data.has("pos") else _pose(float(data.get("s", 0.0)), 0.0)["pos"]
	if data.has("s") and not data.has("pos"):
		data["pz"] = _pose(float(data["s"]), 0.0)
	var d := _diag(p)
	for q in shape:
		d = maxi(d, _diag(q))
	if not statics.has(d):
		statics[d] = []
	statics[d].append([type, data, floori(p.x - ox)])


func _build_flora(rng: RandomNumberGenerator) -> void:
	for j in gh:
		for i in gw:
			var x := ox + i + rng.randf()
			var y := oy + j + rng.randf()
			var p := Vector2(x, y)
			var z := _tz(p)
			var f := z / peak
			var forest := smoothstep(-0.3, 0.6, _biome(x, y))
			var chance := 0.04 + 0.42 * forest
			if f > 0.8:
				chance *= 0.3
			if f > 0.9:
				chance = 0.0
			var roll := rng.randf()
			if _rd(p) < 2.0 or _stream_d(x, y) < 1.0:
				continue
			if roll < chance:
				var kind := rng.randi() % 3
				var r2 := rng.randf()
				if forest < 0.4 and r2 < 0.5:
					kind = 3 if r2 < 0.3 else 4
				elif r2 < 0.04:
					kind = 5
				_put_static(1, {"pos": p, "z": z, "s": rng.randf_range(0.8, 1.4), "kind": kind}, [])
			elif roll < chance + (0.09 if f > 0.85 else 0.015):
				_put_static(3, {"pos": p, "z": z, "size": rng.randf_range(0.6, 1.5), "h": rng.randi()}, [])


func _build_stream_geometry() -> void:
	stream_buckets.clear()
	var k := 0
	for st in streams:
		var y: float = st["y0"]
		var prev := Vector2(_stream_x(st, y), y)
		while y < float(st["y1"]):
			y += 0.5
			var p := Vector2(_stream_x(st, y), y)
			var mid := (prev + p) * 0.5
			k += 1
			if _rd(mid) > 0.95 and mid.x > ox and mid.x < ox + gw:
				var nn := (p - prev).normalized()
				var side := Vector2(-nn.y, nn.x) * (0.16 + 0.2 * clampf((y - float(st["y0"])) / 40.0, 0.0, 1.0))
				var za := _tz(prev) + 1.5
				var zb := _tz(p) + 1.5
				var d := _diag(mid)
				if not stream_buckets.has(d):
					stream_buckets[d] = []
				stream_buckets[d].append({"poly": PackedVector2Array([Iso.to_screen(prev - side, za), Iso.to_screen(p - side, zb),
					Iso.to_screen(p + side, zb), Iso.to_screen(prev + side, za)]), "a": Iso.to_screen(prev, za), "b": Iso.to_screen(p, zb), "k": k})
			prev = p


## Road as a smooth gravel ribbon, pre-projected to screen space and bucketed by depth diagonal.
func _build_road_geometry() -> void:
	road_segs.clear()
	road_buckets.clear()
	for i in M - 1:
		var pa := pts[i]
		var pb := pts[i + 1]
		var ua := nrm[i]
		var ub := nrm[i + 1]
		var za := elev[i] * vz + 1.5
		var zb := elev[i + 1] * vz + 1.5
		var edge := PackedVector2Array([Iso.to_screen(pa - ua * 0.64, za), Iso.to_screen(pb - ub * 0.64, zb),
			Iso.to_screen(pb + ub * 0.64, zb), Iso.to_screen(pa + ua * 0.64, za)])
		var gravel := PackedVector2Array([Iso.to_screen(pa - ua * 0.52, za + 0.3), Iso.to_screen(pb - ub * 0.52, zb + 0.3),
			Iso.to_screen(pb + ub * 0.52, zb + 0.3), Iso.to_screen(pa + ua * 0.52, za + 0.3)])
		var ruts: Array = []
		for off in [-0.25, 0.25]:
			ruts.append(PackedVector2Array([Iso.to_screen(pa + ua * (off - 0.05), za + 0.5), Iso.to_screen(pb + ub * (off - 0.05), zb + 0.5),
				Iso.to_screen(pb + ub * (off + 0.05), zb + 0.5), Iso.to_screen(pa + ua * (off + 0.05), za + 0.5)]))
		var pebbles := PackedVector2Array()
		for k in 3:
			var f := fposmod(i * 0.618 + k * 0.29, 1.0)
			var lat := fposmod(i * 0.377 + k * 0.53, 1.0) * 1.0 - 0.5
			pebbles.append(Iso.to_screen(pa.lerp(pb, f) + ua * lat, lerpf(za, zb, f) + 0.6))
		road_segs.append({"edge": edge, "gravel": gravel, "ruts": ruts, "pebbles": pebbles, "shade": 0.92 + 0.08 * float(i % 2)})
		var d := _diag((pa + pb) * 0.5)
		if not road_buckets.has(d):
			road_buckets[d] = []
		road_buckets[d].append(i)


## Wildlife along the course. Deer, foxes and squirrels may dash across in front of you, bears give chase,
## goats and marmots watch from the rocks, moose wade by the creeks.
func _build_animals(rng: RandomNumberGenerator) -> void:
	animals.clear()
	var length: float = course["length"]
	var s := 130.0
	var last_bear := 0.0
	while s < length - 80.0:
		var f := elev[_idx(s)] / gain
		var kind := ""
		var r := rng.randf()
		if s - last_bear > 1200.0 and f < 0.85:
			kind = "bear"
		elif _near_ford(s, 45.0) and rng.randf() < 0.5:
			kind = "moose"
		elif f > 0.75:
			kind = "goat" if r < 0.35 else ("marmot" if r < 0.65 else ("bear" if r < 0.8 else "deer"))
		else:
			for w in [["deer", 0.3], ["bear", 0.12], ["rabbit", 0.15], ["squirrel", 0.16], ["fox", 0.1], ["moose", 0.06], ["goat", 0.11]]:
				r -= float(w[1])
				if r <= 0.0:
					kind = w[0]
					break
			if kind == "":
				kind = "deer"
		if kind == "bear":
			last_bear = s
		var group := 1
		if kind in ["deer", "goat"]:
			group = rng.randi_range(1, 3)
		elif kind in ["rabbit", "squirrel", "marmot"]:
			group = rng.randi_range(1, 2)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for q in group:
			var ss := s + rng.randf_range(-6.0, 6.0)
			var p: Vector2 = _pose(ss, side * rng.randf_range(1.8, 4.2))["pos"]
			if _rd(p) < 1.4:
				continue
			animals.append({"kind": kind, "pos": p, "home": p, "s": ss, "side": side, "state": "idle", "t": rng.randf() * 3.0,
				"face": 1.0 if rng.randf() < 0.5 else -1.0, "vel": Vector2.ZERO, "phase": rng.randf() * TAU, "run": false,
				"cross": kind in ["deer", "fox", "squirrel"] and q == 0 and rng.randf() < 0.5, "stag": rng.randf() < 0.45,
				"dark": rng.randf() < 0.35, "done": false})
		s += rng.randf_range(80.0, 150.0)


## People along the course handing out power-ups (frisbee, socks, breadsticks) to every rider who passes.
func _build_givers(rng: RandomNumberGenerator) -> void:
	givers.clear()
	var shirts := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(1.0, 0.85, 0.2), Color(0.4, 0.85, 0.4), Color(0.95, 0.55, 0.85)]
	var length: float = course["length"]
	var s := 220.0
	var side := 1.0
	while s < length - 120.0:
		if _clear_of(s, 25.0):
			givers.append({"s": s, "lat": side * 1.25, "shirt": shirts[rng.randi() % shirts.size()],
				"skin": Color(0.96, 0.8, 0.65).lerp(Color(0.55, 0.38, 0.28), rng.randf()), "hair": Color(0.3, 0.2, 0.1).lerp(Color(0.9, 0.8, 0.4), rng.randf()),
				"phase": rng.randf() * TAU})
			side = -side
			s += rng.randf_range(300.0, 420.0)
		else:
			s += 20.0


func _build_riders() -> void:
	riders.clear()
	var b := Game.bike()
	riders.append({"name": Game.player_name, "color": Color(0.95, 0.95, 0.95), "frame": b["color"], "s": 0.0, "v": 0.0, "lat": 0.0,
		"bike": b, "player": true, "phase": 0.0, "done": false, "time": 0.0, "mass": Game.weight_kg, "power": 0.0,
		"air": 0.0, "air_tot": 1.0, "air_h": 0.0, "land": 0.0, "ob": 0, "wet": false,
		"pu": "", "pu_hold": 0.0, "socks": 0.0, "bread": 0.0, "down": 0.0, "gv": 0})
	var n := Talk.rivals.size()
	for i in n:
		var info: Dictionary = Talk.rivals[i]
		var mass := Game.rival_mass(i)
		var lane := (i - (n - 1) * 0.5) * 0.1 + 0.05
		riders.append({"name": info["name"], "short": info["short"], "color": info["color"], "frame": Color(info["color"]).lerp(Color.WHITE, 0.2),
			"s": 0.0, "v": 0.0, "lat": lane, "lane": lane, "bike": Game.rival_bike(info), "player": false,
			"phase": randf() * TAU, "done": false, "time": 0.0, "mass": mass, "ftp": Game.rival_ftp(info, mass), "idx": i,
			"surge": 0.0, "surge_in": randf_range(25.0, 50.0), "power": 0.0, "wiggle": randf() * TAU,
			"air": 0.0, "air_tot": 1.0, "air_h": 0.0, "land": 0.0, "ob": 0, "wet": false,
			"pu": "", "pu_hold": 0.0, "socks": 0.0, "bread": 0.0, "down": 0.0, "gv": 0})


# ---------------------------------------------------------------------
# Pose helpers
# ---------------------------------------------------------------------

func _fi(s: float) -> float:
	return clampf(s / ds_m, 0.0, M - 1.0)


func _idx(s: float) -> int:
	return clampi(roundi(s / ds_m), 0, M - 1)


func _t_of_s(s: float) -> float:
	return _fi(s) / float(M - 1)


func _elev_at_t(t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * (M - 1)
	var i := mini(int(f), M - 2)
	return lerpf(elev[i], elev[i + 1], f - i)


func _grade_at(s: float) -> float:
	return grade_a[_idx(s)]


func _pose(s: float, lat: float) -> Dictionary:
	var f := _fi(s)
	var i := mini(int(f), M - 2)
	var u := f - i
	var n := nrm[i].lerp(nrm[i + 1], u).normalized()
	return {"pos": pts[i].lerp(pts[i + 1], u) + n * lat, "z": lerpf(elev[i], elev[i + 1], u) * vz, "t": f / float(M - 1), "n": n}


func _near_ford(s: float, within: float) -> bool:
	if fords.is_empty():
		return false
	var i := fords.bsearch(s)
	return (i < fords.size() and fords[i] - s < within) or (i > 0 and s - fords[i - 1] < within)


func _air_px(r: Dictionary) -> float:
	if float(r["air"]) <= 0.0:
		return 0.0
	var u := 1.0 - float(r["air"]) / float(r["air_tot"])
	return float(r["air_h"]) * 4.0 * u * (1.0 - u)


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
	_step_animals(delta)
	for k in bubbles.keys():
		bubbles[k]["t"] -= delta
		if bubbles[k]["t"] <= 0.0:
			bubbles.erase(k)
	for i in range(pops.size() - 1, -1, -1):
		pops[i]["t"] -= delta
		if pops[i]["t"] <= 0.0:
			pops.remove_at(i)
	kick_t = maxf(0.0, kick_t - delta)
	var me: Dictionary = riders[0]
	var g := _grade_at(me["s"]) + (0.06 if kick_t > 0.0 else 0.0) + (0.03 if me["wet"] else 0.0)
	Trainer.send_grade(g * 100.0 if countdown <= 0.0 and not me["done"] else 0.0)
	queue_redraw()


func _step_riders(delta: float) -> void:
	var length: float = course["length"]
	# player
	var me: Dictionary = riders[0]
	if not me["done"]:
		var g := _grade_at(me["s"])
		var p := Trainer.power()
		if not Trainer.trainer_live:
			if p > Game.ftp * 1.1:
				stamina = maxf(0.0, stamina - delta * 0.1)
				if stamina <= 0.0:
					p = Game.ftp
			else:
				stamina = minf(1.0, stamina + delta * 0.06)
		me["power"] = p
		var b: Dictionary = me["bike"]
		var vt := Game.speed_from_power(p, b["mass"], b["cda"], _crr(b) + (FORD_CRR if me["wet"] else 0.0), g)
		if Game.hp_ratio() < 0.3:
			vt *= 0.92
		vt *= 1.0 + _draft(0)
		_tick_powerups(0, delta)
		if Input.is_action_just_pressed("powerup"):
			_use_powerup(0)
		if float(me["socks"]) > 0.0:
			vt *= PowerUps.SOCKS_BOOST
		if float(me["down"]) > 0.0:
			vt = 0.0
			me["v"] = move_toward(me["v"], 0.0, 14.0 * delta)
		if float(me["air"]) <= 0.0:   # no traction in the air
			me["v"] += (minf(vt, MAX_SPEED) - me["v"]) * (1.0 - exp(-1.5 * delta))
		me["lat"] = clampf(me["lat"] + Input.get_axis("steer_left", "steer_right") * 1.1 * delta, -0.4, 0.4)
		me["s"] += me["v"] * delta
		me["phase"] += (Trainer.cadence() if Trainer.cadence() > 1.0 else me["v"] * 14.0) / 60.0 * TAU * delta
		_terrain_events(0, delta)
		if me["s"] >= length:
			_finish(0)
	# rivals
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
		var pw: float = r["ftp"] * (float(Game.DIFFICULTIES[Game.difficulty]["race"]) + 0.04 * sin(clock * 0.21 + r["wiggle"]))
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
		var vt := Game.speed_from_power(pw, bk["mass"], bk["cda"], _crr(bk) + (FORD_CRR if r["wet"] else 0.0), _grade_at(r["s"]), r["mass"])
		_tick_powerups(k, delta)
		if r["pu"] != "" and _rival_wants(k):
			_use_powerup(k)
		if float(r["socks"]) > 0.0:
			vt *= PowerUps.SOCKS_BOOST
		if float(r["down"]) > 0.0:
			vt = 0.0
			r["v"] = move_toward(r["v"], 0.0, 14.0 * delta)
		if float(r["air"]) <= 0.0:
			r["v"] += (minf(vt, MAX_SPEED) - r["v"]) * (1.0 - exp(-1.5 * delta))
		r["s"] += r["v"] * delta
		r["lat"] = r["lane"] + sin(clock * 0.6 + r["wiggle"]) * 0.08
		r["phase"] += r["v"] * 14.0 / 60.0 * TAU * delta
		_terrain_events(k, delta)
		if r["s"] >= length:
			_finish(k)
	_step_frisbees(delta)
	_squash()
	if finish_count > 0 and not over:
		over_clock += delta
	if not over and (finish_count >= riders.size() or (me["done"] and over_clock > 10.0) or over_clock > 420.0):
		_end_race()


## Airtime, landings, creek wading and hitting the jumps / logs as a rider reaches them.
func _terrain_events(k: int, delta: float) -> void:
	var r: Dictionary = riders[k]
	var was_air := float(r["air"]) > 0.0
	r["air"] = float(r["air"]) - delta
	if was_air and float(r["air"]) <= 0.0:
		r["land"] = 0.4
	r["land"] = maxf(0.0, float(r["land"]) - delta)
	var wet := _near_ford(r["s"], FORD_HALF)
	if wet and not r["wet"] and r["player"]:
		_pop(k, "SPLASH!", WATER.lightened(0.3))
		if randf() < 0.3:
			Talk.say_random("race_splash")
	r["wet"] = wet
	while int(r["ob"]) < obstacles.size() and float(r["s"]) >= float(obstacles[int(r["ob"])]["s"]):
		var ob: Dictionary = obstacles[int(r["ob"])]
		r["ob"] = int(r["ob"]) + 1
		var v: float = r["v"]
		match ob["kind"]:
			"jump":
				if v >= 3.0:
					r["air_tot"] = clampf(0.25 + v * 0.05, 0.3, 1.0)
					r["air_h"] = clampf(v * v * 0.3, 6.0, 48.0)
					r["air"] = r["air_tot"]
					if r["player"]:
						if v > 8.5:
							_pop(k, "BIG AIR!", Color(1.0, 0.85, 0.2))
							if randf() < 0.5:
								Talk.say_random("race_air")
						else:
							_pop(k, "AIR!", Color(1.0, 0.85, 0.2))
			"log":
				r["air_tot"] = 0.42
				r["air_h"] = 11.0
				r["air"] = 0.42
				r["v"] = v * 0.72
				if r["player"]:
					_pop(k, "HOP!", Color(0.95, 0.7, 0.45))
					kick_t = 1.2
					if randf() < 0.3:
						Talk.say_random("race_log")


func _pop(k: int, text: String, col: Color) -> void:
	pops.append({"k": k, "text": text, "col": col, "t": 1.4})


func _pop_at(p: Vector2, text: String, col: Color) -> void:
	pops.append({"pos": p, "text": text, "col": col, "t": 1.4})


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


# ---------------------------------------------------------------------
# Power-ups (see PowerUps): frisbee, socks and breadsticks, handed out along the course
# ---------------------------------------------------------------------

func _tick_powerups(k: int, delta: float) -> void:
	var r: Dictionary = riders[k]
	r["socks"] = maxf(0.0, float(r["socks"]) - delta)
	r["bread"] = maxf(0.0, float(r["bread"]) - delta)
	r["down"] = maxf(0.0, float(r["down"]) - delta)
	if r["pu"] != "":
		r["pu_hold"] = float(r["pu_hold"]) + delta
	while int(r["gv"]) < givers.size() and float(r["s"]) >= float(givers[int(r["gv"])]["s"]):
		r["gv"] = int(r["gv"]) + 1
		if r["pu"] == "" and float(r["down"]) <= 0.0:
			r["pu"] = PowerUps.pick(PowerUps.RACE)
			r["pu_hold"] = 0.0
			if r["player"]:
				Game.toast.emit("POWER-UP: %s! Press Y." % PowerUps.label(r["pu"]), PowerUps.col(r["pu"]))


## Metres between two riders, counting the sideways gap across the road.
func _gap_m(a: int, b: int) -> float:
	var ra: Dictionary = riders[a]
	var rb: Dictionary = riders[b]
	return Vector2(float(rb["s"]) - float(ra["s"]), (float(rb["lat"]) - float(ra["lat"])) * M_PER_TILE).length()


func _nearest_opponent(k: int, within: float) -> int:
	var best := -1
	var bd := within
	for o in riders.size():
		if o == k or riders[o]["done"] or float(riders[o]["down"]) > 0.0:
			continue
		var d := _gap_m(k, o)
		if d < bd:
			bd = d
			best = o
	return best


func _use_powerup(k: int) -> bool:
	var r: Dictionary = riders[k]
	var kind: String = r["pu"]
	if kind == "" or r["done"] or float(r["down"]) > 0.0:
		return false
	match kind:
		"frisbee":
			var v := _nearest_opponent(k, PowerUps.FRISBEE_RANGE_M)
			if v < 0:
				if r["player"]:
					Game.toast.emit("Nobody within 5 m. Get closer to a rival, then toss!", Color(1.0, 0.8, 0.5))
				return false
			frisbees.append({"from": k, "to": v, "u": 0.0})
		"socks":
			r["socks"] = PowerUps.SOCKS_TIME
			_pop(k, "FIRE SOCKS!", PowerUps.col(kind))
		"breadsticks":
			r["bread"] = PowerUps.BREAD_TIME
			_pop(k, "BREADSTICKS!", PowerUps.col(kind))
	r["pu"] = ""
	return true


func _rival_wants(k: int) -> bool:
	var r: Dictionary = riders[k]
	var hold: float = r["pu_hold"]
	if hold < 1.5:
		return false
	match r["pu"]:
		"frisbee":
			return _nearest_opponent(k, PowerUps.FRISBEE_RANGE_M) >= 0
		"socks":
			return _grade_at(r["s"]) > 0.03 or hold > 12.0
		"breadsticks":
			return _nearest_opponent(k, 10.0) >= 0 or hold > 30.0
	return false


func _knock_down(k: int, secs: float, by: int, how: String) -> void:
	var r: Dictionary = riders[k]
	r["down"] = secs
	_pop(k, "SPLAT!", Color(1.0, 0.5, 0.35))
	if r["player"]:
		Game.toast.emit("%s %s! Down for %d s." % [riders[by]["short"], how, int(secs)], Color(1.0, 0.45, 0.35))
		Talk.say(int(riders[by]["idx"]), "pu_hit_player", true)
	elif riders[by]["player"]:
		Talk.say(int(r["idx"]), "pu_ouch", true)


func _step_frisbees(delta: float) -> void:
	for i in range(frisbees.size() - 1, -1, -1):
		var fz: Dictionary = frisbees[i]
		fz["u"] += delta / 0.45
		if fz["u"] >= 1.0:
			frisbees.remove_at(i)
			var to: int = fz["to"]
			if not riders[to]["done"] and float(riders[to]["down"]) <= 0.0:
				_knock_down(to, PowerUps.DOWN_TIME, fz["from"], "beaned you with a Pizza Frisbee")


## A rider on breadsticks flattens anyone they ride into.
func _squash() -> void:
	for a in riders.size():
		var ra: Dictionary = riders[a]
		if float(ra["bread"]) <= 0.0 or float(ra["down"]) > 0.0 or ra["done"]:
			continue
		for b in riders.size():
			var rb: Dictionary = riders[b]
			if b == a or float(rb["bread"]) > 0.0 or float(rb["down"]) > 0.0 or rb["done"]:
				continue
			if absf(float(rb["s"]) - float(ra["s"])) < 1.8 and absf(float(rb["lat"]) - float(ra["lat"])) < 0.4:
				_knock_down(b, PowerUps.SQUASH_TIME, a, "flattened you with breadstick power")


func _bread_k(t: float) -> float:
	return 1.0 + (PowerUps.BREAD_SCALE - 1.0) * clampf(minf(PowerUps.BREAD_TIME - t, t) / 0.4, 0.0, 1.0) if t > 0.0 else 1.0


func _step_animals(delta: float) -> void:
	var me: Dictionary = riders[0]
	var ms: float = me["s"]
	for a in animals:
		var ds: float = float(a["s"]) - ms
		if absf(ds) > 120.0 and a["state"] != "chase":
			continue
		a["t"] = float(a["t"]) - delta
		a["phase"] = float(a["phase"]) + delta
		var kind: String = a["kind"]
		match a["state"]:
			"idle":
				a["run"] = false
				if not a["done"] and countdown <= 0.0:
					if kind in ["deer", "fox", "squirrel", "rabbit"]:
						if a["cross"] and ds < 22.0 and ds > 2.0:
							_animal_cross(a)
						elif ds < (5.0 if kind in ["squirrel", "rabbit"] else 9.0) and ds > -3.0:
							_animal_flee(a, 1.4)
					elif kind == "bear" and ds < 4.0 and ds > -4.0 and not me["done"]:
						a["state"] = "chase"
						a["cs"] = ms - 10.0
						a["t"] = 6.5
						a["done"] = true
						_pop_at(a["pos"], "ROAR!", Color(1.0, 0.4, 0.3))
						Game.toast.emit("BEAR! PEDAL!!", Color(1.0, 0.45, 0.3))
						Talk.say_random("race_bear", true)
					elif kind in ["goat", "marmot", "moose"] and absf(ds) < 6.0:
						a["done"] = true
						_pop_at(a["pos"], {"goat": "MEHH!", "marmot": "EEP!", "moose": "HRRMPH"}[kind], Color(1, 1, 1))
				if a["state"] == "idle" and float(a["t"]) <= 0.0:
					a["t"] = randf_range(2.0, 5.0)
					var home: Vector2 = a["home"]
					if (a["pos"] as Vector2).distance_to(home) > 0.8:
						a["vel"] = (home - a["pos"]).normalized() * 0.35
					elif randf() < 0.5:
						a["vel"] = Vector2.from_angle(randf() * TAU) * 0.3
					else:
						a["vel"] = Vector2.ZERO
			"flee", "cross":
				a["run"] = true
				if float(a["t"]) <= 0.0:
					if a["state"] == "cross":
						_animal_flee(a, 0.8)
					else:
						a["state"] = "idle"
						a["home"] = a["pos"]
						a["vel"] = Vector2.ZERO
				elif a["state"] == "cross" and not a.get("whoa", false) and absf(ds) < 2.5 and _rd(a["pos"]) < 0.7 and not me["done"]:
					a["whoa"] = true
					me["v"] = float(me["v"]) * 0.85
					_pop(0, "WHOA!", Color(1.0, 0.6, 0.3))
			"chase":
				a["run"] = true
				var cs: float = a["cs"]
				var vb := clampf(float(me["v"]) * 1.04 + 0.35, 2.5, 10.0)
				cs += vb * delta
				a["cs"] = cs
				a["s"] = cs
				var pz := _pose(cs, float(a["side"]) * 0.3)
				var np: Vector2 = pz["pos"]
				_face(a, np - a["pos"])
				a["pos"] = np
				a["vel"] = Vector2.ZERO
				if ms - cs < 1.6 and not me["done"]:
					Game.damage_bike(3.0)
					me["v"] = float(me["v"]) * 0.8
					Game.toast.emit("SWIPE! The bear wants your pizza!", Color(1.0, 0.45, 0.3))
					a["t"] = 0.0
				if float(a["t"]) <= 0.0 or me["done"]:
					a["state"] = "roar"
					a["t"] = 1.8
					_pop_at(a["pos"], "GRRR...", Color(1.0, 0.6, 0.4))
			"roar":
				a["run"] = false
				if float(a["t"]) <= 0.0:
					a["state"] = "idle"
					a["home"] = _pose(a["s"], float(a["side"]) * 2.5)["pos"]
					a["t"] = 0.0
		var vel: Vector2 = a["vel"]
		if vel.length() > 0.01:
			a["pos"] = (a["pos"] as Vector2) + vel * delta
			_face(a, vel)


func _face(a: Dictionary, dir: Vector2) -> void:
	var sx := dir.x - dir.y
	if absf(sx) > 0.001:
		a["face"] = signf(sx)


func _animal_cross(a: Dictionary) -> void:
	var target: Vector2 = _pose(float(a["s"]) + 2.0, -float(a["side"]) * 3.2)["pos"]
	var speed: float = {"deer": 4.5, "fox": 4.0, "squirrel": 3.0}.get(a["kind"], 3.5)
	a["state"] = "cross"
	a["vel"] = (target - a["pos"]).normalized() * speed
	a["t"] = (a["pos"] as Vector2).distance_to(target) / speed
	a["done"] = true
	if a["kind"] == "deer":
		_pop_at(a["pos"], "DEER!", Color(1.0, 0.85, 0.5))
		if randf() < 0.35:
			Talk.say_random("race_wildlife")
	elif a["kind"] == "fox":
		_pop_at(a["pos"], "FOX!", Color(1.0, 0.6, 0.3))


func _animal_flee(a: Dictionary, dur: float) -> void:
	var away: Vector2 = _pose(a["s"], float(a["side"]))["n"] * float(a["side"])
	if a["state"] == "cross":
		away = (a["vel"] as Vector2).normalized()
	var speed: float = {"deer": 4.0, "fox": 3.5, "rabbit": 3.0, "squirrel": 2.5}.get(a["kind"], 3.0)
	a["state"] = "flee"
	a["vel"] = (away + Vector2.from_angle(randf() * TAU) * 0.3).normalized() * speed
	a["t"] = dur
	a["done"] = true


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
	Trainer.send_grade(0.0)
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


## Dev helper: race positions worth a screenshot (just before the first of each obstacle, a bear, the finish).
func debug_spots() -> Array:
	var out: Array = [40.0]
	for kind in ["jump", "log", "ford"]:
		for ob in obstacles:
			if ob["kind"] == kind:
				out.append(float(ob["s"]) - (6.0 if kind == "jump" else 3.0))
				break
	for want in ["bear", "deer", "moose"]:
		for a in animals:
			if a["kind"] == want and (want != "deer" or a["cross"]):
				out.append(float(a["s"]) - (2.0 if want == "bear" else (16.0 if want == "deer" else 4.0)))
				break
	out.append(float(course["length"]) - 25.0)
	return out


func debug_place(s: float) -> void:
	countdown = 0.0
	for k in riders.size():
		var r: Dictionary = riders[k]
		r["s"] = s - k * 3.0
		r["v"] = 9.0
		r["ob"] = 0
		while int(r["ob"]) < obstacles.size() and float(obstacles[int(r["ob"])]["s"]) < r["s"]:
			r["ob"] = int(r["ob"]) + 1
		r["gv"] = 0
		while int(r["gv"]) < givers.size() and float(givers[int(r["gv"])]["s"]) < r["s"]:
			r["gv"] = int(r["gv"]) + 1


# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------

func _draw() -> void:
	if course.is_empty():
		return
	var inv := get_canvas_transform().affine_inverse()
	var vr: Rect2 = inv * get_viewport_rect()
	_draw_sky(vr)
	var me_pos: Vector2 = _pose(riders[0]["s"], 0.0)["pos"] if not riders.is_empty() else pts[0]
	var ci := floori(me_pos.x - ox)
	var cj := floori(me_pos.y - oy)
	var i0 := maxi(0, ci - VIEW_R)
	var i1 := mini(gw - 1, ci + VIEW_R)
	var j0 := maxi(0, cj - VIEW_R)
	var j1 := mini(gh - 1, cj + VIEW_R)

	# moving things: riders and animals
	var buckets := {}
	for k in riders.size():
		var r: Dictionary = riders[k]
		var pz := _pose(r["s"], r["lat"])
		var d := _diag(pz["pos"])
		if not buckets.has(d):
			buckets[d] = []
		buckets[d].append([0, k, pz])
	for a in animals:
		var p: Vector2 = a["pos"]
		if absf(p.x - me_pos.x) > VIEW_R or absf(p.y - me_pos.y) > VIEW_R:
			continue
		var d := _diag(p)
		if not buckets.has(d):
			buckets[d] = []
		buckets[d].append([1, a])
	for g in givers:
		if absf(float(g["s"]) - float(riders[0]["s"])) > 140.0:
			continue
		var gp := _pose(g["s"], g["lat"])
		var d := _diag(gp["pos"])
		if not buckets.has(d):
			buckets[d] = []
		buckets[d].append([2, g, gp])

	# flat ground first (terrain, creeks, road, fords): the mountainside faces the camera, so nothing on the
	# ground needs to hide the road. Then everything standing up, back to front.
	var big := vr.grow(160.0)
	var n1 := gw + 1
	var d0 := i0 + j0
	var d1 := i1 + j1
	for d in range(d0, d1 + 1):
		for i in range(maxi(i0, d - j1), mini(i1, d - j0) + 1):
			var j := d - i
			var z00 := zgrid[j * n1 + i]
			var z10 := zgrid[j * n1 + i + 1]
			var z11 := zgrid[(j + 1) * n1 + i + 1]
			var z01 := zgrid[(j + 1) * n1 + i]
			var wx := ox + i
			var wy := oy + j
			var center := Iso.to_screen(Vector2(wx + 0.5, wy + 0.5), (z00 + z11) * 0.5)
			if not big.has_point(center):
				continue
			var col := cell_col[j * gw + i]
			# a quad primitive needs no triangulation, so steep cells that fold over still draw
			draw_primitive(PackedVector2Array([Iso.to_screen(Vector2(wx, wy), z00), Iso.to_screen(Vector2(wx + 1, wy), z10),
				Iso.to_screen(Vector2(wx + 1, wy + 1), z11), Iso.to_screen(Vector2(wx, wy + 1), z01)]), PackedColorArray([col]), PackedVector2Array())
			_cell_detail(i, j, center, cell_kind[j * gw + i], col)
	for d in range(d0, d1 + 1):
		if stream_buckets.has(d):
			for sg in stream_buckets[d]:
				var a: Vector2 = sg["a"]
				if not big.has_point(a):
					continue
				draw_colored_polygon(sg["poly"], WATER)
				if (int(sg["k"]) + int(t_ * 5.0)) % 4 == 0:
					draw_line(a, sg["b"], Color(0.85, 0.95, 1.0), 1.0)
	for d in range(d0, d1 + 1):
		if road_buckets.has(d):
			for si in road_buckets[d]:
				var seg: Dictionary = road_segs[si]
				var e: PackedVector2Array = seg["edge"]
				if not big.has_point(e[0]):
					continue
				draw_colored_polygon(e, Color(0.5, 0.42, 0.33))
				draw_colored_polygon(seg["gravel"], Iso.shade(Color(0.72, 0.64, 0.52), seg["shade"]))
				for rut in seg["ruts"]:
					draw_colored_polygon(rut, Color(0.6, 0.52, 0.42))
				var pi_ := 0
				for pb in seg["pebbles"]:
					draw_rect(Rect2(pb, Vector2(2, 1)), Color(0.5, 0.44, 0.36) if pi_ % 2 == 0 else Color(0.86, 0.8, 0.68))
					pi_ += 1
	for d in range(d0, d1 + 1):
		if statics.has(d):
			for it in statics[d]:
				if it[0] == 4 and it[1]["kind"] == "ford" and int(it[2]) >= i0 - 3 and int(it[2]) <= i1 + 3:
					_draw_obstacle(it[1])
	for d in range(d0, d1 + 1):
		if statics.has(d):
			for it in statics[d]:
				if int(it[2]) < i0 - 3 or int(it[2]) > i1 + 3 or (it[0] == 4 and it[1]["kind"] == "ford"):
					continue
				match it[0]:
					1: _draw_tree(it[1])
					2: _draw_deco(it[1])
					3: _draw_rock(it[1])
					4: _draw_obstacle(it[1])
		if buckets.has(d):
			for it in buckets[d]:
				match it[0]:
					0: _draw_rider(it[1], it[2])
					1: _draw_animal(it[1])
					2: _draw_giver(it[1], it[2])
	_draw_birds(me_pos)
	for fz in frisbees:
		var ra: Dictionary = riders[int(fz["from"])]
		var rb: Dictionary = riders[int(fz["to"])]
		var pa := _pose(ra["s"], ra["lat"])
		var pb := _pose(rb["s"], rb["lat"])
		PowerUps.draw_frisbee(self, Iso.to_screen(pa["pos"], pa["z"] + 22.0), Iso.to_screen(pb["pos"], pb["z"] + 16.0), fz["u"], t_)
	# speech bubbles and pop-ups on top
	for k in bubbles:
		if k < riders.size():
			var r: Dictionary = riders[k]
			var pz := _pose(r["s"], r["lat"])
			_bubble(Iso.to_screen(pz["pos"], pz["z"] + _air_px(r)) + Vector2(0, -64), bubbles[k]["text"], r["color"])
	for pp in pops:
		var at: Vector2
		if pp.has("k"):
			var r: Dictionary = riders[int(pp["k"])]
			var pz := _pose(r["s"], r["lat"])
			at = Iso.to_screen(pz["pos"], pz["z"] + _air_px(r)) + Vector2(0, -48)
		else:
			at = Iso.to_screen(pp["pos"], _tz(pp["pos"])) + Vector2(0, -26)
		at.y -= (1.4 - float(pp["t"])) * 18.0
		var c: Color = pp["col"]
		c.a = clampf(float(pp["t"]) * 2.0, 0.0, 1.0)
		draw_string_outline(font, at + Vector2(-80, 0), pp["text"], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 10, 4, Iso.fa(Iso.OUTLINE, c.a))
		draw_string(font, at + Vector2(-80, 0), pp["text"], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 10, c)
	if countdown > 0.0:
		var n := int(ceilf(countdown)) - 1
		var txt := "GO!" if n <= 0 else str(n)
		var c := vr.get_center()
		var sz := 48
		draw_string_outline(font, c + Vector2(-150, -30), txt, HORIZONTAL_ALIGNMENT_CENTER, 300.0, sz, 6, Iso.OUTLINE)
		draw_string(font, c + Vector2(-150, -30), txt, HORIZONTAL_ALIGNMENT_CENTER, 300.0, sz, Color(1.0, 0.9, 0.2))


func _diag(p: Vector2) -> int:
	return clampi(floori(p.x - ox) + floori(p.y - oy), 0, gw + gh - 2)


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


## Small pixel details per terrain cell: grass tufts and flowers in the meadows, needles and cones under the
## trees, rocks on the scree.
func _cell_detail(i: int, j: int, center: Vector2, kind: int, col: Color) -> void:
	var h := ((i * 73856093) ^ (j * 19349663)) & 0x7fffffff
	var o := Vector2(float(h % 17) - 8.0, float((h >> 5) % 9) - 4.0)
	match kind:
		1:
			for k in 3:
				var p := center + o + Vector2((k - 1) * 9.0, float((h >> (k + 2)) % 5) - 2.0)
				var tc := Iso.shade(col, 0.72)
				draw_line(p, p + Vector2(-2, -3), tc, 1.0)
				draw_line(p, p + Vector2(0, -4), tc, 1.0)
				draw_line(p, p + Vector2(2, -3), tc, 1.0)
			if h % 4 == 0:
				draw_rect(Rect2(center - o, Vector2(2, 2)), [Color(1.0, 0.5, 0.75), Color(1.0, 0.92, 0.3), Color(1, 1, 1), Color(0.6, 0.6, 1.0)][(h >> 3) % 4])
				draw_rect(Rect2(center - o + Vector2(5, 2), Vector2(2, 2)), [Color(1.0, 0.92, 0.3), Color(1, 1, 1)][(h >> 4) % 2])
		2:
			var nc := Iso.shade(col, 0.8)
			draw_line(center + o, center + o + Vector2(3, 1), nc, 1.0)
			draw_line(center - o, center - o + Vector2(-3, 1), nc, 1.0)
			if h % 5 == 0:
				draw_rect(Rect2(center + o * 0.5, Vector2(2, 2)), Color(0.5, 0.32, 0.18))
		3:
			if h % 3 == 0:
				var rp := center + o
				draw_rect(Rect2(rp - Vector2(3, 2), Vector2(6, 4)), Iso.OUTLINE)
				draw_rect(Rect2(rp - Vector2(2, 1), Vector2(4, 2)), Color(0.68, 0.65, 0.62))
				draw_rect(Rect2(rp - Vector2(2, 1), Vector2(2, 1)), Color(0.85, 0.83, 0.8))


func _draw_tree(t: Dictionary) -> void:
	var base := Iso.to_screen(t["pos"], t["z"])
	var s: float = t["s"]
	match int(t["kind"]):
		3:
			draw_rect(Rect2(base + Vector2(-2, -9) * s, Vector2(4, 9) * s), Color(0.4, 0.25, 0.15))
			draw_circle(base + Vector2(0, -20) * s, 11.0 * s, Iso.OUTLINE)
			draw_circle(base + Vector2(0, -20) * s, 10.0 * s, Color(0.4, 0.68, 0.25))
			draw_circle(base + Vector2(-3, -23) * s, 5.0 * s, Color(0.55, 0.8, 0.32))
			return
		4:   # birch
			draw_rect(Rect2(base + Vector2(-1.5, -16) * s, Vector2(3, 16) * s), Color(0.92, 0.92, 0.88))
			draw_rect(Rect2(base + Vector2(-1.5, -10) * s, Vector2(3, 1) * s), Iso.OUTLINE)
			draw_circle(base + Vector2(0, -22) * s, 8.0 * s, Iso.OUTLINE)
			draw_circle(base + Vector2(0, -22) * s, 7.0 * s, Color(0.75, 0.88, 0.3))
			return
		5:   # dead snag
			var gc := Color(0.55, 0.5, 0.45)
			draw_line(base, base + Vector2(0, -26) * s, Iso.OUTLINE, 4.0)
			draw_line(base, base + Vector2(0, -26) * s, gc, 2.0)
			draw_line(base + Vector2(0, -16) * s, base + Vector2(6, -21) * s, gc, 1.0)
			draw_line(base + Vector2(0, -12) * s, base + Vector2(-5, -17) * s, gc, 1.0)
			return
	draw_rect(Rect2(base + Vector2(-2, -9) * s, Vector2(4, 9) * s), Color(0.4, 0.25, 0.15))
	var g := Color(0.1, 0.45, 0.28)
	for i in 3:
		var y := -9.0 - i * 10.0
		var w := (13.0 - i * 3.5) * s
		var tri := PackedVector2Array([base + Vector2(-w, y * s), base + Vector2(w, y * s), base + Vector2(0, (y - 18.0) * s)])
		draw_colored_polygon(tri, Iso.shade(g, 1.0 + i * 0.15))
		draw_colored_polygon(PackedVector2Array([tri[0], base + Vector2(-w * 0.1, y * s), tri[2]]), Iso.shade(g, 1.35 + i * 0.15))
		tri.append(tri[0])
		draw_polyline(tri, Iso.OUTLINE, 1.0)


func _draw_rock(r: Dictionary) -> void:
	var b := Iso.to_screen(r["pos"], r["z"])
	var s: float = r["size"]
	var h: int = r["h"]
	var w := 7.0 * s
	var ht := 6.0 * s + float(h % 3)
	var poly := PackedVector2Array([b + Vector2(-w, 1), b + Vector2(-w * 0.8, -ht * 0.7), b + Vector2(-w * 0.2, -ht), b + Vector2(w * 0.6, -ht * 0.8),
		b + Vector2(w, -ht * 0.2), b + Vector2(w * 0.8, 2)])
	Iso.poly(self, poly, Color(0.58, 0.56, 0.54))
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 0.8, -ht * 0.7), b + Vector2(-w * 0.2, -ht), b + Vector2(w * 0.1, -ht * 0.6), b + Vector2(-w * 0.5, -ht * 0.4)]),
		Color(0.76, 0.74, 0.72))
	if h % 4 == 0:
		draw_rect(Rect2(b + Vector2(-w * 0.4, -ht * 0.3), Vector2(3, 2)), Color(0.45, 0.65, 0.35))


func _draw_deco(e: Dictionary) -> void:
	match e["kind"]:
		"arch":
			var pz: Dictionary = e["pz"]
			var n: Vector2 = pz["n"]
			var z: float = pz["z"]
			var b0 := Iso.to_screen(pz["pos"] - n * 1.1, z)
			var b1 := Iso.to_screen(pz["pos"] + n * 1.1, z)
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
			var pz: Dictionary = e["pz"]
			var b := Iso.to_screen(pz["pos"] + (pz["n"] as Vector2) * 1.1, pz["z"])
			draw_line(b, b + Vector2(0, -26), Color(0.4, 0.3, 0.2), 3.0)
			draw_rect(Rect2(b + Vector2(-24, -42), Vector2(48, 18)), Color(1.0, 0.85, 0.2))
			draw_string(font, b + Vector2(-24, -29), e["label"], HORIZONTAL_ALIGNMENT_CENTER, 48.0, 8, Color(0.1, 0.1, 0.15))
		"warn":
			var pz: Dictionary = e["pz"]
			var b := Iso.to_screen(pz["pos"] + (pz["n"] as Vector2) * 0.95 * float(e["side"]), pz["z"])
			draw_line(b, b + Vector2(0, -18), Color(0.4, 0.3, 0.2), 2.0)
			var c := b + Vector2(0, -26)
			var dia := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
			Iso.poly(self, dia, Color(1.0, 0.82, 0.15))
			match e["icon"]:
				"log":
					draw_line(c + Vector2(-5, 2), c + Vector2(5, -1), Color(0.45, 0.28, 0.15), 3.0)
				"jump":
					draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 3), c + Vector2(4, 3), c + Vector2(4, -4)]), Iso.OUTLINE)
				"ford":
					for q in 2:
						draw_polyline(PackedVector2Array([c + Vector2(-5, -1 + q * 3), c + Vector2(-2, -3 + q * 3), c + Vector2(1, -1 + q * 3), c + Vector2(4, -3 + q * 3)]), Color(0.15, 0.4, 0.8), 1.0)
		"fan":
			var b := Iso.to_screen(e["pos"], e["z"])
			var col: Color = e["col"]
			draw_line(b, b + Vector2(0, -14), col, 5.0)
			draw_circle(b + Vector2(0, -19), 4.0, Color(0.95, 0.8, 0.65))
			var wave := sin(t_ * 8.0 + (e["pos"] as Vector2).x * 3.0) * 5.0
			draw_line(b + Vector2(0, -13), b + Vector2(7, -24 + wave), col, 2.0)
			draw_line(b + Vector2(0, -13), b + Vector2(-7, -22 - wave), col, 2.0)


func _sp(p: Dictionary, lift: float = 0.0) -> Vector2:
	return Iso.to_screen(p["pos"], float(p["z"]) + 1.8 + lift)


func _draw_obstacle(ob: Dictionary) -> void:
	var s: float = ob["s"]
	match ob["kind"]:
		"jump":
			var a0 := _pose(s - 2.4, -0.5)
			var a1 := _pose(s - 2.4, 0.5)
			var b0 := _pose(s, -0.5)
			var b1 := _pose(s, 0.5)
			var h := 8.0
			var dirt := Color(0.62, 0.45, 0.28)
			Iso.poly(self, PackedVector2Array([_sp(a0), _sp(b0, h), _sp(b0)]), Iso.shade(dirt, 0.8))
			Iso.poly(self, PackedVector2Array([_sp(a1), _sp(b1, h), _sp(b1)]), Iso.shade(dirt, 0.8))
			Iso.poly(self, PackedVector2Array([_sp(b0, h), _sp(b1, h), _sp(b1), _sp(b0)]), Iso.shade(dirt, 0.6))
			Iso.poly(self, PackedVector2Array([_sp(a0), _sp(a1), _sp(b1, h), _sp(b0, h)]), dirt)
			draw_line(_sp(b0, h), _sp(b1, h), Color(0.85, 0.7, 0.5), 1.0)
			for lat in [-0.8, 0.8]:
				var fb := _sp(_pose(s, lat))
				draw_line(fb, fb + Vector2(0, -16), Iso.OUTLINE, 2.0)
				var w := sin(t_ * 7.0 + lat) * 2.0
				draw_colored_polygon(PackedVector2Array([fb + Vector2(0, -16), fb + Vector2(8, -13 + w), fb + Vector2(0, -10)]), Color(1.0, 0.45, 0.1))
		"log":
			var flip := -1.0 if ob.get("flip", false) else 1.0
			var pa := _pose(s, -1.35 * flip)
			var pb := _pose(s, 1.55 * flip)
			var za := maxf(_tz(pa["pos"]), float(pa["z"])) + 4.0
			var zb := maxf(_tz(pb["pos"]), float(pb["z"])) + 4.0
			var a := Iso.to_screen(pa["pos"], za)
			var b := Iso.to_screen(pb["pos"], zb)
			var bark := Color(0.45, 0.3, 0.18)
			draw_line(a, b, Iso.OUTLINE, 8.0)
			draw_line(a, b, bark, 6.0)
			draw_line(a + Vector2(0, -2), b + Vector2(0, -2), Iso.shade(bark, 1.3), 1.0)
			for f in [0.3, 0.62]:
				var m := a.lerp(b, f)
				draw_line(m, m + Vector2(3, -7), Iso.OUTLINE, 3.0)
				draw_line(m, m + Vector2(3, -7), bark, 1.0)
				draw_circle(m + Vector2(4, -8), 3.0, Color(0.15, 0.45, 0.25))
			# root ball on one end, saw-cut rings on the other
			draw_circle(a, 7.0, Iso.OUTLINE)
			draw_circle(a, 6.0, Color(0.38, 0.27, 0.17))
			for q in 4:
				draw_line(a, a + Vector2.from_angle(q * 1.4 + 0.5) * 9.0, Color(0.32, 0.22, 0.14), 1.0)
			draw_circle(b, 4.0, Iso.OUTLINE)
			draw_circle(b, 3.0, Color(0.86, 0.72, 0.5))
			draw_circle(b, 1.5, Color(0.7, 0.55, 0.35))
		"ford":
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for q in 5:
				var ss := s - FORD_HALF + FORD_HALF * 2.0 * q / 4.0
				left.append(_sp(_pose(ss, -1.0), 0.2))
				right.append(_sp(_pose(ss, 1.0), 0.2))
			right.reverse()
			var poly := left + right
			draw_colored_polygon(poly, Iso.fa(WATER, 0.9))
			for q in 3:
				var u := fposmod(t_ * 0.5 + q / 3.0, 1.0)
				var ss := s - FORD_HALF + FORD_HALF * 2.0 * u
				draw_line(_sp(_pose(ss, -0.8), 0.4), _sp(_pose(ss, 0.8), 0.4), Color(0.85, 0.95, 1.0, 1.0 - absf(u - 0.5) * 2.0), 1.0)
			for lat in [-0.85, 0.9]:
				for k in 2:
					var rp := _sp(_pose(s + (k - 0.5) * 2.0, lat))
					draw_rect(Rect2(rp - Vector2(3, 2), Vector2(6, 4)), Iso.OUTLINE)
					draw_rect(Rect2(rp - Vector2(2, 1), Vector2(4, 2)), Color(0.66, 0.64, 0.6))


## Pixel sprites from [x, y, w, h, colour(, outline)] rectangles in 2x2-pixel units, drawn facing right (face 1)
## or mirrored, with a 1 px outline.
func _sprite(base: Vector2, face: float, rects: Array) -> void:
	for r in rects:
		if r.size() < 6 or r[5]:
			draw_rect(_flip(base, face, r[0], r[1], r[2], r[3]).grow(1.0), Iso.OUTLINE)
	for r in rects:
		draw_rect(_flip(base, face, r[0], r[1], r[2], r[3]), r[4])


func _flip(base: Vector2, face: float, x: float, y: float, w: float, h: float) -> Rect2:
	x *= 2.0
	y *= 2.0
	w *= 2.0
	h *= 2.0
	return Rect2(Vector2(base.x + x if face > 0.0 else base.x - x - w, base.y + y), Vector2(w, h))


func _shadow(c: Vector2, w: float) -> void:
	var poly := PackedVector2Array()
	for q in 8:
		poly.append(c + Vector2(cos(q * TAU / 8.0) * w, sin(q * TAU / 8.0) * w * 0.4))
	draw_colored_polygon(poly, Color(0, 0, 0, 0.22))


func _draw_animal(a: Dictionary) -> void:
	var p: Vector2 = a["pos"]
	var base := Iso.to_screen(p, _tz(p) + 1.5).round()
	var f: float = a["face"]
	var run: bool = a["run"]
	var ph: float = a["phase"]
	var g := int(fposmod(ph * 10.0, 2.0)) if run else 0     # gallop frame
	var ink := Iso.OUTLINE
	match a["kind"]:
		"bear":
			var col := Color(0.18, 0.14, 0.13) if a["dark"] else Color(0.45, 0.29, 0.16)
			var dk := Iso.shade(col, 0.72)
			var mz := Color(0.78, 0.6, 0.4)
			_shadow(base, 24.0)
			if a["state"] == "roar":
				_sprite(base, f, [[-4, -5, 3, 5, dk], [1, -5, 3, 5, dk], [-5, -19, 10, 15, col], [-8, -18, 4, 3, col], [4, -18, 5, 3, col],
					[-4, -26, 8, 7, col], [-5, -28, 2, 2, col], [3, -28, 2, 2, col], [1, -23, 4, 3, mz]])
				_sprite(base, f, [[2, -21, 3, 1, Color(0.85, 0.15, 0.15), false], [0, -25, 1, 1, ink, false], [4, -23, 1, 1, ink, false]])
			else:
				var bob := -1 if g == 1 else 0
				_sprite(base, f, [[-9 + g * 2, -5, 3, 5, dk], [6 - g * 2, -5, 3, 5, dk], [-6 - g, -5, 3, 5, col], [3 + g, -5, 3, 5, col],
					[-9, -12 + bob, 17, 8, col], [-3, -14 + bob, 7, 3, col], [7, -14 + bob, 6, 6, col], [8, -16 + bob, 2, 2, col], [11, -11 + bob, 4, 3, mz]])
				_sprite(base, f, [[14, -11 + bob, 1, 1, ink, false], [10, -12 + bob, 1, 1, ink, false]])
		"deer":
			var col := Color(0.72, 0.5, 0.3)
			var dk := Iso.shade(col, 0.7)
			var white := Color(0.97, 0.95, 0.9)
			_shadow(base, 16.0)
			var graze: bool = not run and sin(ph * 0.7) > 0.3
			var bob := -1 if g == 1 else 0
			var legs: Array = [[-6, -6, 1, 6, dk], [-4, -6, 1, 6, dk], [3, -6, 1, 6, dk], [5, -6, 1, 6, dk]] if not run else \
				([[-9, -6, 1, 5, dk], [-7, -6, 1, 4, dk], [6, -6, 1, 5, dk], [8, -6, 1, 4, dk]] if g == 0 else [[-4, -6, 1, 6, dk], [-2, -6, 1, 6, dk], [1, -6, 1, 6, dk], [3, -6, 1, 6, dk]])
			var body: Array = [[-7, -11 + bob, 13, 5, col], [-8, -12 + bob, 2, 2, white]]
			if graze:
				body += [[5, -10, 3, 4, col], [7, -7, 4, 3, col], [6, -9, 1, 2, col]]
			else:
				body += [[4, -15 + bob, 3, 5, col], [5, -17 + bob, 5, 3, col], [4, -19 + bob, 1, 2, col]]
			_sprite(base, f, legs + body)
			var det: Array = [[-4, -7 + bob, 8, 1, white, false]]
			if graze:
				det.append([10, -6, 1, 1, ink, false])
			else:
				det.append([9, -16 + bob, 1, 1, ink, false])
				if a["stag"]:
					var ac := Color(0.85, 0.75, 0.55)
					det += [[5, -23 + bob, 1, 5, ac, false], [7, -22 + bob, 1, 4, ac, false], [4, -22 + bob, 1, 1, ac, false], [8, -23 + bob, 1, 1, ac, false]]
			_sprite(base, f, det)
		"rabbit":
			var col := Color(0.62, 0.52, 0.42)
			var hop := -int(absf(sin(ph * 12.0)) * 4.0) if run else 0
			_shadow(base, 8.0)
			_sprite(base, f, [[-3, -4 + hop, 5, 3, col], [1, -6 + hop, 3, 3, col], [1, -9 + hop, 1, 3, col], [3, -9 + hop, 1, 3, col], [-4, -4 + hop, 2, 2, Color(1, 1, 1)]])
		"squirrel":
			var col := Color(0.68, 0.33, 0.15)
			var hop := -int(absf(sin(ph * 14.0)) * 2.0) if run else 0
			_shadow(base, 8.0)
			_sprite(base, f, [[-2, -4 + hop, 4, 3, col], [-5, -9 + hop, 3, 6, col], [1, -6 + hop, 3, 2, col], [2, -7 + hop, 1, 1, col]])
		"fox":
			var col := Color(0.92, 0.46, 0.12)
			var dk := Color(0.25, 0.15, 0.12)
			_shadow(base, 14.0)
			_sprite(base, f, [[-4 - g, -3, 1, 3, dk], [3 + g, -3, 1, 3, dk], [-2 + g, -3, 1, 3, dk], [1 - g, -3, 1, 3, dk],
				[-5, -6, 10, 3, col], [-10, -7, 5, 2, col], [-11, -7, 2, 2, Color(1, 1, 1)], [4, -8, 4, 3, col], [7, -7, 2, 2, Color(1, 1, 1)],
				[4, -10, 1, 2, col], [6, -10, 1, 2, col]])
			_sprite(base, f, [[6, -8, 1, 1, ink, false], [8, -7, 1, 1, ink, false]])
		"goat":
			var col := Color(0.95, 0.95, 0.92)
			var dk := Color(0.55, 0.55, 0.55)
			_shadow(base, 12.0)
			_sprite(base, f, [[-4, -4, 1, 4, dk], [-2, -4, 1, 4, dk], [2, -4, 1, 4, dk], [4, -4, 1, 4, dk], [-5, -9, 10, 5, col], [4, -12, 3, 4, col], [6, -8, 1, 2, col]])
			_sprite(base, f, [[4, -15, 1, 3, Color(0.25, 0.22, 0.2), false], [5, -15, 1, 1, Color(0.25, 0.22, 0.2), false], [6, -11, 1, 1, ink, false]])
		"marmot":
			var col := Color(0.58, 0.42, 0.26)
			var up := not run and sin(ph * 0.9) > 0.0
			_shadow(base, 8.0)
			if up:
				_sprite(base, f, [[-2, -7, 4, 7, col], [-1, -10, 3, 3, col]])
				_sprite(base, f, [[-1, -6, 2, 4, Color(0.8, 0.68, 0.5), false], [1, -9, 1, 1, ink, false]])
			else:
				_sprite(base, f, [[-3, -4, 6, 4, col], [2, -5, 3, 3, col]])
		"moose":
			var col := Color(0.3, 0.2, 0.13)
			var leg := Color(0.55, 0.45, 0.35)
			var ant := Color(0.8, 0.7, 0.5)
			_shadow(base, 26.0)
			_sprite(base, f, [[-7, -9, 2, 9, leg], [-4, -9, 2, 9, leg], [4, -9, 2, 9, leg], [7, -9, 2, 9, leg],
				[-9, -17, 18, 8, col], [-2, -19, 6, 2, col], [8, -18, 4, 4, col], [10, -15, 4, 4, col], [9, -12, 2, 3, col]])
			_sprite(base, f, [[4, -22, 7, 2, ant], [4, -24, 1, 2, ant], [7, -24, 1, 2, ant], [10, -24, 1, 2, ant]])
			_sprite(base, f, [[10, -17, 1, 1, ink, false]])


## A pair of eagles circling high over the course.
func _draw_birds(me_pos: Vector2) -> void:
	for q in 2:
		var ang := t_ * (0.35 + q * 0.12) + q * PI
		var p := me_pos + Vector2(4.0 + q * 3.0, -5.0) + Vector2(cos(ang), sin(ang)) * (3.5 + q)
		var c := Iso.to_screen(p, _tz(me_pos) + 150.0 + q * 30.0)
		var flap := sin(t_ * (5.0 + q)) * 3.0
		var wing := Color(0.32, 0.22, 0.14)
		draw_polyline(PackedVector2Array([c + Vector2(-8, -2 + flap), c + Vector2(-3, 0), c, c + Vector2(3, 0), c + Vector2(8, -2 + flap)]), wing, 2.0)
		draw_rect(Rect2(c + Vector2(-1, -2), Vector2(2, 2)), Color(0.98, 0.98, 0.95))


func _crowded(k: int) -> bool:
	for o in riders.size():
		if o != k and absf(float(riders[o]["s"]) - float(riders[k]["s"])) < 4.0 and (o < k or riders[o]["player"]):
			return true
	return false


func _draw_rider(k: int, pz: Dictionary) -> void:
	var r: Dictionary = riders[k]
	var s: float = r["s"]
	var pa := _pose(s - 1.5, r["lat"])
	var pb := _pose(s + 1.5, r["lat"])
	var sa := Iso.to_screen(pa["pos"], pa["z"])
	var sb := Iso.to_screen(pb["pos"], pb["z"])
	var ds := (sb - sa)
	if ds.length() < 0.01:
		ds = Vector2(1, 0.3)
	var ground := Iso.to_screen(pz["pos"], pz["z"])
	var air := _air_px(r)
	var c := ground + Vector2(0, -air)
	if air > 0.0:
		_shadow(ground, 10.0 - minf(air * 0.1, 4.0))
	if r["wet"]:
		for q in 6:
			var u := fposmod(t_ * 2.5 + q * 0.37 + k * 0.2, 1.0)
			var dp := ground + Vector2(sin(q * 2.1 + k) * (6.0 + u * 8.0), -sin(u * PI) * 12.0)
			draw_rect(Rect2(dp, Vector2(2, 2)), Color(0.8, 0.92, 1.0, 1.0 - u))
		draw_arc(ground, 9.0 + sin(t_ * 6.0) * 1.5, 0.0, TAU, 12, Color(0.9, 0.97, 1.0, 0.7), 1.0)
	var kb := _bread_k(r["bread"])
	var down := float(r["down"]) > 0.0
	if float(r["socks"]) > 0.0 and not down:
		PowerUps.draw_flames(self, c, -ds.normalized(), t_ + k)
	var dsd := Iso.to_screen(Iso.to_world(ds).rotated(1.2)) if down else ds   # tipped over, turned in world space
	var phase: float = 0.0 if down else r["phase"]
	if kb != 1.0:
		draw_set_transform(c, 0.0, Vector2(kb, kb))
		BikeDraw.draw(self, Vector2.ZERO, dsd, r["frame"], r["color"], phase, true, "YOU" if r["player"] else r["short"])
		draw_set_transform(Vector2.ZERO)
	else:
		BikeDraw.draw(self, c, dsd, r["frame"], r["color"], phase, true, "YOU" if r["player"] else r["short"])
	if down:
		for q in 3:
			var a := t_ * 5.0 + q * TAU / 3.0
			var sp := c + Vector2(cos(a) * 9.0, -30.0 + sin(a) * 3.0)
			draw_rect(Rect2(sp - Vector2(1, 1), Vector2(3, 3)), Iso.OUTLINE)
			draw_rect(Rect2(sp, Vector2(1, 1)), Color(1.0, 0.95, 0.3))
	if r["player"] or not _crowded(k):
		var label: String = "YOU" if r["player"] else r["short"]
		var outline_col: Color = Color(1, 1, 1) if r["player"] else r["color"]
		var p := c + Vector2(-100, -54 * kb)
		draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8, 4, Iso.OUTLINE)
		draw_string(font, p, label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8, outline_col)
	var dust := clampf(float(r["v"]) / 5.0, 0.0, 1.0) * (0.0 if air > 0.0 or r["wet"] else 1.0)
	for q in 3:
		var puff := ground - ds.normalized() * (16.0 + q * 11.0) + Vector2(0, -6 - q * 5 - sin(t_ * 4.0 + q + k) * 2.0)
		draw_circle(puff, 5.0 + q * 2.5, Color(0.8, 0.72, 0.58, 0.32 * dust * (1.0 - q * 0.28)))
	if float(r["land"]) > 0.0:
		var u := 1.0 - float(r["land"]) / 0.4
		for q in 2:
			draw_circle(ground + Vector2((q * 2 - 1) * (8.0 + u * 10.0), -3.0), 4.0 + u * 4.0, Color(0.8, 0.72, 0.58, 0.5 * (1.0 - u)))


## A power-up person at the roadside, holding a gift out to the riders.
func _draw_giver(g: Dictionary, gp: Dictionary) -> void:
	var ground := Iso.to_screen(gp["pos"], gp["z"])
	PowerUps.draw_person(self, ground, g["shirt"], g["skin"], g["hair"], t_ + float(g["phase"]), true)
	PowerUps.draw_gift(self, ground + Vector2(7, -24), t_ + float(g["phase"]))


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
