extends Node

signal needs_changed

const KEYS := ["saude", "saciedade", "hidratacao", "energia", "higiene", "sanidade"]
const LABELS := {
	"saude": "Saúde",
	"saciedade": "Saciedade",
	"hidratacao": "Hidratação",
	"energia": "Energia",
	"higiene": "Higiene",
	"sanidade": "Sanidade",
}

var values: Dictionary = {}


func _ready() -> void:
	reset()
	TimeManager.time_advanced.connect(_on_time_advanced)


func reset(overrides: Dictionary = {}) -> void:
	for k in KEYS:
		values[k] = 80.0
	values["saude"] = 100.0
	for k in overrides:
		if k in values:
			values[k] = float(overrides[k])
	needs_changed.emit()


func get_value(k: String) -> float:
	return float(values.get(k, 0.0))


func change(k: String, delta: float) -> void:
	values[k] = clampf(get_value(k) + delta, 0.0, 100.0)


func apply(effects: Dictionary, cause: String = "") -> void:
	for k in effects:
		if k in values:
			change(k, float(effects[k]))
	_after_change(cause)


func _on_time_advanced(minutes: int, sleeping: bool) -> void:
	if not GameState.active:
		return
	var h := minutes / 60.0
	var tough := 0.75 if GameState.has_trait("resistente") else 1.0
	if sleeping:
		change("saciedade", -2.0 * h * tough)
		change("hidratacao", -3.0 * h * tough)
		change("energia", 12.0 * h)
		change("higiene", -1.0 * h)
	else:
		change("saciedade", -4.0 * h * tough)
		change("hidratacao", -6.0 * h * tough)
		change("energia", -4.0 * h * tough)
		change("higiene", -2.0 * h)

	var sanity_loss := 0.5
	for k in ["saciedade", "hidratacao", "energia", "higiene"]:
		if get_value(k) < 20.0:
			sanity_loss += 1.5
	if GameState.has_trait("ansioso"):
		sanity_loss *= 1.5
	change("sanidade", -sanity_loss * h)

	var starving := get_value("saciedade") <= 0.0
	var dehydrated := get_value("hidratacao") <= 0.0
	if starving or dehydrated:
		change("saude", -6.0 * h)
	elif get_value("saciedade") > 50.0 and get_value("hidratacao") > 50.0 and get_value("energia") > 30.0:
		change("saude", 1.0 * h)
	if get_value("energia") <= 0.0:
		change("saude", -2.0 * h)

	var cause := "fome" if starving else ("sede" if dehydrated else "exaustão")
	_after_change(cause)


func _after_change(cause: String) -> void:
	needs_changed.emit()
	if get_value("saude") <= 0.0:
		GameState.kill_player(cause if cause != "" else "ferimentos")


func appearance_notes() -> String:
	var notes: Array = []
	if get_value("higiene") < 30.0:
		notes.append("está sujo e cheira mal")
	if get_value("energia") < 25.0:
		notes.append("tem olheiras fundas e parece exausto")
	if get_value("saude") < 50.0:
		notes.append("parece ferido ou doente")
	if get_value("saciedade") < 20.0:
		notes.append("parece faminto e fraco")
	if get_value("sanidade") < 30.0:
		notes.append("tem o olhar perturbado e age de forma estranha")
	return ", ".join(notes)


func to_dict() -> Dictionary:
	return values.duplicate()


func from_dict(d: Dictionary) -> void:
	for k in d:
		values[k] = float(d[k])
	needs_changed.emit()
