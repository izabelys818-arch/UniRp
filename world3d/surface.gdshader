shader_type spatial;
uniform float stream_visibility = 1.0;
uniform bool stream_inverse = false;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Superfícies do mundo com texturas fotográficas (ambientCG, CC0) projetadas no espaço do
// mundo (triplanar): não depende de UV das caixas do Kit. A cor do vértice continua sendo a
// direção de arte (tom de cada parede, carro, grama) e a foto entra como material por baixo.
// Camada: UV2.x > 0 escolhe explicitamente; senão é deduzida pela cor e pela face.
// Por cima: relevo de verdade (parallax), desgaste do mundo real, sombra de nuvens e chuva.

global uniform vec3 world_wind;
global uniform float wetness;          // 0 seco .. 1 encharcado (city_builder.set_wetness)
global uniform float rain_time;
global uniform float night_glow;      // 0 dia .. 1 noite com energia: lâmpadas acesas
global uniform float grime;           // desgaste do cenário (0 novo .. 1 abandonado)
global uniform float cloud_shade;     // sombra de nuvens passando (0 sem sol direto)
global uniform float pom_quality;     // 0 desliga o relevo (qualidade "desempenho")

uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray height_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

// Por camada (0-3 chão em 4K, 4+ superfícies em 2K): tamanho do ladrilho, tingimento, média
// e relevo do parallax (m; 0 = sem relevo).
uniform float layer_tile[24];
uniform float layer_tint[24];
uniform vec3 layer_mean[24];
uniform float layer_pom[24];

// Categoria do material (o mesmo shader serve todas): 0 prédio, 1 asfalto, 2 chão/calçada,
// 3 objetos, 4 vegetação, 5 telhado.
uniform int kind = 0;
uniform float porosity = 0.6;          // quanto escurece molhado
uniform bool sheltered = false;       // interiores protegidos não recebem chuva

// índices das camadas (mesma ordem do layers.json)
const int L_GRASS = 0;
const int L_ASPHALT = 1;
const int L_PAVING = 2;
const int L_GROUND = 3;
const int L_PLASTER = 4;
const int L_BRICK = 5;
const int L_CONCRETE = 6;
const int L_ROOF = 7;
const int L_WOODFLOOR = 8;
const int L_WOOD = 9;
const int L_PAINTEDWOOD = 10;
const int L_TILES = 11;
const int L_FABRIC = 12;
const int L_LEATHER = 13;
const int L_CARPET = 14;
const int L_MARBLE = 15;
const int L_METAL = 16;
const int L_RUST = 17;
const int L_GRAVEL = 18;
const int L_BARK = 19;
const int L_LEAF = 20;
const int L_CARPAINT = 21;   // virtual: pintura de carro (metal liso e brilhante)
const int L_LAMPGLOW = 22;   // virtual: vidro de luminária (acende à noite)

varying flat int v_layer;
varying vec3 v_wpos;
varying vec3 v_wnorm;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

