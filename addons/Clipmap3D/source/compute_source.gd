@tool
class_name Clipmap3DComputeSource extends Clipmap3DSource

## The compute shader to use for terrain generation.
@export var compute_shader: RDShaderFile:
	set(value):
		if compute_shader == value:
			return
		_disconnect_shader()
		compute_shader = value
		if _built:
			_connect_shader()

## The random number seed passed to your shader.
@export var compute_seed: int = 0:
	set(value):
		compute_seed = value
		_mark_maps_dirty()

var _rd := RenderingServer.get_rendering_device()

var _shader_rid: RID
var _uniform_set_rid: RID
var _pipeline_rid: RID
var _map_rd_rids: Dictionary[MapType, RID]
var _map_rids: Dictionary[MapType, RID]

var _texel_origins: Array[Vector2i]
var _world_origins: Array[Vector2]

var _deltas: Array[Vector2i]

var _collision_data: PackedByteArray

const DEBUG_MATERIAL: ShaderMaterial = preload("debug.tres")

var _debug_rids: Array[RID]

func create_debug_canvas_items(parent_node: CanvasItem):
	if not has_maps():
		if _built:
			await maps_created
		else:
			return
	
	var rid := RenderingServer.canvas_item_create()
	
	var material_rid := DEBUG_MATERIAL.get_rid()
	RenderingServer.material_set_param(material_rid, &"_height_maps", _map_rids.get(MapType.HEIGHT, RID()))
	RenderingServer.material_set_param(material_rid, &"_gradient_maps", _map_rids.get(MapType.GRADIENT, RID()))
	RenderingServer.material_set_param(material_rid, &"_control_maps", _map_rids.get(MapType.CONTROL, RID()))
	
	RenderingServer.canvas_item_set_parent(rid, parent_node.get_canvas_item())
	RenderingServer.canvas_item_set_material(rid, DEBUG_MATERIAL.get_rid())
	
	const DEBUG_IMAGE_SIZE := Vector2(200, 200)
	RenderingServer.canvas_item_add_rect(rid, Rect2(Vector2.ZERO, DEBUG_IMAGE_SIZE * Vector2(lod_count, 1.0)), Color.WHITE)
	RenderingServer.canvas_item_set_transform(rid, Transform2D(0.0, Vector2(10.0, 130.0)))
	_debug_rids.append(rid)

func clear_debug_canvas_items():
	for rid: RID in _debug_rids:
		RenderingServer.free_rid(rid)

func has_maps() -> bool:
	return not _map_rids.is_empty()

func get_map_rids() -> Dictionary[MapType, RID]:
	return _map_rids

func get_world_origin(lod: int) -> Vector2:
	if clampi(lod, 0, lod_count) != lod:
		return Vector2.ZERO
	return _world_origins[lod]
	
func get_texel_origin(lod: int) -> Vector2i:
	if clampi(lod, 0, lod_count) != lod:
		return Vector2i.ZERO
	return _texel_origins[lod]

func get_heightmap_data(mesh_radius: Vector2i) -> Dictionary:
	var data: Dictionary = {}
	if _collision_data.is_empty():
		return data
	
	var heights := PackedFloat32Array()
	
	var texel_origin := _texel_origins[0]
	
	var full_size := size * texels_per_vertex
	var step := texels_per_vertex
	
	var vertices := 2 * mesh_radius + Vector2i.ONE
	var half: Vector2i = (size - vertices) / 2 * texels_per_vertex
	
	data["width"] = vertices.x
	data["depth"] = vertices.y
	
	for y: int in range(half.y, full_size.y - half.y, step.y):
		for x: int in range(half.x, full_size.x - half.x, step.x):
			# TODO: math is wrong. ideally we would not fetch the entire image from the gpu
			# TODO: allow selecting which lod to use for collision mesh
			var texel = Vector2(Vector2i(x, y) + texel_origin) - Vector2(full_size) * 0.5 + Vector2(1.5, 1.5) * Vector2(texels_per_vertex)
			var tx = posmod(floori(texel.x), full_size.x)
			var ty = posmod(floori(texel.y), full_size.y)
			var index = (tx + ty * full_size.x) * 4
			var h = _collision_data.decode_float(index)
			heights.append(h)
	
	data["heights"] = heights
	
	return data

