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

// Painting helpers

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
	
	weight = clamp(weight, 0.0, 1.0);
	
	if (id != mat.id_0 && id != mat.id_1) {
		if (mat.blend > 0.5) {
			mat.blend = min(mat.blend + weight, 1.0);
			mat.id_0 = mat.blend > 1.0 - INV_255 ? id : mat.id_0;
		} else {
			mat.blend = max(mat.blend - weight, 0.0);
			mat.id_1 = mat.blend < INV_255 ? id : mat.id_1;
		}
	}
	
	if (mat.id_0 == id) mat.blend = max(mat.blend - weight, 0.0);
	if (mat.id_1 == id) mat.blend = min(mat.blend + weight, 1.0);
	
}

ivec2 imod(ivec2 x, ivec2 s) {
	ivec2 m = min(sign(x), 0);
	return x-s*((x-m)/s+m);
}

vec2 hash21(vec2 p) {
	vec3 p3 = vec3(p, float(parameters.compute_seed));
	p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return -1.0 + 2.0 * fract((p3.xx+p3.yz)*p3.zy);
}

vec2 hash22(vec2 p) {
	vec2 q = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return fract(sin(q)*43758.5453);
}

// gradient noise and derivative by iq https://www.shadertoy.com/view/XdXBRH
vec3 noise(vec2 p) {
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
vec3 ridges(vec2 p, vec2 curl) {
	vec2 p_i = floor(p);
	vec2 p_f = fract(p);
	
	vec3 r = vec3(0.0);
	
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec2 o = vec2(float(i), float(j));
		vec2 d = o - p_f + hash22(p_i + o);
		float dd = max(0.0, 1.0 - dot(d, d));
		//vec3 w = vec3(dd, 4.0 * d) * dd; // C1 quartic interpolant
        vec3 w = vec3(dd, 6.0 * d) * dd * dd; // C2
		
		float phase = dot(d, curl) * TAU;
		float c = cos(phase), s = sin(phase);
		r += vec3(c * w.x, TAU * s * curl * w.x + c * w.yz);
	}
	
	return r;
}


// Returns (height, dHeight_dx, dHeight_dz), and some normalized painting parameters
vec3 height_map(vec2 position, out float erosion_factor) {
    // FBM terrain
	vec3 height = vec3(0.0);
	float height_amplitude = 1500.0;
	float height_frequency = 0.0005;
	
	for (int i = 0; i < 6; i++) {
		vec3 layer = noise(position * height_frequency) * height_amplitude;
		height += layer * vec3(1.0, vec2(height_frequency));
		
		height_amplitude *= 0.4; // gain
		height_frequency *= 1.8; // lacunarity
	}

	// map terrain to [0, amplitude]
	// TODO: use noise in the range [0, 1]
	height.x += 1500.0; 
	
	// FBM erosion
	vec3 erosion = vec3(0.0);
	float erosion_amplitude = 20.0;
	float erosion_frequency = 0.005;
	
	float initial_erosion_amplitude = erosion_amplitude;
	
	for (int i = 0; i < 5; i++) {
		vec2 curl = (height.zy + erosion.zy) * vec2(1.0, -1.0);
		vec3 layer = ridges(position * erosion_frequency, curl) * erosion_amplitude;
		erosion += layer * vec3(1.0, vec2(erosion_frequency));
		
		erosion_amplitude *= 0.5; // gain
		erosion_frequency *= 1.8; // lacunarity
	}
	
	erosion_factor = erosion.x / initial_erosion_amplitude;
	
	return height + erosion;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	
	if (id.x >= parameters.region.z || id.y >= parameters.region.w) return;
	
	ivec2 size = imageSize(gradient_buffers).xy;
	ivec2 texel = parameters.region.xy + id;
	ivec2 wrapped_texel = imod(texel, size);

	vec2 scale = float(1 << parameters.lod) / vec2(parameters.texels_per_vertex);

	float erosion_factor;
	vec3 height = height_map(texel * scale, erosion_factor);

	imageStore(height_buffers, ivec3(wrapped_texel, parameters.lod), vec4(height.x, 0.0, 0.0, 0.0));
	imageStore(gradient_buffers, ivec3(wrapped_texel, parameters.lod), vec4(height.yz, 0.0, 0.0));
	
	/*
	Painting: we use painting helper functions and calculated painting parameters to decide two dominant materials.
	*/

	Material mat = Material(0u, 0u, 0.0);

	// Material IDs: values correspond to Clipmap3DTextureAsset array indices in the Clipmap3D node.
	#define GRASS_ID 0
	#define CLIFF_ID 1
	#define SNOW_ID 2
	#define MOSS_ID 3

	// "Factors" are normalized painting parameters.
	float slope_factor = 1.0 - normalize(vec3(-height.y, 1.0, -height.z)).y;
	float ridge_factor = max(erosion_factor, 0.0);
	float occlusion_factor = max(-erosion_factor, 0.0);

	// Initialize with cliff.
	brush_replace(mat, CLIFF_ID);

	// Paint moss in low and flat areas. Also incentivize occluded areas.
	float moss_weight = 1.6 * (1.0 - smoothstep(0.0, 1350.0, height.x)); // Inverse height factor
	moss_weight += 1.0 * (1.0 - smoothstep(0.2, 0.3, slope_factor)); // Inverse slope factor
	moss_weight += 0.7 * occlusion_factor;
	moss_weight = smoothstep(0.85, 1.0, moss_weight); // Final threshold
	brush_add(mat, MOSS_ID, moss_weight);
	
	// Paint some grass on top of the moss.
	float grass_weight = 1.6 * (1.0 - smoothstep(0.0, 1120.0, height.x)); // Inverse height factor
	grass_weight += 1.0 * (1.0 - smoothstep(0.17, 0.2, slope_factor)); // Inverse slope factor
	grass_weight = smoothstep(0.95, 1.0, grass_weight); // Final threshold
	brush_add(mat, GRASS_ID, grass_weight);
	
	// Paint snow in high, ridged areas.
	float snow_weight = 0.9 * smoothstep(1500.0, 1720.0, height.x);
	snow_weight += 0.4 * ridge_factor;
	snow_weight = smoothstep(0.95, 1.0, snow_weight);
	brush_add(mat, SNOW_ID, snow_weight);
	
	/*
	Control encoding: The two dominant material IDs and a blending float are written into the control buffer, and later parsed by the fragment function.
	*/
	
	uint control = 0u;
	
	control |= (mat.id_0 & 0x1F) << 27; // id 0, bits 28-32
	control |= (mat.id_1 & 0x1F) << 22; // id 1, bits 23-27
	
	uint blend = uint(clamp(mat.blend * 255.0, 0.0, 255.0));
	control |= (blend & 0xFF) << 14; // id 0 -> id 1 blend, bits 15-22
	
	imageStore(control_buffers, ivec3(wrapped_texel, parameters.lod), vec4(uintBitsToFloat(control), 0.0, 0.0, 1.0));
}
