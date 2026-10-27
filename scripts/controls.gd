extends Node
## Input bindings: which keyboard keys and which handlebar-controller buttons drive each game action.
## The defaults live here; the player's changes are saved to user://controls.json (kept apart from the game save,
## so "New game" never resets them) and applied to the InputMap. The remap screens are in main.gd (_open_controls).

signal changed

const PATH := "user://controls.json"
const MAX_SLOTS := 3   # keys (or buttons) one action can have

## Every remappable action, in the order the remap screens list them: action -> label. `GROUPS` splits them over two pages.
const LABELS := {
	"pedal": "Pedal", "sprint": "Sprint", "brake": "Brake", "shift_up": "Shift up (harder)", "shift_down": "Shift down (easier)",
	"powerup": "Use power-up", "honk": "Shout at rivals", "lane_left": "Lane left", "lane_right": "Lane right",
	"steer_left": "Turn left / menu left", "steer_right": "Turn right / menu right", "act_up": "Straight / menu up",
	"act_down": "U-turn / menu down", "act_select": "Select / enter", "act_back": "Pause / back",
}
const GROUPS := [
	{"name": "Riding", "actions": ["pedal", "sprint", "brake", "shift_up", "shift_down", "powerup", "honk", "lane_left", "lane_right"]},
	{"name": "Steering and menus", "actions": ["steer_left", "steer_right", "act_up", "act_down", "act_select", "act_back"]},
]
## The menus can't be driven without these, so each must keep at least one keyboard key.
const MENU_ACTIONS := ["steer_left", "steer_right", "act_up", "act_down", "act_select", "act_back"]

const DEFAULT_KEYS := {
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"pedal": [KEY_W],
	"brake": [KEY_S],
	"sprint": [KEY_SHIFT],
	"powerup": [KEY_Y, KEY_SPACE],
	"honk": [KEY_H],
	"lane_left": [],      # the handlebar paddles: move across the road (never pick a turn)
	"lane_right": [],
	"shift_up": [KEY_R, KEY_BRACKETRIGHT],
	"shift_down": [KEY_Q, KEY_BRACKETLEFT],
	"act_up": [KEY_UP],
	"act_down": [KEY_DOWN],
	"act_select": [KEY_E, KEY_ENTER],
	"act_back": [KEY_ESCAPE],
}

## Every button the bridge reports, in the order the capture prompt names them.
const PAD_LABELS := {
	"LEFT": "D-pad left", "RIGHT": "D-pad right", "UP": "D-pad up", "DOWN": "D-pad down",
	"A": "A", "B": "B", "Y": "Y", "Z": "Z",
	"LS1": "Left shifter", "RS1": "Right shifter", "LS2": "LS2", "RS2": "RS2",
	"POWERUP_L": "Left power-up", "POWERUP_R": "Right power-up", "PADDLE_L": "Left paddle", "PADDLE_R": "Right paddle",
}
const DEFAULT_PADS := {
	"steer_left": ["LEFT"],
	"steer_right": ["RIGHT"],
	"act_up": ["UP"],
	"act_down": ["DOWN"],
	"act_select": ["A"],
	"act_back": ["B"],
	"powerup": ["Y", "RS2", "POWERUP_R"],
	"honk": ["Z"],
	"brake": ["LS2", "POWERUP_L"],
	"shift_up": ["RS1"],
	"shift_down": ["LS1"],
	"lane_left": ["PADDLE_L"],
	"lane_right": ["PADDLE_R"],
	"pedal": [],
	"sprint": [],
}

var keys: Dictionary = {}      # action -> Array of physical keycodes
var pads: Dictionary = {}      # action -> Array of button names
var pad_lookup: Dictionary = {}   # button name -> action (the inverse of `pads`; a button drives one action)


func _ready() -> void:
	reset_all(false)
	_load()
	_apply()


func _apply() -> void:
	pad_lookup.clear()
	for action in pads:
		for b in pads[action]:
			pad_lookup[b] = action
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	changed.emit()


func reset_all(save_it: bool = true) -> void:
	keys.clear()
	pads.clear()
	for action in DEFAULT_KEYS:
		keys[action] = (DEFAULT_KEYS[action] as Array).duplicate()
	for action in DEFAULT_PADS:
		pads[action] = (DEFAULT_PADS[action] as Array).duplicate()
	if save_it:
		_apply()
		_save()


