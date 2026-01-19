@tool
class_name Clipmap3DNoiseParams extends Resource

@export_enum("Simplex", "Simplex Smooth", "Cellular", "Perlin", "Value Cubic", "Value") var noise_type: int:
	set(value):
		noise_type = value
		emit_changed()

@warning_ignore("shadowed_global_identifier")
@export var seed: int = 1337:
	set(value):
		seed = value
		emit_changed()

@export var amplitude: float = 100.0:
	set(value):
		amplitude = value
		emit_changed()

@export var frequency: float = 0.01:
	set(value):
		frequency = value
		emit_changed()

@export var offset := Vector2.ZERO:
	set(value):
		offset = value
		emit_changed()

@export var absolute: bool = false:
	set(value):
		absolute = value
		emit_changed()

@export_group("Fractal", "fractal_")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var fractal_enabled: bool = false:
	set(value):
		fractal_enabled = value
		emit_changed()

@export_enum("FBM:1", "Ridged:2", "Ping Pong:3") var fractal_type: int = 1:
	set(value):
		fractal_type = value
		emit_changed()

@export_range(1, 10) var fractal_octaves: int = 5:
	set(value):
		fractal_octaves = value
		emit_changed()

@export var fractal_lacunarity: float = 2.0:
	set(value):
		fractal_lacunarity = value
		emit_changed()

@export var fractal_gain: float = 0.5:
	set(value):
		fractal_gain = value
		emit_changed()

@export_range(0.0, 1.0) var fractal_weighted_strength: float = 0.0:
	set(value):
		fractal_weighted_strength = value
		emit_changed()

@export var fractal_ping_pong_strength: float = 2.0:
	set(value):
		fractal_ping_pong_strength = value
		emit_changed()

const ENCODED_SIZE: int = 64

func encode() -> PackedByteArray:
	var result: PackedByteArray
	result.resize(ENCODED_SIZE)
	result.encode_s32(0, noise_type)
	result.encode_s32(4, seed)
	result.encode_float(8, amplitude)
	result.encode_float(12, frequency)
	result.encode_float(16, offset.x)
	result.encode_float(20, offset.y)
	result.encode_u32(24, int(absolute))
	result.encode_s32(28, fractal_type if fractal_enabled else 0)
	result.encode_s32(32, fractal_octaves)
	result.encode_float(36, fractal_lacunarity)
	result.encode_float(40, fractal_gain)
	result.encode_float(44, fractal_weighted_strength)
	result.encode_float(48, fractal_ping_pong_strength)
	
	return result
