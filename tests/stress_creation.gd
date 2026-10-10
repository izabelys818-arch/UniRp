extends Control

# Estresse da tela de criação: tempo de cada categoria, prévia 3D, aleatorizar, arrastar idade.
# Mede o pior quadro de cada ação e a memória. Uso: godot --path . res://tests/stress_creation.tscn

const UITheme = preload("res://ui/ui_theme.gd")
var worst := 0.0
var cc


func _process(delta: float) -> void:
	worst = maxf(worst, delta * 1000.0)


func _measure(label: String, action: Callable, frames_after: int = 6) -> void:
	worst = 0.0
	var t0 := Time.get_ticks_usec()
	action.call()
	var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	for i in frames_after:
		await get_tree().process_frame
	print("CRIACAO %-34s código=%6.0f ms  pior quadro=%6.0f ms  | mem=%3.0fMB nos=%d recursos=%d vram=%3.0fMB" % [label, sync_ms, worst, float(OS.get_static_memory_usage()) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	theme = UITheme.build()
	cc = preload("res://ui/character_creation.gd").new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	for i in 30:
		await get_tree().process_frame
	for i in cc.CATEGORIES.size():
		await _measure("categoria " + str(cc.CATEGORIES[i][1]), func(): cc._show_cat(i))
	await _measure("Corpo 3D ligar", func(): cc._show_view(true), 20)
	for t in 7:
		await _measure("tipo físico %d (3D)" % t, func():
			cc.spec["corpo"] = t
			cc._update_preview(), 25)
	for a in [9, 15, 28, 68]:
		await _measure("idade %d (3D)" % a, func():
			cc.age = a
			cc._update_preview(), 25)
	await _measure("Aleatorizar tudo (3D)", func(): cc._randomize_all(), 25)
	for k in 6:
		await _measure("Aleatorizar tudo #%d" % k, func(): cc._randomize_all(), 25)
	await _measure("Retrato", func(): cc._show_view(false), 10)
	for k in 6:
		await _measure("Aleatorizar tudo retrato #%d" % k, func(): cc._randomize_all(), 12)
	print("CRIACAO FIM")
	get_tree().quit()
