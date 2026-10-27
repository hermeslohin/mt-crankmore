extends RefCounted
## Dev helper (PIZZA_POPS=<frames>, with PIZZA_DEBUG=city; runs headless too): watches everything the town draws and
## prints whatever pops: appears or vanishes in place while on screen, jumps across the screen or changes its look,
## with why (removed, culled, not drawn, inside, ...), and a summary every <frames> frames (1: every 1800).
## PIZZA_POPS_EVENTS=1 also sets off a happening every 15 s, each kind in turn, as it would start by itself.
## City._draw_world calls begin / end round each thing it draws and finish after; Sprites marks what's drawn.

var city: Node2D
var every := 1800
var prev := {}          # id -> [screen rect, alpha, what, the thing, look], drawn last frame
var now := {}           # the same, this frame
var listed := {}        # ids handed to the draw this frame (in view, drawn or not)
var _listed_prev := {}
var alive_prev := {}    # id -> "" or why it's not drawn (inside, gone...), last frame
var fixed := {}         # buildings and trees: always there
var key := 0            # the thing being drawn now
var ref = null
var what := ""
var counts := {}
var lines := 0
var last_vr := Rect2()
var _vr := Rect2()
var _cut := false
var _n := 0
var _sized := false
var storm := OS.has_environment("PIZZA_POPS_EVENTS")
var storm_i := 0


func _init(c: Node2D) -> void:
	city = c
	every = maxi(60, OS.get_environment("PIZZA_POPS").to_int()) if OS.get_environment("PIZZA_POPS").to_int() > 1 else 1800


func id_of(d: Dictionary) -> int:
	if not d.has("_pw"):
		_n += 1
		d["_pw"] = _n
	return d["_pw"]


## Before one item of the town's draw: [type, thing] as in City._draw_world's list.
func begin(it: Array) -> void:
	if not _sized and DisplayServer.get_name() == "headless":   # a 16:9 screen, as in the game (headless is square)
		_sized = true
		city.get_window().size = Vector2i(1280, 720)
	var t: int = it[1]
	ref = it[2]
	key = 0
	match t:
		4:
			return
		3:
			key = -1000 - int(it[2])
			what = "rival"
		7:
			key = -2000 - int(it[2])
			what = "chef"
		_:
			key = id_of(it[2])
			what = _what(t, it[2])
			if t <= 1:
				fixed[key] = true
	listed[key] = true
	Sprites.marking = true
	Sprites.marked_a = 0.0


func end() -> void:
	if key == 0:
		return
	Sprites.marking = false
	if Sprites.marked_a > 0.0:
		var look := ""
		if ref is Dictionary and ref.has("uid"):
			look = str(Sprites._cast_now.get(ref["uid"], ""))
		now[key] = [Sprites.marked, Sprites.marked_a, what, ref, look]


func _what(t: int, d: Dictionary) -> String:
	match t:
		0: return "building %s" % d.get("kind", "?")
		1: return "tree"
		2: return "car %s%s" % [d.get("kind", "?"), " siren" if d.get("siren", false) else ""]
		5: return "prop %s" % d.get("kind", "?")
		6: return "giver" if d.get("giver", false) else ("street ped" if int(d.get("road", -1)) >= 0 else "plaza ped")
		8: return "mascot"
		9: return "season prop %s" % d.get("kind", "?")
		10: return "actor %s %s" % [d.get("type", "?"), d.get("name", d.get("design", ""))]
	return "?"


func _seen(r: Rect2, vr: Rect2) -> bool:
	var i := r.intersection(vr)
	return i.size.x >= 4.0 and i.size.y >= 4.0


func _log(kind: String, why: String, e: Array) -> void:
	if Engine.get_process_frames() < 90 or _cut:   # the camera is still swooping in from the title, or cut
		return
	var tag: String = "%s | %s | %s" % [kind, e[2], why]
	counts[tag] = int(counts.get(tag, 0)) + 1
	counts[kind] = int(counts.get(kind, 0)) + 1
	if lines < 300:
		lines += 1
		var d = e[3]
		var extra := ""
		if d is Dictionary:
			extra = " pos=%s" % str(d.get("pos", ""))
		print("POP f%d %s %s (%s) rect=%s a=%.2f%s view=%s" % [Engine.get_process_frames(), kind, e[2], why, str(e[0]), e[1], extra, str(_vr)])


