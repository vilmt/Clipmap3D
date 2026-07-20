@tool
class_name Clipmap3DTextureHandler

const MAX_TEXTURE_COUNT: int = 16

var texture_assets: Array[Clipmap3DTextureAsset]:
	set(value):
		if texture_assets:
			for texture_asset: Clipmap3DTextureAsset in texture_assets:
				if not texture_asset:
					continue
				if texture_asset.changed.is_connected(_on_texture_asset_changed):
					texture_asset.changed.disconnect(_on_texture_asset_changed)
		texture_assets = value
		if texture_assets:
			for texture_asset: Clipmap3DTextureAsset in texture_assets:
				if not texture_asset:
					continue
				if not texture_asset.changed.is_connected(_on_texture_asset_changed):
					texture_asset.changed.connect(_on_texture_asset_changed)
		_on_texture_asset_changed()

var material: ShaderMaterial:
	set(value):
		if material == value:
			return
		material = value
		_update_material_parameters()

func build():
	if _built:
		return
	_built = true
	_textures_need_rebuild = true
	_schedule_update()

func clear():
	if not _built:
		return
	_built = false
	_textures_need_rebuild = false
	_clear_textures()

func _schedule_update():
	_update.call_deferred()

func _update():
	_rebuild_textures()

var _built: bool = false

var _textures_need_rebuild: bool = false

var _albedo_textures_rid: RID
var _albedo_remap := PackedInt32Array()
var _normal_textures_rid: RID
var _normal_remap := PackedInt32Array()

var _uv_scales := PackedVector3Array()
var _albedo_modulates := PackedColorArray()
var _roughness_offsets := PackedFloat32Array()
var _normal_depths := PackedFloat32Array()
var _stochastic_offsets := PackedVector3Array()
var _stochastic_rotations := PackedFloat32Array()
var _flags := PackedInt32Array()

