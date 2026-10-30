extends RefCounted
## St. Pedro's air ambulance (art/heli_medical.png: 8 isometric directions, like the vehicles). It sits on the helipad on the
## hospital roof, and every so often spins up, climbs, flies off over the town and out past the edge of the map, then
## some minutes later comes back in, lands on the pad and spins down. A shadow follows it over the ground.

const EVERY := [420.0, 900.0]   # seconds on the pad between call-outs
const AWAY := [60.0, 150.0]     # seconds gone out of town
const SPEED := 7.0              # tiles a second, cruising
const CRUISE := 210.0           # px up when cruising
const PAD := Vector2(-4.0, -113.0)   # the pad on hospital.png, from the lot's near corner on screen
const SPIN := 3.0               # seconds to spin the rotor up (or down)
const CLIMB := 5.0              # seconds to climb off the pad (or settle onto it)
const SKIDS := -20.0            # from where its skids touch down to the middle of its frame (Sprites.draw_vehicle)
const HUB := -24.0              # from the middle of its frame up to the rotor hub

var city
var pad := Vector2.INF          # world point under the pad: the hospital lot's near corner
var pos := Vector2.ZERO         # world point it's over
var alt := 0.0                  # px above the pad's height
var state := "parked"
var t := 0.0
var rotor := 0.0                # 0 = still, 1 = full speed
var dir := Vector2(1, 0)        # world direction of travel
var target := Vector2.ZERO
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
			pos += dir * SPEED * delta
			if pos.distance_to(target) < SPEED * delta * 2.0 or pos.dot(dir) > target.dot(dir):
				state = "away"
				t = randf_range(AWAY[0], AWAY[1])
		"away":
			if t <= 0.0:
				state = "in"
				pos = Vector2(city.N, city.N) * 0.5 + Vector2.from_angle(randf() * TAU) * city.N * 0.95
				dir = (pad - pos).normalized()
		"in":
			var to := pad + dir * -2.0 - pos   # to just short of the pad, then it settles onto it
			var step := SPEED * delta
			if to.length() <= step:
				state = "land"
				t = CLIMB
			else:
				pos += to.normalized() * step
		"land":
			alt = CRUISE * smoothstep(0.0, 1.0, t / CLIMB)
			pos = pad + dir * -2.0 * (t / CLIMB)
			if t <= 0.0:
				state = "spindown"
				alt = 0.0
				pos = pad
				t = SPIN
		"spindown":
			rotor = maxf(0.0, rotor - delta / SPIN)
			if t <= 0.0:
				state = "parked"
				t = randf_range(EVERY[0], EVERY[1])


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
	Sprites.draw_vehicle(ci, "heli_medical", at, dir, Color.WHITE, 0, turn)
	if rotor > 0.0:
		draw_rotor(ci, at, t_, rotor)
	if state in ["spinup", "climb", "land"] and int(t_ * 3.0) % 2 == 0:
		city._label("WHUP WHUP", at + Vector2(0, -44), 8, Color(1, 1, 1))
