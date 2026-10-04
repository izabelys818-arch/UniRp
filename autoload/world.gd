extends Node

signal location_changed(loc_id: String)
signal narrator_busy(busy: bool)

const Prompts = preload("res://ai/prompts.gd")

var locations: Dictionary = {}
var items: Dictionary = {}
var origins: Array = []
var traits: Array = []
var emotions: Dictionary = {}
var appearance: Dictionary = {}
var npc_looks: Dictionary = {}


func _ready() -> void:
	TimeManager.time_advanced.connect(_check_key_expiry)
	emotions = _load_json("res://data/emotions.json")
	appearance = _load_json("res://data/appearance.json")
	npc_looks = _load_json("res://data/npc_looks.json")
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
	if loc.get("interior", false):
		return has_key(str(loc.get("chave", "")))
	if loc.get("privado", false):
		return GameState.player.get("home", "") == loc_id
	return true


func visible_locations() -> Array:
	var out: Array = []
	for id in locations:
		if not locations[id].get("interior", false) and is_accessible(id):
			out.append(id)
	return out


# ---------- chaves e interiores ----------

func keys() -> Dictionary:
	if not GameState.player.has("keys"):
		GameState.player["keys"] = {}
	return GameState.player["keys"]


func has_key(key: String) -> bool:
	return key != "" and GameState.active and int(keys().get(key, 0)) > TimeManager.total_minutes


func key_expires(key: String) -> int:
	return int(keys().get(key, 0))


# Valida até o meio-dia do último dia pago (check-out), como numa pensão de verdade.
func grant_key(key: String, nights: int) -> void:
	var now := TimeManager.total_minutes
	var day_start := (now / 1440) * 1440
	var noon := day_start + 12 * 60
	if now >= noon:
		noon += 1440
	var base := maxi(noon, key_expires(key))
	keys()[key] = base + (nights - 1) * 1440 if key_expires(key) <= now else key_expires(key) + nights * 1440
	GameState.player_changed.emit()


func enter_interior(interior_id: String) -> void:
	if not GameState.active or not is_accessible(interior_id):
		return
	NPCManager.end_conversation()
	TimeManager.advance(1)
	GameState.player["location"] = interior_id
	GameState.add_log("Você usa a chave e entra: %s." % locations[interior_id]["nome"], "info")
	GameState.add_log(locations[interior_id]["descricao"], "narration")
	location_changed.emit(interior_id)


func leave_interior() -> void:
	var loc := current()
	if not loc.get("interior", false):
		return
	NPCManager.end_conversation()
	TimeManager.advance(1)
	var parent: String = loc["pai"]
	GameState.player["location"] = parent
	GameState.add_log("Você tranca a porta e sai para %s." % locations[parent]["nome"], "info")
	location_changed.emit(parent)


func _check_key_expiry(_minutes: int, _sleeping: bool) -> void:
	var loc := current()
	if GameState.active and loc.get("interior", false) and not has_key(str(loc.get("chave", ""))):
		var parent: String = loc["pai"]
		GameState.player["location"] = parent
		GameState.add_log("Batidas na porta. \"Já passou da hora, criatura. O quarto é para quem pagou.\" Suas coisas estão na mão e você é posto para fora.", "danger")
		location_changed.emit(parent)


func travel_minutes(from_id: String, to_id: String) -> int:
	var a: Dictionary = locations[from_id]
	var b: Dictionary = locations[to_id]
	var dist := Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))
	return int(5 + dist * 0.6)


func _distance(from_id: String, to_id: String) -> float:
	var a: Dictionary = locations[from_id]
	var b: Dictionary = locations[to_id]
	return Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))


func travel_options(to_id: String) -> Array:
	var d := _distance(current_id(), to_id)
	var car := str(GameState.player.get("car", ""))
	var uber_price := int(round(7.0 + d * 0.35))
	var opts: Array = [
		{"mode": "ape", "label": "A pé", "minutes": int(5 + d * 0.6), "cost": 0, "ok": true, "note": "gasta energia"},
		{"mode": "uber", "label": "Uber", "minutes": int(6 + d * 0.18), "cost": uber_price, "ok": GameState.money() >= uber_price, "note": "" if GameState.money() >= uber_price else "sem dinheiro"},
	]
	if car != "":
		opts.append({"mode": "carro", "label": car, "minutes": int(3 + d * 0.15), "cost": 0, "ok": true, "note": "seu carro"})
	return opts


func shop_open(loc_id: String = "") -> bool:
	if loc_id == "":
		loc_id = current_id()
	var loc: Dictionary = locations[loc_id]
	if loc.get("loja", []).is_empty():
		return false
	var hours: Array = loc.get("vendedor_horario", [])
	return hours.is_empty() or hour_in_range(TimeManager.hour(), int(hours[0]), int(hours[1]))


func move_player_to(loc_id: String, mode: String = "ape") -> void:
	if not GameState.active or loc_id == current_id():
		return
	if not is_accessible(loc_id):
		return
	var opt: Dictionary = {}
	for o in travel_options(loc_id):
		if o["mode"] == mode:
			opt = o
	if opt.is_empty() or not opt["ok"]:
		return
	var minutes: int = opt["minutes"]
	NPCManager.end_conversation()
	if int(opt["cost"]) > 0:
		GameState.add_money(-int(opt["cost"]))
		PhoneSystem.log_bank("Corrida de Uber", -int(opt["cost"]))
	TimeManager.advance(minutes)
	if mode == "ape":
		NeedsSystem.apply({"energia": -minutes * 0.08})
	if not GameState.active:
		return
	if not is_open(loc_id):
		GameState.add_log("Você chega em %s, mas está fechado." % locations[loc_id]["nome"], "info")
		return
	GameState.player["location"] = loc_id
	var how := {"ape": "a pé", "uber": "de Uber (R$ %d)" % int(opt["cost"]), "carro": "de carro"}
	GameState.add_log("Você vai até %s %s. (%d min)" % [locations[loc_id]["nome"], how.get(mode, ""), minutes], "info")
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
