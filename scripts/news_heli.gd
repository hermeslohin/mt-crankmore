extends RefCounted
## The Channel 9 news helicopter (art/heli_news.png, laid out like heli_medical.png: 8 isometric directions, and for
## each tilt a run of spinning-rotor frames; see MedHeli.draw_heli). It films the riders: it chases a point near
## whoever it's following, swinging round to face where it's going, banking into turns, nose down to catch up and
## nose up as it slows into a hover. Used in town (City: now and then it comes to follow you for a while) and in
## races (RaceLife: it follows the riders all race, switching between you and the leader).

const MedHeli := preload("res://scripts/med_heli.gd")
const TOP := 13.0          # tiles a second, flat out
const ACCEL := 5.0         # tiles a second, per second
const TURN_RATE := 1.4     # radians a second

var pos := Vector2.ZERO    # world point it's over
var vel := Vector2.ZERO
var heading := Vector2(1, 0)
var want := Vector2(1, 0)  # where it would like to point
var accel := 0.0           # how fast it's speeding up (+) or slowing down (-), smoothed
var turn := {}             # Sprites.turn_rows state
var t_ := 0.0


func place(p: Vector2, facing: Vector2) -> void:
	pos = p
	vel = Vector2.ZERO
	heading = facing.normalized()
	want = heading


## Heads for `target` (a world point), easing off as it gets there.
func update(delta: float, target: Vector2) -> void:
	t_ += delta
	var to := target - pos
	var desired := to.normalized() * minf(TOP, to.length() * 0.9) if to.length() > 0.05 else Vector2.ZERO
	var was := vel.length()
	vel = vel.move_toward(desired, ACCEL * delta)
	accel = lerpf(accel, (vel.length() - was) / maxf(delta, 0.001), minf(1.0, delta * 3.0))
	pos += vel * delta
	if vel.length() > 0.8:
		want = vel.normalized()
	heading = heading.rotated(clampf(heading.angle_to(want), -TURN_RATE * delta, TURN_RATE * delta))


## Which way it leans (a MedHeli.TILT column): into a turn, nose down speeding up (or flat out), nose up slowing down,
## else level (keeping pace).
func lean() -> int:
	var turn_by := heading.angle_to(want)
	if absf(turn_by) > 0.08:
		return MedHeli.TILT["bank_right"] if turn_by > 0.0 else MedHeli.TILT["bank_left"]
	if accel > 1.2 or vel.dot(heading) > TOP * 0.6:
		return MedHeli.TILT["nose_down"]
	if accel < -1.2:
		return MedHeli.TILT["nose_up"]
	return MedHeli.TILT["level"]


## Draws it with its skids `alt` px over the ground point `ground` (already on screen), and its shadow there.
func draw(ci: CanvasItem, ground: Vector2, alt: float) -> void:
	var k := clampf(1.0 - alt / 400.0, 0.4, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-18, 0) * k, ground + Vector2(0, -6) * k, ground + Vector2(18, 0) * k, ground + Vector2(0, 6) * k]), Color(0, 0, 0, 0.16))
	var at := ground + Vector2(0.0, -alt + MedHeli.SKIDS + sin(t_ * 1.9) * 2.0)
	MedHeli.draw_heli(ci, "heli_news", at, heading, lean(), t_, 1.0, turn)
