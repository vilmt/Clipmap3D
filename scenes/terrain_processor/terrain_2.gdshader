shader_type canvas_item;

uniform int mode: hint_enum("Height", "Normal", "Cycle") = 0;
uniform float amplitude: hint_range(0, 1000) = 25;

uniform vec2 offset = vec2(0.0);
uniform vec2 frequency = vec2(1.0);
uniform int fbm_iterations: hint_range(1, 10) = 7;
uniform float fbm_lacunarity: hint_range(0.0, 5.0) = 0.5;


vec2 hash( vec2 p ) {
	p = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float noise( in vec2 p ) {
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;
	vec2 i = floor(p + (p.x+p.y)*K1);
    vec2 a = p - i + (i.x+i.y)*K2;
    vec2 o = (a.x>a.y) ? vec2(1.0,0.0) : vec2(0.0,1.0); //vec2 of = 0.5 + 0.5*vec2(sign(a.x-a.y), sign(a.y-a.x));
    vec2 b = a - o + K2;
	vec2 c = a - 1.0 + 2.0*K2;
    vec3 h = max(0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3 n = h*h*h*h*vec3( dot(a,hash(i+0.0)), dot(b,hash(i+o)), dot(c,hash(i+1.0)));
    return dot(n, vec3(70.0));
}

float fbm(vec2 n) {
	float total = 0.0, a = 1.0;
	for (int i = 0; i < fbm_iterations; i++) {
		total += noise(n) * a;
		n = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * n;
		a *= fbm_lacunarity;
	}
	return total;
}


void fragment() {
	int current_mode = mode;
	if (mode == 2) {
		current_mode = int(TIME) % 2;
	}

	float falloff = max(1.0 - length(UV - 0.5) * 2.0, 0.0);

	vec2 uv = (UV + offset) * frequency;

	float height = fbm(uv) * falloff;

	float e = 0.001;

	float left = fbm(uv + vec2(-e, 0.0));
	float right = fbm(uv + vec2(e, 0.0));
	float down = fbm(uv + vec2(0.0, -e));
	float up = fbm(uv + vec2(0.0, e));

	left *= amplitude * falloff;
	right *= amplitude * falloff;
	down *= amplitude * falloff;
	up *= amplitude * falloff;

	vec3 normal = normalize(vec3(left - right, 1.0, down - up));
	normal = normal * 0.5 + 0.5;

	switch (current_mode) {
		case 0:
			COLOR = vec4(vec3(height), 1.0);
			break;
		case 1:
			COLOR = vec4(normal, 1.0);
			break;
	};
}