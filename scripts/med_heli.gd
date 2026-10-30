extends RefCounted
## St. Pedro's air ambulance (art/heli_medical.png: 8 isometric directions like the vehicles; for each tilt (level,
## nose down, nose up, banked left, banked right; see TILT) a run of frames of its rotor spinning). It sits on the helipad on the
## hospital roof, and every so often spins up, climbs, flies off over the town and out past the edge of the map, then
## some minutes later comes back in, lands on the pad and spins down. A shadow follows it over the ground.

const EVERY := [420.0, 900.0]   # seconds on the pad between call-outs
const AWAY := [60.0, 150.0]     # seconds gone out of town
const SPEED := 7.0              # tiles a second, cruising
const CRUISE := 210.0           # px up when cruising
const PAD := Vector2(-4.0, -113.0)   # the pad on hospital.png, from the lot's near corner on screen
const SPIN := 3.0               # seconds to spin the rotor up (or down)
const CLIMB := 5.0              # seconds to climb off the pad (or settle onto it)
const TURN_RATE := 1.1          # radians a second it can swing round
const SLOW := 9.0               # tiles out from the pad it starts slowing to land, nose up
const TILT := {"level": 0, "nose_down": 1, "nose_up": 2, "bank_left": 3, "bank_right": 4}   # columns of the sheet
const SPIN_FPS := 18.0          # rotor frames a second at full speed
const SKIDS := -20.0            # from where its skids touch down to the middle of its frame (Sprites.draw_vehicle)
const HUB := -24.0              # from the middle of its frame up to the rotor hub

var city
var pad := Vector2.INF          # world point under the pad: the hospital lot's near corner
var pos := Vector2.ZERO         # world point it's over
var alt := 0.0                  # px above the pad's height
var state := "parked"
var t := 0.0
var rotor := 0.0                # 0 = still, 1 = full speed
var dir := Vector2(1, 0)        # world direction it wants to go
var heading := Vector2(1, 0)    # world direction its nose points (turns towards dir at TURN_RATE)
var tilt := "level"
var target := Vector2.ZERO
var approach := Vector2.ZERO    # where it comes to a hover just short of the pad before it settles
var t_ := 0.0
var turn := {}                  # its turning between views (Sprites.turn_rows)


func _init(c) -> void:
	city = c


func setup() -> void:
	pad = Vector2.INF
	for b in city.buildings:
		if b.get("kind", "") == "er":
			pad = (b["pos"] as Vector2) + (b["size"] as Vector2)
	pos = pad
	alt = 0.0
	state = "parked"
	rotor = 0.0
	t = randf_range(90.0, 300.0)   # the first one comes along fairly soon


func update(delta: float) -> void:
	if pad == Vector2.INF or Sprites.sheet("heli_medical") == null:
		return
	t_ += delta
	t -= delta
	# swing round towards where it's going, banking into the turn
	var turn_by := heading.angle_to(dir)
	heading = heading.rotated(clampf(turn_by, -TURN_RATE * delta, TURN_RATE * delta))
	tilt = "level"
	match state:
		"parked":
			if t <= 0.0:
				state = "spinup"
				t = SPIN
		"spinup":
			rotor = minf(1.0, rotor + delta / SPIN)
			if t <= 0.0:
				state = "climb"
				t = CLIMB
				var ang := randf() * TAU
				target = Vector2(city.N, city.N) * 0.5 + Vector2.from_angle(ang) * city.N * 0.95   # out past the edge
				dir = (target - pad).normalized()
		"climb":
			alt = CRUISE * smoothstep(0.0, 1.0, 1.0 - t / CLIMB)
			pos = pad + dir * (1.0 - t / CLIMB) * 2.0   # nosing off the pad as it goes up
			if t <= 0.0:
				state = "out"
		"out":
			pos += heading * SPEED * delta
			tilt = "nose_down"
			if pos.distance_to(target) < SPEED * delta * 2.0 or (pos - target).dot(dir) > 0.0:
				state = "away"
				t = randf_range(AWAY[0], AWAY[1])
		"away":
			if t <= 0.0:
				state = "in"
				pos = Vector2(city.N, city.N) * 0.5 + Vector2.from_angle(randf() * TAU) * city.N * 0.95
				dir = (pad - pos).normalized()
				heading = dir
				approach = pad - dir * 2.0
		"in":
			var to := approach - pos   # to just short of the pad, then it settles onto it
			var near_pad := to.length() < SLOW
			var step := SPEED * delta * (clampf(to.length() / SLOW, 0.25, 1.0) if near_pad else 1.0)
			tilt = "nose_up" if near_pad else "nose_down"
			if to.length() <= maxf(step, 0.05):
				state = "land"
				t = CLIMB
			else:
				dir = to.normalized()
				if to.length() < 1.5:   # lined up by now: no circling the pad
					heading = dir
				pos += heading * step
		"land":
			tilt = "nose_up" if t > CLIMB * 0.6 else "level"
			alt = CRUISE * smoothstep(0.0, 1.0, t / CLIMB)
			pos = pad.lerp(approach, t / CLIMB)
			if t <= 0.0:
				state = "spindown"
				alt = 0.0
				dir = heading
				pos = pad
				t = SPIN
		"spindown":
			rotor = maxf(0.0, rotor - delta / SPIN)
			if t <= 0.0:
				state = "parked"
				t = randf_range(EVERY[0], EVERY[1])


