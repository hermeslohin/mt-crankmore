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
	get_tree().auto_accept_quit = false   # closing the window goes through _quit, so the game gets saved
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
	var sky := CanvasLayer.new()   # falling snow, leaves and petals, under the HUD
	sky.layer = 5
	add_child(sky)
	var weather := preload("res://scripts/weather.gd").new()
	weather.cam = cam
	sky.add_child(weather)
	if OS.has_environment("PIZZA_SEASON"):   # dev helper: PIZZA_SEASON=spring|summer|fall|winter
		Season.set_choice(OS.get_environment("PIZZA_SEASON"))
	var dusk := CanvasLayer.new()   # night and rain clouds over the world and the weather, under the HUD
	dusk.layer = 6
	add_child(dusk)
	var night := preload("res://scripts/night.gd").new()
	night.source = func(): return city.night_lights() if mode == Mode.CITY else race.night_lights() if mode == Mode.RACE else []
	dusk.add_child(night)
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
			_start_race(OS.get_environment("PIZZA_COURSE").to_int())
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
		"race_shot":
			_debug_race_shot()
		"readme":
			_debug_readme()
		"powerups":
			_debug_powerups()
		"gears":
			_debug_gears()
		"ride":
			_debug_ride()
		"events":
			_debug_events()
		"wipeout":
			_debug_wipeout()
		"animals":
			_debug_animals()
		"buildings":
			_start_game()
			var count := {}
			for b in city.buildings:
				var key := "%s %dx%d" % [b["kind"], int(b["size"].x), int(b["size"].y)]
				count[key] = int(count.get(key, 0)) + 1
			print("BUILDINGS total=%d %s" % [city.buildings.size(), count])
			get_tree().quit()
		"seasons":
			_debug_seasons()
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


## Quitting (the title screen's Quit or closing the window) saves the game. The ride isn't posted: it stays saved
## until you post it from the Strava menu or the pause menu.
func _quit() -> void:
	Game.save_game()
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
	# log the ride for Strava (the dev helpers don't, so they never leave fake rides behind)
	if OS.get_environment("PIZZA_DEBUG") in ["", "ride"]:
		if mode == Mode.CITY and city.active and city.er_timer <= 0.0:
			Ride.tick(delta, city.p_speed / (city.TILES_PER_MS * city.PACE), city.grade)
		elif mode == Mode.RACE and race.active and not race.over:
			Ride.tick(delta, race.riders[0]["v"], race._grade_at(race.riders[0]["s"]))
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
		return {"title": "Welcome to Mt. Crankmore", "sub": "%s.\n%s in Crankmore Village. %s. One mountain. Just pedal: your bike follows the road. At junctions pick LEFT / RIGHT or UP for straight (DOWN = U-turn). Shifters change gear (1-21). Keyboard: W pedal, Shift sprint, Q / R shift gear, arrows choose, S brake, Y use power-up, H shout, E select." % [Game.SLOGAN, Season.NAMES[Season.current], _cap(_rivals_text())],
			"items": [
				{"label": "Continue game", "fn": _start_or_setup, "enabled": Game.has_save(),
					"detail": "$%d  |  %d deliveries" % [Game.money, Game.deliveries] if Game.has_save() else "No saved game yet"},
				{"label": "New game", "fn": _new_game, "detail": "Start over with $%d. Deletes your save." % Game.START_MONEY},
				{"label": "Rider setup", "fn": _open_setup.bind(_show_title),
					"detail": "FTP %d W  |  %s  |  %.1f W/kg  |  %s  |  %d rival%s" % [int(Game.ftp), Game.weight_text(), Game.wkg(),
						Game.DIFFICULTIES[Game.difficulty]["label"], Game.rival_count, "" if Game.rival_count == 1 else "s"]},
				_season_item(),
				{"label": "Connect Trainer", "fn": _open_trainer_menu, "detail": Trainer.status_text()},
				{"label": "Strava", "fn": _open_strava_menu.bind(_show_title), "detail": "%s  |  this ride: %s" % [Strava.status_text(), Ride.summary()]},
				{"label": "Quit", "fn": _quit},
			], "live": true}, true)
	if not Game.has_save():
		hud.menu_index = 1  # nothing to continue: start on "New game"
		hud._rebuild_menu()


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


