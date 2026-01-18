@tool
class_name Clipmap3DNoiseSource extends Clipmap3DSource

@export var continental_amplitude: float:
	set(value):
		if continental_amplitude == value:
			return
		continental_amplitude = value
		amplitude_changed.emit(get_height_amplitude())

const SHADER_FILE: RDShaderFile = preload("res://scenes/compute/compute.glsl")

#@export var mountain_noise: Noise
#@export var ridge_noise: Noise



const HEIGHT_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT
const NORMAL_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
const CONTROL_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT

static var _rd: RenderingDevice
static var _shader_rid: RID # TODO: research if this is bad

var _uniform_set_rid: RID
var _pipeline_rid: RID
var _texture_rd_rids: Array[RID]
var _map_rids: Array[RID]

var _size: Vector2i
var _lod_count: int
var _vertex_spacing: Vector2
var _world_origin: Vector2

func has_maps() -> bool:
	return not _map_rids.is_empty()

func get_map_rids() -> Array[RID]:
	return _map_rids

func get_height_amplitude():
	return continental_amplitude

func _init() -> void:
	if not _rd:
		_rd = RenderingServer.get_rendering_device()
	
	if not _shader_rid:
		var spirv := SHADER_FILE.get_spirv()
		_shader_rid = _rd.shader_create_from_spirv(spirv)

func create_maps(world_origin: Vector2, size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void:
	if not SHADER_FILE:
		push_error("Shader file invalid")
		return
	_world_origin = world_origin
	_size = size
	_lod_count = lod_count
	_vertex_spacing = vertex_spacing
	
	RenderingServer.call_on_render_thread(_initialize)
	
	maps_created.emit()

func shift_maps(world_origin: Vector2) -> void:
	# TODO: only regen shifted maps
	_world_origin = world_origin
	
	RenderingServer.call_on_render_thread(_compute)
	
	maps_redrawn.emit()

func _initialize():
	if not _rd:
		push_error("RenderingDevice not initialized")
		return
	if not _shader_rid:
		push_error("Shader not loaded")
		return
	
	_free_all_rids()
	
	var uniforms: Array[RDUniform] = []
	for format in [HEIGHT_FORMAT, NORMAL_FORMAT, CONTROL_FORMAT]:
		uniforms.append(_create_uniform(format))
	
	_uniform_set_rid = _rd.uniform_set_create(uniforms, _shader_rid, 0)
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	
	_compute()

func _compute() -> void:
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	
	var push := PackedFloat32Array()
	push.append(_world_origin.x)
	push.append(_world_origin.y)
	push.append(_vertex_spacing.x)
	push.append(_vertex_spacing.y)
	push.append(continental_amplitude)
	push.append(0.0)
	push.append(0.0)
	push.append(0.0)
	
	_rd.compute_list_set_push_constant(compute_list, push.to_byte_array(), push.size() * 4)
	
	var groups_x := ceili(_size.x / 8.0)
	var groups_y := ceili(_size.y / 8.0)
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, _lod_count)
	_rd.compute_list_end()

func get_height_world(world_xz: Vector2) -> float:
	return 0.0

func _free_all_rids() -> void:
	if not _rd:
		return
	if _pipeline_rid:
		_rd.free_rid(_pipeline_rid)
		_pipeline_rid = RID()
	if _uniform_set_rid:
		_rd.free_rid(_uniform_set_rid)
		_uniform_set_rid = RID()
	for rid in _map_rids:
		RenderingServer.free_rid(rid)
	_map_rids.clear()
	for rid in _texture_rd_rids:
		_rd.free_rid(rid)
	_texture_rd_rids.clear()

func _create_uniform(data_format: RenderingDevice.DataFormat) -> RDUniform:
	var format := RDTextureFormat.new()
	format.format = data_format
	format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	format.width = _size.x
	format.height = _size.y
	format.array_layers = _lod_count
	format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_UPDATE_BIT #| \
		#_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT # TODO: needed to get CPU image for collision
	
	var index: int = _texture_rd_rids.size()
	var texture_rid := _rd.texture_create(format, RDTextureView.new())
	_texture_rd_rids.append(texture_rid)
	
	_map_rids.append(RenderingServer.texture_rd_create(texture_rid, RenderingServer.TEXTURE_LAYERED_2D_ARRAY))
	
	var uniform := RDUniform.new()
	uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	uniform.binding = index
	uniform.add_id(texture_rid)
	
	return uniform
