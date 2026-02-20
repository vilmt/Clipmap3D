@tool
class_name Clipmap3DTextureAsset extends Resource

const UV_SCALE_DEFAULT := Vector2.ONE
const ALBEDO_MODULATE_DEFAULT := Color.WHITE
const ROUGHNESS_OFFSET_DEFAULT: float = 0.0
const NORMAL_DEPTH_DEFAULT: float = 1.0
const FLAGS_DEFAULT: int = 0b00000000_00000000_00000000_00000000

# TODO: changed signals and live updating

@export_custom(PROPERTY_HINT_LINK, "") var uv_scale := UV_SCALE_DEFAULT

## RGB: Albedo, A: Roughness
@export var albedo_texture: Texture2D

## The albedo color is multiplied by this value.
@export_color_no_alpha var albedo_modulate := ALBEDO_MODULATE_DEFAULT

## This value is added to the texture roughness.
@export_range(-1.0, 1.0) var roughness_offset := ROUGHNESS_OFFSET_DEFAULT

## RG: Normal (OpenGL), OPTIONAL: (B: Height, A: Ambient Occlusion)
@export var normal_texture: Texture2D

@export_range(0.0, 20.0) var normal_depth := NORMAL_DEPTH_DEFAULT

@export_flags("Randomize Translation", "Randomize Rotation") var flags := FLAGS_DEFAULT

func get_texture(type: Clipmap3DSource.TextureType) -> Texture2D:
	match type:
		Clipmap3DSource.TextureType.ALBEDO:
			return albedo_texture
		Clipmap3DSource.TextureType.NORMAL:
			return normal_texture
	return null
