extends Node2D
## Mt. Crankmore gravel race: long switchbacks zig-zag up a big isometric mountainside, with rolling ups and downs,
## jumps, fallen trees, creek fords and wildlife. The map is built at about the town's scale (a few metres per tile),
## so riding speed looks the same as in town. Player power drives speed through a real power/grade/drag model;
## the trainer gets the grade (plus a kick over logs and through creeks).

signal finished(result: Dictionary)

const COURSES := [
	# "hairpins": turnarounds stacked up the mountainside (a few may fall in the run-out); "stagger": how far (a fraction
	# of the leg) each one may sit in from the edge, so the stack is ragged like the Alpe d'Huez's 21 virages
	{"name": "Foothill Gravel Grind", "length": 6000.0, "grade": 0.04, "roll": 1.3, "entry": 40, "prize": 500, "seed": 7, "tunnels": 1,
		"hairpins": 15, "stagger": 0.22,
		"blurb": "6 km of rolling gravel switchbacks with jumps, creek crossings and fallen trees, about 20 minutes for the front of the pack. Full of squirrels. And deer. And a bear or two."},
	{"name": "Summit Gravel Showdown", "length": 4400.0, "grade": 0.065, "roll": 1.2, "entry": 100, "prize": 1200, "seed": 21, "tunnels": 2,
		"hairpins": 18, "stagger": 0.22,
		"blurb": "4.4 km of steep gravel to the top of Mt. Crankmore, hairpin after hairpin stacked up the face like the Alpe d'Huez, with ramps up to 12%, short plunges, logs and bears, about 20 minutes. Legends are made here. So are blisters."},
	# "bump": gentle rollers on top of the base grade; "flowers": a valley of flower meadows instead of a mountain;
	# "profile": [metres, grade] stretches replacing the base grade, levelled so the finish is as high as the start;
	# "bends": wide sweeping U-bends ("gap" tiles across) and long meanders instead of hairpins
	{"name": "Flour Run", "length": 3000.0, "grade": 0.0, "roll": 0.0, "bump": 0.006, "flowers": true, "entry": 20, "prize": 250, "seed": 33,
		"hairpins": 3, "bends": true, "gap": 44.0, "stagger": 0.12,
		"profile": [[150, 0.0], [400, 0.03], [150, -0.02], [250, 0.0], [200, -0.025], [350, 0.035], [200, 0.0],
			[300, -0.03], [150, 0.02], [250, 0.0], [450, -0.023], [150, 0.0]],
		"blurb": "3 km through the flower meadows at the foot of Mt. Crankmore: gentle climbs, easy dips and flat stretches, finishing back where you started, about 10 minutes. Stop and smell the flowers. Or don't, and win."},
]
const MAX_GRADE := 0.12
const MIN_GRADE := -0.09
const M_PER_TILE := 3.3       # metres of road per tile (the town is about 3.2), so speeds look the same
const PX_PER_M := 12.0        # screen lift per metre of height
const LEG_GAP := 16.0         # tiles between switchback legs (a course's "gap" can widen it)
const HAIRPIN_R := 8.0        # radius of a hairpin (LEG_GAP / 2)
const STEP := 0.5             # road sample spacing (tiles)
const ROAD_W := 2.0           # how much wider the race road is than it was first drawn
const ROAD_HW := 0.64 * ROAD_W  # half the road's width (tiles)
const ROAD_GROW := ROAD_HW - 0.64   # how much further out everything beside the road stands
const VIEW_R := 17            # terrain cells drawn around the player
const MAX_SPEED := 16.0       # m/s cap on the descents
const RUNOUT := 400.0         # metres of cool-down road past the finish arch
const COOL_SPEED := 5.0       # m/s finished rivals soft-pedal at
const IDLE_END := 15.0        # seconds stopped past the finish before the results come up anyway
const FORD_HALF := 2.5        # metres of water either side of a ford's centre
const FORD_CRR := 0.05        # extra rolling resistance while wading
const WATER := Color(0.3, 0.62, 0.92)
## Speed (km/h) -> share of the watts saved riding in a slipstream; linear in between, flat above the last point.
const DRAFT_CURVE := [[0.0, 0.0], [13.0, 0.18], [17.0, 0.24], [40.0, 0.30]]

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
var leg_gap := LEG_GAP                # tiles between legs on this course
var turn_r := HAIRPIN_R               # radius of the turns joining the legs (leg_gap / 2)
var leg_wob: Array = []
var leg_span: Array = []              # per leg: Vector2(lowest x, highest x) it runs between
var wob_w := 16.0                     # tiles at each end of a leg over which its meander eases in
var leg_elev: Array = []              # per leg: road elevation (m) per grid column
var gw := 1
var gh := 1
var ox := 0
var oy := 0
var zgrid := PackedFloat32Array()     # terrain height (px) at cell corners
var rdist := PackedFloat32Array()     # tiles to the road at cell corners (99 = far)
var cell_col := PackedColorArray()
var cell_kind := PackedByteArray()    # 0 bare, 1 meadow, 2 forest floor, 3 scree, 4 snow
var cell_tex := PackedByteArray()     # index into GROUND_KINDS: the texture of each cell (see Ground)
var cell_light := PackedFloat32Array() # banded light level of each cell
var cell_tint := PackedColorArray()
const GROUND_KINDS := ["grass_meadow", "grass_forest", "grass_alpine", "grass_fall", "grass_spring", "scree", "snow", "dirt"]
const CONTOUR_M := 3.0                # metres between the light/dark contour stripes on the hillside
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
## A rescue (see main._start_rescue): you alone, carrying a medical kit up to an injured skier RESCUE_AT of the way
## up the course; reaching them ends it.
var rescue := false
var rescue_s := 0.0
const RESCUE_AT := 0.25
const RESCUE_PAY := 250
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
var road_len := 0.0                   # course length plus the run-out (m)
var idle_t := 0.0                     # seconds the finished player has been stopped
var last_swap := {}
var lead_clock := 0.0
var t_ := 0.0
var road_leg := PackedInt32Array()    # which switchback leg each road sample is on (-1 = in a hairpin, -2 = in a wide bend)
var hairpins: Array = []              # {s, i0, i1, left, n, c, called}
var tunnels: Array = []               # {s0, s1, i0, i1, a (roof opacity), called}
var cliffs: Array = []                # rock faces beside the road {i0, i1, side (which side of the road), h (m, + wall, - drop)}
var cell_cliff := PackedByteArray()   # per cell: 0 none, 1 rock on top of / below a cliff, 2 the cliff face
var ramps: Array = []                 # steep climbs and fast descents {s0, s1, g, called}
var snow_called := false
var life: RaceLife                    # the race-day crowds, motos, helicopter and the railway (see RaceLife)
## The bear caught you: you wipe out and lie there while a ski patroller wheels your bike away and comes back with a
## new one (see _bear_wipeout and _patrol_at). {t: seconds since the catch, lie: where you lie, bike / bike_z: where
## your bike lies, off: off screen, where the patroller fetches the new bike, st: their turning}. Empty when there's
## none going on. Nobody waits: the race clock and the rivals carry on, so the whole scene costs you BEAR_DOWN seconds.
var patrol: Dictionary = {}
const BEAR_DOWN := 15.0       # seconds down after the bear catches you
const BEAR_FTP := 1.1         # the bear runs as fast as you'd ride at this share of your FTP: hold it to get away
const BEAR_CHASE := 19.5      # seconds it keeps after you
const BEAR_ROUSE := 0.7       # seconds it rears up and roars where it stood before it sets off
const BEAR_ACCEL := 5.0       # m/s per second as it gets going
const BEAR_REACH := 1.6       # m behind you when it swipes
const BEAR_SWIPE := 0.75      # seconds of the swipe; the paw lands at BEAR_HIT through it
const BEAR_HIT := 0.4
const SP_LIE := 1.3           # the wipe-out animation is over (13 frames at Sprites.FALL_FPS): lying there now
const SP_IN := 1.4            # the patroller sets off from off screen
const SP_WALK := 3.2          # seconds for each walk between off screen and your bike
const SP_LIFT := 0.4          # standing over the old bike, picking it up
const SP_AWAY := 0.6          # out of sight, fetching the new bike
const SP_SET := 0.6           # setting the new bike down next to you before walking off
const SP_GETUP := 1.3         # the wipe-out played backwards at the end of the BEAR_DOWN: you climb back on
const SP_MARGIN := 40.0       # px past the edge of the screen the patroller walks to (their sprite is out of sight)


func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # the ground textures (see Ground) wrap
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
	_build_tunnels(rng)
	_build_cliffs(rng)
	_build_terrain()
	_build_features(rng)
	life = RaceLife.new(self)
	life.build(rng)
	_build_flora(rng)
	_build_stream_geometry()
	_build_road_geometry()
	_build_animals(rng)
	_build_givers(rng)
	_build_season()
	_build_riders()
	if rescue:
		riders = [riders[0]]   # no race: just you and the medical kit
		rescue_s = float(course["length"]) * RESCUE_AT
	clock = 0.0
	countdown = 2.0 if rescue else 4.0
	over = false
	over_clock = 0.0
	finish_count = 0
	frisbees.clear()
	patrol = {}
	stamina = 1.0
	kick_t = 0.0
	lead_clock = 0.0
	last_swap.clear()
	snow_called = false
	for t in tunnels:
		t["called"] = false
		t["a"] = 1.0
	for r in ramps:
		r["called"] = false
	bubbles.clear()
	pops.clear()
	player_finish_time = 0.0
	idle_t = 0.0
	if rescue:
		Game.toast.emit("Get the medical kit up to the injured skier, %d m up the mountain!" % int(rescue_s), Color(1.0, 0.45, 0.45))
		return
	# pre-race jabber
	var ids := range(Talk.rivals.size())
	ids.shuffle()
	for k in mini(3, ids.size()):
		get_tree().create_timer(1.0 + k * 1.2).timeout.connect(Talk.say.bind(ids[k], "race_start", true))


## Switchbacks: legs run along +x / -x, each one leg_gap tiles further up the mountain (towards -y, away from the
## camera, so the slope never hides you), joined by hairpins. Leg 0 is at the bottom.
func _build_road(rng: RandomNumberGenerator) -> void:
	var length: float = course["length"]
	road_len = length + RUNOUT
	var target := road_len / M_PER_TILE
	var bends: bool = course.get("bends", false)
	leg_gap = float(course.get("gap", LEG_GAP))
	turn_r = leg_gap * 0.5
	legs_n = int(course.get("hairpins", maxi(2, roundi(target / 185.0) - 1))) + 1
	var stagger: float = course.get("stagger", 0.0)
	wob_w = 34.0 if bends else 16.0
	# the shape has its own random numbers; the course's rng skips what the old layout used, so the grade profile
	# (and with it the climb) is exactly what it was before the hairpins were stacked up
	var geo := RandomNumberGenerator.new()
	geo.seed = int(course["seed"]) * 7919 + 17
	for _q in maxi(3, roundi(target / 185.0)) * 6:
		rng.randf()
	leg_wob.clear()
	for k in legs_n:
		if bends:   # long lazy meanders through the meadows
			leg_wob.append([geo.randf_range(6.0, 8.5), geo.randf_range(0.05, 0.075), geo.randf() * TAU,
				geo.randf_range(1.5, 2.5), geo.randf_range(0.1, 0.14), geo.randf() * TAU])
		else:       # short ramps that kink and bow between the hairpins
			leg_wob.append([geo.randf_range(1.6, 2.8), geo.randf_range(0.06, 0.1), geo.randf() * TAU,
				geo.randf_range(0.5, 1.2), geo.randf_range(0.13, 0.2), geo.randf() * TAU])
	# how far in from the edge each turn sits (a fraction of the leg), so the stack is ragged
	var inset: Array = []
	for k in legs_n - 1:
		inset.append(geo.randf() * stagger)
	# size the legs so the whole road (turns included) comes out at about road_len
	var turns := (legs_n - 1) * PI * turn_r
	leg_len = maxf(40.0, (target - turns) / (legs_n * (1.0 - stagger * 0.5) * 1.04))
	var poly := PackedVector2Array()
	var poly_leg := PackedInt32Array()
	for _pass in 6:
		leg_span.clear()
		for k in legs_n:
			var a := 0.0
			var b := leg_len
			if k % 2 == 0:
				a = leg_len * float(inset[k - 1]) if k > 0 else 0.0
				b = leg_len * (1.0 - float(inset[k])) if k < legs_n - 1 else leg_len
			else:
				b = leg_len * (1.0 - float(inset[k - 1]))
				a = leg_len * float(inset[k]) if k < legs_n - 1 else 0.0
			leg_span.append(Vector2(a, b))
		poly = PackedVector2Array()
		poly_leg = PackedInt32Array()
		for k in legs_n:
			var fwd := k % 2 == 0
			var lo: float = leg_span[k].x
			var hi: float = leg_span[k].y
			var n := maxi(8, int((hi - lo) * 2.0))
			for q in n + 1:
				var x := lerpf(lo, hi, q / float(n)) if fwd else lerpf(hi, lo, q / float(n))
				poly.append(Vector2(x, leg_y(k, x)))
				poly_leg.append(k)
			if k < legs_n - 1:
				var c := Vector2(hi if fwd else lo, _leg_base(k) - turn_r)
				var na := maxi(48, int(PI * turn_r * 2.0))
				for q in range(1, na):
					var a := PI * q / float(na)
					poly.append(c + Vector2(sin(a) * turn_r * (1.0 if fwd else -1.0), cos(a) * turn_r))
					poly_leg.append(-2 if bends else -1)
		var got := 0.0
		for i in range(1, poly.size()):
			got += poly[i].distance_to(poly[i - 1])
		if absf(got - target) < 1.0:
			break
		leg_len *= (target - turns) / maxf(got - turns, 1.0)
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
		sample_leg[i] = poly_leg[j] if poly_leg[j] == poly_leg[j + 1] else mini(mini(poly_leg[j], poly_leg[j + 1]), -1)
	for i in M:
		var tng := (pts[mini(i + 1, M - 1)] - pts[maxi(i - 1, 0)]).normalized()
		nrm[i] = Vector2(-tng.y, tng.x)
	road_leg = sample_leg
	# rolling profile: long climbs broken up by short plunges and steep kickers
	ds_m = road_len / float(M - 1)
	var g0: float = course["grade"]
	var amp: float = course["roll"]
	var p0 := rng.randf() * TAU
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	# a mountain gets a random run of climbs, ramps, flats and drops instead of the same rolling wave
	var prof: Array = [] if course.has("profile") else _random_profile(rng, length, g0)
	var e := 0.0
	var lo := 0.0
	for i in M:
		var s := i * ds_m
		s_m[i] = s
		var g := g0 * (1.0 + amp * sin(TAU * s / 650.0 + p0) + 0.45 * amp * sin(TAU * s / 230.0 + p1) + 0.25 * sin(TAU * s / 97.0 + p2))
		if not prof.is_empty():
			g = _profile_grade(prof, s) + 0.012 * sin(TAU * s / 71.0 + p2) + 0.008 * sin(TAU * s / 29.0 + p0)
		if course.has("profile"):
			g = _profile_grade(course["profile"], s)
		g += float(course.get("bump", 0.0)) * (sin(TAU * s / 420.0 + p1) + 0.4 * sin(TAU * s / 160.0 + p2))
		g = lerpf(0.01, clampf(g, MIN_GRADE, MAX_GRADE), smoothstep(0.0, 120.0, s))
		grade_a[i] = g
		if i > 0 and s <= length:
			e += g * ds_m
	# a profiled course finishes level with the start: spread the leftover climb evenly over the course
	var drift := e / length if course.has("profile") else 0.0
	e = 0.0
	for i in M:
		# past the arch the road eases out flat for the cool-down
		grade_a[i] = lerpf(grade_a[i] - drift, 0.0, smoothstep(length, length + 80.0, s_m[i]))
		if i > 0:
			e += grade_a[i] * ds_m
		elev[i] = e
		lo = minf(lo, e)
	gain = 1.0
	for i in M:
		elev[i] -= lo
		gain = maxf(gain, elev[i])
	# the hairpins (runs of samples that are on no leg) before the finish, to warn about; wide bends are not hairpins
	hairpins.clear()
	var run := -1
	for i in M:
		if road_leg[i] == -1 and run < 0:
			run = i
		elif road_leg[i] != -1 and run >= 0:
			if s_m[(run + i) / 2] > length - 20.0:
				break
			hairpins.append({"s": s_m[(run + i) / 2], "i0": run, "i1": i - 1, "left": road_leg[run - 1] % 2 == 0 if run > 0 else true,
				"n": hairpins.size() + 1, "c": (pts[run] + pts[i - 1]) * 0.5, "dx": 1.0 if road_leg[run - 1] % 2 == 0 else -1.0, "called": false})
			run = -1
	vz = PX_PER_M
	# terrain grid around the switchbacks (with room for the legs' meanders)
	var mw := 0
	for w in leg_wob:
		mw = maxi(mw, ceili(float(w[0]) + float(w[3])))
	ox = -int(turn_r) - 14
	oy = -18 - mw
	gw = int(leg_len) + 2 * (int(turn_r) + 14) + 1
	gh = int((legs_n - 1) * leg_gap) + 34 + 2 * mw
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


