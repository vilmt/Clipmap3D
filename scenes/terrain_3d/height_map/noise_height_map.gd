@tool
class_name NoiseHeightMap extends HeightMap

@export var noise: Noise: set = set_noise

@export var enable_normal: bool = true: set = set_enable_normal

var _height_image: Image
var _normal_image: Image
var _height_texture: ImageTexture
var _normal_texture: ImageTexture

var _last_origin := Vector2i.ZERO

# NOTE: we just set a bunch of shit from the export variables simultaneously, probably slow and dangerous

func set_amplitude(value: float):
	if amplitude == value:
		return
	amplitude = value
	if enable_normal:
		_fill_maps()
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

func set_enable_normal(value: bool):
	if enable_normal == value:
		return
	enable_normal = value
	_dereference_maps()
	_create_maps()
	emit_changed()

func get_image() -> Image:
	return _height_image

func get_texture() -> ImageTexture:
	return _height_texture

func get_normal_texture() -> ImageTexture:
	return _normal_texture

@warning_ignore_start("integer_division")
func sample(world_position: Vector2, vertex_spacing: Vector2) -> float:
	if not _height_image:
		return 0.0
	var map_position := Vector2i((world_position / vertex_spacing).round())
	var image_size := _height_image.get_size()
	var texel := map_position - origin + image_size / 2;
	if not Rect2i(Vector2i.ZERO, image_size).has_point(texel):
		return 0.0
	return _height_image.get_pixelv(texel).r * amplitude

func sample_normal(world_position: Vector2, vertex_spacing: Vector2) -> Color:
	return Color()

func _create_maps():
	_height_image = Image.create_empty(size.x, size.y, true, Image.FORMAT_RF)
	if enable_normal:
		_normal_image = Image.create_empty(size.x, size.y, true, Image.FORMAT_RGB8)
		
	_generate_region(Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	
	_height_image.generate_mipmaps()
	_height_texture = ImageTexture.create_from_image(_height_image)
	if enable_normal:
		_normal_image.generate_mipmaps()
		_normal_texture = ImageTexture.create_from_image(_normal_image)

func _dereference_maps():
	_height_image = null
	_height_texture = null
	_normal_image = null
	_normal_texture = null
	
func _fill_maps():
	_generate_region(Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	
	_height_image.generate_mipmaps()
	_height_texture.update(_height_image)
	if enable_normal:
		_normal_image.generate_mipmaps()
		_normal_texture.update(_normal_image)

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

		_height_image.generate_mipmaps()
		_height_texture.update(_height_image)
		if enable_normal:
			_normal_image.generate_mipmaps()
			_normal_texture.update(_normal_image)
	
func _shift_x(delta_x: int):
	if delta_x == 0:
		return
	
	var abs_x := absi(delta_x)
	assert(abs_x < size.x)
	
	var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(size.x - abs_x, size.y))
	var destination := Vector2i(maxi(-delta_x, 0), 0)
	
	_height_image.blit_rect(_height_image.duplicate(), source_rect, destination)
	if enable_normal:
		_normal_image.blit_rect(_normal_image.duplicate(), source_rect, destination)
	
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
	
	_height_image.blit_rect(_height_image.duplicate(), source_rect, destination)
	if enable_normal:
		_normal_image.blit_rect(_normal_image.duplicate(), source_rect, destination)
	
	var image_rect := Rect2i(
		Vector2i(0, size.y - abs_y if delta_y > 0 else 0),
		Vector2i(size.x, abs_y)
	)
	
	_generate_region(image_rect, image_rect.position)

#func _generate_region(image_rect: Rect2i, world_offset: Vector2i):
	#for y: int in image_rect.size.y:
		#for x: int in image_rect.size.x:
			#var p_local := Vector2i(x, y)
			#var p_image := p_local + image_rect.position
			#var p_world := p_local + world_offset
			#
			#var h := noise.get_noise_2dv(_last_origin + p_world) * 0.5 + 0.5
			#
			#_height_image.set_pixelv(p_image, Color(h, 0.0, 0.0))

func _generate_region(image_rect: Rect2i, world_offset: Vector2i):
	var skirt := Vector2i.ZERO
	if enable_normal:
		skirt = Vector2i.ONE
	
	var strip_size := image_rect.size
	var full_size := strip_size + skirt * 2
	
	var heights := PackedFloat32Array()
	heights.resize(full_size.x * full_size.y)
	
	for s_y: int in full_size.y:
		for s_x: int in full_size.x:
			var s := Vector2i(s_x, s_y)
			var p_local := s - skirt
			var p_image := p_local + image_rect.position
			var p_world := p_local + world_offset
			
			var h := noise.get_noise_2dv(_last_origin + p_world) * 0.5 + 0.5
			heights[s_y * full_size.x + s_x] = h
			
			if image_rect.has_point(p_image):
				_height_image.set_pixelv(p_image, Color(h, 0.0, 0.0))
	
	if not enable_normal:
		return
	
	for y: int in strip_size.y:
		for x: int in strip_size.x:
			var p_image := Vector2i(x, y) + image_rect.position
			var s := Vector2i(x, y) + skirt
			
			var l := heights[s.y * full_size.x + (s.x - 1)]
			var r := heights[s.y * full_size.x + (s.x + 1)]
			var d := heights[(s.y - 1) * full_size.x + s.x]
			var u := heights[(s.y + 1) * full_size.x + s.x]
			
			# TODO: scale normals in shader or smth
			var dx := amplitude * (r - l) * 0.5
			var dz := amplitude * (u - d) * 0.5
			
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normal = (normal + Vector3.ONE) * 0.5
			
			_normal_image.set_pixelv(p_image, Color(normal.x, normal.y, normal.z))
