@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO: threading

@export var origin := Vector2.ZERO

@warning_ignore("unused_signal")
signal refreshed

@abstract
func create_maps(ring_size: Vector2i, lod_count: int)

@abstract
func shift_maps()

@abstract
func get_images() -> Array[Image]

@abstract
func get_textures() -> Texture2DArray

@abstract
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float
