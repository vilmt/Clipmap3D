@tool
extends Node

## When received, free any RIDs depending on the shader. Emitted from the rendering thread.
signal about_to_reload

## Emitted from the rendering thread whenever the shader is hot reloaded
signal reloaded

const SHADER_FILE := preload("res://scenes/clipmap_3d/compute/compute.glsl")

var _shader_rid: RID

var _rd := RenderingServer.get_rendering_device()

func get_shader_rid() -> RID:
	return _shader_rid

func _init() -> void:
	if not _rd:
		push_error("Compatibility renderer does not support RenderingDevice.")
		return
	
	RenderingServer.call_on_render_thread(_load_shader_threaded)
	SHADER_FILE.changed.connect(RenderingServer.call_on_render_thread.bind(_load_shader_threaded))

func _exit_tree() -> void:
	RenderingServer.call_on_render_thread(_clear_shader_threaded)

func _load_shader_threaded() -> void:
	about_to_reload.emit()
	
	_clear_shader_threaded()
	var spirv := SHADER_FILE.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(spirv)

	reloaded.emit()

func _clear_shader_threaded() -> void:
	if not _rd:
		return
	if _shader_rid:
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()
	
