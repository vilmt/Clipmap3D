@abstract
@tool
class_name Biome extends Resource

#@export var use_slope: bool

@warning_ignore_start("unused_signal")
signal textures_changed
signal parameters_changed

class BiomeSurface:
	var base: Texture2D
	var overlay: Texture2D
	var blend: float

@export var base_albedo_texture: Texture2D:
	set(value):
		if base_albedo_texture == value:
			return
		base_albedo_texture = value
		textures_changed.emit()

@export var base_normal_texture: Texture2D:
	set(value):
		if base_normal_texture == value:
			return
		base_normal_texture = value
		textures_changed.emit()

@export var overlay_albedo_texture: Texture2D:
	set(value):
		if overlay_albedo_texture == value:
			return
		overlay_albedo_texture = value
		textures_changed.emit()
		
@export var overlay_normal_texture: Texture2D:
	set(value):
		if overlay_normal_texture == value:
			return
		overlay_normal_texture = value
		textures_changed.emit()

func get_albedo_textures() -> Array[Texture2D]:
	return [base_albedo_texture, overlay_albedo_texture]

func get_normal_textures() -> Array[Texture2D]:
	return [base_normal_texture, overlay_normal_texture]

@abstract
func get_weight(xz: Vector2i) -> float

@abstract
func get_height(xz: Vector2i) -> float

@abstract
func choose_surface(xz: Vector2) -> BiomeSurface
