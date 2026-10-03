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
	NeedsSystem.from_dict(data["needs"])
	NPCManager.from_dict(data["npcs"])
	return GameState.active


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
