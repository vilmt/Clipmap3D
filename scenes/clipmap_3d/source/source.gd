@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO
@export var world_offset := Vector2.ZERO

@warning_ignore_start("unused_signal")
signal texture_arrays_created
signal texture_arrays_changed
signal maps_created
signal maps_redrawn

enum TextureType {
	HEIGHT,
	NORMAL,
	CONTROL
}

const FORMATS: Dictionary[TextureType, RenderingDevice.DataFormat] = {
	TextureType.HEIGHT: RenderingDevice.DATA_FORMAT_R32_SFLOAT,
	TextureType.NORMAL: RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,
	TextureType.CONTROL: RenderingDevice.DATA_FORMAT_R32_SFLOAT
}

@abstract
func create_maps(world_origin: Vector2, size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void

@abstract
func shift_maps(world_origin: Vector2) -> void

@abstract
func clear_maps()

@abstract
func has_maps() -> bool

@abstract
func get_map_rids() -> Dictionary[TextureType, RID]

@abstract
func get_height_world(world_xz: Vector2) -> float

@abstract
func get_height_amplitude() -> float
