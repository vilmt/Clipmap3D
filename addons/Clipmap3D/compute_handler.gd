@tool
class_name Clipmap3DComputeHandler

# NOTE: "_threaded" suffix indicates that the function should be called using RenderingServer.call_on_render_thread()

const LOCAL_SIZE := Vector3i(16, 16, 1)

const HEIGHT_BUFFER_BINDING: int = 0
const GRADIENT_BUFFER_BINDING: int = 1
const CONTROL_BUFFER_BINDING: int = 2

const HEIGHT_BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT
const GRADIENT_BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
const CONTROL_BUFFER_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT

signal region_updated(lod: int, new_safe_region: Rect2i)

var compute_data: Clipmap3DComputeData:
	set(value):
		if compute_data == value:
			return
		
		if compute_data and compute_data.changed.is_connected(_on_compute_data_changed):
			compute_data.changed.disconnect(_on_compute_data_changed)
		compute_data = value
		if compute_data and not compute_data.changed.is_connected(_on_compute_data_changed):
			compute_data.changed.connect(_on_compute_data_changed)
		
		_on_compute_data_changed()

var lod_count: int:
	set(value):
		if lod_count == value:
			return
		lod_count = value
		
		_buffers_need_rebuild = true
		_compute_needs_update = true
		_material_needs_update = true
		_schedule_update()

## Used to calculate the vertex count which is equal to the buffer size.
var tile_size: Vector2i:
	set(value):
		if tile_size == value:
			return
		tile_size = value
		
		_buffers_need_rebuild = true
		_compute_needs_update = true
		_material_needs_update = true
		_schedule_update()

var target_transform: Transform3D:
	set(value):
		if target_transform == value:
			return
		target_transform = value
		
		_compute_needs_update = true
		_schedule_update()

var material: ShaderMaterial:
	set(value):
		if material == value:
			return
		material = value
		
		_material_needs_update = true
		_schedule_update()

var _compute_shader: RDShaderFile:
	set(value):
		if _compute_shader == value:
			return
		# Disconnect from old resource
		if _compute_shader and _compute_shader.changed.is_connected(_on_shader_changed):
			_compute_shader.changed.disconnect(_on_shader_changed)
		_compute_shader = value
		# Connect to new resource
		if _compute_shader and not _compute_shader.changed.is_connected(_on_shader_changed):
			_compute_shader.changed.connect(_on_shader_changed)
		
		_on_shader_changed()

var _compute_seed: int:
	set(value):
		if _compute_seed == value:
			return
		_compute_seed = value
		_previous_origins.clear()
		_compute_needs_update = true
		_schedule_update()

var _texels_per_vertex: Vector2i:
	set(value):
		if _texels_per_vertex == value:
			return
		_texels_per_vertex = value
		
		_buffers_need_rebuild = true
		_compute_needs_update = true
		_material_needs_update = true
		_schedule_update()

# State bools
var _built: bool = false
var _shader_needs_rebuild: bool = false
var _buffers_need_rebuild: bool = false
var _compute_needs_update: bool = false
var _material_needs_update: bool = false

var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _uniform_set_rid: RID

# RD buffers are used to get data from compute
var _height_buffer_rd_rid: RID
var _gradient_buffer_rd_rid: RID
var _control_buffer_rd_rid: RID

# TextureRD buffers expose the RD buffers to vertex and fragment
# TODO: check if this still works when using a local RenderingDevice
var _height_buffer_rid: RID
var _gradient_buffer_rid: RID
var _control_buffer_rid: RID

# Used for calculating the changed region of the buffers
var _previous_origins: Array[Vector2i]

func build():
	if _built:
		return
	_built = true
	_shader_needs_rebuild = true
	_buffers_need_rebuild = true
	_compute_needs_update = true
	_material_needs_update = true
	
	_schedule_update()

func clear():
	if not _built:
		return
	_built = false
	_shader_needs_rebuild = false
	_buffers_need_rebuild = false
	_compute_needs_update = false
	_material_needs_update = false
	
	RenderingServer.call_on_render_thread(_clear_threaded)

func request_height_data(lod: int, callback: Callable) -> void:
	if lod >= lod_count:
		push_error("Lod %s is out of bounds." % lod)
		return
	_rd.texture_get_data_async(_height_buffer_rd_rid, lod, callback)

