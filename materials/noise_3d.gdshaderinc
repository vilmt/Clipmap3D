#define QUINTIC(t) t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

const ivec3 PRIME = ivec3(501125321, 1136930381, 1720413743);

const int[] GRADIENTS = {
	0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
	1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
	1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
	0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
	1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
	1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
	0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
	1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
	1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
	0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
	1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
	1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
	0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
	1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
	1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
	1, 1, 0, 0,  0,-1, 1, 0, -1, 1, 0, 0,  0,-1,-1, 0
};

int hash(int seed, ivec3 primed) {
	int h = seed ^ primed.x ^ primed.y ^ primed.z;

	h *= 0x27d4eb2d;
	return h;
}

float grad_coord(int seed, ivec3 primed, vec3 d) {
	int h = hash(seed, primed);
	h ^= h >> 15;
	h &= 63 << 2;
	
	ivec3 g = ivec3(GRADIENTS[h], GRADIENTS[h | 1], GRADIENTS[h | 2]);
	return dot(d, vec3(g));
}

float perlin(int seed, vec3 p) {
	ivec3 i0 = ivec3(floor(p));
	vec3 d0 = fract(p);
	
	vec3 d1 = d0 - 1.0;
	
	vec3 s = QUINTIC(d0);
	
	i0 *= PRIME;
	ivec3 i1 = i0 + PRIME;
	
	float xf00 = mix(grad_coord(seed, i0, d0), grad_coord(seed, ivec3(i1.x, i0.yz), vec3(d1.x, d0.yz)), s.x);
	float xf10 = mix(grad_coord(seed, ivec3(i0.x, i1.y, i0.z), vec3(d0.x, d1.y, d0.z)), grad_coord(seed, ivec3(i1.xy, i0.z), vec3(d1.xy, d0.z)), s.x);
	float xf01 = mix(grad_coord(seed, ivec3(i0.xy, i1.z), vec3(d0.xy, d0.z)), grad_coord(seed, ivec3(i1.x, i0.y, i1.z), vec3(d1.x, d0.y, d1.z)), s.x);
	float xf11 = mix(grad_coord(seed, ivec3(i0.x, i1.yz), vec3(d0.x, d1.yz)), grad_coord(seed, i1, d1), s.x);
	
	float yf0 = mix(xf00, xf10, s.y);
	float yf1 = mix(xf01, xf11, s.y);
	
	return mix(yf0, yf1, s.z) * 0.964921414852142333984375f;
}
