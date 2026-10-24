extends Node2D
## Scene manager: title -> city -> race, plus the menus that connect them.

enum Mode { TITLE, CITY, RACE }

var mode: int = Mode.TITLE
var cam: Camera2D
var city: Node2D
var race: Node2D
var hud: Control
var title_t := 0.0
var shot_at := Vector2.INF   # dev helper: camera pinned on a world point for screenshots


func _ready() -> void:
	# fill the screen (the dev helpers keep the plain window so screenshots stay predictable)
	if not OS.has_environment("PIZZA_DEBUG") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	cam = Camera2D.new()
	add_child(cam)
	city = preload("res://scripts/city.gd").new()
	add_child(city)
	race = preload("res://scripts/race.gd").new()
	race.visible = false
	add_child(race)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	layer.add_child(hud)
	hud.setup(self)
	city.interact.connect(_on_interact)
	race.finished.connect(_on_race_finished)
	cam.position = Iso.to_screen(Vector2(80, 76))
	_show_title()
	# Dev helper: PIZZA_DEBUG=city|race auto-starts with the W key held (used for screenshots).
	match OS.get_environment("PIZZA_DEBUG"):
		"city":
			_start_game()
			Input.action_press("pedal")
		"city_fast":
			_start_game()
			Input.action_press("pedal")
			Input.action_press("steer_right")
			Engine.time_scale = 15.0
		"race":
			_start_game()
			_start_race(1)
			Input.action_press("pedal")
		"race_fast":
			_start_game()
			_start_race(0)
			Input.action_press("pedal")
			Engine.time_scale = 40.0
		"shop":
			Game.money = 3000
			_start_game()
			_on_interact("bike")
		"er":
			_start_game()
			city._hit_by_car({"speed": 0.0})
		"flow":
			_debug_flow()
		"overview":
			hud.close_menu()
		"rails":
			_debug_rails()
		"trainer":
			_debug_trainer()
		"roads":
			_debug_roads()
		"latch":
			_debug_latch()
		"shot":
			_debug_shot()
		"readme":
			_debug_readme()
		"gears":
			_debug_gears()
		"link":
			await get_tree().create_timer(3.0).timeout
			print("LINK: ", Trainer.status_text(), " power=", int(Trainer.power()), " cadence=", int(Trainer.cadence()),
				" gear=", Trainer.gear, " ratio=", snappedf(Trainer.gear_ratio(), 0.001))
			Trainer.send_grade(5.5)
			for i in 20:
				await get_tree().process_frame
			get_tree().quit()


## Feeds fake shifter presses through the link and prints gear, ratio and keyboard watts.
func _debug_gears() -> void:
	var packet := func(buttons: Array) -> void:
		Trainer._on_message({"type": "data", "trainer": false, "controller": true, "buttons": buttons})
		await get_tree().process_frame
	for b in [["RS1"], [], ["RS1"], ["RS1"], ["RS1", "A"], [], ["LS2"], ["LS1"], []]:
		await packet.call(b)
	print("GEARS: after RS1,RS1(held),RS1,LS2(no shift),LS1 -> gear ", Trainer.gear, " (want 12)")
	for i in 30:
		await packet.call(["RS1"] if i % 2 == 0 else [])
	print("GEARS: top gear ", Trainer.gear, " ratio ", snappedf(Trainer.gear_ratio(), 0.001))
	for g in [1, 6, 11, 16, 21]:
		Trainer.gear = g
		Input.action_press("pedal")
		for i in 240:
			await get_tree().process_frame
		print("GEARS: gear %2d ratio %.3f  keyboard %3d W  %3d rpm" % [g, Trainer.gear_ratio(), int(Trainer.kb_power), int(Trainer.kb_cadence)])
	get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed)):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	title_t += delta
	var target: Vector2
	match mode:
		Mode.TITLE:
			target = Iso.to_screen(Vector2(80.0 + 30.0 * cos(title_t * 0.05), 76.0 + 30.0 * sin(title_t * 0.05)))
		Mode.CITY:
			target = city.cam_target() if shot_at == Vector2.INF else Iso.to_screen(shot_at, 12.0 + Iso.ground_z(shot_at))
		_:
			target = race.cam_target()
	cam.position = cam.position.lerp(target, 1.0 - exp(-6.0 * delta))
	# flat road on the trainer whenever you're not riding (title, menus, the bike shop, the ER)
	if mode == Mode.TITLE or (mode == Mode.CITY and (not city.active or city.er_timer > 0.0)):
		Trainer.send_grade(0.0)
	var z := 1.0 if mode == Mode.TITLE else (1.8 if mode == Mode.RACE else 1.75)
	if OS.has_environment("PIZZA_ZOOM"):  # dev helper for overview screenshots
		z = OS.get_environment("PIZZA_ZOOM").to_float()
		cam.zoom = Vector2(z, z)
	cam.zoom = cam.zoom.lerp(Vector2(z, z), 1.0 - exp(-3.0 * delta))
	if not hud.menu_open and Input.is_action_just_pressed("act_back"):
		if mode == Mode.CITY and city.er_timer <= 0.0:
			_open_pause()
		elif mode == Mode.RACE and race.active:
			_open_race_pause()


