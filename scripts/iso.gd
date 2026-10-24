class_name Iso
extends RefCounted
## Isometric helpers. World units are tiles; +x runs down-right on screen, +y down-left.
## Everything is drawn flat-shaded with dark pixel outlines for a 16-bit look.

const TW := 64.0
const TH := 32.0
const OUTLINE := Color(0.1, 0.08, 0.16)

## Alpha multiplier for the shape helpers; lowered while drawing a building that hides the player.
static var fade := 1.0


## Optional terrain (the town's hills). While `terrain_on`, to_screen lifts every point by the ground height
## (screen px, bilinear over a grid of tile corners), so ground, roads and everything on them follow the hills.
## Setting `hold_on` pins the lift to `hold_z` instead: a building or tree then stands level instead of tilting.
static var terrain_on := false
static var hold_on := false
static var hold_z := 0.0
static var hgrid := PackedFloat32Array()
static var hgrid_o := 0       # world coordinate of grid column / row 0
static var hgrid_n := 0       # grid points per side


static func ground_z(p: Vector2) -> float:
	if hgrid_n == 0:
		return 0.0
	var fx := clampf(p.x - hgrid_o, 0.0, hgrid_n - 1.001)
	var fy := clampf(p.y - hgrid_o, 0.0, hgrid_n - 1.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var i := iy * hgrid_n + ix
	return lerpf(lerpf(hgrid[i], hgrid[i + 1], tx), lerpf(hgrid[i + hgrid_n], hgrid[i + hgrid_n + 1], tx), ty)


static func to_screen(p: Vector2, z: float = 0.0) -> Vector2:
	if terrain_on:
		z += hold_z if hold_on else ground_z(p)
	return Vector2((p.x - p.y) * TW * 0.5, (p.x + p.y) * TH * 0.5 - z)


## Lifts everything drawn in `fn` by a fixed ground height `z` (level, not following the slope).
static func held(z: float, fn: Callable) -> void:
	if not terrain_on:
		fn.call()
		return
	hold_z = z
	hold_on = true
	fn.call()
	hold_on = false


static func to_world(s: Vector2) -> Vector2:
	var a := s.x / (TW * 0.5)
	var b := s.y / (TH * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


static func fa(c: Color, f: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * f)


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func diamond(ci: CanvasItem, tile: Vector2, col: Color, z: float = 0.0, size: Vector2 = Vector2.ONE) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		to_screen(tile, z), to_screen(tile + Vector2(size.x, 0), z), to_screen(tile + size, z), to_screen(tile + Vector2(0, size.y), z),
	]), col)


static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, outline: bool = true) -> void:
	ci.draw_colored_polygon(pts, fa(col, fade))
	if outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, fa(OUTLINE, fade), 1.0)


## Axis-aligned box: light top, mid +y face (lower-left), dark +x face (lower-right), outlined.
static func box(ci: CanvasItem, pos: Vector2, size: Vector2, h: float, col: Color, z0: float = 0.0, roof: Color = Color(0, 0, 0, 0), outline: bool = true) -> void:
	var a := pos
	var b := pos + Vector2(size.x, 0)
	var c := pos + size
	var d := pos + Vector2(0, size.y)
	var f := fade
	var top := roof if roof.a > 0.0 else shade(col, 1.12)
	ci.draw_colored_polygon(PackedVector2Array([to_screen(b, z0), to_screen(c, z0), to_screen(c, z0 + h), to_screen(b, z0 + h)]), fa(shade(col, 0.7), f))
	ci.draw_colored_polygon(PackedVector2Array([to_screen(c, z0), to_screen(d, z0), to_screen(d, z0 + h), to_screen(c, z0 + h)]), fa(shade(col, 0.88), f))
	ci.draw_colored_polygon(PackedVector2Array([to_screen(a, z0 + h), to_screen(b, z0 + h), to_screen(c, z0 + h), to_screen(d, z0 + h)]), fa(top, f))
	if h > 6.0:
		# dark "ambient occlusion" band at the foot of the walls
		ci.draw_colored_polygon(PackedVector2Array([to_screen(b, z0), to_screen(c, z0), to_screen(c, z0 + 2.0), to_screen(b, z0 + 2.0)]), fa(shade(col, 0.5), f))
		ci.draw_colored_polygon(PackedVector2Array([to_screen(c, z0), to_screen(d, z0), to_screen(d, z0 + 2.0), to_screen(c, z0 + 2.0)]), fa(shade(col, 0.62), f))
	if h > 4.0:
		# light catching the top edges of the walls
		ci.draw_line(to_screen(b, z0 + h - 1.5), to_screen(c, z0 + h - 1.5), fa(shade(col, 0.95), f), 1.0)
		ci.draw_line(to_screen(c, z0 + h - 1.5), to_screen(d, z0 + h - 1.5), fa(shade(col, 1.1), f), 1.0)
	if outline:
		var o := fa(OUTLINE, f)
		var at := to_screen(a, z0 + h)
		var bt := to_screen(b, z0 + h)
		var ct := to_screen(c, z0 + h)
		var dt := to_screen(d, z0 + h)
		ci.draw_polyline(PackedVector2Array([at, bt, to_screen(b, z0), to_screen(c, z0), to_screen(d, z0), dt, at]), o, 1.0)
		ci.draw_polyline(PackedVector2Array([bt, ct, dt]), o, 1.0)
		ci.draw_line(to_screen(c, z0), ct, o, 1.0)


