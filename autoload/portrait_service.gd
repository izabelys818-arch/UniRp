extends Node

signal portrait_ready(npc_id: String, emotion: String)
signal status_changed(text: String)

var dir: String = "user://portraits"
const MAX_WIDTH := 640
const STYLE := "Photorealistic close-up portrait photograph, head and shoulders, the subject looks straight into the camera. Dark moody background, dim harsh side lighting, cinematic, natural skin texture with pores and imperfections, subtle film grain, slightly unsettling atmosphere, like a real person photographed at night. No text, no watermark, no frame, no illustration."
const GENDER_EN := {"homem": "man", "mulher": "woman"}

var cache: Dictionary = {}
var queue: Array = []
var pending: Dictionary = {}
var failed: Dictionary = {}
var working: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


func file_path(npc_id: String, emotion: String) -> String:
	return "%s/%s/%s.png" % [dir, npc_id, emotion]


func get_texture(npc_id: String, emotion: String) -> Texture2D:
	var key := npc_id + "/" + emotion
	if cache.has(key):
		return cache[key]
	var p := file_path(npc_id, emotion)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	cache[key] = tex
	return tex


func best_texture(npc_id: String, emotion: String) -> Texture2D:
	var tex := get_texture(npc_id, emotion)
	return tex if tex != null else get_texture(npc_id, "neutro")


func request(npc_id: String, emotion: String) -> void:
	if not World.emotions.has(emotion):
		emotion = "neutro"
	if not Settings.images_ready():
		return
	var key := npc_id + "/" + emotion
	if pending.has(key) or failed.has(key) or get_texture(npc_id, emotion) != null:
		return
	if emotion != "neutro":
		request(npc_id, "neutro")
	pending[key] = true
	queue.append([npc_id, emotion])
	if not working:
		_process_queue()


func _process_queue() -> void:
	working = true
	while not queue.is_empty():
		var job: Array = queue.pop_front()
		await _generate(job[0], job[1])
		pending.erase(job[0] + "/" + job[1])
	working = false
	status_changed.emit("")


func _person_description(npc_id: String) -> String:
	var n: Dictionary = NPCManager.npcs[npc_id]
	return "a %d-year-old Brazilian %s. Physical appearance: %s. Occupation: %s." % [
		int(n["idade"]), GENDER_EN.get(n["genero"], "person"), n["aparencia"], n["profissao"]]


func _generate(npc_id: String, emotion: String) -> void:
	var key := npc_id + "/" + emotion
	var emo: Dictionary = World.emotions[emotion]
	status_changed.emit("Gerando rosto de %s (%s)..." % [NPCManager.npcs[npc_id]["nome"], emo["pt"]])
	var refs: Array = []
	var prompt := "%s The subject is %s Facial expression: %s." % [STYLE, _person_description(npc_id), emo["en"]]
	if emotion != "neutro":
		if get_texture(npc_id, "neutro") == null:
			failed[key] = true
			return
		if Settings.image_model_refs:
			refs.append(FileAccess.get_file_as_bytes(file_path(npc_id, "neutro")))
			prompt = "Edit the reference photo. Keep EXACTLY the same person: same face and identity, same age, hair, clothes, lighting, background, camera angle and framing. Change ONLY the facial expression to: %s. Keep it photorealistic." % emo["en"]
	var res: Dictionary = await AIService.generate_image(prompt, refs)
	if not res["ok"]:
		failed[key] = true
		GameState.add_log("Não foi possível gerar um rosto: " + str(res["error"]), "system")
		return
	store(npc_id, emotion, res["image"])


func store(npc_id: String, emotion: String, img: Image) -> void:
	if img.get_width() > MAX_WIDTH:
		img.resize(MAX_WIDTH, int(img.get_height() * float(MAX_WIDTH) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(dir + "/" + npc_id)
	img.save_png(file_path(npc_id, emotion))
	cache[npc_id + "/" + emotion] = ImageTexture.create_from_image(img)
	portrait_ready.emit(npc_id, emotion)


func clear_all() -> void:
	cache.clear()
	failed.clear()
	for npc_dir in DirAccess.get_directories_at(dir):
		var d := dir + "/" + npc_dir
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(d + "/" + f))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(d))
