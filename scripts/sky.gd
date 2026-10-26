extends Node
## Time of day and the weather, for the town and the races alike.
##
## A whole day goes by in DAY_SECONDS (an hour): dawn, a long day, dusk and the night, when it gets dark, the
## street lamps come on one by one and cars and bikes ride with their lights on (see night.gd, which draws the
## dark and the pools of light). A new game starts in the morning.
##
## Now and then it rains, for 5 to 10 minutes at a time, in spring, summer and fall; in winter there is always a
## light snow falling, and every few minutes a proper snowfall. weather.gd draws the drops and flakes.
##
## Dev helpers: PIZZA_TIME=<hour, 0-24> sets the clock, PIZZA_WEATHER=rain|snow|clear holds the weather.

const DAY_SECONDS := 3600.0
const START_HOUR := 8.0
const FADE := 25.0           # seconds for a shower to build up or die away

## The light through the day: [hour, colour everything is multiplied by, darkness 0-1].
const LIGHT := [
	[0.0, Color(0.30, 0.34, 0.58), 1.0],
	[5.0, Color(0.30, 0.34, 0.58), 1.0],
	[6.0, Color(0.72, 0.58, 0.66), 0.55],
	[7.0, Color(1.0, 0.9, 0.82), 0.12],
	[8.0, Color.WHITE, 0.0],
	[17.5, Color.WHITE, 0.0],
	[18.5, Color(1.0, 0.8, 0.6), 0.2],
	[19.5, Color(0.62, 0.5, 0.62), 0.6],
	[20.5, Color(0.30, 0.34, 0.58), 1.0],
	[24.0, Color(0.30, 0.34, 0.58), 1.0],
]
const OVERCAST := Color(0.74, 0.77, 0.86)   # the light under rain clouds

var hour := START_HOUR
var weather := "clear"       # "clear", "rain" or "snow" (a heavy snowfall; winter always has some flakes)
var amount := 0.0            # how hard it is raining / snowing, 0-1 (eases in and out)
var _left := 0.0             # seconds until the weather changes
var _forced := ""
var _season := ""
var _dried := false          # had the season's first dry spell


func _ready() -> void:
	if OS.has_environment("PIZZA_TIME"):
		hour = fposmod(OS.get_environment("PIZZA_TIME").to_float(), 24.0)
	_forced = OS.get_environment("PIZZA_WEATHER")


func _process(delta: float) -> void:
	if not OS.has_environment("PIZZA_TIME"):
		hour = fposmod(hour + delta * 24.0 / DAY_SECONDS, 24.0)
	if Season.current != _season:
		_season = Season.current
		_left = 0.0
		_dried = false
		weather = "clear"
	if _forced != "":
		weather = _forced if _forced != "snow" or _season == "winter" else "clear"
	else:
		_left -= delta
		if _left <= 0.0:
			_next()
	amount = move_toward(amount, 0.0 if weather == "clear" else 1.0, delta / FADE if _forced == "" else 1.0)


## Dry spells and showers. Rain: 5-10 minutes now and then, a dry spell of 6-18 minutes in between. Winter: heavy
## snowfalls of 5-10 minutes with only 2-5 minutes of light flurries between them.
func _next() -> void:
	var winter := _season == "winter"
	if weather == "clear" and _dried:
		weather = "snow" if winter else "rain"
		_left = randf_range(5.0, 10.0) * 60.0
		Game.toast.emit("It's snowing hard!" if winter else "It's starting to rain!", Color(0.75, 0.85, 1.0))
	else:
		# the first dry spell of a season is a short one
		weather = "clear"
		_left = (randf_range(2.0, 5.0) if winter else randf_range(6.0, 18.0) if _dried else randf_range(2.0, 7.0)) * 60.0
	_dried = true


## Darkness, 0 in the day to 1 at night.
func dark() -> float:
	return _at(2)


## What the world is multiplied by: the time of day's light, under clouds while it rains.
func tint() -> Color:
	var c: Color = _at(1)
	c *= Color.WHITE.lerp(OVERCAST if _season != "winter" else Color(0.86, 0.88, 0.94), amount)
	return Color(c.r, c.g, c.b, 1.0)


## "8:05 PM"
func clock() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, m, "AM" if h < 12 else "PM"]


func _at(i: int) -> Variant:
	for k in LIGHT.size() - 1:
		var a: Array = LIGHT[k]
		var b: Array = LIGHT[k + 1]
		if hour >= a[0] and hour <= b[0]:
			var u := (hour - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			if i == 1:
				return (a[1] as Color).lerp(b[1], u)
			return lerpf(a[2], b[2], u)
	return LIGHT[0][i]
