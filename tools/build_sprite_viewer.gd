extends SceneTree
## Writes tools/sprite_viewer/manifest.js: every picture in art/ with its size, for the sprite viewer page
## (tools/sprite_viewer/index.html, open it in a browser). Run it again after adding art.
##
##   godot --headless -s tools/build_sprite_viewer.gd


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://art")
	var rows: PackedStringArray = []
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		if not f.ends_with(".png"):
			continue
		var size := _png_size("%s/%s" % [dir, f])
		if size != Vector2i.ZERO:
			rows.append('["%s",%d,%d]' % [f.trim_suffix(".png"), size.x, size.y])
	var out := FileAccess.open(ProjectSettings.globalize_path("res://tools/sprite_viewer/manifest.js"), FileAccess.WRITE)
	out.store_string("// Made by tools/build_sprite_viewer.gd: [name, width, height] for every art/*.png\nwindow.SPRITES = [\n%s\n];\n" % ",\n".join(rows))
	out.close()
	print("%d sprites" % rows.size())
	quit()


## Width and height from the PNG header (much quicker than loading every picture).
func _png_size(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 24:
		return Vector2i.ZERO
	f.big_endian = true
	f.seek(16)
	return Vector2i(f.get_32(), f.get_32())