func on_menu_closed() -> void:
	if mode == Mode.TITLE:
		Trainer.scan(false)
		_show_title()
	elif mode == Mode.CITY:
		city.active = true
	elif mode == Mode.RACE and not race.over:
		race.active = true


# ---- title / pause ------------------------------------------------------

func _show_title() -> void:
	mode = Mode.TITLE
	city.active = false
	city.visible = true
	race.visible = false
	hud.open_menu(func():
		return {"title": "Welcome to Mt. Crankmore", "sub": "%s.\nSummer in Crankmore Village. %s. One mountain. Just pedal: your bike follows the road. At junctions pick LEFT / RIGHT or UP for straight (DOWN = U-turn). Shifters change gear (1-21). Keyboard: W pedal, Shift sprint, Q / R shift gear, arrows choose, S brake, Space turbo, H shout, E select." % [Game.SLOGAN, _cap(_rivals_text())],
			"items": [
				{"label": "Start delivering", "fn": _start_or_setup},
				{"label": "Rider setup", "fn": _open_setup.bind(_show_title),
					"detail": "FTP %d W  |  %s  |  %.1f W/kg  |  %s  |  %d rival%s" % [int(Game.ftp), Game.weight_text(), Game.wkg(),
						Game.DIFFICULTIES[Game.difficulty]["label"], Game.rival_count, "" if Game.rival_count == 1 else "s"]},
				{"label": "Connect Trainer", "fn": _open_trainer_menu, "detail": Trainer.status_text()},
				{"label": "Quit", "fn": get_tree().quit},
			], "live": true}, true)


# ---- Trainer connection screen -------------------------------------------

func _open_trainer_menu() -> void:
	if Trainer.bridge_live:
		Trainer.scan(true)
	hud.open_menu(_trainer_menu)


func _role_line(label: String, role: String, live_text: String) -> String:
	var info := Trainer.role_info(role)
	var st: String = info.get("state", "idle")
	match st:
		"connected":
			return "%s: %s - CONNECTED %s" % [label, info.get("name", ""), live_text]
		"connecting":
			return "%s: connecting to %s..." % [label, info.get("name", "")]
		"searching":
			return "%s: looking for %s... (wake it up)" % [label, info.get("name", "your device")]
		"failed":
			return "%s: couldn't connect to %s - retrying" % [label, info.get("name", "")]
	return "%s: not connected" % label


