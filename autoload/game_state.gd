extends Node

signal log_added(entry: Dictionary)
signal player_changed
signal game_over(reason: String)

const CITY := "Porto Cinza"
const MAX_LOG := 300

var player: Dictionary = {}
var log_entries: Array = []
var active: bool = false


func new_game(p: Dictionary) -> void:
	player = p
	log_entries.clear()
	active = true


func add_log(text: String, kind: String = "info", speaker: String = "") -> void:
	var entry := {"text": text, "kind": kind, "speaker": speaker}
	log_entries.append(entry)
	if log_entries.size() > MAX_LOG:
		log_entries.pop_front()
	log_added.emit(entry)


func money() -> int:
	return int(player.get("money", 0))


func add_money(v: int) -> void:
	player["money"] = max(0, money() + v)
	player_changed.emit()


func item_count(id: String) -> int:
	return int(player["inventory"].get(id, 0))


func add_item(id: String, qty: int = 1) -> void:
	player["inventory"][id] = item_count(id) + qty
	player_changed.emit()


func remove_item(id: String, qty: int = 1) -> bool:
	var have := item_count(id)
	if have < qty:
		return false
	if have == qty:
		player["inventory"].erase(id)
	else:
		player["inventory"][id] = have - qty
	player_changed.emit()
	return true


func has_trait(id: String) -> bool:
	return id in player.get("traits", [])


func kill_player(reason: String) -> void:
	if not player.get("alive", false):
		return
	player["alive"] = false
	active = false
	add_log("Você morreu: %s." % reason, "death")
	game_over.emit(reason)


func to_dict() -> Dictionary:
	return {"player": player, "log": log_entries.slice(-120)}


func from_dict(d: Dictionary) -> void:
	player = d["player"]
	log_entries = d.get("log", [])
	active = player.get("alive", false)
