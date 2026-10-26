extends Node
## The four seasons in Crankmore Village and on Mt. Crankmore. "auto" (the default) follows today's date
## (northern hemisphere: Mar-May spring, Jun-Aug summer, Sep-Nov fall, Dec-Feb winter); the title and pause
## menus can pick one. Summer is the game as it was drawn; the other seasons recolour it through the helpers
## below (ground, leaves, sky, water, roofs) and add their own scenery: snow, snowmen and skiers in winter,
## blossom, flower beds and butterflies in spring, orange trees, pumpkins and leaf piles in fall, and
## people playing games in summer. weather.gd draws the falling snow, leaves and petals.

signal changed

const ORDER := ["spring", "summer", "fall", "winter"]
const NAMES := {"spring": "Spring", "summer": "Summer", "fall": "Fall", "winter": "Winter"}
const SNOW := Color(0.93, 0.95, 1.0)
const FALL_LEAVES := [Color(0.96, 0.55, 0.13), Color(0.86, 0.27, 0.14), Color(0.98, 0.78, 0.2), Color(0.78, 0.42, 0.16)]
const BLOSSOM := [Color(1.0, 0.7, 0.82), Color(0.99, 0.9, 0.93), Color(0.62, 0.86, 0.4)]

var choice := "auto"         # "auto" or one of ORDER
var current := "summer"


func _ready() -> void:
	current = today()


func today() -> String:
	var m: int = Time.get_date_dict_from_system()["month"]
	if m >= 3 and m <= 5:
		return "spring"
	if m >= 6 and m <= 8:
		return "summer"
	if m >= 9 and m <= 11:
		return "fall"
	return "winter"


func set_choice(c: String) -> void:
	choice = c if c in ORDER else "auto"
	var now := today() if choice == "auto" else choice
	if now != current:
		current = now
		changed.emit()


## LEFT / RIGHT on the menu: auto, spring, summer, fall, winter.
func step(d: int) -> void:
	var opts: Array = ["auto"] + ORDER
	set_choice(opts[posmod(opts.find(choice) + d, opts.size())])


func label() -> String:
	return "Today (%s)" % NAMES[current] if choice == "auto" else NAMES[current]


func is_(s: String) -> bool:
	return current == s


# ---- colours ------------------------------------------------------------------

## Grass, meadow and forest floor.
func ground(col: Color) -> Color:
	match current:
		"spring":
			return Color(col.r * 0.92, minf(1.0, col.g * 1.02 + 0.02), col.b * 0.86)
		"fall":
			return col.lerp(Color(0.84, 0.54, 0.2), 0.75)
		"winter":
			return SNOW.lerp(col, 0.08).darkened(clampf((0.5 - col.get_luminance()) * 0.2, 0.0, 0.08))
	return col


## A broadleaf canopy colour. `sd` picks each tree's own fall colour or blossom. Winter trees are bare (see bare()).
func leaves(col: Color, sd: int) -> Color:
	var pal: Color
	match current:
		"spring":
			pal = BLOSSOM[posmod(sd, BLOSSOM.size())]
		"fall":
			pal = FALL_LEAVES[posmod(sd, FALL_LEAVES.size())]
		_:
			return col
	return Color.from_hsv(pal.h, pal.s, clampf(col.v * pal.v / 0.75, 0.0, 1.0))


## Evergreens: one kind of pine is a larch, which goes golden in the fall.
func pine(col: Color, larch: bool) -> Color:
	return Color(0.9, 0.62, 0.16).lerp(col, 0.15) if larch and current == "fall" else col


func bare() -> bool:
	return current == "winter"


func sky(col: Color) -> Color:
	match current:
		"winter":
			return col.lerp(Color(0.8, 0.84, 0.92), 0.45)
		"fall":
			return col.lerp(Color(0.98, 0.82, 0.62), 0.18)
		"spring":
			return col.lerp(Color(0.72, 0.88, 1.0), 0.15)
	return col


## Lakes and creeks freeze in winter.
func water(col: Color) -> Color:
	return Color(0.82, 0.91, 0.98).lerp(col, 0.22) if current == "winter" else col


func roof(col: Color) -> Color:
	return col.lerp(SNOW, 0.8) if current == "winter" else col


