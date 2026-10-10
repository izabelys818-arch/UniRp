extends Node

# Casas e portas da cidade. Cada casa tem a sua fechadura: trancada, aberta ou arrombada.
# Quem está de fora pode tentar a maçaneta, bater, usar uma chave ou arrombar (com risco).
# Dentro, dá para vasculhar os cômodos atrás de comida, remédio e dinheiro.

signal changed

const LOOT := {
	"cozinha": [["pao", 0.55], ["miojo", 0.5], ["frutas", 0.4], ["agua", 0.45], ["refrigerante", 0.35], ["cafe", 0.3], ["cerveja", 0.25]],
	"quarto": [["analgesico", 0.25], ["cigarro", 0.3], ["curativo", 0.2], ["lenco_umedecido", 0.2]],
	"garagem": [["faca", 0.12], ["pe_de_cabra", 0.14], ["mixa", 0.06], ["energetico", 0.2]],
	"sala": [["cachaca", 0.2], ["cigarro", 0.2]],
}
const TYPES := ["familia", "idoso", "estudante", "casal", "abandonada"]

var near_door: String = ""     # local cuja porta está a poucos passos do jogador (preenchido pela vista 3D)


func all() -> Dictionary:
	if not GameState.player.has("houses"):
		GameState.player["houses"] = {}
	return GameState.player["houses"]


func is_house(id: String) -> bool:
	return World.locations.has(id) and bool(World.locations[id].get("casa_generica", false))


func register(id: String, label: String, seed_n: int) -> void:
	if World.locations.has(id):
		return
	World.locations[id] = {
		"nome": label, "tipo": "casa", "casa_generica": true, "seed": seed_n,
		"abre": 0, "fecha": 24, "x": 50, "y": 50, "loja": [], "servicos": [],
		"descricao": "Uma casa comum de bairro. Cheiro de poeira e de coisa guardada; a luz entra fraca pelas cortinas.",
	}


func _seed_of(id: String) -> int:
	return int(World.locations[id].get("seed", hash(id)))


func st(id: String) -> Dictionary:
	var h := all()
	if not h.has(id):
		var r := RandomNumberGenerator.new()
		r.seed = _seed_of(id)
		var kind: String = TYPES[r.randi() % TYPES.size()]
		h[id] = {
			"lock": "open" if r.randf() < 0.38 else "locked",
			"tipo": kind,
			"ocupada": kind != "abandonada" and r.randf() < 0.8,
			"busca": -1, "tentou": false, "forcada": 0,
		}
		if kind == "abandonada":
			h[id]["lock"] = "open" if r.randf() < 0.5 else "locked"
	return h[id]


func has_key(id: String) -> bool:
	return World.has_key("casa:" + id)


func locked(id: String) -> bool:
	if not is_house(id):
		return false
	if HomeSystem.has_access(id):
		return false
	return str(st(id)["lock"]) == "locked" and not has_key(id)


func forced(id: String) -> bool:
	return GameState.active and int(all().get("f_" + id, 0)) > TimeManager.total_minutes


func force_open(id: String, hours: float) -> void:
	all()["f_" + id] = TimeManager.total_minutes + int(hours * 60.0)


# Alguém está em casa agora? (muda a luz nas janelas e o risco de arrombar)
func resident_home(id: String) -> bool:
	if not is_house(id) or not st(id)["ocupada"] or HomeSystem.has_access(id):
		return false
	var h := TimeManager.hour()
	var r := RandomNumberGenerator.new()
	r.seed = _seed_of(id) + TimeManager.day() * 7 + h
	var p := 0.85 if (h >= 20 or h < 7) else (0.45 if h >= 17 else 0.3)
	return r.randf() < p


func label_of(id: String) -> String:
	return str(World.locations[id]["nome"])


# ---------- ações na porta ----------

