extends Node

signal log_added(entry: Dictionary)
signal player_changed
signal game_over(reason: String)

const MAX_LOG := 300

var player: Dictionary = {}
var log_entries: Array = []
var active: bool = false


func city() -> String:
	return str(World.scenario().get("nome", "Porto Cinza"))


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


func age() -> int:
	return int(player.get("age", 30))


# Menor de idade: bares, bebida, drogas, crime, trabalho adulto, carro, contratos e romance ficam bloqueados.
func is_minor() -> bool:
	return age() < 18


# Itens que menor de idade não compra, não usa e não recebe.
const MINOR_ITEMS := {"cerveja": "alcool", "cachaca": "alcool", "cigarro": "cigarro", "droga": "droga", "faca": "arma", "pe_de_cabra": "crime", "mixa": "crime"}
const MINOR_REASONS := {
	"alcool": "O balconista olha bem pra você e balança a cabeça: \"Bebida só pra maior de idade.\" (bloqueado para menores)",
	"cigarro": "\"Cigarro pra menor? Nem pensar.\" O maço volta para a prateleira. (bloqueado para menores)",
	"droga": "Ninguém que mexe com isso quer problema com menor de idade. (bloqueado para menores)",
	"arma": "\"Isso não é coisa pra você.\" Ninguém te entrega. (bloqueado para menores)",
	"crime": "O coração dispara e você desiste. Não é esse o caminho. (crime bloqueado para menores)",
	"trabalho": "Ninguém contrata menor de idade para esse serviço. (bloqueado para menores)",
	"bico": "Ninguém dá bico pra criança. Volta quando tiver uns 14 anos. (bloqueado para menores de 14)",
	"contrato": "Menor de idade não assina contrato: aluguel, compra ou negócio ficam para depois dos 18. (bloqueado para menores)",
	"romance": "Isso não acontece: o seu personagem é menor de idade. (romance bloqueado para menores)",
	"carro": "Você não tem idade para dirigir. (bloqueado para menores)",
}


# Motivo do bloqueio para o jogador menor de idade, ou "" se ele pode.
func minor_block(kind: String) -> String:
	if not is_minor():
		return ""
	if kind == "bico" and age() >= 14:
		return ""
	return str(MINOR_REASONS.get(kind, ""))


# Se o jogador é menor e a ação é proibida, avisa e devolve true.
func refuse_minor(kind: String) -> bool:
	var why := minor_block(kind)
	if why == "":
		return false
	add_log(why, "info")
	return true


func refuse_item_for_minor(item_id: String) -> bool:
	return MINOR_ITEMS.has(item_id) and refuse_minor(str(MINOR_ITEMS[item_id]))


func age_stage() -> String:
	var a := age()
	if a < 13:
		return "crianca"
	if a < 18:
		return "adolescente"
	if a < 60:
		return "adulto"
	return "idoso"


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
	var stream: Dictionary = player.get("world_stream", {})
	for pair in [["seed", 7741], ["chunks", {}], ["landmarks", {}], ["npc_positions", {}]]:
		if not stream.has(pair[0]):
			stream[pair[0]] = pair[1]
	player["world_stream"] = stream
	log_entries = d.get("log", [])
	active = player.get("alive", false)
