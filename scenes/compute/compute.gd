extends Node3D

@export_file_path("*.glsl") var shader_path: String
@export var shader_material: ShaderMaterial
@export var image_size := Vector2i(512, 512)
@export var lod_count: int = 5

const HEIGHT_FORMAT := RenderingDevice.DATA_FORMAT_R32_SFLOAT

# TODO: these formats are unsupported
const NORMAL_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_SNORM
const CONTROL_FORMAT := RenderingDevice.DATA_FORMAT_R32_UINT

var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID

var _texture_rd_rids: Array[RID]
var _map_rids: Array[RID]

var _uniform_set_rid: RID

func _ready() -> void:
	RenderingServer.call_on_render_thread(_initialize)

func _exit_tree():
	RenderingServer.call_on_render_thread(_free_rids)

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
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set_rid, 0)
	var groups_x := ceili(image_size.x / 8.0)
	var groups_y := ceili(image_size.y / 8.0)
	_rd.compute_list_dispatch(compute_list, groups_x, groups_y, lod_count)
	_rd.compute_list_end()
	
	for texture_rd_rid in _texture_rd_rids:
		_map_rids.append(RenderingServer.texture_rd_create(texture_rd_rid, RenderingServer.TEXTURE_LAYERED_2D_ARRAY))
	
	if shader_material:
		var material_rid := shader_material.get_rid()
		RenderingServer.material_set_param(material_rid, &"_height_maps", _map_rids[0])
		RenderingServer.material_set_param(material_rid, &"_normal_maps", _map_rids[1])
		RenderingServer.material_set_param(material_rid, &"_control_maps", _map_rids[2])

func _free_rids() -> void:
	_rd.free_rid(_pipeline_rid)
	_rd.free_rid(_uniform_set_rid)
	_rd.free_rid(_shader_rid)
	for rid in _map_rids + _texture_rd_rids:
		_rd.free_rid(rid)
	_rd.free()

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
