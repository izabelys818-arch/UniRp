shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, sss_mode_skin;

// Pele: textura MakeHuman (2K) + pigmento do rosto por vértice (lábios, bochechas, marcas),
// poros (relevo celular fino), oleosidade variando, luz que atravessa (SSS) e penugem
// contra a luz. Molha na chuva (wet).

uniform sampler2D skin_map : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 fill : source_color = vec4(0.8, 0.6, 0.5, 1.0);
uniform sampler2D pores : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D oil_noise : filter_linear_mipmap, repeat_enable;
uniform float pore_scale = 48.0;
uniform float pore_depth = 0.45;
uniform float age_k = 0.0;          // 0 jovem .. 1 idoso: pele mais seca e marcada
uniform float wet = 0.0;

void fragment() {
	vec3 alb = texture(skin_map, UV).rgb * tint.rgb * COLOR.rgb;
	// manchinhas de cor (sardas, vasinhos) muito sutis: pele real não é uniforme
	float blotch = texture(oil_noise, UV * 9.0).r;
	alb *= mix(vec3(1.03, 0.98, 0.97), vec3(0.97, 1.0, 1.01), blotch);
	ALBEDO = alb * (1.0 - wet * 0.16);
	// poros: dois tamanhos misturados para não parecer padrão repetido
	vec3 p1 = texture(pores, UV * pore_scale).rgb;
	vec3 p2 = texture(pores, UV * pore_scale * 2.37 + vec2(0.31, 0.57)).rgb;
	NORMAL_MAP = normalize(mix(p1, p2, 0.4) * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = pore_depth * mix(1.0, 1.5, age_k);
	// oleosidade: brilho que varia em manchas largas (testa e nariz mais brilhantes na média)
	float oil = texture(oil_noise, UV * 3.0 + vec2(0.17, 0.4)).r;
	float rough = mix(0.62, 0.42, oil) + age_k * 0.1;
	ROUGHNESS = mix(rough, 0.22, wet);
	SPECULAR = mix(0.32, 0.5, wet);
	SSS_STRENGTH = 0.38;
	SSS_TRANSMITTANCE_COLOR = vec4(0.88, 0.3, 0.2, 1.0);
	SSS_TRANSMITTANCE_DEPTH = 0.09;
	SSS_TRANSMITTANCE_BOOST = 0.18;
	// penugem: leve halo quente na silhueta contra a luz
	RIM = 0.18;
	RIM_TINT = 0.65;
	// preenchimento mínimo para a pessoa não sumir na noite
	EMISSION = fill.rgb * 0.035;
}
