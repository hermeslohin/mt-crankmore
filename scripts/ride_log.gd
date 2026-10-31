extends Node
## Records your ride for Strava: a session runs from New game / Continue game until you quit to the title. Once a second while you're riding (town or race) it logs distance, speed,
## altitude (built up from the road grade), power and cadence, counts the pizzas delivered and races won,
## keeps a timeline of what happened (pizzas, challenges won or lost, race placings) and grabs up to 4 screenshots along the way. The ride and its screenshots live in memory only: nothing is written
## to disk until it is posted (then the screenshots go to user://rides/<activity>), so quitting without posting throws
## it away. It is written out as a TCX file for the upload.
## Power and cadence only come from a real trainer: keyboard riding logs speed and distance, never made-up watts.

const OLD_DIR := "user://ride"   # where older versions kept the unposted ride on disk
const MAX_SHOTS := 4
const MIN_SECONDS := 60          # shorter rides aren't worth posting
const START_ALT := 1250.0        # metres: Crankmore Village sits up in the mountains
const SCENIC_EVERY := 300.0      # seconds of riding between scenery screenshots (the first one at 90 s)
const SHOT_PRIO := {"scenic": 0, "delivery": 1, "race": 2, "race_win": 3}

var samples: Array = []          # [unix time, distance m, altitude m, speed m/s, watts or -1, rpm or -1]
var distance := 0.0
var altitude := START_ALT
var pizzas := 0
var races_won := 0
var events: Array = []           # {t: unix time, kind: pizza | won | lost | race, text, place}: the session's timeline
var shots: Array = []            # {"image": Image, "kind", "t"}
var _seen_deliveries := -1
var _riding := 0.0               # seconds ridden (pauses don't count)
var _next_scenic := 90.0
var _last_sec := 0


## Clears out the unposted ride (and stray screenshots) older versions left on disk.
func _ready() -> void:
	if Game.no_save or not DirAccess.dir_exists_absolute(OLD_DIR):
		return
	for f in DirAccess.get_files_at(OLD_DIR):
		DirAccess.remove_absolute(OLD_DIR.path_join(f))
	DirAccess.remove_absolute(OLD_DIR)


## Called every frame you're actually riding, with your speed (m/s) and the road grade (0.05 = 5%).
func tick(delta: float, speed_mps: float, grade: float) -> void:
	var now := int(Time.get_unix_time_from_system())
	var v := maxf(speed_mps, 0.0)
	var ds := v * delta
	distance += ds
	altitude = maxf(0.0, altitude + ds * grade / sqrt(1.0 + grade * grade))
	_riding += delta
	if _seen_deliveries < 0 or Game.deliveries < _seen_deliveries:
		_seen_deliveries = Game.deliveries   # first tick, or a New game reset the count
	elif Game.deliveries > _seen_deliveries:
		for i in Game.deliveries - _seen_deliveries:
			mark("pizza", "Pizza delivered")
		pizzas += Game.deliveries - _seen_deliveries
		_seen_deliveries = Game.deliveries
		snap("delivery", 0.4)
	if _riding >= _next_scenic:
		_next_scenic = _riding + SCENIC_EVERY
		snap("scenic")
	if now != _last_sec:
		_last_sec = now
		var live := Trainer.trainer_live
		samples.append([now, snappedf(distance, 0.1), snappedf(altitude, 0.1), snappedf(v, 0.01),
			roundi(Trainer.power()) if live else -1, roundi(Trainer.cadence()) if live else -1])


## Puts something that happened on the session's timeline (see `events`).
func mark(kind: String, text: String, place := 0) -> void:
	events.append({"t": int(Time.get_unix_time_from_system()), "kind": kind, "text": text, "place": place})


func on_race_finished(place: int, course := "Race") -> void:
	mark("race", "%s: #%d" % [course, place], place)
	if place == 1:
		races_won += 1
	snap("race_win" if place == 1 else "race", 0.3)


func seconds() -> int:
	return 0 if samples.size() < 2 else int(samples[-1][0]) - int(samples[0][0])


func can_post() -> bool:
	return seconds() >= MIN_SECONDS


## Session averages: power over every second a trainer reported (coasting included), cadence while pedalling, speed
## over the time ridden. Power / cadence are -1 without a trainer.
func averages() -> Dictionary:
	var pw := 0.0
	var pw_n := 0
	var rpm := 0.0
	var rpm_n := 0
	var vmax := 0.0
	for s in samples:
		if int(s[4]) >= 0:
			pw += float(s[4])
			pw_n += 1
		if int(s[5]) > 0:
			rpm += float(s[5])
			rpm_n += 1
		vmax = maxf(vmax, float(s[3]))
	return {"watts": pw / pw_n if pw_n > 0 else -1.0, "rpm": rpm / rpm_n if rpm_n > 0 else -1.0,
		"kmh": distance / _riding * 3.6 if _riding > 0.0 else 0.0, "max_kmh": vmax * 3.6}


func count(kind: String) -> int:
	return events.filter(func(e): return e["kind"] == kind).size()


## The session as it stands, for the end-of-session screen (it outlives the ride being posted and reset).
func snapshot() -> Dictionary:
	return {"samples": samples.duplicate(), "events": events.duplicate(true), "avg": averages(), "seconds": seconds(),
		"distance": distance, "pizzas": pizzas, "won": count("won"), "lost": count("lost"),
		"races": events.filter(func(e): return e["kind"] == "race").map(func(e): return e["text"])}


