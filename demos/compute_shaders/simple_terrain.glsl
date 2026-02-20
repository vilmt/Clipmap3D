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
#define TAU 6.28318530717958

ivec2 imod(ivec2 x, ivec2 s) {
	ivec2 m = min(sign(x), 0);
	return x-s*((x-m)/s+m);
}

float hash1(float n) {
	return fract( n*17.0*fract( n*0.3183099 ) );
}

float noise(vec2 x2) {
	vec3 x = vec3(x2, float(params.seed));
	
    vec3 p = floor(x);
    vec3 w = fract(x);
    
    vec3 u = w*w*w*(w*(w*6.0-15.0)+10.0);

    float n = p.x + 317.0*p.y + 157.0*p.z;
    
    float a = hash1(n+0.0);
    float b = hash1(n+1.0);
    float c = hash1(n+317.0);
    float d = hash1(n+318.0);
    float e = hash1(n+157.0);
	float f = hash1(n+158.0);
    float g = hash1(n+474.0);
    float h = hash1(n+475.0);

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return (k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z);
}


// height
float height_map(vec2 p) {
	p = p + 10000.0; // offset to avoid noise artifacts at 0, 0
	float scale = 0.0012; // master scale value
	
    // FBM terrain
	float h = 0.0;
	float h_a = 0.5; // base amplitude (use height_amplitude instead)
	float h_f = 1.0 * scale; // frequency
	
	for (int i = 0; i < 8; i++) {
		h += noise(p * h_f) * h_a;
		
		h_a *= 0.50; // gain
		h_f *= 1.7; // lacunarity
	}
	
	return h;
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
	strength = clamp(strength, 0.0, 1.0);

	if (mat.id_1 == id) {
		mat.blend = min(mat.blend + strength, 1.0);
		return;
	}

	if (mat.id_0 == id) {
		mat.blend = max(mat.blend - strength, 0.0);
		return;
	}

	if (mat.blend < 1.0 / 255.0) {
		mat.id_1 = id;
		mat.blend = strength;
	} else if (mat.blend > 1.0 - 1.0 / 255.0) {
		mat.id_0 = mat.id_1;
		mat.id_1 = id;
		mat.blend = strength;
	}
}

// should match asset array order in Clipmap3DSource
#define GRASS_ID 0
#define CLIFF_ID 1
#define SNOW_ID 2

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	
	if (any(greaterThanEqual(local, params.region.zw))) {
		return; // skip if texel is outside requested region
	}
	
	ivec2 size = imageSize(height_maps).xy;
	ivec2 texel = local + params.region.xy + params.origin - (size / 2 - params.texels_per_vertex); // half size
	vec2 scale = params.vertex_spacing * float(1 << params.lod) / vec2(params.texels_per_vertex);
	
	vec2 uv = texel * scale;
	
	float h = height_map(uv);
	
	float h_px = height_map(uv + vec2(scale.x, 0.0));
	float h_nx = height_map(uv - vec2(scale.x, 0.0));
	float h_py = height_map(uv + vec2(0.0, scale.y));
	float h_ny = height_map(uv - vec2(0.0, scale.y));
	
	vec2 gradient = {
		(h_px - h_nx) * (0.5 / scale.x),
		(h_py - h_ny) * (0.5 / scale.y)
	};
	
	ivec3 coords = ivec3(imod(texel.xy, size), params.lod); // toroidal wrapping
	
	imageStore(height_maps, coords, vec4(h * params.height_amplitude, 0.0, 0.0, 0.0));
	imageStore(gradient_maps, coords, vec4(gradient * params.height_amplitude, 0.0, 0.0)); // gradient maps expect world-space texel spacing
	
	// material parameters
	float height = h;
	float slope = 1.0 - normalize(vec3(-gradient.x, 0.0001, -gradient.y)).y;
	
	// material mixing
	Material mat = Material(0u, 0u, 0.0);
	
	brush_replace(mat, CLIFF_ID); // initialize with cliff
	
	float w_grass = smoothstep(1.0, 0.9, height + slope * 0.8) * smoothstep(0.605, 0.6, height);
	brush_add(mat, GRASS_ID, w_grass); // disincentivize grass growth in high and steep areas
	
	float w_snow = smoothstep(0.6, 0.605, height) * smoothstep(0.8, 0.78, slope);
	brush_add(mat, SNOW_ID, w_snow); // paint peaks with snow
	
	// encode control
	uint control = 0u;
	
	control |= (mat.id_0 & 0x1F) << 27; // id 0, bits 28-32
	control |= (mat.id_1 & 0x1F) << 22; // id 1, bits 23-27
	
	uint blend = uint(clamp(mat.blend * 255.0, 0.0, 255.0));
	control |= (blend & 0xFF) << 14; // id 0 -> id 1 blend, bits 15-22
	
	imageStore(control_maps, coords, vec4(uintBitsToFloat(control), 0.0, 0.0, 1.0));
}
