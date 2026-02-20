@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO
#@export var world_offset := Vector2.ZERO

## Defines how many pixels in the generated terrain images correspond to a vertex.
## Higher values mean more normal and control detail.
@export var texels_per_vertex := Vector2i.ONE:
	set(value):
		texels_per_vertex = value.maxi(1)
		_mark_maps_dirty()

@export_range(0.1, 10000.0) var height_amplitude: float = 1000.0:
	set(value):
		height_amplitude = value
		_mark_maps_dirty()

@export var texture_assets: Array[Clipmap3DTextureAsset]:
	set(value):
		if texture_assets == value:
			return
		texture_assets = value
		_mark_textures_dirty()

@export_tool_button("Submit Texture Assets", "Texture2DArray") var submit: Callable = _mark_textures_dirty

# TODO: live updating
#@export_tool_button("Upload Texture Assets", "Texture2DArray") var upload_textures: Callable = create_textures

var size: Vector2i:
	set(value):
		size = value
		_mark_maps_dirty()

var lod_count: int:
	set(value):
		lod_count = value
		_mark_maps_dirty()

var vertex_spacing: Vector2:
	set(value):
		vertex_spacing = value
		_mark_maps_dirty()

var world_origin: Vector2:
	set(value):
		world_origin = value
		_try_shift_maps()

# TODO: clean this up
var collision_enabled: bool = true

const MAX_TEXTURE_COUNT: int = 32

# TODO: remove this, simple enough to write in loop
class ImageParams:
	var format: Image.Format
	var size: Vector2i
	var has_mipmaps: bool
	var placeholder: Image
	
	static func create_from_image(image: Image) -> ImageParams:
		if not image:
			return null
		var image_params := ImageParams.new()
		image_params.format = image.get_format()
		image_params.size = image.get_size()
		image_params.has_mipmaps = image.has_mipmaps()
		return image_params
	
	func is_image_valid(image: Image) -> bool:
		if not image:
			return false
		if image.get_format() != format:
			push_error("Texture asset format mismatch.")
			return false
		if image.get_size() != size:
			push_error("Texture size mismatch.")
			return false
		if image.has_mipmaps() != has_mipmaps:
			push_error("Texture mipmap enable mismatch.")
			return false
		return true

var _maps_dirty: bool = true
var _textures_dirty: bool = true

var _texture_rids: Dictionary[TextureType, RID]
var _texture_remaps: Dictionary[TextureType, PackedInt32Array]

var _uv_scales: PackedVector2Array
var _albedo_modulates: PackedColorArray
var _roughness_offsets: PackedFloat32Array
var _normal_depths: PackedFloat32Array
var _flags: PackedInt32Array

signal textures_created
signal textures_updated

@warning_ignore_start("unused_signal")
signal maps_created
signal maps_updated

signal collision_data_changed

enum TextureType {
	ALBEDO,
	NORMAL
}

enum MapType {
	HEIGHT,
	GRADIENT,
	CONTROL
}

const FORMATS: Dictionary[MapType, RenderingDevice.DataFormat] = {
	MapType.HEIGHT: RenderingDevice.DATA_FORMAT_R32_SFLOAT,
	MapType.GRADIENT: RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,
	MapType.CONTROL: RenderingDevice.DATA_FORMAT_R32_SFLOAT
}

var _built: bool = false

func build() -> void:
	_built = true
	_mark_textures_dirty()
	_mark_maps_dirty()

func clear() -> void:
	_built = false
	_textures_dirty = false
	_maps_dirty = false
	_free_textures()
	_free_maps()
	clear_debug_canvas_items()

func get_texture_rids() -> Dictionary[TextureType, RID]:
	return _texture_rids

func has_textures() -> bool:
	return not _texture_rids.is_empty()

func get_texture_remaps() -> Dictionary[TextureType, PackedInt32Array]:
	return _texture_remaps

func get_uv_scales() -> PackedVector2Array:
	return _uv_scales
	
