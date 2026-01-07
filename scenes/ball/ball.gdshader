shader_type spatial;

uniform vec3 ant_color: source_color = vec3(1.0);
uniform vec3 background_color: source_color = vec3(0.0);

uniform float ants = 20.0;
uniform float ratio = 0.8;
uniform float velocity = 1.0;

void fragment() {
	float signal = sin((UV.x * ants + TIME * velocity + UV.y) * TAU) * 0.5 + 0.5;
	float mask = 1.0 - smoothstep(0.0, fwidth(signal), signal - ratio);
	ALBEDO = mix(background_color, ant_color, mask);
}