# ---- Strava ----------------------------------------------------------------

## Link a Strava account and post the ride. `back` reopens the screen this was opened from (title or pause).
func _open_strava_menu(back: Callable) -> void:
	if Strava.state in ["done", "error"]:
		Strava.state = "idle"
		Strava.msg = ""
	hud.open_menu(_strava_menu.bind(back))


func _strava_menu(back: Callable) -> Dictionary:
	var items: Array = []
	var lines: Array = ["This ride: " + Ride.summary()]
	if not Strava.has_app():
		lines.append("One-time setup: on strava.com/settings/api create an app (any name and website; Authorization Callback Domain: localhost). Copy its Client ID, pick Paste Client ID, then do the same for the Client Secret.")
		items.append({"label": "Open Strava API settings", "fn": func(): OS.shell_open(Strava.SETTINGS_URL),
			"detail": "Opens %s in your browser." % Strava.SETTINGS_URL})
		items.append({"label": "Paste Client ID" + ("  (%s)" % Strava.client_id if Strava.client_id != "" else ""), "fn": Strava.paste_client_id,
			"detail": "Copy the Client ID from the Strava page first."})
		items.append({"label": "Paste Client Secret" + ("  (set)" if Strava.client_secret != "" else ""), "fn": Strava.paste_client_secret,
			"detail": "On the Strava page click Show next to Client Secret, copy it, then pick this. It's kept only on this computer."})
	elif not Strava.linked():
		items.append({"label": "Waiting for Strava..." if Strava.state == "linking" else "Link Strava account", "fn": Strava.start_link,
			"enabled": Strava.state != "linking", "detail": "Opens Strava in your browser. Approve Mt. Crankmore (leave \"Upload your activities\" ticked) and come back."})
		items.append({"label": "Change Client ID / Secret", "fn": func():
			Strava.client_secret = ""
			Strava._save(), "detail": "Clears the Client Secret so you can paste new app details."})
	else:
		lines.append(Strava.status_text() + ". Post your ride here or from the pause menu; it's kept until you do.")
		var post_label := "Uploading..." if Strava.busy() else "Post this ride to Strava"
		items.append({"label": post_label, "fn": Strava.post_ride, "enabled": not Strava.busy() and Ride.can_post(),
			"detail": ("Posts a Virtual Ride with your distance, speed, power and cadence, and the pizzas and races in the notes:\n%s" % Ride.description()) if Ride.can_post() else "Ride for at least a minute first."})
		if not Strava.last_activity.is_empty():
			var shots_dir: String = Strava.last_activity.get("shots_dir", "")
			items.append({"label": "Add screenshots to the last ride" if shots_dir != "" else "Open the last ride on Strava", "fn": Strava.open_last_activity,
				"detail": "Strava doesn't let games attach photos, so this opens the activity and the folder with its screenshots: drag them onto the activity." if shots_dir != "" else "Opens the activity in your browser."})
		items.append({"label": "Unlink Strava", "fn": Strava.unlink, "enabled": not Strava.busy(), "detail": "Disconnects the game from your Strava account."})
	if Ride.seconds() > 0:
		items.append({"label": "Discard this ride", "fn": func(): Ride.reset(), "enabled": not Strava.busy(),
			"detail": "Throws away the ride recorded so far (and its screenshots) and starts a new one."})
	if Strava.msg != "":
		lines.append(("! " if Strava.state == "error" else "") + Strava.msg)
	items.append({"label": "Back", "fn": back, "detail": ""})
	return {"title": "Strava", "sub": "\n".join(lines), "items": items, "live": true}


func _rivals_text() -> String:
	var words := ["", "one", "two", "three", "four", "five", "six", "seven"]
	var n: int = Talk.rivals.size()
	return "%s rival pizza biker%s" % [words[n] if n < words.size() else str(n), "" if n == 1 else "s"]


func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


