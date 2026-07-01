@tool
class_name Clipmap3DComputeHandler

# NOTE: "_threaded" prefix indicates that the function should be called using RenderingServer.call_on_render_thread()

const LOCAL_SIZE := Vector3i(16, 16, 1)

const HEIGHT_BUFFER_BINDING: int = 0
const GRADIENT_BUFFER_BINDING: int = 1
const CONTROL_BUFFER_BINDING: int = 2

const HEIGHT_BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT
const GRADIENT_BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
const CONTROL_BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT

signal compute_finished

var compute_shader: RDShaderFile:
	set(value):
		# Disconnect from old resource
		if compute_shader and compute_shader.changed.is_connected(_on_shader_changed):
			compute_shader.changed.disconnect(_on_shader_changed)
		compute_shader = value
		# Connect to new resource
		if compute_shader and not compute_shader.changed.is_connected(_on_shader_changed):
			compute_shader.changed.connect(_on_shader_changed)
		
		_on_shader_changed()

var compute_seed: int:
	set(value):
		compute_seed = value
		
		_compute_needs_update = true
		_schedule_update()

var texels_per_vertex: Vector2i:
	set(value):
		texels_per_vertex = value
		
		_buffers_need_rebuild = true
		_compute_needs_update = true
		_schedule_update()

var lod_count: int:
	set(value):
		lod_count = value
		
		_buffers_need_rebuild = true
		_compute_needs_update = true
		_schedule_update()

# Used to calculate the vertex count which is equal to the buffer size
var tile_size: Vector2i:
	set(value):
		tile_size = value
		
		_buffers_need_rebuild = true
		_compute_needs_update = true
		_schedule_update()

var vertex_spacing: Vector2:
	set(value):
		vertex_spacing = value
		
		_compute_needs_update = true
		_schedule_update()

var world_origin: Vector2:
	set(value):
		world_origin = value
		
		_compute_needs_update = true
		_schedule_update()

var _built: bool = false

var _shader_needs_rebuild: bool = true
var _buffers_need_rebuild: bool = true
var _compute_needs_update: bool = true

var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _uniform_set_rid: RID

# rd buffers are used to get data from compute
var _height_buffer_rd_rid: RID
var _gradient_buffer_rd_rid: RID
var _control_buffer_rd_rid: RID

# regular TextureRD buffers expose the rd buffers to vertex and fragment
var _height_buffer_rid: RID
var _gradient_buffer_rid: RID
var _control_buffer_rid: RID

var _previous_origins: Array[Vector2i]

func build():
	if _built:
		return
	_built = true
	_shader_needs_rebuild = true
	_buffers_need_rebuild = true
	_compute_needs_update = true
	
	_schedule_update()

func clear():
	if not _built:
		return
	_built = false
	_shader_needs_rebuild = false
	_buffers_need_rebuild = false
	_compute_needs_update = false
	
	RenderingServer.call_on_render_thread(_clear_threaded)

func get_height_buffer_rid() -> RID:
	return _height_buffer_rid

func get_gradient_buffer_rid() -> RID:
	return _gradient_buffer_rid

func get_control_buffer_rid() -> RID:
	return _control_buffer_rid

func _get_vertex_count() -> Vector2i:
	return 4 * tile_size + 3 * Vector2i.ONE

func _schedule_update() -> void:
	RenderingServer.call_on_render_thread(_update_threaded)

func _update_threaded() -> void:
	if not _built:
		return
	
	if not _ensure_device_threaded():
		return
	if not _ensure_shader_threaded():
		return
	if not _ensure_buffers_threaded():
		return
	
	_compute_threaded()

func _clear_threaded() -> void:
	_free_buffers_threaded()
	_free_shader_threaded()

#region device lifecycle

func _ensure_device_threaded() -> bool:
	if not _rd:
		# NOTE: could use local rendering device
		_rd = RenderingServer.get_rendering_device()
		if not _rd:
			push_error("RenderingDevice is not supported on Compatibility renderer.")
			return false
	return true

#endregion

#region shader lifecycle

func _ensure_shader_threaded() -> bool:
	if not _shader_needs_rebuild:
		return true
	
	_free_shader_threaded()
	
	if not compute_shader:
		return false
	
	var spirv := compute_shader.get_spirv()
	
	if not spirv.compile_error_compute.is_empty():
		push_error("Compile error in compute shader: %s" % spirv.compile_error_compute)
		return false
	
	_shader_rid = _rd.shader_create_from_spirv(spirv)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	
	_shader_needs_rebuild = false
	return true

func _free_shader_threaded() -> void:
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)

func _on_shader_changed():
	_shader_needs_rebuild = true
	_buffers_need_rebuild = true
	_compute_needs_update = true
	_schedule_update()

#endregion

#region buffer lifecycle