func _trainer_menu() -> Dictionary:
	var items: Array = []
	var lines: Array = []
	if not Trainer.bridge_live:
		lines.append("Your game talks to your bicycle trainer through a small Bluetooth helper.")
		if Trainer.helper_state == "installing" or Trainer.helper_state == "starting":
			items.append({"label": "Please wait...", "fn": func(): pass, "enabled": false})
		elif not Trainer.helper_installed():
			items.append({"label": "Install Bluetooth helper (one time)", "fn": Trainer.install_helper,
				"detail": "Sets up a private copy of the Bluetooth library in bridge/.venv. Needs Python 3 and internet, about a minute."})
		else:
			items.append({"label": "Start Bluetooth helper", "fn": func():
				Trainer.start_helper()
				Trainer.scan(true),
				"detail": "Starts scanning for your trainer and handlebar controllers."})
		if Trainer.helper_msg != "":
			lines.append(Trainer.helper_msg)
	else:
		var trainer_live := "(%dW %drpm)" % [int(Trainer.trainer_power), int(Trainer.trainer_cadence)] if Trainer.trainer_live else ""
		var pressed := "  buttons: " + " ".join(Trainer.pressed_names) if not Trainer.pressed_names.is_empty() else ""
		lines.append(_role_line("Trainer", "trainer", trainer_live))
		lines.append(_role_line("Controls", "controller", pressed))
		var err: String = Trainer.status.get("error", "")
		if err != "":
			lines.append("! " + err)
		var scanning: bool = Trainer.status.get("scanning", false)
		items.append({"label": "Scanning..." if scanning else "Scan for devices", "fn": func(): Trainer.scan(true),
			"detail": "Pedal or press a button so the devices wake up. Close any other trainer app first: Bluetooth devices only accept one connection."})
		var shown := {}
		for d in Trainer.devices():
			var role: String = d["kind"]
			var addr: String = d["address"]
			shown[addr] = true
			var info := Trainer.role_info(role)
			var connected: bool = info.get("address", "") == addr and info.get("state", "") in ["connected", "connecting", "searching"]
			var tag := "TRAINER " if role == "trainer" else "CONTROLS"
			var signal_bars := "|".repeat(clampi(int((float(d["rssi"]) + 100.0) / 12.0), 1, 5))
			if connected:
				items.append({"label": "%s  %s  [connected - disconnect]" % [tag, d["name"]], "fn": Trainer.disconnect_device.bind(role),
					"detail": "Select to disconnect this device."})
			else:
				items.append({"label": "%s  %s  %s" % [tag, d["name"], signal_bars], "fn": Trainer.connect_device.bind(role, addr),
					"detail": "Select to use this as your %s. It will reconnect automatically next time." % ("trainer (power, cadence, climbs)" if role == "trainer" else "handlebar controllers (buttons)")})
		for role in ["trainer", "controller"]:
			var info := Trainer.role_info(role)
			if info.get("address", "") != "" and not shown.has(info["address"]) and info.get("state", "idle") != "idle":
				items.append({"label": "%s  %s  [forget]" % ["TRAINER " if role == "trainer" else "CONTROLS", info.get("name", "device")],
					"fn": Trainer.disconnect_device.bind(role), "detail": "Stop using this device."})
		if Trainer.devices().is_empty():
			lines.append("No trainers or handlebar controllers found yet.")
	items.append({"label": "Back", "fn": func():
		Trainer.scan(false)
		_show_title(), "detail": ""})
	return {"title": "Connect Trainer", "sub": "\n".join(lines), "items": items, "live": true}


func _rivals_text() -> String:
	var words := ["", "one", "two", "three", "four", "five", "six", "seven"]
	var n: int = Talk.rivals.size()
	return "%s rival pizza biker%s" % [words[n] if n < words.size() else str(n), "" if n == 1 else "s"]


func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


## First ride: ask for FTP / weight / difficulty before heading out.
func _start_or_setup() -> void:
	if Game.setup_done:
		_start_game()
	else:
		_open_setup(_start_game)


# ---- rider setup ---------------------------------------------------------

