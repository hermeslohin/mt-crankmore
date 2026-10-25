extends Node
## Links the game to your Strava account and posts your rides (see ride_log.gd) as Virtual Rides.
## Strava has no app keys a game can share, so each rider makes their own free API app at
## strava.com/settings/api and pastes its Client ID and Client Secret into the game. Linking opens the Strava
## approval page in your browser, which sends you back to a tiny web server the game runs on localhost.
## Tokens are kept in user://strava.json and refreshed when they expire.
## Strava's API can't attach photos, so a posted ride's screenshots are kept in user://rides/<activity> and
## "Add screenshots" opens the activity and that folder, ready to drag them in.

const SAVE := "user://strava.json"
const PORT := 9873
const REDIRECT := "http://localhost:9873/strava"
const API := "https://www.strava.com/api/v3"
const SETTINGS_URL := "https://www.strava.com/settings/api"

var client_id := ""
var client_secret := ""
var access_token := ""
var refresh_token := ""
var expires_at := 0
var athlete := ""
var last_activity: Dictionary = {}   # {"id", "shots_dir"} of the last ride posted

var state := "idle"                  # idle | linking | uploading | done | error
var msg := ""
var _server: TCPServer
var _conn: StreamPeerTCP
var _req := PackedByteArray()
var _oauth_state := ""
var _link_deadline := 0.0


func _ready() -> void:
	if not FileAccess.file_exists(SAVE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if typeof(d) == TYPE_DICTIONARY:
		client_id = str(d.get("client_id", ""))
		client_secret = str(d.get("client_secret", ""))
		access_token = str(d.get("access_token", ""))
		refresh_token = str(d.get("refresh_token", ""))
		expires_at = int(d.get("expires_at", 0))
		athlete = str(d.get("athlete", ""))
		last_activity = d.get("last_activity", {})


func _save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"client_id": client_id, "client_secret": client_secret, "access_token": access_token,
			"refresh_token": refresh_token, "expires_at": expires_at, "athlete": athlete, "last_activity": last_activity}))


func has_app() -> bool:
	return client_id != "" and client_secret != ""


func linked() -> bool:
	return refresh_token != ""


func status_text() -> String:
	if linked():
		return "Linked as %s" % athlete if athlete != "" else "Linked"
	return "Not linked" if has_app() else "Not set up"


## Menu helpers: Client ID and Secret come from the clipboard, so a D-pad is all you need.
func paste_client_id() -> void:
	var t := DisplayServer.clipboard_get().strip_edges()
	if t.is_valid_int():
		client_id = t
		msg = "Client ID set."
		_save()
	else:
		msg = "The clipboard doesn't hold a Client ID (it's a number, like 123456)."


func paste_client_secret() -> void:
	var t := DisplayServer.clipboard_get().strip_edges()
	if t.length() >= 20 and t.is_valid_hex_number():
		client_secret = t
		msg = "Client Secret set."
		_save()
	else:
		msg = "The clipboard doesn't hold a Client Secret (40 letters and digits). Click \"Show\" next to it on Strava, then copy."


# ---- linking (OAuth) ---------------------------------------------------------

func start_link() -> void:
	if not has_app():
		return
	_stop_server()
	_server = TCPServer.new()
	if _server.listen(PORT, "127.0.0.1") != OK:
		_server = null
		state = "error"
		msg = "Couldn't open port %d for Strava to send you back to. Is another copy of the game running?" % PORT
		return
	_oauth_state = "%08x%08x" % [randi(), randi()]
	_link_deadline = Time.get_ticks_msec() / 1000.0 + 300.0
	state = "linking"
	msg = "Approve Mt. Crankmore in your browser, then come back here."
	OS.shell_open("https://www.strava.com/oauth/authorize?client_id=%s&response_type=code&approval_prompt=auto&scope=read,activity:write&redirect_uri=%s&state=%s" % [
		client_id, REDIRECT.uri_encode(), _oauth_state])


func unlink() -> void:
	if access_token != "":
		_http(HTTPClient.METHOD_POST, "https://www.strava.com/oauth/deauthorize", "access_token=" + access_token.uri_encode())
	access_token = ""
	refresh_token = ""
	expires_at = 0
	athlete = ""
	state = "idle"
	msg = "Unlinked from Strava."
	_save()


func _stop_server() -> void:
	if _conn != null:
		_conn.disconnect_from_host()
		_conn = null
	if _server != null:
		_server.stop()
		_server = null


