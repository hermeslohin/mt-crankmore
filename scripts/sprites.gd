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
## How faded in everything drawn is (1 = fully there): someone stepping out of a door or into a van fades in or out.
static var fade := 1.0


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
## when every option is taken it returns "" (skip drawing them), or, when `must` (someone a scene needs), a double: a
## look someone else on screen has too. A double keeps that look while on screen (and never takes it off whoever had
## it first), so nobody ever changes look in front of you.
## Designs only ever worn by a role (police, builders...) are left out of the everyday choice.
const ROLE_ONLY := ["police", "construction"]
static var _uid := 0
static var _cast_frame := -1
static var _cast_prev := {}     # uid -> look, last frame
static var _cast_now := {}      # uid -> look, this frame
static var _taken := {}         # look -> uid, this frame
static var _held := {}          # look -> uid that had it last frame
static var _hid_prev := {}      # uids left out last frame (nobody to be): they stay out until they've left the screen
static var _hid_now := {}
static var _dbl_prev := {}      # uids drawn as a double last frame
static var _dbl_now := {}
static var _everyone: Array = []
static var doubles := 0         # times someone had to be drawn in a look already on screen (debugging)


static func cast(person: Dictionary, options: Array = [], must := false) -> String:
	var f := Engine.get_process_frames()
	if f != _cast_frame:
		_cast_frame = f
		_cast_prev = _cast_now
		_cast_now = {}
		_hid_prev = _hid_now
		_hid_now = {}
		_dbl_prev = _dbl_now
		_dbl_now = {}
		_taken = {}
		_held = {}
		for u in _cast_prev:   # (whoever had a look first holds it; a double only when nobody else has it any more)
			if not _dbl_prev.has(u):
				_held[_cast_prev[u]] = u
		for u in _dbl_prev:
			if not _held.has(_cast_prev[u]):
				_held[_cast_prev[u]] = u
	var u := uid(person)
	if _cast_now.has(u):
		return _cast_now[u]
	var pool: Array = options if not options.is_empty() else _order(person)
	var pick := ""
	var had: String = _cast_prev.get(u, "")
	if had != "" and had in pool and _dbl_prev.has(u) and _held.get(had, u) != u:
		# still a double: they keep their look
		doubles += 1
		_dbl_now[u] = true
		_cast_now[u] = had
		return had
	if had != "" and had in pool and not _taken.has(had):
		pick = had
	else:
		for d in pool:
			if not _taken.has(d) and (not _held.has(d) or _held[d] == u):
				pick = d
				break
	if pick == "" or (not _cast_prev.has(u) and _hid_prev.has(u) and not must):
		# no look for them: they're left out, and stay out while on screen (no popping in when one frees up)
		if not must or pool.is_empty():
			_hid_now[u] = true
			return ""
		if pick == "":
			# nobody free to be: a double, in a look nobody's been given yet this frame if there is one
			pick = pool[0]
			for d in pool:
				if not _taken.has(d):
					pick = d
					break
			doubles += 1
			_dbl_now[u] = true
			_cast_now[u] = pick
			return pick
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
		# the picture itself when it's there (running from the project folder): Godot's imported copy only catches up
		# when the editor looks, so it can be an old version of art that's been changed since
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				tex = ImageTexture.create_from_image(img)
		elif dir == "res://art/" and ResourceLoader.exists(path):
			tex = load(path)   # imported by Godot (an exported build has only these)
		if tex != null:
			break
	_cache[sheet_name] = tex
	if tex != null:
		_names[tex] = sheet_name
	return tex
