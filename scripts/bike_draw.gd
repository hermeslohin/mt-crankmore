class_name BikeDraw
extends RefCounted
## Procedural 16-bit cyclist, used by both the city and the mountain race: outlined frame,
## spoked wheels that turn, crank + chainring, jersey with stripe, helmet, shoes, pizza box.
## The rider is a small 3D model (x = forward, y = sideways, z = up, in pixels). Every part is projected through the
## bike's heading and the parts are depth-sorted, so a bike coming head-on has shoulders, two legs and a tire width,
## and limbs / wheels / pizza box layer correctly as it turns.

const INK := Color(0.1, 0.08, 0.16)
const SKIN := Color(0.96, 0.78, 0.62)
const TIRE := Color(0.16, 0.16, 0.2)


## Per-character looks, keyed by the rider's short name ("YOU" is the player). Missing keys fall back to DEFAULT_STYLE.
## hat: helmet | cap | chef | beret | visor | beanie | band      hair: none | ponytail | long | bun | dreads | mohawk
## shades: none | shades | round                                  stache: none | stache | beard
const DEFAULT_STYLE := {"skin": Color(0.96, 0.78, 0.62), "hat": "helmet", "hat_col": Color(0, 0, 0, 0), "hair": "none", "hair_col": Color(0.25, 0.15, 0.1),
	"shades": "none", "stache": "none", "scarf": Color(0, 0, 0, 0), "shoe": Color(0.95, 0.95, 0.95), "glove": Color(0.12, 0.12, 0.16), "emblem": true}
const STYLES := {
	"YOU": {"hat": "cap", "hat_col": Color(0.92, 0.18, 0.15), "shades": "shades", "scarf": Color(1.0, 0.85, 0.2), "shoe": Color(1.0, 0.85, 0.2), "hair": "ponytail", "hair_col": Color(0.2, 0.12, 0.08)},
	"Dave": {"hat": "chef", "hat_col": Color(1, 1, 1), "stache": "stache", "hair_col": Color(0.15, 0.1, 0.08), "skin": Color(0.98, 0.74, 0.58), "shoe": Color(0.95, 0.4, 0.15)},
	"Sam": {"hat": "beret", "hat_col": Color(0.35, 0.18, 0.55), "shades": "round", "scarf": Color(0.9, 0.85, 0.95), "skin": Color(0.72, 0.5, 0.36), "hair": "bun", "hair_col": Color(0.1, 0.08, 0.08)},
	"Carla": {"hat": "visor", "hat_col": Color(1, 1, 1), "shades": "round", "hair": "bun", "hair_col": Color(0.55, 0.3, 0.15), "skin": Color(0.99, 0.84, 0.7), "shoe": Color(0.1, 0.75, 0.75)},
	"Wanda": {"hat": "helmet", "hat_col": Color(1.0, 0.4, 0.7), "hair": "ponytail", "hair_col": Color(0.95, 0.75, 0.2), "scarf": Color(1.0, 0.85, 0.95), "skin": Color(0.88, 0.62, 0.45), "shoe": Color(1.0, 0.4, 0.7)},
	"Gus": {"hat": "cap", "hat_col": Color(0.45, 0.36, 0.26), "stache": "beard", "hair_col": Color(0.8, 0.8, 0.82), "skin": Color(0.9, 0.66, 0.5), "shoe": Color(0.35, 0.28, 0.2)},
	"Maya": {"hat": "band", "hat_col": Color(0.95, 0.95, 0.9), "shades": "shades", "hair": "long", "hair_col": Color(0.08, 0.06, 0.08), "skin": Color(0.62, 0.42, 0.3), "scarf": Color(0.35, 0.8, 0.35), "shoe": Color(0.35, 0.8, 0.35)},
	"Tony": {"hat": "beanie", "hat_col": Color(0.95, 0.85, 0.2), "shades": "shades", "hair": "dreads", "hair_col": Color(0.4, 0.25, 0.12), "skin": Color(0.93, 0.7, 0.52), "shoe": Color(0.95, 0.85, 0.2)},
}


static func style_for(who: String) -> Dictionary:
	var st := DEFAULT_STYLE.duplicate()
	st.merge(STYLES.get(who, STYLES["YOU"] if who == "" else {}), true)
	return st


