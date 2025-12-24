@tool
class_name TerrainProcessor extends SubViewport

@onready var color_rect: ColorRect = $ColorRect
@onready var shader_material := color_rect.material as ShaderMaterial

func set_noise_model(noise_model: FastNoiseLite):
	var noise_texture: NoiseTexture2D = shader_material.get_shader_parameter("noise_texture")
	noise_texture.noise = noise_model
	
func set_amplitude(amplitude: float) -> void:
	shader_material.set_shader_parameter("amplitude", amplitude)

func get_image(mode: int) -> Image:
	color_rect.material.set_shader_parameter("mode", mode)
	await RenderingServer.frame_post_draw
	return get_texture().get_image()