static var _names := {}   # texture -> the sheet name it was loaded as


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
	_turns.clear()
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
	pizza_top = Vector2.INF
	var with_pizza := false
	if tex == null:
		for suffix in (["_pizza", "_boxed", ""] if has_pizza else (["_boxed", ""] if boxed else [""])):
			tex = outfit(base + suffix)
			if tex != null:
				with_pizza = suffix == "_pizza"
				break
	if tex == null:
		return false
	var fh := tex.get_height() / DIRS
	var fw := fh
	var frames := maxi(1, tex.get_width() / fw)
	var col := clampi(int(fall_t * FALL_FPS), 0, frames - 1) if falling else posmod(int(floorf(phase / TAU * frames)), frames)
	if throw_t >= 0.0:
		col = clampi(int(throw_t * THROW_FPS), 0, frames - 1)
	var dst := Rect2((c - Vector2(fw * 0.5, fh - ANCHOR_UP)).round(), Vector2(fw, fh))
	var key := "%d/%s" % [ci.get_instance_id(), who]   # each rider is one of a kind in a scene
	if not _rider_turns.has(key):
		_rider_turns[key] = {}
	var rows := turn_rows(_rider_turns[key], w)
	_draw_turning(ci, tex, dst, col * fw, fw, fh, rows, Color.WHITE)
	if with_pizza:
		var spot := _pizza_spot(tex, outfit(base + "_boxed"), int(rows[0]), col)
		if spot != Vector2.INF:
			pizza_top = dst.position + spot
	return true


## Where the pizza is in the frame draw_rider just drew (its top middle, on screen), Vector2.INF if no pizza: for the
## steam (BikeDraw). Found by comparing the pizza sheet with the same rider's empty-box sheet: the difference is the
## pizza, frame by frame.
static var pizza_top := Vector2.INF
static var _pizza_spots := {}   # pizza texture -> {cell index: top-middle of the pizza in the cell, or INF}


static func _pizza_spot(tp: Texture2D, tb: Texture2D, row: int, col: int) -> Vector2:
	if tb == null:
		return Vector2.INF
	if not _pizza_spots.has(tp):
		_pizza_spots[tp] = {}
	var cache: Dictionary = _pizza_spots[tp]
	var key := row * 64 + col
	if cache.has(key):
		return cache[key]
	var spot := Vector2.INF
	var ip := tp.get_image()
	var ib := tb.get_image()
	if ip != null and ib != null and ip.get_size() == ib.get_size():
		var fh := ip.get_height() / DIRS
		var x0 := col * fh
		var y0 := row * fh
		var lo := Vector2i(fh, fh)
		var hi := Vector2i(-1, -1)
		for y in fh:
			for x in fh:
				var a := ip.get_pixel(x0 + x, y0 + y)
				var b := ib.get_pixel(x0 + x, y0 + y)
				# a pixel that's different in the pizza sheet and pizza-coloured (cheese, crust, sauce, pepperoni)
				var pizza_col := a.r > 0.55 and a.b < 0.45 and a.r > a.b + 0.25
				if a.a > 0.5 and pizza_col and (b.a < 0.5 or absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.3):
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if hi.x >= 0 and (hi - lo).x < fh / 2:   # a pizza-sized patch, not a whole different pose
			spot = Vector2((lo.x + hi.x) * 0.5, lo.y + 1.0)
	cache[key] = spot
	return spot


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
	tint.a *= fade
	_mark(Rect2(tl, Vector2(fh, fh)), tint.a)
	if flip:
		_mirrored(ci, tl.x + fh * 0.5, func(): ci.draw_texture_rect_region(tex, Rect2(tl, Vector2(fh, fh)), src, tint))
	else:
		ci.draw_texture_rect_region(tex, Rect2(tl, Vector2(fh, fh)), src, tint)
	return true


