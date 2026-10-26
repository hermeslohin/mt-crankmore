extends Node2D
## Falling snow in winter, tumbling leaves in fall and drifting blossom petals in spring, drawn over the world
## (under the HUD) in screen space. The flakes shift a little against the camera so they feel part of the scene.
## When Skies says so, rain streaks down (with little splashes) or a heavy snowfall thickens the flurries.

var cam: Camera2D
var parts: Array = []
var _season := ""
var _last_cam := Vector2.ZERO
var rain: Array = []
var splashes: Array = []     # {pos, t}
const RAIN_DROPS := 320
const HEAVY_SNOW := 380      # extra flakes in a winter snowfall


func _process(delta: float) -> void:
	if Season.current != _season:
		_season = Season.current
		_spawn()
	var size := get_viewport_rect().size
	var shift := Vector2.ZERO
	if cam != null:
		shift = (cam.position - _last_cam) * cam.zoom * 0.6
		_last_cam = cam.position
		if shift.length() > 200.0:
			shift = Vector2.ZERO   # a jump cut (new race, the ER): don't smear the flakes across the screen
	for p in parts:
		p["ph"] += delta * p["spin"]
		p["pos"] += Vector2(p["wind"] + sin(p["ph"]) * p["sway"], p["fall"]) * delta - shift
		p["pos"] = Vector2(fposmod(p["pos"].x, size.x + 20.0), fposmod(p["pos"].y, size.y + 20.0))
	_update_rain(delta, size, shift)
	queue_redraw()


func _update_rain(delta: float, size: Vector2, shift: Vector2) -> void:
	if rain.is_empty():
		for k in RAIN_DROPS:
			rain.append({"pos": Vector2(randf() * (size.x + 40.0), randf() * (size.y + 40.0)), "v": randf_range(330.0, 430.0), "len": randf_range(5.0, 9.0)})
	if Skies.weather != "rain" and Skies.amount <= 0.0:
		splashes.clear()
		return
	for d in rain:
		d["pos"] += Vector2(-0.22, 1.0) * float(d["v"]) * delta - shift
		if d["pos"].y > size.y + 20.0 or (randf() < delta * 1.6 and d["pos"].y > 20.0):
			# lands: a splash where it hit, and a new drop at the top
			if splashes.size() < 60 and randf() < Skies.amount:
				splashes.append({"pos": d["pos"] - Vector2(20, 20), "t": 0.0})
			d["pos"] = Vector2(randf() * (size.x + 40.0), randf_range(-20.0, 0.0))
		d["pos"].x = fposmod(d["pos"].x, size.x + 40.0)
	for sp in splashes:
		sp["t"] += delta
		sp["pos"] -= shift
	splashes = splashes.filter(func(sp): return sp["t"] < 0.25)


func _spawn() -> void:
	parts.clear()
	var size := get_viewport_rect().size
	var n: int = {"winter": 170 + HEAVY_SNOW, "fall": 34, "spring": 30}.get(_season, 0)
	for k in n:
		var p := {"pos": Vector2(randf() * (size.x + 20.0), randf() * (size.y + 20.0)), "ph": randf() * TAU}
		match _season:
			"winter":
				var near := randf() < 0.25
				p.merge({"fall": randf_range(26.0, 40.0) if near else randf_range(12.0, 24.0), "wind": -6.0, "sway": 8.0, "spin": randf_range(1.0, 2.0),
					"size": 2.0 if near else 1.0, "col": Color(1, 1, 1, 0.95 if near else 0.7)})
			"fall":
				p.merge({"fall": randf_range(14.0, 24.0), "wind": 8.0, "sway": 18.0, "spin": randf_range(2.0, 3.5), "size": 2.0,
					"col": Season.FALL_LEAVES[k % Season.FALL_LEAVES.size()]})
			"spring":
				p.merge({"fall": randf_range(9.0, 16.0), "wind": 10.0, "sway": 12.0, "spin": randf_range(1.5, 3.0), "size": 2.0,
					"col": [Color(1.0, 0.75, 0.86), Color(1.0, 0.92, 0.95)][k % 2]})
		parts.append(p)


func _draw() -> void:
	var heavy := Skies.amount if Skies.weather == "snow" or (Skies.weather == "clear" and _season == "winter") else 0.0
	var shown := parts.size() if _season != "winter" else 170 + int(HEAVY_SNOW * heavy)
	for i in shown:
		var p: Dictionary = parts[i]
		var at: Vector2 = p["pos"] - Vector2(10, 10)
		var s: float = p["size"]
		if _season == "winter":
			draw_rect(Rect2(at.round(), Vector2(s, s)), p["col"])
		else:
			# a leaf or petal tumbling: its width flips as it turns over
			var w := maxf(1.0, roundf(absf(cos(p["ph"])) * 3.0))
			draw_rect(Rect2(at.round(), Vector2(w, s)), p["col"])
			if _season == "fall":
				draw_rect(Rect2(at.round() + Vector2(0, s), Vector2(1, 1)), Iso.shade(p["col"], 0.6))
	if Skies.amount > 0.0 and (Skies.weather == "rain" or (Skies.weather == "clear" and _season != "winter")):
		var col := Color(0.75, 0.82, 0.95, 0.55)
		var n := int(rain.size() * Skies.amount)
		for i in n:
			var d: Dictionary = rain[i]
			var a: Vector2 = (d["pos"] as Vector2) - Vector2(20, 20)
			draw_line(a.round(), (a + Vector2(0.22, -1.0) * float(d["len"])).round(), col, 1.0)
		for sp in splashes:
			var u: float = sp["t"] / 0.25
			var c: Vector2 = sp["pos"]
			draw_rect(Rect2((c + Vector2(-2.0 - u * 2.0, -u * 2.0)).round(), Vector2(1, 1)), col)
			draw_rect(Rect2((c + Vector2(2.0 + u * 2.0, -u * 2.0)).round(), Vector2(1, 1)), col)