// Material deduzido: cor (em sRGB, como foi pintada), face e altura.
int classify(vec3 c, vec3 n, float y) {
	vec3 hsv = rgb2hsv(c);
	float h = hsv.x * 360.0;
	float s = hsv.y;
	float v = hsv.z;
	bool up = n.y > 0.7;
	bool green = h > 65.0 && h < 170.0 && s > 0.18;
	bool brown = h > 12.0 && h < 48.0 && s > 0.22 && v < 0.72;
	bool red = (h < 18.0 || h > 340.0) && s > 0.3;
	if (kind == 1) {
		// faixas e zebras: tinta sobre asfalto (concreto liso tingido)
		if (v > 0.62 || (s > 0.45 && h > 35.0 && h < 60.0)) return L_CONCRETE;
		return L_ASPHALT;
	}
	if (kind == 2) {
		if (green) return up ? L_GRASS : L_GROUND;
		if (brown) return L_GROUND;
		if (up) return v > 0.78 ? L_CONCRETE : L_PAVING;
		return L_CONCRETE;
	}
	if (kind == 4) {
		if (brown || (v < 0.35 && s < 0.35 && !green)) return L_BARK;
		if (green && up && y < 1.0) return L_GRASS;
		return L_LEAF;
	}
	if (kind == 5) {
		if (s < 0.12) return L_CONCRETE;
		return L_ROOF;
	}
	if (kind == 3) {
		if (brown) return L_WOOD;
		if (green && y < 1.3 && s > 0.25 && v < 0.6) return L_LEAF;
		if (v < 0.16) return L_METAL;
		if (s < 0.1 && v > 0.55) return L_CONCRETE;
		return L_METAL;
	}
	// prédios e casas
	if (up && y < 0.45) {
		if (brown) return L_WOODFLOOR;
		if (green) return L_GRASS;
		if (v > 0.66 && s < 0.25) return L_TILES;
		if (s < 0.12) return L_CONCRETE;
		return L_CARPET;
	}
	if (up && y > 2.2) return L_CONCRETE;
	if (brown && v < 0.42) return L_PAINTEDWOOD;
	if (red && v < 0.7 && s > 0.38) return L_BRICK;
	if (v < 0.13) return L_METAL;
	return L_PLASTER;
}

