@tool
class_name Clipmap3DComputeData extends Resource

const COMPUTE_SEED_DEFAULT: int = 0
const TEXELS_PER_VERTEX_DEFAULT := Vector2i.ONE

@export var compute_shader: RDShaderFile:
	set(value):
		compute_shader = value
		emit_changed()

## The random number seed passed to the compute shader.
@export var compute_seed := COMPUTE_SEED_DEFAULT:
	set(value):
		compute_seed = value
		emit_changed()

@export var texels_per_vertex := TEXELS_PER_VERTEX_DEFAULT:
	set(value):
		texels_per_vertex = value.maxi(1)
		emit_changed()
