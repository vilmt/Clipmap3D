#[compute]
#version 460

/*
TODO:

- Floating-point origin shifting
- Integer-based hashes (will fix seams due to precision issues)
- More painting helpers (maybe use a shader include)
- Color map? Could create new buffers or write to control.
- A simple perlin noise parameter for painting

*/

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_buffers;
layout(rg16f, binding = 1) restrict uniform image2DArray gradient_buffers;
layout(r32f, binding = 2) restrict uniform image2DArray control_buffers;

layout(push_constant, std430) uniform Parameters {
	ivec4 region;
	ivec2 texels_per_vertex;
	int lod;
	uint compute_seed;
} parameters;

#define INV_255 0.003921568627450
#define TAU 6.28318530717958

// Math helpers

// Stable integer floor division and modulo by vilmt
ivec4 div_mod(ivec2 x, ivec2 y) {
    uvec2 x_u = uvec2(x), x_s = x_u >> 31;
    uvec2 y_u = uvec2(y), y_s = y_u >> 31;
    
    uvec2 x_a = (x_u ^ -x_s) + x_s;
    uvec2 y_a = (y_u ^ -y_s) + y_s;
    
    uvec2 q = x_a / y_a, q_s = x_s ^ y_s;
    q += q_s & uvec2(notEqual(x_a, y_a * q));
    q = (q ^ -q_s) + q_s;
    
    return ivec4(q, x - y * ivec2(q));
}

// Painting helpers. TODO: optimize, add more.

struct Material {
	uint id_0;
	uint id_1;
	float blend;
};

void brush_replace(inout Material mat, uint id) {
	mat.id_0 = id;
	mat.id_1 = id;
	mat.blend = 0.0;
}

void brush_add(inout Material mat, uint id, float weight) {
	if (weight < 1e-6) return;
	
	//weight = clamp(weight, 0.0, 1.0);
	
	if (id != mat.id_0 && id != mat.id_1) {
		if (mat.blend > 0.5) {
			mat.blend = min(mat.blend + weight, 1.0);
			mat.id_0 = mat.blend > 1.0 - 1.0 / 255.0 ? id : mat.id_0;
		} else {
			mat.blend = max(mat.blend - weight, 0.0);
			mat.id_1 = mat.blend < 1.0 / 255.0 ? id : mat.id_1;
		}
	}
	
	if (mat.id_0 == id) mat.blend = max(mat.blend - weight, 0.0);
	if (mat.id_1 == id) mat.blend = min(mat.blend + weight, 1.0);
	
}

// Hash and noise functions

// pcg3d hash (0, 1): https://www.jcgt.org/published/0009/03/02/
vec2 hash(ivec2 p_i, uint seed) {
    uvec3 v = uvec3(uvec2(p_i), seed);

    v = v * 1664525u + 1013904223u;

    v.x += v.y*v.z;
    v.y += v.z*v.x;
    v.z += v.x*v.y;

    v ^= v >> 16u;

    v.x += v.y*v.z;
    v.y += v.z*v.x;
    v.z += v.x*v.y;
    
    return vec2(v.xy) / 4294967296.0;
}

// Gradient noise and derivative by iq: https://www.shadertoy.com/view/XdXBRH
vec3 noise(ivec2 position, ivec2 wavelength, float amplitude) {
    ivec4 division_result = div_mod(position, wavelength * parameters.texels_per_vertex);
	vec2 frequency = 1.0 / vec2(wavelength);
    ivec2 p_i = division_result.xy;
    vec2 p_f = vec2(division_result.zw) * frequency / vec2(parameters.texels_per_vertex);
        
    vec2 u = p_f * p_f * p_f * (p_f * (p_f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * p_f * p_f * (p_f * (p_f - 2.0) + 1.0);
    
    vec2 ga = 2.0 * hash(p_i + ivec2(0, 0), parameters.compute_seed) - 1.0;
    vec2 gb = 2.0 * hash(p_i + ivec2(1, 0), parameters.compute_seed) - 1.0;
    vec2 gc = 2.0 * hash(p_i + ivec2(0, 1), parameters.compute_seed) - 1.0;
    vec2 gd = 2.0 * hash(p_i + ivec2(1, 1), parameters.compute_seed) - 1.0;
    
    float va = dot(ga, p_f - vec2(0.0, 0.0));
    float vb = dot(gb, p_f - vec2(1.0, 0.0));
    float vc = dot(gc, p_f - vec2(0.0, 1.0));
    float vd = dot(gd, p_f - vec2(1.0, 1.0));
    
    vec3 layer = vec3(
        va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd),
        ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd) +
        du * (u.yx * (va - vb - vc + vd) + vec2(vb, vc) - va)
    );
    
    return layer * amplitude * vec3(1.0, frequency);
}

// Erosion ridges and derivatives by vilmt
vec3 ridges(ivec2 position, ivec2 wavelength, float amplitude, vec3 height) {
    ivec4 division_result = div_mod(position, wavelength * parameters.texels_per_vertex);
    vec2 frequency = 1.0 / vec2(wavelength);
    ivec2 p_i = division_result.xy;
    vec2 p_f = vec2(division_result.zw) * frequency / vec2(parameters.texels_per_vertex);

	vec2 curl = vec2(height.z, -height.y);
    
	vec3 layer = vec3(0.0);
	
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		ivec2 offset = ivec2(i, j);
		vec2 random = vec2(offset) - p_f + hash(p_i + offset, parameters.compute_seed);
		
        float x = 1.0 - dot(random, random);
        vec3 weight = vec3(x, 4.0 * random) * max(0.0, x);
        
        float phase = TAU * dot(random, curl);
        
        layer += cos(phase) * weight;
        layer.yz += TAU * sin(phase) * weight.x * curl;
	}
    
	return layer * amplitude * vec3(1.0, frequency);
}