## A random [metres, grade] profile for a mountain: climbs, steep ramps, flats, descents and plunges in a random order
## and of random lengths, with the climbs scaled so the course gains about `g0` * its length overall.
func _random_profile(rng: RandomNumberGenerator, length: float, g0: float) -> Array:
	var segs: Array = []
	var total := 0.0
	var last := ""
	var ramp_w := 0.03 + g0 * 1.0
	while total < length + 300.0:
		var r := rng.randf()
		var kind := "climb"
		if r < 0.46:
			kind = "climb"
		elif r < 0.46 + ramp_w:
			kind = "ramp"
		elif r < 0.58 + ramp_w:
			kind = "flat"
		elif r < 0.78 + ramp_w:
			kind = "descent"
		else:
			kind = "plunge"
		if kind == last and rng.randf() < 0.7:
			continue
		var m := 100.0
		var g := 0.0
		match kind:
			"climb":
				m = rng.randf_range(110.0, 430.0)
				g = g0 * rng.randf_range(0.6, 1.8)
			"ramp":
				m = rng.randf_range(60.0, 170.0)
				g = rng.randf_range(0.085, 0.12)
			"flat":
				m = rng.randf_range(60.0, 220.0)
				g = rng.randf_range(-0.008, 0.016)
			"descent":
				m = rng.randf_range(100.0, 380.0)
				g = -rng.randf_range(0.015, 0.045)
			"plunge":
				m = rng.randf_range(40.0, 110.0)
				g = -rng.randf_range(0.05, 0.085)
		segs.append([m, g, kind])
		total += m
		last = kind
	# scale the climbs (not the drops) until the mean grade over the course is g0
	for _pass in 6:
		var sum := 0.0
		var n := 0
		var x := 0.0
		while x < length:
			sum += clampf(_profile_grade(segs, x), MIN_GRADE, MAX_GRADE)
			n += 1
			x += 10.0
		var k := clampf(g0 / maxf(sum / n, 0.005), 0.8, 1.25)
		for sg in segs:
			if sg[2] == "climb":
				sg[1] = clampf(float(sg[1]) * k, 0.01, 0.105)
	return segs


## Grade (fraction) at `s` metres along a [metres, grade] profile, eased over 40 m either side of each change.
func _profile_grade(profile: Array, s: float) -> float:
	var g: float = profile[0][1]
	var at := 0.0
	for k in range(1, profile.size()):
		at += float(profile[k - 1][0])
		g += (float(profile[k][1]) - float(profile[k - 1][1])) * smoothstep(at - 40.0, at + 40.0, s)
	return g


func _leg_base(k: int) -> float:
	return (legs_n - 1 - k) * leg_gap


## A leg's centre line: its base row plus a meander that eases off to nothing at the turns at either end.
func leg_y(k: int, x: float) -> float:
	var w: Array = leg_wob[k]
	var sp: Vector2 = leg_span[k]
	var win := smoothstep(sp.x, sp.x + wob_w, x) * smoothstep(sp.y, sp.y - wob_w, x)
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
	var k := clampi(int(((legs_n - 1) * leg_gap - y) / leg_gap), 0, legs_n - 2)
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
			"y0": _leg_base(ks) - leg_gap * 0.5, "y1": float(oy + gh)})


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
		var x0 := clampi(floori(minf(a.x, b.x) - 3.5 - ROAD_GROW) - ox, 0, gw)
		var x1 := clampi(ceili(maxf(a.x, b.x) + 3.5 + ROAD_GROW) - ox, 0, gw)
		var y0 := clampi(floori(minf(a.y, b.y) - 3.5 - ROAD_GROW) - oy, 0, gh)
		var y1 := clampi(ceili(maxf(a.y, b.y) + 3.5 + ROAD_GROW) - oy, 0, gh)
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
	var cliff_off := _cliff_offsets(n1, count)
	var cliff_m := PackedFloat32Array()   # how much of its cliff each corner has (0..1)
	cliff_m.resize(count)
	peak = 1.0
	for cy in gh + 1:
		for cx in n1:
			var x := float(ox + cx)
			var y := float(oy + cy)
			var idx := cy * n1 + cx
			var d := rdist[idx]
			# (measured from the road's edge: the wider road is flat across, its shoulders as they were)
			var de := d - ROAD_GROW
			var e := _base_m(x, y) + _noise_m(x, y) * smoothstep(1.0, 4.0, de)
			e -= 0.45 * (1.0 - smoothstep(0.2, 1.6, _stream_d(x, y))) * smoothstep(0.9, 2.5, de)
			if de < 3.5:
				e = lerpf(re[idx], e, smoothstep(0.75, 3.2, de))
			if cliff_off.has(idx):   # a rock wall up from the shoulder, or a drop away from it (never on a road)
				var co: Vector2 = cliff_off[idx]
				var k := smoothstep(2.0, 3.5, de)
				e += co.x * k
				cliff_m[idx] = co.y * k
			zgrid[idx] = e * vz
			peak = maxf(peak, zgrid[idx])
	cell_col.resize(gw * gh)
	cell_kind.resize(gw * gh)
	cell_tex.resize(gw * gh)
	cell_light.resize(gw * gh)
	cell_tint.resize(gw * gh)
	cell_cliff.resize(gw * gh)
	cell_cliff.fill(0)
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
			if course.get("flowers", false):
				f = 0.0              # a valley: no snow or scree, and much less forest
				b -= 1.5
			var cover := _snow_cover(x, y, f)
			if cover > 0.5:
				kind = 4
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
			# cliffs: bare grey rock on the face, broken scree on the ledge above or below it
			var m00 := cliff_m[j * n1 + i]
			var m10 := cliff_m[j * n1 + i + 1]
			var m11 := cliff_m[(j + 1) * n1 + i + 1]
			var m01 := cliff_m[(j + 1) * n1 + i]
			var mlo := minf(minf(m00, m10), minf(m11, m01))
			var mhi := maxf(maxf(m00, m10), maxf(m11, m01))
			if mhi - mlo > 0.4:
				cell_cliff[j * gw + i] = 2   # the face itself (drawn as bare rock, see _draw_cliff_face)
				col = Color(0.55, 0.51, 0.48)
				kind = 3
			elif mhi > 0.35:
				cell_cliff[j * gw + i] = 1   # the ledge above or the foot below: loose rocks (see _build_flora)
			if kind == 3:
				col = col.lerp(Season.SNOW, 0.65) if Season.bare() else col
			elif kind != 4:
				col = Season.ground(col)
			if cover > 0.0:
				col = col.lerp(Color(0.93, 0.96, 1.0), cover * 0.92)
			cell_col[j * gw + i] = Iso.shade(col, sh)
			# the textured look: which ground, a stepped light level, and stripes every few metres of height
			var gname := "grass_meadow"
			if kind == 4 or cover > 0.5 or f > 0.975 or (Season.bare() and kind != 3):
				gname = "snow"
			elif kind == 3:
				gname = "scree"
			elif kind == 2:
				gname = "grass_fall" if Season.is_("fall") else "grass_forest"
			elif f > 0.6:
				gname = "grass_alpine"
			elif Season.is_("spring") or course.get("flowers", false):
				gname = "grass_spring"
			elif Season.is_("fall"):
				gname = "grass_fall"
			var stripe := 0.94 if int(floorf(zc / (CONTOUR_M * vz))) % 2 == 1 else 1.0
			cell_tex[j * gw + i] = GROUND_KINDS.find(gname)
			cell_light[j * gw + i] = Ground.band(sh) * stripe
			var tint := Color.WHITE
			if kind == 3 and Season.bare():
				tint = Color(1.15, 1.15, 1.2)
			elif cover > 0.0 and gname != "snow":
				tint = Color.WHITE.lerp(Color(1.2, 1.22, 1.28), cover)
			if _stream_d(x, y) < 1.8 and gname.begins_with("grass"):
				tint = tint * Color(0.9, 1.0, 0.92)
			cell_tint[j * gw + i] = tint
			cell_kind[j * gw + i] = kind


## How snowy the mountain is at (x, y) at height fraction `f` (0..1): the snow line wanders, so there are patches
## below it and bare rock sticking out above, in every season.
func _snow_cover(x: float, y: float, f: float) -> float:
	if course.get("flowers", false):
		return 0.0
	var edge := 0.58 + 0.06 * sin(x * 0.31 + y * 0.23) + 0.05 * sin(x * 0.13 - y * 0.37) + 0.03 * sin(x * 0.7 + y * 0.9)
	return smoothstep(edge - 0.07, edge + 0.04, f)


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


func _in_tunnel(s: float, gap: float = 0.0) -> bool:
	for t in tunnels:
		if s > float(t["s0"]) - gap and s < float(t["s1"]) + gap:
			return true
	return false


## True on a cliff face (or its ledge, with `ledge`): nothing should stand there.
func _on_cliff(p: Vector2, ledge := false) -> bool:
	var i := int(floorf(p.x)) - ox
	var j := int(floorf(p.y)) - oy
	if i < 0 or j < 0 or i >= gw or j >= gh or cell_cliff.is_empty():
		return false
	return cell_cliff[j * gw + i] >= (1 if ledge else 2)


func _in_cliff(s: float, gap: float = 0.0) -> bool:
	for cl in cliffs:
		if s > s_m[int(cl["i0"])] - gap and s < s_m[int(cl["i1"])] + gap:
			return true
	return false


## Cliffs on the mountain, like the Alpe d'Huez's: rock walls rising on the uphill side of some of the ramps, and
## drops falling away off the outside of some of the hairpins that face the camera (and a few ramps). Kept off the
## start and finish, tunnels, creeks and the fans' campsites.
func _build_cliffs(rng: RandomNumberGenerator) -> void:
	cliffs.clear()
	if course.get("flowers", false):
		return
	var length: float = course["length"]
	var ok := func(i0: int, i1: int) -> bool:
		if i0 < 0 or i1 >= M or s_m[i0] < 160.0 or s_m[i1] > length - 160.0:
			return false
		for k in 4:   # the camper vans (see RaceLife._build_camps)
			var cs := length * (0.15 + 0.2 * k)
			if s_m[i1] > cs - 75.0 and s_m[i0] < cs + 75.0:
				return false
		for q in range(i0, i1 + 1, 4):
			if _in_tunnel(s_m[q], 30.0) or _stream_d(pts[q].x, pts[q].y) < 5.0:
				return false
		for cl in cliffs:
			if i1 > int(cl["i0"]) - 40 and i0 < int(cl["i1"]) + 40:
				return false
		return true
	# drops off the outside of the right-hand hairpins (their outside faces the camera)
	for h in hairpins:
		if float(h["dx"]) < 0.0 or rng.randf() > 0.7:
			continue
		var i0: int = int(h["i0"]) - 12
		var i1: int = int(h["i1"]) + 12
		var mid := (int(h["i0"]) + int(h["i1"])) / 2
		if ok.call(i0, i1):
			var side := signf(nrm[mid].dot(pts[mid] - (h["c"] as Vector2)))
			cliffs.append({"i0": i0, "i1": i1, "side": side, "h": -rng.randf_range(5.0, 8.0)})
	# rock walls up the uphill side (away from the camera) of some ramps, and the odd drop on the downhill side
	for k in range(1, legs_n - 1):
		if rng.randf() > 0.65:
			continue
		var ia := -1
		var ib := -1
		for i in M:
			if road_leg[i] == k:
				if ia < 0:
					ia = i
				ib = i
		var n := int(rng.randf_range(45.0, 85.0) / ds_m)
		var pad := int(22.0 / ds_m)
		if ia < 0 or ib - ia < n + 2 * pad:
			continue
		var i0 := ia + pad + int((ib - ia - n - 2 * pad) * rng.randf())
		var i1 := i0 + n
		if not ok.call(i0, i1):
			continue
		var mid := (i0 + i1) / 2
		var up := -signf(nrm[mid].y)   # the side of the road towards -y, up the mountain
		if rng.randf() < 0.7:
			cliffs.append({"i0": i0, "i1": i1, "side": up, "h": rng.randf_range(4.0, 7.0)})
		else:
			cliffs.append({"i0": i0, "i1": i1, "side": -up, "h": -rng.randf_range(4.5, 7.0)})
	cliffs.sort_custom(func(a, b): return int(a["i0"]) < int(b["i0"]))