func door_actions() -> Array:
	var id := near_door
	if id == "" or not World.locations.has(id) or not World.door_locked(id) or not GameState.active:
		return []
	var out: Array = []
	var loc: Dictionary = World.locations[id]
	var nome := label_of(id)
	if is_house(id) or loc.has("arrombavel"):
		out.append({"id": "porta:tentar", "label": "Tentar abrir a porta"})
	if is_house(id):
		out.append({"id": "porta:bater", "label": "Bater na porta"})
	if is_house(id) or loc.has("arrombavel"):
		var tool := CrimeSystem.tool_for_breaking()
		out.append({"id": "porta:arrombar", "label": "Arrombar a porta" + ("" if tool != "" else " (sem ferramenta)")})
	return out


func inside_actions() -> Array:
	var id := World.current_id()
	if not is_house(id):
		return []
	var out: Array = []
	if HomeSystem.has_access(id):
		# a casa é sua (alugada ou comprada na imobiliária)
		out.append({"id": "casa_g:dormir", "label": "Dormir na sua cama (8h)"})
		return out
	if int(st(id)["busca"]) != TimeManager.day():
		out.append({"id": "casa_g:vasculhar", "label": "Vasculhar os cômodos (30 min)"})
	out.append({"id": "casa_g:dormir", "label": "Deitar numa cama e dormir (8h)"})
	return out


func actions() -> Array:
	return door_actions() + inside_actions()


func do(action: String) -> void:
	match action:
		"porta:tentar":
			_try(near_door)
		"porta:bater":
			_knock(near_door)
		"porta:arrombar":
			_break_in(near_door)
		"casa_g:vasculhar":
			_search(World.current_id())
		"casa_g:dormir":
			_sleep(World.current_id())


func _try(id: String) -> void:
	TimeManager.advance(1)
	if is_house(id):
		st(id)["tentou"] = true
	GameState.add_log("Você gira a maçaneta. Trancada.", "info")
	changed.emit()


func _knock(id: String) -> void:
	TimeManager.advance(3)
	var s := st(id)
	if resident_home(id):
		var lines := [
			"Uma voz abafada vem de dentro: \"Quem é? Não estamos esperando ninguém!\" Ninguém abre.",
			"A cortina da janela mexe de leve. Alguém te olha por trás do vidro e some.",
			"Passos pesados do outro lado. \"Vai embora, ou eu chamo a polícia!\"",
		]
		GameState.add_log(lines.pick_random(), "event")
		if randf() < 0.18:
			GameState.add_log("O morador liga para a polícia por causa do barulho.", "danger")
			CrimeSystem.set_wanted(CrimeSystem.wanted() + 1)
	else:
		GameState.add_log("Você bate e espera. Só o silêncio, e um cachorro latindo na casa ao lado.", "info")
		if str(s["tipo"]) == "abandonada":
			GameState.add_log("Pela fresta dá para ver mato crescendo no quintal dos fundos. Faz tempo que ninguém mora aqui.", "info")
	changed.emit()


