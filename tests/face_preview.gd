extends Node

const FaceRig = preload("res://ui/face/face_rig.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")

var out_path := "face_preview.png"
var cell_size := Vector2(218, 262)


func _ready() -> void:
	var looks: Dictionary = World._load_json("res://data/npc_looks.json")
	var root := ColorRect.new()
	root.color = Color("#121417")
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.position = Vector2(6, 6)
	root.add_child(grid)
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "npcs"
	if mode == "grande":
		grid.columns = 3
		cell_size = Vector2(440, 560)
		for pair in [["marina", "chorando"], ["ruan", "furioso"], ["helena", "neutro"]]:
			_cell(grid, looks, pair[0], pair[1], "%s - %s" % pair)
	elif mode == "npcs":
		for id in looks:
			_cell(grid, looks, id, "neutro", NPCManager.npcs[id]["nome"])
	else:
		for emo in World.emotions:
			_cell(grid, looks, mode, emo, emo)
	out_path = "face_preview_%s.png" % mode
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/" + out_path
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT: ", path)
	get_tree().quit()


func _cell(grid: GridContainer, looks: Dictionary, id: String, emo: String, label: String) -> void:
	var box := VBoxContainer.new()
	grid.add_child(box)
	var face := FaceRig.new()
	face.custom_minimum_size = cell_size
	face.bg_color = Color(NPCManager.npcs[id]["cor"])
	var loc: String = NPCManager.npcs[id]["rotina"][0]["local"]
	face.scene = FaceRig.scene_for_location(loc, World.locations[loc]["tipo"])
	box.add_child(face)
	face.set_look(LookBuilder.build(looks[id], int(NPCManager.npcs[id]["idade"]), NPCManager.npcs[id]["genero"]))
	face.set_emotion(emo, true)
	face.blink = 0.0
	face.next_blink = 999.0
	var l := Label.new()
	l.text = label
	box.add_child(l)
