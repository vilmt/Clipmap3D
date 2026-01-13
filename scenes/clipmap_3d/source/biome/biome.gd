class_name Biome extends Resource

@export var height_noise: Noise

@export var base_albedo_texture: Texture2D
@export var base_normal_texture: Texture2D

func get_textures() -> Array[Image]:
	return [base_albedo_texture.get_image(), base_normal_texture.get_image()]