## FTP, weight (kg or lbs), difficulty and how many rivals ride. Everything is changed with LEFT / RIGHT,
## so it works from the handlebar D-pad as well as the keyboard. `done` runs when the rider confirms.
func _open_setup(done: Callable) -> void:
	var before := {"n": Game.rival_count}
	var finish := func():
		Game.setup_done = true
		Game.save_game()
		if Game.rival_count != before["n"]:
			city.respawn_rivals()
		else:
			city.refresh_rivals()
		done.call()
	hud.open_menu(func(): return _setup_menu(finish))


func _setup_menu(finish: Callable) -> Dictionary:
	var lbs := Game.units == "lbs"
	var diff: Dictionary = Game.DIFFICULTIES[Game.difficulty]
	var names: Array = Talk.roster.slice(0, Game.rival_count).map(func(r): return r["short"])
	var items: Array = [
		{"label": "FTP: %d W" % int(Game.ftp), "fn": func(): pass,
			"adjust": func(d: int): Game.ftp = clampf(Game.ftp + d * 5.0, 50.0, 600.0),
			"detail": "Your Functional Threshold Power: roughly the best power you can hold for an hour. Hold LEFT / RIGHT to change it faster. Your W/kg sets how strong the rivals are."},
		{"label": "Weight: %s" % Game.weight_text(), "fn": func(): pass,
			"adjust": func(d: int): Game.weight_kg = clampf((roundf(Game.weight_kg * Game.LB_PER_KG) + d) / Game.LB_PER_KG if lbs else roundf(Game.weight_kg) + d, 30.0, 200.0),
			"detail": "Your body weight. It matters on the climbs, just like outside."},
		{"label": "Units: %s" % ("lbs" if lbs else "kg"), "fn": func(): Game.units = "kg" if lbs else "lbs",
			"adjust": func(_d: int): Game.units = "kg" if Game.units == "lbs" else "lbs",
			"detail": "Show weight in kilograms or pounds."},
		{"label": "Difficulty: %s" % diff["label"], "fn": func(): pass,
			"adjust": func(d: int): Game.difficulty = Game.DIFF_ORDER[clampi(Game.DIFF_ORDER.find(Game.difficulty) + d, 0, Game.DIFF_ORDER.size() - 1)],
			"detail": diff["blurb"]},
		{"label": "Rival bikers: %d" % Game.rival_count, "fn": func(): pass,
			"adjust": func(d: int): Game.set_rival_count(Game.rival_count + d),
			"detail": "Riding against you: %s." % ", ".join(names)},
		{"label": "Done", "fn": finish, "detail": ""},
	]
	return {"title": "Rider setup", "sub": "%.2f W/kg. Rivals ride at a similar W/kg, scaled by difficulty." % Game.wkg(), "items": items}


func _start_game() -> void:
	hud.close_menu()
	mode = Mode.CITY
	city.reset_player()
	city.active = true
	Game.toast.emit("Ride to a glowing pizza window to grab an order!", Color(1.0, 0.9, 0.4))
	Talk.say_random("trash_bike" if Game.equipped == 0 else "idle", true)


func _open_pause() -> void:
	city.active = false
	hud.open_menu(func():
		return {"title": "Paused", "sub": "Money: $%d    Deliveries: %d    Races won: %d" % [Game.money, Game.deliveries, Game.race_wins],
			"items": [
				{"label": "Resume", "fn": func(): hud.close_menu(); on_menu_closed()},
				{"label": "Rider setup", "fn": _open_setup.bind(_open_pause)},
				{"label": "Quit to title", "fn": func(): Game.save_game(); _show_title()},
			]})


func _open_race_pause() -> void:
	race.active = false
	hud.open_menu(func():
		return {"title": "Race paused", "sub": "Forfeiting loses your entry fee.",
			"items": [
				{"label": "Back to the climb", "fn": func(): hud.close_menu(); on_menu_closed()},
				{"label": "Forfeit and return to town", "fn": _leave_race},
			]})