const HEAD_R := 4.6
const WHEEL_R := 6.0
const WHEEL_HW := 1.6     # half the tire width
const SILVER := Color(0.75, 0.75, 0.8)

enum { LIMB, BALL, POLY, LINE, LINES }

# Projection state for the bike being drawn (drawing is single threaded and not re-entrant).
static var _c := Vector2.ZERO        # screen position of the ground contact
static var _sf := Vector2.RIGHT      # screen offset of one pixel forward
static var _sl := Vector2.DOWN       # screen offset of one pixel sideways
static var _cam := Vector3.ZERO      # unit vector towards the camera in bike space, for facing tests
static var _dw := Vector3.ZERO       # depth weights: bigger dot = nearer to the camera
static var _hc := Vector3.ZERO       # head centre
static var _items: Array = []


## `c` is the screen position of the bike's ground contact, `ds` the screen-space travel direction.
## `heat` (0..1) sets how much steam rises from the pizza box: a fresh pie steams hard, a cold one not at all.
static func draw(ci: CanvasItem, c: Vector2, ds: Vector2, frame_col: Color, shirt: Color, phase: float, has_pizza: bool, who: String = "YOU", heat := 1.0) -> void:
	var st := style_for(who)
	ds = ds.normalized()
	if ds == Vector2.ZERO:
		ds = Vector2.RIGHT
	# undo the isometric projection to get the world heading, then the sideways axis (both unit length)
	var w := Vector2(ds.x + 2.0 * ds.y, 2.0 * ds.y - ds.x).normalized()
	var wl := Vector2(-w.y, w.x)
	_c = c
	_sf = _iso(w) * 0.9
	_sl = _iso(wl) * 1.1
	var near_f := (w.x + w.y) * 0.612
	var near_l := (wl.x + wl.y) * 0.612
	_cam = Vector3(near_f, near_l, 0.5).normalized()
	# sideways gets extra weight so the near arm / leg / rim always beat the body they overlap
	_dw = Vector3(near_f, near_l * 1.8, 0.25)
	_items.clear()
	# the side that is nearer to the camera, and how strongly (0 head-on, 1 side-on)
	var side := 1.0 if near_l >= 0.0 else -1.0
	var lateral := clampf(absf(near_l) * 1.6, 0.0, 1.0)

	# shadow on the ground, stretched along the heading
	var sh := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		sh.append(_proj(Vector3(cos(a) * 15.0, sin(a) * 6.5, 0.0)))
	if not Sprites.baking:   # sprite sheets leave the shadow to the game
		ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.22))
	# pixel art, when there is a sheet for this rider (see Sprites)
	if Sprites.draw_bike(ci, c, w, frame_col, shirt, phase, has_pizza, who):
		if has_pizza and heat > 0.0:
			_steam(ci, _proj(Vector3(-11, 0, 17.4)), heat)
		return

	var bob := Vector3(0, 0, sin(phase * 2.0) * 0.7)
	# both cranks and wheels turn clockwise seen from the drive side (the top moves forward), like a real bike
	var spin := -phase * 1.6
	var rear := Vector3(-11, 0, WHEEL_R)
	var front := Vector3(11, 0, WHEEL_R)
	var bb := Vector3(-1, 0, 7)
	var seat := Vector3(-4, 0, 17)
	var bars := Vector3(8, 0, 18)

	# ---- bike ----
	_wheel(rear, spin, side)
	_wheel(front, spin, side)
	for p in [[bb, seat], [bb, bars], [seat, bars]]:
		_limb(p[0], p[1], 2.0, frame_col)
	_line3(seat + Vector3(0, 0, 1), bars + Vector3(0, 0, 1), frame_col.lightened(0.45), 1.0, 0.05)
	for s in [-1.0, 1.0]:
		# fork blades, seat stays and chain stays straddle the tire
		_limb(bars + Vector3(0.2, s * 0.9, -0.8), front + Vector3(0, s * 2.0, 0), 1.5, frame_col)
		_limb(seat + Vector3(0.4, s * 0.8, -0.6), rear + Vector3(0, s * 2.0, 0), 1.3, frame_col.darkened(0.1))
		_limb(bb + Vector3(0, s * 1.0, 0), rear + Vector3(0, s * 2.0, 0), 1.3, frame_col.darkened(0.3))
	# chainring on the drive side
	_ball(bb + Vector3(0, 1.4, 0), 1.8, SILVER)
	# saddle and drop bars
	_limb(seat + Vector3(-2.8, 0, 0.6), seat + Vector3(2.2, 0, 0.6), 1.8, Color(0.35, 0.3, 0.4))
	_limb(bars + Vector3(-1.5, 0, 0.3), bars + Vector3(0.6, 0, 0.8), 1.6, SILVER.darkened(0.2))
	for s in [-1.0, 1.0]:
		_limb(bars + Vector3(0, s * 3.4, 0), bars + Vector3(0, s * 3.4, 0) + Vector3(2.6, 0, -1.8), 1.6, SILVER.darkened(0.15))
	_limb(bars + Vector3(0, -3.4, 0), bars + Vector3(0, 3.4, 0), 1.6, SILVER.darkened(0.15))
	if has_pizza:
		_pizza_box(Vector3(-11, 0, 15.6))

	# ---- rider ----
	var skin: Color = st["skin"]
	var hip := Vector3(-4.5, 0, 18.0)
	var shoulder_c := Vector3(2.5, 0, 27.0) + bob
	_hc = Vector3(5.0, 0, 33.2) + bob
	# scarf / cape streaming behind the rider, flapping with the pedal stroke (sideways, now that we have a side)
	var scarf: Color = st["scarf"]
	if scarf.a > 0.0:
		var neck := shoulder_c + Vector3(-0.4, 0, 1.8)
		_limb(neck + Vector3(0, -2.4, 0), neck + Vector3(0, 2.4, 0), 2.6, scarf)
		var prev := neck
		for k in range(1, 6):
			var u := k / 5.0
			var pt := neck + Vector3(-u * 11.0, sin(phase * 3.0 - u * 4.0) * 2.2 * u, -u * 3.0 + 0.6)
			_limb(prev, pt, 2.4, scarf)
			prev = pt
	# legs: the side that points away from the camera is shaded darker
	for s in [-1.0, 1.0]:
		var ph := phase + (0.0 if s > 0.0 else PI)
		var foot := bb + Vector3(cos(ph) * 5.0, s * 2.4, -sin(ph) * 4.0)
		var hp := hip + Vector3(0, s * 1.9, 0)
		var knee := (hp + foot) * 0.5 + Vector3(4.0, s * 0.9, 2.0)
		var dk := clampf(-s * side * lateral * 0.3 + (0.0 if s * side > 0.0 else 0.08), 0.0, 0.3)
		var shorts := Color(0.14, 0.14, 0.2).darkened(dk)
		var calf := skin.darkened(dk)
		var shoe_col: Color = Color(st["shoe"]).darkened(dk)
		_limb(hp, knee, 3.6, shorts)
		_limb(knee, foot, 2.4, calf)
		_limb(foot + Vector3(-1.8, 0, 0), foot + Vector3(2.6, 0, 0), 1.9, shoe_col)
		_line3(bb + Vector3(0, s * 2.0, 0), foot - Vector3(0, 0.4 * s, 0), SILVER.darkened(0.25), 1.0, -0.02)
	# torso: a lofted body, wide at the shoulders, thin front to back
	_torso(hip, shoulder_c, shirt, st)
	# arms: sleeve, skin forearm, glove on the drop bar
	for s in [-1.0, 1.0]:
		var sh_p := shoulder_c + Vector3(0.2, s * 4.3, -0.4)
		var hand := bars + Vector3(0.6, s * 3.4, 0.3)
		var elbow := (sh_p + hand) * 0.5 + Vector3(0.0, s * 1.5, 1.2)
		var dk := clampf(-s * side * lateral * 0.3 + (0.0 if s * side > 0.0 else 0.08), 0.0, 0.3)
		_ball(sh_p, 2.2, shirt.darkened(0.12 + dk))
		_limb(sh_p, elbow, 2.6, shirt.darkened(0.15 + dk))
		_limb(elbow, hand, 2.2, skin.darkened(dk))
		_ball(hand, 1.2, Color(st["glove"]))
	# neck, head, face, headgear
	_limb(shoulder_c + Vector3(0.6, 0, 1.6), _hc + Vector3(-0.8, 0, -2.4), 2.8, skin.darkened(0.1))
	_head(st, skin, shirt, phase)

	_flush(ci)
	if has_pizza and heat > 0.0:
		_steam(ci, _proj(Vector3(-11, 0, 17.4)), heat)


