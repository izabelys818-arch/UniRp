extends ColorRect

# Acabamento de filme sobre a imagem 3D: granulação, vinheta, leve aberração cromática,
# gradação (sombras azuladas, luzes quentes) e uma respiração discreta de brilho.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.075;
uniform float vignette = 0.85;
uniform float aberration = 0.0022;
uniform float fade = 0.0;
uniform float sat = 0.82;
uniform float contrast = 1.1;
uniform vec3 shadow_tint = vec3(0.90, 1.0, 1.10);
uniform vec3 high_tint = vec3(1.10, 1.0, 0.86);
uniform float glow = 0.55;
uniform float breathe = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float r2 = dot(d, d);
	vec3 col;
	col.r = texture(screen_tex, uv + d * aberration * (1.0 + r2 * 6.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * aberration * (1.0 + r2 * 6.0)).b;
	// brilho suave nas altas luzes
	vec3 blur = texture(screen_tex, uv, 3.5).rgb;
	col += max(blur - vec3(0.62), vec3(0.0)) * glow;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, sat);
	vec3 cool = col * shadow_tint;
	vec3 warm = col * high_tint;
	col = mix(cool, warm, smoothstep(0.18, 0.75, l));
	col = (col - 0.5) * contrast + 0.5;
	col *= 1.0 - smoothstep(0.12, 0.62, r2 * vignette * 2.4);
	float n = hash(uv * vec2(1920.0, 1080.0) + TIME * vec2(47.0, 91.0));
	float n2 = hash(uv * vec2(960.0, 540.0) - TIME * vec2(13.0, 29.0));
	col += (n - 0.5) * grain + (n2 - 0.5) * grain * 0.6;
	col *= 1.0 - breathe * (0.03 - 0.03 * sin(TIME * 1.7 + uv.y * 3.0));
	col *= 1.0 - fade;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
"""

var mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	material = mat


# Gradação discreta para o jogo (sem respiração, pouca vinheta, grão leve).
func setup_game(grade: Dictionary) -> void:
	var sh: Array = grade.get("shadow", [0.92, 0.98, 1.08])
	var hi: Array = grade.get("high", [1.06, 1.0, 0.9])
	mat.set_shader_parameter("sat", float(grade.get("sat", 0.8)))
	mat.set_shader_parameter("contrast", float(grade.get("contrast", 1.06)))
	mat.set_shader_parameter("shadow_tint", Vector3(float(sh[0]), float(sh[1]), float(sh[2])))
	mat.set_shader_parameter("high_tint", Vector3(float(hi[0]), float(hi[1]), float(hi[2])))
	mat.set_shader_parameter("grain", float(grade.get("grain", 0.03)))
	mat.set_shader_parameter("vignette", 0.5)
	mat.set_shader_parameter("aberration", 0.0006)
	# brilho só nas luzes mais fortes, curto: janelas e postes sem auréola exagerada
	mat.set_shader_parameter("glow", 0.22)
	mat.set_shader_parameter("breathe", 0.0)


func set_fade(v: float) -> void:
	mat.set_shader_parameter("fade", clampf(v, 0.0, 1.0))
