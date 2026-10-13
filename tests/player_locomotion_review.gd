extends Node

const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")
const Motion = preload("res://world3d/human_motion.gd")
var fails := 0
var rows: Array = []

func check(ok: bool, label: String) -> void:
	print(("OK " if ok else "FALHOU ") + label)
	if not ok:
		fails += 1

func _ready() -> void:
	var world := SubViewport.new()
	world.own_world_3d = true
	add_child(world)
	for subject in [[30,"homem"], [30,"mulher"], [9,"homem"], [9,"mulher"], [16,"mulher"], [76,"homem"], [76,"mulher"]]:
		var actor := Person.new()
		actor.use_player_locomotion = true
		world.add_child(actor)
		actor.set_look(Looks.build({"pele":2,"cabelo":0,"corpo":1},subject[0],subject[1]))
		actor.set_process(false)
		check(actor.player_motion != null and actor.player_motion.tree != null, "%s %s: árvore do jogador" % subject)
		var initial_phase: float = actor.player_motion.phase
		var profile := Motion.profile(subject[0])
		for mode in ["andar", "correr"]:
			var speed := (1.6 * float(profile["walk"])) if mode == "andar" else (5.0 * float(profile["run"]))
			actor.move_speed = speed
			actor.walking = true
			actor.running = mode == "correr"
			var time := Time.get_ticks_usec()
			var foot_positions := {}
			for frame in 360:
				actor.position.z += speed / 60.0
				actor._process(1.0/60.0)
				if frame > 240:
					foot_positions[str(actor.skel.get_bone_global_pose(actor.skel.find_bone("foot_l")).origin.snapped(Vector3.ONE * 0.001))] = true
			var cost_ms := (Time.get_ticks_usec() - time)/1000.0/360.0
			var motion = actor.player_motion
			var distance: float = motion.cycle_length if motion.get("cycle_length") != null else lerpf(motion.walk_distance, motion.run_distance, motion.run_weight)
			check(absf(motion.pace * distance - speed) < 0.01, "%s %s %s: ritmo por distância real" % [subject[0],subject[1],mode])
			check((actor._cur_anim == motion.walk_clip) == (mode == "andar") and actor._cur_anim != "Idle", "%s %s %s: ciclo correto %s" % [subject[0],subject[1],mode,actor._cur_anim])
			check(motion.tree.active and motion.pace > 0.0, "AnimationTree avançando")
			check(foot_positions.size() > 20, "ciclo continua animando após seis segundos")
			check(not actor.skel.get_bone_pose_rotation(actor._spine).is_equal_approx(Quaternion.IDENTITY), "pose locomotora não foi apagada")
			var record := {"age":subject[0],"gender":subject[1],"mode":mode,"speed_mps":speed,"clip":actor._cur_anim,"initial_phase":initial_phase,"pace_hz":motion.pace,"rate":motion.current_rate,"cycle_m":distance,"cpu_ms_per_actor_frame":cost_ms}
			rows.append(record)
			print("LOCOMOTION ", JSON.stringify(record))
		actor.move_speed = 0.0
		for frame in 260:
			actor._process(1.0/60.0)
		check(actor._cur_anim == "Idle" and actor.player_motion.pace == 0.0, "parada: sem passos após cessar o deslocamento")
		actor.daily_action = "beber"
		actor._process(1.0/60.0)
		check(not actor.player_motion.tree.active and not actor.player_motion.active, "ação suspende locomoção")
		actor.daily_action = ""
		actor.activity = "sentar"
		actor._process(1.0/60.0)
		check(actor._cur_anim == "Sitting_Enter" and not actor.player_motion.active, "sentar preserva transição existente")
		actor.activity = ""
		actor.busy_t = 0.0
		actor._act_prev = ""
		actor._process(1.0/60.0)
		check(actor.player_motion.active, "retoma árvore após ação")
		actor.set_active(false)
		check(not actor.player_motion.tree.active and not actor.ap.active, "árvore e AnimationPlayer pausam ao esconder")
		actor.set_active(true)
		check(actor.player_motion.tree.active and actor.ap.active, "reativação preservada")
		actor.set_look(Looks.build({"pele":2,"cabelo":0,"corpo":1},subject[0],subject[1]))
		actor.set_process(false)
		check(is_equal_approx(actor.player_motion.phase, initial_phase), "fase determinística após reconstrução")
		actor.queue_free()
		await get_tree().process_frame
	var npc := Person.new()
	world.add_child(npc)
	npc.set_look(Looks.build({"pele":2,"cabelo":0,"corpo":1},30,"homem"))
	check(npc.player_motion != null, "NPC usa a mesma biblioteca visual sem alterar IA")
	npc.queue_free()
	world.queue_free()
	await get_tree().process_frame
	var output := OS.get_environment("LOCOMOTION_OUT")
	if output != "":
		var file := FileAccess.open(output + "/locomotion.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(rows,"\t"))
	print("RESULTADO PLAYER LOCOMOTION: ", "OK" if fails == 0 else str(fails)+" falhas")
	get_tree().quit(0 if fails == 0 else 1)