## Each bystander's other ways of cheering you on as you ride past, besides jumping: the moves their art was made from,
## art/ped_<design>_pass.png, _pass2.png, _pass3.png... in order (strips like _cheer; winter_ped_... in winter).
## A move without art is skipped; with none they just jump.
const PASS_MOVES := {
	"kid": ["jumping fist pump", "victory V signs with both hands", "pointing at you and cheering"],
	"tourist": ["waving a small flag", "spinning around once with arms out", "deep theatrical bow"],
	"grandpa": ["thumbs up", "big two-arm wave", "salute"],
	"lady": ["clapping overhead", "waving one arm in big circles", "throwing confetti"],
	"teen": ["raise the roof", "victory V signs with both hands", "pointing at you and cheering"],
	"grandma": ["waving a handkerchief", "deep theatrical bow", "pumping both fists"],
	"dad_stroller": ["thumbs up", "salute", "doing the running man dance"],
	"tourist_family": ["waving both arms", "throwing confetti", "double thumbs up"],
	"norm_man_jeans": ["fist pump", "cupped hands shouting", "pointing at you and cheering"],
	"norm_woman_sundress": ["blowing a kiss and waving", "pumping both fists", "jumping fist pump"],
	"norm_man_plaid": ["flexing both biceps", "doing the running man dance", "dab"],
	"norm_woman_jeans_jacket": ["double thumbs up", "dancing a little happy jig", "air punching"],
	"norm_old_man_cane": ["raising his cane", "hands on head in amazement", "pointing at you and cheering"],
	"norm_old_woman": ["clapping", "jumping fist pump", "shaking pom-pom fists"],
	"norm_teen_girl": ["pointing at you and cheering", "dab", "blowing a kiss and waving"],
	"norm_teen_boy": ["air guitar", "dancing a little happy jig", "raise the roof"],
	"norm_student": ["waving a pennant flag", "pointing at you and cheering", "flexing both biceps"],
	"norm_mom_bags": ["thumbs up", "shaking pom-pom fists", "bouncing on the spot clapping"],
	"norm_man_suit_casual": ["salute", "blowing a kiss and waving", "clapping overhead"],
	"norm_woman_sweater": ["cupped hands shouting", "air punching", "raise the roof"],
	"norm_man_heavy": ["flexing both biceps", "high kick", "waving one arm in big circles"],
	"norm_woman_tall": ["big two-arm wave", "bouncing on the spot clapping", "jumping jacks"],
	"norm_couple_kid": ["fist pump", "clapping overhead", "spinning around once with arms out"],
	"norm_man_shorts": ["waving a towel overhead", "raise the roof", "big two-arm wave"],
	"norm_man_windbreaker": ["double fist pump", "high kick", "waving one arm in big circles"],
	"norm_woman_cardigan": ["clapping overhead", "jumping jacks", "victory V signs with both hands"],
	"norm_man_overalls": ["waving his cap", "spinning around once with arms out", "deep theatrical bow"],
	"norm_woman_tracksuit": ["running in place and pumping fists", "big two-arm wave", "salute"],
	"norm_man_bald_glasses": ["thumbs up", "waving one arm in big circles", "throwing confetti"],
	"norm_woman_curly_hair": ["jumping star jump", "victory V signs with both hands", "pointing at you and cheering"],
	"norm_teen_skater_plain": ["raise the roof", "deep theatrical bow", "pumping both fists"],
	"norm_man_fleece": ["ringing a cowbell", "salute", "doing the running man dance"],
	"norm_woman_office": ["waving a scarf", "throwing confetti", "double thumbs up"],
	"norm_old_man_vest": ["salute", "cupped hands shouting", "pointing at you and cheering"],
	"norm_woman_ponytail_runner_casual": ["fist pump", "pumping both fists", "bouncing on the spot clapping"],
	"norm_man_denim_jacket": ["pointing at you", "doing the running man dance", "dab"],
	"norm_woman_hat_scarf": ["waving her hat", "double thumbs up", "dancing a little happy jig"],
	"norm_boy_kid": ["flexing both biceps", "hands on head in amazement", "pointing at you and cheering"],
	"norm_man_tall_thin": ["big two-arm wave", "jumping fist pump", "shaking pom-pom fists"],
	"norm_woman_short_hair": ["double thumbs up", "dab", "blowing a kiss and waving"],
	"grunge_teen": ["rock-on horns with both hands", "dancing a little happy jig", "air punching"],
	"neon_windbreaker": ["waving a neon flag", "pointing at you and cheering", "flexing both biceps"],
	"fanny_pack": ["thumbs up", "shaking pom-pom fists", "bouncing on the spot clapping"],
	"mullet_dad": ["flexing both biceps", "blowing a kiss and waving", "clapping overhead"],
	"scrunchie_girl": ["clapping", "air punching", "raise the roof"],
	"bucket_hat_kid": ["jumping fist pump", "flexing both biceps", "high kick"],
	"pager_guy": ["cupped hands shouting", "bouncing on the spot clapping", "jumping jacks"],
	"jogger": ["running in place and pumping fists", "clapping overhead", "spinning around once with arms out"],
	"hiker": ["raising trekking pole", "raise the roof", "big two-arm wave"],
	"surfer": ["shaka sign with both hands", "high kick", "waving one arm in big circles"],
	"artist": ["waving paintbrush", "jumping jacks", "victory V signs with both hands"],
	"skater_kid": ["raise the roof", "spinning around once with arms out", "deep theatrical bow"],
	"businesswoman": ["fist pump", "big two-arm wave", "salute"],
	"doctor": ["thumbs up", "waving one arm in big circles", "throwing confetti"],
	"musician": ["air guitar", "victory V signs with both hands", "pointing at you and cheering"],
	"baker": ["waving rolling pin", "deep theatrical bow", "pumping both fists"],
	"cyclist_fan": ["waving a big flag", "salute", "doing the running man dance"],
	"photographer": ["taking a photo", "throwing confetti", "double thumbs up"],
	"mailman": ["salute", "cupped hands shouting", "pointing at you and cheering"],
	"nurse": ["double thumbs up", "pumping both fists", "jumping fist pump"],
	"dogwalker": ["big wave", "doing the running man dance", "dab"],
	"construction": ["flexing both biceps", "double thumbs up", "dancing a little happy jig"],
	"sweeper": ["raising broom overhead", "hands on head in amazement", "pointing at you and cheering"],
	"courier": ["fist pump", "shaking pom-pom fists", "bouncing on the spot clapping"],
	"police": ["thumbs up", "dab", "blowing a kiss and waving"],
	"gardener": ["waving trowel", "dancing a little happy jig", "air punching"],
	"newsboy": ["waving newspaper", "pointing at you and cheering", "flexing both biceps"],
	"crossing_guard": ["waving stop sign", "shaking pom-pom fists", "bouncing on the spot clapping"],
	"barista": ["raising coffee cup", "blowing a kiss and waving", "clapping overhead"],
	"scout": ["salute", "air punching", "raise the roof"],
	"balloon_vendor": ["waving balloons", "flexing both biceps", "high kick"],
	"rollerblader": ["spinning and pointing", "bouncing on the spot clapping", "jumping jacks"],
	"boombox": ["lifting boombox overhead", "spinning around once with arms out", "deep theatrical bow"],
	"walkman_jogger": ["fist pump", "raise the roof", "big two-arm wave"],
	"fan_sign": ["shaking the sign overhead", "high kick", "waving one arm in big circles"],
	"fan_flag": ["waving the flag in big circles", "jumping jacks", "victory V signs with both hands"],
	"fan_cowbell": ["ringing cowbell overhead", "spinning around once with arms out", "deep theatrical bow"],
	"fan_highfive_kid": ["holding out a hand for a high five", "big two-arm wave", "salute"],
}
const PASS_FPS := 8.0