# ---- shared drawing (screen coordinates; `ci` is the canvas item doing the drawing) ---------------------

## Snow lying on one tier of a pine: a cap at the tip and a rim along the lower edge.
func snow_tier(ci: CanvasItem, l: Vector2, r: Vector2, tip: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([tip, tip.lerp(l, 0.42), tip.lerp(tip.lerp(r, 0.42), 0.6) + Vector2(0, 1), tip.lerp(r, 0.42)]), SNOW)
	ci.draw_line(l + Vector2(1, -1), l.lerp(r, 0.45) + Vector2(0, -1), SNOW, 1.0)


## A leafless broadleaf tree for winter, with snow on the branches.
func bare_tree(ci: CanvasItem, base: Vector2, s: float, sd: int) -> void:
	var o := Iso.OUTLINE
	var bark := Color(0.42, 0.3, 0.22)
	var top := base + Vector2(0, -24) * s
	ci.draw_line(base, top, o, 4.0)
	ci.draw_line(base, top, bark, 2.0)
	for k in 4:
		var y := -10.0 - k * 4.5
		var side := 1.0 if (k + sd) % 2 == 0 else -1.0
		var from := base + Vector2(0, y) * s
		var to := from + Vector2(side * (9.0 - k * 1.5), -6.0 - k) * s
		ci.draw_line(from, to, bark, 1.0)
		ci.draw_line(to + Vector2(side * -1, -1), to + Vector2(side * 2, -3), bark, 1.0)
		ci.draw_rect(Rect2(to + Vector2(-1, -2), Vector2(3, 1)), SNOW)
	ci.draw_rect(Rect2(top + Vector2(-2, -1), Vector2(4, 2)), SNOW)


func snowman(ci: CanvasItem, b: Vector2, sd: int) -> void:
	var o := Iso.OUTLINE
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-7, 0), b + Vector2(0, -3), b + Vector2(7, 0), b + Vector2(0, 3)]), Color(0, 0, 0, 0.15))
	for c in [[Vector2(0, -5), 6.0], [Vector2(0, -14), 4.5], [Vector2(0, -21), 3.5]]:
		ci.draw_circle(b + c[0], c[1] + 1.0, o)
	for c in [[Vector2(0, -5), 6.0], [Vector2(0, -14), 4.5], [Vector2(0, -21), 3.5]]:
		ci.draw_circle(b + c[0], c[1], Color(0.97, 0.98, 1.0))
		ci.draw_circle(b + c[0] + Vector2(2, 1), c[1] * 0.55, Color(0.84, 0.88, 0.96))
	ci.draw_rect(Rect2(b + Vector2(-2, -22), Vector2(1, 1)), o)
	ci.draw_rect(Rect2(b + Vector2(1, -22), Vector2(1, 1)), o)
	ci.draw_line(b + Vector2(0, -21), b + Vector2(4, -20), Color(1.0, 0.55, 0.1), 1.0)   # carrot
	ci.draw_rect(Rect2(b + Vector2(0, -15), Vector2(1, 1)), o)
	ci.draw_rect(Rect2(b + Vector2(0, -12), Vector2(1, 1)), o)
	ci.draw_line(b + Vector2(-4, -14), b + Vector2(-10, -18), Color(0.42, 0.3, 0.22), 1.0)   # stick arms
	ci.draw_line(b + Vector2(4, -14), b + Vector2(10, -19), Color(0.42, 0.3, 0.22), 1.0)
	var scarf: Color = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.2, 0.7, 0.35)][posmod(sd, 3)]
	ci.draw_rect(Rect2(b + Vector2(-3, -18), Vector2(6, 2)), scarf)
	ci.draw_rect(Rect2(b + Vector2(1, -17), Vector2(2, 4)), scarf)
	if sd % 2 == 0:   # top hat
		ci.draw_rect(Rect2(b + Vector2(-4, -25), Vector2(8, 1)), o)
		ci.draw_rect(Rect2(b + Vector2(-3, -30), Vector2(6, 5)), o)
	else:               # bobble hat
		ci.draw_rect(Rect2(b + Vector2(-3, -26), Vector2(6, 3)), scarf)
		ci.draw_circle(b + Vector2(0, -27), 1.5, Color.WHITE)


