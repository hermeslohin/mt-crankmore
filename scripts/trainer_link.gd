extends Node
## Talks to bridge/trainer_bridge.py over localhost UDP, and runs that bridge ("the Bluetooth helper")
## for the player: it installs it into bridge/.venv, launches it in --managed mode, and sends it
## scan / connect / disconnect commands from the Connect Trainer screen.
## Bridge -> game (port 9871): {"type":"data", "power","cadence","speed","buttons":[...],"trainer","controller"}
##                             {"type":"status", "scanning", "devices":[...], "trainer":{...}, "controller":{...}, "error"}
## Game -> bridge (port 9872): {"grade": percent, "gear": ratio, "mass": kg} or {"cmd": "ping"|"scan"|"connect"|"disconnect"|"quit", ...}
## With no bridge running, the keyboard stands in for the trainer and controllers.
## Virtual shifting: a 21-speed bike, gear 1 (easiest) to 21 (hardest). LS1 (left shifter) shifts
## down, RS1 (right shifter) shifts up. The bridge turns the gear into trainer resistance, so an easier gear
## pushes back less and you make fewer watts at the same cadence.

const RX_PORT := 9871
const TX_PORT := 9872

const GEARS := 21
const START_GEAR := 11
const EASIEST := 0.33    # gear 1, ratio to gear 11
const HARDEST := 2.55    # gear 21

## Shifter buttons: LS1 = easier, RS1 = harder.
const SHIFT_BUTTONS := {"LS1": -1, "RS1": 1}

## Controller button name -> game action.
const BUTTON_ACTIONS := {
	"LEFT": "steer_left",
	"RIGHT": "steer_right",
	"UP": "act_up",
	"DOWN": "act_down",
	"A": "act_select",
	"B": "act_back",
	"Y": "powerup",
	"Z": "honk",
	"RS2": "powerup",
	"LS2": "brake",
	"POWERUP_R": "powerup",
	"POWERUP_L": "brake",
	"PADDLE_L": "steer_left",
	"PADDLE_R": "steer_right",
}

var rx := PacketPeerUDP.new()
var tx := PacketPeerUDP.new()

var trainer_power := 0.0
var trainer_cadence := 0.0
var trainer_speed_kmh := 0.0
var trainer_live := false
var controller_live := false
var bridge_live := false
var last_msg_ms := -100000
var last_trainer_ms := -100000

var kb_power := 0.0
var kb_cadence := 0.0

var pressed_names: Array = []
var gear := START_GEAR
var shift_flash := 0.0            # seconds left to show the big gear number after a shift
var status: Dictionary = {}       # latest {"type":"status"} from the bridge
var helper_pid := -1
var helper_state := "stopped"     # stopped | installing | starting | running | error
var helper_msg := ""
var _install_thread: Thread
var _install_log := ""
var _ping_clock := 0.0
var _autostart_clock := 1.5

var _held: Dictionary = {}
var _pressed_frame: Dictionary = {}   # action -> process frame it was pressed in
var _release_later: Array = []         # releases that arrived in the same frame as their press
var _grade_sent := 999.0
var _grade_clock := 0.0


func _ready() -> void:
	var err := rx.bind(RX_PORT, "127.0.0.1")
	if err != OK:
		push_warning("Trainer link: could not bind UDP %d (%s). Keyboard only." % [RX_PORT, error_string(err)])
	tx.set_dest_address("127.0.0.1", TX_PORT)


func _exit_tree() -> void:
	stop_helper()


# ---- the Bluetooth helper (bridge) ----------------------------------------

## From the editor the helper runs in place; in an exported build res:// is packed, so its files are copied to user://bridge.
func bridge_dir() -> String:
	if not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://bridge")
	var dir := ProjectSettings.globalize_path("user://bridge")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["trainer_bridge.py", "requirements.txt"]:
		var src := FileAccess.get_file_as_bytes("res://bridge/" + f)
		if src.is_empty():
			continue
		var dst := FileAccess.open(dir + "/" + f, FileAccess.WRITE)
		if dst != null:
			dst.store_buffer(src)
	return dir


func venv_python() -> String:
	for p in [bridge_dir() + "/.venv/bin/python", bridge_dir() + "/.venv/Scripts/python.exe"]:
		if FileAccess.file_exists(p):
			return p
	return ""


