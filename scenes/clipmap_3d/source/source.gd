@tool
@abstract
class_name Clipmap3DSource extends Resource

# TODO
@export var world_offset := Vector2.ZERO

# TODO: if size of array does not change, update rid instead of remaking
# TODO: connect each asset using id for partial updates
@export var texture_assets: Array[Clipmap3DTextureAsset]:
	set(value):
		if texture_assets == value:
			return
		texture_assets = value

@export_tool_button("Submit Texture Assets") var submit_textures: Callable = create_textures

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
			push_error("Texture asset format mismatch. Ensure all .")
			return false
		if image.get_size() != size:
			push_error("Texture size mismatch. Ensure all .")
			return false
		if image.has_mipmaps() != has_mipmaps:
			push_error("Texture mipmap enable mismatch. Ensure all .")
			return false
		return true
	
	func create_placeholder() -> Image:
		if not size:
			return
		placeholder = Image.create_empty(size.x, size.y, has_mipmaps, format)
		return placeholder

var _texture_rids: Dictionary[TextureType, RID]
#
#func _connect_texture_assets():
	#for i: int in texture_assets.size():
		#var texture_asset := texture_assets[i]
		#if not texture_asset or texture_asset.changed.is_connected(_update_texture_asset):
			#continue
		#texture_asset.changed.connect(_update_texture_asset.bind(i))
#
#func _disconnect_texture_assets():
	#for i: int in texture_assets.size():
		#var texture_asset := texture_assets[i]
		#if not texture_asset or not texture_asset.changed.is_connected(_update_texture_asset):
			#continue
		#texture_asset.changed.disconnect(_update_texture_asset)
#
#func _update_texture_asset(i: int):
	#assert(i < _texture_assets_size)
	#var texture_asset := texture_assets[i]
	#for type: TextureType in [TextureType.ALBEDO, TextureType.NORMAL]:
		#var image: Image = null
		#var texture := texture_asset.get_texture(type)
		#if texture:
			#image = texture.get_image()
			#
		#if _image_params.has(type) and _image_params[type].is_image_valid(image):
			#RenderingServer.texture_2d_update(_texture_rids[type], image, i)
	#
	
@warning_ignore_start("unused_signal")
signal textures_changed
signal maps_created
signal maps_redrawn

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



# TODO: pass error strings

func create_textures() -> void:
	RenderingServer.call_on_render_thread(_free_textures_threaded)
	RenderingServer.call_on_render_thread(_initialize_textures_threaded)

func _free_textures_threaded() -> void:
	for rid in _texture_rids.values():
		RenderingServer.free_rid(rid)
	_texture_rids.clear()

func _initialize_textures_threaded() -> void:
	if texture_assets.is_empty():
		return
	
	_free_textures_threaded()
	
	_create_texture_layered(TextureType.ALBEDO)
	_create_texture_layered(TextureType.NORMAL)
	
	if has_textures():
		textures_changed.emit()

func _create_texture_layered(type: TextureType):
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

func clear_textures() -> void:
	RenderingServer.call_on_render_thread(_free_textures_threaded)

func has_textures() -> bool:
	return not _texture_rids.is_empty()

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

@abstract
func get_height_amplitude() -> float