# ---- interactions -------------------------------------------------------

func _on_interact(kind: String) -> void:
	city.active = false
	match kind:
		"bike":
			hud.open_menu(_bike_shop_menu)
		"race":
			hud.open_menu(_race_menu)


func _bike_shop_menu() -> Dictionary:
	var items: Array = []
	for i in Game.bikes.size():
		var b: Dictionary = Game.bikes[i]
		var owned := Game.owned.has(i)
		var label := ""
		var enabled := true
		var fn := func(): pass
		if i == Game.equipped:
			label = "%s   [riding]" % b["name"]
			enabled = false
		elif owned:
			label = "%s   [equip]" % b["name"]
			fn = func():
				Game.equipped = i
				Talk.say_random("idle")
		else:
			label = "%s   $%d" % [b["name"], b["price"]]
			enabled = Game.money >= int(b["price"])
			fn = func():
				if Game.buy_bike(i):
					Game.toast.emit("New ride: %s!" % b["name"], Color(0.5, 1.0, 0.6))
					Talk.say_random("new_bike", true)
		var at_ftp: float = Game.speed_from_power(Game.ftp, b["mass"], b["cda"], b["crr"], 0.0) * 3.6
		var detail := "%s\n%.1f kg  |  %.0f HP  |  ~%.0f km/h at your FTP  |  handling x%.2f  |  gravel drag x%.2f" % [b["blurb"], b["mass"], b["hp"], at_ftp, b["turn"], b["gravel"]]
		items.append({"label": label, "fn": fn, "enabled": enabled, "detail": detail})
	var rc := Game.repair_cost()
	items.append({"label": ("Repair bike   $%d" % rc) if rc > 0 else "Repair bike   (already perfect)",
		"fn": func(): Game.repair(), "enabled": rc > 0 and Game.money >= rc,
		"detail": "Fresh tape, fresh grease. Bike HP %d / %d." % [int(Game.bike_hp()), int(Game.bike()["hp"])]})
	items.append({"label": "Leave", "fn": func(): hud.close_menu(); on_menu_closed(), "detail": ""})
	return {"title": "Spokes & Stuff Bike Shop", "sub": "Cash: $%d.   \"Careful out there. The cars don't brake for dreams.\"" % Game.money, "items": items}


func _race_menu() -> Dictionary:
	var items: Array = []
	for i in race.COURSES.size():
		var c: Dictionary = race.COURSES[i]
		items.append({"label": "%s    entry $%d   prize pool $%d" % [c["name"], c["entry"], c["prize"]],
			"fn": func(): _start_race(i), "enabled": Game.money >= int(c["entry"]) and Game.hp_ratio() > 0.1,
			"detail": "%s\nPayouts: 1st 100%%, 2nd 50%%, 3rd 30%%, 4th 15%%. Racing wears your bike a little." % c["blurb"]})
	items.append({"label": "Not today", "fn": func(): hud.close_menu(); on_menu_closed(), "detail": ""})
	return {"title": "Mt. Crankmore Race HQ", "sub": "%s %s warming up. You can hear %s talking about you." % [_cap(_rivals_text()), "is" if Talk.rivals.size() == 1 else "are", "them"], "items": items}


func _start_race(i: int) -> void:
	var c: Dictionary = race.COURSES[i]
	Game.add_money(-int(c["entry"]))
	hud.close_menu()
	mode = Mode.RACE
	city.active = false
	city.visible = false
	race.visible = true
	race.setup(i)
	race.active = true
	cam.position = race.cam_target()


func _on_race_finished(result: Dictionary) -> void:
	hud.open_menu(func():
		var lines := ""
		for i in result["order"].size():
			lines += "%d. %s\n" % [i + 1, result["order"][i]]
		var t: float = result["time"]
		return {"title": "%s: you placed #%d!" % [result["course"], result["place"]],
			"sub": "Time %d:%04.1f     Prize: $%d\n\n%s" % [int(t) / 60, fmod(t, 60.0), result["prize"], lines],
			"items": [{"label": "Back to town", "fn": _leave_race}]}, true)


