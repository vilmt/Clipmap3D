shader_type canvas_item;
#include "fast_noise_lite.gdshaderinc"

uniform float f = 1.0;

void fragment() {

	fnl_state noise = fnlCreateState(0);
	noise.noise_type = FNL_NOISE_PERLIN;
	//noise.frequency = f;

	vec2 uv = UV * 1000.0;
	COLOR = vec4(vec3(fnlGetNoise2D(noise, uv.x, uv.y)), 1.0);
}