shader_type canvas_item;

uniform vec4 backdrop : source_color = vec4(0.08, 0.1, 0.12, 1.0);
uniform vec4 window_color : source_color = vec4(0.22, 0.25, 0.28, 1.0);
uniform bool transparent_backdrop = false;
uniform float dim_amount = 0.0;
uniform float highlight_amount = 0.0;

void fragment() {
	vec4 figure = texture(TEXTURE, UV);
	vec2 q = UV - vec2(0.45, 0.4);
	float halo = exp(-dot(q * vec2(1.3, 0.85), q * vec2(1.3, 0.85)) * 5.0);
	vec3 bg = backdrop.rgb * (0.65 + halo * 0.8);
	// Janela desfocada: o fundo sugere o ambiente sem competir com as feições.
	float panel = smoothstep(0.67, 0.73, UV.x) * (1.0 - smoothstep(0.95, 1.0, UV.x));
	panel *= smoothstep(0.02, 0.07, UV.y) * (1.0 - smoothstep(0.52, 0.6, UV.y));
	bg = mix(bg, window_color.rgb, panel * 0.38);
	vec3 col = mix(bg, figure.rgb, figure.a);
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, 0.94);
	// Transição suave nos tons claros: preserva a textura da pele sem branco estourado.
	col = col / (vec3(1.0) + max(col - vec3(0.4), vec3(0.0)) * 0.65);
	float edge = smoothstep(0.3, 0.74, length((UV - vec2(0.5, 0.44)) * vec2(1.0, 0.8)));
	col *= 1.0 - edge * 0.26;
	col *= 1.0 - dim_amount * 0.45;
	col += vec3(0.035, 0.026, 0.012) * highlight_amount * halo;
	COLOR = vec4(col, transparent_backdrop ? figure.a : 1.0);
}