func _rebuild_textures():
	if not _textures_need_rebuild:
		return
	
	_clear_textures()
	
	var albedo_parameters: ImageParameters
	var albedo_images: Array[Image] = []
	_albedo_remap.resize(MAX_TEXTURE_COUNT)
	_albedo_remap.fill(-1)
	
	var normal_parameters: ImageParameters
	var normal_images: Array[Image] = []
	_normal_remap.resize(MAX_TEXTURE_COUNT)
	_normal_remap.fill(-1)
	
	_uv_scales.resize(MAX_TEXTURE_COUNT)
	_uv_scales.fill(Clipmap3DTextureAsset.UV_SCALE_DEFAULT)
	
	_albedo_modulates.resize(MAX_TEXTURE_COUNT)
	_albedo_modulates.fill(Clipmap3DTextureAsset.ALBEDO_MODULATE_DEFAULT)
	
	_roughness_offsets.resize(MAX_TEXTURE_COUNT)
	_roughness_offsets.fill(Clipmap3DTextureAsset.ROUGHNESS_OFFSET_DEFAULT)
	
	_normal_depths.resize(MAX_TEXTURE_COUNT)
	_normal_depths.fill(Clipmap3DTextureAsset.NORMAL_DEPTH_DEFAULT)
	
	_stochastic_offsets.resize(MAX_TEXTURE_COUNT)
	_stochastic_offsets.fill(Clipmap3DTextureAsset.STOCHASTIC_OFFSET_DEFAULT)
	
	_stochastic_rotations.resize(MAX_TEXTURE_COUNT)
	_stochastic_rotations.fill(Clipmap3DTextureAsset.STOCHASTIC_ROTATION_DEFAULT)
	
	_flags.resize(MAX_TEXTURE_COUNT)
	_flags.fill(Clipmap3DTextureAsset.FLAGS_DEFAULT)
	
	for i: int in texture_assets.size():
		var texture_asset := texture_assets[i]
		if not texture_asset:
			continue
		
		_uv_scales[i] = texture_asset.uv_scale
		_albedo_modulates[i] = texture_asset.albedo_modulate
		_roughness_offsets[i] = texture_asset.roughness_offset
		_normal_depths[i] = texture_asset.normal_depth
		_stochastic_offsets[i] = texture_asset.stochastic_offset
		_stochastic_rotations[i] = texture_asset.stochastic_rotation
		_flags[i] = texture_asset.flags
		
		if texture_asset.albedo_texture:
			var albedo_image := texture_asset.albedo_texture.get_image()
			var success: bool
			
			if albedo_parameters:
				success = albedo_parameters.matches(albedo_image)
			else:
				albedo_parameters = ImageParameters.create(albedo_image)
				success = true
			
			if success:
				_albedo_remap[i] = albedo_images.size()
				albedo_images.append(albedo_image)
		
		if texture_asset.normal_texture:
			var normal_image := texture_asset.normal_texture.get_image()
			var success: bool
			
			if normal_parameters:
				success = normal_parameters.matches(normal_image)
			else:
				normal_parameters = ImageParameters.create(normal_image)
				success = true
			
			if success:
				_normal_remap[i] = normal_images.size()
				normal_images.append(normal_image)
	
	if not albedo_images.is_empty():
		_albedo_textures_rid = RenderingServer.texture_2d_layered_create(albedo_images, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	if not normal_images.is_empty():
		_normal_textures_rid = RenderingServer.texture_2d_layered_create(normal_images, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	_update_material_parameters()
	
	_textures_need_rebuild = false

func _update_material_parameters():
	if not material:
		return
	material.set_shader_parameter(&"_albedo_textures", _albedo_textures_rid)
	material.set_shader_parameter(&"_albedo_remap", _albedo_remap)
	material.set_shader_parameter(&"_normal_textures", _normal_textures_rid)
	material.set_shader_parameter(&"_normal_remap", _normal_remap)
	material.set_shader_parameter(&"_uv_scales", _uv_scales)
	material.set_shader_parameter(&"_albedo_modulates", _albedo_modulates)
	material.set_shader_parameter(&"_roughness_offsets", _roughness_offsets)
	material.set_shader_parameter(&"_normal_depths", _normal_depths)
	material.set_shader_parameter(&"_stochastic_offsets", _stochastic_offsets)
	material.set_shader_parameter(&"_stochastic_rotations", _stochastic_rotations)
	material.set_shader_parameter(&"_flags", _flags)

func _clear_textures():
	if _albedo_textures_rid.is_valid():
		RenderingServer.free_rid(_albedo_textures_rid)
	_albedo_remap = PackedInt32Array()
	if _normal_textures_rid.is_valid():
		RenderingServer.free_rid(_normal_textures_rid)
	_normal_remap = PackedInt32Array()
	
	_uv_scales = PackedVector3Array()
	_albedo_modulates = PackedColorArray()
	_roughness_offsets = PackedFloat32Array()
	_normal_depths = PackedFloat32Array()
	_stochastic_offsets = PackedVector3Array()
	_stochastic_rotations = PackedFloat32Array()
	_flags = PackedInt32Array()

func _on_texture_asset_changed():
	_textures_need_rebuild = true
	_schedule_update()

#region ImageParameters

class ImageParameters:
	var _format: Image.Format
	var _size: Vector2i
	var _has_mipmaps: bool
	
	static func create(image: Image) -> ImageParameters:
		var parameters := ImageParameters.new()
		parameters._format = image.get_format()
		parameters._size = image.get_size()
		parameters._has_mipmaps = image.has_mipmaps()
		return parameters
	
	func matches(image: Image) -> bool:
		if not image:
			return false
		
		if image.get_format() != _format:
			push_error("Texture asset format mismatch.")
			return false
		if image.get_size() != _size:
			push_error("Texture asset size mismatch.")
			return false
		if image.has_mipmaps() != _has_mipmaps:
			push_error("Texture asset mipmaps enabled mismatch.")
			return false
		
		return true


#endregion
