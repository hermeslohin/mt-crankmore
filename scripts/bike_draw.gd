class_name BikeDraw
extends RefCounted
## Draws a rider for both the city and the mountain race: the shadow on the ground, then the pixel-art sprite (see
## Sprites) and, over a hot pizza, its steam. Every rider is a sprite sheet; there is no procedural fallback.

const SHADOW_COL := Color(0, 0, 0, 0.22)

# Projection state for the rider being drawn (drawing is single threaded and not re-entrant).
static var _c := Vector2.ZERO        # screen position of the ground contact
static var _sf := Vector2.RIGHT      # screen offset of one pixel forward
static var _sl := Vector2.DOWN       # screen offset of one pixel sideways


## `c` is the screen position of the rider's ground contact, `ds` the screen-space travel direction.
## `heat` (0..1) sets how much steam rises from the pizza: a fresh pie steams hard, a cold one not at all.
## `fall_t` >= 0 plays the wipe-out animation, that many seconds in.
static func draw(ci: CanvasItem, c: Vector2, ds: Vector2, phase: float, has_pizza: bool, who: String = "YOU", heat := 1.0, boxed := true, fall_t := -1.0) -> void:
	ds = ds.normalized()
	if ds == Vector2.ZERO:
		ds = Vector2.RIGHT
	# undo the isometric projection to get the world heading, then the sideways axis (both unit length)
	var w := Vector2(ds.x + 2.0 * ds.y, 2.0 * ds.y - ds.x).normalized()
	var wl := Vector2(-w.y, w.x)
	_c = c
	_sf = _iso(w) * 0.9
	_sl = _iso(wl) * 1.1

	# shadow on the ground, stretched along the heading
	var sh := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		sh.append(_proj(Vector3(cos(a) * 15.0, sin(a) * 6.5, 0.0)))
	ci.draw_colored_polygon(sh, SHADOW_COL)
	if Sprites.draw_rider(ci, c, w, phase, has_pizza, who, boxed, fall_t) and has_pizza and heat > 0.0 and fall_t < 0.0:
		# from the pizza itself, wherever it sits in this frame (a rough spot over the rack if it can't be found)
		_steam(ci, Sprites.pizza_top if Sprites.pizza_top != Vector2.INF else _proj(Vector3(-11, 0, 17.4)), heat)


static func _iso(v: Vector2) -> Vector2:
	return Vector2(v.x - v.y, (v.x + v.y) * 0.5)


static func _proj(p: Vector3) -> Vector2:
	return _c + _sf * p.x + _sl * p.y + Vector2(0, -p.z)


## Wisps of steam curling up from a hot pizza box. Drawn on top of the rider, they rise, sway and fade.
static func _steam(ci: CanvasItem, top: Vector2, heat: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var wisps := 1 + int(round(heat * 2.0))
	for w in wisps:
		var x0 := (w - (wisps - 1) * 0.5) * 3.2
		for k in 6:
			# each puff loops from the box lid up to about 20 px above it
			var u := fposmod(t * 0.9 + k / 6.0 + w * 0.37, 1.0)
			var y := -u * (12.0 + 9.0 * heat)
			var x := x0 + sin(u * 7.0 + t * 3.0 + w * 2.1) * (1.0 + u * 2.5)
			var a := (1.0 - u) * (0.25 + 0.6 * heat)
			var r := 1.0 + u * 1.8
			ci.draw_circle(top + Vector2(x, y), r + 0.6, Color(0.55, 0.6, 0.7, a * 0.35))
			ci.draw_circle(top + Vector2(x, y), r, Color(1, 1, 1, a))


static func world_dir(head: float) -> Vector2:
	var d := Vector2(cos(head), sin(head))
	return Vector2(d.x - d.y, (d.x + d.y) * 0.5)