## One of a bystander's other cheers (move `k` of PASS_MOVES). False when there is no art for it.
static func draw_pass(ci: CanvasItem, design: String, at: Vector2, t: float, k := 0) -> bool:
	return draw_strip(ci, pass_sheet(design, k), at, t, PASS_FPS)


static func pass_sheet(design: String, k: int) -> String:
	return "ped_%s_pass%s" % [design, "" if k == 0 else str(k + 1)]


## Which way someone cheers, from a random `roll` kept for the whole cheer: -1 for the jump, else one of their
## PASS_MOVES with art, each as likely.
static func cheer_way(design: String, roll: int) -> int:
	var ways := [-1]
	for k in PASS_MOVES.get(design, []).size():
		if sheet(pass_sheet(design, k)) != null:
			ways.append(k)
	return ways[posmod(roll, ways.size())]


## Someone cheering: their jump or one of their other cheers (see cheer_way).
static func draw_any_cheer(ci: CanvasItem, design: String, at: Vector2, t: float, roll: int) -> void:
	var k := cheer_way(design, roll)
	if k < 0 or not draw_pass(ci, design, at, t, k):
		draw_cheer(ci, "ped_%s_cheer" % design, at, t)


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
## `state`: the vehicle's own dictionary, to keep its turning smooth (see turn_rows).
static func draw_vehicle(ci: CanvasItem, name: String, at: Vector2, w: Vector2, tint := Color.WHITE, frame := 0, state: Dictionary = {}) -> bool:
	var tex := sheet(name)
	if tex == null:
		return false
	var f := tex.get_height() / DIRS
	var frames := maxi(1, tex.get_width() / f)
	var dst := Rect2((at - Vector2(f * 0.5, f * 0.5 + VEHICLE_LIFT)).round(), Vector2(f, f))
	_draw_turning(ci, tex, dst, posmod(frame, frames) * f, f, f, turn_rows(state, w), tint)
	return true


