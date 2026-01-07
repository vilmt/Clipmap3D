@tool
@abstract
class_name Terrain3DSource extends Resource

# TODO: threading

@export var size := Vector2i(512, 512): set = set_size
@export var origin := Vector2i.ZERO: set = set_origin

@abstract
func get_image() -> Image

@abstract
func get_texture() -> ImageTexture

@abstract
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float

func set_size(value: Vector2i):
	if size == value:
		return
	size = value
	emit_changed()

func set_origin(value: Vector2i):
	if origin == value:
		return
	origin = value
	emit_changed()