func _ensure_buffers_threaded() -> bool:
	if not _buffers_need_rebuild:
		return true
	
	_free_buffers_threaded()
	_previous_origins.clear()
	
	var vertex_count := _get_vertex_count()
	
	## Height buffer
	
	var height_format := RDTextureFormat.new()
	height_format.format = HEIGHT_BUFFER_FORMAT
	height_format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	height_format.width = vertex_count.x * texels_per_vertex.x
	height_format.height = vertex_count.y * texels_per_vertex.y
	height_format.array_layers = lod_count
	height_format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_TO_BIT
	
	_height_buffer_rd_rid = _rd.texture_create(height_format, RDTextureView.new())
	_height_buffer_rid = RenderingServer.texture_rd_create(_height_buffer_rd_rid, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	height_uniform.binding = HEIGHT_BUFFER_BINDING
	height_uniform.add_id(_height_buffer_rd_rid)
	
	## Gradient buffer
	
	var gradient_format := RDTextureFormat.new()
	gradient_format.format = GRADIENT_BUFFER_FORMAT
	gradient_format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	gradient_format.width = vertex_count.x * texels_per_vertex.x
	gradient_format.height = vertex_count.y * texels_per_vertex.y
	gradient_format.array_layers = lod_count
	gradient_format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_TO_BIT
	
	_gradient_buffer_rd_rid = _rd.texture_create(gradient_format, RDTextureView.new())
	_gradient_buffer_rid = RenderingServer.texture_rd_create(_gradient_buffer_rd_rid, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	var gradient_uniform := RDUniform.new()
	gradient_uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	gradient_uniform.binding = GRADIENT_BUFFER_BINDING
	gradient_uniform.add_id(_gradient_buffer_rd_rid)
	
	## Control
	
	var control_format := RDTextureFormat.new()
	control_format.format = CONTROL_BUFFER_FORMAT
	control_format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	control_format.width = vertex_count.x * texels_per_vertex.x
	control_format.height = vertex_count.y * texels_per_vertex.y
	control_format.array_layers = lod_count
	control_format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		_rd.TEXTURE_USAGE_CAN_COPY_TO_BIT
	
	_control_buffer_rd_rid = _rd.texture_create(control_format, RDTextureView.new())
	_control_buffer_rid = RenderingServer.texture_rd_create(_control_buffer_rd_rid, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	var control_uniform := RDUniform.new()
	control_uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	control_uniform.binding = CONTROL_BUFFER_BINDING
	control_uniform.add_id(_control_buffer_rd_rid)
	
	var uniforms: Array[RDUniform] = [height_uniform, gradient_uniform, control_uniform]
	_uniform_set_rid = _rd.uniform_set_create(uniforms, _shader_rid, 0)
	
	_buffers_need_rebuild = false
	return true

func _free_buffers_threaded() -> void:
	# Uniform set must be checked explicitly since it may be freed with the shader
	if _rd.uniform_set_is_valid(_uniform_set_rid):
		_rd.free_rid(_uniform_set_rid)
	
	if _height_buffer_rid.is_valid():
		RenderingServer.free_rid(_height_buffer_rid)
	if _gradient_buffer_rid.is_valid():
		RenderingServer.free_rid(_gradient_buffer_rid)
	if _control_buffer_rid.is_valid():
		RenderingServer.free_rid(_control_buffer_rid)
	
	if _height_buffer_rd_rid.is_valid():
		_rd.free_rid(_height_buffer_rd_rid)
	if _gradient_buffer_rd_rid.is_valid():
		_rd.free_rid(_gradient_buffer_rd_rid)
	if _control_buffer_rd_rid.is_valid():
		_rd.free_rid(_control_buffer_rd_rid)

#endregion

func _compute_threaded() -> void:
	var current_origins: Array[Vector2i] = []
	current_origins.resize(lod_count)
	if _previous_origins.is_empty():
		_previous_origins.resize(lod_count)
		_previous_origins.fill(Vector2i(1000000, 1000000))
	
	var snap := 2.0 * Vector2.ONE
	for lod: int in lod_count:
		var scale := vertex_spacing * float(1 << lod)
		var vertex_origin := Vector2i((world_origin / scale / snap).floor() * snap)
		current_origins[lod] = vertex_origin * texels_per_vertex
	
	var size := _get_vertex_count()
	
	for lod: int in lod_count:
		var origin := current_origins[lod]
		var delta := origin - _previous_origins[lod]
		
		if delta == Vector2i.ZERO:
			continue
		
		var delta_abs := delta.abs()
		
		if delta_abs.x >= size.x or delta_abs.y >= size.y:
			var region := Rect2i(origin, size * texels_per_vertex)
			_generate_region_threaded(lod, region)
		else:
			if delta.x != 0:
				var x := size.x - delta.x if delta.x > 0 else 0
				var region := Rect2i(origin.x + x, origin.y, delta_abs.x, size.y)
				_generate_region_threaded(lod, region)
			if delta.y != 0:
				var y := size.y - delta.y if delta.y > 0 else 0
				var region := Rect2i(origin.x, origin.y + y, size.x, delta_abs.y)
				_generate_region_threaded(lod, region)
	
	_compute_needs_update = false
	compute_finished.emit()

func _generate_region_threaded(lod: int, region: Rect2i):
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	
	var push := PackedByteArray()
	push.resize(48)
	
	push.encode_s32(0, region.position.x)
	push.encode_s32(4, region.position.y)
	push.encode_s32(8, region.size.x)
	push.encode_s32(12, region.size.y)
	push.encode_s32(16, texels_per_vertex.x)
	push.encode_s32(20, texels_per_vertex.y)
	push.encode_s32(24, lod)
	push.encode_u32(28, compute_seed)
	push.encode_float(32, vertex_spacing.x)
	push.encode_float(36, vertex_spacing.y)
	
	_rd.compute_list_set_push_constant(compute_list, push, push.size())
	
	var groups_x := ceili(region.size.x / float(LOCAL_SIZE.x))
	var groups_y := ceili(region.size.y / float(LOCAL_SIZE.y))
	
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	_rd.compute_list_end()