## Terrain corner -> Vector2(height offset (m), how much of the cliff it has (0..1)) for the corners by a cliff.
func _cliff_offsets(n1: int, count: int) -> Dictionary:
	var out := {}
	for cl in cliffs:
		var i0: int = cl["i0"]
		var i1: int = cl["i1"]
		var side: float = cl["side"]
		var h: float = cl["h"]
		var ramp := maxf(6.0, (i1 - i0) * 0.18)
		var best := {}   # corner -> [distance, taper]
		for i in range(i0, i1, 2):
			var a := pts[i]
			var b := pts[mini(i + 2, M - 1)]
			var taper := smoothstep(float(i0), i0 + ramp, float(i)) * smoothstep(float(i1), i1 - ramp, float(i))
			var x0 := clampi(floori(minf(a.x, b.x) - 11.5 - ROAD_GROW) - ox, 0, gw)
			var x1 := clampi(ceili(maxf(a.x, b.x) + 11.5 + ROAD_GROW) - ox, 0, gw)
			var y0 := clampi(floori(minf(a.y, b.y) - 11.5 - ROAD_GROW) - oy, 0, gh)
			var y1 := clampi(ceili(maxf(a.y, b.y) + 11.5 + ROAD_GROW) - oy, 0, gh)
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					var p := Vector2(ox + cx, oy + cy)
					if (p - a).dot(nrm[i]) * side <= 0.0:
						continue
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					var idx := cy * n1 + cx
					if not best.has(idx) or d < float(best[idx][0]):
						best[idx] = [d, taper]
		for idx in best:
			var d: float = float(best[idx][0]) - ROAD_GROW   # from the road's edge
			var t: float = best[idx][1]
			var f := 0.0
			if h > 0.0:   # a wall: straight up off the shoulder, a ledge, then back down into the hillside
				f = smoothstep(2.9, 3.7, d) * (1.0 - smoothstep(6.0, 11.0, d))
			else:         # a drop: straight down off the shoulder, then the slope below eases back into the hillside
				f = smoothstep(2.3, 3.1, d) * (1.0 - smoothstep(6.5, 11.0, d))
			f *= t
			if f <= 0.0:
				continue
			var o: Vector2 = out.get(idx, Vector2.ZERO)
			if absf(h * f) > absf(o.x):
				out[idx] = Vector2(h * f, f)
	return out


func _clear_of(s: float, gap: float, kind: String = "") -> bool:
	if _in_tunnel(s, gap):
		return false
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
				_put_fan(float(ob["s"]) + rng.randf_range(-6.0, 6.0), (1.0 if k % 2 == 0 else -1.0) * (rng.randf_range(1.2, 2.0) + ROAD_GROW), rng)
	_put_static(2, {"kind": "arch", "s": 0.0, "label": "START"}, [])
	_put_static(2, {"kind": "arch", "s": length - 2.0, "label": "FINISH"}, [])
	var km := 500.0
	while km < length - 60.0:
		_put_static(2, {"kind": "sign", "s": km, "label": "%.1f km" % (km / 1000.0)}, [])
		km += 500.0
	_build_course_signs(rng)
	for k in 18:
		_put_fan(rng.randf_range(0.0, 30.0) if k < 9 else length - rng.randf_range(0.0, 30.0),
			(1.0 if rng.randf() < 0.5 else -1.0) * (rng.randf_range(1.1, 2.4) + ROAD_GROW), rng)


## Tunnels bored through the hillside along a straight stretch of a few of the middle legs.
func _build_tunnels(rng: RandomNumberGenerator) -> void:
	tunnels.clear()
	var length: float = course["length"]
	var legs: Array = range(1, legs_n - 1)
	for q in range(legs.size() - 1, 0, -1):
		legs.push_back(legs.pop_at(rng.randi() % (q + 1)))
	var want := int(course.get("tunnels", 0))
	for k in legs:
		if tunnels.size() >= want:
			break
		var ia := -1
		var ib := -1
		for i in M:
			if road_leg[i] == k:
				if ia < 0:
					ia = i
				ib = i
		var n := int(rng.randf_range(80.0, 110.0) / ds_m)
		if ia < 0 or ib - ia < n + 50:   # room for the tunnel and a run-in either side
			continue
		var i0 := ia + int((ib - ia - n) * rng.randf_range(0.3, 0.6))
		var s0 := s_m[i0]
		var s1 := s_m[i0 + n]
		if s0 < 300.0 or s1 > length - 220.0:
			continue
		var ok := true
		for t in tunnels:
			ok = ok and (absf(float(t["s0"]) - s0) > 500.0)
		if ok:
			tunnels.append({"s0": s0, "s1": s1, "i0": i0, "i1": i0 + n, "a": 1.0, "called": false})


## The mound over a tunnel: a hillside strip along the road, drawn over the road (so riders vanish into it unless it is
## see-through), with a stone portal at the end the camera sees.
## (the sides stand ROAD_GROW further out than they were first drawn, round the wider road; the same goes for the portal)
const TUN_PROFILE := [[-1.9 - ROAD_GROW, 0.0], [-1.6 - ROAD_GROW, 34.0], [-0.95 - ROAD_GROW, 50.0], [0.0, 56.0], [0.95 + ROAD_GROW, 50.0],
	[1.6 + ROAD_GROW, 34.0], [1.9 + ROAD_GROW, 0.0]]
const TUN_RING := [[-1.25 - ROAD_GROW, 0.0], [-1.25 - ROAD_GROW, 27.0], [-0.75 - ROAD_GROW, 41.0], [0.0, 45.0], [0.75 + ROAD_GROW, 41.0],
	[1.25 + ROAD_GROW, 27.0], [1.25 + ROAD_GROW, 0.0]]
const TUN_HOLE := [[-0.95 - ROAD_GROW, 0.0], [-0.95 - ROAD_GROW, 24.0], [-0.55 - ROAD_GROW, 36.0], [0.0, 39.0], [0.55 + ROAD_GROW, 36.0],
	[0.95 + ROAD_GROW, 24.0], [0.95 + ROAD_GROW, 0.0]]
const TUN_SHADE := [0.72, 0.86, 1.08, 1.04, 0.9, 0.7]
const TUN_STEP := 4   # road samples per piece


func _tun_p(i: int, lat: float, z: float) -> Vector2:
	return Iso.to_screen(pts[i] + nrm[i] * lat, elev[i] * vz + z)


func _draw_tunnel_piece(it: Dictionary) -> void:
	var t: Dictionary = tunnels[int(it["t"])]
	var a: float = t["a"]
	var ia: int = it["ia"]
	var ib: int = it["ib"]
	var cover: float = it["cover"]
	var grass := Color(0.36, 0.58, 0.3).lerp(Color(0.56, 0.6, 0.34), clampf(float(ia) / float(M) * 1.5, 0.0, 1.0))
	var base := grass.lerp(Color(0.94, 0.96, 1.0), cover * 0.95)
	for k in 6:
		var col := Iso.shade(base, TUN_SHADE[k] * (0.97 + 0.06 * float((ia / TUN_STEP) % 2)))
		col.a = a
		var q := PackedVector2Array([_tun_p(ia, TUN_PROFILE[k][0], TUN_PROFILE[k][1]), _tun_p(ib, TUN_PROFILE[k][0], TUN_PROFILE[k][1]),
			_tun_p(ib, TUN_PROFILE[k + 1][0], TUN_PROFILE[k + 1][1]), _tun_p(ia, TUN_PROFILE[k + 1][0], TUN_PROFILE[k + 1][1])])
		draw_colored_polygon(q, col)
	if a < 0.95:   # inside: it is dim, with a lamp every few metres
		var w := 0.95 + ROAD_GROW
		var gloom := PackedVector2Array([_tun_p(ia, -w, 1.0), _tun_p(ib, -w, 1.0), _tun_p(ib, w, 1.0), _tun_p(ia, w, 1.0)])
		draw_colored_polygon(gloom, Color(0.02, 0.02, 0.1, 0.5 * (1.0 - a)))
		var lamp := _tun_p(ia, 0.0, 46.0)
		draw_circle(lamp, 9.0, Color(1.0, 0.85, 0.4, 0.12 * (1.0 - a)))
		draw_circle(lamp, 3.0, Color(1.0, 0.9, 0.5, 0.9 * (1.0 - a)))
	if it.get("portal", false):
		var stone := Color(0.55, 0.52, 0.5)
		var edge := Color(0.14, 0.12, 0.14)
		var pa := lerpf(a, 1.0, 0.5)
		var outer := PackedVector2Array()
		for pr in TUN_PROFILE:
			outer.append(_tun_p(ib if it["at_b"] else ia, pr[0], pr[1]))
		draw_colored_polygon(outer, Color(stone.r, stone.g, stone.b, pa))
		var j: int = ib if it["at_b"] else ia
		var ring := PackedVector2Array()
		for pr in TUN_RING:
			ring.append(_tun_p(j, pr[0], pr[1]))
		draw_colored_polygon(ring, Color(0.72, 0.69, 0.66, pa))
		var hole := PackedVector2Array()
		for pr in TUN_HOLE:
			hole.append(_tun_p(j, pr[0], pr[1]))
		draw_colored_polygon(hole, Color(0.03, 0.03, 0.06, 0.85 * pa))
		draw_polyline(outer, Color(edge.r, edge.g, edge.b, pa), 1.0)
		draw_polyline(hole, Color(edge.r, edge.g, edge.b, pa), 1.0)
		draw_circle(_tun_p(j, 0.0, 49.0), 2.0, Color(1.0, 0.85, 0.35, pa))


## Signs along the climb that tell you what is coming: hairpins, tunnels, steep ramps, descents and the snow line,
## chevron boards round the outside of every hairpin, and the tunnel mounds themselves.
func _build_course_signs(rng: RandomNumberGenerator) -> void:
	var length: float = course["length"]
	# steep ramps and fast descents
	ramps.clear()
	var i := 0
	while i < M and s_m[i] < length - 40.0:
		var steep := grade_a[i] >= 0.088
		var drop := grade_a[i] <= -0.06
		if steep or drop:
			var j := i
			while j < M - 1 and (grade_a[j + 1] >= 0.088 if steep else grade_a[j + 1] <= -0.06):
				j += 1
			if s_m[j] - s_m[i] >= 60.0 and s_m[i] > 80.0 and not _in_tunnel(s_m[i], 30.0):
				var gm := 0.0
				for q in range(i, j + 1):
					gm = maxf(gm, absf(grade_a[q]))
				ramps.append({"s0": s_m[i], "s1": s_m[j], "g": gm, "up": steep, "called": false})
			i = j + 1
		else:
			i += 1
	# the boards, hairpins and tunnels first, so they are never crowded out
	var boards: Array = []
	for h in hairpins:
		boards.append({"s": float(h["s"]) - 105.0, "icon": "left" if h["left"] else "right", "l1": "HAIRPIN", "l2": "%d of %d" % [h["n"], hairpins.size()]})
	for t in tunnels:
		boards.append({"s": float(t["s0"]) - 105.0, "icon": "tunnel", "l1": "TUNNEL", "l2": "%d m" % int(float(t["s1"]) - float(t["s0"]))})
	var placed: Array = []
	for b in boards:
		placed.append(float(b["s"]))
	var extra: Array = []
	for r in ramps:
		extra.append({"s": float(r["s0"]) - 40.0, "icon": "up" if r["up"] else "down", "l1": "STEEP" if r["up"] else "DROP", "l2": "%d%%" % roundi(float(r["g"]) * 100.0)})
	# where the snow starts
	var snow_s := -1.0
	for q in M:
		if s_m[q] > 60.0 and s_m[q] < length and _snow_cover(pts[q].x, pts[q].y, elev[q] * vz / peak) > 0.5:
			snow_s = s_m[q]
			break
	if snow_s > 0.0:
		extra.append({"s": snow_s - 10.0, "icon": "snow", "l1": "SNOW", "l2": "LINE"})
	for b in extra:
		var ok := float(b["s"]) > 30.0
		for ps in placed:
			ok = ok and absf(float(ps) - float(b["s"])) > 70.0
		if ok and not _in_tunnel(float(b["s"]), 5.0):
			boards.append(b)
			placed.append(float(b["s"]))
	for b in boards:
		if float(b["s"]) < 30.0:
			continue
		var pz := _pose(float(b["s"]), 0.0)
		var n: Vector2 = pz["n"]
		var side := 1.0 if n.y >= 0.0 else -1.0
		b["kind"] = "board"
		b["side"] = side
		_put_static(2, b, [])
	# chevrons round the outside of each hairpin
	for h in hairpins:
		var c: Vector2 = h["c"]
		var dx: float = h["dx"]
		for fr in [0.18, 0.34, 0.5, 0.66, 0.82]:
			var a: float = PI * fr
			var dirv := Vector2(sin(a) * dx, cos(a))
			var p := c + dirv * (HAIRPIN_R + 1.5 + ROAD_GROW)
			var tv := Vector2(cos(a) * dx, -sin(a))
			_put_static(2, {"kind": "chevron", "pos": p, "z": _tz(p), "tan": tv, "s": float(h["s"])}, [])
	# the tunnel mounds: one piece per few road samples, in the bucket just after the riders on it
	for ti in tunnels.size():
		var t: Dictionary = tunnels[ti]
		var i0: int = t["i0"]
		var i1: int = t["i1"]
		var at_b := pts[i1].x > pts[i0].x   # the end with the larger x faces the camera
		var q := i0
		while q < i1:
			var qb := mini(q + TUN_STEP, i1)
			var far := pts[qb] if pts[qb].x > pts[q].x else pts[q]
			var cover := _snow_cover(far.x, far.y, elev[q] * vz / peak)
			var portal := (qb == i1 and at_b) or (q == i0 and not at_b)
			_put_static(6, {"kind": "tunnel", "t": ti, "ia": q, "ib": qb, "cover": cover, "portal": portal, "at_b": qb == i1 and at_b, "pos": far + Vector2(1.6 + ROAD_GROW, 0.0)}, [])
			q = qb


