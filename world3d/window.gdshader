shader_type spatial;
uniform float stream_visibility = 1.0;
uniform bool stream_inverse = false;
render_mode diffuse_burley, specular_schlick_ggx;

// Janelas de fachada com "interior mapping": atrás do vidro há uma sala falsa com
// profundidade (piso, teto, paredes de cores variadas, móveis em silhueta, quadro, cortina),
// que muda de perspectiva com a câmera, como nos jogos de mundo aberto atuais.
// Dia: o vidro reflete o céu (reflexo do motor) e a sala aparece de leve.
// Noite: janela de cômodo aceso (lit = 1) brilha quente; vidro comum mostra a sala escura.
// Cor do vértice: tom do vidro / cortina (Kit.vary_glass) ou cor da luz (Kit.vary_lit).

global uniform float night_glow;
global uniform float wetness;
global uniform vec3 world_wind;
uniform float lit = 0.0;
uniform vec3 room = vec3(3.4, 2.9, 3.4);

varying vec3 v_wpos;
varying vec3 v_wn;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (stream_visibility < 1.0) {
		float stream_pixel = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if ((!stream_inverse && stream_pixel >= stream_visibility) || (stream_inverse && stream_pixel < 1.0 - stream_visibility)) discard;
	}
	vec3 n = normalize(v_wn);
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);   // câmera -> dentro do prédio
	vec3 p = (v_wpos - n * 0.03) / room;
	vec3 cell = floor(p);
	vec3 local = p - cell;
	vec3 dd = d / room;
	vec3 inv = 1.0 / (dd + sign(dd) * 1e-5);
	vec3 k = (step(vec3(0.0), dd) - local) * inv;
	float t = min(min(k.x, k.y), k.z);
	vec3 hit = local + dd * t;
	float h1 = hash(cell);
	float h2 = hash(cell + 17.3);
	float h3 = hash(cell + 41.7);
	vec3 col;
	bool floor_ceiling = t == k.y;
	if (floor_ceiling) {
		// piso de taco ou cerâmica, teto claro
		vec3 floor_c = h2 > 0.5 ? vec3(0.36, 0.24, 0.15) : vec3(0.55, 0.5, 0.44);
		floor_c *= mix(0.85, 1.1, fract(hit.x * 6.0 + hit.z * 0.5));
		col = dd.y < 0.0 ? floor_c : vec3(0.82, 0.8, 0.75);
	} else {
		vec3 wall = mix(vec3(0.74, 0.68, 0.58), vec3(0.58, 0.64, 0.68), h1);
		wall = mix(wall, vec3(0.7, 0.55, 0.45), step(0.8, h3));
		col = wall * mix(0.78, 1.04, h2);
		float along = fract(hit.x + hit.z + h1);
		// móvel encostado (sofá, estante, mesa) e um quadro na parede
		float furn_h = 0.22 + 0.25 * h2;
		float furn = step(hit.y, furn_h) * step(0.15, along) * step(along, 0.15 + 0.45 + 0.2 * h3);
		col = mix(col, vec3(0.13, 0.11, 0.1) + vec3(0.05, 0.03, 0.0) * h1, furn * 0.9);
		float frame = step(0.55, hit.y) * step(hit.y, 0.75) * step(0.62, along) * step(along, 0.82);
		col = mix(col, vec3(0.2, 0.25, 0.3) * (0.6 + h3), frame * step(0.45, h1) * 0.8);
	}
	// fundo da sala mais escuro
	col *= mix(1.0, 0.5, clamp(t * 0.8, 0.0, 1.0));
	vec3 vc = COLOR.rgb;
	vec3 vlin = mix(pow((vc + vec3(0.055)) / 1.055, vec3(2.4)), vc / 12.92, step(vc, vec3(0.04045)));
	float facing = abs(dot(n, -d));
	float day = 1.0 - night_glow;
	// vidro (de dia ou apagado): sala vista pela luz do dia, cortina, reflexo do céu
	float curtain = smoothstep(0.32, 0.45, max(vc.r, max(vc.g, vc.b))) * (1.0 - lit);
	float open = step(0.5, hash(cell + 3.1)) * step(fract(hit.x + hit.z), 0.45);
	float folds = 0.75 + 0.25 * sin((v_wpos.x + v_wpos.z) * 28.0 + sin(TIME * 1.8 + h2 * 8.0) * length(world_wind) * 0.6);
	vec3 inside = col * mix(0.035, 0.42, day);
	vec3 fabric = vlin * folds * mix(0.04, 0.5, day);
	vec3 seen = mix(inside, fabric, curtain * (1.0 - open));
	vec3 sky = mix(vec3(0.42, 0.5, 0.6), vec3(0.03, 0.04, 0.07), night_glow);
	float fres = 0.1 + 0.6 * pow(1.0 - facing, 3.0);
	vec3 glass = seen * (1.0 - fres) + sky * fres * 0.55;
	if (lit > 0.5) {
		// cômodo aceso à noite: luz quente (tom da janela) com poça de luz no teto
		float lamp_pool = 1.0 - smoothstep(0.0, 0.6, length(hit.xz - vec2(0.5)));
		vec3 light = vlin * mix(1.4, 2.2, lamp_pool);
		vec3 lit_room = col * light * 1.6 + vlin * 0.12;
		EMISSION = mix(glass, lit_room, night_glow);
	} else {
		EMISSION = glass;
	}
	ALBEDO = vec3(0.012);
	ROUGHNESS = 0.035;
	SPECULAR = 0.9;
}
