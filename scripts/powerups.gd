class_name PowerUps
extends RefCounted
## Power-ups: about 1 in 8 townsfolk (and spectators along the race course) hand them out as you ride past.
## A rider carries one at a time (shown on the WEEHOO) and uses it with Y. Rivals grab and use them too.
## Town only: portal, wrench, walkie. Town and race: frisbee, socks, breadsticks.

const DEFS := {
	"portal": {"name": "Pepperoni Portal", "short": "PORTAL", "col": Color(0.9, 0.25, 0.2),
		"blurb": "warps you to the nearest pizza shop with a pizza"},
	"wrench": {"name": "Bike Wrench", "short": "WRENCH", "col": Color(0.7, 0.72, 0.78), "blurb": "fixes your bike"},
	"walkie": {"name": "Walkie Talkie", "short": "WALKIE", "col": Color(0.25, 0.7, 0.35),
		"blurb": "summons a dancing pizza mascot to block a rival"},
	"frisbee": {"name": "Pizza Frisbee", "short": "FRISBEE", "col": Color(1.0, 0.7, 0.2),
		"blurb": "toss it at a rival within 5 m to knock them down"},
	"socks": {"name": "Fire Socks", "short": "FIRE SOCKS", "col": Color(1.0, 0.4, 0.1), "blurb": "30% faster for 15 s"},
	"breadsticks": {"name": "Breadsticks", "short": "BREADSTICKS", "col": Color(0.9, 0.7, 0.35),
		"blurb": "grow huge and run over your rivals"},
}
const TOWN := ["portal", "wrench", "walkie", "frisbee", "socks", "breadsticks"]
const RACE := ["frisbee", "socks", "breadsticks"]

const GIVER_ODDS := 8          # 1 in 8 people hand out power-ups
const FRISBEE_RANGE_M := 5.0
const DOWN_TIME := 5.0         # seconds on the ground after a frisbee hit
const SQUASH_TIME := 3.0       # seconds on the ground after being run over
const SOCKS_TIME := 15.0
const SOCKS_BOOST := 1.3
const BREAD_TIME := 12.0
const BREAD_SCALE := 1.7
const MASCOT_TIME := 12.0


## How often each one turns up, relative to the others (1 = normal).
const ODDS := {"walkie": 0.3}


static func pick(pool: Array) -> String:
	var total := 0.0
	for k in pool:
		total += float(ODDS.get(k, 1.0))
	var r := randf() * total
	for k in pool:
		r -= float(ODDS.get(k, 1.0))
		if r <= 0.0:
			return k
	return pool[pool.size() - 1]


static func label(kind: String) -> String:
	return DEFS[kind]["name"] if DEFS.has(kind) else ""


static func col(kind: String) -> Color:
	return DEFS[kind]["col"] if DEFS.has(kind) else Color.WHITE


## A small pixel icon centred on `c`, about 10 px across at k = 1.
static func draw_icon(ci: CanvasItem, c: Vector2, kind: String, k := 1.0) -> void:
	var o := Iso.OUTLINE
	match kind:
		"portal":
			ci.draw_circle(c, 5.5 * k, o)
			ci.draw_circle(c, 4.6 * k, Color(0.95, 0.3, 0.2))
			ci.draw_circle(c, 3.0 * k, Color(1.0, 0.75, 0.3))
			ci.draw_circle(c, 1.4 * k, Color(0.55, 0.1, 0.35))
			for a in 3:
				var p := c + Vector2.from_angle(a * TAU / 3.0 + 0.5) * 3.6 * k
				ci.draw_circle(p, 0.9 * k, Color(0.7, 0.1, 0.1))
		"wrench":
			ci.draw_line(c + Vector2(-4, 4) * k, c + Vector2(3, -3) * k, o, 3.5 * k)
			ci.draw_line(c + Vector2(-4, 4) * k, c + Vector2(3, -3) * k, Color(0.78, 0.8, 0.86), 1.8 * k)
			ci.draw_circle(c + Vector2(3, -3) * k, 2.8 * k, o)
			ci.draw_circle(c + Vector2(3, -3) * k, 2.0 * k, Color(0.78, 0.8, 0.86))
			ci.draw_rect(Rect2(c + Vector2(3, -5) * k, Vector2(2, 2) * k), o)
		"walkie":
			ci.draw_rect(Rect2(c + Vector2(-3, -3) * k, Vector2(6, 8) * k), o)
			ci.draw_rect(Rect2(c + Vector2(-2, -2) * k, Vector2(4, 6) * k), Color(0.25, 0.7, 0.35))
			ci.draw_rect(Rect2(c + Vector2(-1.5, -1.5) * k, Vector2(3, 2) * k), Color(0.75, 0.95, 0.75))
			ci.draw_line(c + Vector2(1.5, -3) * k, c + Vector2(1.5, -6.5) * k, o, 1.5 * k)
			ci.draw_rect(Rect2(c + Vector2(-1, 2) * k, Vector2(1, 1) * k), o)
			ci.draw_rect(Rect2(c + Vector2(1, 2) * k, Vector2(1, 1) * k), o)
		"frisbee":
			ci.draw_circle(c, 5.0 * k, o)
			ci.draw_circle(c, 4.2 * k, Color(0.85, 0.55, 0.2))
			ci.draw_circle(c, 3.3 * k, Color(1.0, 0.85, 0.35))
			for p in [Vector2(-1.5, -1), Vector2(1.5, 0.5), Vector2(-0.5, 2)]:
				ci.draw_circle(c + p * k, 0.9 * k, Color(0.8, 0.15, 0.12))
		"socks":
			var flame := Color(1.0, 0.55, 0.1)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -6) * k, c + Vector2(0, -2) * k, c + Vector2(2, -6) * k,
				c + Vector2(3, 0) * k, c + Vector2(-3, 0) * k]), Color(1.0, 0.85, 0.2))
			ci.draw_rect(Rect2(c + Vector2(-3, -2) * k, Vector2(5, 5) * k), o)
			ci.draw_rect(Rect2(c + Vector2(-2, -1) * k, Vector2(3, 3) * k), flame)
			ci.draw_rect(Rect2(c + Vector2(-3, 2) * k, Vector2(7, 3) * k), o)
			ci.draw_rect(Rect2(c + Vector2(-2, 3) * k, Vector2(5, 1) * k), flame)
		"breadsticks":
			for q in 3:
				var x := (q - 1) * 2.6
				var a := c + Vector2(x - 1.0, 5) * k
				var b := c + Vector2(x + 1.0, -5) * k
				ci.draw_line(a, b, o, 3.2 * k)
				ci.draw_line(a, b, Color(0.9, 0.7, 0.35), 1.8 * k)
				ci.draw_rect(Rect2(b + Vector2(-0.5, 1.5) * k, Vector2(1, 1) * k), Color(1, 1, 0.9))


