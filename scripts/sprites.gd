class_name Sprites
extends RefCounted
## Rider sprite sheets, from the PixelLab characters in sprites/ (packed with tools/import_rider.gd). Sheets are looked
## up in user://art/ first (drop-in testing, mods), then res://art/.
##
## One rider = a set of sheets named after them: bike_<rider>.png ("bike_carla", "bike_rookie_girl", ...; the player
## is bike_rookie_boy or bike_rookie_girl, see player_sheet).
##   * Columns = animation frames, 8 rows = directions of travel:
##     down-right, down, down-left, left, up-left, up, up-right, right (the first is world +x, then turning 45 degrees
##     at a time; in the isometric view the diagonals are the ones you see on the roads).
##   * Frames are square, sheet height / 8 on a side. The wheels touch the ground at the bottom centre of the frame,
##     ANCHOR_UP pixels above its bottom edge. Drawn 1:1: one sprite pixel = one world pixel.
##   * Three looks: bike_<rider>_pizza.png is carrying a pizza, bike_<rider>_boxed.png rides around town with the
##     (empty) delivery bag and bike_<rider>.png (no bag) is the race look. A missing look falls back to the next.
##   * The wipe-out is the same three looks with _fall in the name (bike_<rider>_fall_pizza.png, _fall_boxed.png,
##     bike_<rider>_fall.png): frame 0 is the riding pose, then the rider tips over and ends up on the ground.

const DIRS := 8
const ANCHOR_UP := 12    # room below the contact point for the near wheel in the diagonal views
const FALL_FPS := 10.0   # fall frames per second; the last frame is held while the rider lies there
const STRIP_FEET_MARGIN := 4.0   # pixels below the feet in a strip frame (see tools/import_sprite.gd)
const VEHICLE_LIFT := 4.0        # a vehicle sprite's middle sits this far above its spot on the ground

## Every pedestrian design there may be art for (art/ped_<design>_walk.png and _cheer.png): the townsfolk, spectators
## and joggers. NORMAL_DESIGNS are ordinary people in everyday clothes; they make up most of any crowd (each counts
## NORMAL_WEIGHT times in pedestrians()), the characters in costume or uniform are the odd one out.
const NORMAL_DESIGNS := ["kid", "tourist", "grandpa", "lady", "teen", "grandma", "dad_stroller", "tourist_family",
	"norm_man_jeans", "norm_woman_sundress", "norm_man_plaid", "norm_woman_jeans_jacket", "norm_old_man_cane", "norm_old_woman",
	"norm_teen_girl", "norm_teen_boy", "norm_student", "norm_mom_bags", "norm_man_suit_casual", "norm_woman_sweater",
	"norm_man_heavy", "norm_woman_tall", "norm_couple_kid", "norm_man_shorts",
	"norm_man_windbreaker", "norm_woman_cardigan", "norm_man_overalls", "norm_woman_tracksuit", "norm_man_bald_glasses",
	"norm_woman_curly_hair", "norm_teen_skater_plain", "norm_man_fleece", "norm_woman_office", "norm_old_man_vest",
	"norm_woman_ponytail_runner_casual", "norm_man_denim_jacket", "norm_woman_hat_scarf", "norm_boy_kid",
	"norm_man_tall_thin", "norm_woman_short_hair",
	"grunge_teen", "neon_windbreaker", "fanny_pack", "mullet_dad", "scrunchie_girl", "bucket_hat_kid", "pager_guy"]
const CHARACTER_DESIGNS := ["jogger", "hiker", "surfer", "artist", "skater_kid", "businesswoman", "doctor", "musician",
	"baker", "cyclist_fan", "photographer", "mailman", "nurse", "dogwalker", "construction", "sweeper", "courier", "police",
	"gardener", "newsboy", "crossing_guard", "barista", "scout", "balloon_vendor",
	"rollerblader", "boombox", "walkman_jogger"]
const PEDESTRIAN_DESIGNS := NORMAL_DESIGNS + CHARACTER_DESIGNS
const NORMAL_WEIGHT := 4
static var _peds: Array = []


