@tool
class_name Clipmap3DComputeSource extends Clipmap3DSource

# TODO: remove unnecessary image skirts

## The compute shader to use for generation.
@export var compute_shader: RDShaderFile:
	set(value):
		if compute_shader == value:
			return
		_disconnect_shader()
		compute_shader = value
		if not _initialized:
			return
		_connect_shader()

## The random number seed passed to your shader.
@export var compute_seed: int = 0:
	set(value):
		compute_seed = value
		emit_changed()

var _rd := RenderingServer.get_rendering_device()

var _shader_rid: RID
var _uniform_set_rid: RID
var _pipeline_rid: RID
var _map_rd_rids: Dictionary[MapType, RID]
var _map_rids: Dictionary[MapType, RID]

var _initialized: bool = false
var _size: Vector2i
var _lod_count: int
var _vertex_spacing: Vector2
var _world_origin: Vector2

var _origins: Array[Vector2i]
var _deltas: Array[Vector2i]

var _cpu_height_image: Image

func has_maps() -> bool:
	return not _map_rids.is_empty()

func get_map_rids() -> Dictionary[MapType, RID]:
	return _map_rids

func get_map_origins() -> Array[Vector2i]:
	return _origins

## Get the height from the LOD 0 map.
func get_height_world(world_xz: Vector2) -> float:
	return 0.0
	#if not _cpu_height_image:
		#return 0.0
	#var inv_scale := Vector2.ONE / _vertex_spacing
	#var origin := Vector2i((_world_origin * inv_scale).floor()) * texels_per_vertex
	#var lod_cell := Vector2i((world_xz * inv_scale).floor()) - origin
	#@warning_ignore("integer_division")
	#var texel := lod_cell + _size / 2;
	#if not Rect2i(Vector2i.ZERO, _size).has_point(texel):
		#return 0.0
	#return _cpu_height_image.get_pixelv(texel).r
	
func create_maps(world_origin: Vector2, size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void:
	if not _rd:
		push_error("RenderingDevice not initialized. Could not create maps.")
		return
	
	_initialized = true
	_world_origin = world_origin
	_size = size * texels_per_vertex
	_lod_count = lod_count
	_vertex_spacing = vertex_spacing
	
	if not compute_shader:
		return
	
	_connect_shader()

func shift_maps(world_origin: Vector2) -> void:
	if not _rd:
		return
	_world_origin = world_origin
	
	var unscaled_origin: Vector2 = _world_origin / _vertex_spacing
	
	for lod: int in _lod_count:
		var snap := 2.0 * Vector2.ONE
		var origin := Vector2i((unscaled_origin / float(1 << lod) / snap).floor() * snap) * texels_per_vertex
		var delta := origin - _origins[lod]
		if delta == Vector2i.ZERO:
			continue
		_deltas[lod] = delta
		_origins[lod] = origin
	
	RenderingServer.call_on_render_thread(_compute_threaded)

func clear_maps() -> void:
	_initialized = false
	_disconnect_shader()

func _initialize_threaded():
	if not _shader_rid:
		push_error("Shader not loaded")
		return
	
	var uniforms: Array[RDUniform] = [
		_create_texture_uniform_threaded(MapType.HEIGHT, 0),
		_create_texture_uniform_threaded(MapType.NORMAL, 1),
		_create_texture_uniform_threaded(MapType.CONTROL, 2)
	]
	
	_uniform_set_rid = _rd.uniform_set_create(uniforms, _shader_rid, 0)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	
	_deltas.resize(_lod_count)
	_deltas.fill(Vector2i(1000000, 1000000))

	_origins.resize(_lod_count)
	var unscaled_origin: Vector2 = _world_origin / _vertex_spacing
	for lod: int in _lod_count:
		var snap := 2.0 * Vector2.ONE
		_origins[lod] = Vector2i((unscaled_origin / float(1 << lod) / snap).floor() * snap) * texels_per_vertex
	
	_compute_threaded(false)
	maps_created.emit()

func _compute_threaded(use_signal: bool = true) -> void:
	for lod: int in _lod_count:
		var delta := _deltas[lod]
		
		if delta == Vector2i.ZERO:
			continue
		
		var delta_abs := delta.abs()
		
		if delta_abs.x >= _size.x or delta_abs.y >= _size.y:
			_generate_region_threaded(lod)
		else:
			if delta.x != 0:
				var x := _size.x - delta.x if delta.x > 0 else 0.0
				var region := Rect2i(x, 0, delta_abs.x, _size.y)
				_generate_region_threaded(lod, region)
			if delta.y != 0:
				var y := _size.y - delta.y if delta.y > 0 else 0.0
				var region := Rect2i(0, y, _size.x, delta_abs.y)
				_generate_region_threaded(lod, region)
		
		_deltas[lod] = Vector2i.ZERO
		
		#if lod == 0:
			#_cpu_height_image = RenderingServer.texture_2d_layer_get(_map_rids[MapType.HEIGHT], 0)
	
	if use_signal:
		maps_shifted.emit()

func _generate_region_threaded(lod: int, region := Rect2i(Vector2i.ZERO, _size)):
	var groups_x := ceili(region.size.x / 16.0)
	var groups_y := ceili(region.size.y / 16.0)
	
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	
	var push := PackedByteArray()
	push.resize(64)
	
	push.encode_s32(0, region.position.x)
	push.encode_s32(4, region.position.y)
	push.encode_s32(8, region.size.x)
	push.encode_s32(12, region.size.y)
	push.encode_s32(16, lod)
	push.encode_s32(20, compute_seed)
	push.encode_s32(24, _origins[lod].x)
	push.encode_s32(28, _origins[lod].y)
	push.encode_s32(32, texels_per_vertex.x)
	push.encode_s32(36, texels_per_vertex.y)
	push.encode_float(40, _vertex_spacing.x)
	push.encode_float(44, _vertex_spacing.y)
	push.encode_float(48, height_amplitude)
	
	_rd.compute_list_set_push_constant(compute_list, push, push.size())
	
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	_rd.compute_list_end()

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
		_rd.TEXTURE_USAGE_CAN_UPDATE_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_TO_BIT
	 # dont need can update bit
	
	_map_rd_rids[type] = _rd.texture_create(format, RDTextureView.new())
	_map_rids[type] = RenderingServer.texture_rd_create(_map_rd_rids[type], RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(_map_rd_rids[type])
	
	return uniform

func _connect_shader():
	if not compute_shader:
		return
	if not compute_shader.changed.is_connected(RenderingServer.call_on_render_thread):
		compute_shader.changed.connect(RenderingServer.call_on_render_thread.bind(_load_shader_threaded))
	
	RenderingServer.call_on_render_thread(_load_shader_threaded)

func _disconnect_shader():
	if compute_shader and compute_shader.changed.is_connected(RenderingServer.call_on_render_thread):
		compute_shader.changed.disconnect(RenderingServer.call_on_render_thread)
	
	RenderingServer.call_on_render_thread(_free_compute_rids_threaded)
	RenderingServer.call_on_render_thread(_free_shader_threaded)

func _load_shader_threaded() -> void:
	_free_compute_rids_threaded()
	_free_shader_threaded()
	
	var spirv := compute_shader.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(spirv)

	_initialize_threaded()

func _free_shader_threaded() -> void:
	if not _rd:
		return
	if _shader_rid:
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()

func _free_compute_rids_threaded() -> void:
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
