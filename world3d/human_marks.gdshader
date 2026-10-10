shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform vec3 nose;
uniform float eye_y;
uniform vec4 marks_a = vec4(0.0);
uniform vec4 marks_b = vec4(0.0);
varying vec3 p;
void vertex() { p = VERTEX; }
float patch(vec2 d) { return exp(-dot(d,d)*2.0); }
void fragment() {
	float front = smoothstep(nose.z - 0.065, nose.z - 0.025, p.z);
	float cheek = patch(vec2((abs(p.x)-0.038)/0.04,(p.y-eye_y+0.025)/0.027));
	vec2 grid = vec2(p.x*900.0,p.y*900.0);
	float rnd = fract(sin(dot(floor(grid),vec2(12.9898,78.233)))*43758.5453);
	float freckle = (1.0-smoothstep(0.07,0.3,length(fract(grid)-vec2(0.5)))) * step(0.76,rnd) * cheek * marks_a.w;
	float mole = patch(vec2((p.x+0.032)/0.002,(p.y-nose.y+0.054)/0.002)) * marks_b.z;
	float scar_y = eye_y - 0.025 + (p.x + 0.055)*0.65;
	float scar = patch(vec2((p.x+0.045)/0.026,(p.y-scar_y)/0.0012)) * marks_a.x;
	float tattoo = patch(vec2((p.x-0.045)/0.005,(p.y-nose.y+0.026)/0.016)) * marks_a.z;
	float neck = patch(vec2(p.x/0.026,(p.y-eye_y+0.22)/0.028)) * marks_a.y;
	float bags = patch(vec2((abs(p.x)-0.032)/0.029,(p.y-eye_y+0.012)/0.01)) * marks_b.x;
	float makeup = patch(vec2((abs(p.x)-0.034)/0.027,(p.y-eye_y-0.008)/0.01)) * marks_b.y;
	float burn = patch(vec2((p.x-0.047)/0.021,(p.y-nose.y+0.041)/0.024)) * marks_b.w;
	ALBEDO = mix(vec3(0.17,0.085,0.045),vec3(0.36,0.15,0.14),clamp(scar+burn,0.0,1.0));
	ALBEDO = mix(ALBEDO,vec3(0.075,0.09,0.12),clamp(tattoo+neck,0.0,1.0));
	ALBEDO = mix(ALBEDO,vec3(0.23,0.15,0.23),clamp(bags+makeup,0.0,1.0));
	ALPHA = clamp(freckle*0.55+mole*0.7+scar*0.48+tattoo*0.7+neck*0.65+bags*0.28+makeup*0.48+burn*0.35,0.0,0.8)*front;
	ROUGHNESS = 0.75;
}
