extends Control
## Heads-up display, toasts, rival chat feed, and keyboard/controller-navigable menus.
## Laid out for the 640x360 pixel canvas: chunky bordered panels, small aliased text.

const INK := Color(0.1, 0.08, 0.16)

var main: Node
var font: Font
var toasts: Array = []
var feed: Array = []
var panel_sb := StyleBoxFlat.new()
var weehoo_sb := StyleBoxFlat.new()
var weehoo_shadow := StyleBoxFlat.new()

var menu_panel: PanelContainer
var menu_box: VBoxContainer
var menu_builder := Callable()
var menu_index := 0
var menu_open := false
var menu_age := 0.0
var menu_cache: Dictionary = {}
var title_mode := false
var capture := {}           # while a remap screen waits for a key or button: {"device", "action", "slot", "t"}
var menu_note := {}         # a remap result shown inside the menu (a toast would be hidden under it): {"text", "color", "t"}
var _adjust_hold := 0.0     # how long LEFT / RIGHT has been held on an adjustable item (for auto-repeat)
var _adjust_next := 0.0


func setup(m: Node) -> void:
	main = m
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(panel_sb, Color(0.1, 0.12, 0.3, 0.9), Color(0.95, 0.92, 0.8), 0)
	for sb in [weehoo_sb, weehoo_shadow]:
		sb.set_corner_radius_all(9)
		sb.anti_aliasing = false
	weehoo_sb.bg_color = Color(0.15, 0.15, 0.17)
	weehoo_sb.border_color = Color(0.36, 0.37, 0.4)
	weehoo_sb.set_border_width_all(2)
	weehoo_shadow.bg_color = INK
	Game.toast.connect(func(text: String, color: Color): toasts.append({"text": text, "color": color, "t": 4.5}))
	Game.rival_say.connect(_on_rival_say)
	Game.feed.connect(func(text: String, color: Color): _push_feed("", text, color))

	menu_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	_style(sb, Color(0.1, 0.12, 0.32, 0.97), Color(1.0, 0.85, 0.3), 10)
	menu_panel.add_theme_stylebox_override("panel", sb)
	menu_panel.visible = false
	add_child(menu_panel)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 2)
	menu_panel.add_child(menu_box)


func _style(sb: StyleBoxFlat, bg: Color, border: Color, margin: int) -> void:
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	sb.shadow_color = INK
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(2, 2)
	sb.expand_margin_left = 1
	sb.expand_margin_top = 1
	sb.set_content_margin_all(margin)


func _on_rival_say(rival: int, text: String) -> void:
	_push_feed(Talk.rivals[rival]["short"], text, Talk.rivals[rival]["color"])


func _push_feed(who: String, text: String, col: Color) -> void:
	feed.append({"who": who, "text": text, "color": col, "t": 11.0})
	if feed.size() > 4:
		feed.pop_front()


# ======================================================================
# Menus
# ======================================================================

## builder() -> {"title": String, "sub": String, "items": [{"label", "fn": Callable, "enabled": bool, "detail": String, "adjust": Callable}]}
## An item with "adjust" is a setting: LEFT / RIGHT call adjust(-1 / +1), and holding the button repeats, faster over time.
func open_menu(builder: Callable, is_title: bool = false) -> void:
	menu_builder = builder
	menu_index = 0
	menu_open = true
	title_mode = is_title
	menu_age = 0.0
	menu_note = {}
	_rebuild_menu()
	menu_panel.visible = true


func close_menu() -> void:
	_end_capture("")
	menu_open = false
	menu_panel.visible = false


