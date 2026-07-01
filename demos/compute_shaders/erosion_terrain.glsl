#[compute]
#version 460

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_buffers;
layout(rg16f, binding = 1) restrict uniform image2DArray gradient_buffers;
layout(r32f, binding = 2) restrict uniform image2DArray control_buffers;

layout(push_constant, std430) uniform Parameters {
	ivec4 region;
	ivec2 texels_per_vertex;
	int lod;
	uint compute_seed;
	vec2 vertex_spacing;
} parameters;

#define EPSILON 1e-6
#define INV_255 0.003921568627450
#define TAU 6.28318530717958

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
	
	if (mat.id_0 == id) mat.blend = max(mat.blend - strength, 0.0);
	if (mat.id_1 == id) mat.blend = min(mat.blend + strength, 1.0);
	
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


// (height, dHeight_dx, dHeight_dy)
vec3 height_map(vec2 position, out float erosion_factor) {
	const float scale = 0.0005; // master scale value
	
    // FBM terrain
	vec3 height = vec3(0.0);
	float height_amplitude = 1500.0;
	float height_frequency = 1.0 * scale;
	
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
	float erosion_amplitude = 10.0;
	float erosion_frequency = 10.0 * scale;
	
	float initial_erosion_amplitude = erosion_amplitude;
	
	for (int i = 0; i < 4; i++) {
		vec2 curl = (height.zy + erosion.zy) * vec2(1.0, -1.0); // scale-invariant curl
		vec3 layer = ridges(position * erosion_frequency, curl) * erosion_amplitude;
		erosion += layer * vec3(1.0, vec2(erosion_frequency));
		
		erosion_amplitude *= 0.5;
		erosion_frequency *= 1.8;
	}
	
	erosion_factor = erosion.x / initial_erosion_amplitude;
	
	return height + erosion;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	
	if (id.x >= parameters.region.z || id.y >= parameters.region.w) return; // Skip if invocation ID is greater than region size
	
	ivec2 size = imageSize(gradient_buffers).xy;
	ivec2 texel = id + parameters.region.xy - (size / 2 - parameters.texels_per_vertex); // half size
	ivec2 wrapped_texel = imod(texel, size);

	vec2 scale = parameters.vertex_spacing * float(1 << parameters.lod) / vec2(parameters.texels_per_vertex);
	
	float erosion_factor;
	vec3 height = height_map(texel * scale, erosion_factor);

	imageStore(height_buffers, ivec3(wrapped_texel, parameters.lod), vec4(height.x, 0.0, 0.0, 0.0));
	imageStore(gradient_buffers, ivec3(wrapped_texel, parameters.lod), vec4(height.yz, 0.0, 0.0));

	// Indices correspond to texture asset ordering
	#define GRASS_ID 0
	#define CLIFF_ID 1
	#define SNOW_ID 2
	#define MOSS_ID 3
	
	// arbitrary parameters for painting (independent of world scaling)
	float height_factor = height.x;
	float slope_factor = 1.0 - normalize(vec3(-height.y, 0.0001, -height.z)).y;
	float ridge_factor = max(erosion_factor, 0.0);
	
	// material painting
	Material mat = Material(0u, 0u, 0.0);
	
	brush_replace(mat, CLIFF_ID); // initialize with cliff

	float moss_weight = smoothstep(1.0, 0.9, height_factor + slope_factor * 0.8);
	brush_add(mat, MOSS_ID, moss_weight); // paint moss around grass
	
	float grass_weight = smoothstep(1.0, 0.9, height_factor + slope_factor);
	brush_add(mat, GRASS_ID, grass_weight); // disincentivize grass growth in high and steep areas
	
	float snow_weight = smoothstep(0.98, 1.0, height_factor * 1.2 + ridge_factor * 0.2) * smoothstep(0.6, 0.605, height_factor);
	brush_add(mat, SNOW_ID, snow_weight); // incentivize snow in high and ridged areas
	
	// encode control
	uint control = 0u;
	
	control |= (mat.id_0 & 0x1F) << 27; // id 0, bits 28-32
	control |= (mat.id_1 & 0x1F) << 22; // id 1, bits 23-27
	
	uint blend = uint(clamp(mat.blend * 255.0, 0.0, 255.0));
	control |= (blend & 0xFF) << 14; // id 0 -> id 1 blend, bits 15-22
	
	imageStore(control_buffers, ivec3(wrapped_texel, parameters.lod), vec4(uintBitsToFloat(control), 0.0, 0.0, 1.0));
}
