extends Node

const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")
var fails := 0
var records: Array = []

func check(ok: bool, label: String) -> void:
	print(("OK " if ok else "FALHOU ") + label)
	if not ok: fails += 1

func _ready() -> void:
	var world := SubViewport.new()
	add_child(world)
	for subject in [[30,"homem",0],[30,"homem",1],[30,"homem",2],[30,"homem",3],[30,"homem",4],[30,"homem",5],[30,"homem",6],[30,"mulher",1],[9,"homem",1],[76,"mulher",1]]:
		var actor := Person.new()
		world.add_child(actor)
		actor.set_look(Looks.build({"pele":2,"cabelo":0,"corpo":subject[2]},subject[0],subject[1]))
		actor.set_process(false)
		check(actor.player_motion != null, "biblioteca compartilhada para NPC")
		var poses := {}
		var pose_shapes := {}
		for i in 5:
			actor.t = i * 12.0 + 5.0 - fposmod(actor.seed_n * 0.031,17.0)
			for frame in 20: actor._process(1.0/60.0)
			poses[actor.idle_pose] = true
			var hand_pose := actor.skel.get_bone_global_pose(actor.skel.find_bone("hand_r")).origin.snapped(Vector3.ONE*0.002)
			var head_pose := actor.skel.get_bone_global_pose(actor.skel.find_bone("Head")).basis.get_euler().snapped(Vector3.ONE*0.005)
			pose_shapes[str(hand_pose)+str(head_pose)] = true
		check(poses.size()==5, "cinco repousos determinísticos %s" % [str(subject)])
		check(pose_shapes.size()>=4, "repousos alteram ossos, não somente rótulos")
		var max_width := 0.0
		var z_min := INF
		var z_max := -INF
		var start := Time.get_ticks_usec()
		for frame in 360:
			actor.position.z += 1.55 * float(actor.HumanMotion.profile(subject[0])["walk"])/60.0
			actor.move_speed = 1.55 * float(actor.HumanMotion.profile(subject[0])["walk"])
			actor._process(1.0/60.0)
			var a := actor.skel.get_bone_global_pose(actor.skel.find_bone("foot_l")).origin
			var b := actor.skel.get_bone_global_pose(actor.skel.find_bone("foot_r")).origin
			if frame>60:
				max_width = maxf(max_width,absf(a.x-b.x)*actor.scale.x)
				z_min = minf(z_min,a.z)
				z_max = maxf(z_max,a.z)
				if frame==359:
					check(a.is_finite() and b.is_finite(), "pés com transformações válidas")
		var cost: float = (Time.get_ticks_usec()-start)/1000.0/360.0
		check(max_width < 0.19 and max_width > 0.06, "base sem abertura excessiva %s: %.3f m" % [subject,max_width])
		check(actor._cur_anim in ["Walk","Walk_Formal",actor.player_motion.walk_clip], "NPC não corre ao caminhar")
		check(z_max-z_min>0.25, "avanço da perna preservado")
		check(actor.rest_weight==0.0, "repouso sai gradualmente durante movimento")
		actor.move_speed = 0.0
		# a parada toca o passo final da captura antes do repouso
		var settled := -1
		for frame in 240:
			actor._process(1.0/60.0)
			if settled < 0 and actor._cur_anim == "Idle": settled = frame
		check(actor.rest_weight>0.0, "entrada suave no repouso")
		check(settled >= 0 and settled < 200, "parada do NPC termina em repouso (%d quadros)" % settled)
		actor.daily_action = "beber"
		actor._process(1.0/60.0)
		check(not actor.player_motion.active, "ação real tem prioridade")
		records.append({"age":subject[0],"gender":subject[1],"body":subject[2],"max_walk_width":max_width,"poses":poses.keys(),"pose_shapes":pose_shapes.size(),"foot_z_range":z_max-z_min,"cpu_ms":cost})
		actor.queue_free()
		await get_tree().process_frame
	world.queue_free();await get_tree().process_frame
	var output := OS.get_environment("LOCOMOTION_OUT")
	if output!="":
		var file := FileAccess.open(output+"/natural_motion.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(records,"\t"))
	print("RESULTADO NATURAL MOTION: ","OK" if fails==0 else str(fails)+" falhas")
	get_tree().quit(0 if fails==0 else 1)