func _rebuild_menu() -> void:
	menu_cache = menu_builder.call()
	var items: Array = menu_cache["items"]
	menu_index = clampi(menu_index, 0, maxi(0, items.size() - 1))
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()
	menu_box.add_child(_mk_label(menu_cache["title"], 16, Color(1.0, 0.85, 0.3)))
	if menu_cache.get("sub", "") != "":
		var sub := _mk_label(menu_cache["sub"], 9, Color(0.85, 0.9, 1.0))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(330, 0)
		menu_box.add_child(sub)
	menu_box.add_child(_rule())
	for i in items.size():
		var it: Dictionary = items[i]
		var sel := i == menu_index
		var enabled: bool = it.get("enabled", true)
		var col := Color(1, 1, 1) if enabled else Color(0.5, 0.5, 0.62)
		if sel:
			col = Color(1.0, 0.95, 0.4) if enabled else Color(0.8, 0.6, 0.6)
		var label: String = it["label"]
		if it.has("adjust"):
			label = ("< %s >" if sel else "  %s  ") % label
		menu_box.add_child(_mk_label(("> " if sel else "  ") + label, 12, col))
	var detail: String = items[menu_index].get("detail", "") if not items.is_empty() else ""
	if detail != "":
		menu_box.add_child(_rule())
		var d := _mk_label(detail, 9, Color(0.75, 0.85, 1.0))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(330, 0)
		menu_box.add_child(d)
	if not menu_note.is_empty():
		var n := _mk_label(menu_note["text"], 9, menu_note["color"])
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(330, 0)
		menu_box.add_child(n)
	var adjustable: bool = not items.is_empty() and items[menu_index].has("adjust")
	var hint := "UP/DOWN choose   E/A select   ESC/B back"
	if not capture.is_empty():
		hint = "Press the new %s    ESC cancel    DEL clear" % ("key" if capture["device"] == "key" else "controller button")
	else:
		var up: String = Controls.key("act_up").to_upper()
		var dn: String = Controls.key("act_down").to_upper()
		var lf: String = Controls.key("steer_left").to_upper()
		var rt: String = Controls.key("steer_right").to_upper()
		hint = "%s/%s choose   %s/A select   %s/B back" % [up, dn, Controls.key("act_select").to_upper(), Controls.key("act_back").to_upper()]
		if adjustable:
			hint = "%s/%s choose   %s/%s change   %s/A select   %s/B back" % [up, dn, lf, rt, Controls.key("act_select").to_upper(), Controls.key("act_back").to_upper()]
	menu_box.add_child(_mk_label(hint, 8, Color(0.6, 0.65, 0.85)))
	menu_panel.reset_size()


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(1.0, 0.85, 0.3, 0.6)
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _mk_label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", INK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _process(delta: float) -> void:
	menu_age += delta
	if menu_open:
		menu_panel.position = ((size - menu_panel.size) * 0.5).round()
	for t in toasts:
		t["t"] -= delta
	toasts = toasts.filter(func(t): return t["t"] > 0.0)
	if toasts.size() > 3:
		toasts = toasts.slice(toasts.size() - 3)
	for f in feed:
		f["t"] -= delta
	feed = feed.filter(func(f): return f["t"] > 0.0)
	if not menu_note.is_empty():
		menu_note["t"] -= delta
		if menu_note["t"] <= 0.0:
			menu_note = {}
			if menu_open:
				_rebuild_menu()
	if not capture.is_empty():   # remapping: nothing else may react to the key being pressed
		capture["t"] -= delta
		if capture["t"] <= 0.0:
			_end_capture("")
		queue_redraw()
		return
	if menu_open and menu_cache.get("live", false) and int(menu_age * 4.0) != int((menu_age - delta) * 4.0):
		_rebuild_menu()  # live screens (device lists, connection status) refresh 4x a second
	if menu_open and menu_age > 0.25:
		var items: Array = menu_cache["items"]
		if Input.is_action_just_pressed("act_up"):
			menu_index = (menu_index - 1 + items.size()) % items.size()
			_rebuild_menu()
		elif Input.is_action_just_pressed("act_down"):
			menu_index = (menu_index + 1) % items.size()
			_rebuild_menu()
		elif not items.is_empty() and items[menu_index].has("adjust") and _adjust_step(items[menu_index], delta):
			_rebuild_menu()
		elif Input.is_action_just_pressed("act_select"):
			var it: Dictionary = items[menu_index]
			if it.get("enabled", true):
				var fn: Callable = it["fn"]
				fn.call()
				if menu_open and menu_builder.is_valid():
					_rebuild_menu()
		elif Input.is_action_just_pressed("act_back") and not title_mode:
			close_menu()
			main.on_menu_closed()
	queue_redraw()


## Waits for the player's next key ("key") or handlebar-controller button ("pad") and binds it to slot `slot` of `action`.
## ESC cancels, DEL clears the slot, and it gives up on its own after 8 s.
func begin_capture(device: String, action: String, slot: int) -> void:
	capture = {"device": device, "action": action, "slot": slot, "t": 8.0}
	menu_age = 0.0
	menu_note = {}
	if device == "pad":
		Trainer.capture = _pad_captured
	_rebuild_menu()


func _pad_captured(button: String) -> void:
	if capture.is_empty() or capture["device"] != "pad":
		return
	_end_capture(Controls.bind("pad", capture["action"], capture["slot"], button))


## Ends a capture; `msg` (a refusal, or a note that a key was taken from another action) is shown in the menu.
func _end_capture(msg: String) -> void:
	if capture.is_empty():
		return
	capture = {}
	Trainer.capture = Callable()
	menu_age = 0.0   # the press that ended it must not also drive the menu
	if msg != "":
		var col := Color(1.0, 0.85, 0.4) if msg.begins_with("Took") else Color(1.0, 0.6, 0.4)
		if menu_open:
			menu_note = {"text": msg, "color": col, "t": 6.0}
		else:
			Game.toast.emit(msg, col)
	if menu_open and menu_builder.is_valid():
		_rebuild_menu()


func _input(event: InputEvent) -> void:
	if capture.is_empty():
		return
	var k := event as InputEventKey
	if k == null or k.echo or k.physical_keycode == KEY_NONE or k.physical_keycode == KEY_F11:
		return
	get_viewport().set_input_as_handled()
	# Shift / Ctrl / Alt / Cmd wait for their release: typing "<" (Shift + comma) binds the comma key, and only a
	# modifier pressed and let go on its own binds the modifier.
	var modifier := k.physical_keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
	if not k.pressed:
		if modifier and capture.get("mod", KEY_NONE) == k.physical_keycode and capture["device"] == "key":
			_end_capture(Controls.bind("key", capture["action"], capture["slot"], int(k.physical_keycode)))
		return
	if modifier:
		capture["mod"] = k.physical_keycode
		return
	match k.physical_keycode:
		KEY_ESCAPE:
			_end_capture("")
		KEY_DELETE, KEY_BACKSPACE:
			_end_capture(Controls.clear_slot(capture["device"], capture["action"], capture["slot"]))
		_:
			if capture["device"] == "key":
				_end_capture(Controls.bind("key", capture["action"], capture["slot"], int(k.physical_keycode)))


## LEFT / RIGHT on a setting: one step per press, then auto-repeat while held (getting faster).
func _adjust_step(it: Dictionary, delta: float) -> bool:
	var dir := 0
	if Input.is_action_pressed("steer_left"):
		dir = -1
	elif Input.is_action_pressed("steer_right"):
		dir = 1
	if dir == 0:
		_adjust_hold = 0.0
		return false
	var fire := Input.is_action_just_pressed("steer_left") or Input.is_action_just_pressed("steer_right")
	if fire:
		_adjust_hold = 0.0
		_adjust_next = 0.4
	else:
		_adjust_hold += delta
		if _adjust_hold >= _adjust_next:
			_adjust_next = _adjust_hold + (0.09 if _adjust_hold < 1.5 else 0.035)
			fire = true
	if fire:
		var fn: Callable = it["adjust"]
		fn.call(dir)
	return fire