func summary() -> String:
	if samples.is_empty():
		return "Nothing recorded yet: go ride!"
	var s := seconds()
	return "%.1f km  |  %d:%02d  |  %d pizza%s delivered  |  %d race%s won  |  %d screenshot%s" % [distance / 1000.0, s / 60, s % 60,
		pizzas, "" if pizzas == 1 else "s", races_won, "" if races_won == 1 else "s", shots.size(), "" if shots.size() == 1 else "s"]


func title() -> String:
	if races_won > 0 and pizzas == 0:
		return "Mt. Crankmore: %d race win%s" % [races_won, "" if races_won == 1 else "s"]
	if races_won > 0:
		return "Mt. Crankmore: %d pizza%s and %d race win%s" % [pizzas, "" if pizzas == 1 else "s", races_won, "" if races_won == 1 else "s"]
	return "Mt. Crankmore: %d pizza%s delivered" % [pizzas, "" if pizzas == 1 else "s"] if pizzas > 0 else "Mt. Crankmore pizza ride"


func description() -> String:
	var avg := averages()
	var notes := "Pizza delivered: %d\nRaces won: %d\nChallenges won: %d, lost: %d" % [pizzas, races_won, count("won"), count("lost")]
	for e in events:
		if e["kind"] == "race":
			notes += "\n" + str(e["text"])
	if avg["watts"] >= 0.0:
		notes += "\nAverage %d W, %d rpm" % [roundi(avg["watts"]), roundi(maxf(avg["rpm"], 0.0))]
	return notes + "\n\nMt Crankmore - Pizza pays the bills, Cycling is life\nhttps://github.com/hermeslohin/mt-crankmore/releases"


## Forget the current ride (after posting it, or when the rider throws it away). Screenshots of a posted ride are
## written to `keep_dir` so they can still be added to the activity.
func reset(keep_dir := "") -> void:
	if keep_dir != "":
		save_shots(keep_dir)
	samples = []
	shots = []
	distance = 0.0
	altitude = START_ALT
	pizzas = 0
	races_won = 0
	events = []
	_riding = 0.0
	_next_scenic = 90.0
	_seen_deliveries = -1


# ---- screenshots -----------------------------------------------------------

## Grab the screen `wait` seconds from now. Only MAX_SHOTS are kept: a new shot pushes out the oldest of the least
## interesting ones (scenery < deliveries < races < race wins), unless it is less interesting than all of them.
func snap(kind: String, wait := 0.0) -> void:
	if DisplayServer.get_name() == "headless" or Game.no_save:   # (dev helpers never add photos to your ride)
		return
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var prio: int = SHOT_PRIO[kind]
	if shots.size() >= MAX_SHOTS:
		var drop := -1
		for i in shots.size():
			if SHOT_PRIO[shots[i]["kind"]] <= prio and (drop < 0 or SHOT_PRIO[shots[i]["kind"]] < SHOT_PRIO[shots[drop]["kind"]]):
				drop = i
		if drop < 0:
			return
		shots.remove_at(drop)
	shots.append({"image": get_viewport().get_texture().get_image(), "kind": kind, "t": int(Time.get_unix_time_from_system())})


## Writes the screenshots to `dir` as PNGs.
func save_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for s in shots:
		(s["image"] as Image).save_png(dir.path_join("crankmore_%d_%s.png" % [int(s["t"]), s["kind"]]))


# ---- TCX -------------------------------------------------------------------

func _iso(t: int) -> String:
	return Time.get_datetime_string_from_unix_time(t) + "Z"


## The ride as a Garmin TCX file (no GPS: Strava takes the distance, speed, power and cadence from it).
func to_tcx() -> String:
	var t0 := int(samples[0][0])
	var vmax := 0.0
	for s in samples:
		vmax = maxf(vmax, float(s[3]))
	var out := PackedStringArray()
	out.append('<?xml version="1.0" encoding="UTF-8"?>')
	out.append('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">')
	out.append('<Activities><Activity Sport="Biking"><Id>%s</Id>' % _iso(t0))
	out.append('<Lap StartTime="%s"><TotalTimeSeconds>%d</TotalTimeSeconds><DistanceMeters>%.1f</DistanceMeters><MaximumSpeed>%.2f</MaximumSpeed><Calories>0</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod><Track>' % [
		_iso(t0), seconds(), float(samples[-1][1]), vmax])
	for s in samples:
		var pt := "<Trackpoint><Time>%s</Time><AltitudeMeters>%.1f</AltitudeMeters><DistanceMeters>%.1f</DistanceMeters>" % [_iso(int(s[0])), float(s[2]), float(s[1])]
		if int(s[5]) >= 0:
			pt += "<Cadence>%d</Cadence>" % clampi(int(s[5]), 0, 254)
		pt += "<Extensions><ns3:TPX><ns3:Speed>%.2f</ns3:Speed>" % float(s[3])
		if int(s[4]) >= 0:
			pt += "<ns3:Watts>%d</ns3:Watts>" % maxi(int(s[4]), 0)
		out.append(pt + "</ns3:TPX></Extensions></Trackpoint>")
	out.append("</Track></Lap><Creator><Name>Mt. Crankmore</Name></Creator></Activity></Activities></TrainingCenterDatabase>")
	return "\n".join(out)

