@tool
class_name Clipmap3DTextureAsset extends Resource

const UV_SCALE_DEFAULT := Vector3.ONE
const ALBEDO_MODULATE_DEFAULT := Color.WHITE
const ROUGHNESS_OFFSET_DEFAULT: float = 0.0
const NORMAL_DEPTH_DEFAULT: float = 1.0
const STOCHASTIC_OFFSET_DEFAULT := Vector3.ZERO
const STOCHASTIC_ROTATION_DEFAULT: float = 0.0
const FLAGS_DEFAULT: int = 0b00000000_00000000_00000000_00000000

@export_custom(PROPERTY_HINT_LINK, "") var uv_scale := UV_SCALE_DEFAULT:
	set(value):
		uv_scale = value
		emit_changed()

## By default, RGB = Albedo, and A = Roughness.
@export var albedo_texture: Texture2D:
	set(value):
		albedo_texture = value
		emit_changed()

## The albedo color is multiplied by this value.
@export_color_no_alpha var albedo_modulate := ALBEDO_MODULATE_DEFAULT:
	set(value):
		albedo_modulate = value
		emit_changed()

## This value is added to the texture roughness.
@export_range(-1.0, 1.0) var roughness_offset := ROUGHNESS_OFFSET_DEFAULT:
	set(value):
		roughness_offset = value
		emit_changed()

## RG = Normal (OpenGL). Optionally, B = Height, A = Ambient Occlusion.
@export var normal_texture: Texture2D:
	set(value):
		normal_texture = value
		emit_changed()

@export_range(0.0, 20.0) var normal_depth := NORMAL_DEPTH_DEFAULT:
	set(value):
		normal_depth = value
		emit_changed()

@export var stochastic_offset := STOCHASTIC_OFFSET_DEFAULT:
	set(value):
		stochastic_offset = value
		emit_changed()

@export var stochastic_rotation := STOCHASTIC_ROTATION_DEFAULT:
	set(value):
		stochastic_rotation = value
		emit_changed()

@export_flags("Triplanar") var flags := FLAGS_DEFAULT:
	set(value):
		flags = value
		emit_changed()