## First ride: ask for FTP / weight / difficulty before heading out.
func _new_game() -> void:
	Game.new_game()
	_start_or_setup()


func _start_or_setup() -> void:
	if Game.setup_done:
		_start_game()
	else:
		_open_setup(_start_game)


# ---- rider setup ---------------------------------------------------------

## Rider (boy or girl), FTP, weight (kg or lbs), difficulty and how many rivals ride. Everything is changed with LEFT / RIGHT,
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
		{"label": "Rider: %s" % Game.RIDERS[Game.rider]["label"], "fn": func(): Game.set_rider("girl" if Game.rider == "boy" else "boy"),
			"adjust": func(_d: int): Game.set_rider("girl" if Game.rider == "boy" else "boy"),
			"detail": "Who you ride as: Rookie Boy or Rookie Girl."},
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
				_season_item(),
				{"label": "Post ride to Strava", "fn": _open_strava_menu.bind(_open_pause), "detail": Ride.summary()},
				{"label": "Quit to title", "fn": func(): Game.save_game(); _show_title()},
			]})


## LEFT / RIGHT picks the season (or select to step through them). "Today" follows the date.
func _season_item() -> Dictionary:
	var change := func(d: int):
		Season.step(d)
		Game.save_game()
	return {"label": "Season: %s" % Season.label(), "fn": change.bind(1), "adjust": change,
		"detail": "Snow, snowmen and skiers in winter; blossom, tulips and butterflies in spring; kites, frisbees and beach volleyball in summer; orange trees, pumpkins and falling leaves in fall. \"Today\" follows the date (it's %s)." % Season.NAMES[Season.today()].to_lower()}


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
	# cheapest first (the list itself stays in save order, so saved garages keep their bikes)
	var order: Array = range(Game.bikes.size())
	order.sort_custom(func(a, b): return int(Game.bikes[a]["price"]) < int(Game.bikes[b]["price"]))
	for i in order:
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
		var detail := "%s%s\n%.1f kg  |  %.0f HP  |  ~%.0f km/h at your FTP  |  handling x%.2f  |  gravel drag x%.2f" % [b["blurb"], "  One gear, no brakes." if b.get("fixed", false) else "", b["mass"], b["hp"], at_ftp, b["turn"], b["gravel"]]
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
	Ride.on_race_finished(result["place"])
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


## Dev helper: PIZZA_DEBUG=ride [PIZZA_OUT=dir] rides the town for a few seconds, then writes the Strava TCX file to
## PIZZA_OUT (default user://shots) and prints the ride summary and notes. The recorded ride is put back afterwards.
func _debug_ride() -> void:
	var path := Ride.DIR.path_join("ride.json")
	var backup := FileAccess.get_file_as_string(path)
	Ride.reset()
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	_start_game()
	Input.action_press("pedal")
	await get_tree().create_timer(6.0).timeout
	Game.deliveries += 2
	Ride.on_race_finished(1)
	await get_tree().create_timer(1.5).timeout
	print("RIDE: ", Ride.summary(), "  samples=", Ride.samples.size(), "  can_post=", Ride.can_post())
	print("RIDE title: ", Ride.title())
	print("RIDE notes:\n", Ride.description())
	FileAccess.open(out.path_join("ride.tcx"), FileAccess.WRITE).store_string(Ride.to_tcx())
	print("RIDE tcx: ", ProjectSettings.globalize_path(out.path_join("ride.tcx")))
	for s in Ride.shots:
		DirAccess.copy_absolute(Ride.DIR.path_join(s["file"]), out.path_join(s["file"]))
		print("RIDE shot: ", s["kind"], " ", s["file"])
	Game.deliveries -= 2
	Ride.reset()
	if backup != "":
		FileAccess.open(path, FileAccess.WRITE).store_string(backup)
		Ride._load()
	get_tree().quit()


