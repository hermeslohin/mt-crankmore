class_name Sprites
extends RefCounted
## Optional pixel-art sprites. Anything without art keeps its procedural drawing, so art can be added one piece at
## a time. Sheets are looked up in user://art/ first (drop-in testing, mods), then res://art/.
##
## Bike sheets (rider + bike), e.g. art/bike.png:
##   * Columns = pedal frames (4 in the templates: cranks at 0, 90, 180, 270 degrees; any number works, a single
##     column is a still), 8 rows = directions of travel:
##     down-right, down, down-left, left, up-left, up, up-right, right (the first is world +x, then turning 45 degrees
##     at a time; in the isometric view the diagonals are the ones you see on the roads).
##   * Frames are square, sheet height / 8 on a side. The wheels touch the ground at the bottom
##     centre of the frame, ANCHOR_UP pixels above its bottom edge. Drawn 1:1: one sprite pixel = one world pixel.
##   * Optional layers on the same grid, drawn on top in this order: <name>_frame.png and <name>_jersey.png are
##     greyscale and get tinted with the bike's frame colour / the rider's jersey colour (so one sheet serves every
##     rival), and <name>_box.png is the delivery box, shown only while carrying a pizza.
##   * bike_<rider>.png (bike_you, bike_dave, bike_sam, ...) replaces bike.png for that rider.
##   * Whole-rider looks instead of the _box layer: <name>_boxed.png rides around town with the (empty) delivery box,
##     <name>_pizza.png is carrying a pizza, and <name>.png itself (no box) is the race look. A missing look falls back
##     to _boxed, then to <name>.png. tools/import_rider.gd builds these from a PixelLab character export.
## PIZZA_DEBUG=bake_bike writes the current procedural bike in this format to art/templates/, to paint over.

const FRAMES := 4       # pedal frames in the baked templates
const DIRS := 8
const ANCHOR_UP := 12    # room below the contact point for the near wheel in the diagonal views

static var enabled := true
static var baking := false     # PIZZA_DEBUG=bake_bike is drawing the procedural bike into a template
static var _cache := {}


## The texture for a sheet name ("bike", "bike_jersey", ...), or null if there is no such art.
static func sheet(sheet_name: String) -> Texture2D:
	if _cache.has(sheet_name):
		return _cache[sheet_name]
	var tex: Texture2D = null
	for dir in ["user://art/", "res://art/"]:
		var path: String = dir + sheet_name + ".png"
		if dir == "res://art/" and ResourceLoader.exists(path):
			tex = load(path)   # imported by Godot (exported builds, or after the editor has seen the file)
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			break
	_cache[sheet_name] = tex
	return tex


## Forget loaded art (after new files were dropped in).
static func reload() -> void:
	_cache.clear()


## The row for a world heading (unit vector, world tiles).
static func dir_row(w: Vector2) -> int:
	return posmod(roundi(w.angle() / (PI / 4.0)), DIRS)


## Draws rider + bike from a sheet if there is one. Returns false (drawing nothing) when there's no art, so the
## caller falls back to the procedural bike. `c` = ground contact on screen, `w` = world heading. `boxed`: riding
## around town with the delivery box (off in races).
static func draw_bike(ci: CanvasItem, c: Vector2, w: Vector2, frame_col: Color, shirt: Color, phase: float, has_pizza: bool, who: String, boxed := true) -> bool:
	if not enabled or baking:
		return false
	var base_name := "bike_" + who.to_lower()
	if sheet(base_name) == null:
		base_name = "bike"
	var base := sheet(base_name)
	if base == null:
		return false
	var look := ""   # a whole-rider look replaces the base sheet and the _box layer
	for suffix in (["_pizza", "_boxed"] if has_pizza else (["_boxed"] if boxed else [])):
		if sheet(base_name + suffix) != null:
			look = suffix
			break
	if look != "":
		base = sheet(base_name + look)
	var fh := base.get_height() / DIRS
	var fw := fh
	var frames := maxi(1, base.get_width() / fw)
	var col := posmod(int(floorf(phase / TAU * frames)), frames)
	var src := Rect2(col * fw, dir_row(w) * fh, fw, fh)
	var dst := Rect2((c - Vector2(fw * 0.5, fh - ANCHOR_UP)).round(), Vector2(fw, fh))
	ci.draw_texture_rect_region(base, dst, src)
	for layer in ([] if look != "" else [["_frame", frame_col], ["_jersey", shirt]]):
		var t := sheet(base_name + layer[0])
		if t != null:
			ci.draw_texture_rect_region(t, dst, src, layer[1])
	if has_pizza and look == "":
		var box := sheet(base_name + "_box")
		if box != null:
			ci.draw_texture_rect_region(box, dst, src)
	return true