## The pedestrian designs that have art, ordinary people NORMAL_WEIGHT times over, so picking one at random (or by an
## index) mostly gives an everyday person.
static func pedestrians() -> Array:
	if _peds.is_empty():
		for d in PEDESTRIAN_DESIGNS:
			if sheet("ped_%s_walk" % d) != null and sheet("ped_%s_cheer" % d) != null:
				for k in (NORMAL_WEIGHT if d in NORMAL_DESIGNS else 1):
					_peds.append(d)
		if _peds.is_empty():
			_peds = ["kid"]
	return _peds


## The cast: nobody shows up twice on screen at once. Everyone drawn asks cast() for their look each frame; someone
## who was on screen last frame keeps theirs, and a newcomer gets the first look in their own (shuffled, everyday people
## first) order that nobody else on screen has. `options` limits the choice (the givers, firefighters, kid skiers...);
## when every option is taken it returns "" (skip drawing them), or options[0] when `must` (someone a scene needs).
## Designs only ever worn by a role (police, builders...) are left out of the everyday choice.
const ROLE_ONLY := ["police", "construction"]
static var _uid := 0
static var _cast_frame := -1
static var _cast_prev := {}     # uid -> look, last frame
static var _cast_now := {}      # uid -> look, this frame
static var _taken := {}         # look -> uid, this frame
static var _held := {}          # look -> uid that had it last frame
static var _everyone: Array = []
static var doubles := 0         # times someone had to be drawn in a look already on screen (debugging)


static func cast(person: Dictionary, options: Array = [], must := false) -> String:
	var f := Engine.get_process_frames()
	if f != _cast_frame:
		_cast_frame = f
		_cast_prev = _cast_now
		_cast_now = {}
		_taken = {}
		_held = {}
		for u in _cast_prev:
			_held[_cast_prev[u]] = u
	var u := uid(person)
	if _cast_now.has(u):
		return _cast_now[u]
	var pool: Array = options if not options.is_empty() else _order(person)
	var pick := ""
	var had: String = _cast_prev.get(u, "")
	if had != "" and had in pool and not _taken.has(had):
		pick = had
	else:
		for d in pool:
			if not _taken.has(d) and (not _held.has(d) or _held[d] == u):
				pick = d
				break
	if pick == "":
		if not must or pool.is_empty():
			return ""
		pick = pool[0]
		doubles += 1
	_taken[pick] = u
	_cast_now[u] = pick
	return pick


## A person's cast id (given on first sight).
static func uid(person: Dictionary) -> int:
	if not person.has("uid"):
		_uid += 1
		person["uid"] = _uid
	return person["uid"]


