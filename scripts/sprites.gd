class_name Sprites
extends RefCounted
## Rider sprite sheets, from the PixelLab characters in sprites/ (packed with tools/import_rider.gd). Sheets are looked
## up in user://art/ first (drop-in testing, mods), then res://art/.
##
## One rider = a set of sheets named after them: bike_<rider>.png ("bike_carla", "bike_rookie_girl", ...; the player
## is bike_rookie_boy or bike_rookie_girl, see player_sheet).
##   * Columns = animation frames, 8 rows = directions of travel:
##     down-right, down, down-left, left, up-left, up, up-right, right (the first is world +x, then turning 45 degrees
##     at a time; in the isometric view the diagonals are the ones you see on the roads).
##   * Frames are square, sheet height / 8 on a side. The wheels touch the ground at the bottom centre of the frame,
##     ANCHOR_UP pixels above its bottom edge. Drawn 1:1: one sprite pixel = one world pixel.
##   * Three looks: bike_<rider>_pizza.png is carrying a pizza, bike_<rider>_boxed.png rides around town with the
##     (empty) delivery bag and bike_<rider>.png (no bag) is the race look. A missing look falls back to the next.
##   * The wipe-out is the same three looks with _fall in the name (bike_<rider>_fall_pizza.png, _fall_boxed.png,
##     bike_<rider>_fall.png): frame 0 is the riding pose, then the rider tips over and ends up on the ground.

const DIRS := 8
const ANCHOR_UP := 12    # room below the contact point for the near wheel in the diagonal views
const FALL_FPS := 10.0   # fall frames per second; the last frame is held while the rider lies there
const STRIP_FEET_MARGIN := 4.0   # pixels below the feet in a strip frame (see tools/import_sprite.gd)
const VEHICLE_LIFT := 4.0        # a vehicle sprite's middle sits this far above its spot on the ground

## Every pedestrian design there may be art for (art/ped_<design>_walk.png and _cheer.png): the townsfolk, spectators
## and joggers. pedestrians() lists the ones that are actually there.
const PEDESTRIAN_DESIGNS := ["kid", "jogger", "tourist", "hiker", "grandpa", "lady", "surfer", "artist", "skater_kid", "businesswoman", "doctor", "musician", "baker", "cyclist_fan", "photographer", "mailman", "nurse", "dogwalker", "busker", "scout"]
static var _peds: Array = []


static func pedestrians() -> Array:
	if _peds.is_empty():
		_peds = PEDESTRIAN_DESIGNS.filter(func(d): return sheet("ped_%s_walk" % d) != null and sheet("ped_%s_cheer" % d) != null)
		if _peds.is_empty():
			_peds = ["kid"]
	return _peds


## True in cold weather (see Season.cold): characters then use their winter sheets (art/winter_<name>.png: hat, gloves
## and a jacket) when there is one.
static var cold := false

## Which character the player rides as: "rookie_boy" or "rookie_girl" (Game sets it).
static var player_sheet := "rookie_boy"

static var _cache := {}


## The texture for a sheet name ("bike_carla", ...), or null if there is no such art.
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


## The sheet for a person or rider: the winter version in cold weather if there is one, else the usual one.
static func outfit(sheet_name: String) -> Texture2D:
	if cold:
		var w := sheet("winter_" + sheet_name)
		if w != null:
			return w
	return sheet(sheet_name)


## Forget loaded art (after new files were dropped in).
static func reload() -> void:
	_cache.clear()
	_peds = []


## The row for a world heading (unit vector, world tiles).
static func dir_row(w: Vector2) -> int:
	return posmod(roundi(w.angle() / (PI / 4.0)), DIRS)


## The sheet name for a rider: "YOU" is the player's chosen character, anyone else their short name ("Carla").
static func sheet_name(who: String) -> String:
	return "bike_" + (player_sheet if who == "YOU" else who.to_lower())


