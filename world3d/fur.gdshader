shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Pelagem de bicho (cachorro) e penas (pombo). O padrão da pelagem segue o espaço da peça
// (acompanha o corpo ao andar): dorso mais escuro, barriga e patas mais claras, manchas para
// os malhados. Fios: relevo esticado na direção do pelo e brilho de pelo contra a luz.
// Pombo (feathers): pescoço iridescente (verde/roxo conforme o ângulo) e barras nas asas.

global uniform float wetness;
uniform vec4 coat : source_color = vec4(0.62, 0.42, 0.24, 1.0);
uniform vec4 belly : source_color = vec4(0.85, 0.74, 0.58, 1.0);
uniform vec4 saddle : source_color = vec4(0.32, 0.2, 0.12, 1.0);
uniform float spots = 0.0;            // 0 liso .. 1 malhado
uniform float feathers = 0.0;         // 1 = pombo
uniform float iridescent = 0.0;       // pescoço do pombo
uniform sampler2D fur_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 part_offset = vec3(0.0); // posição da peça no corpo (padrão contínuo entre peças)
uniform float belly_y = -10.0;        // abaixo desta altura (na peça) a pelagem clareia
uniform float sock_y = -10.0;         // patas: abaixo daqui, "meia" clara (malhado)

varying vec3 v_local;
varying vec3 v_lnorm;
varying float v_y;

void vertex() {
	v_local = VERTEX + part_offset;
	v_y = VERTEX.y;
	v_lnorm = NORMAL;
}

void fragment() {
	vec3 p = v_local;
	// dorso escuro (só onde a superfície olha bem para cima), barriga clara pela altura
	vec3 col = mix(coat.rgb, saddle.rgb, smoothstep(0.55, 0.95, v_lnorm.y) * 0.6 * (1.0 - spots));
	col = mix(col, belly.rgb, smoothstep(belly_y + 0.03, belly_y - 0.05, v_y));
	col = mix(col, belly.rgb, smoothstep(sock_y + 0.02, sock_y - 0.04, v_y) * spots);
	// manchas grandes (malhado)
	float sp = texture(fur_noise, vec2(p.x * 1.3 + p.y * 0.7, p.z * 1.3)).r;
	col = mix(col, saddle.rgb, smoothstep(0.55, 0.62, sp) * spots);
	// fios: ruído esticado ao longo do corpo (z) e variação de tom fio a fio
	float strands = texture(fur_noise, vec2(p.x * 38.0 + p.y * 30.0, p.z * 6.0)).r;
	col *= mix(0.82, 1.1, strands);
	float rough = 0.86;
	if (feathers > 0.5) {
		// penas: escamas sobrepostas e barras escuras nas asas
		float scale_p = texture(fur_noise, p.xz * 22.0).r;
		col *= mix(0.88, 1.06, scale_p);
		rough = 0.7;
	}
	if (iridescent > 0.0) {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		vec3 sheen = mix(vec3(0.15, 0.55, 0.3), vec3(0.5, 0.25, 0.6), facing);
		col = mix(col, col * 0.4 + sheen * 0.45, iridescent);
		rough = 0.45;
	}
	col *= 1.0 - wetness * 0.3;
	ALBEDO = col;
	NORMAL_MAP = vec3(0.5 + (strands - 0.5) * 0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(rough, 0.45, wetness);
	SPECULAR = 0.3;
	// brilho de pelo/penas na silhueta contra a luz
	RIM = feathers > 0.5 ? 0.2 : 0.45;
	RIM_TINT = 0.55;
	BACKLIGHT = col * 0.12;
}