## Dev helper: PIZZA_DEBUG=seasons [PIZZA_OUT=dir] saves, for each season, the title view and a close-up of each
## kind of that season's scenery in town. The player's save file is put back afterwards.
func _debug_seasons() -> void:
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var backup := FileAccess.get_file_as_string(Game.SAVE_PATH)
	for se in Season.ORDER:
		Season.set_choice(se)
		_show_title()
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_title.png" % [out, se])
		_start_game()
		var seen := {}
		for e in city.season_props:
			if e["season"] != se or seen.has(e["kind"]):
				continue
			seen[e["kind"]] = true
			shot_at = city._sprop_pos(e)
			cam.position = Iso.to_screen(shot_at, 12.0 + Iso.ground_z(shot_at))
			await get_tree().create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, se, e["kind"]])
		shot_at = Vector2.INF
		print("SEASON %s: %s" % [se, seen.keys()])
	if backup != "":
		FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE).store_string(backup)
	get_tree().quit()


## Dev helper: PIZZA_DEBUG=wipeout [PIZZA_OUT=dir] knocks the player and the first rival down (a frisbee-style hit), then
## runs the player over with a car, saving a screenshot at several moments of each wipe-out animation.
## Dev helper: PIZZA_DEBUG=events [PIZZA_OUT=dir] sets off every kind of town happening (see TownEvents) right next to
## the player and saves a screenshot of each. The player's save file is put back afterwards.
func _debug_events() -> void:
	var backup := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	Trainer._autostart_clock = 0.0
	_start_game()
	await get_tree().create_timer(1.0).timeout
	city.events.near = 2.5
	city.events.far = 5.0
	city.events.next_t = 999.0
	for kind in ["crowd", "dog", "pigeons", "cat", "band", "busker", "mime", "truck", "ball", "balloon", "siren", "parade"]:
		city.events.events.clear()
		city.events.start(kind)
		print("event %s: %s" % [kind, "started" if not city.events.events.is_empty() else "skipped (no art or no spot)"])
		await get_tree().create_timer(1.2).timeout
		cam.position = city.cam_target()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/event_%s.png" % [out, kind])
	if backup != "":
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	get_tree().quit()


func _debug_wipeout() -> void:
	var backup := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	Trainer._autostart_clock = 0.0
	_start_game()
	Input.action_press("pedal")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("pedal")
	var r: Dictionary = city.rival_state[0]
	r["pos"] = city.p_pos + city.p_fwd * 3.0
	r["path"] = []
	r["state"] = "idle"
	r["idle"] = 99.0
	city._knock_down(0, 5.0, -1, "")
	city._knock_down(-1, 5.0, 0, "beaned you")
	var shot := func(file: String) -> void:
		cam.position = city.cam_target()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s" % [out, file])
	var at := 0.0
	for t in [0.05, 0.3, 0.6, 1.0, 2.0]:
		await get_tree().create_timer(t - at).timeout
		at = t
		await shot.call("wipe_pu_%.2f.png" % t)
	city.p_down = 0.0
	city._hit_by_car({"speed": 0.0})
	at = 0.0
	for t in [0.05, 0.5, 1.2, 2.5]:
		await get_tree().create_timer(t - at).timeout
		at = t
		await shot.call("wipe_car_%.2f.png" % t)
	print("WIPEOUT: p_fall=%.2f er_timer=%.2f" % [city.p_fall, city.er_timer])
	if backup != "":
		FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE).store_string(backup)
	get_tree().quit()


