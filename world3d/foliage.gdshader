shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha, world_vertex_coords;

// Cartões de folhas (MultiMesh) que formam as copas. INSTANCE_CUSTOM: rgb = cor da copa
// (direção de arte, linear), a = variação (qual janela da folha e espelhamento).

global uniform float wetness;
global uniform vec3 player_pos;
global uniform vec3 world_wind;
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaves_n : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D gust_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 leaf_mean = vec3(0.089, 0.149, 0.033);
uniform float wind_strength = 0.06;

varying vec3 v_color;
varying vec3 v_wp;

void vertex() {
	v_color = INSTANCE_CUSTOM.rgb;
	float variant = INSTANCE_CUSTOM.a;
	// janela 2x2 folhas dentro do conjunto 3x3, escolhida pela variação
	float pick = floor(variant * 4.0);
	vec2 offset = vec2(mod(pick, 2.0), floor(pick / 2.0)) / 3.0;
	vec2 uv = UV;
	if (fract(variant * 7.0) > 0.5) uv.x = 1.0 - uv.x;
	// janela maior da folha de fotos: folhas do tamanho real (antes pareciam gigantes)
	UV = offset * 0.5 + uv * (5.0 / 6.0);
	vec3 root = MODEL_MATRIX[3].xyz;
	float gust = texture(gust_noise, root.xz * 0.03 + vec2(TIME * 0.05, TIME * 0.035)).r;
	float flutter = sin(TIME * 4.3 + variant * 60.0 + root.y * 3.0);
	VERTEX += (world_wind + vec3(0.0, 0.15, 0.0)) * (gust - 0.4) * wind_strength * 6.0
		+ vec3(0.3, 0.6, 0.2) * flutter * wind_strength * 0.5;
	v_wp = VERTEX;
}

void fragment() {
	vec4 tex = texture(leaves, UV);
	// copa entre a câmera e o jogador fica rendada (Project Zomboid): o boneco não some
	vec3 to_cam = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 rel = v_wp - (player_pos + vec3(0.0, 0.9, 0.0));
	float along = dot(rel, to_cam);
	float off_axis = length(rel - to_cam * along);
	float cut = (1.0 - smoothstep(1.4, 2.6, off_axis)) * step(0.4, along);
	float dither = fract(dot(FRAGCOORD.xy, vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
	if (cut > 0.0 && dither < cut * 0.82) {
		discard;
	}
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	// detalhe só de luminosidade: folhas verdes da foto não pintam flores brancas/roxas de verde
	float lum = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722)) / dot(leaf_mean, vec3(0.2126, 0.7152, 0.0722));
	vec3 hue = mix(vec3(1.0), tex.rgb / leaf_mean / max(lum, 0.05), 0.25 * smoothstep(0.1, 0.3, v_color.g - max(v_color.r, v_color.b)));
	vec3 col = v_color * clamp(lum, 0.25, 2.2) * hue * 0.5;
	col *= 1.0 - wetness * 0.25;
	ALBEDO = col;
	NORMAL_MAP = texture(leaves_n, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = mix(0.62, 0.25, wetness);
	SPECULAR = mix(0.35, 0.65, wetness);
	// luz atravessando as folhas contra o sol
	BACKLIGHT = col * 0.55;
}