## Pitched roof sitting at height z0 over a footprint. ridge_x: ridge runs along x.
static func gable(ci: CanvasItem, pos: Vector2, size: Vector2, z0: float, rh: float, col: Color, wall: Color, ridge_x: bool, overhang: float = 0.15) -> void:
	var p := pos - Vector2(overhang, overhang)
	var s := size + Vector2(overhang, overhang) * 2.0
	var x0 := p.x
	var y0 := p.y
	var x1 := p.x + s.x
	var y1 := p.y + s.y
	var back: PackedVector2Array
	var front: PackedVector2Array
	var gab: PackedVector2Array
	var ridge_a: Vector2
	var ridge_b: Vector2
	var eave_a: Vector2
	var eave_b: Vector2
	if ridge_x:
		var ym := (y0 + y1) * 0.5
		back = PackedVector2Array([to_screen(Vector2(x0, y0), z0), to_screen(Vector2(x1, y0), z0), to_screen(Vector2(x1, ym), z0 + rh), to_screen(Vector2(x0, ym), z0 + rh)])
		front = PackedVector2Array([to_screen(Vector2(x0, ym), z0 + rh), to_screen(Vector2(x1, ym), z0 + rh), to_screen(Vector2(x1, y1), z0), to_screen(Vector2(x0, y1), z0)])
		gab = PackedVector2Array([to_screen(Vector2(x1 - overhang, y0 + overhang), z0), to_screen(Vector2(x1 - overhang, y1 - overhang), z0), to_screen(Vector2(x1 - overhang, ym), z0 + rh - 2.0)])
		ridge_a = Vector2(x0, ym)
		ridge_b = Vector2(x1, ym)
		eave_a = Vector2(x0, y1)
		eave_b = Vector2(x1, y1)
	else:
		var xm := (x0 + x1) * 0.5
		back = PackedVector2Array([to_screen(Vector2(x0, y0), z0), to_screen(Vector2(x0, y1), z0), to_screen(Vector2(xm, y1), z0 + rh), to_screen(Vector2(xm, y0), z0 + rh)])
		front = PackedVector2Array([to_screen(Vector2(xm, y0), z0 + rh), to_screen(Vector2(xm, y1), z0 + rh), to_screen(Vector2(x1, y1), z0), to_screen(Vector2(x1, y0), z0)])
		gab = PackedVector2Array([to_screen(Vector2(x0 + overhang, y1 - overhang), z0), to_screen(Vector2(x1 - overhang, y1 - overhang), z0), to_screen(Vector2(xm, y1 - overhang), z0 + rh - 2.0)])
		ridge_a = Vector2(xm, y0)
		ridge_b = Vector2(xm, y1)
		eave_a = Vector2(x1, y0)
		eave_b = Vector2(x1, y1)
	poly(ci, back, shade(col, 1.18))
	poly(ci, gab, shade(wall, 0.8))
	poly(ci, front, shade(col, 0.92))
	# staggered shingle rows on the front slope + a light ridge cap
	var rows := 5
	var along := ridge_a.distance_to(ridge_b)
	var ticks := maxi(2, int(along * 2.5))
	for k in range(1, rows + 1):
		var t := k / float(rows + 1)
		var za := z0 + rh * (1.0 - t)
		var ra := ridge_a.lerp(eave_a, t)
		var rb := ridge_b.lerp(eave_b, t)
		ci.draw_line(to_screen(ra, za), to_screen(rb, za), fa(shade(col, 0.7), fade), 1.0)
		var t_prev := (k - 1) / float(rows + 1)
		var zp := z0 + rh * (1.0 - t_prev)
		for m in ticks:
			var f := (m + (0.5 if k % 2 == 0 else 0.0)) / float(ticks)
			if f >= 1.0:
				continue
			ci.draw_line(to_screen(ra.lerp(rb, f), za), to_screen(ridge_a.lerp(eave_a, t_prev).lerp(ridge_b.lerp(eave_b, t_prev), f), zp), fa(shade(col, 0.78), fade), 1.0)
	ci.draw_line(to_screen(ridge_a, z0 + rh), to_screen(ridge_b, z0 + rh), fa(shade(col, 1.45), fade), 2.0)


