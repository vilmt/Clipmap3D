#[compute]
#version 460

#include "FastNoiseLite.glsl.inc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_maps;
layout(rg16f, binding = 1) restrict uniform image2DArray normal_maps;
layout(r32f, binding = 2) restrict uniform image2DArray control_maps;

layout(push_constant, std430) uniform Params {
	vec2 world_origin;
	vec2 vertex_spacing;
	
	int lod;
	int noise_seed;
	float pad1;
	float pad2;

} params;

const float EPSILON = 1e-6;

vec3 sample_h_and_grad(fnl_state n, vec2 uv, vec2 s) {
	vec3 r = vec3(
		fnlGetNoise2D(n, uv.x, uv.y),
		fnlGetNoise2D(n, uv.x + s.x, uv.y),
		fnlGetNoise2D(n, uv.x, uv.y + s.y)
	) * 0.5 + 0.5;
	
	return vec3(r.x, r.x - r.y, r.x - r.z);
}

void main() {
	ivec3 global_id = ivec3(gl_GlobalInvocationID);
	global_id.z += params.lod;
	ivec3 bounds = imageSize(height_maps);
	
	if (any(greaterThanEqual(global_id, bounds))) {
		return;
	}
	
	ivec2 texel = global_id.xy;
	//int lod = global_id.z;
	int lod = params.lod;
	ivec2 size = bounds.xy;
	
	vec2 scale = params.vertex_spacing * float(1 << lod);
	vec2 inv_scale = 1.0 / scale;
	
	vec2 centered = vec2(texel - size / 2);
	vec2 origin = floor(params.world_origin * inv_scale + EPSILON);
	vec2 uv = (centered + origin) * scale;
	
	vec3 samples = vec3(0.0);

	fnl_state continental = fnlCreateState(params.noise_seed + 777);
	continental.noise_type = FNL_NOISE_OPENSIMPLEX2;
	continental.frequency = 0.001;
	continental.fractal_type = FNL_FRACTAL_FBM;
	continental.octaves = 5;
	
	samples += sample_h_and_grad(continental, uv + vec2(150.0, 0.0), scale) * 800.0;

    imageStore(height_maps, global_id, vec4(samples.x, 0.0, 0.0, 0.0));
	imageStore(normal_maps, global_id, vec4(samples.yz, 0.0, 0.0));
	imageStore(control_maps, global_id, vec4(0.0, 0.0, 0.0, 0.0));
}
