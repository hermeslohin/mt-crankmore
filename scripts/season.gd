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


func snowman(ci: CanvasItem, b: Vector2, sd: int) -> void:
	Sprites.draw_image(ci, "scenery_snowman_a" if sd % 2 == 0 else "scenery_snowman_b", b)


func pumpkin(ci: CanvasItem, b: Vector2, size: float, sd: int) -> void:
	Sprites.draw_image(ci, "scenery_pumpkins_%d" % (1 + sd % 3), b, sd % 2 == 1, 1.0, size * 0.7)


## A butterfly (art/animal_butterfly.png) centred on `p`, tinted towards `col` so they are not all orange.
func butterfly(ci: CanvasItem, p: Vector2, col: Color, flap: float) -> void:
	Sprites.draw_strip(ci, "animal_butterfly", p, flap / 14.0, 14.0, false, false, Color.WHITE.lerp(col, 0.4))


## A little bed of tulips.
func flower_bed(ci: CanvasItem, b: Vector2, sd: int) -> void:
	Sprites.draw_image(ci, ["scenery_tulips_red", "scenery_tulips_yellow", "scenery_tulips_pink"][sd % 3], b, sd % 2 == 1)


## A heap of fallen leaves.
func leaf_pile(ci: CanvasItem, b: Vector2, sd: int) -> void:
	Sprites.draw_image(ci, "scenery_leafpile_orange" if sd % 2 == 0 else "scenery_leafpile_red", b, sd % 3 == 0)


## A duck (or a duckling, `small`) paddling on the water.
func duck(ci: CanvasItem, p: Vector2, facing: float, small: bool) -> void:
	# swimming right (down-right on screen is world +x then -y) or left
	Sprites.draw_vehicle(ci, "obj_duckling" if small else "obj_duck", p + Vector2(0, -2), Vector2(1, -1) if facing > 0.0 else Vector2(-1, 1))