func system_python() -> String:
	for p in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]:
		if FileAccess.file_exists(p):
			return p
	var out: Array = []
	if OS.execute("python3", ["--version"], out) == 0:
		return "python3"
	if OS.execute("python", ["--version"], out) == 0:
		return "python"
	return ""


func helper_installed() -> bool:
	return venv_python() != ""


func start_helper() -> void:
	if bridge_live or helper_state == "installing":
		return
	var py := venv_python()
	if py == "":
		helper_state = "error"
		helper_msg = "The Bluetooth helper isn't installed yet."
		return
	helper_pid = OS.create_process(py, [bridge_dir() + "/trainer_bridge.py", "--managed"])
	if helper_pid > 0:
		helper_state = "starting"
		helper_msg = "Starting the Bluetooth helper..."
	else:
		helper_state = "error"
		helper_msg = "Could not start %s" % py


func stop_helper() -> void:
	send_cmd({"cmd": "quit"})
	if helper_pid > 0:
		OS.kill(helper_pid)
		helper_pid = -1


## One-time setup: a private Python environment in bridge/.venv with the Bluetooth library.
func install_helper() -> void:
	if helper_state == "installing":
		return
	var py := system_python()
	if py == "":
		helper_state = "error"
		helper_msg = "Python 3 was not found. Install it from python.org, then try again."
		return
	helper_state = "installing"
	helper_msg = "Installing the Bluetooth helper (about a minute, needs internet)..."
	_install_thread = Thread.new()
	_install_thread.start(_install.bind(py))


func _install(py: String) -> int:
	var out: Array = []
	var venv := bridge_dir() + "/.venv"
	var code := OS.execute(py, ["-m", "venv", venv], out, true)
	if code == 0:
		var vpy := venv + ("/Scripts/python.exe" if OS.get_name() == "Windows" else "/bin/python")
		code = OS.execute(vpy, ["-m", "pip", "install", "--disable-pip-version-check", "-q", "-r", bridge_dir() + "/requirements.txt"], out, true)
	_install_log = "\n".join(out)
	return code


func send_cmd(d: Dictionary) -> void:
	tx.put_packet(JSON.stringify(d).to_utf8_buffer())


func scan(on: bool) -> void:
	send_cmd({"cmd": "scan", "on": on})


func connect_device(role: String, address: String) -> void:
	send_cmd({"cmd": "connect", "role": role, "address": address})


func disconnect_device(role: String) -> void:
	send_cmd({"cmd": "disconnect", "role": role})


func devices() -> Array:
	return status.get("devices", [])


func role_info(role: String) -> Dictionary:
	return status.get(role, {"state": "idle", "name": "", "address": ""})


func _process(delta: float) -> void:
	for action in _release_later:
		if not _held.has(action):
			Input.action_release(action)
	_release_later.clear()
	while rx.get_available_packet_count() > 0:
		var txt := rx.get_packet().get_string_from_utf8()
		var d = JSON.parse_string(txt)
		if typeof(d) == TYPE_DICTIONARY:
			_on_message(d)
	var now := Time.get_ticks_msec()
	bridge_live = now - last_msg_ms < 2500
	_ping_clock -= delta
	if _ping_clock <= 0.0 and (bridge_live or helper_pid > 0):
		_ping_clock = 1.0
		send_cmd({"cmd": "ping"})
	if bridge_live and helper_state != "running":
		helper_state = "running"
		helper_msg = ""
	elif not bridge_live and helper_state == "running":
		helper_state = "stopped"
		helper_msg = "The Bluetooth helper stopped."
	if helper_state == "starting" and helper_pid > 0 and not OS.is_process_running(helper_pid):
		helper_state = "error"
		helper_msg = "The Bluetooth helper quit right away. Try 'Install Bluetooth helper' again."
		helper_pid = -1
	if _install_thread != null and not _install_thread.is_alive():
		var code: int = _install_thread.wait_to_finish()
		_install_thread = null
		if code == 0:
			helper_state = "stopped"
			start_helper()
		else:
			helper_state = "error"
			var lines := _install_log.strip_edges().split("\n")
			helper_msg = "Install failed: " + (lines[lines.size() - 1] if lines.size() > 0 else "unknown error")
	# reconnect remembered devices automatically when the helper is already installed
	if _autostart_clock > 0.0:
		_autostart_clock -= delta
		if _autostart_clock <= 0.0 and not bridge_live and helper_installed():
			start_helper()
	if not bridge_live:
		trainer_live = false
		controller_live = false
		_release_all()
	elif now - last_trainer_ms > 2500:
		trainer_live = false

	# keyboard stand-in for the trainer: W rides at a steady 85% of your FTP, Shift sprints
	# (that's in gear 11; easier gears push back less, so the same legs make fewer watts at a higher cadence)
	var target := 0.0
	if Input.is_action_pressed("pedal"):
		target = Game.ftp * 0.85
		if Input.is_action_pressed("sprint"):
			target = Game.ftp * 1.75
		target *= pow(gear_ratio(), 0.75)
	var rate := (1.25 if target > kb_power else 0.7) * Game.ftp
	kb_power = move_toward(kb_power, target, rate * delta)
	var spin := clampf((70.0 + kb_power * 0.14) * pow(gear_ratio(), -0.75), 50.0, 125.0)
	kb_cadence = move_toward(kb_cadence, 0.0 if kb_power < 5.0 else spin, 90.0 * delta)

	if Input.is_action_just_pressed("shift_up"):
		shift(1)
	if Input.is_action_just_pressed("shift_down"):
		shift(-1)
	shift_flash = maxf(0.0, shift_flash - delta)
	_grade_clock += delta


