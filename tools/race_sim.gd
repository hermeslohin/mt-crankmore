extends SceneTree
## Simulates one race with you holding a steady wattage the whole way, as if on a trainer: no power-ups used, no
## steering, the rivals racing as usual. Prints one line starting "RESULT" (see tools/race_sim.py, which runs many).
##
##   SIM_COURSE=2 SIM_WATTS=150 godot --headless --fixed-fps 10 --path . -s tools/race_sim.gd
##
## Environment:
##   SIM_COURSE    index into Race.COURSES (0 Foothill, 1 Summit, 2 Flour Run, 3 Crusty Crit, 4 the Velodoughm,
##                 5 Baguette Boulevard)
##   SIM_CHAMP     1: the champion's version of the race (Maillot Max rides too; on Baguette Boulevard, Yellow Jersey Yolanda)
##   SIM_WATTS     your steady power
##   SIM_FTP       your FTP (default 200), SIM_WEIGHT_KG your weight (default 75)
##   SIM_DIFF      easy | medium | hard | ludicrous (default medium)
##   SIM_BIKE      index into Game.bikes (default 3, the Carbon Crit Machine)
##   SIM_SEED      random seed (rival behaviour differs from seed to seed)
## Run with PIZZA_NO_SAVE=1 so the save file is never touched. --fixed-fps 10 simulates in 0.1 s steps as fast as the
## machine allows (results match 0.05 s steps to a fraction of a second).
## The result: "place=1 time=<s>" if you won, else "place=2+" (stopped as soon as a rival crosses the line first).

var main
var t := 0.0
var started := false
var watts := 0.0
var game
var trainer


func _env(name: String, fallback: String) -> String:
	return OS.get_environment(name) if OS.get_environment(name) != "" else fallback


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	if game == null:
		game = root.get_node("Game")
		trainer = root.get_node("Trainer")
	if t > 0.3 and not started:
		started = true
		seed(_env("SIM_SEED", "1").to_int())
		watts = _env("SIM_WATTS", "200").to_float()
		trainer._autostart_clock = 0.0   # leave a real trainer alone
		main._start_game()
		game.ftp = _env("SIM_FTP", "200").to_float()
		game.weight_kg = _env("SIM_WEIGHT_KG", "75").to_float()
		game.difficulty = _env("SIM_DIFF", "medium")
		var bike := _env("SIM_BIKE", "3").to_int()
		if not game.owned.has(bike):
			game.owned.append(bike)
		game.equipped = bike
		game.hp[bike] = float(game.bikes[bike]["hp"])
		game.money = 100000
		main.city.refresh_rivals()
		var course := _env("SIM_COURSE", "0").to_int()
		var champ: Dictionary = {}
		if _env("SIM_CHAMP", "0") == "1":
			champ = game.YOLANDA if main.race.COURSES[course].get("road", false) else game.CHAMPION
		main._start_race(course, champ)
	if started:
		# a trainer that's always there, always holding the same watts
		var now := Time.get_ticks_msec()
		trainer.last_msg_ms = now
		trainer.last_trainer_ms = now
		trainer.trainer_live = true
		trainer.trainer_power = watts
		trainer.trainer_cadence = 90.0
	if started and main.race != null and main.race.riders.size() > 1:
		var race = main.race
		var me: Dictionary = race.riders[0]
		if me["done"]:
			var ahead := 0
			for k in range(1, race.riders.size()):
				if race.riders[k]["done"] and float(race.riders[k]["time"]) <= float(me["time"]):
					ahead += 1
			print("RESULT diff=%s place=%d time=%.1f riders=%d course=%s" % [game.difficulty, ahead + 1, float(me["time"]), race.riders.size(), race.course["name"]])
			return true
		for k in range(1, race.riders.size()):
			var r: Dictionary = race.riders[k]
			if r["done"]:
				print("RESULT diff=%s place=2+ time=-1 first_rival=%s rival_time=%.1f my_s=%.0f course=%s" % [game.difficulty, r["short"], float(r["time"]), float(me["s"]), race.course["name"]])
				return true
		if race.clock > 7200.0:
			print("RESULT diff=%s place=99 time=-1 course=%s" % [game.difficulty, race.course["name"]])
			return true
	return false