# ---------------------------------------------------------------- projection

static func _iso(v: Vector2) -> Vector2:
	return Vector2(v.x - v.y, (v.x + v.y) * 0.5)


static func _proj(p: Vector3) -> Vector2:
	return _c + _sf * p.x + _sl * p.y + Vector2(0, -p.z)


static func _depth(p: Vector3) -> float:
	return p.dot(_dw)


static func _push(depth: float, kind: int, a, b, w, col) -> void:
	# the running index keeps equal depths in drawing order
	_items.append([depth + _items.size() * 0.00001, kind, a, b, w, col])


## A thick rounded limb with an ink outline.
static func _limb(a: Vector3, b: Vector3, w: float, col: Color, bias := 0.0) -> void:
	_push(_depth((a + b) * 0.5) + bias, LIMB, _proj(a), _proj(b), w, col)


static func _ball(p: Vector3, r: float, col: Color, bias := 0.0) -> void:
	_push(_depth(p) + bias, BALL, _proj(p), r, true, col)


static func _line3(a: Vector3, b: Vector3, col: Color, w: float, bias := 0.0) -> void:
	_push(_depth((a + b) * 0.5) + bias, LINE, _proj(a), _proj(b), w, col)


## Fills the convex hull of the projected points (the exact silhouette of a convex 3D shape).
static func _hull(pts: PackedVector2Array, col: Color, outline: bool, depth: float) -> void:
	var h := Geometry2D.convex_hull(pts)
	if h.size() >= 4:
		_push(depth, POLY, h, outline, 0.0, col)