func _leave_race() -> void:
	hud.close_menu()
	Trainer.send_grade(0.0)
	race.active = false
	race.visible = false
	city.visible = true
	mode = Mode.CITY
	city.active = true
	city.place_on(city.zone_anchor("race"))
	city.invuln = 1.5
	cam.position = city.cam_target()


## Dev helper: scripted pickup + delivery to check the order loop headlessly.
func _debug_flow() -> void:
	Game.money = 100
	_start_game()
	Engine.time_scale = 8.0
	for i in 2000:
		await get_tree().process_frame
		if not city.orders.is_empty():
			break
	var o: Dictionary = city.orders[0]
	print("order posted: shop=", city.shops[o["shop"]]["name"], " dest=", city.spots[o["dest"]]["name"], " pay=", o["pay"])
	city.place_on(city.shops[o["shop"]])
	for i in 200:
		await get_tree().process_frame
	print("picked up: ", not city.carry.is_empty(), " order state=", o["state"])
	if not city.carry.is_empty():
		city.place_on(city.spots[city.carry["dest"]])
		for i in 120:
			await get_tree().process_frame
	print("money=", Game.money, " deliveries=", Game.deliveries, " rival scores=", city.rival_score)
	get_tree().quit()


## Dev helper: ride on rails, cycling left/straight/right at each junction, logging the route.
func _debug_rails() -> void:
	_start_game()
	Input.action_press("pedal")
	Engine.time_scale = float(OS.get_environment("PIZZA_TS")) if OS.has_environment("PIZZA_TS") else 6.0
	var hits := [0]
	Game.toast.connect(func(t: String, _c: Color):
		if t.begins_with("HIT BY"):
			hits[0] += 1
			print("  HIT at ", city.roads[city.rr]["name"], " s=", snappedf(city.rs, 0.1), " pending=", not city.pending.is_empty()))
	var last_road := -1
	var last_j := -1
	var turn := 0
	var frames := int(OS.get_environment("PIZZA_FRAMES")) if OS.has_environment("PIZZA_FRAMES") else 2400
	for i in frames:
		await get_tree().process_frame
		if city.rr != last_road:
			last_road = city.rr
			print("on ", city.roads[city.rr]["name"], " s=", snappedf(city.rs, 0.1), " dir=", city.rdir)
		if not city.pending.is_empty() and city.pending["j"] != last_j:
			last_j = city.pending["j"]
			var keys: Array = city.pending["labels"].keys()
			var want: String = ["left", "straight", "right"][turn % 3]
			turn += 1
			if keys.has(want):
				city.pending["choice"] = want
			print("  junction ", last_j, " options=", keys, " gps=", city.pending["gps"], " chose=", city.pending["choice"])
	print("junctions=", city.junctions.size(), " hits=", hits[0], " game_seconds=", snappedf(frames / 60.0 * Engine.time_scale, 1))
	get_tree().quit()


## Dev helper: drive the Connect Trainer screen headlessly and print what the helper reports.
func _debug_trainer() -> void:
	_open_trainer_menu()
	for i in 4000:
		await get_tree().create_timer(0.05).timeout
		if i % 40 == 0:
			print("helper=", Trainer.helper_state, " msg='", Trainer.helper_msg, "' live=", Trainer.bridge_live,
				" scanning=", Trainer.status.get("scanning", false), " devices=", Trainer.devices().size(), " err='", Trainer.status.get("error", ""), "'")
		if Trainer.helper_state in ["stopped", "error"] and not Trainer.helper_installed() and i == 10:
			Trainer.install_helper()
		if Trainer.bridge_live and i % 100 == 0:
			Trainer.scan(true)
		if Trainer.bridge_live and i > 400 and (Trainer.devices().size() > 0 or i > 900):
			break
	for d in Trainer.devices():
		print("  found: ", d)
	print("menu items: ", hud.menu_cache.get("items", []).map(func(it): return it["label"]))
	get_tree().quit()


