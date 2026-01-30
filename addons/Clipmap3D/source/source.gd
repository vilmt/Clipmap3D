@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO
#@export var world_offset := Vector2.ZERO

## Defines how many pixels in the generated terrain images correspond to a vertex.
## Higher values mean more normal and control detail.
@export var texels_per_vertex := Vector2i.ONE:
	set(value):
		value = value.maxi(1)
		texels_per_vertex = value
		emit_changed()

@export_range(0.1, 10000.0) var height_amplitude: float = 1000.0:
	set(value):
		height_amplitude = value
		emit_changed()

@export var texture_assets: Array[Clipmap3DTextureAsset]:
	set(value):
		if texture_assets == value:
			return
		texture_assets = value

# TODO: live updating
@export_tool_button("Upload Texture Assets", "Texture2DArray") var upload_textures: Callable = create_textures

const MAX_TEXTURE_COUNT: int = 32

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
	
	func create_placeholder() -> Image:
		if not size:
			return
		placeholder = Image.create_empty(size.x, size.y, has_mipmaps, format)
		return placeholder

var _texture_rids: Dictionary[TextureType, RID]

# TODO: consolidate into single update method and pass to shader
var _albedos: PackedColorArray
var _uv_scales: PackedVector2Array
var _normal_depths: PackedFloat32Array

@warning_ignore_start("unused_signal")
signal textures_changed
signal maps_created
signal maps_shifted

enum TextureType {
	ALBEDO,
	NORMAL
}

enum MapType {
	HEIGHT,
	NORMAL,
	CONTROL
}

const FORMATS: Dictionary[MapType, RenderingDevice.DataFormat] = {
	MapType.HEIGHT: RenderingDevice.DATA_FORMAT_R32_SFLOAT,
	MapType.NORMAL: RenderingDevice.DATA_FORMAT_R16G16_SFLOAT,
	MapType.CONTROL: RenderingDevice.DATA_FORMAT_R32_SFLOAT
}

func create_textures() -> void:
	RenderingServer.call_on_render_thread(_free_textures_threaded)
	RenderingServer.call_on_render_thread(_initialize_textures_threaded)

func _free_textures_threaded() -> void:
	for rid in _texture_rids.values():
		RenderingServer.free_rid(rid)
	_texture_rids.clear()
	
	_albedos.clear()
	_uv_scales.clear()
	_normal_depths.clear()

func _initialize_textures_threaded() -> void:
	if texture_assets.is_empty():
		return
	
	_free_textures_threaded()
	
	_create_texture_layered_threaded(TextureType.ALBEDO)
	_create_texture_layered_threaded(TextureType.NORMAL)
	
	for asset in texture_assets:
		if not asset:
			_normal_depths.append(1.0)
			_uv_scales.append(Vector2.ONE)
			_albedos.append(Color(1.0, 1.0, 1.0))
			continue
		_normal_depths.append(asset.normal_depth)
		_uv_scales.append(asset.uv_scale)
		_albedos.append(asset.albedo_color)
	
	if has_textures():
		textures_changed.emit()

func _create_texture_layered_threaded(type: TextureType):
	var images: Array[Image] = []
	var params: ImageParams = null
	
	for asset in texture_assets:
		if not asset:
			images.append(null)
			continue
		
		var texture := asset.get_texture(type)
		
		if not texture:
			images.append(null)
			continue
		
		var image := texture.get_image()
		
		if params:
			if not params.is_image_valid(image):
				images.append(null)
				continue
		else:
			params = ImageParams.create_from_image(image)
			
		images.append(image)
		
	var null_count: int = images.count(null)
	if null_count == images.size():
		return
	if null_count != 0:
		var placeholder := params.create_placeholder()
		for i: int in images.size():
			if images[i] == null:
				images[i] = placeholder
	_texture_rids[type] = RenderingServer.texture_2d_layered_create(images, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
func get_texture_rids() -> Dictionary[TextureType, RID]:
	return _texture_rids

# HACK
func get_texture_data_arrays() -> Dictionary[String, Array]:
	return {
		"albedos": _albedos,
		"normal_depths": _normal_depths,
		"uv_scales": _uv_scales
	}

func clear_textures() -> void:
	RenderingServer.call_on_render_thread(_free_textures_threaded)

func has_textures() -> bool:
	return not _texture_rids.is_empty()

@abstract
func get_map_origins() -> Array[Vector2i]

@abstract
func create_maps(world_origin: Vector2, size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void

@abstract
func shift_maps(world_origin: Vector2) -> void

@abstract
func clear_maps() -> void

@abstract
func get_map_rids() -> Dictionary[MapType, RID]

@abstract
func has_maps() -> bool

@abstract
func get_height_world(world_xz: Vector2) -> float
