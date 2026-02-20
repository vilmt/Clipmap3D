#[compute]
#version 460

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_maps;
layout(rg16f, binding = 1) restrict uniform image2DArray gradient_maps;
layout(r32f, binding = 2) restrict uniform image2DArray control_maps;

layout(push_constant, std430) uniform Params {
	ivec4 region;
	int lod;
	int seed;
	ivec2 origin;
	ivec2 texels_per_vertex;
	vec2 vertex_spacing;
	float height_amplitude;
	
	float _pad0;
	float _pad1;
	float _pad2;
	
} params;

#define EPSILON 1e-6
#define INV_255 0.003921568627450
#define TAU 6.28318530717958

ivec2 imod(ivec2 x, ivec2 s) {
	ivec2 m = min(sign(x), 0);
	return x-s*((x-m)/s+m);
}

vec2 hash21(vec2 p) {
	vec3 p3 = vec3(p, float(params.seed));
	p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return -1.0 + 2.0 * fract((p3.xx+p3.yz)*p3.zy);
}

vec2 hash22(vec2 p) {
	vec2 q = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return fract(sin(q)*43758.5453);
}

// gradient noise and derivative by iq https://www.shadertoy.com/view/XdXBRH
vec3 noised(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0); 
    
    vec2 ga = hash21(i + vec2(0.0, 0.0));
    vec2 gb = hash21(i + vec2(1.0, 0.0));
    vec2 gc = hash21(i + vec2(0.0, 1.0));
    vec2 gd = hash21(i + vec2(1.0, 1.0));
    
    float va = dot(ga, f - vec2(0.0, 0.0));
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));

    return vec3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),
        ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +
        du * (u.yx*(va-vb-vc+vd) + vec2(vb,vc) - va));
}

// erosion ridges and derivative by vilmt
// based on smooth voronoi by iq https://iquilezles.org/articles/smoothvoronoi/
vec3 erosion(vec2 p, vec2 curl) {
	vec2 p_i = floor(p);
	vec2 p_f = fract(p);
	
	vec3 r = vec3(0.0);
	
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 d = o - p_f + hash22(p_i + o);
			
			float dd = min(1.0, dot(d, d));
			
			float w = dd * (dd - 2.0) + 1.0; // quartic interpolant weight
			vec2 w_d = 4.0 * (1.0 - dd) * d; // derivative
			
			float phase = dot(d, curl) * TAU;
			float c = cos(phase);
			float s = sin(phase);
			
			r += vec3(c * w, TAU * s * curl * w + c * w_d);
		}
	}
	
	return r;
}

// height, derivative, and erosion parameter
vec4 height_map(vec2 p) {
	float scale = 0.0005; // master scale value
	
    // FBM terrain
	vec3 h = vec3(0.0);
	float h_a = 0.5; // amplitude (don't change this)
	float h_f = 1.0 * scale; // frequency
	
	for (int i = 0; i < 6; i++) {
		vec3 n = noised(p * h_f) * h_a;
		h += n * vec3(1.0, h_f, h_f);
		
		h_a *= 0.4; // gain
		h_f *= 1.8; // lacunarity
	}
	
	h.x += 0.5; // map terrain to [0, 1]
	
	// FBM erosion
	vec3 e = vec3(0.0);
	float e_a = 0.005; // erosion amplitude
	float e_f = 20.0 * scale; // erosion frequency
	
	float e_w = e_a; // erosion weight, used for normalizing
	
	for (int i = 0; i < 7; i++) {
		vec2 curl = (h.zy + e.zy) * vec2(1.0, -1.0) / scale; // scale-invariant curl direction
		vec3 n = erosion(p * e_f, curl) * e_a;
		e += n * vec3(1.0, e_f, e_f);
		
		e_a *= 0.5;
		e_f *= 1.8;
	}
	
	return vec4(h + e, e.x / e_w);
}

struct Material {
	uint id_0;
	uint id_1;
	float blend;
};

// painting helpers
void brush_replace(inout Material mat, uint id) {
	mat.id_0 = id;
	mat.id_1 = id;
	mat.blend = 0.0;
}

void brush_add(inout Material mat, uint id, float strength) {
	if (strength < EPSILON) return;
	
	strength = clamp(strength, 0.0, 1.0);
	
	if (id != mat.id_0 && id != mat.id_1) {
		if (mat.blend > 0.5) {
			mat.blend = min(mat.blend + strength, 1.0);
			mat.id_0 = mat.blend > 1.0 - INV_255 ? id : mat.id_0;
		} else {
			mat.blend = max(mat.blend - strength, 0.0);
			mat.id_1 = mat.blend < INV_255 ? id : mat.id_1;
		}
	}
	
	if (mat.id_0 == id) {
		mat.blend = max(mat.blend - strength, 0.0);
	}

	if (mat.id_1 == id) {
		mat.blend = min(mat.blend + strength, 1.0);
	}
}

// should match Clipmap3DTextureAsset array indices in source
#define GRASS_ID 0
#define CLIFF_ID 1
#define SNOW_ID 2
#define MOSS_ID 3

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	
	if (any(greaterThanEqual(local, params.region.zw))) {
		return; // skip if texel is outside requested region
	}
	
	ivec2 size = imageSize(height_maps).xy;
	ivec2 texel = local + params.region.xy + params.origin - (size / 2 - params.texels_per_vertex); // half size
	vec2 scale = params.vertex_spacing * float(1 << params.lod) / vec2(params.texels_per_vertex);
	
	vec4 h = height_map(texel * scale);
	
	ivec3 coords = ivec3(imod(texel.xy, size), params.lod); // toroidal wrapping
	
	// NOTE: The simple terrain compute shader uses central differences.
	// No need to derive analytical derivatives like it's done here.
	imageStore(height_maps, coords, vec4(h.x * params.height_amplitude, 0.0, 0.0, 0.0));
	imageStore(gradient_maps, coords, vec4(h.yz * params.height_amplitude, 0.0, 0.0)); // gradient maps expect world-space texel spacing
	
	// arbitrary parameters for painting (independent of world scaling)
	float height = h.x;
	float slope = 1.0 - normalize(vec3(-h.y, 0.0001, -h.z)).y;
	float ridge = max(h.w, 0.0);
	float occlusion = max(-h.w, 0.0);
	
	// material painting
	Material mat = Material(0u, 0u, 0.0);
	
	brush_replace(mat, CLIFF_ID); // initialize with cliff

	float w_moss = smoothstep(1.0, 0.9, height + slope * 0.8);
	brush_add(mat, MOSS_ID, w_moss); // paint moss around grass
	
	float w_grass = smoothstep(1.0, 0.9, height + slope);
	brush_add(mat, GRASS_ID, w_grass); // disincentivize grass growth in high and steep areas
	
	float w_snow = smoothstep(0.98, 1.0, height * 1.2 + ridge * 0.2) * smoothstep(0.6, 0.605, height);
	brush_add(mat, SNOW_ID, w_snow); // incentivize snow in high and ridged areas
	
	// encode control
	uint control = 0u;
	
	control |= (mat.id_0 & 0x1F) << 27; // id 0, bits 28-32
	control |= (mat.id_1 & 0x1F) << 22; // id 1, bits 23-27
	
	uint blend = uint(clamp(mat.blend * 255.0, 0.0, 255.0));
	control |= (blend & 0xFF) << 14; // id 0 -> id 1 blend, bits 15-22
	
	imageStore(control_maps, coords, vec4(uintBitsToFloat(control), 0.0, 0.0, 1.0));
}
