#[compute]
#version 460

#include "FastNoiseLite.glsl.inc"

struct NoiseParams {
	int enabled;
	int ridged;
	int seed;
	float amplitude;
	float frequency;
	vec2 offset;
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

layout(std430, binding = 3) restrict buffer NoiseBuffer {
	NoiseParams noises[8];
};

layout(push_constant, std430) uniform Params {
	vec2 world_origin;
	vec2 vertex_spacing;
} params;

const float EPSILON = 10e-6;

void main() {
	ivec3 texel = ivec3(gl_GlobalInvocationID);
	ivec3 size = imageSize(height_maps);
	
	if (any(greaterThanEqual(texel, size))) {
		return;
	}
	
	// terrain should look the same when changing vertex spacing
	// e.g. 1.0 -> 0.5 spacing.x, double sampling density on x
	
	vec2 scale = params.vertex_spacing * float(1 << texel.z);
	vec2 inv_scale = 1.0 / scale;
	
	vec2 world_xz = vec2(texel.xy - size.xy / 2); // step size increases with lod
	vec2 origin = floor(params.world_origin * inv_scale + EPSILON);
	
	vec2 noise_texel = (world_xz + origin) * scale;
	vec2 noise_step = scale;

    fnl_state noise = fnlCreateState(1337);
    noise.noise_type = FNL_NOISE_OPENSIMPLEX2;
	noise.frequency = 0.003;
	
	float h = fnlGetNoise2D(noise, noise_texel.x, noise_texel.y) * noises[0].amplitude;
	float r = fnlGetNoise2D(noise, noise_texel.x + noise_step.x, noise_texel.y) * noises[0].amplitude;
	float u = fnlGetNoise2D(noise, noise_texel.x, noise_texel.y + noise_step.y) * noises[0].amplitude;
	
    imageStore(height_maps, texel, vec4(h, 0.0, 0.0, 0.0));
	imageStore(normal_maps, texel, vec4(h - r, h - u, 0.0, 0.0));
	imageStore(control_maps, texel, vec4(0.0, 0.0, 0.0, 0.0));
}