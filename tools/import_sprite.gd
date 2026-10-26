extends SceneTree
## Packs single sprites (not riders: see import_rider.gd) from PixelLab exports into the sheets Sprites reads.
##
##   godot --headless -s tools/import_sprite.gd -- strip <dir> <direction> <anim> <out name> [anchor=feet|center]
##     One row of animation frames for one direction, e.g. a baker's dance: <dir> holds animations/<anim>/<direction>/
##     frame_NNN.png (and rotations/<direction>.png, which sets where the feet are). anchor=feet puts the feet at the
##     bottom centre of each frame (people), anchor=center the middle of the sprite at the frame's middle (a spinning
##     pizza). Output: art/<out name>.png, frames side by side, square.
##   godot --headless -s tools/import_sprite.gd -- people <dir> <anim|still> <out name>
##     8 rows (the rider row order: down-right, down, down-left, left, up-left, up, up-right, right), feet at the bottom
##     centre of each frame: a person walking in every direction. <dir> holds rotations/ and animations/<anim>/<direction>/;
##     "still" packs just the rotations (one column), for a pose that doesn't animate (a skier).
##   godot --headless -s tools/import_sprite.gd -- rotations <dir> <out name>
##     8 rows, one per direction of travel (the same row order as the rider sheets), one still each, centred in the
##     frame: for vehicles. <dir> holds rotations/<direction>.png.

const ROW_DIRS := ["south-east", "south", "south-west", "west", "north-west", "north", "north-east", "east"]
const FEET_MARGIN := 4   # pixels below the feet in a "feet" frame


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out_dir := ProjectSettings.globalize_path("res://art")
	if a.size() >= 5 and a[0] == "strip":
		_strip(a[1], a[2], a[3], "%s/%s.png" % [out_dir, a[4]], a.size() > 5 and a[5] == "anchor=center")
	elif a.size() >= 4 and a[0] == "people":
		_people(a[1], a[2], "%s/%s.png" % [out_dir, a[3]])
	elif a.size() >= 3 and a[0] == "rotations":
		_rotations(a[1], "%s/%s.png" % [out_dir, a[2]])
	else:
		printerr("usage: see the top of tools/import_sprite.gd")
		quit(1)
		return
	quit()


func _strip(dir: String, direction: String, anim: String, out: String, center: bool) -> void:
	var folder := "%s/animations/%s/%s" % [dir, anim, direction]
	var files := Array(DirAccess.get_files_at(folder)).filter(func(f): return f.ends_with(".png"))
	files.sort()
	if files.is_empty():
		printerr("no frames in ", folder)
		return
	var frames: Array[Image] = []
	var size := 0
	for f in files:
		var img := _load("%s/%s" % [folder, f])
		frames.append(img)
		size = maxi(size, maxi(img.get_width(), img.get_height()))
	size += 2 * FEET_MARGIN
	var sheet := Image.create(size * frames.size(), size, false, Image.FORMAT_RGBA8)
	# line every frame up with the first one, which is placed by the still's feet (or the middle of the sprite)
	var still := _load("%s/rotations/%s.png" % [dir, direction])
	var first_rect := frames[0].get_used_rect()
	var ref := still.get_used_rect() if still != null else first_rect
	var anchor_x := ref.position.x + ref.size.x / 2
	var anchor_y := (ref.position.y + ref.size.y / 2) if center else ref.end.y
	var shift := Vector2i(size / 2 - anchor_x, (size / 2 if center else size - FEET_MARGIN) - anchor_y)
	for i in frames.size():
		var off := shift + ref.position - first_rect.position if still != null else shift
		sheet.blend_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(i * size, 0) + off)
	print("%s: %d frame(s) of %d px" % [out, frames.size(), size])
	sheet.save_png(out)


func _people(dir: String, anim: String, out: String) -> void:
	var rows: Array = []   # per row: the frames
	var size := 0
	for d in ROW_DIRS:
		var frames: Array[Image] = []
		if anim == "still":
			frames.append(_load("%s/rotations/%s.png" % [dir, d]))
		else:
			var folder := "%s/animations/%s/%s" % [dir, anim, d]
			var files := Array(DirAccess.get_files_at(folder)).filter(func(f): return f.ends_with(".png"))
			files.sort()
			for f in files:
				frames.append(_load("%s/%s" % [folder, f]))
		if frames.is_empty() or frames[0] == null:
			printerr("missing frames for ", d)
			return
		rows.append(frames)
		for img in frames:
			size = maxi(size, maxi(img.get_width(), img.get_height()))
	size += 2 * FEET_MARGIN
	var cols: int = rows[0].size()
	var sheet := Image.create(size * cols, size * rows.size(), false, Image.FORMAT_RGBA8)
	for row in rows.size():
		var frames: Array = rows[row]
		var still := _load("%s/rotations/%s.png" % [dir, ROW_DIRS[row]])
		var first_rect: Rect2i = frames[0].get_used_rect()
		var ref: Rect2i = still.get_used_rect() if still != null else first_rect
		var shift := Vector2i(size / 2 - (ref.position.x + ref.size.x / 2), size - FEET_MARGIN - ref.end.y)
		for i in mini(frames.size(), cols):
			var off: Vector2i = shift + ref.position - first_rect.position if still != null and anim != "still" else shift
			sheet.blend_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(i * size, row * size) + off)
	print("%s: %d frame(s) x 8 directions of %d px" % [out, cols, size])
	sheet.save_png(out)


func _rotations(dir: String, out: String) -> void:
	var imgs: Array[Image] = []
	var size := 0
	for d in ROW_DIRS:
		var img := _load("%s/rotations/%s.png" % [dir, d])
		if img == null:
			printerr("missing rotations/", d, ".png")
			return
		imgs.append(img)
		size = maxi(size, maxi(img.get_width(), img.get_height()))
	var sheet := Image.create(size, size * ROW_DIRS.size(), false, Image.FORMAT_RGBA8)
	for row in imgs.size():
		var r := imgs[row].get_used_rect()
		var off := Vector2i(size / 2 - (r.position.x + r.size.x / 2), row * size + size / 2 - (r.position.y + r.size.y / 2))
		sheet.blend_rect(imgs[row], Rect2i(Vector2i.ZERO, imgs[row].get_size()), off)
	print("%s: 8 directions of %d px" % [out, size])
	sheet.save_png(out)


func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	img.convert(Image.FORMAT_RGBA8)
	return img