## Dev helper: PIZZA_DEBUG=animals [PIZZA_OUT=dir] lines up one of every animal beside the player in a race (standing,
## then running; the bear also roaring) and saves a screenshot of each.
func _debug_animals() -> void:
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	Trainer._autostart_clock = 0.0
	Game.money = maxi(Game.money, 1000)
	_start_race(0)
	await get_tree().create_timer(0.3).timeout
	var kinds := ["bear", "deer", "moose", "goat", "marmot", "rabbit", "squirrel", "fox", "elk", "wolf", "raccoon", "hedgehog", "chipmunk", "skunk", "bighorn", "badger", "mountain_lion", "porcupine", "otter", "beaver", "coyote", "ram_lamb"]
	var s0 := float(race.riders[0]["s"]) + 4.0
	for look in ["idle", "run", "roar"]:
		race.animals.clear()
		for i in kinds.size():
			var side := 1.0 if i % 2 == 0 else -1.0
			var p: Vector2 = race._pose(s0 + i * 0.9, side * (1.6 + (i % 3) * 0.9))["pos"]
			race.animals.append({"kind": kinds[i], "pos": p, "home": p, "s": s0 + i, "side": side, "state": "roar" if look == "roar" else "idle", "t": 99.0,
				"face": 1.0 if i % 4 < 2 else -1.0, "vel": Vector2.ZERO, "phase": float(i), "run": look == "run", "cross": false, "stag": true,
				"dark": i % 3 == 1, "done": true})
		race.riders[0]["s"] = s0 - 3.0
		race.riders[0]["v"] = 0.0
		for k in 3:
			await get_tree().process_frame
		cam.position = race.cam_target()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/animals_%s.png" % [out, look])
	get_tree().quit()


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
## PIZZA_CARRY=1 rides with a pizza on board.
func _debug_shot() -> void:
	_start_game()
	Input.action_press("pedal")
	if OS.has_environment("PIZZA_CARRY"):
		city._post_order()
		city._take_order(city.orders[-1])
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var spots: Array = []
	if OS.get_environment("PIZZA_AT") == "junctions":
		for j in city.junctions:
			spots.append(j["pos"])
	elif OS.get_environment("PIZZA_AT") == "er":
		spots.append(city.zone_anchor("er")["pos"])
	elif OS.get_environment("PIZZA_AT") == "townhall":
		for b in city.buildings:
			if b["kind"] == "townhall":
				spots.append(b["door"])
	elif OS.get_environment("PIZZA_AT") == "nineties":
		for b in city.buildings:
			if city.SHOP_90S.has(str(b.get("name", ""))):
				spots.append(b["door"])
		for p in city.props:
			if p["kind"] == "tube" or str(p.get("art", "")) in ["basketball_hoop", "skate_ramp"]:
				spots.append(p["pos"])
	elif OS.get_environment("PIZZA_AT") == "edges":   # the buildings out by the edge of the map
		for b in city.buildings:
			var c: Vector2 = b["pos"] + b["size"] * 0.5
			if minf(minf(c.x, c.y), minf(city.N - c.x, city.N - c.y)) < 22.0:
				spots.append(c)
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


## Dev helper: PIZZA_DEBUG=race_shot [PIZZA_COURSE=0|1] [PIZZA_OUT=dir] saves race screenshots just before the first
## jump, log, creek and bear, and at the finish. The player's save file is put back afterwards.
func _debug_race_shot() -> void:
	Trainer._autostart_clock = 0.0   # leave a real trainer alone
	var backup := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	_start_game()
	Game.money = maxi(Game.money, 1000)
	_start_race(OS.get_environment("PIZZA_COURSE").to_int())
	Input.action_press("pedal")
	var gmin := 1.0
	var gmax := -1.0
	for g in race.grade_a:
		gmin = minf(gmin, g)
		gmax = maxf(gmax, g)
	print("COURSE %s: %.0f m, gain %.0f m, grade %+.1f%% to %+.1f%%, %d obstacles" % [race.course["name"], race.course["length"],
		race.gain, gmin * 100.0, gmax * 100.0, race.obstacles.size()])
	print("  %d hairpins, %d tunnels, %d steep/drop stretches" % [race.hairpins.size(), race.tunnels.size(), race.ramps.size()])
	print("  %d skiers, chairlift %s, %d groomers, railway %s with %d crossings" % [race.life.skiers.size(), "yes" if not race.life.lift.is_empty() else "no",
		race.life.groomers.size(), "yes" if race.life.rail_x >= 0.0 else "no", race.life.crossings.size()])
	var spots: Array = race.debug_spots()
	for k in spots.size():
		race.debug_place(spots[k])
		cam.position = race.cam_target()
		await get_tree().create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/race_%02d.png" % [out, k])
	if backup != "":
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	get_tree().quit()


