shader_type spatial;
uniform float stream_visibility = 1.0;
uniform bool stream_inverse = false;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Água (lago, chafariz): ondas em duas escalas andando com o vento, cor de profundidade
// (mais escura no meio), reflexo forte de lado (Fresnel), respingos de chuva.

global uniform float wetness;
global uniform float rain_time;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 deep : source_color = vec4(0.06, 0.14, 0.16, 1.0);
uniform vec4 shallow : source_color = vec4(0.2, 0.32, 0.3, 1.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (stream_visibility < 1.0) {
		float stream_pixel = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if ((!stream_inverse && stream_pixel >= stream_visibility) || (stream_inverse && stream_pixel < 1.0 - stream_visibility)) discard;
	}
	vec2 p = v_wpos.xz;
	vec3 n1 = texture(wave_a, p * 0.18 + vec2(TIME * 0.02, TIME * 0.013)).rgb;
	vec3 n2 = texture(wave_b, p * 0.47 - vec2(TIME * 0.031, -TIME * 0.022)).rgb;
	vec3 n = normalize((n1 * 2.0 - 1.0) + (n2 * 2.0 - 1.0) * 0.6);
	// chuva: anéis pequenos espalhados
	if (wetness > 0.05) {
		vec2 cell = floor(p * 4.0);
		vec2 f = fract(p * 4.0) - 0.5;
		float ph = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float t = fract(rain_time * 1.1 + ph);
		float ring = sin(length(f) * 46.0 - t * 20.0) * (1.0 - t) * smoothstep(0.5, 0.05, length(f));
		n.xy += f * ring * 0.9 * wetness;
	}
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fres = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
	ALBEDO = mix(shallow.rgb, deep.rgb, 0.6);
	ROUGHNESS = 0.03;
	SPECULAR = 0.6;
	ALPHA = mix(0.78, 0.97, fres);
}
