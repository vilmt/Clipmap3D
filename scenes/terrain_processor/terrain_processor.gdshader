shader_type canvas_item;
#include "res://materials/noise_3d.gdshaderinc"

uniform int mode: hint_enum("Height", "Normal", "Cycle") = 0;

uniform float amplitude: hint_range(0, 1000) = 25;

uniform vec2 offset = vec2(0.0);
uniform vec2 frequency = vec2(1.0);

//uniform sampler2D noise_texture: hint_default_white, filter_linear;
//uniform float noise_lod = 0.0;

void fragment() {
	int current_mode = mode;
	if (mode == 2) {
		current_mode = int(TIME) % 2;
	}

	vec3 p = vec3((UV + offset) * frequency, 0.0);

	float height = perlin(0, p);

	//float falloff = max(1.0 - length(UV - 0.5) * 2.0, 0.0);
	//float noise = textureLod(noise_texture, UV, noise_lod).r;
//
	//vec2 texel = 1.0 / vec2(textureSize(noise_texture, 0));
//
	//float left = textureLod(noise_texture, UV - vec2(texel.x, 0.0), noise_lod).r;
	//float right = textureLod(noise_texture, UV + vec2(texel.x, 0.0), noise_lod).r;
	//float down = textureLod(noise_texture, UV - vec2(0.0, texel.y), noise_lod).r;
	//float up = textureLod(noise_texture, UV + vec2(0.0, texel.y), noise_lod).r;
//
	//left *= amplitude;
	//right *= amplitude;
	//down *= amplitude;
	//up *= amplitude;
//
	//vec3 normal = normalize(vec3(left - right, 1.0, down - up));
	//normal = normal * 0.5 + 0.5;

	switch (current_mode) {
		case 0:
			COLOR = vec4(vec3(height), 1.0);
			break;
		case 1:
			COLOR = vec4(vec3(0.0), 1.0);
			break;
	};
}