func get_vertex_count() -> Vector2i:
	return 4 * tile_size + 3 * Vector2i.ONE

func get_texels_per_vertex() -> Vector2i:
	return _texels_per_vertex

func get_buffer_size() -> Vector2i:
	return get_vertex_count() * _texels_per_vertex

func get_safe_region(lod: int) -> Rect2i:
	if _previous_origins.size() <= lod:
		return Rect2i()
	var origin := _previous_origins[lod]
	var buffer_size := get_buffer_size()
	var top_corner := origin - (buffer_size / 2 - _texels_per_vertex)
	return Rect2i(top_corner, buffer_size)

func world_to_texel(world_position: Vector3, lod: int) -> Vector2i:
	# TODO: document why the snap is 2 texels wide
	var snap := 2.0 * Vector2.ONE
	var vertex_position := Vector2(world_position.x, world_position.z) / float(1 << lod)
	return Vector2i((vertex_position / snap).floor() * snap) * _texels_per_vertex

func texel_to_world(texel_position: Vector2i, lod: int) -> Vector3:
	var s = Vector2(texel_position) / Vector2(_texels_per_vertex) * float(1 << lod)
	return Vector3(s.x, 0.0, s.y)

func _schedule_update() -> void:
	RenderingServer.call_on_render_thread(_update_threaded)

func _update_threaded() -> void:
	if not _built:
		return
	
	# All dependencies must be fulfilled or the compute stage will fail
	if not _ensure_device_threaded():
		_clear_threaded()
		return
	if not _ensure_shader_threaded():
		_clear_threaded()
		return
	if not _ensure_buffers_threaded():
		_clear_threaded()
		return
	
	_update_compute_threaded()
	_update_material()

func _clear_threaded() -> void:
	_free_buffers_threaded()
	_free_shader_threaded()

#region device
func _ensure_device_threaded() -> bool:
	if not _rd:
		# NOTE: could use local rendering device
		_rd = RenderingServer.get_rendering_device()
		if not _rd:
			push_error("RenderingDevice is not supported on Compatibility renderer.")
			return false
	return true
#endregion

#region shader
func _ensure_shader_threaded() -> bool:
	if not _shader_needs_rebuild:
		return true
	
	_free_shader_threaded()
	
	if not _compute_shader:
		return false
	
	var spirv := _compute_shader.get_spirv()
	
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
		_pipeline_rid = RID()
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()

func _on_shader_changed():
	_shader_needs_rebuild = true
	_buffers_need_rebuild = true
	_compute_needs_update = true
	_material_needs_update = true
	_schedule_update()
#endregion

#region buffers
func _ensure_buffers_threaded() -> bool:
	if not _buffers_need_rebuild:
		return true
	
	_free_buffers_threaded()
	_previous_origins.clear()
	
	var buffer_size := get_buffer_size()
	
	# Height buffer
	
	var height_format := RDTextureFormat.new()
	height_format.format = HEIGHT_BUFFER_FORMAT
	height_format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	height_format.width = buffer_size.x
	height_format.height = buffer_size.y
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
	
	# Gradient buffer
	
	var gradient_format := RDTextureFormat.new()
	gradient_format.format = GRADIENT_BUFFER_FORMAT
	gradient_format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	gradient_format.width = buffer_size.x
	gradient_format.height = buffer_size.y
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
	
	# Control buffer
	
	var control_format := RDTextureFormat.new()
	control_format.format = CONTROL_BUFFER_FORMAT
	control_format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	control_format.width = buffer_size.x
	control_format.height = buffer_size.y
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
		_uniform_set_rid = RID()
	
	if _height_buffer_rid.is_valid():
		RenderingServer.free_rid(_height_buffer_rid)
		_height_buffer_rid = RID()
	if _gradient_buffer_rid.is_valid():
		RenderingServer.free_rid(_gradient_buffer_rid)
		_gradient_buffer_rid = RID()
	if _control_buffer_rid.is_valid():
		RenderingServer.free_rid(_control_buffer_rid)
		_control_buffer_rid = RID()
	
	if _height_buffer_rd_rid.is_valid():
		_rd.free_rid(_height_buffer_rd_rid)
		_height_buffer_rd_rid = RID()
	if _gradient_buffer_rd_rid.is_valid():
		_rd.free_rid(_gradient_buffer_rd_rid)
		_gradient_buffer_rd_rid = RID()
	if _control_buffer_rd_rid.is_valid():
		_rd.free_rid(_control_buffer_rd_rid)
		_control_buffer_rd_rid = RID()
