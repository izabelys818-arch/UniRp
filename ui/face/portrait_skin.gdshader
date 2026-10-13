shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D skin_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 skin_tint : source_color = vec4(1.0);
uniform vec3 nose;
uniform vec3 eye_left;
uniform vec3 eye_right;
uniform float blush = 0.0;
uniform float fatigue = 0.0;
uniform float pale = 0.0;
uniform float bruise = 0.0;
uniform float tears = 0.0;
uniform float sweat = 0.0;
uniform float menace = 0.0;
uniform float phase = 0.0;
varying vec3 face_position;

float spot(vec3 p, vec3 c, vec3 radius) {
	vec3 d = (p - c) / radius;
	return exp(-dot(d, d) * 2.5);
}

void vertex() {
	face_position = VERTEX;
}

void fragment() {
	vec3 p = face_position;
	vec3 base = texture(skin_texture, UV).rgb * skin_tint.rgb * COLOR.rgb;
	float front = smoothstep(nose.z - 0.065, nose.z - 0.025, p.z);
	float cheeks = spot(p, vec3(eye_left.x * 1.3, eye_left.y - 0.037, nose.z - 0.02), vec3(0.032, 0.03, 0.05))
		+ spot(p, vec3(eye_right.x * 1.3, eye_right.y - 0.037, nose.z - 0.02), vec3(0.032, 0.03, 0.05));
	float under_eyes = spot(p, eye_left - vec3(0.0, 0.011, 0.006), vec3(0.026, 0.008, 0.04))
		+ spot(p, eye_right - vec3(0.0, 0.011, 0.006), vec3(0.026, 0.008, 0.04));
	base = mix(base, base * vec3(1.15, 0.69, 0.66), min(0.65, cheeks * blush * front));
	base = mix(base, base * vec3(0.52, 0.49, 0.63), min(0.65, under_eyes * fatigue * front));
	float injured = spot(p, eye_left - vec3(0.0, 0.01, 0.0), vec3(0.029, 0.023, 0.04));
	float cut = spot(p, vec3(-0.045, nose.y - 0.031, nose.z - 0.025), vec3(0.012, 0.002, 0.04));
	base = mix(base, base * vec3(0.61, 0.34, 0.47), injured * bruise * front * 0.62);
	base = mix(base, vec3(0.26, 0.04, 0.045), cut * bruise * front * 0.65);
	base = mix(base, base * vec3(0.97, 1.01, 1.07), pale * 0.4);
	base *= 1.0 - under_eyes * menace * front * 0.15;
	// Lábios e dentes são geometria. Não pinta uma segunda boca por cima da textura.
	float wet = 0.0;
	for (int i = 0; i < 2; i++) {
		vec3 eye = i == 0 ? eye_left : eye_right;
		float side = i == 0 ? -1.0 : 1.0;
		float down = eye.y - p.y;
		float track_x = eye.x * 0.86 + side * down * 0.12 + sin(down * 130.0 + float(i)) * 0.001;
		float stream = exp(-pow((p.x - track_x) / 0.0016, 2.0));
		stream *= smoothstep(0.003, 0.011, down) * (1.0 - smoothstep(0.06, 0.085, down));
		wet += stream * tears * front;
		float drop_down = mod(phase * 0.018 + float(i) * 0.029, 0.072) + 0.008;
		vec3 drop = vec3(eye.x * 0.86 + side * drop_down * 0.12, eye.y - drop_down, p.z);
		wet += spot(p, drop, vec3(0.002, 0.004, 0.05)) * tears * front;
	}
	float forehead = spot(p, vec3(0.0, eye_left.y + 0.045, nose.z - 0.015), vec3(0.065, 0.045, 0.07));
	wet = clamp(wet + forehead * sweat * 0.35, 0.0, 1.0);
	vec3 bead = vec3(0.047, eye_left.y + 0.04 - mod(phase * 0.008, 0.025), p.z);
	wet = clamp(wet + spot(p, bead, vec3(0.002, 0.0035, 0.05)) * sweat * front, 0.0, 1.0);
	base = mix(base, base * 0.87 + vec3(0.014, 0.02, 0.025), wet * 0.55);
	ALBEDO = base;
	ROUGHNESS = mix(0.68, 0.15, wet);
	SPECULAR = mix(0.24, 0.7, wet);
	EMISSION = base * 0.018 + vec3(0.035, 0.045, 0.055) * wet * tears;
}
