extends "res://ui/game/overlay.gd"

var log_view: RichTextLabel
var star_re := RegEx.new()


func _ready() -> void:
	star_re.compile("\\*([^*]+)\\*")
	_build_overlay("Histórico", Vector2(860, 620))
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 17)
	log_view.add_theme_font_size_override("italics_font_size", 17)
	log_view.add_theme_font_size_override("bold_font_size", 17)
	content.add_child(log_view)


func open() -> void:
	log_view.clear()
	for e in GameState.log_entries:
		log_view.append_text(format_entry(e, star_re) + "\n\n")
	open_overlay()


static func format_entry(e: Dictionary, re: RegEx) -> String:
	var kind := str(e.get("kind", "info"))
	var color: String = UI.KIND_COLORS.get(kind, "#cccccc")
	var text := re.sub(UI.escape_bbcode(str(e.get("text", ""))), "[i][color=#a39f95]$1[/color][/i]", true)
	match kind:
		"player":
			return "[color=%s][b]Você:[/b] %s[/color]" % [color, text]
		"npc":
			return "[color=%s][b]%s:[/b][/color] %s" % [UI.ACCENT.to_html(false), UI.escape_bbcode(str(e.get("speaker", ""))), text]
		"narration":
			return "[i][color=%s]%s[/color][/i]" % [color, text]
		"death":
			return "[b][color=%s]%s[/color][/b]" % [color, text]
	return "[color=%s]%s[/color]" % [color, text]
