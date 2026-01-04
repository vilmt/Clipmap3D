extends Label

@onready var vp := get_viewport().get_viewport_rid()

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(vp, true)

func _physics_process(_delta: float) -> void:
	text = "FPS: " + str(int(Engine.get_frames_per_second()))
	var setup_time: float = RenderingServer.get_frame_setup_time_cpu()
	var viewport_time: float = RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var cpu_time: float = setup_time + viewport_time
	text += "\nCPU Time: " + '%.2f' % cpu_time
	var gpu_time: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	text += "\nGPU Time: " + '%.2f' % gpu_time