## Draws the rider + bike. `c` = ground contact on screen, `w` = world heading. `boxed`: riding around town with the
## delivery bag (off in races). `fall_t` >= 0 plays the wipe-out, that many seconds in. Returns false (drawing
## nothing) when there is no art for this rider.
static func draw_rider(ci: CanvasItem, c: Vector2, w: Vector2, phase: float, has_pizza: bool, who: String, boxed := true, fall_t := -1.0) -> bool:
	var falling := fall_t >= 0.0
	var base := sheet_name(who) + ("_fall" if falling else "")
	var tex: Texture2D = null
	for suffix in (["_pizza", "_boxed", ""] if has_pizza else (["_boxed", ""] if boxed else [""])):
		tex = outfit(base + suffix)
		if tex != null:
			break
	if tex == null:
		return false
	var fh := tex.get_height() / DIRS
	var fw := fh
	var frames := maxi(1, tex.get_width() / fw)
	var col := clampi(int(fall_t * FALL_FPS), 0, frames - 1) if falling else posmod(int(floorf(phase / TAU * frames)), frames)
	var src := Rect2(col * fw, dir_row(w) * fh, fw, fh)
	var dst := Rect2((c - Vector2(fw * 0.5, fh - ANCHOR_UP)).round(), Vector2(fw, fh))
	ci.draw_texture_rect_region(tex, dst, src)
	return true


## An animation row (art/<name>.png, square frames side by side) drawn at the screen point `at`: standing on it with
## their feet there (`feet`, people and animals) or centred on it (a spinning pizza), mirrored left to right when `flip`,
## multiplied by `tint`. `t` is in seconds. Returns false when there is no such art.
static func draw_strip(ci: CanvasItem, name: String, at: Vector2, t: float, fps := 10.0, feet := true, flip := false, tint := Color.WHITE) -> bool:
	var tex := outfit(name)
	if tex == null:
		return false
	var fh := tex.get_height()
	var frames := maxi(1, tex.get_width() / fh)
	var src := Rect2(posmod(int(t * fps), frames) * fh, 0, fh, fh)
	var tl := (at - Vector2(fh * 0.5, fh - STRIP_FEET_MARGIN if feet else fh * 0.5)).round()
	var dst := Rect2(tl + Vector2(fh, 0), Vector2(-fh, fh)) if flip else Rect2(tl, Vector2(fh, fh))
	ci.draw_texture_rect_region(tex, dst, src, tint)
	return true


## A vehicle (art/<name>.png: 8 square rows, one per direction of travel as in the rider sheets) with its middle on `at`,
## heading `w` (world direction), tinted by `tint`.
static func draw_vehicle(ci: CanvasItem, name: String, at: Vector2, w: Vector2, tint := Color.WHITE) -> bool:
	var tex := sheet(name)
	if tex == null:
		return false
	var f := tex.get_height() / DIRS
	var src := Rect2(0, dir_row(w) * f, f, f)
	var dst := Rect2((at - Vector2(f * 0.5, f * 0.5 + VEHICLE_LIFT)).round(), Vector2(f, f))
	ci.draw_texture_rect_region(tex, dst, src, tint)
	return true


## A person (art/<name>.png: 8 square rows of directions as in the rider sheets, frames across; see
## tools/import_sprite.gd people) standing with their feet on `at`, walking towards the world direction `w`. `t` is in
## seconds.
static func draw_person(ci: CanvasItem, name: String, at: Vector2, w: Vector2, t: float, fps := 8.0, tint := Color.WHITE) -> bool:
	var tex := outfit(name)
	if tex == null:
		return false
	var f := tex.get_height() / DIRS
	var frames := maxi(1, tex.get_width() / f)
	var src := Rect2(posmod(int(t * fps), frames) * f, dir_row(w) * f, f, f)
	ci.draw_texture_rect_region(tex, Rect2((at - Vector2(f * 0.5, f - STRIP_FEET_MARGIN)).round(), Vector2(f, f)), src, tint)
	return true


## A single picture (art/<name>.png) with the middle of its bottom edge on `at`, optionally mirrored left to right,
## scaled by `scale` and faded to `alpha`. Returns false when there is none.
static func draw_image(ci: CanvasItem, name: String, at: Vector2, flip := false, alpha := 1.0, scale := 1.0) -> bool:
	var tex := sheet(name)
	if tex == null:
		return false
	var w := float(tex.get_width()) * scale
	var h := float(tex.get_height()) * scale
	var top_left := (at - Vector2(w * 0.5, h)).round()
	var rect := Rect2(top_left + Vector2(w, 0.0), Vector2(-w, h)) if flip else Rect2(top_left, Vector2(w, h))
	ci.draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))
	return true
