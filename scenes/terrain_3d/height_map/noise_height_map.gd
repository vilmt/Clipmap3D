@tool
class_name NoiseHeightMap extends HeightMap

@export var noise: Noise: set = set_noise

var _image: Image
var _texture: ImageTexture

var _last_origin := Vector2i.ZERO

func set_amplitude(value: float):
	if amplitude == value:
		return
	amplitude = value
	emit_changed()

func set_size(value: Vector2i):
	if size == value:
		return
	size = value
	_create_maps()
	emit_changed()

func set_origin(value: Vector2i):
	if origin == value:
		return
	origin = value
	_shift_maps()
	emit_changed()

func set_noise(value: Noise):
	if noise == value:
		return
	if noise:
		noise.changed.disconnect(_fill_maps)
		
	noise = value
	if noise:
		noise.changed.connect(_fill_maps)
		_create_maps()
	else:
		_dereference_maps()
	
	emit_changed()

func get_image() -> Image:
	return _image

func get_texture() -> ImageTexture:
	return _texture

@warning_ignore_start("integer_division")
func sample(world_position: Vector2, vertex_spacing: Vector2) -> float:
	if not _image:
		return 0.0
	var map_position := Vector2i((world_position / vertex_spacing).round())
	var image_size := _image.get_size()
	var texel := map_position - origin + image_size / 2;
	if not Rect2i(Vector2i.ZERO, image_size).has_point(texel):
		return 0.0
	return _image.get_pixelv(texel).r * amplitude

func _create_maps():
	_image = Image.create_empty(size.x, size.y, true, Image.FORMAT_RF)
		
	_generate_region(Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	_image.generate_mipmaps()
	
	_texture = ImageTexture.create_from_image(_image)
	
	image_changed.emit(_image)
	texture_changed.emit(_texture)

func _dereference_maps():
	_image = null
	_texture = null
	
func _fill_maps():
	_generate_region(Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	_image.generate_mipmaps()
	
	_texture.update(_image)

func _shift_maps():
	var delta := origin - _last_origin
	
	if not delta:
		return
		
	if delta.x >= size.x or delta.y >= size.y:
		_last_origin = origin
		_fill_maps()
		return
	else:
		_last_origin.x = origin.x
		_shift_x(delta.x)
		_last_origin.y = origin.y
		_shift_y(delta.y)

		_image.generate_mipmaps()
		_texture.update(_image)
	
func _shift_x(delta_x: int):
	if delta_x == 0:
		return
	
	var abs_x := absi(delta_x)
	assert(abs_x < size.x)
	
	var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(size.x - abs_x, size.y))
	var destination := Vector2i(maxi(-delta_x, 0), 0)
	
	_image.blit_rect(_image.duplicate(), source_rect, destination)
	
	var image_rect := Rect2i(
		Vector2i(size.x - abs_x if delta_x > 0 else 0, 0),
		Vector2i(abs_x, size.y)
	)
	
	_generate_region(image_rect, image_rect.position)
	
func _shift_y(delta_y: int):
	if delta_y == 0:
		return
	
	var abs_y := absi(delta_y)
	assert(abs_y < size.y)
	
	var source_rect := Rect2i(Vector2i(0, maxi(delta_y, 0)), Vector2i(size.x, size.y - abs_y))
	var destination := Vector2i(0, maxi(-delta_y, 0))
	
	_image.blit_rect(_image.duplicate(), source_rect, destination)
	
	var image_rect := Rect2i(
		Vector2i(0, size.y - abs_y if delta_y > 0 else 0),
		Vector2i(size.x, abs_y)
	)
	
	_generate_region(image_rect, image_rect.position)

func _generate_region(image_rect: Rect2i, world_offset: Vector2i):
	for y: int in image_rect.size.y:
		for x: int in image_rect.size.x:
			var p_local := Vector2i(x, y)
			var p_image := p_local + image_rect.position
			var p_world := p_local + world_offset
			
			var h := noise.get_noise_2dv(_last_origin + p_world) * 0.5 + 0.5
			
			_image.set_pixelv(p_image, Color(h, 0.0, 0.0))
