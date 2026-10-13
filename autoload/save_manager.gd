extends Node

const VERSION := 1

var path: String = "user://save1.json"


func has_save() -> bool:
	return FileAccess.file_exists(path)


# Salva o jogo e diz se deu certo (o formato do arquivo é o mesmo de sempre).
func save_game() -> bool:
	if not GameState.active:
		return false
	get_tree().call_group("world_stream", "flush")
	var data := {
		"version": VERSION,
		"game": GameState.to_dict(),
		"time": TimeManager.total_minutes,
		"calendar": TimeManager.cal_to_dict(),
		"needs": NeedsSystem.to_dict(),
		"npcs": NPCManager.to_dict(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Não foi possível salvar: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data))
	var err := f.get_error()
	f.close()
	if err != OK or not FileAccess.file_exists(path):
		push_warning("Falha ao gravar o save: %s" % error_string(err))
		return false
	GameState.add_log("Jogo salvo.", "system")
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	TimeManager.total_minutes = int(data["time"])
	# saves antigos não têm calendário: começam em 1º de março de 2026 e seguem o ritmo escolhido
	TimeManager.cal_from_dict(data.get("calendar", {}))
	Settings.apply_calendar()
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
	AgingSystem.reset()
	return GameState.active


# Resumo do save para a tela inicial (sem carregar o jogo).
func preview() -> Dictionary:
	if not has_save():
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var p: Dictionary = data.get("game", {}).get("player", {})
	var dt: Dictionary = TimeManager.date_from_save(int(data.get("time", 0)), data.get("calendar", {}))
	return {"name": str(p.get("name", "")), "day": int(data.get("time", 0)) / 1440 + 1, "money": int(p.get("money", 0)), "location": str(p.get("location", "")),
		"date": "%d de %s de %d" % [dt["d"], TimeManager.MONTHS_SHORT[dt["m"]], dt["y"]], "age": int(p.get("age", 0))}


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
