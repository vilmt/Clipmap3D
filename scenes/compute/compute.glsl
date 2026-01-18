#[compute]
#version 460

#include "FastNoiseLite.glsl.inc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_maps;
layout(rg16_snorm, binding = 1) restrict uniform image2DArray normal_maps;
layout(r32ui, binding = 2) restrict uniform uimage2DArray control_maps;

void main() {
	ivec3 texel = ivec3(gl_GlobalInvocationID);
	ivec3 size = imageSize(height_maps);
	
	if (any(greaterThanEqual(texel, size))) {
		return;
	}

    fnl_state noise = fnlCreateState(1337);
    noise.noise_type = FNL_NOISE_OPENSIMPLEX2;
	noise.frequency = float(texel.z * 0.01 + 0.01);
   
	float h = fnlGetNoise2D(noise, float(texel.x), float(texel.y));
	//float h = float(texel.x % 2 == 0);
    imageStore(height_maps, texel, vec4(h, 0.0, 0.0, 0.0));
	
	imageStore(normal_maps, texel, vec4(0.5, 1.0, 0.0, 0.0));
	imageStore(control_maps, texel, uvec4(5u, 0, 0, 0));
}