// Height and derivatives
vec3 height_map(ivec2 position, out float erosion_factor) {
	vec3 height = vec3(1500.0, 0.0, 0.0);
    
	position += 100000; // Remove obvious pattern from 0, 0

    height += noise(position, ivec2(2000), 1500.0);
    height += noise(position, ivec2(1200), 750.0);
    height += noise(position, ivec2(700), 325.0);
    height += noise(position, ivec2(400), 112.0);
    height += noise(position, ivec2(240), 56.0);
	height += noise(position, ivec2(130), 30.0);
	height += noise(position, ivec2(70), 15.0);
	height += noise(position, ivec2(40), 7.0);

	vec3 erosion = vec3(0.0, 0.0, 0.0);
	
	erosion += ridges(position, ivec2(100), 5.0, height + erosion);
    erosion += ridges(position, ivec2(50), 2.5, height + erosion);
    erosion += ridges(position, ivec2(25), 1.2, height + erosion);
	erosion += ridges(position, ivec2(13), 0.6, height + erosion);

	erosion_factor = erosion.x;
	
	return height + erosion;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	
	if (id.x >= parameters.region.z || id.y >= parameters.region.w)
		return;
	
	ivec2 position = parameters.region.xy + id;

	ivec2 wrap_size = imageSize(gradient_buffers).xy;
	ivec3 texel = ivec3(div_mod(position, wrap_size).zw, parameters.lod);

	position <<= parameters.lod;

	float erosion_factor;
	vec3 height = height_map(position, erosion_factor);

	imageStore(height_buffers, texel, vec4(height.x, 0.0, 0.0, 0.0));
	imageStore(gradient_buffers, texel, vec4(height.yz, 0.0, 0.0));
	
	/*
	Painting: we use painting helper functions and calculated painting parameters to decide two dominant materials.
	*/

	Material mat = Material(0u, 0u, 0.0);

	// Material IDs: values correspond to Clipmap3DTextureAsset array indices in the Clipmap3D node.
	#define GRASS_ID 0
	#define CLIFF_ID 1
	#define SNOW_ID 2
	#define MOSS_ID 3

	// Arbitrary painting parameters
	float slope_factor = 1.0 - normalize(vec3(-height.y, 1.0, -height.z)).y;
	float ridge_factor = max(erosion_factor, 0.0);
	float occlusion_factor = max(-erosion_factor, 0.0);

	float random_factor1 = noise(position, ivec2(500), 1.0).x;
	float random_factor2 = noise(position, ivec2(100), 1.0).x;

	// Initialize with cliff.
	brush_replace(mat, CLIFF_ID);

	// Paint moss in low and flat areas. Also incentivize occluded areas.
	float moss_weight = 1.6 * (1.0 - smoothstep(0.0, 1350.0, height.x)); // Inverse height factor
	moss_weight += 1.0 * (1.0 - smoothstep(0.2, 0.3, slope_factor)); // Inverse slope factor
	moss_weight += 0.7 * smoothstep(3.0, 7.0, occlusion_factor);
	moss_weight = smoothstep(0.85, 1.0, moss_weight); // Final threshold
	brush_add(mat, MOSS_ID, moss_weight);
	
	// Paint some grass on top of the moss.
	float grass_weight = 1.6 * (1.0 - smoothstep(0.0, 1120.0, height.x)); // Inverse height factor
	grass_weight += 1.0 * (1.0 - smoothstep(0.17, 0.2, slope_factor)); // Inverse slope factor
	grass_weight = smoothstep(0.95, 1.0, grass_weight); // Final threshold
	brush_add(mat, GRASS_ID, grass_weight);
	
	// Paint snow in high, ridged areas.
	float height_mask1 = smoothstep(1800.0, 1920.0, height.x + random_factor1 * 500.0);
	float height_mask2 = smoothstep(2100, 2200, height.x + random_factor2 * 200.0);
	float snow_weight = 0.7 * height_mask1;
	snow_weight += 0.5 * height_mask2;
	snow_weight += smoothstep(2.0, 5.0, ridge_factor) * height_mask1;
	snow_weight = smoothstep(0.8, 1.0, snow_weight);
	
	brush_add(mat, SNOW_ID, snow_weight);

	//bool hole = bool(length(texel * scale) < 20.0);
	
	/*
	Control encoding: The two dominant material IDs and a blending float are written into the control buffer, and later parsed by the fragment function.
	*/
	
	uint control = 0u;
	
	control |= (mat.id_0 & 0x1Fu) << 27u; // id 0, bits 28-32
	control |= (mat.id_1 & 0x1Fu) << 22u; // id 1, bits 23-27

	uint blend = uint(clamp(mat.blend * 255.0, 0.0, 255.0));
	control |= (blend & 0xFFu) << 14u; // id 0 -> id 1 blend, bits 15-22

	//control |= (uint(hole) & 0x1u) << 13u;
	
	imageStore(control_buffers, texel, vec4(uintBitsToFloat(control), 0.0, 0.0, 1.0));
}