## Dev helper: PIZZA_DEBUG=powerups [PIZZA_OUT=dir] uses every power-up next to a rival in town and in a race, saving a
## screenshot of each and printing what happened, then lets the town run fast so the rivals grab and use them on
## their own. The player's save file is put back afterwards.
func _debug_powerups() -> void:
	var backup := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var out := OS.get_environment("PIZZA_OUT") if OS.has_environment("PIZZA_OUT") else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var save := func(file: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s" % [out, file])
	Trainer._autostart_clock = 0.0   # leave a real trainer alone
	_start_game()
	Input.action_press("pedal")
	await get_tree().create_timer(1.5).timeout
	Input.action_press("lane_left")   # slide across the lane
	await get_tree().create_timer(0.5).timeout
	Input.action_release("lane_left")
	print("TOWN lane: p_lat=%.2f" % city.p_lat)
	for kind in PowerUps.TOWN:
		var r: Dictionary = city.rival_state[0]
		r["pos"] = city.p_pos + city.p_fwd * 1.0
		r["path"] = []
		r["state"] = "idle"
		r["idle"] = 99.0
		r["stun"] = 0.0
		if kind == "portal" and city.orders.is_empty():
			city._post_order()
		if kind == "wrench":
			Game.hp[Game.equipped] = 10.0
		city.pu = kind
		city._use_powerup(-1)
		await get_tree().create_timer(0.7).timeout
		cam.position = city.cam_target()
		print("TOWN %s: active=%s used=%s rival_stun=%.1f hp=%d socks=%.1f bread=%.1f mascots=%d carry=%s" % [kind, city.active, city.pu == "",
			r["stun"], int(Game.bike_hp()), city.socks_t, city.bread_t, city.mascots.size(), not city.carry.is_empty()])
		await save.call("pu_town_%s.png" % kind)
		city.socks_t = 0.0
		city.bread_t = 0.0
		city.p_down = 0.0
	# breadsticks run-over: ride into a rival while huge
	var rv: Dictionary = city.rival_state[0]
	rv["stun"] = 0.0
	city.bread_t = PowerUps.BREAD_TIME
	rv["pos"] = city.p_pos
	await get_tree().process_frame
	print("TOWN squash: rival_stun=%.1f" % rv["stun"])
	city.bread_t = 0.0
	# let the rivals loose: they should grab and use power-ups themselves
	var grabbed := 0
	var seen := {}
	Engine.time_scale = 10.0
	for i in 600:
		await get_tree().create_timer(0.1).timeout
		for k in city.rival_state.size():
			var kind: String = city.rival_state[k]["pu"]
			if kind != "" and not seen.get(k, false):
				grabbed += 1
			seen[k] = kind != ""
	Engine.time_scale = 1.0
	print("TOWN rivals: grabbed=%d player_down=%.1f" % [grabbed, city.p_down])
	# race
	Game.money = maxi(Game.money, 1000)
	_start_race(0)
	Input.action_press("pedal")
	race.debug_place(float(race.givers[1]["s"]) + 3.0)
	race.riders[0]["s"] = float(race.givers[1]["s"]) - 1.0
	race.riders[0]["gv"] = 1
	await get_tree().create_timer(0.5).timeout
	print("RACE giver: player has %s" % race.riders[0]["pu"])
	cam.position = race.cam_target()
	await save.call("pu_race_giver.png")
	for kind in PowerUps.RACE:
		var me: Dictionary = race.riders[0]
		var r: Dictionary = race.riders[1]
		r["s"] = float(me["s"]) + 2.5
		r["lat"] = me["lat"]
		r["down"] = 0.0
		me["down"] = 0.0
		me["pu"] = kind
		race._use_powerup(0)
		await get_tree().create_timer(0.7).timeout
		cam.position = race.cam_target()
		var downs: int = race.riders.filter(func(o): return float(o["down"]) > 0.0).size()
		print("RACE %s: used=%s riders_down=%d socks=%.1f bread=%.1f roller=%.1f draft=%d%%" % [kind, me["pu"] == "", downs,
			me["socks"], me["bread"], me["roller"], roundi(float(me["draft"]) * 100.0)])
		await save.call("pu_race_%s.png" % kind)
	if backup != "":
		FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE).store_string(backup)
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
