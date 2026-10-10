shader_type spatial;
render_mode cull_back;
uniform sampler2D eye_map : source_color, filter_linear_mipmap;
uniform vec4 iris_color : source_color = vec4(0.35, 0.22, 0.13, 1.0);
uniform vec4 second_color : source_color = vec4(0.29, 0.47, 0.66, 1.0);
uniform bool heterochromia = false;
void fragment() {
	vec3 photo = texture(eye_map, UV).rgb;
	float a = distance(UV, vec2(0.707, 0.296));
	float b = distance(UV, vec2(0.296, 0.707));
	float radius = min(a, b);
	float mask = smoothstep(0.037, 0.045, radius) * (1.0 - smoothstep(0.106, 0.116, radius));
	vec3 pigment = (heterochromia && b < a) ? second_color.rgb : iris_color.rgb;
	float detail = clamp(dot(photo, vec3(0.299, 0.587, 0.114)) * 5.5, 0.28, 1.65);
	ALBEDO = mix(photo, pigment * detail, mask);
	ROUGHNESS = 0.3;
	SPECULAR = 0.38;
}
