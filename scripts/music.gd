extends Node
## Music (autoload Music). Always on, on its own Music bus a little under the sound effects; how loud is up to the
## system volume. The songs are seamless loops in music/<name>.wav, synthesised by tools/make_music.py:
##   title           the menus
##   race_<course>   one per race, see RACE_SONGS
##   cruise_1..3     riding round town: one picked at random, and after a couple of times round another one
## Music.play("title") crossfades to a song (playing the one already on does nothing); Music.town() starts the town
## shuffle; Music.race(course) the course's own song.

const DIR := "res://music/"
const FADE := 1.2              # seconds to crossfade between songs
const LEVEL_DB := -7.0         # under the sound effects
const TOWN_SONGS := ["cruise_1", "cruise_2", "cruise_3"]
const TOWN_PLAYS := 2          # times round a town song before shuffling to another
const RACE_SONGS := {
	"Foothill Gravel Grind": "race_foothill",
	"Summit Gravel Showdown": "race_summit",
	"Flour Run": "race_flour",
	"Crusty Crit": "race_crit",
	"The Velodoughm": "race_velo",
	"Baguette Boulevard": "race_baguette",
}

var current := ""
var _players: Array[AudioStreamPlayer] = []   # two, for crossfading
var _active := 0
var _tween: Tween             # the new song fading in
var _fade_out: Tween          # the old one fading out
var _in_town := false
var _town_left := 0.0          # seconds until the town shuffle moves on
var _last_town := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "Music")
	AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_volume_db(bus, LEVEL_DB)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	if not _in_town or current.is_empty():
		return
	_town_left -= delta
	if _town_left <= 0.0:
		_play_town_song()


## Crossfades to `song` (a file name in music/, without .wav); "" fades the music out.
func play(song: String) -> void:
	_in_town = false
	_switch(song)


## Riding round town: a random town song (not the last one), moving on to another every TOWN_PLAYS loops.
func town() -> void:
	if _in_town:
		return
	_in_town = true
	_play_town_song()


## The race's own song (the rescue rides the Foothill course).
func race(course: Dictionary) -> void:
	play(RACE_SONGS.get(String(course.get("name", "")), "race_summit"))


func _play_town_song() -> void:
	var pick: Array = TOWN_SONGS.filter(func(s): return s != _last_town)
	_last_town = pick[randi() % pick.size()]
	_switch(_last_town)
	var s := _players[_active].stream
	_town_left = (s.get_length() if s else 60.0) * TOWN_PLAYS


func _switch(song: String) -> void:
	if song == current:
		return
	current = song
	var path := DIR + song + ".wav"
	var stream: AudioStream = load(path) if not song.is_empty() and ResourceLoader.exists(path) else null
	var old := _players[_active]
	for t in [_tween, _fade_out]:
		if t:
			t.kill()
	_players[1 - _active].stop()   # whatever was still fading out from the switch before
	if old.playing:
		_fade_out = create_tween()
		_fade_out.tween_property(old, "volume_db", -80.0, FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_fade_out.tween_callback(old.stop)
	if stream == null:
		return
	if stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:   # in case the import lost it
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = -30.0
	p.play()
	_tween = create_tween()
	_tween.tween_property(p, "volume_db", 0.0, FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