#endregion

#region compute
func _update_compute_threaded() -> void:
	if not _compute_needs_update:
		return
	
	var current_origins: Array[Vector2i] = []
	current_origins.resize(lod_count)
	if _previous_origins.is_empty():
		_previous_origins.resize(lod_count)
		_previous_origins.fill(Vector2i(-1e10, -1e10))
	
	for lod: int in lod_count:
		current_origins[lod] = world_to_texel(target_transform.origin, lod)
	
	var buffer_size := get_buffer_size()
	
	for lod: int in lod_count:
		var origin := current_origins[lod]
		var delta := origin - _previous_origins[lod]
		
		if delta == Vector2i.ZERO:
			continue
		
		var delta_abs := delta.abs()
		
		# I don't understand this formula but it works perfectly for each LOD and texels_per_vertex, so don't touch it.
		var top_corner := origin - (buffer_size / 2 - _texels_per_vertex)
		
		var full_region := Rect2i(top_corner, buffer_size)
		
		if delta_abs.x >= buffer_size.x or delta_abs.y >= buffer_size.y:
			# Delta is greater than buffer size, generate whole thing again.
			_generate_region_threaded(lod, full_region)
		else:
			# Delta is smaller than buffer size, generate x and y strips.
			if delta.x != 0:
				var x := buffer_size.x - delta.x if delta.x > 0 else 0
				var region := Rect2i(top_corner.x + x, top_corner.y, delta_abs.x, buffer_size.y)
				_generate_region_threaded(lod, region)
			if delta.y != 0:
				var y := buffer_size.y - delta.y if delta.y > 0 else 0
				var region := Rect2i(top_corner.x, top_corner.y + y, buffer_size.x, delta_abs.y)
				_generate_region_threaded(lod, region)
		
		region_updated.emit(lod, full_region)
	
	_previous_origins = current_origins
	
	_compute_needs_update = false

func _generate_region_threaded(lod: int, region: Rect2i) -> void:
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	
	var push := PackedByteArray()
	push.resize(32)
	
	push.encode_s32(0, region.position.x)
	push.encode_s32(4, region.position.y)
	push.encode_s32(8, region.size.x)
	push.encode_s32(12, region.size.y)
	push.encode_s32(16, _texels_per_vertex.x)
	push.encode_s32(20, _texels_per_vertex.y)
	push.encode_s32(24, lod)
	push.encode_u32(28, _compute_seed)
	
	_rd.compute_list_set_push_constant(compute_list, push, push.size())
	
	var groups_x := ceili(region.size.x / float(LOCAL_SIZE.x))
	var groups_y := ceili(region.size.y / float(LOCAL_SIZE.y))
	
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	_rd.compute_list_end()

func _on_compute_data_changed() -> void:
	if compute_data:
		_compute_shader = compute_data.compute_shader
		_compute_seed = compute_data.compute_seed
		_texels_per_vertex = compute_data.texels_per_vertex
	else:
		_compute_shader = null
		_compute_seed = 0
		_texels_per_vertex = Vector2i.ONE
#endregion

#region material
func _update_material() -> void:
	if not _material_needs_update:
		return
	if not material:
		_material_needs_update = false
		return
	
	# NOTE: Setting shader parameters using the RID is more consistent when calling from the rendering thread
	
	var material_rid := material.get_rid()
	RenderingServer.material_set_param(material_rid, &"_texels_per_vertex", _texels_per_vertex)
	RenderingServer.material_set_param(material_rid, &"_height_buffer", _height_buffer_rid)
	RenderingServer.material_set_param(material_rid, &"_gradient_buffer", _gradient_buffer_rid)
	RenderingServer.material_set_param(material_rid, &"_control_buffer", _control_buffer_rid)
	
	_material_needs_update = false
#endregion
