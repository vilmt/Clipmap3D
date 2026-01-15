@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO: threading
@export var origin := Vector2.ZERO:
	set(value):
		if origin == value:
			return
		origin = value
		origin_changed.emit(origin)

@export var biomes: Array[Biome]

@warning_ignore_start("unused_signal")
signal parameters_changed
signal origin_changed(new_origin: Vector2)
signal amplitude_changed(new_amplitude: float)
signal maps_created
signal maps_redrawn

@abstract
func create_maps(ring_size: Vector2i, lod_count: int) -> void

@abstract
func shift_maps() -> void

@abstract
func has_maps() -> bool

@abstract
func get_height_images() -> Array[Image]

@abstract
func get_height_texture_array() -> Texture2DArray

@abstract
func get_control_texture_array() -> Texture2DArray

@abstract
func sample(world_position: Vector2, vertex_spacing: Vector2) -> float

@abstract
func get_height_amplitude() -> float