## A skier in a bright jacket, skis along `dir` (screen), poles planted on the turns.
func skier(ci: CanvasItem, b: Vector2, dir: Vector2, jacket: Color, phase: float) -> void:
	var o := Iso.OUTLINE
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-5, 0), b + Vector2(0, -2), b + Vector2(5, 0), b + Vector2(0, 2)]), Color(0, 0, 0, 0.15))
	for side in [-1.0, 1.0]:
		var c: Vector2 = b + n * side * 1.5
		ci.draw_line(c - d * 6.0, c + d * 7.0, o, 2.0)
		ci.draw_line(c + d * 6.0, c + d * 7.0 + Vector2(0, -1), o, 1.0)
	var lean := d.x * 2.0
	var hip := b + Vector2(lean * 0.5, -6)
	ci.draw_line(b + Vector2(-1, -1), hip, Color(0.2, 0.22, 0.3), 2.0)
	ci.draw_line(b + Vector2(1, -1), hip + Vector2(1, 0), Color(0.2, 0.22, 0.3), 2.0)
	ci.draw_rect(Rect2(hip + Vector2(-3 + lean, -7), Vector2(6, 7)), o)
	ci.draw_rect(Rect2(hip + Vector2(-2 + lean, -6), Vector2(4, 5)), jacket)
	var head := hip + Vector2(lean, -10)
	ci.draw_circle(head, 2.8, o)
	ci.draw_circle(head, 2.2, Color(0.96, 0.8, 0.65))
	ci.draw_rect(Rect2(head + Vector2(-2, -3), Vector2(4, 2)), jacket.darkened(0.3))
	ci.draw_rect(Rect2(head + Vector2(-2, -1), Vector2(4, 1)), Color(0.15, 0.15, 0.2))   # goggles
	var plant := sin(phase) * 2.0
	ci.draw_line(hip + Vector2(-3 + lean, -5), b + Vector2(-5, plant), Color(0.7, 0.7, 0.75), 1.0)
	ci.draw_line(hip + Vector2(3 + lean, -5), b + Vector2(5, -plant), Color(0.7, 0.7, 0.75), 1.0)


func pumpkin(ci: CanvasItem, b: Vector2, size: float, sd: int) -> void:
	var o := Iso.OUTLINE
	var w := 4.0 * size
	var h := 3.2 * size
	var c := b + Vector2(0, -h)
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-w - 1, 0), b + Vector2(0, -2), b + Vector2(w + 1, 0), b + Vector2(0, 2)]), Color(0, 0, 0, 0.15))
	ci.draw_set_transform(c, 0.0, Vector2(1.0, h / w))
	ci.draw_circle(Vector2.ZERO, w + 1.0, o)
	ci.draw_circle(Vector2.ZERO, w, Color(0.95, 0.52, 0.1))
	ci.draw_circle(Vector2(-w * 0.35, 0), w * 0.45, Color(0.85, 0.42, 0.06))
	ci.draw_circle(Vector2(w * 0.4, -w * 0.2), w * 0.3, Color(1.0, 0.68, 0.25))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_line(c + Vector2(0, -h + 1), c + Vector2(1, -h - 2), Color(0.3, 0.42, 0.15), 2.0)
	if sd % 3 == 0 and size > 1.0:   # a jack-o'-lantern
		ci.draw_rect(Rect2(c + Vector2(-3, -1), Vector2(2, 1)), o)
		ci.draw_rect(Rect2(c + Vector2(1, -1), Vector2(2, 1)), o)
		ci.draw_rect(Rect2(c + Vector2(-2, 2), Vector2(4, 1)), o)


## A butterfly (art/animal_butterfly.png) centred on `p`, tinted towards `col` so they are not all orange.
func butterfly(ci: CanvasItem, p: Vector2, col: Color, flap: float) -> void:
	Sprites.draw_strip(ci, "animal_butterfly", p, flap / 14.0, 14.0, false, false, Color.WHITE.lerp(col, 0.4))