## A person's own order of everyday looks (cached on them): shuffled by their id, everyday people coming up more.
static func _order(person: Dictionary) -> Array:
	if person.has("order"):
		return person["order"]
	if _everyone.is_empty():
		for d in pedestrians():
			if not d in _everyone and not d in ROLE_ONLY:
				_everyone.append(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = uid(person) * 7919 + 13
	var weighted: Array = pedestrians().filter(func(d): return not d in ROLE_ONLY)
	var out: Array = []
	while out.size() < _everyone.size() and not weighted.is_empty():
		var d: String = weighted[rng.randi() % weighted.size()]
		if not d in out:
			out.append(d)
		weighted.erase(d)
	person["order"] = out
	return out


## The designs of `role` with art: the role itself and its numbered variants (construction, construction_2, ...).
static var _roles := {}
static func variants(role: String, sheet_suffix := "_walk", prefix := "ped_") -> Array:
	var key := prefix + role + sheet_suffix
	if not _roles.has(key):
		var out: Array = []
		for d in [role] + range(2, 9).map(func(k): return "%s_%d" % [role, k]) + ROLE_EXTRAS.get(role, []):
			if sheet(prefix + d + sheet_suffix) != null:
				out.append(d)
		_roles[key] = out
	return _roles[key]
const ROLE_EXTRAS := {"trumpeter": ["band_trumpeter_2"], "drummer": ["band_drummer_2"], "band_clarinet": ["band_flute"]}


## The gift-givers' looks (art/giver_<look>_wave.png).
const GIVER_LOOKS := ["red", "blue", "green", "yellow", "purple", "orange", "pink", "teal"]
static func givers() -> Array:
	return GIVER_LOOKS.filter(func(g): return sheet("giver_%s_wave" % g) != null)


## Everyone who skis or snowboards (art/ped_<design>_ski.png); kids: just the little ones.
static func skiers(kids := false) -> Array:
	var out: Array = []
	for d in ["skier_red", "skier_blue", "skier_retro", "skier_green", "skier_purple", "skier_orange", "skier_yellow", "snowboarder_green",
			"snowboarder_pink", "snowboarder_black", "snowboarder_teal", "ski_patrol", "skier_kid", "skier_kid_2", "skier_kid_3"]:
		if (not kids or d.begins_with("skier_kid")) and sheet("ped_%s_ski" % d) != null:
			out.append(d)
	return out


## True in cold weather (see Season.cold): characters then use their winter sheets (art/winter_<name>.png: hat, gloves
## and a jacket) when there is one.
static var cold := false

## Which character the player rides as: "rookie_boy" or "rookie_girl" (Game sets it).
static var player_sheet := "rookie_boy"

static var _cache := {}


## The texture for a sheet name ("bike_carla", ...), or null if there is no such art.
static func sheet(sheet_name: String) -> Texture2D:
	if _cache.has(sheet_name):
		return _cache[sheet_name]
	var tex: Texture2D = null
	for dir in ["user://art/", "res://art/"]:
		var path: String = dir + sheet_name + ".png"
		if dir == "res://art/" and ResourceLoader.exists(path):
			tex = load(path)   # imported by Godot (exported builds, or after the editor has seen the file)
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			break
	_cache[sheet_name] = tex
	return tex


## The sheet for a person or rider: the winter version in cold weather if there is one, else the usual one.
static func outfit(sheet_name: String) -> Texture2D:
	if cold:
		var w := sheet("winter_" + sheet_name)
		if w != null:
			return w
	return sheet(sheet_name)


## Forget loaded art (after new files were dropped in).
static func reload() -> void:
	_roles.clear()
	_everyone.clear()
	_cache.clear()
	_peds = []


## The row for a world heading (unit vector, world tiles).
static func dir_row(w: Vector2) -> int:
	return posmod(roundi(w.angle() / (PI / 4.0)), DIRS)


## The sheet name for a rider: "YOU" is the player's chosen character, anyone else their short name ("Carla").
static func sheet_name(who: String) -> String:
	return "bike_" + (player_sheet if who == "YOU" else who.to_lower())


const THROW_FPS := 14.0   # the pizza-frisbee throw (art/bike_<rider>_throw[_boxed].png), played once
static var _throws: Dictionary = {}   # sheet name -> msec the rider started throwing

## Starts `who`'s pizza-throwing animation ("YOU" or a rival's short name); draw_rider plays it once through.
static func start_throw(who: String) -> void:
	_throws[sheet_name(who)] = Time.get_ticks_msec()


## Draws the rider + bike. `c` = ground contact on screen, `w` = world heading. `boxed`: riding around town with the
## delivery bag (off in races). `fall_t` >= 0 plays the wipe-out, that many seconds in. Returns false (drawing
## nothing) when there is no art for this rider.
static func draw_rider(ci: CanvasItem, c: Vector2, w: Vector2, phase: float, has_pizza: bool, who: String, boxed := true, fall_t := -1.0) -> bool:
	var falling := fall_t >= 0.0
	var base := sheet_name(who) + ("_fall" if falling else "")
	var tex: Texture2D = null
	# mid-throw: the throw sheet (bag on the rack in town, plain bike in races), once through, then back to riding
	var throw_t := -1.0
	if not falling and _throws.has(base):
		throw_t = (Time.get_ticks_msec() - int(_throws[base])) / 1000.0
		var tn := base + ("_throw_boxed" if boxed else "_throw")
		tex = outfit(tn)
		# no winter throw for a rider in winter gear: don't flash back to summer clothes
		if cold and sheet("winter_" + tn) == null and sheet("winter_" + base + ("_boxed" if boxed else "")) != null:
			tex = null
		if tex == null or throw_t >= float(tex.get_width() / (tex.get_height() / DIRS)) / THROW_FPS:
			tex = null
			throw_t = -1.0
			_throws.erase(base)
	if tex == null:
		for suffix in (["_pizza", "_boxed", ""] if has_pizza else (["_boxed", ""] if boxed else [""])):
			tex = outfit(base + suffix)
			if tex != null:
				break
	if tex == null:
		return false
	var fh := tex.get_height() / DIRS
	var fw := fh
	var frames := maxi(1, tex.get_width() / fw)
	var col := clampi(int(fall_t * FALL_FPS), 0, frames - 1) if falling else posmod(int(floorf(phase / TAU * frames)), frames)
	if throw_t >= 0.0:
		col = clampi(int(throw_t * THROW_FPS), 0, frames - 1)
	var src := Rect2(col * fw, dir_row(w) * fh, fw, fh)
	var dst := Rect2((c - Vector2(fw * 0.5, fh - ANCHOR_UP)).round(), Vector2(fw, fh))
	ci.draw_texture_rect_region(tex, dst, src)
	return true


## An animation row (art/<name>.png, square frames side by side) drawn at the screen point `at`: standing on it with
## their feet there (`feet`, people and animals) or centred on it (a spinning pizza), mirrored left to right when `flip`,
## multiplied by `tint`. `t` is in seconds. Returns false when there is no such art.
static func draw_strip(ci: CanvasItem, name: String, at: Vector2, t: float, fps := 10.0, feet := true, flip := false, tint := Color.WHITE) -> bool:
	var tex := outfit(name)
	if tex == null:
		return false
	var fh := tex.get_height()
	var frames := maxi(1, tex.get_width() / fh)
	var src := Rect2(posmod(int(t * fps), frames) * fh, 0, fh, fh)
	var tl := (at - Vector2(fh * 0.5, fh - STRIP_FEET_MARGIN if feet else fh * 0.5)).round()
	if flip:
		_mirrored(ci, tl.x + fh * 0.5, func(): ci.draw_texture_rect_region(tex, Rect2(tl, Vector2(fh, fh)), src, tint))
	else:
		ci.draw_texture_rect_region(tex, Rect2(tl, Vector2(fh, fh)), src, tint)
	return true


const CHEER_FPS := 6.5   # a cheering person's jump (art/ped_<design>_cheer.png): about one hop every 1.2 s
static var _hops := {}    # cheer texture -> hops in one loop of its frames


## A cheering, jumping person (a ped_<design>_cheer strip). Some sheets hop twice in one loop; those play at half
## speed so everyone jumps at about the same, unhurried pace.
static func draw_cheer(ci: CanvasItem, name: String, at: Vector2, t: float) -> bool:
	var tex := outfit(name)
	if tex == null:
		return false
	if not _hops.has(tex):
		_hops[tex] = _count_hops(tex)
	return draw_strip(ci, name, at, t, CHEER_FPS / float(_hops[tex]))


## Times the feet leave the ground in one loop of a strip (at least 1).
static func _count_hops(tex: Texture2D) -> int:
	var img := tex.get_image()
	if img == null:
		return 1
	var fh := img.get_height()
	var frames := maxi(1, img.get_width() / fh)
	var feet: Array = []
	for k in frames:
		feet.append(img.get_region(Rect2i(k * fh, 0, fh, fh)).get_used_rect().end.y)
	var ground: int = feet.max()
	var hops := 0
	for k in frames:
		if ground - int(feet[k]) >= 3 and ground - int(feet[k - 1]) < 3:
			hops += 1
	return maxi(1, hops)


## A vehicle (art/<name>.png: 8 square rows, one per direction of travel as in the rider sheets; columns are the frames
## of its driving animation, if it has one) with its middle on `at`, heading `w` (world direction), tinted by `tint`.
## `frame` picks the animation frame (it wraps).
## `on_road`: lay a diagonal view along the road. The sprites' diagonals are drawn at 45 degrees, but a road along the
## town's grid runs at the isometric 2:1 slope on screen, so a car on it looked crooked; those rows are sheared to
## the road's slope about the car's middle (the straight-up/down and sideways rows already line up). `scale` shrinks
## it about the same point.
static func draw_vehicle(ci: CanvasItem, name: String, at: Vector2, w: Vector2, tint := Color.WHITE, frame := 0, on_road := false, scale := 1.0) -> bool:
	var tex := sheet(name)
	if tex == null:
		return false
	var f := tex.get_height() / DIRS
	var frames := maxi(1, tex.get_width() / f)
	var row := dir_row(w)
	var src := Rect2(posmod(frame, frames) * f, row * f, f, f)
	var dst := Rect2((at - Vector2(f * 0.5, f * 0.5 + VEHICLE_LIFT)).round(), Vector2(f, f))
	if not on_road and scale == 1.0:
		ci.draw_texture_rect_region(tex, dst, src, tint)
		return true
	# rows 0 and 4 (world +x / -x) run down-right / up-left on screen, rows 2 and 6 (world +y / -y) down-left / up-right
	var k := 0.0
	if on_road:
		k = -0.5 if row == 0 or row == 4 else (0.5 if row == 2 or row == 6 else 0.0)
	var c := (at - Vector2(0, VEHICLE_LIFT)).round()
	var xf := Transform2D(Vector2(scale, k * scale), Vector2(0, scale), Vector2.ZERO)
	xf.origin = c - xf.basis_xform(c)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture_rect_region(tex, dst, src, tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


## A person (art/<name>.png: 8 square rows of directions as in the rider sheets, frames across; see
## tools/import_sprite.gd people) standing with their feet on `at`, walking towards the world direction `w`. `t` is in
## seconds.
static func draw_person(ci: CanvasItem, name: String, at: Vector2, w: Vector2, t: float, fps := 8.0, tint := Color.WHITE) -> bool:
	var tex := outfit(name)
	if tex == null:
		return false
	var f := tex.get_height() / DIRS
	var frames := maxi(1, tex.get_width() / f)
	var src := Rect2(posmod(int(t * fps), frames) * f, dir_row(w) * f, f, f)
	ci.draw_texture_rect_region(tex, Rect2((at - Vector2(f * 0.5, f - STRIP_FEET_MARGIN)).round(), Vector2(f, f)), src, tint)
	return true


## A single picture (art/<name>.png) with the middle of its bottom edge on `at`, optionally mirrored left to right,
## scaled by `scale` and faded to `alpha`. Returns false when there is none.
static func draw_image(ci: CanvasItem, name: String, at: Vector2, flip := false, alpha := 1.0, scale := 1.0) -> bool:
	var tex := sheet(name)
	if tex == null:
		return false
	var w := float(tex.get_width()) * scale
	var h := float(tex.get_height()) * scale
	var top_left := (at - Vector2(w * 0.5, h)).round()
	if flip:
		_mirrored(ci, top_left.x + w * 0.5, func(): ci.draw_texture_rect(tex, Rect2(top_left, Vector2(w, h)), false, Color(1, 1, 1, alpha)))
	else:
		ci.draw_texture_rect(tex, Rect2(top_left, Vector2(w, h)), false, Color(1, 1, 1, alpha))
	return true


## Runs `fn` (some drawing) mirrored left to right about the vertical line x = `mid`. (A negative-width rect doesn't
## mirror in place, it lands a whole width to one side.)
static func _mirrored(ci: CanvasItem, mid: float, fn: Callable) -> void:
	ci.draw_set_transform(Vector2(2.0 * mid, 0.0), 0.0, Vector2(-1.0, 1.0))
	fn.call()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