## After the town's draw: compare with last frame. `vr` is the world rect on screen.
func finish(vr: Rect2) -> void:
	# the camera cutting somewhere (a respawn, the ER...) shows a new view: nothing to report there
	_vr = vr
	_cut = last_vr.position.distance_to(vr.position) > 25.0 or absf(last_vr.size.x - vr.size.x) > 4.0
	var owner := {}
	var alive := {}
	for p in city.peds:
		alive[id_of(p)] = "inside" if float(p.get("inside", 0.0)) > 0.0 else ("away" if p.get("state", "") == "away" else "")
	for c in city.cars:
		alive[id_of(c)] = "hidden" if c.get("hidden", false) else ""
	for m in city.mascots:
		alive[id_of(m)] = ""
	for e in city.season_props + city.props:
		alive[id_of(e)] = "" if e.get("season", Season.current) == Season.current else "season"
	for k in fixed:
		alive[k] = ""
	for i in city.rival_state.size():
		alive[-1000 - i] = ""
	for i in city.shops.size():
		alive[-2000 - i] = ""
	if city.events != null:
		for a in city.events.critters:
			alive[id_of(a)] = "gone" if a.get("gone", false) else ""
			owner[a["_pw"]] = "critter"
		for a in city.events.crew:
			alive[id_of(a)] = ""
			owner[a["_pw"]] = "crew"
		for e in city.events.events:
			for a in e["actors"]:
				alive[id_of(a)] = "gone" if a.get("gone", false) else ""
				owner[a["_pw"]] = e["kind"]
	for k in prev:
		var e: Array = prev[k]
		if not now.has(k):
			if e[1] < 0.35 or not _seen(e[0], vr):
				continue
			var why := ""
			if not alive.has(k):
				why = "removed"
			elif alive[k] != "":
				why = alive[k]
			elif listed.has(k):
				why = "not drawn" + (" (cast hid)" if e[3] is Dictionary and e[3].has("uid") and Sprites._hid_now.has(e[3]["uid"]) else "")
			else:
				why = "culled"
			_log("OUT", why + " " + str(owner.get(k, "")), e)
		else:
			var n: Array = now[k]
			if _seen(n[0], vr) and _seen(e[0], vr):
				if n[0].get_center().distance_to(e[0].get_center()) > 20.0:
					_log("JUMP", str(owner.get(k, "")), n)
				elif n[4] != e[4] and e[4] != "" and n[4] != "":
					_log("LOOK", "%s->%s %s" % [e[4], n[4], owner.get(k, "")], n)
	for k in now:
		if prev.has(k):
			continue
		var n: Array = now[k]
		if n[1] < 0.35 or not _seen(n[0], vr):
			continue
		var why := "new"
		if alive_prev.has(k):
			why = "was " + str(alive_prev[k]) if alive_prev[k] != "" else ("was not drawn" if _listed_prev.has(k) else "was culled")
		_log("IN", why + " " + str(owner.get(k, "")), n)
	_listed_prev = listed
	alive_prev = alive
	prev = now
	now = {}
	listed = {}
	last_vr = vr
	if storm:
		_storm()
	if Engine.get_process_frames() % every == 0 and Engine.get_process_frames() > 0:
		report()


func report() -> void:
	print("POPS at frame %d (%.0f s): IN %d OUT %d JUMP %d LOOK %d, cast doubles %d" % [Engine.get_process_frames(), city.t_,
		counts.get("IN", 0), counts.get("OUT", 0), counts.get("JUMP", 0), counts.get("LOOK", 0), Sprites.doubles])
	print("  view %s, player %s" % [last_vr, city.p_pos])
	var keys := counts.keys().filter(func(k): return String(k).contains("|"))
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for k in keys:
		print("  %5d  %s" % [counts[k], k])


## PIZZA_POPS_EVENTS: every 15 s the next kind of happening starts the way it would by itself (out of sight, when it fits).
func _storm() -> void:
	var f := Engine.get_process_frames()
	if f < 300 or f % 450 != 0 or city.events == null:
		return
	var ev = city.events
	var kinds: Array = ["crowd", "dog", "pigeons", "cat", "band", "busker", "mime", "truck", "ball", "balloon", "siren", "parade"]
	kinds.append_array(ev.SPECIALS.keys())
	kinds.append_array(ev.TOWN)
	kinds.append_array(ev.SEASONAL.get(Season.current, []))
	kinds.append_array(["outage", "cart", "hydrant", "seagulls", "kid_race"])
	var k: String = kinds[storm_i % kinds.size()]
	storm_i += 1
	if k == "seagulls" and city.carry.is_empty():
		k = "kid_race"
	if ev.has_method("_fits") and k in ev.all_kinds() and not ev._fits(k):
		print("EVENT %s doesn't fit" % k)
		return
	var n: int = ev.events.size()
	ev._start(k)
	print("EVENT f%d %s %s" % [f, k, "started" if ev.events.size() > n else "didn't start"])
