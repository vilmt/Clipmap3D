extends Node3D

@export_file_path("*.glsl") var shader_path: String
@export var shader_material: ShaderMaterial
@export var image_size := Vector2i(512, 512)
@export var lod_count: int = 5

const HEIGHT_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT
const NORMAL_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
const CONTROL_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT

var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID

var _texture_rd_rids: Array[RID]
var _map_rids: Array[RID]

var _uniform_set_rid: RID

var _start_time: int
@onready var label: Label = $Label

func _ready() -> void:
	RenderingServer.call_on_render_thread(_initialize)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("compute"):
		RenderingServer.call_on_render_thread(_compute)

func _exit_tree():
	RenderingServer.call_on_render_thread(_free_all_rids)

func _initialize() -> void:
	_rd = RenderingServer.get_rendering_device()
	
	_shader_rid = _load_shader(shader_path)
	
	var uniforms: Array[RDUniform] = []
	
	for format in [HEIGHT_FORMAT, NORMAL_FORMAT, CONTROL_FORMAT]:
		uniforms.append(_create_uniform(format))
	
	_uniform_set_rid = _rd.uniform_set_create(uniforms, _shader_rid, 0)
	
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	
	_compute()

func _compute() -> void:
	_start_time = Time.get_ticks_usec()
	
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	
	var push := PackedFloat32Array()
	push.append((sin(_start_time) * 0.5 + 0.6) * 50.0)
	push.append(0.0)
	push.append(0.0)
	push.append(0.0)
	
	_rd.compute_list_set_push_constant(compute_list, push.to_byte_array(), push.size() * 4)
	
	var groups_x := ceili(image_size.x / 8.0)
	var groups_y := ceili(image_size.y / 8.0)
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, lod_count)
	_rd.compute_list_end()
	
	_free_runtime_rids()
		
	for texture_rd_rid in _texture_rd_rids:
		_map_rids.append(RenderingServer.texture_rd_create(texture_rd_rid, RenderingServer.TEXTURE_LAYERED_2D_ARRAY))
	
	#print("computed again")
	
	if shader_material:
		var material_rid := shader_material.get_rid()
		RenderingServer.material_set_param(material_rid, &"_height_maps", _map_rids[0])
		RenderingServer.material_set_param(material_rid, &"_normal_maps", _map_rids[1])
		RenderingServer.material_set_param(material_rid, &"_control_maps", _map_rids[2])
	
	var elapsed: int = Time.get_ticks_usec() - _start_time
	label.text = "%s ms" % str(elapsed * 0.001).pad_decimals(1)

func _free_runtime_rids() -> void:
	for rid in _map_rids:
		RenderingServer.free_rid(rid)
	_map_rids.clear()

func _free_all_rids() -> void:
	_free_runtime_rids()
	
	_rd.free_rid(_pipeline_rid)
	_rd.free_rid(_uniform_set_rid)
	_rd.free_rid(_shader_rid)
	for rid in _texture_rd_rids:
		_rd.free_rid(rid)
	_rd.free()
	
	_pipeline_rid = RID()
	_uniform_set_rid = RID()
	_shader_rid = RID()
	_texture_rd_rids.clear()
	_rd = null

func _load_shader(path: String) -> RID:
	var shader_file_data: RDShaderFile = load(path)
	var shader_spirv: RDShaderSPIRV = shader_file_data.get_spirv()
	return _rd.shader_create_from_spirv(shader_spirv)

func _create_uniform(data_format: RenderingDevice.DataFormat) -> RDUniform:
	var format := RDTextureFormat.new()
	format.format = data_format
	format.texture_type = _rd.TEXTURE_TYPE_2D_ARRAY
	format.width = image_size.x
	format.height = image_size.y
	format.array_layers = lod_count
	format.usage_bits = \
		_rd.TEXTURE_USAGE_SAMPLING_BIT | \
		_rd.TEXTURE_USAGE_STORAGE_BIT | \
		_rd.TEXTURE_USAGE_CAN_UPDATE_BIT #| \
		#_rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var index: int = _texture_rd_rids.size()
	var texture_rid := _rd.texture_create(format, RDTextureView.new())
	_texture_rd_rids.append(texture_rid)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = _rd.UNIFORM_TYPE_IMAGE
	uniform.binding = index
	uniform.add_id(texture_rid)
	
	return uniform
