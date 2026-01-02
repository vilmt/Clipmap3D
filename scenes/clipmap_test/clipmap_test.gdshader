shader_type spatial;

//render_mode wireframe;

varying vec3 debug_albedo;

void vertex() {
	debug_albedo.rg = VERTEX.xz / 64.0;
}

void fragment() {
	ALBEDO = debug_albedo;
}