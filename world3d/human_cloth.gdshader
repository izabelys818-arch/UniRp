shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Roupas e sapatos: a textura MakeHuman da peça (cinza: dobras, costuras, desbotado) tinge
// a cor escolhida; por cima entra a trama de verdade do tecido pelo UV (acompanha o corpo):
// 0 algodão (malha + brilho aveludado), 1 jeans (sarja diagonal com fio branco), 2 couro
// (poros e brilho de graxa), 3 lã/sarja de terno. A barra junta poeira (ou lama na chuva) e
// a roupa encharca com a chuva.

global uniform float grime;

uniform sampler2D cloth_map : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 dye : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D weave : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_noise : filter_linear_mipmap, repeat_enable;
uniform int fabric = 0;
uniform float weave_scale = 26.0;
uniform float wet = 0.0;
uniform float hem_top = 0.3;           // até onde (m) a poeira sobe: calça 0,3; sapato só a sola
uniform float hem_amount = 0.35;

varying float v_height;

void vertex() {
	// altura no corpo (já deformado pela animação): barra e sola ficam embaixo
	v_height = VERTEX.y;
}

void fragment() {
	vec4 base = texture(cloth_map, UV);
	vec3 shade = base.rgb / 0.62;
	vec3 alb = dye.rgb * shade;
	vec2 wuv = UV * weave_scale;
	vec3 w = texture(weave, wuv).rgb;
	vec2 nrm = w.rg;
	float rough = 0.9;
	float sheen = 0.0;
	float spec = 0.3;
	if (fabric == 1) {
		// jeans: sarja a 45°, fio de trama branco aparecendo e desbotado irregular
		float twill = sin((UV.x + UV.y) * weave_scale * 22.0);
		float slub = texture(grain_noise, vec2(UV.x * 3.0, UV.y * 40.0)).r;
		alb = mix(alb, alb * vec3(1.35, 1.38, 1.42) + 0.02, smoothstep(0.55, 1.0, twill) * 0.35);
		alb *= mix(0.9, 1.08, slub);
		nrm = mix(nrm, vec2(0.5) + vec2(twill, -twill) * 0.12, 0.6);
		rough = 0.82;
		sheen = 0.12;
	} else if (fabric == 2) {
		// couro: poros finos e brilho de graxa que varia
		float polish = texture(grain_noise, UV * 2.0).r;
		rough = mix(0.72, 0.48, polish) * mix(1.0, w.b * 1.3, 0.35);
		spec = 0.45;
	} else if (fabric == 3) {
		// lã de terno: trama mais fechada, levemente aveludada
		rough = 0.78;
		sheen = 0.25;
	} else {
		// algodão: malha, fiapos e aquele brilho aveludado na borda
		float fuzz = texture(grain_noise, UV * 30.0).r;
		alb *= mix(0.95, 1.04, fuzz);
		rough = 0.92;
		sheen = 0.38;
	}
	NORMAL_MAP = vec3(nrm, 1.0);
	NORMAL_MAP_DEPTH = fabric == 2 ? 0.6 : 0.9;
	// poeira/lama na barra da calça, na ponta e na sola do sapato
	float g = clamp(grime, 0.0, 1.0);
	float hem = (1.0 - smoothstep(hem_top * 0.15, hem_top, v_height)) * (0.3 + g * 0.7) * hem_amount;
	float speck = texture(grain_noise, UV * 11.0).r;
	hem *= smoothstep(0.25, 0.75, speck + hem * 0.5);
	vec3 dirt = mix(vec3(0.42, 0.36, 0.28), vec3(0.18, 0.14, 0.1), wet);
	alb = mix(alb, alb * 0.5 + dirt * (0.3 + 0.3 * speck), hem);
	rough = mix(rough, 1.0, hem * 0.4);
	// encharcada: escurece e perde o aveludado
	alb *= 1.0 - wet * 0.32;
	ALBEDO = alb;
	ROUGHNESS = mix(rough, 0.4, wet);
	SPECULAR = spec;
	RIM = sheen * (1.0 - wet);
	RIM_TINT = 0.4;
}
