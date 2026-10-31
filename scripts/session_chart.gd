extends Control
## The end-of-session timeline: power, cadence and speed lanes over the session (each with its average as a dashed
## line), and markers along the top for pizzas delivered, challenges won or lost and race placings.
## Built from Ride.snapshot(); power and cadence lanes say so when no trainer was connected.

const W := 440
const STRIP := 16          # px, the event markers along the top
const LANE := 32
const GAP := 3
const INK := Color(0.1, 0.08, 0.16)
const LANE_BG := Color(0.04, 0.05, 0.16)
const GAP_S := 3           # seconds without a sample that break the line (paused, in a menu, in the ER)
const LANES := [
	{"key": 4, "name": "POWER", "unit": "W", "avg": "watts", "color": Color(1.0, 0.72, 0.25)},
	{"key": 5, "name": "CADENCE", "unit": "rpm", "avg": "rpm", "color": Color(0.4, 0.85, 1.0)},
	{"key": 3, "name": "SPEED", "unit": "km/h", "avg": "kmh", "color": Color(0.5, 1.0, 0.5)},
]
const EVENT_COL := {"pizza": Color(1.0, 0.6, 0.2), "won": Color(0.4, 1.0, 0.5), "lost": Color(1.0, 0.4, 0.35), "race": Color(1.0, 0.85, 0.3)}

var font: Font
var t0 := 0
var span := 1
var cols: Array = []       # per lane: an array of W values (per pixel column, NAN where there was no riding)
var tops: Array = []       # per lane: the value at the top of the lane
var maxes: Array = []      # per lane: the highest value (per pixel column)
var avg: Dictionary = {}
var events: Array = []


