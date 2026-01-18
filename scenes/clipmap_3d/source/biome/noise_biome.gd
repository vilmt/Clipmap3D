@tool
class_name NoiseBiome extends Biome

@export var height_noise: Noise:
	set(value):
		if height_noise == value:
			return
		if height_noise:
			height_noise.changed.disconnect(parameters_changed.emit)
		height_noise = value
		if height_noise:
			height_noise.changed.connect(parameters_changed.emit)
		parameters_changed.emit()

@export var weight_noise: Noise:
	set(value):
		if weight_noise == value:
			return
		if weight_noise:
			weight_noise.changed.disconnect(parameters_changed.emit)
		weight_noise = value
		if weight_noise:
			weight_noise.changed.connect(parameters_changed.emit)
		parameters_changed.emit()

@export var weight_bias: float = 0.0:
	set(value):
		if weight_bias == value:
			return
		weight_bias = value
		parameters_changed.emit()

func get_height(xz: Vector2i) -> float:
	return height_noise.get_noise_2dv(xz) * 0.5 + 0.5
	
func get_weight(xz: Vector2i) -> float:
	if not weight_noise:
		return 0.0
	return weight_noise.get_noise_2dv(xz) + weight_bias

func choose_surface(xz: Vector2) -> BiomeSurface:
	var bs := BiomeSurface.new()
	bs.base = base_albedo_texture
	bs.overlay = overlay_albedo_texture
	bs.blend = sin(xz.x * 10.0) * 0.5 + 0.5
	return bs
