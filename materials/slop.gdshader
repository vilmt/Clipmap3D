shader_type canvas_item;
#include "noise_3d.gdshaderinc"

void fragment() {
	float noise = perlin(0, vec3(UV * 10.0 + TIME, 0.0));
	COLOR = vec4(vec3(noise), 1.0);
}