# ======================================================================
# Drawing
# ======================================================================

func _panel(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size), INK)
	draw_style_box(panel_sb, r)


func _text(s: String, pos: Vector2, fsize: int, col: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos + Vector2(1, 1), s, align, width, fsize, INK)
	draw_string(font, pos, s, align, width, fsize, col)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r.grow(1.0), INK)
	draw_rect(r, Color(0.2, 0.2, 0.3))
	var w := floorf(r.size.x * clampf(frac, 0.0, 1.0))
	draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(w, 1)), col.lightened(0.4))


func _draw() -> void:
	var w := size.x
	var h := size.y
	match main.mode:
		0:
			_draw_title(w, h)
		1:
			_draw_city_hud(w, h)
		2:
			_draw_race_hud(w, h)
	_draw_toasts(w)
	_draw_feed(h)
	if not main.viewer.is_empty():   # the event viewer's banner
		var vt: String = "EVENT VIEWER   [ / ] or P / N to step, R again:   " + (str(main.viewer["status"]) if main.viewer["status"] != "" else "press ] to start")
		var tw := font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var vr := Rect2(weehoo_rect().end.x + 8, 50, tw + 12, 14)
		draw_rect(vr, Color(0.35, 0.1, 0.4, 0.92))
		draw_rect(vr, Color(1.0, 0.85, 0.3), false, 1.0)
		draw_string(font, vr.position + Vector2(6, 10), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.95, 0.7))


func _draw_title(w: float, h: float) -> void:
	for k in 3:
		_text("MT. CRANKMORE", Vector2(k - 1, 58 + (k % 2)), 48, [Color(0.9, 0.25, 0.2), Color(1.0, 0.85, 0.25), Color(0.9, 0.25, 0.2)][k], w, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Game.SLOGAN, Vector2(0, 80), 12, Color(1, 1, 1), w, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Trainer.status_text(), Vector2(0, h - 8), 9, Color(0.6, 1.0, 0.7) if Trainer.bridge_live else Color(1.0, 0.85, 0.5), w, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_city_hud(w: float, h: float) -> void:
	var city = main.city
	# leaderboard
	var rows: Array = [{"name": Game.player_name, "n": Game.deliveries, "col": Color(1, 1, 1)}]
	for i in Talk.rivals.size():
		rows.append({"name": Talk.rivals[i]["short"], "n": city.rival_score[i], "col": Talk.rivals[i]["color"]})
	rows.sort_custom(func(a, b): return a["n"] > b["n"])
	# (bottom right: the WEEHOO has the top left)
	var lb := Rect2(w - 88, h - 18 - rows.size() * 9, 84, 14 + rows.size() * 9)
	_panel(lb)
	_text("DELIVERIES", lb.position + Vector2(5, 10), 8, Color(1.0, 0.85, 0.3))
	for i in rows.size():
		var r: Dictionary = rows[i]
		_text("%d %s" % [i + 1, r["name"]], lb.position + Vector2(5, 20 + i * 9), 8, r["col"])
		_text(str(r["n"]), lb.position + Vector2(56, 20 + i * 9), 8, r["col"], 22, HORIZONTAL_ALIGNMENT_RIGHT)

	# orders
	var lines: Array = []
	if not city.carry.is_empty():
		var c: Dictionary = city.carry
		lines.append({"text": "CARRYING > %s" % city.spots[c["dest"]]["name"], "col": Color(0.4, 1.0, 0.5), "bar": c["t_left"] / c["t_total"]})
		lines.append({"text": "$%d  quality %d%%  %ds" % [c["pay"], int(c["quality"] * 100.0), int(c["t_left"])], "col": Color.WHITE})
	for o in city.orders:
		if o["state"] != "open":
			continue
		var chasers := 0
		for r in city.rival_state:
			if r["order"] == o["id"] and r["state"] == "to_shop":
				chasers += 1
		var dist := int(city.p_pos.distance_to(city.shops[o["shop"]]["window"]) * 4.0)
		var t := "$%d %s %dm" % [o["pay"], city.shops[o["shop"]]["name"], dist]
		if chasers > 0:
			t += " !%d" % chasers
		lines.append({"text": t, "col": Color(1.0, 0.8, 0.3) if chasers == 0 else Color(1.0, 0.55, 0.45)})
	if lines.is_empty():
		lines.append({"text": "Waiting for the phone to ring...", "col": Color(0.8, 0.85, 1.0)})
	if not city.challenge.is_empty():
		_draw_challenge(city, Rect2(w - 214, 24 + lines.size() * 10, 210, 50))
	_panel(Rect2(w - 214, 4, 210, 16 + lines.size() * 10))
	_text("PIZZA ORDERS", Vector2(w - 208, 14), 8, Color(1.0, 0.85, 0.3))
	for i in lines.size():
		_text(lines[i]["text"], Vector2(w - 208, 25 + i * 10), 8, lines[i]["col"])
		if lines[i].has("bar"):
			_bar(Rect2(w - 54, 19 + i * 10, 44, 4), lines[i]["bar"], Color(0.4, 1.0, 0.5))

	var hp := Game.hp_ratio()
	_draw_weehoo(w, h, city.p_speed / (city.TILES_PER_MS * city.PACE) * 3.6, city.grade * 100.0,
		func(r: Rect2): city.draw_minimap(self, r),
		["MONEY", "$%d" % Game.money, Color(0.1, 0.45, 0.15) if Game.money >= 0 else Color(0.75, 0.1, 0.1)],
		["HP", hp, Color(0.2, 0.7, 0.25) if hp > 0.5 else (Color(0.85, 0.6, 0.1) if hp > 0.25 else Color(0.85, 0.15, 0.1))],
		_pu_slot(city.pu, city.socks_t, city.bread_t, city.roller_t))
	if not city.pending.is_empty():
		_draw_junction(city.pending, w, h)
	elif city.queued != "":
		var qr := Rect2(floorf(w * 0.5) - 70, h - 62, 140, 22)
		_panel(qr)
		_arrow_icon(qr.position + Vector2(16, 12), city.queued, Color(1.0, 0.85, 0.25))
		_text("NEXT TURN: %s" % city.queued.to_upper(), qr.position + Vector2(30, 15), 9, Color(1, 1, 1))
	elif city.uturn_hint:
		_text("Wrong way?  DOWN = U-turn", Vector2(0, h - 44), 10, Color(1.0, 0.75, 0.45), w, HORIZONTAL_ALIGNMENT_CENTER)
	if city.prompt != "":
		_text(city.prompt, Vector2(0, h - 118 if not city.pending.is_empty() else h - 46), 12, Color(1.0, 0.95, 0.4), w, HORIZONTAL_ALIGNMENT_CENTER)
	if city.er_timer > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.95, 0.97, 1.0, 0.86))
		draw_rect(Rect2(w * 0.5 - 14, h * 0.18 - 14, 28, 28), Color(0.9, 0.1, 0.15))
		draw_rect(Rect2(w * 0.5 - 4, h * 0.18 - 12, 8, 24), Color.WHITE)
		draw_rect(Rect2(w * 0.5 - 12, h * 0.18 - 4, 24, 8), Color.WHITE)
		_text("ST. PEDRO'S EMERGENCY ROOM", Vector2(0, h * 0.36), 20, Color(0.9, 0.12, 0.18), w, HORIZONTAL_ALIGNMENT_CENTER)
		draw_string(font, Vector2(0, h * 0.36 + 26), "Medical bill: $%d" % city.er_bill, HORIZONTAL_ALIGNMENT_CENTER, w, 16, INK)
		draw_string(font, Vector2(w * 0.1, h * 0.36 + 56), city.er_text, HORIZONTAL_ALIGNMENT_CENTER, w * 0.8, 10, Color(0.2, 0.2, 0.35))
		draw_string(font, Vector2(0, h * 0.36 + 84), "Discharge in %d..." % int(ceilf(city.er_timer)), HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(0.4, 0.4, 0.5))