func _update_cpu_data(data: PackedByteArray):
	_collision_data = data
	collision_data_changed.emit()

func _build_maps() -> void:
	if not _rd:
		push_error("RenderingDevice not initialized. Compatibility renderer is not supported.")
		return
	_connect_shader()

func _try_shift_maps():
	if not _rd or not _built:
		return
	
	var snap := 2.0 * Vector2.ONE

	for lod: int in lod_count:
		var scale := vertex_spacing * float(1 << lod)
		
		var vertex_origin := Vector2i((world_origin / scale / snap).floor() * snap)
		var texel_origin := vertex_origin * texels_per_vertex
		
		var delta := texel_origin - _texel_origins[lod]
		
		if delta == Vector2i.ZERO:
			continue
		
		_deltas[lod] += delta
		_texel_origins[lod] = texel_origin
		_world_origins[lod] = Vector2(vertex_origin) * scale
	
	RenderingServer.call_on_render_thread(_compute_threaded)
	
func _free_maps() -> void:
	_disconnect_shader()

func _initialize_threaded():
	if not _shader_rid:
		push_error("Shader not loaded.")
		return
	
	var uniforms: Array[RDUniform] = [
		_create_texture_uniform_threaded(MapType.HEIGHT, 0),
		_create_texture_uniform_threaded(MapType.GRADIENT, 1),
		_create_texture_uniform_threaded(MapType.CONTROL, 2)
	]
	
	_uniform_set_rid = _rd.uniform_set_create(uniforms, _shader_rid, 0)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	
	_deltas.resize(lod_count)
	_deltas.fill(Vector2i(1000000, 1000000))

	_texel_origins.resize(lod_count)
	_world_origins.resize(lod_count)
	
	var snap := 2.0 * Vector2.ONE

	for lod: int in lod_count:
		var scale := vertex_spacing * float(1 << lod)
		
		var vertex_origin := Vector2i((world_origin / scale / snap).floor() * snap)
		var texel_origin := vertex_origin * texels_per_vertex
		
		_texel_origins[lod] = texel_origin
		_world_origins[lod] = Vector2(vertex_origin) * scale
	
	_compute_threaded(false)
	maps_created.emit()

func _compute_threaded(use_signal: bool = true) -> void:
	for lod: int in lod_count:
		var delta := _deltas[lod]
		
		if delta == Vector2i.ZERO:
			continue
		
		var delta_abs := delta.abs()
		
		var full_size := size * texels_per_vertex
		
		if delta_abs.x >= full_size.x or delta_abs.y >= full_size.y:
			_generate_region_threaded(lod)
		else:
			if delta.x != 0:
				var x := full_size.x - delta.x if delta.x > 0 else 0.0
				var region := Rect2i(x, 0, delta_abs.x, full_size.y)
				_generate_region_threaded(lod, region)
			if delta.y != 0:
				var y := full_size.y - delta.y if delta.y > 0 else 0.0
				var region := Rect2i(0, y, full_size.x, delta_abs.y)
				_generate_region_threaded(lod, region)
		
		_deltas[lod] = Vector2i.ZERO
		
		if collision_enabled and lod == 0:
			# NOTE: this is currently the cause of all runtime lag
			_rd.texture_get_data_async(_map_rd_rids[MapType.HEIGHT], 0, _update_cpu_data)
	
	if use_signal:
		maps_updated.emit()
	emit_changed()

func _generate_region_threaded(lod: int, region := Rect2i(Vector2i.ZERO, size * texels_per_vertex)):
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
	push.encode_s32(24, _texel_origins[lod].x)
	push.encode_s32(28, _texel_origins[lod].y)
	push.encode_s32(32, texels_per_vertex.x)
	push.encode_s32(36, texels_per_vertex.y)
	push.encode_float(40, vertex_spacing.x)
	push.encode_float(44, vertex_spacing.y)
	push.encode_float(48, height_amplitude)
	
	_rd.compute_list_set_push_constant(compute_list, push, push.size())
	
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	_rd.compute_list_end()

func _create_texture_uniform_threaded(type: MapType, binding: int) -> RDUniform:
	var format := RDTextureFormat.new()
	format.format = FORMATS[type]
	format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	format.width = size.x * texels_per_vertex.x
	format.height = size.y * texels_per_vertex.y
	format.array_layers = lod_count
	format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_TO_BIT
	
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