## A little bed of tulips.
func flower_bed(ci: CanvasItem, b: Vector2, sd: int) -> void:
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-10, 0), b + Vector2(0, -5), b + Vector2(10, 0), b + Vector2(0, 5)]), Color(0.45, 0.3, 0.2))
	var cols := [Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.2), Color(0.95, 0.5, 0.8), Color(1, 1, 1), Color(0.65, 0.45, 1.0)]
	for k in 9:
		var p := b + Vector2((k % 3 - 1) * 5.0 + (k / 3 - 1) * 2.0, (k / 3 - 1) * 2.5 - (k % 3 - 1) * 1.0)
		ci.draw_line(p, p + Vector2(0, -4), Color(0.25, 0.55, 0.22), 1.0)
		ci.draw_rect(Rect2(p + Vector2(-1, -7), Vector2(3, 3)), cols[(sd + k) % cols.size()])


## A heap of fallen leaves.
func leaf_pile(ci: CanvasItem, b: Vector2, sd: int) -> void:
	var pts := PackedVector2Array()
	for k in 9:
		var a := PI + PI * k / 8.0
		pts.append(b + Vector2(cos(a) * 10.0, sin(a) * 6.0 - (2.0 if k % 2 == 0 else 0.0)))
	Iso.poly(ci, pts, Color(0.86, 0.45, 0.14))
	for k in 10:
		var h := sd * 31 + k * 17
		var p := b + Vector2(float(h % 17) - 8.0, -float((h >> 3) % 6) - 1.0)
		ci.draw_rect(Rect2(p, Vector2(2, 1)), FALL_LEAVES[h % FALL_LEAVES.size()])


## An ice skater gliding along `dir` (screen), arms out, one leg pushing back.
func skater(ci: CanvasItem, b: Vector2, dir: Vector2, jacket: Color, phase: float) -> void:
	var o := Iso.OUTLINE
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var push := sin(phase)
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(-4, 0), b + Vector2(0, -2), b + Vector2(4, 0), b + Vector2(0, 2)]), Color(0, 0, 0, 0.12))
	var hip := b + Vector2(d.x * 1.5, -7)
	ci.draw_line(hip, b, Color(0.2, 0.22, 0.3), 2.0)
	var back := b - d * (3.0 + push * 3.0) + Vector2(0, -2.0 - absf(push) * 2.0)
	ci.draw_line(hip, back, Color(0.2, 0.22, 0.3), 2.0)
	ci.draw_line(b + Vector2(-2, 1), b + Vector2(3, 1), Color(0.8, 0.85, 0.9), 1.0)
	ci.draw_rect(Rect2(hip + Vector2(-3, -7), Vector2(6, 7)), o)
	ci.draw_rect(Rect2(hip + Vector2(-2, -6), Vector2(4, 5)), jacket)
	ci.draw_line(hip + Vector2(-2, -5), hip + Vector2(-9, -4 + push), o, 1.0)
	ci.draw_line(hip + Vector2(2, -5), hip + Vector2(9, -4 - push), o, 1.0)
	var head := hip + Vector2(0, -10)
	ci.draw_circle(head, 2.8, o)
	ci.draw_circle(head, 2.2, Color(0.96, 0.8, 0.65))
	ci.draw_rect(Rect2(head + Vector2(-2, -3), Vector2(4, 2)), jacket.darkened(0.35))
	ci.draw_circle(head + Vector2(0, -3), 1.2, Color.WHITE)


## A duck (or a duckling, `small`) paddling on the water.
func duck(ci: CanvasItem, p: Vector2, facing: float, small: bool) -> void:
	var k := 0.6 if small else 1.0
	var body := Color(1.0, 0.88, 0.3) if small else Color(0.62, 0.5, 0.36)
	ci.draw_circle(p, 3.6 * k + 0.8, Iso.OUTLINE)
	ci.draw_circle(p, 3.6 * k, body)
	var head := p + Vector2(facing * 3.0 * k, -3.0 * k)
	ci.draw_circle(head, 2.0 * k + 0.6, Iso.OUTLINE)
	ci.draw_circle(head, 2.0 * k, body if small else Color(0.15, 0.5, 0.3))
	ci.draw_rect(Rect2(head + Vector2(facing * 1.5 * k - (0.0 if facing > 0 else 2.0), 0), Vector2(2, 1)), Color(1.0, 0.6, 0.1))
	ci.draw_line(p + Vector2(-5, 3) * k, p + Vector2(5, 3) * k, Color(0.85, 0.95, 1.0, 0.7), 1.0)
