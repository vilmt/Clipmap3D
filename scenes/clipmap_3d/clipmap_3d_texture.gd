@tool
class_name Clipmap3DTextureAsset extends Resource

# TODO: roughness, ao, etc...

@export var albedo_texture: Texture2D:
	set(value):
		if albedo_texture == value:
			return
		albedo_texture = value
		emit_changed()

@export var normal_texture: Texture2D:
	set(value):
		if normal_texture == value:
			return
		normal_texture = value
		emit_changed()

@export var normal_depth: float = 1.0
@export_enum("OpenGL: 0", "DirectX: 1") var normal_format: int = false

func get_texture(type: Clipmap3DSource.TextureType) -> Texture2D:
	match type:
		Clipmap3DSource.TextureType.ALBEDO:
			return albedo_texture
		Clipmap3DSource.TextureType.NORMAL:
			return normal_texture
	return null
	