## Which way it leans now: into a turn, else nose down cruising / nose up slowing, else level.
func lean() -> int:
	if rotor > 0.5 and alt > 5.0 and absf(heading.angle_to(dir)) > 0.06:
		return TILT["bank_right"] if heading.angle_to(dir) > 0.0 else TILT["bank_left"]   # (screen y points down: + is clockwise, a right turn)
	return TILT[tilt]


## A helicopter from its sheet (8 direction rows; for each TILT column group, frames of the rotor going round), leaning
## `tilt`, its rotor at `speed` (0-1: 0 is the still first frame; while it spins up or down the blur disc goes over it).
static func draw_heli(ci: CanvasItem, sheet: String, at: Vector2, heading: Vector2, tilt: int, t: float, speed: float, turn: Dictionary) -> void:
	var tex := Sprites.sheet(sheet)
	if tex == null:
		return
	var f := tex.get_height() / Sprites.DIRS
	var per := maxi(1, tex.get_width() / f / TILT.size())   # rotor frames for each tilt
	var k := int(t * SPIN_FPS * speed) % per if speed > 0.0 else 0
	Sprites.draw_vehicle(ci, sheet, at, heading, Color.WHITE, tilt * per + k, turn)
	if speed > 0.0 and (per == 1 or speed < 0.95):
		draw_rotor(ci, at, t, speed)


## The blades spinning (0-1 = how fast) over a helicopter drawn at `at` with Sprites.draw_vehicle: a flickering disc
## and a blade sweeping round.
static func draw_rotor(ci: CanvasItem, at: Vector2, t: float, speed: float) -> void:
	var hub := at + Vector2(0.0, HUB)
	var a := t * 25.0 * speed
	var disc := PackedVector2Array()
	for k in 16:
		disc.append(hub + Vector2(cos(k * TAU / 16.0) * 28.0, sin(k * TAU / 16.0) * 14.0))
	ci.draw_colored_polygon(disc, Color(0.85, 0.88, 0.95, (0.16 if int(t * 20.0) % 2 == 0 else 0.1) * speed))
	ci.draw_line(hub - Vector2(cos(a) * 28.0, sin(a) * 14.0), hub + Vector2(cos(a) * 28.0, sin(a) * 14.0), Color(0.15, 0.15, 0.2, 0.5 * speed), 1.0)


## Drawn over the town (City._draw_overlays): it's up on the roof or in the air, above everything.
func draw(ci: CanvasItem) -> void:
	if pad == Vector2.INF or state == "away" or Sprites.sheet("heli_medical") == null:
		return
	var ground := Iso.to_screen(pos)
	# the roof offset fades out as it leaves the hospital, so it lifts off the pad and lands on it
	var near := clampf(1.0 - pos.distance_to(pad) / 6.0, 0.0, 1.0)
	var base := ground + PAD * near + Vector2(0.0, -alt)
	if alt > 20.0:   # its shadow on the ground (on the roof while it's over the pad)
		var sh := ground + PAD * near
		var k := clampf(1.0 - alt / 400.0, 0.4, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([sh + Vector2(-20, 0) * k, sh + Vector2(0, -6) * k, sh + Vector2(20, 0) * k, sh + Vector2(0, 6) * k]), Color(0, 0, 0, 0.18))
	var bob := sin(t_ * 2.3) * 2.0 * rotor if alt > 5.0 else 0.0
	var at := base + Vector2(0.0, bob + SKIDS)
	draw_heli(ci, "heli_medical", at, heading, lean(), t_, rotor, turn)
	if state in ["spinup", "climb", "land"] and int(t_ * 3.0) % 2 == 0:
		city._label("WHUP WHUP", at + Vector2(0, -44), 8, Color(1, 1, 1))