## A person (art/<name>.png: 8 square rows of directions as in the rider sheets, frames across; see
## tools/import_sprite.gd people) standing with their feet on `at`, walking towards the world direction `w`. `t` is in
## seconds.
static func draw_person(ci: CanvasItem, name: String, at: Vector2, w: Vector2, t: float, fps := 8.0, tint := Color.WHITE, state: Dictionary = {}) -> bool:
	var tex := outfit(name)
	if tex == null:
		return false
	var f := tex.get_height() / DIRS
	var frames := maxi(1, tex.get_width() / f)
	var dst := Rect2((at - Vector2(f * 0.5, f - STRIP_FEET_MARGIN)).round(), Vector2(f, f))
	_draw_turning(ci, tex, dst, posmod(int(t * fps), frames) * f, f, f, turn_rows(state, w), tint)
	return true


## Smooth turning for anything drawn in the 8 directions. A view only changes once the heading is TURN_LAG past the
## halfway point between two views (no flicker on a gentle curve), and then the new view fades in over the old one for
## TURN_FADE seconds. `st` is the thing's own dictionary (its turn is kept there); empty means no smoothing.
## Returns [view row, previous view row, how far the new one has faded in 0-1].
const TURN_LAG := 0.12    # radians, about 7 degrees
const TURN_FADE := 0.2    # seconds (a turn clip's 4 frames play over this too)
const TURN_SETTLE := 0.35 # seconds a heading must stay in another view's range to turn to it inside the lag
static var _rider_turns := {}


## A lasting turn dictionary for something drawn by name with nowhere of its own to keep it (one of a kind in a
## scene: the TV moto, the snowcat...), for draw_vehicle / draw_person's `state`.
static func turn_state(key: String) -> Dictionary:
	if not _named_turns.has(key):
		_named_turns[key] = {}
	return _named_turns[key]
static var _named_turns := {}


## The turn clip for a sheet (art/<name>_turn.png next to it), or null. Found by the name the sheet was loaded as, so
## outfits (winter_...) and colour variants (_c2...) get theirs.
static var _turns := {}
static func _turn_sheet(tex: Texture2D) -> Texture2D:
	if _turns.has(tex):
		return _turns[tex]
	var t: Texture2D = null
	if _names.has(tex) and not str(_names[tex]).ends_with("_turn"):
		t = sheet(str(_names[tex]) + "_turn")
	_turns[tex] = t
	return t


static func turn_rows(st: Dictionary, w: Vector2) -> Array:
	var want := dir_row(w)
	if st.is_read_only():
		return [want, want, 1.0]
	var now := Time.get_ticks_msec() / 1000.0
	if not st.has("_row"):
		st["_row"] = want
		st["_prev"] = want
		st["_at"] = -10.0
	var cur: int = st["_row"]
	# a heading that has settled in another view's range turns too, even inside the lag: a road at an angle near the
	# halfway point would otherwise keep the old view for as long as you're on it (a car sliding sideways)
	if want == cur:
		st["_want"] = -1
	elif int(st.get("_want", -1)) != want:
		st["_want"] = want
		st["_want_at"] = now
	var settled := want != cur and now - float(st.get("_want_at", now)) >= TURN_SETTLE
	# a big swing (a U-turn, a hairpin) goes round one view at a time, each step finishing before the next
	if want != cur and (settled or absf(angle_difference(cur * PI / 4.0, w.angle())) > PI / 8.0 + TURN_LAG) and now - float(st["_at"]) >= TURN_FADE:
		var step := posmod(want - cur, DIRS)
		var next := posmod(cur + (1 if step <= DIRS / 2 else -1), DIRS)
		st["_prev"] = cur
		st["_row"] = next
		st["_at"] = now
	return [st["_row"], st["_prev"], clampf((now - float(st["_at"])) / TURN_FADE, 0.0, 1.0)]


