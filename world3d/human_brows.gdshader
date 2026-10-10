shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D brow_map : source_color, filter_linear_mipmap;
uniform vec4 brow_color : source_color = vec4(0.1, 0.07, 0.05, 1.0);
void fragment() {
	vec4 strand = texture(brow_map, UV);
	ALBEDO = brow_color.rgb * (0.72 + strand.r * 0.28);
	ALPHA = strand.a;
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