static func _flush(ci: CanvasItem) -> void:
	_items.sort_custom(func(a, b): return a[0] < b[0])
	for it in _items:
		match it[1]:
			LIMB:
				var a: Vector2 = it[2]
				var b: Vector2 = it[3]
				var w: float = it[4]
				var ink := w + 1.6
				ci.draw_line(a, b, INK, ink)
				ci.draw_circle(a, ink * 0.5, INK)
				ci.draw_circle(b, ink * 0.5, INK)
				ci.draw_line(a, b, it[5], w)
				ci.draw_circle(a, w * 0.5, it[5])
				ci.draw_circle(b, w * 0.5, it[5])
			BALL:
				if it[4]:
					ci.draw_circle(it[2], it[3] + 0.9, INK)
				ci.draw_circle(it[2], it[3], it[5])
			POLY:
				if Geometry2D.triangulate_polygon(it[2]).is_empty():
					continue   # seen edge-on: a sliver the renderer can't fill
				ci.draw_colored_polygon(it[2], it[5])
				if it[3]:
					ci.draw_polyline(it[2], INK, 1.0)
			LINE:
				ci.draw_line(it[2], it[3], it[5], it[4])
			LINES:
				ci.draw_polyline(it[2], it[5], it[4])


# ---------------------------------------------------------------- parts

## A wheel is a disc standing in the vertical plane of travel with a tire width: a far and a near rim joined by tread.
## Only the rim nearer the camera shows spokes. Head-on, the disc is edge-on and the tire width gives it body.
static func _wheel(center: Vector3, spin: float, side: float) -> void:
	var n := 18
	var far_pts := PackedVector2Array()
	var near_pts := PackedVector2Array()
	var rim := PackedVector2Array()
	for k in n + 1:
		var a := TAU * k / n
		var o := Vector3(cos(a) * WHEEL_R, 0, sin(a) * WHEEL_R)
		far_pts.append(_proj(center + o + Vector3(0, -side * WHEEL_HW, 0)))
		near_pts.append(_proj(center + o + Vector3(0, side * WHEEL_HW, 0)))
		rim.append(_proj(center + o * 0.73 + Vector3(0, side * WHEEL_HW, 0)))
	var fd := _depth(center + Vector3(0, -side * WHEEL_HW, 0))
	var nd := _depth(center + Vector3(0, side * WHEEL_HW, 0))
	for k in n:
		_push(fd, LINE, far_pts[k], near_pts[k], 1.8, TIRE)
	_push(fd, LINES, far_pts, 0, 2.2, INK)
	_push(nd, LINES, near_pts, 0, 3.4, INK)
	_push(nd, LINES, near_pts, 0, 2.0, TIRE)
	_push(nd, LINES, rim, 0, 1.0, Color(0.78, 0.8, 0.85))
	var hub := _proj(center + Vector3(0, side * WHEEL_HW, 0))
	for k in 3:
		var a := spin + k * PI / 3.0
		var d := _sf * (cos(a) * 4.2) + Vector2(0, -sin(a) * 4.2)
		_push(nd, LINE, hub - d, hub + d, 1.0, Color(0.65, 0.67, 0.72))
	_push(fd, LINE, _proj(center + Vector3(0, -side * WHEEL_HW, 0)), hub, 1.6, INK)
	_push(nd, BALL, hub, 1.2, true, INK)


