class_name Flora
extends RefCounted
## Trees, bushes and rocks: pictures (art/scenery_<name>.png from the PixelLab sprites in sprites/scenery/) that change
## with the season. A picture stands with the middle of its bottom edge on the spot it is drawn at.

const TREE_SCALE := 0.9   # the pictures are drawn a little smaller than they were made, times each tree's own size


## A tree of `species` ("pine", "pine_light", "oak", "birch", "snag") at `base`, `s` times its usual size:
## snow-laden firs and bare trees in winter, blossom in spring, red and gold in fall.
static func tree(ci: CanvasItem, base: Vector2, s: float, species: String) -> void:
	var name := "scenery_snag_dead"
	match species:
		"pine", "pine_light":
			name = "scenery_pine_snowy" if Season.bare() else ("scenery_pine_light" if species == "pine_light" else "scenery_pine_green")
		"oak":
			name = "scenery_oak_bare" if Season.bare() else ("scenery_oak_fall" if Season.is_("fall") else ("scenery_oak_blossom" if Season.is_("spring") else "scenery_oak_summer"))
		"birch":
			name = "scenery_birch_bare" if Season.bare() else ("scenery_birch_fall" if Season.is_("fall") else "scenery_birch_summer")
	Sprites.draw_image(ci, name, base, false, 1.0, s * TREE_SCALE)


## A boulder: `size` is its scale, `h` a hash that picks the look (some are mossy; all are snowy in winter).
static func rock(ci: CanvasItem, base: Vector2, size: float, h: int) -> void:
	var name := "scenery_rock_snowy" if Season.bare() else ("scenery_rock_mossy" if h % 4 == 0 else "scenery_rock_grey")
	if size < 0.8 and not Season.bare():
		name = "scenery_rock_small"
	Sprites.draw_image(ci, name, base, h % 2 == 0, 1.0, clampf(size, 0.6, 1.4))
