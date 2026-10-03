extends Node

signal location_changed(loc_id: String)
signal narrator_busy(busy: bool)

const Prompts = preload("res://ai/prompts.gd")

var locations: Dictionary = {}
var items: Dictionary = {}
var origins: Array = []
var traits: Array = []
var emotions: Dictionary = {}


func _ready() -> void:
	emotions = _load_json("res://data/emotions.json")
	locations = _load_json("res://data/locations.json")
	items = _load_json("res://data/items.json")
	origins = _load_json("res://data/origins.json")
	traits = _load_json("res://data/traits.json")


func _load_json(path: String) -> Variant:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("Falha ao ler " + path)
	return data


func get_origin(id: String) -> Dictionary:
	for o in origins:
		if o["id"] == id:
			return o
	return {}


func trait_name(id: String) -> String:
	for t in traits:
		if t["id"] == id:
			return t["nome"]
	return id


func item_name(id: String) -> String:
	return items[id]["nome"] if items.has(id) else id


func current_id() -> String:
	return GameState.player.get("location", "")


func current() -> Dictionary:
	return locations.get(current_id(), {})


func is_open(loc_id: String, h: int = -1) -> bool:
	if h < 0:
		h = TimeManager.hour()
	var loc: Dictionary = locations[loc_id]
	return hour_in_range(h, int(loc["abre"]), int(loc["fecha"]))


static func hour_in_range(h: int, from: int, to: int) -> bool:
	if from == to or (from == 0 and to == 24):
		return true
	if from < to:
		return h >= from and h < to
	return h >= from or h < to


func is_accessible(loc_id: String) -> bool:
	var loc: Dictionary = locations[loc_id]
	if loc.get("privado", false):
		return GameState.player.get("home", "") == loc_id
	return true


func visible_locations() -> Array:
	var out: Array = []
	for id in locations:
		if is_accessible(id):
			out.append(id)
	return out


func travel_minutes(from_id: String, to_id: String) -> int:
	var a: Dictionary = locations[from_id]
	var b: Dictionary = locations[to_id]
	var dist := Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))
	return int(5 + dist * 0.6)


func move_player_to(loc_id: String) -> void:
	if not GameState.active or loc_id == current_id():
		return
	if not is_accessible(loc_id):
		return
	var minutes := travel_minutes(current_id(), loc_id)
	NPCManager.end_conversation()
	TimeManager.advance(minutes)
	if not GameState.active:
		return
	if not is_open(loc_id):
		GameState.add_log("Você chega em %s, mas está fechado." % locations[loc_id]["nome"], "info")
		return
	GameState.player["location"] = loc_id
	GameState.add_log("Você vai até %s. (%d min)" % [locations[loc_id]["nome"], minutes], "info")
	GameState.add_log(locations[loc_id]["descricao"], "narration")
	location_changed.emit(loc_id)


func start_story(origin: Dictionary) -> void:
	narrator_busy.emit(true)
	var res: Dictionary = await AIService.chat(Prompts.opening_messages(GameState.player, origin), 500)
	narrator_busy.emit(false)
	if res["ok"] and str(res["text"]).strip_edges() != "":
		GameState.add_log(str(res["text"]).strip_edges(), "narration")
	else:
		GameState.add_log(origin["intro"], "narration")
		if not res["ok"]:
			GameState.add_log(res["error"], "error")
	GameState.add_log(current()["descricao"], "narration")
	location_changed.emit(current_id())