func _break_in(id: String) -> void:
	var loc: Dictionary = World.locations[id]
	if not is_house(id):
		CrimeSystem.break_into_shop(id)
		return
	var tool := CrimeSystem.tool_for_breaking()
	if tool == "":
		GameState.add_log("Você não tem nada para arrombar a porta. Um pé de cabra ou umas mixas resolveriam.", "info")
		return
	TimeManager.advance(randi_range(10, 25))
	var s := st(id)
	var night := TimeManager.hour() >= 22 or TimeManager.hour() < 5
	var silent: bool = World.items[tool].get("silencioso", false)
	var chance := float(World.items[tool]["arrombar"]) + (0.1 if GameState.has_trait("inteligente") else 0.0)
	var noise := (0.12 if silent else 0.4) * (0.7 if night else 1.0)
	var home := resident_home(id)
	# vizinhos e gente na rua
	var witnesses: Array = NPCManager.npcs_here()
	if not witnesses.is_empty() and not night:
		CrimeSystem.commit("invasao", "arrombar a porta de uma casa", 2)
	elif randf() < (0.1 if night else 0.28):
		GameState.add_log("Um vizinho vê você mexendo na porta e liga para a polícia.", "danger")
		CrimeSystem.set_wanted(CrimeSystem.wanted() + 2)
		CrimeSystem.police_event()
	if randf() > chance:
		GameState.add_log("A fechadura não cede e a madeira estala alto demais.", "event")
		if home and randf() < noise + 0.25:
			_resident_wakes(id)
		return
	s["lock"] = "broken"
	GameState.add_log("A porta cede com um estalo seco. Está aberta.", "event")
	CrimeSystem.data()["record"].append({"tipo": "arrombamento", "desc": "arrombar a porta de %s" % label_of(id), "hora": TimeManager.clock_str()})
	CrimeSystem.data()["last_crime"] = TimeManager.total_minutes
	if home and randf() < noise + 0.3:
		_resident_wakes(id)
	changed.emit()
	GameState.player_changed.emit()


func _resident_wakes(id: String) -> void:
	var roll := randf()
	if roll < 0.5:
		GameState.add_log("Alguém grita dentro da casa: \"TEM GENTE AQUI!\" Em segundos, a vizinhança acende as luzes.", "danger")
		CrimeSystem.set_wanted(CrimeSystem.wanted() + 2)
		CrimeSystem.police_event()
	else:
		var dmg := randi_range(8, 20)
		NeedsSystem.apply({"saude": -dmg, "sanidade": -8}, "levou uma pancada de um morador")
		GameState.add_log("Um morador de camisola surge no corredor com um taco e te acerta antes de você reagir.", "danger")


func _search(id: String) -> void:
	var s := st(id)
	TimeManager.advance(30)
	s["busca"] = TimeManager.day()
	var found: Array = []
	var kind := str(s["tipo"])
	var rooms := ["cozinha", "quarto", "sala", "garagem"]
	for room in rooms:
		for entry in LOOT[room]:
			var p := float(entry[1]) * (0.55 if kind == "abandonada" else 1.0) * (0.8 if kind == "estudante" else 1.0)
			if randf() < p * 0.5:
				GameState.add_item(str(entry[0]))
				found.append(World.item_name(str(entry[0])).to_lower())
	var cash := 0
	if randf() < 0.6:
		cash = randi_range(8, 60) if kind != "abandonada" else randi_range(0, 12)
		GameState.add_money(cash)
	var mine := has_key(id)
	if found.is_empty() and cash == 0:
		GameState.add_log("Você revira gavetas e armários, mas não acha nada que valha a pena.", "info")
	else:
		var parts: Array = found.duplicate()
		if cash > 0:
			parts.append("R$ %d em notas amassadas" % cash)
		GameState.add_log("Você vasculha os cômodos e leva: %s." % ", ".join(parts), "event")
	if not mine and (found.size() > 0 or cash > 0):
		CrimeSystem.data()["record"].append({"tipo": "furto", "desc": "furtar uma casa", "hora": TimeManager.clock_str()})
		CrimeSystem.data()["last_crime"] = TimeManager.total_minutes
	if not mine and resident_home(id) and randf() < 0.3:
		_resident_wakes(id)
	changed.emit()
	GameState.player_changed.emit()


func _sleep(id: String) -> void:
	if HomeSystem.has_access(id):
		HomeSystem.sleep_home()
		return
	if not has_key(id) and resident_home(id) and randf() < 0.35:
		GameState.add_log("Você mal se deita quando ouve a chave na porta. Alguém voltou para casa.", "danger")
		_resident_wakes(id)
		return
	Economy._sleep(480, "Você se estica numa cama que não é sua e adormece com um ouvido atento à porta.")
	if not has_key(id) and randf() < 0.1:
		GameState.add_log("Você acorda com passos no andar de cima. Melhor ir embora.", "info")
