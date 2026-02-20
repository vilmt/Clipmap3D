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

// height, partial derivatives
vec3 height_map(vec2 p) {
	float scale = 0.005; // master scale value
	
	float h = sin(p.x * scale) * sin(p.y * scale) * 0.5 + 0.5;
	
	float dhdx = sin(p.y * scale) * cos(p.x * scale) * scale * 0.5;
	float dhdy = sin(p.x * scale) * cos(p.y * scale) * scale * 0.5;
	
	return vec3(h, dhdx, dhdy);
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

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	
	if (any(greaterThanEqual(local, params.region.zw))) {
		return; // skip if texel is outside requested region
	}
	
	ivec2 size = imageSize(height_maps).xy;
	ivec2 texel = local + params.region.xy + params.origin - (size / 2 - params.texels_per_vertex); // half size
	vec2 scale = params.vertex_spacing * float(1 << params.lod) / vec2(params.texels_per_vertex);
	
	vec3 h = height_map(vec2(texel) * scale);
	
	ivec3 coords = ivec3(imod(texel.xy, size), params.lod); // toroidal wrapping
	
	imageStore(height_maps, coords, vec4(h.x * params.height_amplitude, 0.0, 0.0, 0.0));
	imageStore(gradient_maps, coords, vec4(h.yz * params.height_amplitude, 0.0, 0.0)); // gradient maps expect world-space texel spacing
	
	// arbitrary parameters for painting (independent of world scaling)
	float height = h.x;
	float slope = 1.0 - normalize(vec3(-h.y, 0.0001, -h.z)).y;
	
	// material painting
	Material mat = Material(0u, 0u, 0.0);
	
	// should match Clipmap3DTextureAsset array indices in source
	#define GRASS_ID 0
	#define CLIFF_ID 1
	#define SNOW_ID 2
	#define MOSS_ID 3
	
	brush_replace(mat, CLIFF_ID); // initialize with cliff
	
	float w_grass = smoothstep(1.0, 0.9, height + slope);
	brush_add(mat, GRASS_ID, w_grass);
	
	// encode control
	uint control = 0u;
	
	control |= (mat.id_0 & 0x1F) << 27; // id 0, bits 28-32
	control |= (mat.id_1 & 0x1F) << 22; // id 1, bits 23-27
	
	uint blend = uint(clamp(mat.blend * 255.0, 0.0, 255.0));
	control |= (blend & 0xFF) << 14; // id 0 -> id 1 blend, bits 15-22
	
	imageStore(control_maps, coords, vec4(uintBitsToFloat(control), 0.0, 0.0, 1.0));
}
