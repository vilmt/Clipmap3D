@tool
class_name Clipmap3DNoiseSource extends Clipmap3DSource

# TODO: soft refresh signal: textures changed only

@export var noise: Noise

@export var biome_noise: Noise

var _height_images: Array[Image] = []
var _control_images: Array[Image] = []
var _height_textures: Texture2DArray
var _control_textures: Texture2DArray
var _origins: Array[Vector2i]

func has_maps() -> bool:
	return _height_textures and _control_textures

func get_height_images() -> Array[Image]:
	return _height_images

func get_height_texture_array() -> Texture2DArray:
	return _height_textures

func get_control_texture_array() -> Texture2DArray:
	return _control_textures
	
var _image_size: Vector2i

#const EPSILON := Vector2.ONE * 10e-5

func get_height_local():
	pass

func get_height_world(p_world: Vector2i) -> float:
	if not noise:
		return 0.0
	var h := noise.get_noise_2dv(p_world) * 0.5 + 0.5
	h *= h
	return h

func get_control_world(p_world: Vector2i) -> float:
	if not biome_noise:
		return 0.0
	return biome_noise.get_noise_2dv(p_world)

@warning_ignore_start("integer_division")
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float:
	if _height_images.is_empty():
		return 0.0
	var map_position := Vector2i((world_position / vertex_spacing).floor())
	var texel := map_position - _origins[0] + _image_size / 2;
	if not Rect2i(Vector2i.ZERO, _image_size).has_point(texel):
		return 0.0
	return _height_images[0].get_pixelv(texel).r * amplitude

func create_maps(ring_size: Vector2i, lod_count: int):
	_image_size = ring_size
	clear_maps()
	
	for lod: int in lod_count:
		var cell_size := 1 << lod
		_origins.append(Vector2i((origin / cell_size).floor()))
		_height_images.append(Image.create_empty(_image_size.x, _image_size.y, false, Image.FORMAT_RF))
		_control_images.append(Image.create_empty(_image_size.x, _image_size.y, false, Image.FORMAT_RF))
		_generate_region(lod, Rect2i(Vector2.ZERO, ring_size))
	
	_height_textures = Texture2DArray.new()
	_height_textures.create_from_images(_height_images)
	_control_textures = Texture2DArray.new()
	_control_textures.create_from_images(_control_images)
	
	refreshed.emit()

func clear_maps():
	_height_images.clear()
	_height_textures = null
	_control_images.clear()
	_control_textures = null
	_origins.clear()

func shift_maps():
	if _height_images.is_empty():
		push_error("Attempted image shift without creating first.")
		return
	
	for lod: int in _height_images.size():
		var cell_size := 1 << lod
		var new_origin := Vector2i((origin / cell_size).floor())
		
		if _try_shift_lod(lod, new_origin):
			_height_textures.update_layer(_height_images[lod], lod)
			_control_textures.update_layer(_control_images[lod], lod)
	
	refreshed.emit()

# TODO: unify logic with shader transformations
func _generate_region(lod: int, image_rect: Rect2i):
	var image_center := _image_size / 2
	
	for y: int in image_rect.size.y:
		for x: int in image_rect.size.x:
			var p_local := Vector2i(x, y)
			var p_image := p_local + image_rect.position
			
			var p_centered := p_image - image_center
			var p_world := (_origins[lod] + p_centered) * (1 << lod)
			
			#var h := noise.get_noise_2dv(p_world) * 0.5 + 0.5
			#h *= h
			
			_height_images[lod].set_pixelv(p_image, Color(get_height_world(p_world), 0.0, 0.0))
			_control_images[lod].set_pixelv(p_image, Color(get_control_world(p_world), 0.0, 0.0))

func _try_shift_lod(lod: int, new_origin: Vector2i) -> bool:
	var delta := new_origin - _origins[lod]
	
	if delta == Vector2i.ZERO:
		return false

	if absi(delta.x) >= _image_size.x or absi(delta.y) >= _image_size.y:
		_origins[lod] = new_origin
		_generate_region(lod, Rect2i(Vector2i.ZERO, _image_size))
		return true
	
	if delta.x != 0:
		_origins[lod].x = new_origin.x
		_shift_lod_x(lod, delta.x)
	if delta.y != 0:
		_origins[lod].y = new_origin.y
		_shift_lod_y(lod, delta.y)
	
	return true

func _shift_lod_x(lod: int, delta_x: int):
	var abs_x := absi(delta_x)
	
	assert(abs_x < _image_size.x)
	
	var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(_image_size.x - abs_x, _image_size.y))
	var destination := Vector2i(maxi(-delta_x, 0), 0)
	
	# TODO: try not duplicating
	_height_images[lod].blit_rect(_height_images[lod].duplicate(), source_rect, destination)
	_control_images[lod].blit_rect(_control_images[lod].duplicate(), source_rect, destination)
	
	var fill_rect := Rect2i(
		Vector2i(_image_size.x - abs_x if delta_x > 0 else 0, 0),
		Vector2i(abs_x, _image_size.y)
	)
	
	_generate_region(lod, fill_rect)
	
func _shift_lod_y(lod: int, delta_y: int):
	var abs_y := absi(delta_y)
	
	assert(abs_y < _image_size.y)
	
	var source_rect := Rect2i(Vector2i(0, maxi(delta_y, 0)), Vector2i(_image_size.x, _image_size.y - abs_y))
	var destination := Vector2i(0, maxi(-delta_y, 0))
	
	_height_images[lod].blit_rect(_height_images[lod].duplicate(), source_rect, destination)
	_control_images[lod].blit_rect(_control_images[lod].duplicate(), source_rect, destination)
	
	var fill_rect := Rect2i(
		Vector2i(0, _image_size.y - abs_y if delta_y > 0 else 0),
		Vector2i(_image_size.x, abs_y)
	)
	
	_generate_region(lod, fill_rect)
