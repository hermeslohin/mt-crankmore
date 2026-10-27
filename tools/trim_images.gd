extends SceneTree
## Copies single pictures into art/, each cropped to the pixels it actually uses (plus a 1 px margin), so a picture's
## bottom edge is where the thing stands (Sprites.draw_image puts the middle of the bottom edge on the spot).
##
##   godot --headless -s tools/trim_images.gd -- <source dir> <prefix>
##     e.g. <dir>/pine_1.png -> art/<prefix>pine_1.png


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage: trim_images.gd -- <source dir> <prefix>")
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path("res://art")
	var n := 0
	for f in DirAccess.get_files_at(a[0]):
		if not f.ends_with(".png"):
			continue
		var img := Image.load_from_file("%s/%s" % [a[0], f])
		img.convert(Image.FORMAT_RGBA8)
		var r := img.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png("%s/%s%s" % [out_dir, a[1], f])
		n += 1
	print("%d pictures trimmed into art/" % n)
	quit()