func get_albedo_modulates() -> PackedColorArray:
	return _albedo_modulates
	
func get_roughness_offsets() -> PackedFloat32Array:
	return _roughness_offsets

func get_normal_depths() -> PackedFloat32Array:
	return _normal_depths

func get_flags() -> PackedInt32Array:
	return _flags

@abstract
func get_map_rids() -> Dictionary[MapType, RID]

@abstract
func has_maps() -> bool

@abstract
func get_world_origin(lod: int) -> Vector2

@abstract
func get_texel_origin(lod: int) -> Vector2i

@abstract
func get_heightmap_data(mesh_size: Vector2i) -> Dictionary

func _mark_textures_dirty():
	if not _built:
		return
	_textures_dirty = true
	_build_textures.call_deferred()

func _mark_maps_dirty():
	if not _built:
		return
	_maps_dirty = true
	_build_maps.call_deferred()

@abstract
func _build_maps() -> void

@abstract
func _try_shift_maps() -> void

@abstract
func _free_maps() -> void

@abstract
func create_debug_canvas_items(parent_node: CanvasItem)

@abstract
func clear_debug_canvas_items()

func _build_textures() -> void:
	if not _textures_dirty:
		return
	_textures_dirty = false
	_free_textures()
	
	_create_texture_layered(TextureType.ALBEDO)
	_create_texture_layered(TextureType.NORMAL)
	
	_uv_scales.resize(MAX_TEXTURE_COUNT)
	_albedo_modulates.resize(MAX_TEXTURE_COUNT)
	_roughness_offsets.resize(MAX_TEXTURE_COUNT)
	_normal_depths.resize(MAX_TEXTURE_COUNT)
	_flags.resize(MAX_TEXTURE_COUNT)
	
	_uv_scales.fill(Clipmap3DTextureAsset.UV_SCALE_DEFAULT)
	_albedo_modulates.fill(Clipmap3DTextureAsset.ALBEDO_MODULATE_DEFAULT)
	_roughness_offsets.fill(Clipmap3DTextureAsset.ROUGHNESS_OFFSET_DEFAULT)
	_normal_depths.fill(Clipmap3DTextureAsset.NORMAL_DEPTH_DEFAULT)
	_flags.fill(Clipmap3DTextureAsset.FLAGS_DEFAULT)
	
	for i: int in texture_assets.size():
		var asset := texture_assets[i]
		if not asset:
			continue
		
		_uv_scales[i] = asset.uv_scale
		_albedo_modulates[i] = asset.albedo_modulate
		_roughness_offsets[i] = asset.roughness_offset
		_normal_depths[i] = asset.normal_depth
		_flags[i] = asset.flags
	
	textures_created.emit()
	emit_changed()

func _free_textures() -> void:
	for rid in _texture_rids.values():
		RenderingServer.free_rid(rid)
	_texture_rids.clear()
	_texture_remaps.clear()
	
	_uv_scales.clear()
	_albedo_modulates.clear()
	_roughness_offsets.clear()
	_normal_depths.clear()
	_flags.clear()

func _create_texture_layered(type: TextureType):
	var images: Array[Image] = []
	var params: ImageParams = null
	
	var remap := PackedInt32Array()
	remap.resize(MAX_TEXTURE_COUNT)
	remap.fill(-1)
	
	var packed_index := 0
	
	for i: int in texture_assets.size():
		var asset := texture_assets[i]
		if not asset:
			continue
		
		var texture := asset.get_texture(type)
		
		if not texture:
			continue
		
		var image := texture.get_image()
		
		if params:
			if not params.is_image_valid(image):
				continue
		else:
			params = ImageParams.create_from_image(image)
			
		images.append(image)
		remap[i] = packed_index
		packed_index += 1
	
	_texture_remaps[type] = remap
	
	if images.is_empty():
		_texture_rids[type] = RID()
	else:
		_texture_rids[type] = RenderingServer.texture_2d_layered_create(images, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
