extends SceneTree
## Packs a PixelLab-style character export (one folder per look, each with rotations/<dir>.png and optionally
## animations/<name>/<dir>/frame_NNN.png) into the bike sheets Sprites reads (see scripts/sprites.gd).
##
##   godot --headless -s tools/import_rider.gd -- <export dir> [rows=<dir>,...] <folder>=<sheet> [<folder>=<sheet> ...]
##   e.g. ... -- ~/Downloads/rookie rows=south-east,south,west,north-west,north-west,north-east,east,east \
##            Idle=bike_you_pizza same_thing_but_witho=bike_you
##
## A folder with an animation becomes one column per frame; without one, its still is a single column. Exports don't
## agree on where their direction names point on screen, and their 8 poses needn't line up with the sheet's 8 rows
## (the isometric road diagonals are shallow), so rows= picks the export direction to use for each row, in row
## order; a pose can serve two rows. Look at the rotations to choose. The default suits the first rider export.
## Every frame is lined up so the bike's ground contact sits at the bottom centre, Sprites.ANCHOR_UP above the edge.

const FRAME := 80             # output frame size (square)
const ANCHOR_UP := 12         # keep in step with Sprites.ANCHOR_UP
## Export direction for each sheet row: down-right, down, down-left, left, up-left, up, up-right, right.
const ROW_DIRS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
## Pixels from the lowest pixel up to the ground contact per row: the near wheel hangs below it when the bike
## points at or away from the camera, less on the diagonals, hardly at all side-on.
const CONTACT_UP := [5, 9, 5, 1, 5, 9, 5, 1]

var row_dirs: Array[String] = []   # export direction for each sheet row


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: godot --headless -s tools/import_rider.gd -- <export dir> <folder>=<sheet> ...")
		quit(1)
		return
	var src := args[0].trim_suffix("/")
	row_dirs.assign(ROW_DIRS)
	var pairs := args.slice(1)
	if pairs.size() > 0 and pairs[0].begins_with("rows="):
		row_dirs.assign(pairs[0].trim_prefix("rows=").split(","))
		pairs = pairs.slice(1)
	if row_dirs.size() != ROW_DIRS.size() or row_dirs.any(func(d): return not d in COMPASS):
		printerr("rows= takes %d of %s, comma-separated" % [ROW_DIRS.size(), COMPASS])
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path("res://art")
	for pair in pairs:
		var kv: PackedStringArray = pair.split("=")
		var err := _pack("%s/%s" % [src, kv[0]], "%s/%s.png" % [out_dir, kv[1]])
		if err != "":
			printerr(kv[0], ": ", err)
			quit(1)
			return
	quit()


func _pack(folder: String, out_path: String) -> String:
	var anim := ""
	var anims := DirAccess.get_directories_at(folder + "/animations") if DirAccess.dir_exists_absolute(folder + "/animations") else PackedStringArray()
	if anims.size() > 0:
		anim = "%s/animations/%s" % [folder, anims[0]]
	var frames_n := 1
	if anim != "":
		frames_n = DirAccess.get_files_at("%s/%s" % [anim, row_dirs[0]]).size()
	var sheet := Image.create(FRAME * frames_n, FRAME * row_dirs.size(), false, Image.FORMAT_RGBA8)
	for row in row_dirs.size():
		var still := _load("%s/rotations/%s.png" % [folder, row_dirs[row]])
		if still == null:
			return "missing rotations/%s.png" % row_dirs[row]
		var su := still.get_used_rect()
		# where the still's ground contact lands in the frame
		var shift := Vector2i(FRAME / 2 - (su.position.x + su.size.x / 2), FRAME - ANCHOR_UP - (su.end.y - CONTACT_UP[row]))
		for col in frames_n:
			var img := still
			var off := shift
			if anim != "":
				img = _load("%s/%s/frame_%03d.png" % [anim, row_dirs[row], col])
				if img == null:
					return "missing %s frame %d" % [row_dirs[row], col]
				# animation canvases are bigger than the stills: line the first frame's rider up with the still's
				var a0 := _load("%s/%s/frame_000.png" % [anim, row_dirs[row]]).get_used_rect()
				off = shift + su.position - a0.position
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(col * FRAME, row * FRAME) + off)
	print("%s: %d frame(s) x %d directions" % [out_path, frames_n, row_dirs.size()])
	return "" if sheet.save_png(out_path) == OK else "could not write " + out_path


func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	img.convert(Image.FORMAT_RGBA8)
	return img
