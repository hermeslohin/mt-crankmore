class_name Ground
extends RefCounted
## Textured ground for the town and the mountain: seamless 16-bit pixel-art textures (art/ground_<name>.png, from
## PixelLab, see sprites/ground/) mapped in screen space, so their pixels stay square and crisp whatever the slope.
## Each patch of ground is tinted by a light level that comes in a few hard steps (no smooth gradients: the SNES look),
## so a slope reads as bands of lighter and darker ground and you can see the grade at a glance. Without the texture
## a patch is drawn in its plain colour.

const STEPS := 7                 # light levels
const LO := 0.68                 # darkest and brightest light level
const HI := 1.22
const UV_SCALE := 1.0            # texture pixels per screen pixel

## Textures that are made brighter or darker than mid-tone get their light scaled, so slopes still show on them.
const GAIN := {"snow": 0.86, "sand": 0.92, "sidewalk": 0.94}

static var _tex := {}


## The texture for a ground kind ("grass_meadow", "asphalt", ...), or null.
static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = Sprites.sheet("ground_" + name)
	return _tex[name]


static func reload() -> void:
	_tex.clear()


## A light level (1 = flat ground in plain light) snapped to one of the STEPS bands.
static func band(light: float) -> float:
	var u := clampf((light - LO) / (HI - LO), 0.0, 1.0)
	return lerpf(LO, HI, roundf(u * (STEPS - 1)) / (STEPS - 1))


## Fills the screen-space polygon `pts` with ground `name`, lit by `light` (already banded, or pass band(x)) and
## multiplied by `tint`. `fallback` is the colour used when there is no texture.
static func fill(ci: CanvasItem, pts: PackedVector2Array, name: String, light: float, fallback: Color, tint := Color.WHITE) -> void:
	var t := tex(name)
	if t == null:
		ci.draw_colored_polygon(pts, Iso.shade(fallback, light) * tint)
		return
	light *= float(GAIN.get(name, 1.0))
	var c := Color(light * tint.r, light * tint.g, light * tint.b, tint.a)
	var sz := t.get_size() * UV_SCALE
	var uvs := PackedVector2Array()
	uvs.resize(pts.size())
	for i in pts.size():
		uvs[i] = pts[i] / sz
	ci.draw_polygon(pts, PackedColorArray([c]), uvs, t)


## The same for a four-cornered patch that may fold over on a steep slope (draw_polygon would need to triangulate it).
static func quad(ci: CanvasItem, pts: PackedVector2Array, name: String, light: float, fallback: Color, tint := Color.WHITE) -> void:
	var t := tex(name)
	if t == null:
		ci.draw_primitive(pts, PackedColorArray([Iso.shade(fallback, light) * tint]), PackedVector2Array())
		return
	light *= float(GAIN.get(name, 1.0))
	var c := Color(light * tint.r, light * tint.g, light * tint.b, tint.a)
	var sz := t.get_size() * UV_SCALE
	var uvs := PackedVector2Array([pts[0] / sz, pts[1] / sz, pts[2] / sz, pts[3] / sz])
	ci.draw_primitive(pts, PackedColorArray([c, c, c, c]), uvs, t)
