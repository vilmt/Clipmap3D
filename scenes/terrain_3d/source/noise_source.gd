@tool
class_name Terrain3DNoiseSource extends Terrain3DSource

# TODO: soft refresh signal: textures changed only

@export var noise: Noise

var _images: Array[Image]
var _textures: Texture2DArray
var _origins: Array[Vector2i]

func get_images() -> Array[Image]:
	return _images

func get_textures() -> Texture2DArray:
	return _textures

func get_shader_offsets() -> Array[Vector2i]:
	return _origins

var _image_size: Vector2i

const EPSILON := Vector2.ONE * 10e-5

# this will not need changes, only used for lod 0 (collision)
@warning_ignore_start("integer_division")
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float:
	if _images.is_empty():
		return 0.0
	var map_position := Vector2i((world_position / vertex_spacing + EPSILON).floor())
	var texel := map_position - _origins[0] + _image_size / 2;
	if not Rect2i(Vector2i.ZERO, _image_size).has_point(texel):
		return 0.0
	return _images[0].get_pixelv(texel).r * amplitude

func create_maps(ring_size: Vector2i, lod_count: int):
	_image_size = ring_size
	clear_maps()
	
	for lod: int in lod_count:
		var cell_size := 1 << lod
		_origins.append(Vector2i((origin / cell_size + EPSILON).floor()))
		_images.append(Image.create_empty(_image_size.x, _image_size.y, false, Image.FORMAT_RF))
		_generate_region(lod, Rect2i(Vector2.ZERO, ring_size))
	
	_textures = Texture2DArray.new()
	_textures.create_from_images(_images)
	ResourceSaver.save(_textures, "res://texture_2d_array.res", ResourceSaver.FLAG_COMPRESS)

	refreshed.emit()

func clear_maps():
	_images.clear()
	_textures = null
	_origins.clear()
	
func shift_maps():
	if _images.is_empty():
		return
	#print("shift maps")
	for lod: int in _images.size():
		var cell_size := 1 << lod
		var new_origin := Vector2i((origin / cell_size + EPSILON).floor())
		
		# POSSIBLE OPTIMIZATION: break loop if no shift
		if _try_shift_lod(lod, new_origin):
			_textures.update_layer(_images[lod], lod)
	
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
			
			var h := noise.get_noise_2dv(p_world) * 0.5 + 0.5
			h *= h
			
			_images[lod].set_pixelv(p_image, Color(h, 0.0, 0.0))

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
	var image := _images[lod]
	var abs_x := absi(delta_x)
	
	assert(abs_x < _image_size.x)
	
	var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(_image_size.x - abs_x, _image_size.y))
	var destination := Vector2i(maxi(-delta_x, 0), 0)
	
	image.blit_rect(image.duplicate(), source_rect, destination)
	
	var fill_rect := Rect2i(
		Vector2i(_image_size.x - abs_x if delta_x > 0 else 0, 0),
		Vector2i(abs_x, _image_size.y)
	)
	
	_generate_region(lod, fill_rect)
	
func _shift_lod_y(lod: int, delta_y: int):
	var image := _images[lod]
	var abs_y := absi(delta_y)
	
	assert(abs_y < _image_size.y)
	
	var source_rect := Rect2i(Vector2i(0, maxi(delta_y, 0)), Vector2i(_image_size.x, _image_size.y - abs_y))
	var destination := Vector2i(0, maxi(-delta_y, 0))
	
	image.blit_rect(image.duplicate(), source_rect, destination)
	
	var fill_rect := Rect2i(
		Vector2i(0, _image_size.y - abs_y if delta_y > 0 else 0),
		Vector2i(_image_size.x, abs_y)
	)
	
	_generate_region(lod, fill_rect)