## Dev helper: PIZZA_DEBUG=shot saves screenshots to PIZZA_OUT (default user://shots). With PIZZA_AT="x,y;x,y"
## the camera visits those world points; otherwise it follows the rider for PIZZA_SHOTS frames, one every second.
func _debug_shot() -> void:
	_start_game()
	Input.action_press("pedal")
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var spots: Array = []
	if OS.get_environment("PIZZA_AT") == "junctions":
		for j in city.junctions:
			spots.append(j["pos"])
	elif OS.get_environment("PIZZA_AT") == "shops":
		for k in 3:
			city._post_order()
		for sh in city.shops:
			spots.append(sh["chef"])
	else:
		for part in OS.get_environment("PIZZA_AT").split(";", false):
			var xy := part.split(",")
			spots.append(Vector2(xy[0].to_float(), xy[1].to_float()))
	var n := spots.size() if not spots.is_empty() else OS.get_environment("PIZZA_SHOTS").to_int() if OS.has_environment("PIZZA_SHOTS") else 8
	for k in n:
		if not spots.is_empty():
			shot_at = spots[k]
			cam.position = Iso.to_screen(shot_at, 12.0 + Iso.ground_z(shot_at))
			for i in 4:
				await get_tree().process_frame
		else:
			await get_tree().create_timer(1.0).timeout
			if OS.has_environment("PIZZA_SHIFT"):   # shift up before each shot, to see the gear pop-up
				Trainer.shift(1)
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/shot_%02d.png" % [out, k])
	get_tree().quit()


## Dev helper: PIZZA_DEBUG=readme saves the README screenshots (title screen, then out on a delivery with the
## pizza on the bike) to PIZZA_OUT (default docs/). The player's save file is put back afterwards.
func _debug_readme() -> void:
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else ProjectSettings.globalize_path("res://docs")
	DirAccess.make_dir_recursive_absolute(out)
	var backup := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var save := func(file: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s" % [out, file])
	await get_tree().create_timer(2.0).timeout
	await save.call("title.png")
	_start_game()
	Input.action_press("pedal")
	while city.orders.is_empty():
		await get_tree().process_frame
	city.place_on(city.shops[city.orders[0]["shop"]])
	while city.carry.is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(5.0).timeout   # ride off with the box steaming on the bike, toasts faded
	await save.call("delivery.png")
	if backup != "":
		FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE).store_string(backup)
	get_tree().quit()