## Junction chooser: three arrows (left / straight / right), the selection in yellow,
## the GPS suggestion marked, and a bar that runs out as the junction gets close.
func _draw_junction(pd: Dictionary, w: float, h: float) -> void:
	var labels: Dictionary = pd["labels"]
	var cx := floorf(w * 0.5)
	var r := Rect2(cx - 96, h - 110, 192, 68)
	_panel(r)
	_text("TURN IN %dm" % int(float(pd["dist"]) * 4.0), Vector2(r.position.x, r.position.y + 11), 9, Color(1.0, 0.85, 0.3), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text("GPS", Vector2(r.end.x - 26, r.position.y + 11), 8, Color(0.35, 1.0, 0.45))
	var keys := ["left", "straight", "right"]
	for i in 3:
		var k: String = keys[i]
		var c := Vector2(cx + (i - 1) * 48, r.position.y + 32)
		var avail := labels.has(k)
		var sel: bool = pd["choice"] == k
		if sel:
			draw_rect(Rect2(c - Vector2(17, 13), Vector2(34, 26)), INK)
			draw_rect(Rect2(c - Vector2(16, 12), Vector2(32, 24)), Color(1.0, 0.85, 0.25))
		var col := INK if sel else (Color(1, 1, 1) if avail else Color(0.35, 0.37, 0.5))
		_arrow_icon(c, k, col)
		if avail and pd["gps"] == k:
			draw_rect(Rect2(c + Vector2(10, -14), Vector2(9, 7)), INK)
			draw_rect(Rect2(c + Vector2(11, -13), Vector2(7, 5)), Color(0.35, 1.0, 0.45))
	var name: String = labels[pd["choice"]]["name"] if labels.has(pd["choice"]) else ""
	_text(name, Vector2(r.position.x, r.end.y - 12), 8, Color(1, 1, 1), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_bar(Rect2(r.position.x + 8, r.end.y - 6, r.size.x - 16, 2), float(pd["dist"]) / float(pd["look"]), Color(1.0, 0.85, 0.3))
	if pd.get("car", false) and int(Time.get_ticks_msec() / 250) % 2 == 0:
		_text("CAR COMING!  no brakes, good luck" if Game.fixed_gear() else "CAR COMING!  brake to wait", Vector2(0, r.position.y - 6), 12, Color(1.0, 0.35, 0.3), w, HORIZONTAL_ALIGNMENT_CENTER)


func _arrow_icon(c: Vector2, kind: String, col: Color) -> void:
	match kind:
		"straight":
			draw_rect(Rect2(c + Vector2(-2, -3), Vector2(5, 12)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(7, -3), c + Vector2(-7, -3)]), col)
		"left", "right":
			var sx := -1.0 if kind == "left" else 1.0
			draw_rect(Rect2(c + Vector2(-2, -1), Vector2(5, 10)), col)
			var bar := Rect2(c + Vector2(-2 if sx > 0 else -6, -3), Vector2(8, 5))
			draw_rect(bar, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 12, -1), c + Vector2(sx * 5, -8), c + Vector2(sx * 5, 6)]), col)


