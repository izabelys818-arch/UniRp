shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_opaque, world_vertex_coords;

// Lâminas de grama instanciadas (MultiMesh). UV.y = 0 na base, 1 na ponta.
// Cor por instância (INSTANCE_CUSTOM.rgb) vem do chão pintado pela direção de arte.

global uniform float wetness;
global uniform vec3 player_pos;
global uniform vec3 world_wind;
uniform float wind_strength = 0.22;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform sampler2D gust_noise : filter_linear_mipmap, repeat_enable;

varying float v_tip;
varying vec3 v_color;

void vertex() {
	v_tip = UV.y;
	v_color = INSTANCE_CUSTOM.rgb;
	// VERTEX já vem no espaço do mundo (world_vertex_coords): nada de inverter matriz por vértice
	vec3 world_root = MODEL_MATRIX[3].xyz;
	float t = TIME;
	// rajadas que atravessam o gramado + tremor fino por lâmina
	float gust = texture(gust_noise, world_root.xz * 0.035 + wind_dir * t * 0.06).r;
	float flutter = sin(t * 3.1 + INSTANCE_CUSTOM.a * 40.0 + world_root.x * 1.7) * 0.25;
	float bend = (gust * 1.4 - 0.3 + flutter) * wind_strength * (1.0 + wetness * 0.6) * max(0.4, length(world_wind.xz) * 2.0);
	// pisada: abre em volta do jogador
	vec2 away = world_root.xz - player_pos.xz;
	float d = length(away);
	float push = smoothstep(0.75, 0.15, d);
	// tudo proporcional à altura da lâmina (a escala Y da instância)
	float blade_h = length(MODEL_MATRIX[1].xyz);
	float k = UV.y * UV.y * blade_h;
	vec3 offset = vec3(wind_dir.x, 0.0, wind_dir.y) * bend * k * 1.6;
	offset.xz += normalize(away + vec2(0.0001)) * push * 1.4 * k;
	offset.y -= push * 0.6 * k;
	VERTEX += offset;
	// normal puxada para cima: o gramado ganha a luz do chão, não de papel
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.7));
}

void fragment() {
	vec3 base = v_color * 0.42;
	vec3 tip = v_color * mix(vec3(1.18, 1.12, 0.82), vec3(1.0), 0.5);
	vec3 col = mix(base, tip, smoothstep(0.0, 1.0, v_tip));
	col *= 1.0 - wetness * 0.28;
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.35, wetness);
	SPECULAR = mix(0.25, 0.6, wetness);
	// luz atravessando a folha contra o sol
	BACKLIGHT = vec3(0.32, 0.38, 0.12) * v_tip;
	AO = mix(0.45, 1.0, v_tip);
	AO_LIGHT_AFFECT = 0.4;
}