## Oriented box (cars). fwd is a unit world vector.
static func obox(ci: CanvasItem, center: Vector2, fwd: Vector2, hl: float, hw: float, h: float, col: Color, z0: float = 0.0, top: Color = Color(0, 0, 0, 0)) -> void:
	var r := Vector2(-fwd.y, fwd.x)
	var cs := [center + fwd * hl + r * hw, center - fwd * hl + r * hw, center - fwd * hl - r * hw, center + fwd * hl - r * hw]
	for i in 4:
		var a: Vector2 = cs[i]
		var b: Vector2 = cs[(i + 1) % 4]
		var nrm := ((a + b) * 0.5 - center).normalized()
		if nrm.x + nrm.y > 0.08:  # skip faces seen edge-on (zero-area on screen)
			var sh := lerpf(0.7, 0.88, clampf((nrm.y - nrm.x + 1.0) * 0.5, 0.0, 1.0))
			poly(ci, PackedVector2Array([to_screen(a, z0), to_screen(b, z0), to_screen(b, z0 + h), to_screen(a, z0 + h)]), shade(col, sh))
	var tp := PackedVector2Array()
	for c in cs:
		tp.append(to_screen(c, z0 + h))
	poly(ci, tp, top if top.a > 0.0 else shade(col, 1.12))


## Window grid on the two visible faces of a box.
static func windows(ci: CanvasItem, pos: Vector2, size: Vector2, h: float, lit: Color, z0: float = 0.0, start: float = 6.0) -> void:
	var rows := int((h - start - 2.0) / 13.0)
	if rows <= 0:
		return
	var c := pos + size
	for face in 2:
		var from_p := Vector2(pos.x, c.y) if face == 0 else c
		var to_p := c if face == 0 else Vector2(c.x, pos.y)
		var cols := int(from_p.distance_to(to_p) * 1.5)
		var f := 0.88 if face == 0 else 0.7
		for ci_ in cols:
			var p0 := from_p.lerp(to_p, (ci_ + 0.28) / float(cols))
			var p1 := from_p.lerp(to_p, (ci_ + 0.72) / float(cols))
			for r in rows:
				var zz := z0 + start + r * 13.0
				var on := ((ci_ * 7 + r * 3 + int(pos.x * 5.0 + pos.y * 3.0)) % 5) != 0
				var col := shade(lit, f) if on else shade(Color(0.25, 0.35, 0.55), f)
				var q := PackedVector2Array([to_screen(p0, zz), to_screen(p1, zz), to_screen(p1, zz + 7.0), to_screen(p0, zz + 7.0)])
				ci.draw_colored_polygon(q, fa(col, fade))
				# upper pane catches the light
				ci.draw_colored_polygon(PackedVector2Array([to_screen(p0, zz + 4.5), to_screen(p1, zz + 4.5), to_screen(p1, zz + 7.0), to_screen(p0, zz + 7.0)]), fa(shade(col, 1.15), fade))
				q.append(q[0])
				var frame := fa(shade(Color(0.3, 0.22, 0.2), f), fade)
				ci.draw_polyline(q, frame, 1.0)
				var pm := p0.lerp(p1, 0.5)
				ci.draw_line(to_screen(pm, zz), to_screen(pm, zz + 7.0), frame, 1.0)
				# sill
				ci.draw_line(to_screen(p0.lerp(p1, -0.1), zz - 0.5), to_screen(p0.lerp(p1, 1.1), zz - 0.5), fa(shade(Color(0.95, 0.93, 0.88), f), fade), 1.5)
