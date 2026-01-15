class_name NoiseBiome extends Biome

@export var height_noise: Noise
@export var weight_noise: Noise
@export var weight_bias: float = 0.0

func get_height(world_xz: Vector2i) -> float:
	return height_noise.get_noise_2dv(world_xz) * 0.5 + 0.5
	
func get_weight(world_xz: Vector2i) -> float:
	return weight_noise.get_noise_2dv(world_xz) + weight_bias