## Dev helper: graph checks for the road network (junction count, dead ends, unreachable roads).
func _debug_roads() -> void:
	var dead := 0
	for ri in city.roads.size():
		var r: Dictionary = city.roads[ri]
		if r["closed"]:
			continue
		for end_s in [0.0, float(r["len"])]:
			var found := false
			for e in city.road_js[ri]:
				if absf(float(e[0]) - end_s) < 1.6:
					found = true
			if not found:
				dead += 1
				print("DEAD END: ", r["name"], " at s=", end_s)
	# every road reachable from the plaza loop through junctions?
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var ri: int = stack.pop_back()
		for e in city.road_js[ri]:
			for l in city.junctions[e[1]]["links"]:
				if not seen.has(l[0]):
					seen[l[0]] = true
					stack.append(l[0])
	# grass gaps: walk between the road points that meet at each junction and check the asphalt covers the way
	var gaps := 0
	for ji in city.junctions.size():
		var links: Array = city.junctions[ji]["links"]
		for a in links:
			for b in links:
				var pa: Vector2 = city._road_at(city.roads[a[0]], a[1])[0]
				var pb: Vector2 = city._road_at(city.roads[b[0]], b[1])[0]
				for k in 9:
					var q := pa.lerp(pb, k / 8.0)
					if city.road_dist(q) > city.ROAD_HW * 0.9:
						gaps += 1
						print("GAP at junction ", ji, " ", city.roads[a[0]]["name"], " / ", city.roads[b[0]]["name"], " ", q, " d=", pa.distance_to(pb))
						break
	# holes in the drawn asphalt: points on the road that no ribbon polygon covers on screen
	Iso.terrain_on = true
	var bad_poly := 0
	for seg in city.road_draw:
		if Geometry2D.triangulate_polygon(seg[2]).is_empty():
			bad_poly += 1
	var holes := 0
	for r in city.roads:
		var s := 0.0
		while s < float(r["len"]):
			var at: Array = city._road_at(r, s)
			var nrm := Vector2(-at[1].y, at[1].x)
			for off in [-0.9, -0.5, 0.0, 0.5, 0.9]:
				var q: Vector2 = at[0] + nrm * off
				var sq := Iso.to_screen(q)
				var covered := false
				for seg in city.road_draw:
					if seg[0].distance_to(sq) < 90.0 and Geometry2D.is_point_in_polygon(sq, seg[2]):
						covered = true
						break
				if not covered:
					holes += 1
					print("HOLE on ", r["name"], " s=", snappedf(s, 0.1), " off=", off, " at ", q)
			s += 0.25
	Iso.terrain_on = false
	# roads that touch or cross away from a junction
	var cross := 0
	for ia in city.roads.size():
		for ib in range(ia + 1, city.roads.size()):
			var pa: PackedVector2Array = city.roads[ia]["pts"]
			var pb: PackedVector2Array = city.roads[ib]["pts"]
			for i in range(0, pa.size(), 2):
				for k in range(0, pb.size(), 2):
					if pa[i].distance_to(pb[k]) < 2.4:
						var near_j := false
						for j in city.junctions:
							if j["pos"].distance_to(pa[i]) < 5.0:
								near_j = true
						if not near_j:
							cross += 1
							print("CLOSE ", city.roads[ia]["name"], " / ", city.roads[ib]["name"], " at ", pa[i], " d=", pa[i].distance_to(pb[k]))
	print("gaps=", gaps, " bad_polys=", bad_poly, " holes=", holes, " close=", cross)
	print("roads=", city.roads.size(), " junctions=", city.junctions.size(), " dead_ends=", dead, " reachable=", seen.size(),
		" buildings=", city.buildings.size(), " shops=", city.shops.size(), " spots=", city.spots.size(), " trees=", city.trees.size(), " cars=", city.cars.size())
	get_tree().quit()


## Dev helper: tap a direction once (press + release) before a junction and check it's used.
func _debug_latch() -> void:
	_start_game()
	Input.action_press("pedal")
	Engine.time_scale = 3.0
	var tests := 0
	var ok := 0
	var tapped := false
	var want := ""
	var road_before := -1
	for i in 6000:
		await get_tree().process_frame
		if not tapped and city.pending.is_empty():
			var nj: Array = city._next_junction()
			if nj[0] >= 0 and nj[1] > 12.0:
				var lab: Dictionary = city._label_options(city._options(nj[0], city.rr, city.rdir))
				if lab.size() > 1:
					want = "left" if lab.has("left") else "right"
					var act := "steer_left" if want == "left" else "steer_right"
					Input.action_press(act)
					await get_tree().process_frame
					Input.action_release(act)
					tapped = true
					road_before = city.rr
		elif tapped and not city.pending.is_empty() and city.pending["dist"] < 0.6:
			tests += 1
			if city.pending["choice"] == want:
				ok += 1
			print("junction ", city.pending["j"], ": tapped ", want, " early, panel choice=", city.pending["choice"])
			tapped = false
			for k in 30:
				await get_tree().process_frame
		if tests >= 6:
			break
	print("latched ", ok, "/", tests)
	get_tree().quit()