func is_default() -> bool:
	for action in DEFAULT_KEYS:
		if keys[action] != DEFAULT_KEYS[action] or pads[action] != DEFAULT_PADS[action]:
			return false
	return true


## The binding table for a device: "key" or "pad".
func table(device: String) -> Dictionary:
	return keys if device == "key" else pads


## How a key or button is shown to the player.
func name_of(device: String, code) -> String:
	if device == "pad":
		return PAD_LABELS.get(str(code), str(code))
	var label := DisplayServer.keyboard_get_label_from_physical(int(code))
	var s := OS.get_keycode_string(label if label != KEY_NONE else int(code))
	return s if s != "" else "Key %d" % int(code)


## What an action is bound to, e.g. "W / Up" (or "none").
func text(device: String, action: String) -> String:
	var parts: Array = []
	for code in table(device).get(action, []):
		parts.append(name_of(device, code))
	return " / ".join(parts) if not parts.is_empty() else "none"


## The first key of an action, for on-screen hints ("W pedals").
func key(action: String) -> String:
	var ks: Array = keys.get(action, [])
	return name_of("key", ks[0]) if not ks.is_empty() else "(unbound)"


## Puts `code` in slot `slot` of `action` (replacing what was there, or appending past the end). The key / button is
## taken from any other action that had it. Returns "" on success, "Took ..." when it was stolen, or a refusal reason
## (the refusal changes nothing).
func bind(device: String, action: String, slot: int, code) -> String:
	var t := table(device)
	var from := ""
	for other in t:
		if other != action and (t[other] as Array).has(code):
			from = other
	if from != "" and device == "key" and MENU_ACTIONS.has(from) and (t[from] as Array).size() <= 1:
		return "%s is the only key for \"%s\": give that one another key first" % [name_of(device, code), LABELS[from]]
	if from != "":
		(t[from] as Array).erase(code)
	var list: Array = t[action]
	var at := mini(slot, list.size())
	if at < list.size() and list[at] == code:
		return ""
	var old_at: int = list.find(code)
	if old_at >= 0:
		list.remove_at(old_at)   # already on this action in another slot: move it
		if old_at < at:
			at -= 1
	if at < list.size():
		list[at] = code
	else:
		list.append(code)
	_apply()
	_save()
	return "" if from == "" else "Took %s from \"%s\"" % [name_of(device, code), LABELS[from]]


## Empties slot `slot` of `action`. Returns "" or a reason it was refused.
func clear_slot(device: String, action: String, slot: int) -> String:
	var list: Array = table(device)[action]
	if slot >= list.size():
		return ""
	if device == "key" and MENU_ACTIONS.has(action) and list.size() <= 1:
		return "\"%s\" needs at least one key to drive the menus" % LABELS[action]
	list.remove_at(slot)
	_apply()
	_save()
	return ""


func _save() -> void:
	if Game.no_save:   # dev helpers never touch the player's files
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"keys": keys, "pads": pads}))


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	var saved_keys = d.get("keys", {})
	var saved_pads = d.get("pads", {})
	if typeof(saved_keys) == TYPE_DICTIONARY:
		for action in keys:
			if saved_keys.has(action) and typeof(saved_keys[action]) == TYPE_ARRAY:
				var list: Array = []
				for k in saved_keys[action]:
					if int(k) > 0 and not list.has(int(k)):
						list.append(int(k))
				keys[action] = list.slice(0, MAX_SLOTS)
	if typeof(saved_pads) == TYPE_DICTIONARY:
		for action in pads:
			if saved_pads.has(action) and typeof(saved_pads[action]) == TYPE_ARRAY:
				var list: Array = []
				for b in saved_pads[action]:
					if PAD_LABELS.has(str(b)) and not list.has(str(b)):
						list.append(str(b))
				pads[action] = list.slice(0, MAX_SLOTS)
	# a hand-edited file could leave the menus with no way in: put back the defaults for any menu action with no key
	for action in MENU_ACTIONS:
		if (keys[action] as Array).is_empty():
			keys[action] = (DEFAULT_KEYS[action] as Array).duplicate()