## Jersey: a loft of elliptical sections from the hips to the shoulders (convex hull of the projected rings),
## then a lit core, a belt line, and the pizza emblem on whichever face the camera sees best.
static func _torso(hip: Vector3, sh: Vector3, shirt: Color, st: Dictionary) -> void:
	var dir := (sh - hip)
	var back := Vector3(-dir.z, 0, dir.x).normalized()   # points up and back, away from the chest
	if back.z < 0.0:
		back = -back
	var all := PackedVector2Array()
	var core := PackedVector2Array()
	for t in [0.0, 0.5, 1.0]:
		var ctr := hip.lerp(sh, t)
		var hw := lerpf(3.2, 4.9, t)
		var ht := lerpf(3.0, 2.5, t)
		for k in 10:
			var a := TAU * k / 10.0
			all.append(_proj(ctr + back * (ht * cos(a)) + Vector3(0, hw * sin(a), 0)))
			core.append(_proj(ctr + back * (ht * 0.8 * cos(a)) + Vector3(0, hw * 0.75 * sin(a), 1.0)))
	var mid := hip.lerp(sh, 0.5)
	var d := _depth(mid)
	_hull(all, shirt.darkened(0.2), true, d)
	_hull(core, shirt, false, d + 0.001)
	# highlight along the back, belt line around the waist
	_push(d + 0.002, LINE, _proj(hip.lerp(sh, 0.15) + back * 2.5), _proj(hip.lerp(sh, 0.9) + back * 2.3), 1.1, shirt.lightened(0.5))
	var belt := hip.lerp(sh, 0.28)
	for k in 12:
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		var n0 := back * cos(a0) + Vector3(0, sin(a0), 0)
		var n1 := back * cos(a1) + Vector3(0, sin(a1), 0)
		if (n0 + n1).dot(_cam) > 0.0:
			var hw := lerpf(3.2, 4.9, 0.28) + 0.1
			var p0 := belt + back * (2.9 * cos(a0)) + Vector3(0, hw * sin(a0), 0)
			var p1 := belt + back * (2.9 * cos(a1)) + Vector3(0, hw * sin(a1), 0)
			_line3(p0, p1, shirt.darkened(0.4), 1.2, 0.003)
	if st["emblem"]:
		# the emblem sits on the back or on a flank, whichever faces the camera most
		var c := hip.lerp(sh, 0.6)
		var hw := lerpf(3.2, 4.9, 0.6)
		var best := back.dot(_cam)
		var pos := c + back * 2.6
		for s in [-1.0, 1.0]:
			var v: float = s * _cam.y
			if v > best:
				best = v
				pos = c + Vector3(0, s * hw, 0)
		if best > 0.12:
			var e := _proj(pos)
			var ed := _depth(pos) + 0.01
			_push(ed, BALL, e, 1.9, true, Color(1.0, 0.82, 0.25))
			_push(ed, POLY, PackedVector2Array([e + Vector2(-1.2, -1.0), e + Vector2(1.2, -1.0), e + Vector2(0, 1.4)]), false, 0.0, Color(0.85, 0.15, 0.1))


# ---------------------------------------------------------------- head

## A point on the head sphere in direction `dir` (x forward, y sideways, z up), scaled from the centre.
static func _hp(dir: Vector3, k := 1.0) -> Vector3:
	return _hc + dir.normalized() * (HEAD_R * k)


static func _facing(dir: Vector3) -> float:
	return dir.normalized().dot(_cam)


