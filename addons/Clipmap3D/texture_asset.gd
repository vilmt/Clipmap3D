@tool
class_name Clipmap3DTextureAsset extends Resource

## The color to modulate the albedo texture with.
@export_color_no_alpha var albedo_color := Color.WHITE

## RGB: Albedo, A: Roughness
@export var albedo_roughness_texture: Texture2D:
	set(value):
		if albedo_roughness_texture == value:
			return
		albedo_roughness_texture = value
		emit_changed()

## RG: Normal (OpenGL), B: Height, A: Ambient Occlusion
@export var normal_height_ao_texture: Texture2D:
	set(value):
		if normal_height_ao_texture == value:
			return
		normal_height_ao_texture = value
		emit_changed()

@export var uv_scale := Vector2.ONE

@export var normal_depth: float = 1.0

## WIP. Currently does nothing.
@export var projected: bool = false

## WIP. Currently does nothing.
@export var roughness: float = 1.0

func get_texture(type: Clipmap3DSource.TextureType) -> Texture2D:
	match type:
		Clipmap3DSource.TextureType.ALBEDO:
			return albedo_roughness_texture
		Clipmap3DSource.TextureType.NORMAL:
			return normal_height_ao_texture
	return null
	