func _draw_board(e: Dictionary) -> void:
	var pz: Dictionary = e["pz"]
	var b := Iso.to_screen(pz["pos"] + (pz["n"] as Vector2) * (1.45 + ROAD_GROW) * float(e["side"]), pz["z"])
	var ink := Color(0.1, 0.1, 0.15)
	var yellow := Color(1.0, 0.82, 0.12)
	draw_line(b + Vector2(-16, 0), b + Vector2(-16, -14), ink, 2.0)
	draw_line(b + Vector2(16, 0), b + Vector2(16, -14), ink, 2.0)
	var r := Rect2(b + Vector2(-33, -38), Vector2(66, 25))
	draw_rect(Rect2(r.position + Vector2(1, 1), r.size), Color(0, 0, 0, 0.3))
	draw_rect(r, ink)
	draw_rect(r.grow(-1.5), yellow if e["icon"] != "snow" else Color(0.85, 0.93, 1.0))
	var ic := b + Vector2(-20, -25)
	match e["icon"]:
		"left", "right":
			var m := -1.0 if e["icon"] == "left" else 1.0   # a U-turn arrow bending to that side
			draw_polyline(PackedVector2Array([ic + Vector2(-m * 4, 7), ic + Vector2(-m * 4, -2), ic + Vector2(-m * 2, -5), ic + Vector2(m * 2, -5),
				ic + Vector2(m * 4, -2), ic + Vector2(m * 4, 4)]), ink, 2.0)
			draw_colored_polygon(PackedVector2Array([ic + Vector2(m * 4, 8), ic + Vector2(m * 7, 3), ic + Vector2(m * 1, 3)]), ink)
		"up", "down":
			var m := 1.0 if e["icon"] == "up" else -1.0
			draw_colored_polygon(PackedVector2Array([ic + Vector2(-8, m * 5), ic + Vector2(8, m * 5), ic + Vector2(0, -m * 6)]), ink)
			draw_colored_polygon(PackedVector2Array([ic + Vector2(-5, m * 4), ic + Vector2(5, m * 4), ic + Vector2(0, -m * 2)]), Color(1.0, 0.45, 0.1))
		"tunnel":
			draw_polyline(PackedVector2Array([ic + Vector2(-7, 7), ic + Vector2(-7, -1), ic + Vector2(-4, -5), ic + Vector2(4, -5), ic + Vector2(7, -1), ic + Vector2(7, 7)]), ink, 2.0)
			draw_rect(Rect2(ic + Vector2(-3, 0), Vector2(6, 7)), ink)
		"train":
			draw_rect(Rect2(ic + Vector2(-7, -4), Vector2(14, 8)), ink)
			draw_rect(Rect2(ic + Vector2(-5, -6), Vector2(5, 3)), ink)
			draw_circle(ic + Vector2(-4, 5), 2.0, ink)
			draw_circle(ic + Vector2(4, 5), 2.0, ink)
		"snow":
			for a in 3:
				var d := Vector2.from_angle(a * PI / 3.0) * 7.0
				draw_line(ic - d, ic + d, Color(0.2, 0.4, 0.8), 1.5)
	draw_string(font, b + Vector2(-9, -29), e["l1"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, ink)
	draw_string(font, b + Vector2(-9, -19), e["l2"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, ink)


func _draw_chevron(e: Dictionary) -> void:
	var b := Iso.to_screen(e["pos"], e["z"])
	var ink := Color(0.1, 0.1, 0.15)
	draw_line(b, b + Vector2(0, -12), ink, 2.0)
	var r := Rect2(b + Vector2(-7, -30), Vector2(14, 18))
	draw_rect(r, ink)
	draw_rect(r.grow(-1.0), Color(1.0, 0.82, 0.12))
	var tdir := (Iso.to_screen((e["pos"] as Vector2) + (e["tan"] as Vector2) * 0.2, e["z"]) - b).normalized()
	var perp := Vector2(-tdir.y, tdir.x)
	var bc := b + Vector2(0, -21)
	draw_polyline(PackedVector2Array([bc - tdir * 3.0 + perp * 4.0, bc + tdir * 3.0, bc - tdir * 3.0 - perp * 4.0]), ink, 2.0)


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
			if course.get("flowers", false):
				forest = smoothstep(-0.3, 0.6, _biome(x, y) - 1.5)
				chance = 0.01 + 0.3 * forest
			if f > 0.8:
				chance *= 0.3
			if f > 0.9:
				chance = 0.0
			var snow := _snow_cover(x, y, f) > 0.5
			var roll := rng.randf()
			var sd := _stream_d(x, y)
			if _rd(p) < 2.0 + ROAD_GROW or sd < 1.0 or (life.rail_x >= 0.0 and absf(x - life.rail_x) < 1.1 and y > life.rail_y0 - 1.0 and y < life.rail_y1 + 1.0):
				continue
			var cc := cell_cliff[j * gw + i]
			if cc == 2:
				continue
			if cc == 1:   # loose rock and the odd stunted pine on the ledges
				if roll < 0.12:
					_put_static(3, {"pos": p, "z": z, "size": rng.randf_range(0.5, 1.2), "h": rng.randi(), "snow": snow}, [])
				elif roll < 0.16:
					_put_static(1, {"pos": p, "z": z, "s": rng.randf_range(0.6, 0.9), "sp": "snag" if roll < 0.13 else "pine", "snow": snow, "h": rng.randi()}, [])
				continue
			var rock_chance := 0.09 if f > 0.85 else 0.04 if snow else 0.015
			if roll < chance:
				# conifers up high and in the forest, broadleaves lower down and out in the meadows, willows by the creeks
				var r2 := rng.randf()
				var sp := "pine"
				if snow:
					sp = "snag" if r2 < 0.05 else "pine"
				elif r2 < 0.04:
					sp = "snag"
				elif r2 < 0.06:
					sp = "stump"
				elif sd < 2.4 and r2 < 0.3:
					sp = "willow"
				elif f > 0.55 or forest > 0.6:
					sp = ["pine", "pine", "pine_light", "spruce", "fir", "larch", "larch"][rng.randi() % 7]
				else:
					sp = ["oak", "birch", "birch", "maple", "aspen", "aspen", "cherry", "pine_light", "pine"][rng.randi() % 9]
				_put_static(1, {"pos": p, "z": z, "s": rng.randf_range(0.8, 1.4), "sp": sp, "snow": snow, "h": rng.randi()}, [])
			elif roll < chance + rock_chance:
				_put_static(3, {"pos": p, "z": z, "size": rng.randf_range(0.6, 1.5), "h": rng.randi(), "snow": snow}, [])
			elif roll < chance + rock_chance + (0.1 if sd < 2.2 else 0.05):
				# ground plants: reeds and wet stones on the creek banks, ferns, berries and mushrooms in the forest,
				# wildflowers and long grass out in the meadows
				var r3 := rng.randf()
				var kind := "bush"
				if sd < 2.2:
					kind = "reeds" if r3 < 0.6 else "stones"
				elif snow:
					kind = "bush" if r3 < 0.5 else "stones"
				elif forest > 0.5:
					kind = ["bush", "bush", "mushrooms", "grass"][rng.randi() % 4]
				else:
					kind = ["flowers", "flowers", "flowers", "grass", "grass", "bush"][rng.randi() % 6]
				_put_static(7, {"pos": p, "z": z, "kind": kind, "h": rng.randi(), "snow": snow, "scale": rng.randf_range(0.8, 1.15)}, [])


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
			if _rd(mid) > 0.95 + ROAD_GROW and mid.x > ox and mid.x < ox + gw:   # off the road: a ford's water covers it there
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
		var edge := PackedVector2Array([Iso.to_screen(pa - ua * ROAD_HW, za), Iso.to_screen(pb - ub * ROAD_HW, zb),
			Iso.to_screen(pb + ub * ROAD_HW, zb), Iso.to_screen(pa + ua * ROAD_HW, za)])
		var pb2 := pb + (pb - pa).normalized() * 0.08   # overlap the next piece a little, so no seam shows between them
		var gravel_hw := 0.52 * ROAD_W   # the gravel, inside the dirt edge
		var gravel := PackedVector2Array([Iso.to_screen(pa - ua * gravel_hw, za + 0.3), Iso.to_screen(pb2 - ub * gravel_hw, zb + 0.3),
			Iso.to_screen(pb2 + ub * gravel_hw, zb + 0.3), Iso.to_screen(pa + ua * gravel_hw, za + 0.3)])
		var ruts: Array = []
		for off in [-0.25 * ROAD_W, 0.25 * ROAD_W]:
			ruts.append(PackedVector2Array([Iso.to_screen(pa + ua * (off - 0.07), za + 0.5), Iso.to_screen(pb + ub * (off - 0.07), zb + 0.5),
				Iso.to_screen(pb + ub * (off + 0.07), zb + 0.5), Iso.to_screen(pa + ua * (off + 0.07), za + 0.5)]))
		var pebbles := PackedVector2Array()
		for k in 6:   # more of them on the wider road, so it isn't bare
			var f := fposmod(i * 0.618 + k * 0.29, 1.0)
			var lat := (fposmod(i * 0.377 + k * 0.382, 1.0) - 0.5) * ROAD_W
			pebbles.append(Iso.to_screen(pa.lerp(pb, f) + ua * lat, lerpf(za, zb, f) + 0.6))
		var snow := _snow_cover(pa.x, pa.y, elev[i] * vz / peak)
		var seg := {"edge": edge, "gravel": gravel, "ruts": ruts, "pebbles": pebbles, "shade": 0.92 + 0.08 * float(i % 2), "snow": snow,
			"light": Ground.band(1.0 - clampf(grade_a[i], -0.1, 0.12) * 1.6)}
		# a chevron painted on the road every 40 m or so, pointing the way, coloured by how steep it is
		if i % 24 == 12 and s_m[i] < float(course["length"]):
			var t := (pb - pa).normalized()
			var n := Vector2(-t.y, t.x)
			var g := grade_a[i]
			var col := Color(0.35, 0.65, 1.0) if g <= -0.02 else (Color(0.4, 0.85, 0.35) if g < 0.03 else (Color(1.0, 0.85, 0.2) if g < 0.06 else (Color(1.0, 0.5, 0.15) if g < 0.09 else Color(0.95, 0.2, 0.2))))
			var chev: Array = []
			for k in (2 if g >= 0.09 else 1):
				var c := pa + t * (k * 0.32 * ROAD_W)
				var cl := 0.16 * ROAD_W   # half its length along the road
				var cw := 0.32 * ROAD_W   # half its width across
				chev.append(PackedVector2Array([Iso.to_screen(c - t * cl + n * cw, za + 0.6), Iso.to_screen(c + t * cl, za + 0.6), Iso.to_screen(c - t * cl - n * cw, za + 0.6)]))
			seg["chev"] = chev
			seg["chev_col"] = col
		road_segs.append(seg)
		var d := _diag((pa + pb) * 0.5)
		if not road_buckets.has(d):
			road_buckets[d] = []
		road_buckets[d].append(i)


## What each kind of animal does (see _step_animals): the skittish ones bolt when a rider gets close, some dash across
## the course, others stand and watch, and deer-like animals come in small herds.
const FLEERS := ["deer", "fox", "squirrel", "rabbit", "elk", "wolf", "raccoon", "hedgehog", "chipmunk", "skunk", "otter", "coyote"]
const SMALL_FLEERS := ["squirrel", "rabbit", "hedgehog", "chipmunk", "skunk", "otter"]
const CROSSERS := ["deer", "fox", "squirrel", "elk", "wolf", "raccoon", "coyote"]
const WATCHERS := {"goat": "MEHH!", "marmot": "EEP!", "moose": "HRRMPH", "bighorn": "BAAH!", "badger": "HISS!", "mountain_lion": "HSSSS!", "porcupine": "RATTLE", "beaver": "THWAP!"}
const HERDERS := ["deer", "goat", "elk", "bighorn", "ram_lamb"]
const LITTLE := ["rabbit", "squirrel", "marmot", "hedgehog", "chipmunk", "skunk", "otter", "ram_lamb"]
const FLEE_SPEED := {"deer": 4.0, "fox": 3.5, "rabbit": 3.0, "squirrel": 2.5, "elk": 4.0, "wolf": 3.8, "raccoon": 3.0, "hedgehog": 2.0, "chipmunk": 3.0, "skunk": 2.5, "otter": 3.0, "coyote": 3.8}
const CROSS_SPEED := {"deer": 4.5, "fox": 4.0, "squirrel": 3.0, "elk": 4.5, "wolf": 4.2, "raccoon": 3.4, "coyote": 4.2}

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
			kind = "moose" if rng.randf() < 0.5 else "elk"
		elif f > 0.75:
			kind = "goat" if r < 0.25 else ("marmot" if r < 0.45 else ("bighorn" if r < 0.65 else ("badger" if r < 0.8 else ("bear" if r < 0.9 else "deer"))))
		else:
			for w in [["deer", 0.2], ["bear", 0.1], ["rabbit", 0.1], ["squirrel", 0.1], ["fox", 0.07], ["moose", 0.05], ["goat", 0.08], ["elk", 0.1],
					["wolf", 0.05], ["raccoon", 0.05], ["hedgehog", 0.04], ["chipmunk", 0.04], ["skunk", 0.04],
					["coyote", 0.04], ["otter", 0.03], ["beaver", 0.03], ["porcupine", 0.03], ["ram_lamb", 0.03], ["mountain_lion", 0.02]]:
				r -= float(w[1])
				if r <= 0.0:
					kind = w[0]
					break
			if kind == "":
				kind = "deer"
		if Sprites.sheet("animal_%s_idle" % kind) == null:
			kind = "deer"   # no art for this one (yet)
		if kind == "bear":
			last_bear = s
		var group := 1
		if kind in HERDERS:
			group = rng.randi_range(1, 3)
		elif kind in LITTLE:
			group = rng.randi_range(1, 2)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for q in group:
			var ss := s + rng.randf_range(-6.0, 6.0)
			var p: Vector2 = _pose(ss, side * (rng.randf_range(1.8, 4.2) + ROAD_GROW))["pos"]
			if _rd(p) < 1.4 + ROAD_GROW or _in_tunnel(ss, 14.0):
				continue
			animals.append({"kind": kind, "pos": p, "home": p, "s": ss, "side": side, "state": "idle", "t": rng.randf() * 3.0,
				"face": 1.0 if rng.randf() < 0.5 else -1.0, "vel": Vector2.ZERO, "phase": rng.randf() * TAU, "run": false,
				"cross": kind in CROSSERS and q == 0 and rng.randf() < 0.5, "stag": rng.randf() < 0.45,
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
			givers.append({"s": s, "lat": side * (1.25 + ROAD_GROW), "shirt": shirts[rng.randi() % shirts.size()],
				"skin": Color(0.96, 0.8, 0.65).lerp(Color(0.55, 0.38, 0.28), rng.randf()), "hair": Color(0.3, 0.2, 0.1).lerp(Color(0.9, 0.8, 0.4), rng.randf()),
				"phase": rng.randf() * TAU})
			side = -side
			s += rng.randf_range(300.0, 420.0)
		else:
			s += 20.0


## Seasonal scenery beside the course: snowmen and skiers in winter, pumpkins, leaf piles and hay bales in fall,
## tulip beds and butterflies in spring, picnics and kites in summer.
func _build_season() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(course["seed"]) * 7 + Season.ORDER.find(Season.current)
	var kinds: Array = {"winter": ["snowman", "snowman", "skier", "skier"], "fall": ["pumpkins", "leafpile", "hay"],
		"spring": ["flowers", "flowers", "butterfly"], "summer": ["picnic", "kite"]}[Season.current]
	var cols := [Color(0.95, 0.25, 0.25), Color(0.2, 0.55, 0.95), Color(1.0, 0.8, 0.15), Color(0.3, 0.8, 0.45), Color(0.85, 0.35, 0.85)]
	var length: float = course["length"]
	var s := 40.0
	while s < length - 40.0:
		s += rng.randf_range(35.0, 80.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p: Vector2 = _pose(s, side * (rng.randf_range(2.2, 4.0) + ROAD_GROW))["pos"]
		if _rd(p) < 1.8 + ROAD_GROW or _stream_d(p.x, p.y) < 1.2 or not _clear_of(s, 6.0) or _in_cliff(s, 8.0):
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		if kind == "skier":
			for k in 7:
				var q := p + Vector2(0.8 if k % 2 == 0 else -0.8, k * 0.5)
				if _rd(q) < 1.5 + ROAD_GROW or _stream_d(q.x, q.y) < 0.8:
					kind = "snowman"   # the run would cross the course or a creek
		_put_static(2, {"kind": kind, "s": s, "pos": p, "z": _tz(p), "sd": rng.randi() % 100, "ph": rng.randf() * TAU,
			"col": cols[rng.randi() % cols.size()]}, [p + Vector2(0, 3)] if kind == "skier" else [])


var guest := {}                  # a guest rider for this race (the Tour de Crankmore champion), or {}


func _build_riders() -> void:
	riders.clear()
	var b := Game.bike()
	riders.append({"name": Game.player_name, "color": Color(0.95, 0.95, 0.95), "frame": b["color"], "s": 0.0, "v": 0.0, "lat": 0.0,
		"bike": b, "player": true, "phase": 0.0, "done": false, "time": 0.0, "mass": Game.weight_kg, "power": 0.0,
		"air": 0.0, "air_tot": 1.0, "air_h": 0.0, "land": 0.0, "ob": 0, "wet": false,
		"pu": "", "pu_hold": 0.0, "socks": 0.0, "bread": 0.0, "roller": 0.0, "down": 0.0, "fall": 0.0, "gv": 0, "draft": 0.0})
	# a race with the champion brings out the whole roster, not just your usual rivals
	var field: Array = Talk.roster if not guest.is_empty() and not rescue else Talk.rivals
	var n := field.size()
	for i in n:
		var info: Dictionary = field[i]
		var mass := Game.rival_mass(i)
		var lane := ((i - (n - 1) * 0.5) * 0.1 + 0.05) * ROAD_W   # spread across the road
		riders.append({"name": info["name"], "short": info["short"], "color": info["color"], "frame": Color(info["color"]).lerp(Color.WHITE, 0.2),
			"s": 0.0, "v": 0.0, "lat": lane, "lane": lane, "bike": Game.rival_bike(info), "player": false,
			"phase": randf() * TAU, "done": false, "time": 0.0, "mass": mass, "ftp": Game.rival_ftp(info, mass), "idx": i if i < Talk.rivals.size() else -1, "sig": info["sig"],
			"surge": 0.0, "surge_in": randf_range(25.0, 50.0), "power": 0.0, "wiggle": randf() * TAU,
			"air": 0.0, "air_tot": 1.0, "air_h": 0.0, "land": 0.0, "ob": 0, "wet": false,
			"pu": "", "pu_hold": 0.0, "socks": 0.0, "bread": 0.0, "roller": 0.0, "down": 0.0, "fall": 0.0, "gv": 0, "draft": 0.0})
	if not guest.is_empty() and not rescue:
		# the champion: CHAMPION_EDGE harder than the strongest rival here (idx -1: he talks for himself, see _say)
		var top := 0.0
		for r in riders:
			if not r["player"]:
				top = maxf(top, float(r["ftp"]) / float(r["mass"]))
		var mass := 68.0
		var lane := -0.45 * ROAD_W
		riders.append({"name": guest["name"], "short": guest["short"], "color": guest["color"], "frame": Color(guest["color"]).lerp(Color.WHITE, 0.2),
			"s": 0.0, "v": 0.0, "lat": lane, "lane": lane, "bike": Game.rival_bike(guest), "player": false, "guest": true,
			"phase": randf() * TAU, "done": false, "time": 0.0, "mass": mass, "ftp": maxf(top, Game.wkg()) * Game.CHAMPION_EDGE * mass, "idx": -1,
			"surge": 0.0, "surge_in": randf_range(25.0, 50.0), "power": 0.0, "wiggle": randf() * TAU,
			"air": 0.0, "air_tot": 1.0, "air_h": 0.0, "land": 0.0, "ob": 0, "wet": false,
			"pu": "", "pu_hold": 0.0, "socks": 0.0, "bread": 0.0, "roller": 0.0, "down": 0.0, "fall": 0.0, "gv": 0, "draft": 0.0})
		Game.toast.emit("%s lines up beside you in the yellow jersey!" % guest["name"], guest["color"])


## A rider says something: one of your usual rivals through Talk; the guest champion, or a rival who only came out for
## his race, one of their own lines over their head.
func _say(r: Dictionary, cat: String, force := false) -> void:
	if int(r["idx"]) >= 0:
		Talk.say(int(r["idx"]), cat, force)
	elif force or randf() < 0.5:
		var text: String = (guest["sig"] if r.get("guest", false) else r["sig"]).pick_random()
		_pop(riders.find(r), text, r["color"])
		Game.racer_says.emit(String(r["short"]).to_lower(), r["name"], text, Talk.MOODS.get(cat, "smug"), r["color"])


# ---------------------------------------------------------------------
# Pose helpers
# ---------------------------------------------------------------------

## Heads-up for the player: tunnels go see-through while you are in them, and toasts call out hairpins, tunnels, steep
## ramps, descents and the snow line before you get there.
func _course_notices(delta: float) -> void:
	if riders.is_empty():
		return
	var s: float = riders[0]["s"]
	for t in tunnels:
		var inside: bool = s > float(t["s0"]) - 12.0 and s < float(t["s1"]) + 6.0
		t["a"] = move_toward(float(t["a"]), 0.3 if inside else 1.0, delta * 2.5)
		if not t["called"] and s > float(t["s0"]) - 120.0 and s < float(t["s0"]):
			t["called"] = true
			Game.toast.emit("TUNNEL ahead: %d m of dark road, lights on!" % int(float(t["s1"]) - float(t["s0"])), Color(1.0, 0.85, 0.4))
	if countdown > 0.0 or over:
		return
	for h in hairpins:
		if not h["called"] and s > float(h["s"]) - 120.0 and s < float(h["s"]):
			h["called"] = true
			Game.toast.emit("SWITCHBACK %d of %d: sharp %s ahead!" % [h["n"], hairpins.size(), "LEFT" if h["left"] else "RIGHT"], Color(1.0, 0.9, 0.2))
	for r in ramps:
		if not r["called"] and s > float(r["s0"]) - 45.0 and s < float(r["s0"]):
			r["called"] = true
			if r["up"]:
				Game.toast.emit("STEEP RAMP: %d%% for %d m. Dig in!" % [roundi(float(r["g"]) * 100.0), int(float(r["s1"]) - float(r["s0"]))], Color(1.0, 0.5, 0.2))
			else:
				Game.toast.emit("FAST DROP: %d%% downhill. Let it fly!" % roundi(float(r["g"]) * 100.0), Color(0.5, 0.9, 1.0))
	if not snow_called:
		var p: Vector2 = _pose(s, 0.0)["pos"]
		if _snow_cover(p.x, p.y, _tz(p) / peak) > 0.5:
			snow_called = true
			Game.toast.emit("SNOW LINE! It is cold up here, even in summer.", Color(0.8, 0.92, 1.0))


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
		if rescue:
			if float(riders[0]["s"]) >= rescue_s and not over:
				_end_rescue()
		else:
			_banter()
	_step_animals(delta)
	_step_patrol(delta)
	for k in bubbles.keys():
		bubbles[k]["t"] -= delta
		if bubbles[k]["t"] <= 0.0:
			bubbles.erase(k)
	for i in range(pops.size() - 1, -1, -1):
		pops[i]["t"] -= delta
		if pops[i]["t"] <= 0.0:
			pops.remove_at(i)
	kick_t = maxf(0.0, kick_t - delta)
	_course_notices(delta)
	if life != null:
		life.update(delta)
	var me: Dictionary = riders[0]
	var g := PowerUps.felt_grade(_grade_at(me["s"]), me["roller"]) + (0.06 if kick_t > 0.0 else 0.0) + (0.03 if me["wet"] else 0.0)
	Trainer.send_grade(g * 100.0 if countdown <= 0.0 and not over else 0.0)
	queue_redraw()


func _step_riders(delta: float) -> void:
	var length: float = course["length"]
	# player
	var me: Dictionary = riders[0]
	# the player keeps riding past the finish, down the run-out
	_tick_powerups(0, delta)
	var g := PowerUps.felt_grade(_grade_at(me["s"]), me["roller"])
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
	# in a slipstream the same speed takes fewer watts, so your watts go further
	me["draft"] = _draft(0)
	var mvt := Game.speed_from_power(p / (1.0 - float(me["draft"])), b["mass"], b["cda"], _crr(b) + (FORD_CRR if me["wet"] else 0.0), g)
	if Game.hp_ratio() < 0.3:
		mvt *= 0.92
	if Input.is_action_just_pressed("powerup"):
		_use_powerup(0)
	if float(me["socks"]) > 0.0:
		mvt *= PowerUps.SOCKS_BOOST
	if float(me["down"]) > 0.0:
		mvt = 0.0
		me["v"] = move_toward(me["v"], 0.0, 14.0 * delta)
	if float(me["air"]) <= 0.0:   # no traction in the air
		me["v"] += (minf(mvt, MAX_SPEED) - me["v"]) * (1.0 - exp(-1.5 * delta))
	var steer := clampf(Input.get_axis("steer_left", "steer_right") + Input.get_axis("lane_left", "lane_right"), -1.0, 1.0)
	if not patrol.is_empty() and float(me["down"]) > 0.0:
		steer = 0.0   # lying in the road while the ski patrol sees to you
	me["lat"] = clampf(me["lat"] + steer * 1.1 * ROAD_W * delta, -0.4 * ROAD_W, 0.4 * ROAD_W)
	me["s"] += me["v"] * delta
	if me["s"] >= road_len:
		me["s"] = road_len
		me["v"] = 0.0
	me["phase"] += (Trainer.cadence() if Trainer.cadence() > 1.0 else me["v"] * 14.0) / 60.0 * TAU * delta
	_terrain_events(0, delta)
	if me["s"] >= length and not me["done"]:
		_finish(0)
	idle_t = idle_t + delta if me["done"] and me["v"] < 0.5 else 0.0
	# rivals
	for k in range(1, riders.size()):
		var r: Dictionary = riders[k]
		if r["done"]:   # soft-pedal down the run-out, stopping at the end of the road
			r["v"] = move_toward(r["v"], COOL_SPEED if r["s"] < road_len - 1.0 else 0.0, 2.0 * delta)
			r["s"] = minf(r["s"] + r["v"] * delta, road_len)
			r["phase"] += r["v"] * 14.0 / 60.0 * TAU * delta
			continue
		r["surge_in"] -= delta
		if r["surge_in"] <= 0.0:
			r["surge"] = 6.0
			r["surge_in"] = randf_range(30.0, 60.0)
		var pw: float = r["ftp"] * (Game.rival_share() + 0.04 * sin(clock * 0.21 + r["wiggle"]))
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
		_tick_powerups(k, delta)
		r["draft"] = _draft(k)
		var vt := Game.speed_from_power(pw / (1.0 - float(r["draft"])), bk["mass"], bk["cda"], _crr(bk) + (FORD_CRR if r["wet"] else 0.0),
			PowerUps.felt_grade(_grade_at(r["s"]), r["roller"]), r["mass"])
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
		r["lat"] = r["lane"] + sin(clock * 0.6 + r["wiggle"]) * 0.08 * ROAD_W
		r["phase"] += r["v"] * 14.0 / 60.0 * TAU * delta
		_terrain_events(k, delta)
		if r["s"] >= length:
			_finish(k)
	_step_frisbees(delta)
	_squash()
	if finish_count > 0 and not over:
		over_clock += delta
	# results once you reach the end of the run-out (or stop on it); a 7 minute cut-off if you never finish
	if not over and ((me["done"] and (me["s"] >= road_len or idle_t > IDLE_END)) or (not me["done"] and over_clock > 420.0)):
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


## Share of the watts rider `i` saves in the slipstream of someone 1-9 m ahead in the same line (0 if none).
## Everyone drafts: you, and the rivals off you and each other.
func _draft(i: int) -> float:
	var me: Dictionary = riders[i]
	for k in riders.size():
		if k == i:
			continue
		var o: Dictionary = riders[k]
		if o["done"] or float(o["down"]) > 0.0:   # nobody to hide behind
			continue
		var d: float = o["s"] - me["s"]
		if d > 1.0 and d < 9.0 and absf(o["lat"] - me["lat"]) < 0.35 * ROAD_W:   # the same line, on the wider road's wider lanes
			return draft_saving(float(me["v"]) * 3.6)
	return 0.0


static func draft_saving(kmh: float) -> float:
	for j in range(1, DRAFT_CURVE.size()):
		var a: Array = DRAFT_CURVE[j - 1]
		var b: Array = DRAFT_CURVE[j]
		if kmh <= float(b[0]):
			return lerpf(a[1], b[1], (kmh - float(a[0])) / (float(b[0]) - float(a[0])))
	return DRAFT_CURVE[DRAFT_CURVE.size() - 1][1]


# ---------------------------------------------------------------------
# Power-ups (see PowerUps): frisbee, socks and breadsticks, handed out along the course
# ---------------------------------------------------------------------

func _tick_powerups(k: int, delta: float) -> void:
	var r: Dictionary = riders[k]
	r["socks"] = maxf(0.0, float(r["socks"]) - delta)
	r["bread"] = maxf(0.0, float(r["bread"]) - delta)
	r["roller"] = maxf(0.0, float(r["roller"]) - delta)
	if float(r["down"]) > 0.0:
		r["fall"] = float(r["fall"]) + delta
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


## Metres between two riders, counting the sideways gap across the road (as it was before the road was widened, so a
## rival a lane or two over is in reach as before).
func _gap_m(a: int, b: int) -> float:
	var ra: Dictionary = riders[a]
	var rb: Dictionary = riders[b]
	return Vector2(float(rb["s"]) - float(ra["s"]), (float(rb["lat"]) - float(ra["lat"])) / ROAD_W * M_PER_TILE).length()


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
			Sprites.start_throw("YOU" if r["player"] else str(r["short"]))
		"socks":
			r["socks"] = PowerUps.SOCKS_TIME
			_pop(k, "FIRE SOCKS!", PowerUps.col(kind))
		"breadsticks":
			r["bread"] = PowerUps.BREAD_TIME
			_pop(k, "BREADSTICKS!", PowerUps.col(kind))
		"roller":
			r["roller"] = PowerUps.ROLLER_TIME
			_pop(k, "DOUGH ROLLER!", PowerUps.col(kind))
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
		"roller":
			return _grade_at(r["s"]) > 0.04 or hold > 40.0
	return false


func _knock_down(k: int, secs: float, by: int, how: String) -> void:
	var r: Dictionary = riders[k]
	r["down"] = secs
	r["fall"] = 0.0
	_pop(k, "SPLAT!", Color(1.0, 0.5, 0.35))
	if r["player"]:
		Game.toast.emit("%s %s! Down for %d s." % [riders[by]["short"], how, int(secs)], Color(1.0, 0.45, 0.35))
		_say(riders[by], "pu_hit_player", true)
	elif riders[by]["player"]:
		_say(r, "pu_ouch", true)


## The bear caught you: you wipe out and are down BEAR_DOWN seconds while the ski patrol swaps your bike for a new
## one (see _patrol_at). The bike is replaced, so it isn't damaged.
func _bear_wipeout() -> void:
	var me: Dictionary = riders[0]
	me["down"] = BEAR_DOWN
	me["fall"] = 0.0
	me["socks"] = 0.0
	patrol = {"t": 0.0, "st": {}}
	_pop(0, "CRASH!", Color(1.0, 0.5, 0.35))
	Game.toast.emit("The bear got you! Wipe-out! Ski patrol is on the way...", Color(1.0, 0.45, 0.3))


## Moves the bear rescue on (see patrol): where you and your bike lie is fixed once you've stopped sliding.
func _step_patrol(delta: float) -> void:
	if patrol.is_empty():
		return
	patrol["t"] = float(patrol["t"]) + delta
	var t: float = patrol["t"]
	var me: Dictionary = riders[0]
	if t >= SP_LIE and not patrol.has("lie"):
		var lp: Vector2 = _pose(me["s"], me["lat"])["pos"]
		patrol["lie"] = lp
		# the bike lies on the road a body's length behind or ahead of you, whichever is further across the screen
		var back := _pose(float(me["s"]) - 2.6, me["lat"])
		var ahead := _pose(float(me["s"]) + 2.6, me["lat"])
		var wide := func(pz: Dictionary) -> float: return absf((pz["pos"] - lp).x - (pz["pos"] - lp).y)
		var bz: Dictionary = back if float(wide.call(back)) >= float(wide.call(ahead)) else ahead
		patrol["bike"] = bz["pos"]
		patrol["bike_z"] = bz["z"]
		# off screen straight across it, on the bike's side (along the hillside: downhill the ground drops away fast)
		var side := 1.0 if (patrol["bike"] - lp).x - (patrol["bike"] - lp).y >= 0.0 else -1.0
		var across := Vector2(side, -side).normalized()
		var vr: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
		var sx := Iso.to_screen(_patrol_stand(), patrol["bike_z"]).x
		var px := absf((vr.end.x if side > 0.0 else vr.position.x) - sx) + SP_MARGIN
		patrol["off"] = _patrol_stand() + across * maxf(px, 60.0) / (Iso.TW * 0.5 * (across.x - across.y) * side)
	if float(me["down"]) <= 0.0 and t > _sp_leave() + SP_WALK:
		patrol = {}
	elif t >= _sp_back() and t < _sp_back() + delta:
		Game.toast.emit("Ski patrol brought you a new bike!", Color(0.5, 1.0, 0.5))


## Where the patroller stands to pick up or put down the bike: just in front of it (lower on screen), so they're
## drawn over it.
func _patrol_stand() -> Vector2:
	return (patrol["bike"] as Vector2) + Vector2(0.45, 0.45)


func _sp_gone() -> float:   # the patroller is off screen with your old bike
	return SP_IN + SP_WALK + SP_LIFT + SP_WALK


func _sp_back() -> float:   # back with the new bike and setting it down
	return _sp_gone() + SP_AWAY + SP_WALK


func _sp_leave() -> float:   # walking off, empty-handed
	return _sp_back() + SP_SET


## The patroller at the rescue's time `t`: {pos (world), dir (heading), look ("walk" empty-handed or "push" wheeling
## a bike), moving}, or {} while they're out of the picture.
func _patrol_at(t: float) -> Dictionary:
	if not patrol.has("lie") or t < SP_IN:
		return {}
	var stand := _patrol_stand()
	var off: Vector2 = patrol["off"]
	var arrive := SP_IN + SP_WALK
	if t < arrive:
		return {"pos": off.lerp(stand, (t - SP_IN) / SP_WALK), "dir": stand - off, "look": "walk", "moving": true}
	if t < arrive + SP_LIFT:   # bends over the bike, then turns round with it
		var lifted := t >= arrive + SP_LIFT * 0.5
		return {"pos": stand, "dir": off - stand if lifted else stand - off, "look": "push" if lifted else "walk", "moving": false}
	if t < _sp_gone():
		return {"pos": stand.lerp(off, (t - arrive - SP_LIFT) / SP_WALK), "dir": off - stand, "look": "push", "moving": true}
	if t < _sp_gone() + SP_AWAY:
		return {}
	if t < _sp_back():
		return {"pos": off.lerp(stand, (t - _sp_gone() - SP_AWAY) / SP_WALK), "dir": stand - off, "look": "push", "moving": true}
	if t < _sp_leave():
		return {"pos": stand, "dir": stand - off, "look": "walk", "moving": false}
	if t < _sp_leave() + SP_WALK:
		return {"pos": stand.lerp(off, (t - _sp_leave()) / SP_WALK), "dir": off - stand, "look": "walk", "moving": true}
	return {}


## Which bike is lying on the ground next to you at the rescue's time `t`: "old", "new" or "" (none).
func _patrol_bike(t: float) -> String:
	if not patrol.has("lie"):
		return ""
	if t < SP_IN + SP_WALK + SP_LIFT * 0.5:
		return "old"
	if t >= _sp_back() and float(riders[0]["down"]) > SP_GETUP:
		return "new"
	return ""


func _draw_patroller(at: Dictionary) -> void:
	var p: Vector2 = at["pos"]
	var stand := _patrol_stand()
	# on the road where they stand by you, the hillside further out
	var z := lerpf(float(patrol["bike_z"]), _tz(p), clampf(p.distance_to(stand) / 2.0, 0.0, 1.0))
	var base := Iso.to_screen(p, z).round()
	_shadow(base, 9.0)
	var t: float = patrol["t"] if at["moving"] else 0.0
	Sprites.draw_person(self, "ped_ski_patrol_" + str(at["look"]), base, at["dir"], t, 12.0, Color.WHITE, patrol["st"])


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
			if absf(float(rb["s"]) - float(ra["s"])) < 1.8 and absf(float(rb["lat"]) - float(ra["lat"])) < 0.4 * ROAD_W:
				_knock_down(b, PowerUps.SQUASH_TIME, a, "flattened you with breadstick power")


func _bread_k(t: float) -> float:
	return 1.0 + (PowerUps.BREAD_SCALE - 1.0) * clampf(minf(PowerUps.BREAD_TIME - t, t) / 0.4, 0.0, 1.0) if t > 0.0 else 1.0


func _step_animals(delta: float) -> void:
	var me: Dictionary = riders[0]
	var ms: float = me["s"]
	for a in animals:
		var ds: float = float(a["s"]) - ms
		if absf(ds) > 120.0 and not a["state"] in ["rouse", "chase", "swipe"]:
			continue
		a["t"] = float(a["t"]) - delta
		a["phase"] = float(a["phase"]) + delta
		var kind: String = a["kind"]
		match a["state"]:
			"idle":
				a["run"] = false
				if not a["done"] and countdown <= 0.0:
					if kind in FLEERS:
						if a["cross"] and ds < 22.0 and ds > 2.0:
							_animal_cross(a)
						elif ds < (5.0 if kind in SMALL_FLEERS else 9.0) and ds > -3.0:
							_animal_flee(a, 1.4)
					elif kind == "bear" and ds <= 0.0 and ds > -3.0 and not me["done"]:
						# you've just gone by: it rears up and roars where it stands, then comes after you from there
						var at := _pose(a["s"], 0.0)
						a["state"] = "rouse"
						a["lat0"] = ((a["pos"] as Vector2) - (at["pos"] as Vector2)).dot(at["n"])
						a["cs"] = float(a["s"])
						a["bv"] = 0.0
						a["run_t"] = 0.0
						a["t"] = BEAR_ROUSE
						a["vel"] = Vector2.ZERO
						_face(a, (_pose(ms, 0.0)["pos"] as Vector2) - a["pos"])
						a["done"] = true
						_pop_at(a["pos"], "ROAR!", Color(1.0, 0.4, 0.3))
						Game.toast.emit("BEAR! PEDAL!!", Color(1.0, 0.45, 0.3))
						Talk.say_random("race_bear", true)
					elif WATCHERS.has(kind) and absf(ds) < 6.0:
						a["done"] = true
						_pop_at(a["pos"], WATCHERS[kind], Color(1, 1, 1))
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
				elif a["state"] == "cross" and not a.get("whoa", false) and absf(ds) < 2.5 and _rd(a["pos"]) < 0.7 + ROAD_GROW and not me["done"]:
					a["whoa"] = true
					me["v"] = float(me["v"]) * 0.85
					_pop(0, "WHOA!", Color(1.0, 0.6, 0.3))
			"rouse":
				a["run"] = false
				if float(a["t"]) <= 0.0:
					a["state"] = "chase"
					a["t"] = BEAR_CHASE
			"chase", "swipe":
				# as fast as you'd go at BEAR_FTP of your FTP here, on your bike: below that it gains on you
				var bk: Dictionary = me["bike"]
				var top := Game.speed_from_power(Game.ftp * BEAR_FTP, bk["mass"], bk["cda"], _crr(bk), _grade_at(a["cs"]))
				a["bv"] = move_toward(float(a["bv"]), top * (0.35 if a["state"] == "swipe" else 1.0), BEAR_ACCEL * delta)
				var cs: float = float(a["cs"]) + float(a["bv"]) * delta
				a["cs"] = cs
				a["s"] = cs
				# off its spot by the trail and onto the course over the first couple of seconds
				a["run_t"] = float(a["run_t"]) + delta
				var lat := lerpf(float(a["lat0"]), float(a["side"]) * 0.3 * ROAD_W, smoothstep(0.0, 2.0, float(a["run_t"])))
				var np: Vector2 = _pose(cs, lat)["pos"]
				if a["state"] == "chase":
					_face(a, np - a["pos"])
				a["pos"] = np
				a["vel"] = Vector2.ZERO
				var gap := ms - cs
				if a["state"] == "chase":
					a["run"] = true
					if gap < BEAR_REACH and gap > -1.0 and not me["done"] and float(me["down"]) <= 0.0:
						a["state"] = "swipe"
						a["sw"] = 0.0
						a["hit"] = false
						a["phase"] = 0.0   # the swipe plays from its first frame
				else:
					a["run"] = false
					a["sw"] = float(a["sw"]) + delta
					if not a["hit"] and float(a["sw"]) >= BEAR_HIT:
						a["hit"] = true
						if gap < BEAR_REACH + 0.6 and gap > -1.0 and not me["done"] and float(me["down"]) <= 0.0:
							_bear_wipeout()
							a["t"] = 0.0
						else:
							_pop_at(a["pos"], "WHIFF!", Color(1.0, 0.85, 0.5))
					if float(a["sw"]) >= BEAR_SWIPE:
						a["state"] = "chase"
				if float(a["t"]) <= 0.0 or me["done"]:
					a["state"] = "roar"
					a["t"] = 1.8
					_pop_at(a["pos"], "GRRR...", Color(1.0, 0.6, 0.4))
			"roar":
				a["run"] = false
				if float(a["t"]) <= 0.0:
					a["state"] = "idle"
					a["home"] = _pose(a["s"], float(a["side"]) * (2.5 + ROAD_GROW))["pos"]
					a["t"] = 0.0
		var vel: Vector2 = a["vel"]
		if vel.length() > 0.01:
			a["pos"] = (a["pos"] as Vector2) + vel * delta
			_face(a, vel)


func _face(a: Dictionary, dir: Vector2) -> void:
	var sx := dir.x - dir.y
	if absf(sx) > 0.001:
		a["face"] = signf(sx)
	if dir.length() > 0.001:
		a["wdir"] = dir.normalized()   # the way it's heading, for the 8-direction art (Sprites.draw_animal)


func _animal_cross(a: Dictionary) -> void:
	var target: Vector2 = _pose(float(a["s"]) + 2.0, -float(a["side"]) * (3.2 + ROAD_GROW))["pos"]
	var speed: float = CROSS_SPEED.get(a["kind"], 3.5)
	a["state"] = "cross"
	a["vel"] = (target - a["pos"]).normalized() * speed
	a["t"] = (a["pos"] as Vector2).distance_to(target) / speed
	a["done"] = true
	if a["kind"] in ["deer", "elk"]:
		_pop_at(a["pos"], "DEER!" if a["kind"] == "deer" else "ELK!", Color(1.0, 0.85, 0.5))
		if randf() < 0.35:
			Talk.say_random("race_wildlife")
	elif a["kind"] in ["fox", "wolf"]:
		_pop_at(a["pos"], "FOX!" if a["kind"] == "fox" else "WOLF!", Color(1.0, 0.6, 0.3))


func _animal_flee(a: Dictionary, dur: float) -> void:
	var away: Vector2 = _pose(a["s"], float(a["side"]))["n"] * float(a["side"])
	if a["state"] == "cross":
		away = (a["vel"] as Vector2).normalized()
	var speed: float = FLEE_SPEED.get(a["kind"], 3.0)
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
		Game.toast.emit("FINISHED!  Place #%d  -  keep rolling to cool down" % finish_count, Color(1.0, 0.9, 0.3))
		if finish_count == 1:
			for k in 2:
				Talk.say(randi() % Talk.rivals.size(), "race_win_player", true)
		else:
			for o in riders:
				if o.get("place", 0) == 1 and not o["player"]:
					_say(o, "race_lose_player", true)
	elif finish_count == 1:
		_say(r, "race_win_rival", true)


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
				_say(r, "race_pass_player")
			else:
				_say(r, "race_player_pass")
		elif not last_swap.has(k):
			last_swap[k] = {"ahead": sign_now, "t": clock}
	if leader:
		lead_clock += get_process_delta_time()
		if lead_clock > 12.0:
			lead_clock = 0.0
			Talk.say_random("race_leading")
	else:
		lead_clock = 0.0


## Made it to the injured skier with the kit.
func _end_rescue() -> void:
	over = true
	active = false
	Trainer.send_grade(0.0)
	Game.add_money(RESCUE_PAY)
	Game.save_game()
	finished.emit({"rescue": true, "time": clock, "prize": RESCUE_PAY, "course": course["name"]})


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
	var prize := int(float(course["prize"]) * shares[place - 1]) if place <= shares.size() else 0
	var names: Array = []
	for r in order:
		names.append(r["name"])
	if place == 1:
		Game.race_wins += 1
	Game.add_money(prize)
	Game.damage_bike(12.0)
	Game.save_game()
	var champ := -1   # where the guest champion came, if he raced
	for k in order.size():
		if order[k].get("guest", false):
			champ = k + 1
	var new_bike := false
	if champ > 0 and place < champ:   # you beat the champion: his bonus, and his bike
		Game.add_money(Game.CHAMPION_BONUS)
		new_bike = Game.give_bike(Game.CHAMPION_BIKE)
		Game.save_game()
	finished.emit({"place": place, "time": riders[0]["time"] if riders[0]["done"] else clock, "prize": prize, "order": names, "course": course["name"],
		"beat_champion": champ > 0 and place < champ, "champion": champ > 0, "champion_bike": new_bike})


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
	for h in hairpins.slice(0, 1):
		out.append(float(h["s"]) - 60.0)
		out.append(float(h["s"]))
	for t in tunnels.slice(0, 1):
		out.append(float(t["s0"]) - 40.0)
		out.append((float(t["s0"]) + float(t["s1"])) * 0.5)
		out.append(float(t["s1"]) + 10.0)
	for r in ramps.slice(0, 1):
		out.append(float(r["s0"]) - 5.0)
	if life != null:
		for c in life.crossings.slice(0, 1):
			out.append(float(c["s"]) - 6.0)
		if not life.devil.is_empty():
			out.append(float(life.devil["s0"]) + 30.0)
		if not life.lift.is_empty():   # the road sample nearest the bottom of the chairlift
			var best := 0
			for q in range(0, M, 4):
				if pts[q].distance_to(Vector2(float(life.lift["x"]), float(life.lift["y0"]) - 4.0)) < pts[best].distance_to(Vector2(float(life.lift["x"]), float(life.lift["y0"]) - 4.0)):
					best = q
			out.append(s_m[best])
	for q in M:   # the first place with snow
		if _snow_cover(pts[q].x, pts[q].y, elev[q] * vz / peak) > 0.6:
			out.append(s_m[q] + 30.0)
			break
	out.append(float(course["length"]) - 25.0)
	out.append(float(course["length"]) + 150.0)   # out on the run-out
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
	if life != null:
		for mv in life.movers():
			var p: Vector2 = mv[0]
			if absf(p.x - me_pos.x) > VIEW_R + 4 or absf(p.y - me_pos.y) > VIEW_R + 4:
				continue
			var d := _diag(p)
			if not buckets.has(d):
				buckets[d] = []
			buckets[d].append([3, mv[1]])
	if not patrol.is_empty():
		var sp := _patrol_at(patrol["t"])
		if not sp.is_empty():
			var d := _diag(sp["pos"])
			if not buckets.has(d):
				buckets[d] = []
			buckets[d].append([4, sp])

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
			var ci_ := j * gw + i
			var gname: String = GROUND_KINDS[cell_tex[ci_]]
			var quad := PackedVector2Array([Iso.to_screen(Vector2(wx, wy), z00), Iso.to_screen(Vector2(wx + 1, wy), z10),
				Iso.to_screen(Vector2(wx + 1, wy + 1), z11), Iso.to_screen(Vector2(wx, wy + 1), z01)])
			if cell_cliff[ci_] == 2:
				_draw_cliff_face(quad, PackedFloat32Array([z00, z10, z11, z01]), wx, wy)
			elif Ground.tex(gname) == null:
				draw_primitive(quad, PackedColorArray([col]), PackedVector2Array())
				_cell_detail(i, j, center, cell_kind[ci_], col)
			else:
				Ground.quad(self, quad, gname, cell_light[ci_], col, cell_tint[ci_])
				if cell_kind[ci_] == 1 and not Season.bare():
					_cell_flowers(i, j, center)
	for d in range(d0, d1 + 1):
		if stream_buckets.has(d):
			for sg in stream_buckets[d]:
				var a: Vector2 = sg["a"]
				if not big.has_point(a):
					continue
				if Season.bare() or Ground.tex("water_creek") == null:
					draw_colored_polygon(sg["poly"], Season.water(WATER))
				else:
					Ground.fill(self, sg["poly"], "water_creek", 1.0, WATER)
				if not Season.bare() and (int(sg["k"]) + int(t_ * 5.0)) % 4 == 0:
					draw_line(a, sg["b"], Color(0.85, 0.95, 1.0), 1.0)
	for d in range(d0, d1 + 1):
		if road_buckets.has(d):
			for si in road_buckets[d]:
				var seg: Dictionary = road_segs[si]
				var e: PackedVector2Array = seg["edge"]
				if not big.has_point(e[0]):
					continue
				var sn: float = maxf(float(seg["snow"]) * 0.6, 0.3 if Season.bare() else 0.0)
				var snow_tint := Color.WHITE.lerp(Color(1.25, 1.27, 1.32), sn)
				var textured := Ground.tex("gravel_road") != null
				if textured:
					Ground.fill(self, e, "dirt", float(seg["light"]) * 0.82, Color(0.5, 0.42, 0.33), snow_tint)
					Ground.fill(self, seg["gravel"], "gravel_road", float(seg["light"]), Color(0.72, 0.64, 0.52), snow_tint)
					for rut in seg["ruts"]:
						draw_colored_polygon(rut, Color(0.3, 0.24, 0.18, 0.22))
				else:
					draw_colored_polygon(e, Color(0.5, 0.42, 0.33).lerp(Color(0.7, 0.74, 0.8), sn))
					draw_colored_polygon(seg["gravel"], Iso.shade(Color(0.72, 0.64, 0.52).lerp(Season.SNOW, sn), seg["shade"]))
					for rut in seg["ruts"]:
						draw_colored_polygon(rut, Color(0.6, 0.52, 0.42).lerp(Color(0.62, 0.66, 0.74), sn))
					var pi_ := 0
					for pb in seg["pebbles"]:
						draw_rect(Rect2(pb, Vector2(2, 1)), Color(0.5, 0.44, 0.36) if pi_ % 2 == 0 else (Season.SNOW if Season.bare() else Color(0.86, 0.8, 0.68)))
						pi_ += 1
	if life != null:
		life.draw_rails(self, vr)
	for d in range(d0, d1 + 1):   # the grade chevrons on top of the road
		if road_buckets.has(d):
			for si in road_buckets[d]:
				var seg: Dictionary = road_segs[si]
				if seg.has("chev") and big.has_point(seg["edge"][0]):
					for ch in seg["chev"]:
						draw_polyline(ch, Iso.OUTLINE, 4.0)
						draw_polyline(ch, seg["chev_col"], 2.0)
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
					6: _draw_tunnel_piece(it[1])
					7: Flora.plant(self, Iso.to_screen(it[1]["pos"], it[1]["z"]), it[1]["kind"], it[1]["h"], it[1]["snow"], it[1]["scale"])
		if buckets.has(d):
			for it in buckets[d]:
				match it[0]:
					0: _draw_rider(it[1], it[2])
					1: _draw_animal(it[1])
					2: _draw_giver(it[1], it[2])
					3: (it[1] as Callable).call()
					4: _draw_patroller(it[1])
	_draw_birds(me_pos)
	if life != null:
		life.draw_lift_cables(self)
		life.draw_helicopter(self)
	_draw_flurries(vr, _snow_cover(me_pos.x, me_pos.y, _tz(me_pos) / peak))
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


## Snowflakes drifting across the screen once you are up in the snow.
## A cell of cliff face: bare rock (too steep to hold snow) lit at the top and in shadow at the foot, with bedding
## lines and the odd crack so it reads as layered rock.
func _draw_cliff_face(q: PackedVector2Array, z: PackedFloat32Array, wx: int, wy: int) -> void:
	var h := absi(wx * 73856093 ^ wy * 19349663)
	var zlo := minf(minf(z[0], z[1]), minf(z[2], z[3]))
	var zhi := maxf(maxf(z[0], z[1]), maxf(z[2], z[3]))
	var base := Color(0.56, 0.52, 0.49).lerp(Color(0.6, 0.55, 0.47), float(h % 5) / 4.0)
	var cols := PackedColorArray()
	for k in 4:
		var u := (z[k] - zlo) / maxf(zhi - zlo, 1.0)
		cols.append(Iso.shade(base, lerpf(0.62, 1.12, u)))
	draw_primitive(q, cols, PackedVector2Array())
	var dark := Color(0.16, 0.13, 0.13, 0.4)
	var lite := Color(1.0, 0.97, 0.9, 0.14)
	# lines run across the face between its two tall edges
	var top_l := q[0]
	var top_r := q[1]
	var bot_l := q[3]
	var bot_r := q[2]
	if q[0].distance_to(q[1]) + q[3].distance_to(q[2]) > q[0].distance_to(q[3]) + q[1].distance_to(q[2]):
		top_r = q[3]   # a face running along y (round a hairpin): its tall edges are the other pair
		bot_l = q[1]
	for k in 2:
		var u := (0.3 + 0.4 * k) + 0.08 * float((h >> (k * 3)) % 3 - 1)
		var a := top_l.lerp(bot_l, u)
		var b := top_r.lerp(bot_r, u + 0.06 * float((h >> (k * 2 + 7)) % 3 - 1))
		if a.distance_to(b) < 2.0:
			continue
		draw_line(a.round(), b.round(), dark, 1.0)
		draw_line(a.round() + Vector2(0, 1), b.round() + Vector2(0, 1), lite, 1.0)
	if h % 4 == 0:   # a crack down the face
		var c0 := top_l.lerp(top_r, 0.3 + 0.4 * float(h % 7) / 7.0)
		var c1 := bot_l.lerp(bot_r, 0.4 + 0.3 * float(h % 5) / 5.0)
		draw_line(c0.round(), c0.lerp(c1, 0.5).round() + Vector2(1, 0), dark, 1.0)
		draw_line(c0.lerp(c1, 0.5).round() + Vector2(1, 0), c1.round(), dark, 1.0)


func _draw_flurries(vr: Rect2, cover: float) -> void:
	if cover < 0.25:
		return
	var n := int(70.0 * cover)
	for k in n:
		var h := float((k * 7919) % 1000) / 1000.0
		var h2 := float((k * 104729) % 997) / 997.0
		var x := fposmod(h * vr.size.x + t_ * (10.0 + 14.0 * h2) + sin(t_ * 0.8 + k) * 12.0, vr.size.x)
		var y := fposmod(h2 * vr.size.y + t_ * (22.0 + 30.0 * h), vr.size.y)
		draw_rect(Rect2(vr.position + Vector2(x, y), Vector2(2, 2) if k % 3 == 0 else Vector2(1, 1)), Color(1, 1, 1, 0.55 + 0.35 * h))


func _diag(p: Vector2) -> int:
	return clampi(floori(p.x - ox) + floori(p.y - oy), 0, gw + gh - 2)


func _draw_sky(vr: Rect2) -> void:
	var c := vr.get_center()
	var top := Season.sky(Color(0.4, 0.68, 0.95))
	var bottom := Season.sky(Color(0.8, 0.92, 1.0))
	draw_polygon(PackedVector2Array([vr.position - Vector2(50, 50), vr.position + Vector2(vr.size.x + 50, -50), vr.end + Vector2(50, 50), vr.position + Vector2(-50, vr.size.y + 50)]),
		PackedColorArray([top, top, bottom, bottom]))
	draw_circle(c + Vector2(vr.size.x * 0.32, -vr.size.y * 0.32), 70.0, Color(1.0, 0.96, 0.7))
	for k in 5:
		var cp := c + Vector2(fposmod(k * 380.0 + t_ * 8.0, vr.size.x + 400.0) - vr.size.x * 0.5 - 200.0, -vr.size.y * 0.3 + k * 28.0 - 40.0)
		Sprites.draw_image(self, "scenery_cloud_%s" % ["a", "b", "c"][k % 3], cp + Vector2(0, 30), false, 0.9, 1.8)


## Small pixel details per terrain cell: grass tufts and flowers in the meadows, needles and cones under the
## trees, rocks on the scree.
func _cell_detail(i: int, j: int, center: Vector2, kind: int, col: Color) -> void:
	var h := ((i * 73856093) ^ (j * 19349663)) & 0x7fffffff
	var o := Vector2(float(h % 17) - 8.0, float((h >> 5) % 9) - 4.0)
	if Season.bare() and kind != 4:
		if kind != 3 and h % 3 == 0:   # sparkles on the snow
			draw_rect(Rect2(center + o, Vector2(1, 1)), Color(1, 1, 1))
		if kind != 3:
			return
	match kind:
		4:
			if h % 4 == 0:   # sparkles and wind-blown drifts
				draw_rect(Rect2(center + o, Vector2(1, 1)), Color(1, 1, 1))
			if h % 7 == 0:
				draw_line(center - o, center - o + Vector2(5, 1), Iso.shade(col, 0.9), 1.0)
		1:
			if Season.is_("fall") and h % 2 == 0:
				draw_rect(Rect2(center - o, Vector2(2, 1)), Season.FALL_LEAVES[(h >> 3) % 4])
			for k in 3:
				var p := center + o + Vector2((k - 1) * 9.0, float((h >> (k + 2)) % 5) - 2.0)
				var tc := Iso.shade(col, 0.72)
				draw_line(p, p + Vector2(-2, -3), tc, 1.0)
				draw_line(p, p + Vector2(0, -4), tc, 1.0)
				draw_line(p, p + Vector2(2, -3), tc, 1.0)
			if course.get("flowers", false) and (not Season.is_("fall") or h % 4 == 0):
				_flowers(center, h)
			elif h % (2 if Season.is_("spring") else 4 if Season.is_("summer") else 16) == 0:
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


const FLOWER_COLS := [Color(1.0, 0.45, 0.7), Color(1.0, 0.92, 0.3), Color(1, 1, 1), Color(0.6, 0.55, 1.0), Color(1.0, 0.35, 0.3),
	Color(1.0, 0.65, 0.2), Color(0.85, 0.5, 1.0)]


## Flour Run: every meadow cell is a little patch of flowers, each a stem and a four-petal head.
## Flowers dotted over the textured meadows (the texture has the grass).
func _cell_flowers(i: int, j: int, center: Vector2) -> void:
	var h := ((i * 73856093) ^ (j * 19349663)) & 0x7fffffff
	var o := Vector2(float(h % 17) - 8.0, float((h >> 5) % 9) - 4.0)
	if course.get("flowers", false) and (not Season.is_("fall") or h % 4 == 0):
		_flowers(center, h)
	elif h % (3 if Season.is_("spring") else 6 if Season.is_("summer") else 24) == 0:
		draw_rect(Rect2(center - o, Vector2(2, 2)), [Color(1.0, 0.5, 0.75), Color(1.0, 0.92, 0.3), Color(1, 1, 1), Color(0.6, 0.6, 1.0)][(h >> 3) % 4])


func _flowers(center: Vector2, h: int) -> void:
	Sprites.draw_image(self, ["scenery_tulips_red", "scenery_tulips_yellow", "scenery_tulips_pink"][h % 3], center + Vector2(0, 6), h % 2 == 0, 1.0, 0.7)


func _draw_tree(t: Dictionary) -> void:
	var base := Iso.to_screen(t["pos"], t["z"])
	Flora.tree(self, base, t["s"], t.get("sp", "pine"), t.get("snow", false), int(t.get("h", 0)))


func _draw_rock(r: Dictionary) -> void:
	Flora.rock(self, Iso.to_screen(r["pos"], r["z"]), r["size"], r["h"], r.get("snow", false))


func _draw_deco(e: Dictionary) -> void:
	match e["kind"]:
		"arch":
			var pz: Dictionary = e["pz"]
			var n: Vector2 = pz["n"]
			var along := Vector2(-n.y, n.x)   # the way the riders go
			var b := Iso.to_screen(pz["pos"], pz["z"])
			_wide(b, pz, ROAD_W, func(): Sprites.draw_vehicle(self, "obj_race_arch", b + Vector2(0, -34), along))
			draw_string(font, b + Vector2(-60, -88), e["label"], HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12, Color(0.15, 0.15, 0.2) if e["label"] == "START" else Color.WHITE)
		"sign":
			var pz: Dictionary = e["pz"]
			var b := Iso.to_screen(pz["pos"] + (pz["n"] as Vector2) * (1.1 + ROAD_GROW), pz["z"])
			Sprites.draw_image(self, "scenery_sign_marker", b)
			draw_string(font, b + Vector2(-24, -33), e["label"], HORIZONTAL_ALIGNMENT_CENTER, 48.0, 8, Color(0.1, 0.1, 0.15))
		"board":
			_draw_board(e)
		"sprite":
			Sprites.draw_image(self, e["name"], Iso.to_screen(e["pos"], e["z"]), e.get("flip", false))
		"crossing":
			life.draw_crossing(self, e)
		"chevron":
			_draw_chevron(e)
		"warn":
			var pz: Dictionary = e["pz"]
			Sprites.draw_image(self, "scenery_sign_warn", Iso.to_screen(pz["pos"] + (pz["n"] as Vector2) * (0.95 + ROAD_GROW) * float(e["side"]), pz["z"]))
		"fan":
			if e.get("run", "") != "":   # off running with you (RaceLife._step_runners)
				return
			var b := Iso.to_screen(e["pos"], e["z"])
			# their costume if nobody on screen has it yet, else whoever's free (nobody shows up twice; see Sprites.cast)
			if e.has("design") and not e.has("looks"):
				e["looks"] = [e["design"]] + Sprites._order(e)
			var design := Sprites.cast(e, e.get("looks", []))
			if design != "":
				# right by you, fans switch to one of their other cheers (Sprites.PASS_MOVES), each their own
				var by_you: bool = absf(float(riders[0]["s"]) - float(e["s"])) < 12.0
				Sprites.draw_any_cheer(self, design, b, t_ + (e["pos"] as Vector2).x * 0.37, int((e["pos"] as Vector2).x * 7.0) + 1 if by_you else 0)
		"snowman":
			Season.snowman(self, Iso.to_screen(e["pos"], e["z"]), e["sd"])
		"skier":
			# skis down the meadow beside the course (towards the camera), then rides the lift back up
			var u := fposmod(t_ * 0.18 + float(e["ph"]), 1.0)
			if u < 0.94:
				var p0: Vector2 = e["pos"]
				var p := p0 + Vector2(sin(u * TAU * 2.0) * 0.8, u * 3.0)
				var b := Iso.to_screen(p, _tz(p))
				var nxt := p0 + Vector2(sin((u + 0.01) * TAU * 2.0) * 0.8, (u + 0.01) * 3.0)
				var sk := Sprites.cast(e, Sprites.skiers())
				if sk != "":
					Sprites.draw_person(self, "ped_%s_ski" % sk, b, nxt - p, t_, 8.0)
		"pumpkins":
			var b := Iso.to_screen(e["pos"], e["z"])
			for k in 1 + int(e["sd"]) % 3:
				Season.pumpkin(self, b + Vector2(k * 7.0 - 4.0, (k % 2) * 3.0), 1.3 if k == 0 else 0.9, int(e["sd"]) + k)
		"leafpile":
			Season.leaf_pile(self, Iso.to_screen(e["pos"], e["z"]), e["sd"])
		"hay":
			Sprites.draw_image(self, "scenery_haystack" if int(e["sd"]) % 2 == 0 else "scenery_haybale", Iso.to_screen(e["pos"], e["z"]))
		"flowers":
			Season.flower_bed(self, Iso.to_screen(e["pos"], e["z"]), e["sd"])
		"butterfly":
			var ph: float = e["ph"]
			var b := Iso.to_screen(e["pos"], e["z"]) + Vector2(cos(t_ * 0.8 + ph) * 18.0, -14.0 + sin(t_ * 1.3 + ph) * 6.0)
			Season.butterfly(self, b, e["col"], t_ * 14.0 + ph)
		"picnic":
			var b := Iso.to_screen(e["pos"], e["z"])
			Sprites.draw_image(self, "scenery_picnic_red" if int((e["pos"] as Vector2).x) % 2 == 0 else "scenery_picnic_blue", b + Vector2(0, 12))
			for side in [-1.0, 1.0]:   # two spectators sitting by the blanket, waving
				var who: Dictionary = e.get("fan%d" % int(side), {})
				e["fan%d" % int(side)] = who
				var look := Sprites.cast(who)
				if look != "":
					Sprites.draw_cheer(self, "ped_%s_cheer" % look, b + Vector2(side * 22.0, 8), t_ + side)
		"kite":
			var b := Iso.to_screen(e["pos"], e["z"])
			var ph: float = e["ph"]
			var flier := Sprites.cast(e, ["kid", "bucket_hat_kid", "norm_boy_kid", "scout", "skater_kid"].filter(func(d): return Sprites.sheet("ped_%s_walk" % d) != null))
			if flier != "":
				Sprites.draw_person(self, "ped_%s_walk" % flier, b, Vector2(1, 1), 0.0)
			var hand := b + Vector2(4, -26)
			var k := b + Vector2(30 + sin(t_ * 0.7 + ph) * 8.0, -78 + cos(t_ * 1.1 + ph) * 6.0)
			draw_polyline(PackedVector2Array([hand, hand.lerp(k, 0.5) + Vector2(0, 8), k]), Color(1, 1, 1, 0.7), 1.0)
			Sprites.draw_image(self, ["scenery_kite_red", "scenery_kite_blue", "scenery_kite_yellow"][int(ph * 10.0) % 3], k + Vector2(0, 28))


## Bike lights at night for night.gd: a small pool ahead of every rider.
func night_lights() -> Array:
	var out: Array = []
	var on := clampf((Skies.dark() - 0.3) * 3.0, 0.0, 1.0)
	if on <= 0.0:
		return out
	for r in riders:
		var pz := _pose(float(r["s"]) + 1.2, r["lat"])
		out.append([Iso.to_screen(pz["pos"], pz["z"]), 32.0 if r.get("player", false) else 22.0, 0.75 * on])
	return out


func _sp(p: Dictionary, lift: float = 0.0) -> Vector2:
	return Iso.to_screen(p["pos"], float(p["z"]) + 1.8 + lift)


func _draw_obstacle(ob: Dictionary) -> void:
	var s: float = ob["s"]
	match ob["kind"]:
		"jump":
			# kickers side by side across the wider road (one used to do), the far one first
			var pp: Vector2 = _pose(s, 1.0)["pos"]
			var pm: Vector2 = _pose(s, -1.0)["pos"]
			var lats: Array = [-0.3 * ROAD_HW, 0.3 * ROAD_HW] if pp.x + pp.y > pm.x + pm.y else [0.3 * ROAD_HW, -0.3 * ROAD_HW]
			for lat in lats:
				var j0 := _pose(s - 1.2, lat)
				var j1 := _pose(s + 1.2, lat)
				Sprites.draw_vehicle(self, "obj_dirt_jump", _sp(j0, 6.0), (j1["pos"] as Vector2) - (j0["pos"] as Vector2))
		"log":
			# right across the road, its ends sticking out past the edges as far as ever
			var flip := -1.0 if ob.get("flip", false) else 1.0
			var pa := _pose(s, (-1.35 - ROAD_GROW) * flip)
			var pb := _pose(s, (1.55 + ROAD_GROW) * flip)
			var mid := _pose(s, 0.1 * flip)
			var at := _sp(mid, 6.0)
			_wide(Iso.to_screen(mid["pos"], mid["z"]), mid, (2.9 + 2.0 * ROAD_GROW) / 2.9,
				func(): Sprites.draw_vehicle(self, "obj_fallen_log", at, (pb["pos"] as Vector2) - (pa["pos"] as Vector2)))
		"ford":
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for q in 5:
				var ss := s - FORD_HALF + FORD_HALF * 2.0 * q / 4.0
				left.append(_sp(_pose(ss, -1.0 - ROAD_GROW), 0.2))
				right.append(_sp(_pose(ss, 1.0 + ROAD_GROW), 0.2))
			right.reverse()
			var poly := left + right
			if Season.bare() or Ground.tex("water_creek") == null:
				draw_colored_polygon(poly, Iso.fa(Season.water(WATER), 0.9))
			else:
				Ground.fill(self, poly, "water_creek", 1.08, WATER, Color(1, 1, 1, 0.88))
			for q in 3:
				var u := fposmod(t_ * 0.5 + q / 3.0, 1.0)
				var ss := s - FORD_HALF + FORD_HALF * 2.0 * u
				draw_line(_sp(_pose(ss, -0.8 - ROAD_GROW), 0.4), _sp(_pose(ss, 0.8 + ROAD_GROW), 0.4), Color(0.85, 0.95, 1.0, 1.0 - absf(u - 0.5) * 2.0), 1.0)
			for lat in [-0.85 - ROAD_GROW, 0.9 + ROAD_GROW]:
				for k in 2:
					var rp := _sp(_pose(s + (k - 0.5) * 2.0, lat))
					draw_rect(Rect2(rp - Vector2(3, 2), Vector2(6, 4)), Iso.OUTLINE)
					draw_rect(Rect2(rp - Vector2(2, 1), Vector2(4, 2)), Color(0.66, 0.64, 0.6))


## Draws `fn` (something standing on the road at screen point `at`, across the road at `pz`) `k` times as wide: stretched
## sideways on screen and sheared so it still lines up across the road, uprights kept upright and as tall.
func _wide(at: Vector2, pz: Dictionary, k: float, fn: Callable) -> void:
	var n: Vector2 = pz["n"]
	var ns := Vector2((n.x - n.y) * Iso.TW * 0.5, (n.x + n.y) * Iso.TH * 0.5)   # the road's normal on screen
	if absf(ns.x) < 0.3 * ns.length():   # the road runs across the screen: nothing sideways to stretch
		fn.call()
		return
	var m := Transform2D(Vector2(k, ns.y / ns.x * (k - 1.0)), Vector2(0, 1), Vector2.ZERO)
	draw_set_transform_matrix(Transform2D(0.0, at) * m * Transform2D(0.0, -at))
	fn.call()
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A soft oval shadow on the ground.
func _shadow(c: Vector2, w: float) -> void:
	var poly := PackedVector2Array()
	for q in 8:
		poly.append(c + Vector2(cos(q * TAU / 8.0) * w, sin(q * TAU / 8.0) * w * 0.4))
	draw_colored_polygon(poly, Color(0, 0, 0, 0.22))


## Shadow width (px) under each animal, about its body length.
const ANIMAL_SHADOW := {"bear": 24.0, "deer": 22.0, "moose": 26.0, "goat": 14.0, "marmot": 9.0, "rabbit": 9.0, "squirrel": 9.0, "fox": 17.0,
	"elk": 26.0, "wolf": 18.0, "raccoon": 12.0, "hedgehog": 8.0, "chipmunk": 8.0, "skunk": 10.0, "bighorn": 18.0, "badger": 13.0,
	"mountain_lion": 22.0, "porcupine": 10.0, "otter": 13.0, "beaver": 12.0, "coyote": 17.0, "ram_lamb": 11.0}


## An animal from its sheets (art/animal_<kind>_idle.png and _run.png; the bear also _roar.png), facing right and
## mirrored when it faces left. Dark bears are the same bear, darker.
func _draw_animal(a: Dictionary) -> void:
	var p: Vector2 = a["pos"]
	var base := Iso.to_screen(p, _tz(p) + 1.5).round()
	var kind: String = a["kind"]
	var look := "run" if a["run"] else "idle"
	if kind == "bear" and a["state"] in ["roar", "rouse"]:
		look = "roar"
	elif kind == "bear" and a["state"] == "swipe" and Sprites.sheet("animal_bear_swipe") != null:
		look = "swipe"
	var tint := Color(0.5, 0.46, 0.46) if kind == "bear" and a["dark"] else Color.WHITE
	_shadow(base, ANIMAL_SHADOW.get(kind, 14.0))
	var t := float(a["sw"]) if look == "swipe" else t_ + float(a["phase"])   # the swipe plays once, from the start
	var fps := 14.0 if look == "run" else (_swipe_fps() if look == "swipe" else 8.0)
	if look in ["roar", "swipe"]:   # (side-on only)
		Sprites.draw_strip(self, "animal_%s_%s" % [kind, look], base, t, fps, true, float(a["face"]) < 0.0, tint)
	else:
		var w: Vector2 = a.get("wdir", Vector2(float(a["face"]), -float(a["face"])).normalized())
		Sprites.draw_animal(self, kind, look, base, w, t, fps, tint, a)


## Frames a second for the bear's swipe, so the whole strip plays once in BEAR_SWIPE.
func _swipe_fps() -> float:
	var tex := Sprites.sheet("animal_bear_swipe")
	return float(tex.get_width() / tex.get_height()) / BEAR_SWIPE * 0.999


## A pair of eagles circling high over the course (art/animal_eagle_fly.png).
func _draw_birds(me_pos: Vector2) -> void:
	for q in 2:
		var ang := t_ * (0.35 + q * 0.12) + q * PI
		var p := me_pos + Vector2(4.0 + q * 3.0, -5.0) + Vector2(cos(ang), sin(ang)) * (3.5 + q)
		var c := Iso.to_screen(p, _tz(me_pos) + 150.0 + q * 30.0)
		Sprites.draw_strip(self, "animal_eagle_fly", c, t_ + q * 0.37, 8.0 + q, false)


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
	if r["player"] and float(r["draft"]) > 0.0 and not down:
		# wind streaks sliding past: you're in the slipstream
		for q in 4:
			var u := fposmod(t_ * 2.2 + q * 0.25, 1.0)
			var side := Vector2(-ds.y, ds.x).normalized() * (10.0 if q % 2 == 0 else -10.0)
			var a := c + side + Vector2(0, -12 - q * 3) + ds.normalized() * (20.0 - u * 40.0)
			draw_line(a, a - ds.normalized() * 10.0, Color(1, 1, 1, 0.7 * (1.0 - absf(u - 0.5) * 2.0)), 1.0)
	var phase: float = r["phase"]
	var fall_t := float(r["fall"]) if down else -1.0   # the wipe-out animation, then lying there until they get up
	# the bear rescue (see patrol): lying there with your bike beside you, then without it, then climbing back on
	# (the wipe-out played backwards)
	var lying := false
	if r["player"] and down and patrol.has("lie"):
		if _patrol_bike(patrol["t"]) != "":
			Sprites.draw_image(self, "obj_bike_lying_" + Sprites.player_sheet, Iso.to_screen(patrol["bike"], patrol["bike_z"]) + Vector2(0, 5))
		if float(r["down"]) <= SP_GETUP:
			fall_t = float(r["down"])
		else:
			lying = true
			var lie := "rider_lying_" + Sprites.player_sheet
			if Sprites.cold and Sprites.sheet("winter_" + lie) != null:
				lie = "winter_" + lie
			if not Sprites.draw_image(self, lie, c + Vector2(0, 5)):
				lying = false
	if lying:
		pass   # drawn above, without the bike
	elif kb != 1.0:
		draw_set_transform(c, 0.0, Vector2(kb, kb))
		BikeDraw.draw(self, Vector2.ZERO, ds, phase, false, "YOU" if r["player"] else r["short"], 1.0, false, fall_t)
		draw_set_transform(Vector2.ZERO)
	else:
		BikeDraw.draw(self, c, ds, phase, false, "YOU" if r["player"] else r["short"], 1.0, false, fall_t)
	if down:
		for q in 3:
			var a := t_ * 5.0 + q * TAU / 3.0
			var sp := c + Vector2(cos(a) * 9.0, (-16.0 if lying else -30.0) + sin(a) * 3.0)
			draw_rect(Rect2(sp - Vector2(1, 1), Vector2(3, 3)), Iso.OUTLINE)
			draw_rect(Rect2(sp, Vector2(1, 1)), Color(1.0, 0.95, 0.3))
	if r["player"] or not _crowded(k):
		var label: String = "YOU" if r["player"] else r["short"]
		var outline_col: Color = Color(1, 1, 1) if r["player"] else r["color"]
		var p := c + Vector2(-100, -28.0 if lying else -54.0 * kb)
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
	Sprites.draw_strip(self, "giver_%s_wave" % ("red" if int(float(g["phase"]) * 10.0) % 2 == 0 else "blue"), ground, t_ + float(g["phase"]), 8.0)


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