## Coggan power zone colour for a fraction of FTP (used by the LED strip and the watts field).
func _zone_col(frac: float) -> Color:
	if frac < 0.55: return Color(0.55, 0.57, 0.6)
	if frac < 0.75: return Color(0.2, 0.5, 0.95)
	if frac < 0.9: return Color(0.15, 0.75, 0.3)
	if frac < 1.05: return Color(0.95, 0.8, 0.1)
	if frac < 1.2: return Color(1.0, 0.5, 0.1)
	return Color(0.95, 0.15, 0.15)


## The WEEHOO bike computer in the top-left corner: LED power strip, map page on top,
## a 2x2 field grid (speed / watts / `cell` / grade), then two bars and cadence.
## `map_fn` draws into the map window; `cell` is [label, text, colour]; bars are [label, frac, colour].
## What the WEEHOO's power-up row shows: the item you're carrying, or a running Fire Socks / Breadsticks / Dough Roller timer.
func _pu_slot(kind: String, socks: float, bread: float, roller: float) -> Dictionary:
	var fx: Array = []
	if socks > 0.0:
		fx = ["SOCKS", socks / PowerUps.SOCKS_TIME, PowerUps.col("socks")]
	elif bread > 0.0:
		fx = ["BREAD", bread / PowerUps.BREAD_TIME, PowerUps.col("breadsticks")]
	elif roller > 0.0:
		fx = ["ROLLER", roller / PowerUps.ROLLER_TIME, PowerUps.col("roller")]
	return {"kind": kind, "fx": fx}


func _gear_text() -> String:
	return "FIXED" if Game.fixed_gear() else "GEAR %d" % Trainer.gear


## Where the WEEHOO sits (top left) and, on its pixel-art shell (art/ui_weehoo_shell.png), the window the live
## display is drawn into. Without the shell art it's drawn as a plain case of WEEHOO_SIZE.
const WEEHOO_POS := Vector2(-16, -15)   # the shell art has a transparent margin (the case starts at 21, 20): this puts the case 5 px from the corner
const WEEHOO_SIZE := Vector2(192, 288)
const WEEHOO_SCREEN := Rect2(33, 46, 126, 176)


func weehoo_rect() -> Rect2:
	return Rect2(WEEHOO_POS, WEEHOO_SIZE)