## Points on a latitude ring of the head (e = sin of the latitude).
static func _ring(e: float, k: float, n: int) -> Array:
	var out := []
	var cp := sqrt(maxf(1.0 - e * e, 0.0))
	for i in n:
		var a := TAU * i / n
		out.append(_hc + Vector3(cos(a) * cp, sin(a) * cp, e) * (HEAD_R * k))
	return out


## Cap of the sphere above latitude `z0`: hull of its rim and a mid ring, so it fits the head from any direction.
static func _dome(z0: float, grow: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in _ring(z0, grow, 12):
		pts.append(_proj(p))
	for p in _ring(lerpf(z0, 1.0, 0.5), grow, 12):
		pts.append(_proj(p))
	pts.append(_proj(_hc + Vector3(0, 0, HEAD_R * grow)))
	_hull(pts, col, true, _depth(_hc) + 0.01)


static func _band(e: float, k: float, w: float, col: Color) -> void:
	var ring := _ring(e, k, 14)
	for i in ring.size():
		_limb(ring[i], ring[(i + 1) % ring.size()], w, col)


static func _brim(col: Color, length: float, drop: float, wide: float) -> void:
	var pts := PackedVector2Array()
	for p in [Vector3(3.2, -3.2, 1.9), Vector3(3.2 + length, -wide, 1.9 - drop), Vector3(3.2 + length, wide, 1.9 - drop), Vector3(3.2, 3.2, 1.9)]:
		pts.append(_proj(_hc + p))
	pts.append(pts[0])
	_push(_depth(_hc + Vector3(3.2 + length * 0.5, 0, 1.9 - drop * 0.5)), POLY, pts, true, 0.0, col)


static func _head(st: Dictionary, skin: Color, shirt: Color, phase: float) -> void:
	var hair: Color = st["hair_col"]
	var hat: String = st["hat"]
	var hat_col: Color = st["hat_col"]
	if hat_col.a <= 0.0:
		hat_col = shirt
	_hair_back(st, phase)
	_ball(_hc, HEAD_R, skin)
	# face: only the parts turned towards the camera are drawn
	var fd := 0.3
	var nose_d := Vector3(1.0, 0.0, -0.12)
	if _facing(nose_d) > 0.1:
		_push(_depth(_hp(nose_d, 1.1)) + fd, BALL, _proj(_hp(nose_d, 1.1)), 1.0, false, skin.darkened(0.15))
	for s in [-1.0, 1.0]:
		var ed := Vector3(0.92, s * 0.4, 0.2)
		if _facing(ed) > 0.12 and st["shades"] == "none":
			var e := _hp(ed)
			var e2 := _proj(e)
			_push(_depth(e) + fd, LINE, e2 + Vector2(0, 0.8), e2 + Vector2(0, -0.9), 1.4, INK)
			_push(_depth(e) + fd + 0.01, LINE, e2 + Vector2(0.4, -0.8), e2 + Vector2(0.4, -1.2), 0.7, Color(1, 1, 1))
	match st["shades"]:
		"shades":
			var prev := Vector3.ZERO
			for i in range(-6, 7):
				var a := deg_to_rad(i * 6.5)
				var dd := Vector3(cos(a), sin(a), 0.22)
				var p := _hp(dd, 1.04)
				if i > -6 and (_facing(dd) > 0.05):
					var col := INK if absi(i) <= 1 or absi(i) == 6 else INK
					_push(_depth(p) + fd, LINE, _proj(prev), _proj(p), 2.8, col)
					if absi(i) > 1 and absi(i) < 6:
						_push(_depth(p) + fd + 0.01, LINE, _proj(prev), _proj(p), 1.2, Color(0.55, 0.85, 1.0))
				prev = p
			for s in [-1.0, 1.0]:
				var t0 := _hp(Vector3(cos(deg_to_rad(40)), s * sin(deg_to_rad(40)), 0.22), 1.04)
				var t1 := _hp(Vector3(cos(deg_to_rad(95)), s * sin(deg_to_rad(95)), 0.22), 1.04)
				if _facing(Vector3(0.3, s * 0.95, 0.22)) > 0.1:
					_push(_depth(t0) + fd, LINE, _proj(t0), _proj(t1), 1.0, INK)
		"round":
			for s in [-1.0, 1.0]:
				var ld := Vector3(0.9, s * 0.4, 0.2)
				if _facing(ld) > 0.1:
					var tan1 := Vector3(-ld.y, ld.x, 0).normalized()
					var ring := PackedVector2Array()
					for i in 11:
						var a := TAU * i / 10.0
						ring.append(_proj(_hp(ld.normalized() + (tan1 * cos(a) + Vector3(0, 0, sin(a))) * 0.3, 1.05)))
					_push(_depth(_hp(ld)) + fd, POLY, ring, false, 0.0, Color(0.75, 0.9, 1.0, 0.85))
					_push(_depth(_hp(ld)) + fd + 0.01, LINES, ring, 0, 1.1, INK)
			var bridge := _hp(Vector3(0.97, 0.0, 0.2), 1.04)
			if _facing(Vector3(1, 0, 0.2)) > 0.1:
				_push(_depth(bridge) + fd, LINE, _proj(bridge) - Vector2(1.2, 0), _proj(bridge) + Vector2(1.2, 0), 1.0, INK)
	# mouth
	var md := Vector3(0.95, 0.0, -0.36)
	if _facing(md) > 0.1:
		_push(_depth(_hp(md)) + fd + 0.05, LINE, _proj(_hp(Vector3(0.95, -0.22, -0.36))), _proj(_hp(Vector3(0.95, 0.22, -0.36))), 1.0, INK)
	match st["stache"]:
		"stache":
			for i in range(-3, 3):
				var d0 := Vector3(cos(deg_to_rad(i * 7.0)), sin(deg_to_rad(i * 7.0)), -0.2)
				var d1 := Vector3(cos(deg_to_rad((i + 1) * 7.0)), sin(deg_to_rad((i + 1) * 7.0)), -0.2)
				if _facing(d0) > 0.05:
					_push(_depth(_hp(d0)) + fd + 0.1, LINE, _proj(_hp(d0, 1.06)), _proj(_hp(d1, 1.06)), 2.0, hair.darkened(0.3))
		"beard":
			var pts := PackedVector2Array()
			for e in [-0.15, -0.5, -0.85]:
				for i in range(-5, 6):
					var a := deg_to_rad(i * 12.0)
					var cp := sqrt(1.0 - e * e)
					pts.append(_proj(_hp(Vector3(cos(a) * cp, sin(a) * cp, e), 1.07)))
			_hull(pts, hair, true, _depth(_hp(Vector3(1, 0, -0.5))) + fd + 0.1)
	# hair under the hat, then the hat
	match hat:
		"helmet":
			_dome(-0.1, 1.12, hat_col)
			for l in [-2.2, 0.0, 2.2]:
				var r := HEAD_R * 1.12
				var a := _hc + Vector3(-2.6, l, sqrt(maxf(r * r - 2.6 * 2.6 - l * l, 0.0)))
				var b := _hc + Vector3(2.6, l, sqrt(maxf(r * r - 2.6 * 2.6 - l * l, 0.0)))
				_line3(a, b, hat_col.lightened(0.55), 1.0, 0.1)
		"cap":
			_dome(0.05, 1.1, hat_col)
			_brim(hat_col.lightened(0.1), 5.4, 1.4, 3.0)
			_ball(_hc + Vector3(0, 0, HEAD_R * 1.1), 0.9, hat_col.lightened(0.5), 0.05)
		"chef":
			var band := PackedVector2Array()
			for p in _ring(0.25, 1.1, 12):
				band.append(_proj(p))
			for p in _ring(0.7, 1.1, 12):
				band.append(_proj(p))
			_hull(band, hat_col.darkened(0.08), true, _depth(_hc) + 0.01)
			for o in [Vector4(0, -3.4, 7.4, 3.2), Vector4(0, 3.4, 7.4, 3.2), Vector4(2.6, 0, 7.6, 3.1), Vector4(-2.6, 0, 7.6, 3.1), Vector4(0, 0, 9.6, 3.5)]:
				_ball(_hc + Vector3(o.x, o.y, o.z), o.w, hat_col)
		"beret":
			var pts := PackedVector2Array()
			var ctr := _hc + Vector3(-0.8, 1.4, 4.0)
			for e in [-0.5, 0.0, 0.7]:
				var cp := sqrt(1.0 - e * e)
				for i in 12:
					var a := TAU * i / 12.0
					pts.append(_proj(ctr + Vector3(cos(a) * cp * 6.0, sin(a) * cp * 6.0, 2.6 * e)))
			_hull(pts, hat_col, true, _depth(_hc) + 0.01)
			_ball(ctr + Vector3(-1.0, 0.5, 2.4), 1.6, hat_col.lightened(0.18), 0.02)
			_limb(ctr + Vector3(0, 0, 2.0), ctr + Vector3(0, 0, 3.8), 1.4, hat_col.darkened(0.2), 0.02)
		"visor":
			_dome(0.4, 1.0, hair)
			_band(0.4, 1.08, 1.6, hat_col)
			_brim(hat_col, 5.6, 2.0, 3.6)
		"beanie":
			_dome(-0.05, 1.14, hat_col)
			_band(0.05, 1.16, 2.4, hat_col.darkened(0.2))
			_ball(_hc + Vector3(-0.6, 0, HEAD_R * 1.1 + 1.4), 1.6, hat_col.lightened(0.4), 0.05)
		"band":
			_dome(0.45, 1.02, hair)
			_band(0.45, 1.08, 1.6, hat_col)
			var back := _hc + Vector3(-HEAD_R * 0.9, 0, HEAD_R * 0.45)
			for s in [-1.0, 1.0]:
				_limb(back, back + Vector3(-3.6, s * 1.4, -1.8 + sin(phase * 3.0) * 0.6), 1.4, hat_col)


static func _hair_back(st: Dictionary, phase: float) -> void:
	var hc: Color = st["hair_col"]
	var sway := sin(phase * 3.0) * 1.2
	var h := _hc
	match st["hair"]:
		"ponytail":
			var a := h + Vector3(-3.8, 0, 1.0)
			var b := h + Vector3(-7.4, sway * 0.6, -0.6)
			var c := h + Vector3(-10.0, sway * 1.2, -3.4)
			_limb(a, b, 2.8, hc)
			_limb(b, c, 2.4, hc)
		"long":
			for l in [-2.6, 0.0, 2.6]:
				_limb(h + Vector3(-3.2, l, 1.2), h + Vector3(-5.6, l * 1.1, -3.0), 3.4, hc)
				_limb(h + Vector3(-5.6, l * 1.1, -3.0), h + Vector3(-7.4, l * 1.2 + sway * 0.5, -8.4), 3.0, hc)
		"dreads":
			for k in 3:
				var l := -2.4 + k * 2.4
				var base := h + Vector3(-3.4, l, 1.4)
				var mid := h + Vector3(-6.4, l + sway * 0.4, -0.4)
				var tip := h + Vector3(-7.8, l + sway * 0.8, -4.4)
				_limb(base, mid, 2.2, hc.lightened(0.1 * k))
				_limb(mid, tip, 2.0, hc.lightened(0.1 * k))
		"bun":
			_ball(h + Vector3(-1.8, 0, 5.6), 2.5, hc)


static func _pizza_box(ctr: Vector3) -> void:
	var half := Vector3(5.2, 5.2, 1.6)
	var d := _depth(ctr)
	var k := 0
	# the four sides, only those facing the camera
	for face in [[Vector3(1, 0, 0), 0.3], [Vector3(-1, 0, 0), 0.3], [Vector3(0, 1, 0), 0.18], [Vector3(0, -1, 0), 0.18]]:
		var n: Vector3 = face[0]
		if n.dot(_cam) <= 0.0:
			continue
		var along_x := n.x != 0.0
		var t := Vector3(0, 1, 0) if along_x else Vector3(1, 0, 0)
		var hn := half.x if along_x else half.y
		var ht := half.y if along_x else half.x
		var pts := PackedVector2Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
			pts.append(_proj(ctr + n * hn + t * (ht * corner.x) + Vector3(0, 0, half.z * corner.y)))
		_push(d + k * 0.0002, POLY, pts, true, 0.0, Color(0.9, 0.86, 0.76).darkened(face[1]))
		k += 1
	var top := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		top.append(_proj(ctr + Vector3(corner.x * half.x, corner.y * half.y, half.z)))
	_push(d + k * 0.0002, POLY, top, true, 0.0, Color(0.98, 0.96, 0.9))
	_push(d + (k + 1) * 0.0002, BALL, _proj(ctr + Vector3(0, 0, half.z)), 1.6, false, Color(0.9, 0.2, 0.2))


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
