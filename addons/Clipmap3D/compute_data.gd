@tool
class_name Clipmap3DComputeData extends Resource

@export var compute_shader: RDShaderFile:
	set(value):
		compute_shader = value
		emit_changed()

## The random number seed passed to the compute shader.
@export var compute_seed: int = 0:
	set(value):
		compute_seed = value
		emit_changed()

@export var texels_per_vertex := Vector2i.ONE:
	set(value):
		texels_per_vertex = value.maxi(1)
		emit_changed()

@export var max_height: float = 10000.0:
	set(value):
		max_height = value
		emit_changed()
