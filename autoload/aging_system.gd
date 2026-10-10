extends Node

# Aniversários e envelhecimento, ligados ao calendário do TimeManager (sem relógio próprio).
# Cada pessoa tem um dia de nascimento (mês e dia). Quando o calendário chega nele, a pessoa faz
# aniversário e, com o envelhecimento ligado, ganha um ano. A idade de quem está longe é só um
# número que muda uma vez no dia do aniversário: nada é recalculado por quadro.
# O dia do nascimento é guardado numa escala de 28 dias por mês, então trocar o ritmo do
# calendário (meses de 3, 7 ou 28 dias) mantém cada aniversário no mesmo mês.

signal birthday(id: String, age: int)  # id "" = jogador
signal stage_changed(id: String, stage: String)

const STAGE_NAMES := {"crianca": "criança", "adolescente": "adolescente", "adulto": "adulto", "idoso": "idoso"}
const STAGE_RANGES := {"crianca": [6, 12], "adolescente": [13, 17], "adulto": [18, 59], "idoso": [60, 95]}
const STAGE_MSG := {
	"adolescente": "Você não é mais criança. Agora é adolescente: o corpo muda, a voz muda, a cidade olha diferente.",
	"adulto": "Maioridade. A partir de hoje, você responde por tudo o que fizer.",
	"idoso": "Sessenta anos. O espelho mostra alguém que sobreviveu a muita coisa.",
}

var _last_day: int = -1


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


static func stage_of(age: int) -> String:
	if age < 13:
		return "crianca"
	if age < 18:
		return "adolescente"
	if age < 60:
		return "adulto"
	return "idoso"


func reset() -> void:
	_last_day = TimeManager.day()


# ---------- datas de nascimento ----------

static func canonical_day(day_in_month: int, dpm: int) -> int:
	return clampi(int(floor(float(day_in_month - 1) * 28.0 / float(dpm))) + 1, 1, 28)


func _scaled_day(d28: int) -> int:
	return clampi(int(floor(float(clampi(d28, 1, 28) - 1) * float(TimeManager.days_per_month) / 28.0)) + 1, 1, TimeManager.days_per_month)


func _derived(key: String) -> Dictionary:
	var h := absi(key.hash())
	return {"m": h % 12, "d": (h / 12) % 28 + 1}


func birth_of(id: String) -> Dictionary:
	var b = GameState.player.get("nascimento", {}) if id == "" else NPCManager.npcs.get(id, {}).get("nascimento", {})
	if typeof(b) == TYPE_DICTIONARY and b.has("m") and b.has("d"):
		return b
	return _derived(str(GameState.player.get("name", "jogador")) if id == "" else id)


# Mês (0..11) e dia do mês (no ritmo atual) do aniversário.
func birthday_md(id: String) -> Vector2i:
	var b := birth_of(id)
	return Vector2i(int(b["m"]), _scaled_day(int(b["d"])))


func birthday_str(id: String) -> String:
	var md := birthday_md(id)
	return "%d de %s" % [md.y, TimeManager.MONTHS[md.x]]


# Dias de jogo até o próximo aniversário (0 = hoje).
func days_until_birthday(id: String) -> int:
	var md := birthday_md(id)
	var today := TimeManager.date()
	var y := int(today["y"])
	var target := TimeManager.index_of_date(y, md.x, md.y)
	var now := TimeManager.cal_index_of(TimeManager.day())
	if target < now:
		target = TimeManager.index_of_date(y + 1, md.x, md.y)
	return target - now


# ---------- passagem dos dias ----------

func _on_time_advanced(_minutes: int, _sleeping: bool) -> void:
	if not GameState.active:
		return
	var today := TimeManager.day()
	if _last_day < 0 or today < _last_day:
		_last_day = today
		return
	if today == _last_day:
		return
	var from := _last_day
	_last_day = today
	for gd in range(maxi(from + 1, today - 400), today + 1):
		_new_day(gd)


func _new_day(game_day: int) -> void:
	var dt := TimeManager.date_of(game_day)
	var md := Vector2i(int(dt["m"]), int(dt["d"]))
	if int(dt["d"]) == 1 and TimeManager.aging:
		for id in NPCManager.npcs:
			var b = NPCManager.npcs[id].get("bebe", {})
			if typeof(b) == TYPE_DICTIONARY and not b.is_empty():
				b["meses"] = mini(int(b.get("meses", 6)) + 1, 30)
	if birthday_md("") == md and GameState.player.get("alive", false):
		_player_birthday()
	for id in NPCManager.npcs.keys():
		if birthday_md(id) == md:
			_npc_birthday(id)


func _player_birthday() -> void:
	var p := GameState.player
	var old_age := int(p.get("age", 30))
	var new_age := old_age + (1 if TimeManager.aging else 0)
	p["age"] = new_age
	birthday.emit("", new_age)
	if TimeManager.aging:
		GameState.add_log("Hoje é o seu aniversário. Você fez %d anos." % new_age, "event")
	else:
		GameState.add_log("Hoje é o seu aniversário. Mais um ano, mesmo que o espelho não mude.", "event")
	var before := stage_of(old_age)
	var after := stage_of(new_age)
	if before != after:
		if STAGE_MSG.has(after):
			GameState.add_log(STAGE_MSG[after], "event")
		stage_changed.emit("", after)
	GameState.player_changed.emit()


func _npc_birthday(id: String) -> void:
	var npc: Dictionary = NPCManager.npcs[id]
	var st: Dictionary = NPCManager.state.get(id, {})
	if not st.get("vivo", true):
		return
	var old_age := int(npc.get("idade", 30))
	var age := old_age + (1 if TimeManager.aging else 0)
	npc["idade"] = age
	if NPCManager.state.has(id):
		# o elenco fixo volta do arquivo de dados ao carregar: a idade nova vai no estado salvo
		st["idade"] = age
	birthday.emit(id, age)
	if stage_of(old_age) != stage_of(age):
		stage_changed.emit(id, stage_of(age))
	if PhoneSystem.has_contact(id):
		GameState.add_log("Hoje é aniversário de %s: %d anos." % [str(npc.get("nome", id)), age], "phone")


# Próximos aniversários (jogador e contatos), para o app de calendário.
func upcoming(limit: int = 6) -> Array:
	var out: Array = [{"id": "", "nome": "Você", "dias": days_until_birthday("")}]
	for id in NPCManager.npcs:
		if PhoneSystem.has_contact(id) and NPCManager.state.get(id, {}).get("vivo", true):
			out.append({"id": id, "nome": str(NPCManager.npcs[id].get("nome", id)), "dias": days_until_birthday(id)})
	out.sort_custom(func(a, b): return int(a["dias"]) < int(b["dias"]))
	return out.slice(0, limit)
