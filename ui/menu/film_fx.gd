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
	col += max(blur - vec3(0.62), vec3(0.0)) * 0.55;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 0.82);
	vec3 cool = col * vec3(0.90, 1.0, 1.10);
	vec3 warm = col * vec3(1.10, 1.0, 0.86);
	col = mix(cool, warm, smoothstep(0.18, 0.75, l));
	col = (col - 0.5) * 1.1 + 0.5;
	col *= 1.0 - smoothstep(0.12, 0.62, r2 * vignette * 2.4);
	float n = hash(uv * vec2(1920.0, 1080.0) + TIME * vec2(47.0, 91.0));
	float n2 = hash(uv * vec2(960.0, 540.0) - TIME * vec2(13.0, 29.0));
	col += (n - 0.5) * grain + (n2 - 0.5) * grain * 0.6;
	col *= 0.97 + 0.03 * sin(TIME * 1.7 + uv.y * 3.0);
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


func set_fade(v: float) -> void:
	mat.set_shader_parameter("fade", clampf(v, 0.0, 1.0))
