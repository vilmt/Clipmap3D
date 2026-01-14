@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO: threading
@export var origin := Vector2.ZERO
@export var biomes: Array[Biome]

@warning_ignore("unused_signal")
signal refreshed

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
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float
