class_name PowerUps
extends RefCounted
## Power-ups: about 1 in 8 townsfolk (and spectators along the race course) hand them out as you ride past.
## A rider carries one at a time (shown on the WEEHOO) and uses it with Y. Rivals grab and use them too.
## Town only: portal, wrench, walkie. Town and race: frisbee, socks, breadsticks, roller.

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
	"roller": {"name": "Dough Roller", "short": "ROLLER", "col": Color(0.85, 0.6, 0.35), "blurb": "hills feel flat for 15 s"},
}
const TOWN := ["portal", "wrench", "walkie", "frisbee", "socks", "breadsticks", "roller"]
const RACE := ["frisbee", "socks", "breadsticks", "roller"]

const GIVER_ODDS := 8          # 1 in 8 people hand out power-ups
const FRISBEE_RANGE_M := 5.0
const DOWN_TIME := 5.0         # seconds on the ground after a frisbee hit
const SQUASH_TIME := 3.0       # seconds on the ground after being run over
const SOCKS_TIME := 15.0
const SOCKS_BOOST := 1.3
const BREAD_TIME := 12.0
const BREAD_SCALE := 1.7
const MASCOT_TIME := 12.0
const ROLLER_TIME := 15.0      # Dough Roller: climbs feel flat (descents still count)


## The grade a rider feels: a Dough Roller flattens the climbs.
static func felt_grade(g: float, roller: float) -> float:
	return minf(g, 0.0) if roller > 0.0 else g


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
	Sprites.draw_image(ci, "scenery_icon_%s" % kind, c + Vector2(0, 8.0 * k), false, 1.0, 0.5 * k)


## A wrapped gift box with a "?" on it, held up by the people who hand out power-ups.
## A spinning pizza in flight, `u` (0..1) along the way from `a` to `b` in a shallow arc.
static func draw_frisbee(ci: CanvasItem, a: Vector2, b: Vector2, u: float, t: float) -> void:
	var p := a.lerp(b, u) + Vector2(0, -sin(u * PI) * 14.0)
	Sprites.draw_strip(ci, "pizza_spin", p, t, 24.0, false)


## The pizza mascot: a giant slice costume, dancing (art/mascot_dance.png).
static func draw_mascot(ci: CanvasItem, ground: Vector2, t: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array([ground + Vector2(-8, 0), ground + Vector2(0, -3), ground + Vector2(8, 0), ground + Vector2(0, 3)]), Color(0, 0, 0, 0.25))
	Sprites.draw_strip(ci, "mascot_dance", ground, t, 10.0)


## Flames licking up behind a rider in Fire Socks (`c` = rider, `back` = screen direction behind).
static func draw_flames(ci: CanvasItem, c: Vector2, back: Vector2, t: float) -> void:
	for q in 5:
		var u := fposmod(t * 3.0 + q * 0.21, 1.0)
		var p := c + back * (6.0 + u * 18.0) + Vector2(sin(t * 13.0 + q) * 2.0, -4.0 - u * 6.0)
		ci.draw_circle(p, 3.5 * (1.0 - u) + 1.0, Color(1.0, 0.85 - u * 0.6, 0.15, 0.85 * (1.0 - u)))


