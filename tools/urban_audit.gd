extends Node

const Layout = preload("res://world3d/city_layout.gd")

func _ready() -> void:
	audit.call_deferred()

func audit() -> void:
	Layout.urban_prototype_enabled = OS.get_environment("URBAN_PHASE") != "before"
	var state = get_tree().root.get_node("GameState")
	var world = get_tree().root.get_node("World")
	var npc_manager = get_tree().root.get_node("NPCManager")
	for scenario in ["porto_cinza", "vale_sereno", "nova_aurora", "colapso"]:
		state.new_game({"name": "Auditoria", "age": 30, "gender": "homem", "cenario": scenario, "origin": "morador_antigo", "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
		var layout := Layout.new()
		var kinds := {}
		var types := {}
		var building_area := 0.0
		for cell in layout.blocks:
			var info: Dictionary = layout.blocks[cell]
			var kind: String = "marco" if info["loc"] != "" else str(info["kind"])
			kinds[kind] = int(kinds.get(kind, 0)) + 1
		for id in layout.lots:
			var lot: Dictionary = layout.lots[id]
			building_area += (lot["building"] as Rect2).get_area()
			var kind: String = str(world.locations[id].get("tipo", "casa"))
			types[kind] = int(types.get(kind, 0)) + 1
		print("AUDIT ", scenario, " blocks=", kinds, " lots=", layout.lots.size(), " registered_houses=", layout.house_ids.size(), " types=", types, " lot_building_area=", snappedf(building_area, 0.1))
		if scenario == "porto_cinza":
			for id in ["mercado", "lanchonete", "bar", "praca", "apartamento", "hospital", "rodoviaria", "beco"]:
				print("LANDMARK ", id, " cell=", layout.lots[id]["cell"], " building=", layout.lots[id]["building"])
			for cell in layout.blocks:
				if Vector2(cell).distance_to(Vector2(3, 3)) < 2.2:
					print("CENTRAL ", cell, " ", layout.blocks[cell])
	var jobs := []
	for id in npc_manager.npcs:
		var npc: Dictionary = npc_manager.npcs[id]
		if npc.get("servicos", {}).has("emprego"):
			jobs.append({"npc": id, "job": npc["servicos"]["emprego"]})
	print("JOBS ", jobs)
	get_tree().quit()
