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


## Forget loaded art (after new files were dropped in).
static func reload() -> void:
	_cache.clear()


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
		tex = sheet(base + suffix)
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