## One frame (column `x`) of an 8-row sheet in the view `rows` gives (see turn_rows): mid-turn, the new view over the
## old one, fading in.
static func _draw_turning(ci: CanvasItem, tex: Texture2D, dst: Rect2, x: float, fw: float, fh: float, rows: Array, tint: Color) -> void:
	tint.a *= fade
	_mark(dst, tint.a)
	var from := int(rows[1])
	var to := int(rows[0])
	if float(rows[2]) < 1.0 and from != to:
		# a turn clip (art/<sheet>_turn.png: row k turns from view k to view k+1, 4 in-between frames) when there is one,
		# played backwards turning the other way
		var turn := _turn_sheet(tex)
		var step := posmod(to - from, DIRS)
		if turn != null and (step == 1 or step == DIRS - 1):
			var tf := float(turn.get_height() / DIRS)
			var n := maxi(1, int(turn.get_width() / tf))
			var i := mini(int(float(rows[2]) * n), n - 1)
			var row := from if step == 1 else to
			var col := i if step == 1 else n - 1 - i
			var td := Rect2((dst.get_center() - Vector2(tf, tf) * 0.5).round(), Vector2(tf, tf)) if tf != dst.size.x else dst
			ci.draw_texture_rect_region(turn, td, Rect2(col * tf, row * tf, tf, tf), tint)
			return
		ci.draw_texture_rect_region(tex, dst, Rect2(x, int(rows[1]) * fh, fw, fh), tint)
		ci.draw_texture_rect_region(tex, dst, Rect2(x, int(rows[0]) * fh, fw, fh), Color(tint.r, tint.g, tint.b, tint.a * float(rows[2])))
	else:
		ci.draw_texture_rect_region(tex, dst, Rect2(x, int(rows[0]) * fh, fw, fh), tint)


## A single picture (art/<name>.png) with the middle of its bottom edge on `at`, optionally mirrored left to right,
## scaled by `scale` and faded to `alpha`. Returns false when there is none.
static func draw_image(ci: CanvasItem, name: String, at: Vector2, flip := false, alpha := 1.0, scale := 1.0) -> bool:
	var tex := sheet(name)
	if tex == null:
		return false
	var w := float(tex.get_width()) * scale
	var h := float(tex.get_height()) * scale
	var top_left := (at - Vector2(w * 0.5, h)).round()
	alpha *= fade
	_mark(Rect2(top_left, Vector2(w, h)), alpha)
	if flip:
		_mirrored(ci, top_left.x + w * 0.5, func(): ci.draw_texture_rect(tex, Rect2(top_left, Vector2(w, h)), false, Color(1, 1, 1, alpha)))
	else:
		ci.draw_texture_rect(tex, Rect2(top_left, Vector2(w, h)), false, Color(1, 1, 1, alpha))
	return true


## Dev helper (PIZZA_POPS, see tools/pop_watch.gd): while `marking`, the screen rect and strongest alpha of what's drawn.
static var marking := false
static var marked := Rect2()
static var marked_a := 0.0
static func _mark(r: Rect2, a: float) -> void:
	if marking:
		marked = r if marked_a <= 0.0 else marked.merge(r)
		marked_a = maxf(marked_a, maxf(a, 0.001))


## Runs `fn` (some drawing) mirrored left to right about the vertical line x = `mid`. (A negative-width rect doesn't
## mirror in place, it lands a whole width to one side.)
static func _mirrored(ci: CanvasItem, mid: float, fn: Callable) -> void:
	ci.draw_set_transform(Vector2(2.0 * mid, 0.0), 0.0, Vector2(-1.0, 1.0))
	fn.call()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
