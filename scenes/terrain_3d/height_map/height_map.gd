@tool
@abstract
class_name HeightMap extends Resource

# TODO: async updates using signals

@export var amplitude: float = 100.0: set = set_amplitude
@export var size := Vector2i(512, 512): set = set_size
@export var origin := Vector2i.ZERO: set = set_origin

@warning_ignore_start("unused_signal")
signal image_changed(new_image: Image)
signal texture_changed(new_texture: Texture)

func update_sampling_parameters(shader_material: ShaderMaterial):
	shader_material.set_shader_parameter(&"amplitude", amplitude)

@abstract
func get_image() -> Image

@abstract
func get_texture() -> ImageTexture

func set_amplitude(value: float):
	if amplitude == value:
		return
	amplitude = value
	emit_changed()

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
