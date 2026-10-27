extends SceneTree
## Makes colour variants of the vehicle sheets: art/vehicle_<kind>.png -> art/vehicle_<kind>_c<n>.png, the body paint
## shifted round the colour wheel (and some made darker or paler) while windows, tyres, chrome and outlines (the greys
## and near-blacks) stay as they are. Liveried vehicles (police, taxi, ambulance, ...) are left alone.
##
##   godot --headless -s tools/recolor_vehicle.gd -- [variants=4]

const SKIP := ["car", "truck", "sedan_police", "sedan_taxi", "van_ambulance", "truck_firetruck", "van_school_bus", "van_mail",
	"truck_icecream", "sedan_cab_checker", "van_city_bus", "sedan_horse_carriage", "truck_tractor", "snowcat", "snowmobile"]
# per variant: hue shift (turns), saturation and value multipliers
const LOOKS := [[0.5, 1.0, 1.0], [0.25, 1.05, 1.0], [0.75, 0.9, 1.05], [0.0, 0.35, 1.12], [0.12, 1.0, 0.7], [0.62, 1.1, 0.85]]


func _initialize() -> void:
	var n := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("variants="):
			n = clampi(a.substr(9).to_int(), 1, LOOKS.size())
	var dir := ProjectSettings.globalize_path("res://art")
	var made := 0
	var variant_re := RegEx.create_from_string("_c\\d+\\.png$")
	for f in DirAccess.get_files_at(dir):
		if not f.begins_with("vehicle_") or not f.ends_with(".png") or variant_re.search(f) != null:
			continue
		var kind := f.trim_prefix("vehicle_").trim_suffix(".png")
		if kind in SKIP:
			continue
		var src := Image.load_from_file("%s/%s" % [dir, f])
		src.convert(Image.FORMAT_RGBA8)
		var base_h := _body_hue(src)
		for v in n:
			var look: Array = LOOKS[(v + kind.length()) % LOOKS.size()]
			var img: Image = src.duplicate()
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.a < 0.05 or c.s < 0.3 or c.v < 0.22:
						continue   # glass, tyres, chrome, outline
					# only the paint: colours near the body's own hue (keeps tail lights, stripes and signs)
					var d := absf(fposmod(c.h - base_h + 0.5, 1.0) - 0.5)
					if d > 0.12:
						continue
					img.set_pixel(x, y, Color.from_hsv(fposmod(c.h + float(look[0]), 1.0), clampf(c.s * float(look[1]), 0.0, 1.0),
						clampf(c.v * float(look[2]), 0.0, 1.0), c.a))
			img.save_png("%s/vehicle_%s_c%d.png" % [dir, kind, v + 1])
			made += 1
	print("%d colour variants" % made)
	quit()


## The most common saturated hue in the sheet: the body paint.
func _body_hue(img: Image) -> float:
	var bins := PackedInt32Array()
	bins.resize(36)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.s > 0.3 and c.v > 0.22:
				bins[int(c.h * 36.0) % 36] += 1
	var best := 0
	for i in 36:
		if bins[i] > bins[best]:
			best = i
	return (best + 0.5) / 36.0
