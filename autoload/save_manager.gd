extends Node

const VERSION := 1

var path: String = "user://save1.json"


func has_save() -> bool:
	return FileAccess.file_exists(path)


func save_game() -> void:
	if not GameState.active:
		return
	var data := {
		"version": VERSION,
		"game": GameState.to_dict(),
		"time": TimeManager.total_minutes,
		"needs": NeedsSystem.to_dict(),
		"npcs": NPCManager.to_dict(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	GameState.add_log("Jogo salvo.", "system")


func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	TimeManager.total_minutes = int(data["time"])
	GameState.from_dict(data["game"])
	for e in GameState.log_entries:
		if e.get("kind", "") == "npc" and str(e.get("text", "")).strip_edges().begins_with("{"):
			var parsed: Dictionary = preload("res://ai/prompts.gd").parse_npc_reply(str(e["text"]))
			var body := str(parsed.get("acao_corporal", ""))
			e["text"] = (("*" + body + "* ") if body != "" else "") + str(parsed.get("fala", ""))
	NeedsSystem.from_dict(data["needs"])
	NPCManager.reload_cast()
	Population.restore()
	NPCManager.from_dict(data["npcs"])
	return GameState.active


# Resumo do save para a tela inicial (sem carregar o jogo).
func preview() -> Dictionary:
	if not has_save():
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var p: Dictionary = data.get("game", {}).get("player", {})
	return {"name": str(p.get("name", "")), "day": int(data.get("time", 0)) / 1440 + 1, "money": int(p.get("money", 0)), "location": str(p.get("location", ""))}


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
