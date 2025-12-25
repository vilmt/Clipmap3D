shader_type canvas_item;
//#include "res://materials/noise_3d2.gdshaderinc"

uniform int mode: hint_enum("Height", "Normal", "Cycle") = 0;

uniform float amplitude: hint_range(0, 1000) = 25.0;

uniform highp sampler2D noise_texture: hint_default_white, filter_linear;

void fragment() {
	int current_mode = mode;
	if (mode == 2) {
		current_mode = int(TIME) % 2;
	}

	float height = texture(noise_texture, UV).r;

	vec2 texel = 1.0 / vec2(textureSize(noise_texture, 0));

	float left = texture(noise_texture, UV - vec2(texel.x, 0.0)).r;
	float right = texture(noise_texture, UV + vec2(texel.x, 0.0)).r;
	float down = texture(noise_texture, UV - vec2(0.0, texel.y)).r;
	float up = texture(noise_texture, UV + vec2(0.0, texel.y)).r;

	vec3 normal = normalize(vec3(left - right, 1.0 / max(amplitude, 0.0001), down - up));
	normal = normal * 0.5 + 0.5;

	switch (current_mode) {
		case 0:
			COLOR = vec4(vec3(height), 1.0);
			break;
		case 1:
			COLOR = vec4(normal, 1.0);
			break;
	};
}