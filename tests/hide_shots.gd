extends Node

# Prédio na frente do jogador some (estilo Project Zomboid). Põe o jogador atrás de um prédio
# e tira captura com e sem a regra. Uso: godot --path . res://tests/hide_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://esconde_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 11 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	for i in 40:
		await get_tree().process_frame
	var wv = screen.world_view
	# procura um prédio alto e fica do lado oposto à câmera (atrás dele na tela)
	var best: Dictionary = {}
	var tallest := 0.0
	for s in wv.city.structures:
		var h: float = wv._structure_height(s)
		s["h"] = h
		if h > tallest and (s["rect"] as Rect2).size.length() > 8.0:
			tallest = h
			best = s
	print("maior prédio: altura ", snappedf(tallest, 0.1), " de ", wv.city.structures.size(), " estruturas")
	if best.is_empty():
		print("sem prédio alto")
		get_tree().quit()
		return
	var r: Rect2 = best["rect"]
	var d: Vector3 = wv.CAM_DIR.normalized()
	var behind := r.get_center() - Vector2(d.x, d.z).normalized() * (r.size.length() * 0.5 + 3.0)
	wv.player.position = Vector3(behind.x, 0.25, behind.y)
	wv.cam_target = wv.player.position
	wv.zoom = 9.0
	wv.camera.size = 9.0
	for i in 90:
		await get_tree().process_frame
	print("prédio abaixou: escala ", snappedf((best["root"] as Node3D).scale.y, 0.01), " altura ", snappedf(float(best["h"]), 0.1))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/esconde_depois.png")
	# sem a regra, para comparar
	(best["root"] as Node3D).scale = Vector3.ONE
	wv.set_process(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/esconde_antes.png")
	SaveManager.delete_save()
	get_tree().quit()