## A wrapped gift box with a "?" on it, held up by the people who hand out power-ups.
static func draw_gift(ci: CanvasItem, c: Vector2, t: float) -> void:
	var bob := sin(t * 5.0) * 1.0
	var p := c + Vector2(0, bob)
	ci.draw_rect(Rect2(p + Vector2(-5, -5), Vector2(10, 9)), Iso.OUTLINE)
	ci.draw_rect(Rect2(p + Vector2(-4, -4), Vector2(8, 7)), Color.from_hsv(fposmod(t * 0.3, 1.0), 0.6, 1.0))
	ci.draw_rect(Rect2(p + Vector2(-1, -4), Vector2(2, 7)), Color(1, 1, 1))
	ci.draw_rect(Rect2(p + Vector2(-4, -1), Vector2(8, 1)), Color(1, 1, 1))
	ci.draw_line(p + Vector2(0, -5), p + Vector2(-3, -8), Color(1, 1, 1), 1.0)
	ci.draw_line(p + Vector2(0, -5), p + Vector2(3, -8), Color(1, 1, 1), 1.0)
	var spark := Color(1.0, 0.95, 0.5, 0.5 + 0.5 * sin(t * 9.0))
	ci.draw_rect(Rect2(p + Vector2(6, -8), Vector2(1, 1)), spark)
	ci.draw_rect(Rect2(p + Vector2(-8, -3), Vector2(1, 1)), spark)


## A spinning pizza in flight, `u` (0..1) along the way from `a` to `b` in a shallow arc.
static func draw_frisbee(ci: CanvasItem, a: Vector2, b: Vector2, u: float, t: float) -> void:
	var p := a.lerp(b, u) + Vector2(0, -sin(u * PI) * 14.0)
	var w := 6.0
	var h := 2.5 + absf(sin(t * 20.0)) * 1.0
	var poly := PackedVector2Array()
	for i in 10:
		var ang := i * TAU / 10.0
		poly.append(p + Vector2(cos(ang) * w, sin(ang) * h))
	Iso.poly(ci, poly, Color(1.0, 0.82, 0.35))
	ci.draw_circle(p + Vector2(cos(t * 20.0) * 3.0, 0), 1.0, Color(0.8, 0.15, 0.12))
	ci.draw_circle(p + Vector2(-cos(t * 20.0) * 3.0, 0), 1.0, Color(0.8, 0.15, 0.12))


