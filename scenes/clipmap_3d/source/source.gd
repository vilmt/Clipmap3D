@tool
@abstract
class_name Clipmap3DSource extends Resource

@export var world_offset := Vector2.ZERO

@warning_ignore_start("unused_signal")
signal parameters_changed
signal world_origin_changed(new_origin: Vector2)
signal amplitude_changed(new_amplitude: float)
signal texture_arrays_created
signal texture_arrays_changed
signal maps_created
signal maps_redrawn

@abstract
func create_maps(world_origin: Vector2, size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void

@abstract
func shift_maps(world_origin: Vector2) -> void

@abstract
func has_maps() -> bool

@abstract
func get_map_rids() -> Array[RID]

@abstract
func get_height_world(world_xz: Vector2) -> float

@abstract
func get_height_amplitude() -> float