func setup(snap: Dictionary) -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(W, STRIP + 3 * LANE + 2 * GAP + 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var samples: Array = snap["samples"]
	avg = snap["avg"]
	events = snap["events"]
	if samples.is_empty():
		return
	t0 = int(samples[0][0])
	span = maxi(1, int(samples[-1][0]) - t0)
	for lane in LANES:
		var sum := PackedFloat32Array()
		var n := PackedInt32Array()
		sum.resize(W)
		n.resize(W)
		var top := 1.0
		var last_t := -100
		var gapped := PackedByteArray()
		gapped.resize(W)
		for s in samples:
			var v := float(s[lane["key"]])
			if v < 0.0:
				continue
			if lane["key"] == 3:
				v *= 3.6
			var x := _x(int(s[0]))
			if int(s[0]) - last_t > GAP_S and last_t >= 0:
				gapped[x] = 1   # a pause ends here: don't join this column to the one before
			last_t = int(s[0])
			sum[x] += v
			n[x] += 1
			top = maxf(top, v)
		var col: Array = []
		for x in W:
			col.append(sum[x] / n[x] if n[x] > 0 else NAN)
		cols.append({"v": col, "gap": gapped})
		tops.append(ceilf(top * 1.1 / 10.0) * 10.0)
		maxes.append(top)


func _x(t: int) -> int:
	return clampi(int(float(t - t0) / span * (W - 1)), 0, W - 1)


func _clock(s: int) -> String:
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


func _text(s: String, pos: Vector2, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos + Vector2(1, 1), s, align, width, 8, INK)
	draw_string(font, pos, s, align, width, 8, col)


func _draw() -> void:
	var y := float(STRIP)
	for i in LANES.size():
		var lane: Dictionary = LANES[i]
		var r := Rect2(0, y, W, LANE)
		draw_rect(r, LANE_BG)
		draw_rect(r, Color(1.0, 0.85, 0.3, 0.35), false)
		var a: float = avg.get(lane["avg"], -1.0)
		if cols.size() > i and a >= 0.0:
			var top: float = tops[i]
			var line: Array = cols[i]["v"]
			var gap: PackedByteArray = cols[i]["gap"]
			var c: Color = lane["color"]
			for x in W:
				var v: float = line[x]
				if is_nan(v):
					continue
				var py := r.end.y - 1.0 - (r.size.y - 2.0) * clampf(v / top, 0.0, 1.0)
				draw_line(Vector2(x, r.end.y - 1.0), Vector2(x, py), Color(c, 0.18))   # a faint fill under the line
				if x > 0 and not is_nan(line[x - 1]) and gap[x] == 0:
					var py0 := r.end.y - 1.0 - (r.size.y - 2.0) * clampf(float(line[x - 1]) / top, 0.0, 1.0)
					draw_line(Vector2(x - 1, py0), Vector2(x, py), c)
				else:
					draw_rect(Rect2(x, py, 1, 1), c)
			var ay := r.end.y - 1.0 - (r.size.y - 2.0) * clampf(a / top, 0.0, 1.0)
			draw_dashed_line(Vector2(0, ay), Vector2(W, ay), Color(1, 1, 1, 0.55), 1.0, 3.0)
			_text("%s  max %d" % [lane["name"], roundi(maxes[i])], Vector2(3, y + 9), Color(c, 0.9))
			_text("avg %s %s" % [("%.1f" % a) if lane["key"] == 3 else str(roundi(a)), lane["unit"]], Vector2(0, y + 9), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, W - 3)
		else:
			_text(lane["name"], Vector2(3, y + 9), Color(lane["color"], 0.9))
			_text("no trainer connected", Vector2(0, y + LANE * 0.5 + 4), Color(0.6, 0.62, 0.8), HORIZONTAL_ALIGNMENT_CENTER, W)
		y += LANE + GAP
	var bottom := y - GAP
	# events: a faint line down through the lanes and a marker in the strip on top (stacked when they bunch up)
	var row_x := [-100.0, -100.0]
	for e in events:
		var x := float(_x(int(e["t"])))
		var c: Color = EVENT_COL.get(e["kind"], Color.WHITE)
		draw_line(Vector2(x, STRIP), Vector2(x, bottom), Color(c, 0.4))
		var row := 0 if x - row_x[0] >= 9.0 else 1 if x - row_x[1] >= 9.0 else 0
		row_x[row] = x
		_marker(e, Vector2(x, 4.0 if row == 0 else 11.0))
	# time axis and legend
	_text("0:00", Vector2(0, bottom + 9), Color(0.75, 0.8, 1.0))
	_text(_clock(span / 2), Vector2(0, bottom + 9), Color(0.75, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_clock(span), Vector2(0, bottom + 9), Color(0.75, 0.8, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, W)
	var lx := 0.0
	for k in [["pizza", "pizza"], ["won", "challenge won"], ["lost", "challenge lost"], ["race", "race place"]]:
		_marker({"kind": k[0], "place": 1}, Vector2(lx + 4, bottom + 18))
		_text(k[1], Vector2(lx + 10, bottom + 21), Color(0.8, 0.85, 1.0))
		lx += 14 + font.get_string_size(k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 8
	_text("- - average", Vector2(0, bottom + 21), Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, W)


## A little marker centred on `p`: a pizza, a green flag, a red cross, or a medal with the placing on it.
func _marker(e: Dictionary, p: Vector2) -> void:
	var c: Color = EVENT_COL.get(e["kind"], Color.WHITE)
	match e["kind"]:
		"pizza":
			draw_circle(p, 3.5, INK)
			draw_circle(p, 2.8, c)
			draw_rect(Rect2(p + Vector2(-1, -2), Vector2(1, 1)), Color(0.8, 0.15, 0.1))
			draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), Color(0.8, 0.15, 0.1))
		"won":
			draw_line(p + Vector2(-2, -3), p + Vector2(-2, 4), Color(0.9, 0.9, 0.9))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-1, -3), p + Vector2(4, -1), p + Vector2(-1, 1)]), c)
		"lost":
			draw_line(p + Vector2(-3, -3), p + Vector2(3, 3), c, 2.0)
			draw_line(p + Vector2(3, -3), p + Vector2(-3, 3), c, 2.0)
		"race":
			var place := int(e.get("place", 0))
			var medal := Color(1.0, 0.82, 0.25) if place == 1 else Color(0.8, 0.82, 0.88) if place == 2 else Color(0.85, 0.55, 0.3) if place == 3 else Color(0.55, 0.55, 0.65)
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(9, 9)), INK)
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(7, 7)), medal)
			draw_string(font, p + Vector2(-4, 3), str(place), HORIZONTAL_ALIGNMENT_CENTER, 9, 7, INK)