func _on_message(d: Dictionary) -> void:
	last_msg_ms = Time.get_ticks_msec()
	if d.get("type", "data") == "status":
		status = d
		return
	controller_live = bool(d.get("controller", false))
	if bool(d.get("trainer", false)):
		trainer_live = true
		last_trainer_ms = last_msg_ms
		trainer_power = float(d.get("power", 0.0))
		trainer_cadence = float(d.get("cadence", 0.0))
		trainer_speed_kmh = float(d.get("speed", 0.0))
	var pressed: Array = d.get("buttons", [])
	for b in pressed:
		if SHIFT_BUTTONS.has(str(b)) and not pressed_names.has(b):
			shift(SHIFT_BUTTONS[str(b)])
	pressed_names = pressed
	var now_actions := {}
	for b in pressed:
		var action: String = BUTTON_ACTIONS.get(str(b), "")
		if action != "":
			now_actions[action] = true
	var frame := Engine.get_process_frames()
	for action in now_actions:
		if not _held.has(action):
			Input.action_press(action)
			_pressed_frame[action] = frame
	for action in _held.keys():
		if not now_actions.has(action):
			# a press and release in the same frame would never show up as just_pressed: release next frame
			if _pressed_frame.get(action, -1) == frame:
				_release_later.append(action)
			else:
				Input.action_release(action)
	_held = now_actions


func _release_all() -> void:
	for action in _held.keys():
		Input.action_release(action)
	_held.clear()


func power() -> float:
	return trainer_power if trainer_live else kb_power


func cadence() -> float:
	return trainer_cadence if trainer_live else kb_cadence


func status_text() -> String:
	if trainer_live and controller_live:
		return "Trainer + controllers connected"
	if trainer_live:
		return "Trainer connected (controls: keyboard)"
	if controller_live:
		return "Controllers connected (pedalling: keyboard)"
	if bridge_live:
		return "Bluetooth ready - Connect Trainer on the title screen"
	if helper_state == "installing" or helper_state == "starting":
		return helper_msg
	return "Keyboard mode"


## Gear ratio relative to gear 11: evenly spaced steps from EASIEST (gear 1) to HARDEST (gear 21).
func gear_ratio(g: int = gear) -> float:
	if g <= START_GEAR:
		return pow(EASIEST, float(START_GEAR - g) / (START_GEAR - 1))
	return pow(HARDEST, float(g - START_GEAR) / (GEARS - START_GEAR))


func shift(step: int) -> void:
	var g := clampi(gear + step, 1, GEARS)
	shift_flash = 1.2
	if g == gear:
		return
	gear = g
	_grade_clock = 2.0   # tell the trainer straight away
	send_grade(_grade_sent if _grade_sent < 900.0 else 0.0)


## Ask the trainer to simulate a road grade (percent) in the current gear. Throttled; only sends changes.
func send_grade(percent: float) -> void:
	if not bridge_live:
		return
	if absf(percent - _grade_sent) < 0.2 and _grade_clock < 2.0:
		return
	_grade_sent = percent
	_grade_clock = 0.0
	var mass: float = Game.weight_kg + float(Game.bike()["mass"])
	tx.put_packet(JSON.stringify({"grade": snappedf(percent, 0.1), "gear": snappedf(gear_ratio(), 0.001), "mass": snappedf(mass, 0.1)}).to_utf8_buffer())
