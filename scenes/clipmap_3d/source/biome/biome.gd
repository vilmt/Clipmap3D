@abstract
class_name Biome extends Resource

#@export var overwrite_source_height: bool = false

@export var base_albedo_texture: Texture2D
@export var base_normal_texture: Texture2D

@export var overlay_albedo_texture: Texture2D
@export var overlay_normal_texture: Texture2D

func get_unique_textures() -> Array[Texture2D]:
	return [base_albedo_texture, base_normal_texture, overlay_albedo_texture, overlay_normal_texture]

@abstract
func get_weight(world_xz: Vector2i) -> float

@abstract
func get_height(world_xz: Vector2i) -> float
