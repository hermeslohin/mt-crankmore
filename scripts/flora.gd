class_name Flora
extends RefCounted
## Trees, bushes, flowers and rocks: pictures from PixelLab (art/flora_<group>_<n>.png and the older
## art/scenery_<name>.png, sources in sprites/flora/ and sprites/scenery/) that change with the season. Every species
## has several looks for each season, and `h` (a hash of the spot) picks one, so no two stands of trees look alike.
## A picture stands with the middle of its bottom edge on the spot it is drawn at.

const TREE_SCALE := 0.9   # the pictures are drawn a little smaller than they were made, times each tree's own size

## Tree species: the town and the mountain map their own tree kinds onto these.
const SPECIES := ["pine", "pine_light", "oak", "birch", "snag", "maple", "aspen", "larch", "cherry", "willow", "spruce", "fir", "stump"]

static var _names := {}   # group -> picture names that exist


## The pictures there are for a group of flora ("pine", "oak_fall", ...): flora_<group>, flora_<group>_1, _2, ...
static func variants(group: String) -> Array:
	if not _names.has(group):
		var out: Array = []
		if Sprites.sheet("flora_" + group) != null:
			out.append("flora_" + group)
		for n in range(1, 10):
			if Sprites.sheet("flora_%s_%d" % [group, n]) != null:
				out.append("flora_%s_%d" % [group, n])
		_names[group] = out
	return _names[group]


static func reload() -> void:
	_names.clear()


## One picture out of the groups (and the older single pictures in `legacy` that exist), chosen by `h`.
static func _pick(groups: Array, legacy: Array, h: int) -> String:
	var all: Array = []
	for g in groups:
		all.append_array(variants(g))
	for l in legacy:
		if Sprites.sheet(l) != null:
			all.append(l)
	return "" if all.is_empty() else all[posmod(h, all.size())]


## [groups, legacy pictures] a tree of `species` can be drawn from in the current season (`snowy`: up in the snow).
static func _tree_groups(species: String, snowy: bool) -> Array:
	var season := "winter" if Season.bare() else Season.current
	if species == "snag":
		return [["snag"], ["scenery_snag_dead"]]
	if species == "stump":
		return [["stump"], ["scenery_snag_dead"]]
	if snowy or (season == "winter" and species in ["pine", "pine_light", "spruce", "fir", "larch"]):
		return [["pine_snowy"], ["scenery_pine_snowy"]]
	match species:
		"pine":
			return [["pine"], ["scenery_pine_green"]]
		"pine_light":
			return [["pine"], ["scenery_pine_light"]]
		"spruce":
			return [["spruce_blue"], ["scenery_pine_green"]]
		"fir":
			return [["fir_tall"], ["scenery_pine_light"]]
		"larch":
			return [["larch_gold"], ["scenery_pine_light"]] if season == "fall" else [["pine"], ["scenery_pine_green"]]
		"oak":
			match season:
				"winter": return [["oak_bare"], ["scenery_oak_bare"]]
				"fall": return [["oak_fall"], ["scenery_oak_fall"]]
				"spring": return [["oak_blossom"], ["scenery_oak_blossom"]]
			return [["oak_summer"], ["scenery_oak_summer"]]
		"birch":
			match season:
				"winter": return [["birch_bare"], ["scenery_birch_bare"]]
				"fall": return [["birch_fall"], ["scenery_birch_fall"]]
			return [["birch_summer"], ["scenery_birch_summer"]]
		"maple":
			match season:
				"winter": return [["oak_bare"], ["scenery_oak_bare"]]
				"fall": return [["maple_red"], ["scenery_oak_fall"]]
			return [["oak_summer"], ["scenery_oak_summer"]]
		"aspen":
			match season:
				"winter": return [["birch_bare"], ["scenery_birch_bare"]]
				"fall": return [["aspen_gold"], ["scenery_birch_fall"]]
			return [["aspen_summer", "birch_summer"], ["scenery_birch_summer"]]
		"cherry":
			match season:
				"winter": return [["oak_bare"], ["scenery_oak_bare"]]
				"fall": return [["oak_fall"], ["scenery_oak_fall"]]
				"spring": return [["cherry_blossom"], ["scenery_oak_blossom"]]
			return [["oak_summer"], ["scenery_oak_summer"]]
		"willow":
			return [["oak_bare"], ["scenery_oak_bare"]] if season == "winter" else [["willow"], ["scenery_oak_summer"]]
	return [["pine"], ["scenery_pine_green"]]


## A tree of `species` (see SPECIES) at `base`, `s` times its usual size: snow-laden firs and bare trees in winter
## (or snow-laden firs wherever `snowy`: up the mountain), blossom in spring, red and gold in fall. `h` picks the look.
static func tree(ci: CanvasItem, base: Vector2, s: float, species: String, snowy := false, h := 0) -> void:
	var g := _tree_groups(species, snowy)
	var name := _pick(g[0], g[1], h)
	if name != "":
		Sprites.draw_image(ci, name, base, h % 3 == 0, 1.0, s * TREE_SCALE)


## A boulder: `size` is its scale, `h` a hash that picks the look (snowy in winter or up in the snow).
static func rock(ci: CanvasItem, base: Vector2, size: float, h: int, snowy := false) -> void:
	var name := ""
	if Season.bare() or snowy:
		name = _pick(["rock_snowy"], ["scenery_rock_snowy"], h)
	elif size < 0.8:
		name = _pick([], ["scenery_rock_small"], h)
	else:
		name = _pick(["rock_cliff"] if h % 7 == 0 else ["boulder"], ["scenery_rock_mossy", "scenery_rock_grey"], h)
	Sprites.draw_image(ci, name, base, h % 2 == 0, 1.0, clampf(size, 0.6, 1.4))


## Small plants and ground cover: "bush", "flowers", "grass", "reeds" (creek banks), "mushrooms" or "stones" (wet
## creek stones). Returns false when there is nothing of that kind for this season (no flowers in the snow).
static func plant(ci: CanvasItem, base: Vector2, kind: String, h: int, snowy := false, scale := 1.0) -> bool:
	var season := "winter" if Season.bare() or snowy else Season.current
	var name := ""
	match kind:
		"bush":
			if season == "winter":
				name = _pick(["bush_snowy"], [], h)
			elif season == "fall":
				name = _pick(["bush_fall", "bush_juniper", "bush_berry"], ["scenery_bush_green"], h)
			else:
				name = _pick(["bush_berry", "bush_juniper", "bush_fern", "bush_heather", "bush_gorse"], ["scenery_bush_green", "scenery_bush_flowers"], h)
		"flowers":
			match season:
				"spring": name = _pick(["flowers_forgetmenot", "flowers_bluebell", "flowers_daisy"], ["scenery_tulips_pink", "scenery_tulips_yellow"], h)
				"summer": name = _pick(["flowers_lupine", "flowers_poppy", "flowers_daisy", "flowers_fireweed", "flowers_sunflower", "flowers_alpine"], [], h)
				"fall": name = _pick(["mushrooms"], [], h)
		"grass":
			if season != "winter":
				name = _pick(["grass_tall"], [], h)
		"reeds":
			if season != "winter":
				name = _pick(["reeds"], [], h)
		"mushrooms":
			if season == "fall" or season == "spring":
				name = _pick(["mushrooms"], [], h)
		"stones":
			name = _pick(["creek_stones"], [], h)
	if name == "":
		return false
	Sprites.draw_image(ci, name, base, h % 2 == 0, 1.0, scale)
	return true