func _process(_delta: float) -> void:
	if _server == null:
		return
	if Time.get_ticks_msec() / 1000.0 > _link_deadline:
		_stop_server()
		state = "error"
		msg = "Linking timed out. Try again."
		return
	if _conn == null and _server.is_connection_available():
		_conn = _server.take_connection()
		_req = PackedByteArray()
	if _conn == null:
		return
	_conn.poll()
	var n := _conn.get_available_bytes()
	if n > 0:
		_req.append_array(_conn.get_data(n)[1])
	var text := _req.get_string_from_utf8()
	if not text.contains("\r\n\r\n") and _req.size() < 8192:
		return
	var path := text.get_slice("\r\n", 0).get_slice(" ", 1)
	var q := {}
	for kv in path.get_slice("?", 1).split("&", false):
		q[kv.get_slice("=", 0)] = kv.get_slice("=", 1).uri_decode()
	var ok: bool = path.begins_with("/strava") and q.get("state", "") == _oauth_state and q.has("code")
	var page := "Linked! You can close this tab and get back to Mt. Crankmore." if ok else "Mt. Crankmore was not linked to Strava. You can close this tab."
	var html := "<html><body style='font-family:sans-serif;text-align:center;margin-top:20vh'><h2>%s</h2></body></html>" % page
	_conn.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % [
		html.to_utf8_buffer().size(), html]).to_utf8_buffer())
	_conn.disconnect_from_host()
	_conn = null
	if not path.begins_with("/strava"):
		return   # the browser asking for a favicon: keep waiting
	_stop_server()
	if not ok:
		state = "error"
		msg = "Strava access wasn't granted." if q.get("error", "") == "access_denied" else "Strava sent back something unexpected. Try linking again."
		return
	if not str(q.get("scope", "")).contains("activity:write"):
		state = "error"
		msg = "Leave \"Upload your activities\" ticked on the Strava page so rides can be posted. Try linking again."
		return
	_exchange({"grant_type": "authorization_code", "code": q["code"]})


## Trade the code (or the refresh token) for an access token. Returns true on success.
func _exchange(fields: Dictionary) -> bool:
	fields["client_id"] = client_id
	fields["client_secret"] = client_secret
	var body := "&".join(fields.keys().map(func(k): return "%s=%s" % [k, str(fields[k]).uri_encode()]))
	var r: Dictionary = await _http(HTTPClient.METHOD_POST, "https://www.strava.com/oauth/token", body)
	if r["code"] != 200 or typeof(r["json"]) != TYPE_DICTIONARY:
		state = "error"
		msg = "Strava said no (%s). Check the Client ID and Secret." % _err_text(r) if fields["grant_type"] == "authorization_code" else "Strava wants you to link again (%s)." % _err_text(r)
		if fields["grant_type"] == "refresh_token" and r["code"] in [400, 401]:
			refresh_token = ""   # the rider revoked access on strava.com: link again
			_save()
		return false
	var j: Dictionary = r["json"]
	access_token = j.get("access_token", "")
	refresh_token = j.get("refresh_token", refresh_token)
	expires_at = int(j.get("expires_at", 0))
	if j.has("athlete") and typeof(j["athlete"]) == TYPE_DICTIONARY:
		athlete = ("%s %s" % [j["athlete"].get("firstname", ""), j["athlete"].get("lastname", "")]).strip_edges()
	if state == "linking":
		state = "idle"
		msg = "Linked to Strava%s!" % (" as " + athlete if athlete != "" else "")
	_save()
	return true


func _fresh_token() -> bool:
	if access_token != "" and Time.get_unix_time_from_system() < expires_at - 120:
		return true
	return await _exchange({"grant_type": "refresh_token", "refresh_token": refresh_token})


# ---- posting a ride ----------------------------------------------------------

func busy() -> bool:
	return state in ["linking", "uploading"]


