#[compute]
#version 460

#include "FastNoiseLite.glsl.inc"

struct NoiseParams {
	int noise_type;
	int seed;
	float amplitude;
	float frequency;
	
	vec2 offset;
	int absolute;
	int fractal_type;
	
	int octaves;
	float lacunarity;
	float gain;
	float weighted_strength;
	
	float ping_pong_strength;
	int _pad0;
	int _pad1;
	int _pad2;
};

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_maps;
layout(rg16f, binding = 1) restrict uniform image2DArray normal_maps;
layout(r32f, binding = 2) restrict uniform image2DArray control_maps;

layout(std430, binding = 3) buffer NoiseBuffer {
	NoiseParams noise_params[];
};

layout(push_constant, std430) uniform Params {
	vec2 world_origin;
	vec2 vertex_spacing;
	
	int noise_count;
	int lod;
	float pad1;
	float pad2;

} params;

const float EPSILON = 1e-6;

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
	
	vec2 noise_uv = (centered + origin) * scale;
	vec2 normal_step = scale;
	
	float h = 0.0;
	float r = 0.0;
	float u = 0.0;
	
	for (int i = 0; i < params.noise_count; i++) {
		fnl_state n = fnlCreateState(noise_params[i].seed);
		n.noise_type = noise_params[i].noise_type;
		n.frequency = noise_params[i].frequency * 0.01;
		n.fractal_type = noise_params[i].fractal_type;
		n.octaves = noise_params[i].octaves;
		n.lacunarity = noise_params[i].lacunarity;
		n.gain = noise_params[i].gain;
		n.weighted_strength = noise_params[i].weighted_strength;
		n.ping_pong_strength = noise_params[i].ping_pong_strength;
		
		float x = noise_uv.x + noise_params[i].offset.x;
		float y = noise_uv.y + noise_params[i].offset.y;
		
		float h0 = fnlGetNoise2D(n, x, y);
		h0 = noise_params[i].absolute == 1 ? abs(h0) : h0 * 0.5 + 0.5;
		h0 *= noise_params[i].amplitude;
		
		float r0 = fnlGetNoise2D(n, x + normal_step.x, y);
		r0 = noise_params[i].absolute == 1 ? abs(r0) : r0 * 0.5 + 0.5;
		r0 *= noise_params[i].amplitude;
		
		float u0 = fnlGetNoise2D(n, x, y + normal_step.y);
		u0 = noise_params[i].absolute == 1 ? abs(u0) : u0 * 0.5 + 0.5;
		u0 *= noise_params[i].amplitude;
		
		h += h0;
		r += r0;
		u += u0;
	}
	
    imageStore(height_maps, global_id, vec4(h, 0.0, 0.0, 0.0));
	imageStore(normal_maps, global_id, vec4(h - r, h - u, 0.0, 0.0));
	imageStore(control_maps, global_id, vec4(0.0, 0.0, 0.0, 0.0));
}
