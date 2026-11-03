extends Node
## Sound effects (autoload Sfx). Sfx.play("deliver") plays sounds/deliver.wav on the SFX bus, at full level: how loud
## is up to the system volume. The sounds are synthesised by tools/make_sfx.py: drop in a .wav of the same name to
## replace one.

const DIR := "res://sounds/"
const VOICES := 10
const REPEAT_MS := 40          # the same sound started again within this is skipped (no doubled-up clicks)

var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _last := {}
var _loop: AudioStreamPlayer   # the freewheel ticking while you coast
var _bus := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(_bus, "SFX")
	AudioServer.set_bus_send(_bus, "Master")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_loop = AudioStreamPlayer.new()
	_loop.bus = "SFX"
	add_child(_loop)


func _stream(sound: String) -> AudioStream:
	if not _cache.has(sound):
		var path := DIR + sound + ".wav"
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
	return _cache[sound]


## Plays a sound once. `vary` detunes it at random by up to that fraction, so repeats don't sound identical.
func play(sound: String, vol_db := 0.0, pitch := 1.0, vary := 0.0) -> void:
	var s := _stream(sound)
	if s == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(sound, -100000)) < REPEAT_MS:
		return
	_last[sound] = now
	var p: AudioStreamPlayer = null
	for q in _players:
		if not q.playing:
			p = q
			break
	if p == null:   # all busy: cut off the one that has played longest
		p = _players[0]
		for q in _players:
			if q.get_playback_position() > p.get_playback_position():
				p = q
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * (1.0 + randf_range(-vary, vary))
	p.play()


## Plays a sound after `secs` (an ambulance siren after the crash).
func play_later(sound: String, secs: float, vol_db := 0.0) -> void:
	get_tree().create_timer(secs).timeout.connect(play.bind(sound, vol_db))


## The freewheel ticking: on while you roll without pedalling, ticking faster the faster you go (`speed_ms`, m/s).
func coast(on: bool, speed_ms := 0.0) -> void:
	if not on:
		if _loop.playing:
			_loop.stop()
		return
	if _loop.stream == null:
		var s := _stream("freewheel")
		if s == null:
			return
		s = s.duplicate()
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_loop.stream = s
	_loop.pitch_scale = clampf(speed_ms / 7.0, 0.4, 2.2)
	_loop.volume_db = -4.0
	if not _loop.playing:
		_loop.play()