func post_ride() -> void:
	if busy() or not linked() or not Ride.can_post():
		return
	state = "uploading"
	msg = "Uploading your ride..."
	if not await _fresh_token():
		return
	var boundary := "crankmore%08x%08x" % [randi(), randi()]
	var fields := {"data_type": "tcx", "name": Ride.title(), "description": Ride.description(), "trainer": "1",
		"external_id": "crankmore-%d.tcx" % int(Ride.samples[0][0])}
	var body := ""
	for k in fields:
		body += "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, k, fields[k]]
	body += "--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ride.tcx\"\r\nContent-Type: application/xml\r\n\r\n%s\r\n--%s--\r\n" % [
		boundary, Ride.to_tcx(), boundary]
	var r: Dictionary = await _http(HTTPClient.METHOD_POST, API + "/uploads", body, "multipart/form-data; boundary=" + boundary)
	if r["code"] != 201 or typeof(r["json"]) != TYPE_DICTIONARY:
		_fail("Upload failed (%s)." % _err_text(r))
		return
	var upload_id := str(r["json"].get("id_str", r["json"].get("id", "")))
	# Strava processes the file in the background: ask every 2 s until it becomes an activity
	var activity_id := ""
	for i in 45:
		msg = "Strava is processing your ride..."
		await get_tree().create_timer(2.0).timeout
		r = await _http(HTTPClient.METHOD_GET, API + "/uploads/" + upload_id)
		if typeof(r["json"]) != TYPE_DICTIONARY:
			continue
		if r["json"].get("error") != null and str(r["json"]["error"]) != "":
			_fail("Strava couldn't use the ride: %s" % r["json"]["error"])
			return
		if r["json"].get("activity_id") != null:
			activity_id = str(r["json"]["activity_id"]).trim_suffix(".0")
			break
	if activity_id == "":
		_fail("Strava is taking a long time. The ride may still show up; check your Strava feed before posting it again.")
		return
	# a TCX file can only say "Biking", so set the sport afterwards (the new activity can take a moment to accept edits)
	msg = "Marking it as a Virtual Ride..."
	var typed := false
	for i in 4:
		r = await _http(HTTPClient.METHOD_PUT, API + "/activities/" + activity_id, "sport_type=VirtualRide&trainer=1")
		if r["code"] == 200:
			typed = true
			break
		push_warning("Strava: setting Virtual Ride failed (%s)" % _err_text(r))
		await get_tree().create_timer(2.0).timeout
	var dir := "user://rides/" + activity_id
	var had_shots := not Ride.shots.is_empty()
	Ride.reset(dir if had_shots else "")
	last_activity = {"id": activity_id, "shots_dir": dir if had_shots else ""}
	_save()
	state = "done"
	msg = "Posted to Strava!" + ("" if typed else " (as a Ride: Strava wouldn't make it a Virtual Ride: %s)" % _err_text(r)) + \
		(" Pick \"Add screenshots\" to put them on the activity." if had_shots else "")


func _fail(text: String) -> void:
	state = "error"
	msg = text


## Opens the last posted activity in the browser, and the folder with its screenshots next to it.
func open_last_activity() -> void:
	if last_activity.is_empty():
		return
	OS.shell_open("https://www.strava.com/activities/%s" % last_activity["id"])
	var dir: String = last_activity.get("shots_dir", "")
	if dir != "" and DirAccess.dir_exists_absolute(dir):
		OS.shell_open(ProjectSettings.globalize_path(dir))


# ---- HTTP --------------------------------------------------------------------

func _http(method: int, url: String, body := "", content_type := "application/x-www-form-urlencoded") -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = 60.0
	add_child(h)
	var headers := PackedStringArray(["Content-Type: " + content_type, "User-Agent: MtCrankmore/" + str(ProjectSettings.get_setting("application/config/version"))])
	if access_token != "" and url.begins_with(API):
		headers.append("Authorization: Bearer " + access_token)
	var out := {"code": 0, "json": null, "text": ""}
	if h.request(url, headers, method, body) == OK:
		var res: Array = await h.request_completed
		out["code"] = res[1]
		out["text"] = (res[3] as PackedByteArray).get_string_from_utf8()
		out["json"] = JSON.parse_string(out["text"]) if out["text"] != "" else null
		if res[0] != HTTPRequest.RESULT_SUCCESS:
			out["text"] = "no connection to Strava"
	h.queue_free()
	return out


func _err_text(r: Dictionary) -> String:
	if typeof(r["json"]) == TYPE_DICTIONARY and r["json"].has("message"):
		var j: Dictionary = r["json"]
		var errs: Array = j.get("errors", [])
		var detail := " / ".join(errs.map(func(e): return ("%s %s" % [e.get("field", ""), e.get("code", "")]).strip_edges())) if not errs.is_empty() else ""
		return "%s%s" % [j["message"], ": " + detail if detail != "" else ""]
	return "HTTP %d" % r["code"] if r["code"] != 0 else "no connection to Strava"