## The pizza mascot: a giant slice costume with arms, legs and a goofy face, dancing.
static func draw_mascot(ci: CanvasItem, ground: Vector2, t: float) -> void:
	var o := Iso.OUTLINE
	var hop := absf(sin(t * 7.0)) * 4.0
	var sway := sin(t * 3.5) * 3.0
	var base := ground + Vector2(sway, -hop)
	ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-8, 0), ground + Vector2(0, -3), ground + Vector2(8, 0), ground + Vector2(0, 3)]), Color(0, 0, 0, 0.25))
	# legs, kicking in turn
	for s in [-1.0, 1.0]:
		var kick := maxf(0.0, sin(t * 7.0 * s)) * 4.0
		var foot: Vector2 = ground + Vector2(s * 4.0 + kick * s, -kick * 0.6)
		ci.draw_line(base + Vector2(s * 3.0, -8), foot, o, 4.0)
		ci.draw_line(base + Vector2(s * 3.0, -8), foot, Color(0.95, 0.95, 0.95), 2.0)
		ci.draw_rect(Rect2(foot + Vector2(-3, -1), Vector2(6, 3)), Color(0.85, 0.15, 0.12))
	# the slice: crust on top, point at the bottom
	var top := base + Vector2(0, -34)
	var slice := PackedVector2Array([top + Vector2(-11, 0), top + Vector2(11, 0), base + Vector2(0, -6)])
	Iso.poly(ci, slice, Color(1.0, 0.8, 0.3))
	ci.draw_rect(Rect2(top + Vector2(-12, -4), Vector2(24, 6)), o)
	ci.draw_rect(Rect2(top + Vector2(-11, -3), Vector2(22, 4)), Color(0.8, 0.5, 0.2))
	for p in [Vector2(-5, 6), Vector2(5, 7), Vector2(0, 15), Vector2(-2, 21)]:
		ci.draw_circle(top + p, 2.2, Color(0.8, 0.15, 0.12))
	# face
	ci.draw_circle(top + Vector2(-3, 9), 1.8, Color(1, 1, 1))
	ci.draw_circle(top + Vector2(3, 9), 1.8, Color(1, 1, 1))
	ci.draw_rect(Rect2(top + Vector2(-3.5, 8.5), Vector2(1, 1)), o)
	ci.draw_rect(Rect2(top + Vector2(2.5, 8.5), Vector2(1, 1)), o)
	ci.draw_arc(top + Vector2(0, 12), 3.0, 0.2, PI - 0.2, 6, o, 1.0)
	# arms waving overhead
	for s in [-1.0, 1.0]:
		var wave := sin(t * 7.0 + s) * 4.0
		var hand: Vector2 = top + Vector2(s * (16.0 + wave * 0.5), -6.0 - absf(wave))
		ci.draw_line(top + Vector2(s * 9.0, 4), hand, o, 3.0)
		ci.draw_line(top + Vector2(s * 9.0, 4), hand, Color(1.0, 0.8, 0.3), 1.0)
		ci.draw_circle(hand, 2.0, Color(1, 1, 1))
	# music notes
	for q in 2:
		var u := fposmod(t * 0.7 + q * 0.5, 1.0)
		var np := base + Vector2(14.0 + q * 5.0 + sin(u * 6.0) * 3.0, -30.0 - u * 18.0)
		var nc := Color(1.0, 0.85, 0.3, 1.0 - u)
		ci.draw_circle(np, 1.6, nc)
		ci.draw_line(np + Vector2(1.4, 0), np + Vector2(1.4, -6), nc, 1.0)


## Flames licking up behind a rider in Fire Socks (`c` = rider, `back` = screen direction behind).
static func draw_flames(ci: CanvasItem, c: Vector2, back: Vector2, t: float) -> void:
	for q in 5:
		var u := fposmod(t * 3.0 + q * 0.21, 1.0)
		var p := c + back * (6.0 + u * 18.0) + Vector2(sin(t * 13.0 + q) * 2.0, -4.0 - u * 6.0)
		ci.draw_circle(p, 3.5 * (1.0 - u) + 1.0, Color(1.0, 0.85 - u * 0.6, 0.15, 0.85 * (1.0 - u)))


## A plain spectator (used along the race course), the same style as the town's pedestrians.
static func draw_person(ci: CanvasItem, ground: Vector2, shirt: Color, skin: Color, hair: Color, t: float, arm_up: bool) -> void:
	var o := Iso.OUTLINE
	var base := ground + Vector2(0, -absf(sin(t * 4.0)) * 1.5)
	ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-4, 0), ground + Vector2(0, -2), ground + Vector2(4, 0), ground + Vector2(0, 2)]), Color(0, 0, 0, 0.2))
	ci.draw_line(base + Vector2(-1, -6), base + Vector2(-1, 0), Color(0.2, 0.25, 0.45), 2.0)
	ci.draw_line(base + Vector2(1, -6), base + Vector2(1, 0), Color(0.2, 0.25, 0.45), 2.0)
	if arm_up:
		ci.draw_line(base + Vector2(3, -12), base + Vector2(6, -20), o, 2.0)
		ci.draw_line(base + Vector2(3, -12), base + Vector2(6, -20), skin, 1.0)
	else:
		ci.draw_line(base + Vector2(3, -12), base + Vector2(4, -7), shirt.darkened(0.2), 1.0)
	ci.draw_line(base + Vector2(-3, -12), base + Vector2(-4, -7), shirt.darkened(0.2), 1.0)
	ci.draw_rect(Rect2(base + Vector2(-3, -13), Vector2(6, 7)), o)
	ci.draw_rect(Rect2(base + Vector2(-2, -12), Vector2(4, 6)), shirt)
	ci.draw_circle(base + Vector2(0, -16), 3.0, o)
	ci.draw_circle(base + Vector2(0, -16), 2.4, skin)
	ci.draw_rect(Rect2(base + Vector2(-2, -19), Vector2(4, 2)), hair)
