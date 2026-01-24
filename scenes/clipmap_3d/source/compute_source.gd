@tool
class_name Clipmap3DComputeSource extends Clipmap3DSource

# TODO
@export var compute_shader: RDShaderFile

@export var height_amplitude: float = 800.0:
	set(value):
		height_amplitude = value
		emit_changed()

@export var dumb_scale: float = 0.1:
	set(value):
		dumb_scale = value
		emit_changed()

@export var compute_seed: int = 0:
	set(value):
		compute_seed = value
		emit_changed()

static var _rd := RenderingServer.get_rendering_device()

var _uniform_set_rid: RID
var _pipeline_rid: RID
var _map_rd_rids: Dictionary[MapType, RID]
var _map_rids: Dictionary[MapType, RID]

var _size: Vector2i
var _lod_count: int
var _vertex_spacing: Vector2
var _world_origin: Vector2

var _origins: Array[Vector2]
var _dirty: Array[bool]

var _cpu_height_image: Image

func has_maps() -> bool:
	return not _map_rids.is_empty()

func get_map_rids() -> Dictionary[MapType, RID]:
	return _map_rids

func get_height_amplitude():
	return height_amplitude

func get_height_world(world_xz: Vector2) -> float:
	if not _cpu_height_image:
		return 0.0
	var _image_size := _cpu_height_image.get_size()
	var inv_scale := Vector2.ONE / (_vertex_spacing * float(1 << 0))
	var lod_cell := Vector2i((world_xz * inv_scale).floor() - _origins[0])
	@warning_ignore("integer_division")
	var texel := lod_cell + _image_size / 2;
	if not Rect2i(Vector2i.ZERO, _image_size).has_point(texel):
		return 0.0
	return _cpu_height_image.get_pixelv(texel).r
	
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
	_world_origin = world_origin
	
	for lod: int in _lod_count:
		var inv_scale := Vector2.ONE / (_vertex_spacing * float(1 << lod))
		var origin := (_world_origin * inv_scale).floor()
		if origin.is_equal_approx(_origins[lod]):
			continue
		_origins[lod] = origin
		_dirty[lod] = true
	
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
		_create_texture_uniform_threaded(MapType.HEIGHT, 0),
		_create_texture_uniform_threaded(MapType.NORMAL, 1),
		_create_texture_uniform_threaded(MapType.CONTROL, 2)
	]
	
	_uniform_set_rid = _rd.uniform_set_create(uniforms, shader_rid, 0)
	_pipeline_rid = _rd.compute_pipeline_create(shader_rid)
	
	_dirty.resize(_lod_count)
	_dirty.fill(true)
	_origins.resize(_lod_count)
	for lod: int in _lod_count:
		var inv_scale := Vector2.ONE / (_vertex_spacing * float(1 << lod))
		_origins[lod] = (_world_origin * inv_scale).floor()
	
	_compute_threaded(false)
	maps_created.emit()

# TODO: add "strip" mode where only small dirty sections of map are updated
func _compute_threaded(use_signal: bool = true) -> void:
	var groups_x := ceili(_size.x / 8.0)
	var groups_y := ceili(_size.y / 8.0)
	for lod: int in _lod_count:
		if not _dirty[lod]:
			continue
		var compute_list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
		_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
		
		var push := PackedByteArray()
		push.resize(32)
		
		push.encode_float(0, _world_origin.x)
		push.encode_float(4, _world_origin.y)
		push.encode_float(8, _vertex_spacing.x)
		push.encode_float(12, _vertex_spacing.y)
		push.encode_s32(16, lod)
		push.encode_s32(20, compute_seed)
		push.encode_float(24, height_amplitude)
		push.encode_float(28, dumb_scale)
		
		_rd.compute_list_set_push_constant(compute_list, push, push.size())
		
		_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
		_rd.compute_list_end()
		
		_dirty[lod] = false
		
		if lod == 0:
			_cpu_height_image = RenderingServer.texture_2d_layer_get(_map_rids[MapType.HEIGHT], 0)
	
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
	for rid: RID in _map_rd_rids.values():
		_rd.free_rid(rid)
	_map_rd_rids.clear()

func _create_texture_uniform_threaded(type: MapType, binding: int) -> RDUniform:
	var format := RDTextureFormat.new()
	format.format = FORMATS[type]
	format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	format.width = _size.x
	format.height = _size.y
	format.array_layers = _lod_count
	format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	if type == MapType.HEIGHT:
		format.usage_bits |= _rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	_map_rd_rids[type] = _rd.texture_create(format, RDTextureView.new())
	_map_rids[type] = RenderingServer.texture_rd_create(_map_rd_rids[type], RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(_map_rd_rids[type])
	
	return uniform

func _shader_connect():
	if not Clipmap3DShaderCache.reloaded.is_connected(_initialize_threaded):
		Clipmap3DShaderCache.about_to_reload.connect(_free_rids_threaded)
		Clipmap3DShaderCache.reloaded.connect(_initialize_threaded)

func _shader_disconnect():
	if Clipmap3DShaderCache.reloaded.is_connected(_initialize_threaded):
		Clipmap3DShaderCache.about_to_reload.disconnect(_free_rids_threaded)
		Clipmap3DShaderCache.reloaded.disconnect(_initialize_threaded)

# DEBUG
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _pipeline_rid:
			push_error("Maps were not deleted.")
