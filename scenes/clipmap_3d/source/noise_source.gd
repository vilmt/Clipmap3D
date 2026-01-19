@tool
class_name Clipmap3DNoiseSource extends Clipmap3DSource

# TODO: parameters for each noise instance 

# TODO: nulling this crashes editor
@export var continental_noise: Clipmap3DNoiseParams:
	set(value):
		if continental_noise == value:
			return
		_disconnect_noise_params(continental_noise)
		continental_noise = value
		#if not has_maps():
			#return
		_connect_noise_params(continental_noise)
		emit_changed()

func _connect_noise_params(noise_params: Clipmap3DNoiseParams):
	if noise_params and not noise_params.changed.is_connected(emit_changed):
		noise_params.changed.connect(emit_changed)

func _disconnect_noise_params(noise_params: Clipmap3DNoiseParams):
	if noise_params and noise_params.changed.is_connected(emit_changed):
		noise_params.changed.disconnect(emit_changed)

#@export var mountain_noise: Noise
#@export var ridge_noise: Noise

const MAX_NOISES: int = 8

static var _rd := RenderingServer.get_rendering_device()

var _uniform_set_rid: RID
var _pipeline_rid: RID
var _texture_rd_rids: Dictionary[TextureType, RID]
var _map_rids: Dictionary[TextureType, RID]
var _noise_buffer_rid: RID

var _size: Vector2i
var _lod_count: int
var _vertex_spacing: Vector2
var _world_origin: Vector2

func has_maps() -> bool:
	return not _map_rids.is_empty()

func get_map_rids() -> Dictionary[TextureType, RID]:
	return _map_rids

func get_height_amplitude():
	var result: float = 0.0
	if continental_noise:
		result += continental_noise.amplitude
	return result

func get_height_world(world_xz: Vector2) -> float:
	return 0.0
	
func create_maps(world_origin: Vector2, size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void:
	if not _rd:
		push_error("RenderingDevice not initialized. Could not create maps.")
		return
	
	_world_origin = world_origin
	_size = size
	_lod_count = lod_count
	_vertex_spacing = vertex_spacing
	
	RenderingServer.call_on_render_thread(_free_rids_threaded)
	RenderingServer.call_on_render_thread(_initialize_threaded)

func shift_maps(world_origin: Vector2) -> void:
	if not _rd:
		return
	# TODO: only regen shifted maps
	_world_origin = world_origin
	
	RenderingServer.call_on_render_thread(_compute_threaded)

func clear_maps() -> void:
	_shader_disconnect()
	RenderingServer.call_on_render_thread(_free_rids_threaded)

func _initialize_threaded():
	var shader_rid := Clipmap3DShaderCache.get_shader_rid()
	
	_shader_connect()
	
	if not shader_rid:
		push_error("Shader not loaded")
		return
	
	var uniforms: Array[RDUniform] = [
		_create_texture_uniform_threaded(TextureType.HEIGHT, 0),
		_create_texture_uniform_threaded(TextureType.NORMAL, 1),
		_create_texture_uniform_threaded(TextureType.CONTROL, 2),
		_create_noise_buffer_threaded(3)
	]
	
	_uniform_set_rid = _rd.uniform_set_create(uniforms, shader_rid, 0)
	_pipeline_rid = _rd.compute_pipeline_create(shader_rid)
	
	_compute_threaded(false)
	maps_created.emit()

func _compute_threaded(use_signal: bool = true) -> void:
	var noise_data := _encode_noise_array([continental_noise])
	_rd.buffer_update(_noise_buffer_rid, 0, MAX_NOISES * Clipmap3DNoiseParams.ENCODED_SIZE, noise_data)
	
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	
	var push := PackedByteArray()
	push.resize(16)
	
	push.encode_float(0, _world_origin.x)
	push.encode_float(4, _world_origin.y)
	push.encode_float(8, _vertex_spacing.x)
	push.encode_float(12, _vertex_spacing.y)
	
	_rd.compute_list_set_push_constant(compute_list, push, push.size())
	
	var groups_x := ceili(_size.x / 8.0)
	var groups_y := ceili(_size.y / 8.0)
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, _lod_count)
	_rd.compute_list_end()
	
	if use_signal:
		maps_redrawn.emit()
	
func _free_rids_threaded() -> void:
	if not _rd:
		return
	if _pipeline_rid:
		_rd.free_rid(_pipeline_rid)
		_pipeline_rid = RID()
	if _uniform_set_rid:
		_rd.free_rid(_uniform_set_rid)
		_uniform_set_rid = RID()
	for rid: RID in _map_rids.values():
		RenderingServer.free_rid(rid)
	_map_rids.clear()
	for rid: RID in _texture_rd_rids.values():
		_rd.free_rid(rid)
	if _noise_buffer_rid:
		_rd.free_rid(_noise_buffer_rid)
		_noise_buffer_rid = RID()
	_texture_rd_rids.clear()

func _create_texture_uniform_threaded(type: TextureType, binding: int) -> RDUniform:
	var format := RDTextureFormat.new()
	format.format = FORMATS[type]
	format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	format.width = _size.x
	format.height = _size.y
	format.array_layers = _lod_count
	format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_UPDATE_BIT #| \
		#_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT # TODO: needed to get CPU image for collision
	
	_texture_rd_rids[type] = _rd.texture_create(format, RDTextureView.new())
	_map_rids[type] = RenderingServer.texture_rd_create(_texture_rd_rids[type], RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(_texture_rd_rids[type])
	
	return uniform

func _create_noise_buffer_threaded(binding: int) -> RDUniform:
	var size := MAX_NOISES * Clipmap3DNoiseParams.ENCODED_SIZE
	_noise_buffer_rid = _rd.storage_buffer_create(size)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = _rd.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(_noise_buffer_rid)
	
	return uniform

func _shader_connect():
	if not Clipmap3DShaderCache.reloaded.is_connected(_initialize_threaded):
		Clipmap3DShaderCache.about_to_reload.connect(_free_rids_threaded)
		Clipmap3DShaderCache.reloaded.connect(_initialize_threaded)

func _shader_disconnect():
	if Clipmap3DShaderCache.reloaded.is_connected(_initialize_threaded):
		Clipmap3DShaderCache.about_to_reload.disconnect(_free_rids_threaded)
		Clipmap3DShaderCache.reloaded.disconnect(_initialize_threaded)

func _encode_noise_array(noises: Array[Clipmap3DNoiseParams]) -> PackedByteArray:
	var data := PackedByteArray()
	for noise in noises:
		data.append_array(noise.encode())
	data.resize(MAX_NOISES * Clipmap3DNoiseParams.ENCODED_SIZE)
	return data

# DEBUG
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _pipeline_rid:
			push_error("Maps were not deleted.")