void vertex() {
	if (kind == 4 && COLOR.g > COLOR.r * 1.2 && VERTEX.y > 0.8) {
		VERTEX.xz += world_wind.xz * sin(TIME * 1.7 + VERTEX.x * 1.2) * 0.08;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// A matriz de normais preserva a orientação em peças com escala não uniforme.
	v_wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (UV2.x > 0.5) {
		v_layer = int(UV2.x + 0.5) - 1;
	} else {
		v_layer = classify(COLOR.rgb, v_wnorm, v_wpos.y);
	}
}

vec4 tex_albedo(int layer, vec2 uv) {
	if (layer < 4) return texture(ground_albedo, vec3(uv, float(layer)));
	return texture(surf_albedo, vec3(uv, float(layer - 4)));
}

vec3 tex_nr(int layer, vec2 uv) {
	if (layer < 4) return texture(ground_nr, vec3(uv, float(layer))).rgb;
	return texture(surf_nr, vec3(uv, float(layer - 4))).rgb;
}

float tex_height(int layer, vec2 uv) {
	return texture(height_tex, vec3(uv, float(layer))).r;
}

// Amostra com quebra de repetição: segunda leitura girada/escalada misturada por ruído amplo.
void sample_layer(int layer, vec2 uv, float breakup, out vec3 alb, out vec3 nr) {
	alb = tex_albedo(layer, uv).rgb;
	nr = tex_nr(layer, uv);
	if (breakup > 0.0) {
		vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.71 + vec2(0.37, 0.11);
		vec3 a2 = tex_albedo(layer, uv2).rgb;
		vec3 n2 = tex_nr(layer, uv2);
		// A segunda leitura gira o desenho: o relevo deve voltar ao plano da UV original.
		vec2 normal2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * (n2.rg * 2.0 - 1.0);
		n2.rg = normal2 * 0.5 + 0.5;
		alb = mix(alb, a2, breakup);
		nr = mix(nr, n2, breakup);
	}
}

// Parallax occlusion: anda pelo relevo na direção do olhar até achar a superfície.
// vt = olhar no plano da projeção (xy no plano, z para fora); hs = relevo em unidades de UV.
vec2 parallax(int layer, vec2 uv, vec3 vt, float hs, out float h_out) {
	const int STEPS = 12;
	vec2 delta = vt.xy / max(vt.z, 0.25) * hs / float(STEPS);
	float step_d = 1.0 / float(STEPS);
	float layer_d = 0.0;
	vec2 cur = uv;
	float depth = 1.0 - tex_height(layer, cur);
	vec2 prev = cur;
	float prev_gap = depth;
	for (int i = 0; i < STEPS; i++) {
		if (layer_d >= depth) {
			break;
		}
		prev = cur;
		prev_gap = depth - layer_d;
		cur -= delta;
		layer_d += step_d;
		depth = 1.0 - tex_height(layer, cur);
	}
	float after = depth - layer_d;
	float w = after / (after - prev_gap - 1e-5);
	vec2 hit = mix(cur, prev, clamp(w, 0.0, 1.0));
	h_out = tex_height(layer, hit);
	return hit;
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (stream_visibility < 1.0) {
		float stream_pixel = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if ((!stream_inverse && stream_pixel >= stream_visibility) || (stream_inverse && stream_pixel < 1.0 - stream_visibility)) discard;
	}
	int layer = v_layer;
	vec3 wn = normalize(v_wnorm);
	vec3 wp = v_wpos;
	// azulejo: veios do mármore claro + rejunte desenhado (sem o xadrez da foto)
	int src_layer = layer == L_TILES ? L_MARBLE : (layer == L_CARPAINT ? L_METAL : (layer == L_LAMPGLOW ? L_CONCRETE : layer));
	float tile = max(layer_tile[src_layer], 0.05);
	// pesos triplanares (mais nítidos que o normal: menos borrão nas quinas)
	vec3 bw = pow(abs(wn), vec3(6.0));
	bw /= (bw.x + bw.y + bw.z);
	vec2 uvx = wp.zy / tile;
	vec2 uvy = wp.xz / tile;
	vec2 uvz = wp.xy / tile;
	// relevo de verdade na projeção dominante (pedra, tijolo, telha, brita, rachadura)
	float pom = layer_pom[src_layer] * pom_quality;
	float hgt = 1.0;
	if (pom > 0.0) {
		vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float hs = pom / tile;
		if (bw.y >= bw.x && bw.y >= bw.z) {
			uvy = parallax(src_layer, uvy, vec3(V.x, V.z, abs(V.y)), hs, hgt);
		} else if (bw.x >= bw.z) {
			uvx = parallax(src_layer, uvx, vec3(V.z, V.y, abs(V.x)), hs, hgt);
		} else {
			uvz = parallax(src_layer, uvz, vec3(V.x, V.y, abs(V.z)), hs, hgt);
		}
	}
	float macro = texture(macro_noise, wp.xz * 0.013).r;
	float breakup = ((layer < 4 || layer == L_GRAVEL) && pom <= 0.0) ? smoothstep(0.35, 0.65, macro) : 0.0;
	vec3 ax = vec3(0.0); vec3 ay = vec3(0.0); vec3 az = vec3(0.0);
	vec3 nx = vec3(0.5, 0.5, 0.8); vec3 ny = nx; vec3 nz = nx;
	if (bw.x > 0.02) sample_layer(src_layer, uvx, breakup, ax, nx);
	if (bw.y > 0.02) sample_layer(src_layer, uvy, breakup, ay, ny);
	if (bw.z > 0.02) sample_layer(src_layer, uvz, breakup, az, nz);
	vec3 tex = ax * bw.x + ay * bw.y + az * bw.z;
	float rough = nx.b * bw.x + ny.b * bw.y + nz.b * bw.z;
	// normais: mistura "whiteout" (Ben Golus), com sinal por eixo
	vec3 axis_sign = sign(wn);
	vec2 tnx = (nx.rg * 2.0 - 1.0) * vec2(axis_sign.x, 1.0);
	vec2 tny = (ny.rg * 2.0 - 1.0) * vec2(axis_sign.y, 1.0);
	vec2 tnz = (nz.rg * 2.0 - 1.0) * vec2(-axis_sign.z, 1.0);
	float bump = layer == L_PLASTER ? 0.6 : 1.0;
	vec3 wx = vec3(tnx * bump + wn.zy, abs(wn.x));
	vec3 wy = vec3(tny * bump + wn.xz, abs(wn.y));
	vec3 wz = vec3(tnz * bump + wn.xy, abs(wn.z));
	// O eixo perpendicular também precisa do sinal da face. Sem isso, -X/-Y/-Z
	// eram iluminados como +X/+Y/+Z: fachadas escuras e reflexos do lado errado.
	wx.z *= axis_sign.x;
	wy.z *= axis_sign.y;
	wz.z *= axis_sign.z;
	vec3 world_n = normalize(wx.zyx * bw.x + wy.xzy * bw.y + wz.xyz * bw.z);

	// cor: vértice (sRGB) tinge a foto normalizada pela média da camada
	vec3 vcol = COLOR.rgb;
	vec3 vlin = mix(pow((vcol + vec3(0.055)) / 1.055, vec3(2.4)), vcol / 12.92, step(vcol, vec3(0.04045)));
	vec3 mean = max(layer_mean[src_layer], vec3(0.004));
	vec3 detail = tex / mean;
	// concreto e reboco: a foto entra mais contida (senão vira camuflagem em lajes grandes)
	if (src_layer == L_CONCRETE || src_layer == L_PLASTER) {
		detail = mix(vec3(1.0), detail, 0.5);
	}
	float tint = layer_tint[src_layer];
	vec3 alb = mix(tex, vlin * detail, tint);
	if (layer == L_TILES) {
		vec2 gr = abs(fract(uvy * tile / 0.3) - 0.5);
		float grout = smoothstep(0.47, 0.49, max(gr.x, gr.y));
		alb = mix(alb, alb * 0.55, grout);
		rough = mix(0.18, 0.9, grout);
	}
	// variação ampla: manchas de sujeira, sol e umidade (o chão não é uniforme)
	float patch = texture(macro_noise, wp.xz * 0.045 + vec2(0.31, 0.77)).r;
	alb *= mix(0.86, 1.08, patch);
	if (layer == L_GRASS) {
		alb *= mix(vec3(1.08, 1.0, 0.82), vec3(0.88, 1.02, 0.95), macro);
	}

	// ---- desgaste do mundo real ----
	float g = clamp(grime, 0.0, 1.0);
	float above = wp.y - 0.17;
	bool wall = abs(wn.y) < 0.5;
	float occ = 1.0;
	if (pom > 0.0) {
		// o fundo do rejunte acumula terra e sombra; musgo entre pedras de chão
		occ = mix(0.5, 1.0, smoothstep(0.0, 0.6, hgt));
		if (layer == L_PAVING || layer == L_GRAVEL) {
			float moss_j = (1.0 - smoothstep(0.08, 0.3, hgt)) * smoothstep(0.4, 0.7, patch) * (0.3 + g * 0.7);
			alb = mix(alb, vec3(0.045, 0.06, 0.025), moss_j * 0.7);
		}
	}
	if (!sheltered && wall && (kind == 0 || kind == 2 || kind == 3) && layer != L_CARPAINT && layer != L_LAMPGLOW) {
		float wobble = texture(macro_noise, vec2(wp.x + wp.z, 0.0) * 0.6).r;
		// sujeira que sobe do chão (respingo de chuva e poeira da rua)
		float splash = (1.0 - smoothstep(0.0, 0.35 + wobble * 0.7, above)) * (0.35 + g * 0.65);
		alb = mix(alb, alb * vec3(0.6, 0.56, 0.5), splash * 0.85);
		rough = mix(rough, 1.0, splash * 0.3);
		// escorridos verticais de chuva (beiral, janela, laje)
		float streak = texture(macro_noise, vec2((wp.x + wp.z) * 2.3, wp.y * 0.05 + 0.4)).r;
		streak = smoothstep(0.56, 0.78, streak) * smoothstep(0.2, 1.2, above) * (0.25 + g * 0.75);
		alb *= 1.0 - streak * 0.24;
		// limo junto à base, onde a água fica
		float moss = smoothstep(0.62, 0.8, texture(macro_noise, vec2(wp.x + wp.z, wp.y * 2.0) * 0.4).r) * (1.0 - smoothstep(0.0, 0.55, above)) * g;
		alb = mix(alb, vec3(0.035, 0.05, 0.02), moss * 0.55);
	}
	if (kind == 5) {
		// telhado: líquen em placas e escuro de água escorrendo
		float lichen = smoothstep(0.66, 0.82, texture(macro_noise, wp.xz * 0.35 + vec2(0.7, 0.2)).r) * (0.3 + g * 0.7);
		alb = mix(alb, alb * vec3(0.55, 0.62, 0.42), lichen * 0.6);
		float runoff = smoothstep(0.5, 0.8, texture(macro_noise, vec2(wp.x * 1.8, wp.z * 0.12)).r);
		alb *= 1.0 - runoff * 0.15 * (0.4 + g);
	}
	if (layer == L_ASPHALT) {
		// manchas de óleo (escuras e lisas) e remendos de recapeamento
		// poucas manchas, grandes e suaves (onde carro estaciona), não pintas espalhadas
		float oil = smoothstep(0.78, 0.9, texture(macro_noise, wp.xz * 0.075 + vec2(0.5, 0.1)).r);
		alb *= 1.0 - oil * 0.35;
		rough = mix(rough, 0.35, oil);
		vec2 cell = floor(wp.xz / vec2(2.6, 1.7));
		vec2 local = fract(wp.xz / vec2(2.6, 1.7));
		float repair = step(0.965 - g * 0.04, hash12(cell)) * step(0.08, local.x) * step(local.x, 0.92) * step(0.1, local.y) * step(local.y, 0.9);
		alb = mix(alb, alb * (hash12(cell + 7.0) > 0.5 ? 0.82 : 1.1), repair);
	}
	alb *= occ;

	// sombra de nuvens passando (só com sol): manchas largas e lentas em tudo
	if (!sheltered && cloud_shade > 0.001) {
		vec2 cuv = wp.xz * 0.0032 + vec2(TIME * 0.0045, TIME * 0.0028);
		float cloud = smoothstep(0.45, 0.68, texture(macro_noise, cuv).r);
		alb *= 1.0 - cloud * cloud_shade;
	}

	// chuva: escurece o poroso, espelha o chão, poças nos baixos do relevo e respingos
	float wet = sheltered ? 0.0 : clamp(wetness, 0.0, 1.0);
	float up = smoothstep(0.6, 0.95, wn.y);
	float soak = wet * mix(0.45, 1.0, up);
	alb *= mix(1.0, 1.0 - porosity * 0.45, soak);
	rough = mix(rough, mix(0.28, 0.12, up), soak);
	float puddle = 0.0;
	if (wet > 0.05 && up > 0.5 && (kind == 1 || kind == 2)) {
		float pn = texture(macro_noise, wp.xz * 0.09 + vec2(0.13, 0.52)).r;
		// a água junta primeiro nos baixos (rejunte, rachadura)
		pn += (1.0 - hgt) * 0.12;
		puddle = smoothstep(0.58, 0.66, pn) * smoothstep(0.3, 0.9, wet) * up;
		vec2 cell = floor(wp.xz * 3.0);
		vec2 f = fract(wp.xz * 3.0) - 0.5;
		float ph = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float t = fract(rain_time * 0.9 + ph);
		float ring = sin(length(f) * 40.0 - t * 18.0) * (1.0 - t) * smoothstep(0.5, 0.1, length(f));
		vec3 ripple = normalize(vec3(f * ring * 0.6, 1.0));
		world_n = normalize(mix(world_n, vec3(ripple.x, 1.0, ripple.y), puddle));
		alb = mix(alb, alb * 0.45, puddle);
		rough = mix(rough, 0.03, puddle);
	}
	float metal = 0.0;
	if (layer == L_CARPAINT) {
		// verniz: os arranhões da foto viram só leve variação de brilho
		alb = mix(vlin, alb, 0.25);
		rough = mix(0.08, 0.22, rough);
		metal = 0.35;
	}
	if (layer == L_LAMPGLOW) {
		// globo de luminária: acende quente à noite e estoura no glow
		float phase = hash12(floor(wp.xz * 0.1));
		float flicker = phase > 0.96 ? mix(0.45, 1.0, step(0.12, fract(TIME * 1.7 + phase))) : 1.0;
		EMISSION = vlin * vec3(1.0, 0.82, 0.55) * night_glow * 9.0 * flicker;
		rough = 0.2;
	}
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = metal;
	SPECULAR = mix(0.4, 0.7, soak);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}