func _draw_weehoo(w: float, h: float, speed_kmh: float, grade_pct: float, map_fn: Callable, cell: Array, bar1: Array, pu: Dictionary) -> void:
	var d := weehoo_rect()
	var shell := Sprites.sheet("ui_weehoo_shell")
	if shell != null:
		draw_texture(shell, d.position)
	else:
		draw_style_box(weehoo_shadow, Rect2(d.position + Vector2(3, 3), d.size))
		draw_style_box(weehoo_sb, d)
	if Trainer.shift_flash > 0.0:   # big gear number beside the computer after a shift
		var fa := clampf(Trainer.shift_flash / 0.3, 0.0, 1.0)
		var gr := Rect2(d.end.x + 6, d.position.y + 40, 80, 26)
		draw_rect(gr, Color(0.08, 0.08, 0.1, 0.85 * fa))
		var lo := Trainer.gear == 1 or Trainer.gear == Trainer.GEARS
		draw_string(font, Vector2(gr.position.x, gr.position.y + 19), _gear_text(), HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 16,
			Color(1.0, 0.55, 0.3, fa) if lo else Color(1.0, 0.85, 0.3, fa))
		for i in Trainer.GEARS:   # a little cassette of 21 ticks, the current one lit
			var tx := gr.position.x + 5 + i * 3.4
			draw_rect(Rect2(tx, gr.end.y - 4, 2, 2), Color(1.0, 0.85, 0.3, fa) if i + 1 == Trainer.gear else Color(0.5, 0.5, 0.55, fa))
	var dark := Color(0.12, 0.12, 0.15)
	var frac := Trainer.power() / maxf(Game.ftp, 1.0)
	# screen
	var sc := Rect2(d.position + WEEHOO_SCREEN.position, WEEHOO_SCREEN.size)
	draw_rect(sc.grow(1.0), Color(0.05, 0.05, 0.07))
	draw_rect(sc, Color(0.9, 0.92, 0.88))
	var x := sc.position.x
	var y := sc.position.y
	# LED strip along the top of the screen: lights up left to right with power, coloured by zone
	for i in 8:
		var lf := (i + 0.5) / 8.0 * 1.5
		var lit := frac >= lf - 0.09
		var lw := (sc.size.x - 4.0) / 8.0
		draw_rect(Rect2(x + 2 + i * lw, y - 4, lw - 3, 2), _zone_col(lf) if lit else Color(0.27, 0.27, 0.3))
	# status bar: clock, link, battery
	draw_rect(Rect2(x, y, sc.size.x, 10), dark)
	var tm := Time.get_time_dict_from_system()
	draw_string(font, Vector2(x + 3, y + 8), "%d:%02d" % [tm["hour"], tm["minute"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.9, 0.9))
	var link := Color(0.4, 1.0, 0.5) if Trainer.trainer_live else (Color(1.0, 0.85, 0.3) if Trainer.bridge_live else Color(0.45, 0.45, 0.5))
	draw_rect(Rect2(x + sc.size.x - 30, y + 3, 4, 4), link)
	draw_rect(Rect2(x + sc.size.x - 21, y + 2, 15, 6), Color(0.9, 0.9, 0.9), false, 1.0)
	draw_rect(Rect2(x + sc.size.x - 6, y + 4, 2, 2), Color(0.9, 0.9, 0.9))
	draw_rect(Rect2(x + sc.size.x - 19, y + 4, 9, 2), Color(0.4, 1.0, 0.5))
	draw_string(font, Vector2(x, y + 8), _gear_text(), HORIZONTAL_ALIGNMENT_CENTER, sc.size.x, 8, Color(1.0, 0.85, 0.3))
	# map page: everything the fields and bars below don't need
	var map_h := sc.size.y - 12.0 - 2.0 - 49.0 - 28.0
	var mr := Rect2(x + 2, y + 12, sc.size.x - 4, map_h)
	map_fn.call(mr)
	y += map_h + 14.0
	draw_rect(Rect2(x, y, sc.size.x, 1), dark)
	# 2x2 fields
	var gcol := Color(0.8, 0.2, 0.15) if grade_pct > 0.5 else (Color(0.1, 0.55, 0.25) if grade_pct < -0.5 else dark)
	var pcol := _zone_col(frac).darkened(0.25) if frac >= 0.55 else dark
	var fields := [["KM/H", "%.1f" % speed_kmh, dark], ["WATTS", "%d" % int(Trainer.power()), pcol], cell,
		["GRADE", "%+.1f%%" % grade_pct if absf(grade_pct) >= 0.05 else "0.0%", gcol]]
	var cw := sc.size.x * 0.5
	for i in 4:
		var fx := x + (i % 2) * cw
		var fy := y + 1 + (i / 2) * 24
		draw_string(font, Vector2(fx + 3, fy + 8), fields[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.42, 0.45))
		draw_string(font, Vector2(fx, fy + 21), fields[i][1], HORIZONTAL_ALIGNMENT_CENTER, cw, 16, fields[i][2])
	draw_rect(Rect2(x + cw, y + 1, 1, 47), Color(0.7, 0.72, 0.7))
	draw_rect(Rect2(x, y + 25, sc.size.x, 1), Color(0.7, 0.72, 0.7))
	y += 49.0
	draw_rect(Rect2(x, y, sc.size.x, 1), dark)
	# HP / legs bar, the power-up slot, cadence
	var kind: String = pu["kind"]
	var fx: Array = pu["fx"]
	for k in 2:
		var bar: Array = bar1 if k == 0 else fx
		var by := y + 10 + k * 12
		if k == 1 and (kind != "" or fx.is_empty()):
			draw_string(font, Vector2(x + 3, by), "ITEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.42, 0.45))
			if kind == "":
				draw_string(font, Vector2(x + 36, by), "- none -", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.55, 0.57, 0.6))
				continue
			PowerUps.draw_icon(self, Vector2(x + 31, by - 3), kind, 0.8)
			draw_string(font, Vector2(x + 39, by), PowerUps.DEFS[kind]["short"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PowerUps.col(kind).darkened(0.35))
			if int(Time.get_ticks_msec() / 400) % 2 == 0:   # blinking "Y" to remind you it's ready
				draw_rect(Rect2(x + sc.size.x - 11, by - 8, 9, 9), dark)
				draw_string(font, Vector2(x + sc.size.x - 11, by), "Y", HORIZONTAL_ALIGNMENT_CENTER, 9, 8, Color(1.0, 0.85, 0.3))
			continue
		draw_string(font, Vector2(x + 3, by), bar[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.42, 0.45))
		var bx := x + 36.0
		var bw := sc.size.x - 39.0 - (32.0 if k == 0 else 0.0)
		var br := Rect2(bx, by - 6, bw, 5)
		draw_rect(br.grow(1.0), dark)
		draw_rect(br, Color(0.75, 0.77, 0.75))
		draw_rect(Rect2(br.position, Vector2(floorf(bw * clampf(bar[1], 0.0, 1.0)), 5)), bar[2])
	draw_string(font, Vector2(x + sc.size.x - 32, y + 10), "%d" % int(Trainer.cadence()), HORIZONTAL_ALIGNMENT_RIGHT, 18, 8, dark)
	draw_string(font, Vector2(x + sc.size.x - 13, y + 10), "rpm", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.4, 0.42, 0.45))


func _fmt_time(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


func _draw_race_hud(w: float, h: float) -> void:
	var race = main.race
	var me: Dictionary = race.riders[0]
	var order: Array = race.standings()
	var rb := Rect2(w - 116, h - 20 - order.size() * 10, 112, 16 + order.size() * 10)   # bottom right
	_panel(rb)
	_text(race.course["name"].to_upper(), rb.position + Vector2(5, 10), 8, Color(1.0, 0.85, 0.3))
	for i in order.size():
		var r: Dictionary = order[i]
		var nm: String = "YOU" if r["player"] else r["short"]
		var col: Color = Color(1, 1, 1) if r["player"] else r["color"]
		if r["player"]:
			draw_rect(Rect2(rb.position + Vector2(2, 13 + i * 10), Vector2(108, 10)), Color(1, 1, 1, 0.18))
		_text("%d %s" % [i + 1, nm], rb.position + Vector2(5, 21 + i * 10), 8, col)
		var gap: float = race.time_gap(r)
		var gtxt := "--" if r["player"] else ("%+ds" % int(gap))
		_text(gtxt if not r["done"] else "FIN", rb.position + Vector2(66, 21 + i * 10), 8, col, 40, HORIZONTAL_ALIGNMENT_RIGHT)

	var pos := order.find(me) + 1
	if float(me["draft"]) > 0.0:
		_text("DRAFTING  -%d%% watts" % roundi(float(me["draft"]) * 100.0), Vector2(0, h - 30), 10, Color(0.75, 0.95, 1.0), w, HORIZONTAL_ALIGNMENT_CENTER)
	var legs: Array = ["LEGS", race.stamina, Color(0.2, 0.55, 0.9)] if not Trainer.trainer_live else ["HP", Game.hp_ratio(), Color(0.2, 0.7, 0.25)]
	_draw_weehoo(w, h, me["v"] * 3.6, race._grade_at(me["s"]) * 100.0, _draw_race_profile,
		["POS", "%d/%d" % [pos, order.size()], Color(0.12, 0.12, 0.15)],
		legs, _pu_slot(me["pu"], me["socks"], me["bread"], me["roller"]))


## Race map page: the course elevation profile with every rider on it, distance left and clock.
func _draw_race_profile(mr: Rect2) -> void:
	var race = main.race
	var me: Dictionary = race.riders[0]
	var length: float = race.course["length"]
	var pr := Rect2(mr.position + Vector2(0, 12), mr.size - Vector2(0, 12))
	var pts := PackedVector2Array([pr.position + Vector2(0, pr.size.y)])
	for i in range(0, race.M, 5):
		if race.s_m[i] > length:   # the run-out past the finish stays off the map
			break
		pts.append(pr.position + Vector2(race.s_m[i] / length * pr.size.x, pr.size.y - race.elev[i] / race.gain * (pr.size.y - 4.0)))
	pts.append(pr.position + pr.size)
	draw_colored_polygon(pts, Color(0.72, 0.62, 0.45))
	# the snowy stretches get a white cap, tunnels a dark bar, hairpins a yellow tick
	for i in range(0, race.M, 5):
		if race.s_m[i] > length:
			break
		if race._snow_cover(race.pts[i].x, race.pts[i].y, race.elev[i] * race.vz / race.peak) > 0.5:
			draw_rect(Rect2(floorf(pr.position.x + race.s_m[i] / length * pr.size.x), pr.position.y + pr.size.y - race.elev[i] / race.gain * (pr.size.y - 4.0) - 1.0, 2, 2), Color(1, 1, 1))
	if race.rescue:   # where the injured skier is: a red cross on the profile
		var rx: float = floorf(pr.position.x + race.rescue_s / length * pr.size.x)
		draw_rect(Rect2(rx - 1, pr.position.y - 2, 3, 9), Color(0.9, 0.15, 0.15))
		draw_rect(Rect2(rx - 4, pr.position.y + 1, 9, 3), Color(0.9, 0.15, 0.15))
	for t in race.tunnels:
		var tx: float = pr.position.x + float(t["s0"]) / length * pr.size.x
		draw_rect(Rect2(floorf(tx), pr.position.y + pr.size.y - 7, maxf(2.0, floorf((float(t["s1"]) - float(t["s0"])) / length * pr.size.x)), 3), Color(0.15, 0.15, 0.25))
	for h in race.hairpins:
		draw_rect(Rect2(floorf(pr.position.x + float(h["s"]) / length * pr.size.x), pr.position.y + 1, 1, 4), Color(1.0, 0.85, 0.1))
	# creeks, jumps and fallen trees on the profile
	for ob in race.obstacles:
		var ox: float = pr.position.x + float(ob["s"]) / length * pr.size.x
		var oc: Color = {"ford": Color(0.25, 0.55, 0.95), "jump": Color(0.95, 0.55, 0.1), "log": Color(0.4, 0.25, 0.12)}[ob["kind"]]
		draw_rect(Rect2(floorf(ox), pr.position.y + pr.size.y - 3, 1, 3), oc)
	var done := clampf(me["s"] / length, 0.0, 1.0)
	draw_rect(Rect2(pr.position.x + done * pr.size.x, pr.position.y, 1, pr.size.y), Color(0.12, 0.12, 0.15, 0.5))
	for k in range(race.riders.size() - 1, -1, -1):
		var r: Dictionary = race.riders[k]
		var f := clampf(r["s"] / length, 0.0, 1.0)
		var fy: float = race._elev_at_t(race._t_of_s(r["s"])) / race.gain
		var p := (pr.position + Vector2(f * pr.size.x, pr.size.y - fy * (pr.size.y - 4.0))).round()
		var sz := 3.0 if r["player"] else 2.0
		draw_rect(Rect2(p - Vector2(sz, sz), Vector2(sz * 2, sz * 2)), INK)
		draw_rect(Rect2(p - Vector2(sz - 1, sz - 1), Vector2(sz * 2 - 2, sz * 2 - 2)), Color(1, 1, 1) if r["player"] else r["color"])
	var dark := Color(0.12, 0.12, 0.15)
	draw_string(font, Vector2(mr.position.x + 1, mr.position.y + 8), "%.2f km" % (maxf(0.0, length - me["s"]) / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, dark)
	draw_string(font, Vector2(mr.position.x, mr.position.y + 8), _fmt_time(race.clock), HORIZONTAL_ALIGNMENT_RIGHT, mr.size.x - 1, 8, dark)


## A challenge in progress (see City.CHALLENGES): what it pays, the watts it takes (green when you're on it) and how
## it's going: the gap to the thief or dog, or you and the hot rod on the way to the line.
func _draw_challenge(city, r: Rect2) -> void:
	var c: Dictionary = city.challenge
	_panel(r)
	var x := r.position.x + 6
	var y := r.position.y + 10
	_text(("%s  $%d" % [c["title"], int(c["reward"])]) if int(c["reward"]) > 0 else str(c["title"]), Vector2(x, y), 8, Color(1.0, 0.85, 0.3))
	var need: int = city.challenge_watts()
	var have := int(Trainer.power())
	if c["kind"] == "rush":   # the rush is judged on your average
		have = int(float(c["p_sum"]) / maxf(float(c["p_t"]), 0.1))
	var on := have >= need
	_text(("Average %d W+ (%d%% FTP)" if c["kind"] == "rush" else "Ride %d W+ (%d%% FTP)") % [need, int(round(float(c["pct"]) * 100.0))], Vector2(x, y + 11), 8, Color(0.85, 0.9, 1.0))
	_text("%d W" % have, Vector2(r.end.x - 50, y + 11), 8, Color(0.4, 1.0, 0.5) if on else Color(1.0, 0.5, 0.4), 44, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := Rect2(x, y + 20, r.size.x - 12, 6)
	draw_rect(bar.grow(1.0), INK)
	draw_rect(bar, Color(0.25, 0.27, 0.35))
	match c["state"]:
		"won", "lost":
			_text("WON!" if c["state"] == "won" else "MISSED IT", Vector2(x, y + 36), 8, Color(0.4, 1.0, 0.5) if c["state"] == "won" else Color(1.0, 0.5, 0.4))
		"count":
			_text("Get ready... %d" % int(ceil(float(c["count"]))), Vector2(x, y + 36), 8, Color.WHITE)
		"armed":
			_text("Ride to the START line", Vector2(x, y + 36), 8, Color.WHITE)
		_:
			if c["kind"] == "rush":
				var k := float(c["done"]) / float(c["stops"])
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(0.4, 1.0, 0.5) if on else Color(1.0, 0.75, 0.3))
				_text("Stop %d of %d   average %d W" % [int(c["done"]) + 1, int(c["stops"]), have], Vector2(x, y + 36), 8, Color.WHITE)
			elif c["kind"] == "climb":
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(c.get("progress", 0.0)), bar.size.y)), Color(0.4, 1.0, 0.5) if float(c["t"]) <= float(c["target"]) else Color(1.0, 0.5, 0.4))
				_text("%s   %s / %s" % [c["name"], city._clock(float(c["t"])), city._clock(float(c["target"]))], Vector2(x, y + 36), 8, Color.WHITE)
			elif c["kind"] == "gulls" or c["kind"] == "zombies":
				var k := clampf(float(c["gap"]) / float(c["escape"]), 0.0, 1.0)
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(0.4, 1.0, 0.5) if on else Color(1.0, 0.4, 0.3))
				_text("Get away! %d m ahead of them" % int(c["gap"]), Vector2(x, y + 36), 8, Color.WHITE)
			elif c.has("dist"):
				var dist: float = c["dist"]
				var me := clampf(float(c["me_m"]) / dist, 0.0, 1.0)
				var them := clampf(float(c["them_m"]) / dist, 0.0, 1.0)
				draw_rect(Rect2(bar.position + Vector2(bar.size.x * them - 2, -1), Vector2(4, 8)), Color(1.0, 0.55, 0.15))
				draw_rect(Rect2(bar.position + Vector2(bar.size.x * me - 2, -1), Vector2(4, 8)), Color.WHITE)
				_text("you %dm   %s %dm   / %dm" % [int(c["me_m"]), "hot rod" if c["kind"] == "race" else "kid", int(c["them_m"]), int(dist)], Vector2(x, y + 36), 8, Color.WHITE)
			else:
				var k := clampf(1.0 - (float(c["gap"]) - float(c["catch"])) / (float(c["lose"]) - float(c["catch"])), 0.0, 1.0)
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(0.4, 1.0, 0.5) if on else Color(1.0, 0.75, 0.3))
				_text("%d m to go   %ds" % [int(float(c["gap"]) - float(c["catch"])), int(maxf(0.0, float(c["time"]) - float(c["t"])))], Vector2(x, y + 36), 8, Color.WHITE)


