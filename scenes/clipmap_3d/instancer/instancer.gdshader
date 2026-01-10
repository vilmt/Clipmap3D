shader_type particles;

uniform ivec2 rows_and_columns;
uniform vec2 instance_spacing;

void start() {
	int row = int(INDEX) % rows_and_columns.x;
	int column = (int(INDEX) - row) / rows_and_columns.x;
	vec3 offset = vec3(float(column), 0.0, float(row));
	offset.xz *= instance_spacing;
	
	TRANSFORM[3].xyz = offset;
}

void process() {
	// Called for every pixel the material is visible on.
}