@tool
@abstract
class_name Terrain3DSource extends Resource

# TODO: threading

@export var size := Vector2i(512, 512)
@export var origin := Vector2i.ZERO

@warning_ignore("unused_signal")
signal refreshed

@abstract
func get_image() -> Image

@abstract
func get_texture() -> ImageTexture

@abstract
func refresh() -> void

@abstract
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float