func _draw_toasts(w: float) -> void:
	var y := 70.0
	for t in toasts:
		var a := clampf(t["t"] * 2.0, 0.0, 1.0)
		var col: Color = t["color"]
		col.a = a
		var tw := minf(font.get_string_size(t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, 360.0)
		var mid := (weehoo_rect().end.x + w) * 0.5   # the space right of the WEEHOO
		var r := Rect2(floorf(mid - tw * 0.5 - 6), y - 10, tw + 12, 14)
		draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(INK.r, INK.g, INK.b, a))
		draw_rect(r, Color(0.1, 0.12, 0.3, 0.92 * a))
		draw_rect(r, Color(col.r, col.g, col.b, a), false, 1.0)
		draw_string(font, Vector2(r.position.x + 6, y), t["text"], HORIZONTAL_ALIGNMENT_LEFT, 360.0, 10, col)
		y += 17.0


func _draw_feed(h: float) -> void:
	var base := h - 44.0
	var n := feed.size()
	for i in n:
		var f: Dictionary = feed[n - 1 - i]
		var a := clampf(f["t"], 0.0, 1.0)
		var txt: String = f["text"] if f["who"] == "" else "%s: %s" % [f["who"], f["text"]]
		var tw := minf(font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, 240.0)
		var fx := weehoo_rect().end.x + 6.0
		draw_rect(Rect2(fx, base - 8 - i * 11, tw + 8, 11), Color(0.08, 0.1, 0.22, 0.75 * a))
		var c: Color = f["color"]
		c.a = a
		draw_string(font, Vector2(fx + 4, base - i * 11), txt, HORIZONTAL_ALIGNMENT_LEFT, 240.0, 8, c)
