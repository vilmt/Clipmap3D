@tool
class_name Clipmap3DNoiseSource extends Clipmap3DSource

@export var continental_noise: Noise:
	set(value):
		if continental_noise == value:
			return
		if continental_noise:
			continental_noise.changed.disconnect(parameters_changed.emit)
		continental_noise = value
		if continental_noise:
			continental_noise.changed.connect(parameters_changed.emit)
		parameters_changed.emit()

@export var continental_amplitude: float:
	set(value):
		if continental_amplitude == value:
			return
		continental_amplitude = value
		amplitude_changed.emit(get_height_amplitude())

#@export var mountain_noise: Noise
#@export var ridge_noise: Noise

var _image_size: Vector2i
var _vertex_spacing: Vector2
var _height_images: Array[Image] = []
var _control_images: Array[Image] = []
var _height_textures: Texture2DArray
var _control_textures: Texture2DArray
var _origins: Array[Vector2i]
var _inv_scales: Array[Vector2]

func has_maps() -> bool:
	return _height_textures and _control_textures

func get_height_maps() -> Texture2DArray:
	return _height_textures

func get_control_maps() -> Texture2DArray:
	return _control_textures

func get_height_amplitude():
	return continental_amplitude

@warning_ignore_start("integer_division")
func get_height_world(world_xz: Vector2) -> float:
	if _height_images.is_empty():
		return 0.0
	var lod_cell := Vector2i((world_xz * _inv_scales[0]).floor())
	var texel := lod_cell - _origins[0] + _image_size / 2;
	if not Rect2i(Vector2i.ZERO, _image_size).has_point(texel):
		return 0.0
	return _height_images[0].get_pixelv(texel).r

# TODO: biome modifiers
func get_height_local(local_xz: Vector2i):
	if not continental_noise:
		return 0.0
	var c := continental_noise.get_noise_2dv(local_xz) * 0.5 + 0.5
	c = c * c * continental_amplitude
	return c

func create_maps(image_size: Vector2i, lod_count: int, vertex_spacing: Vector2):
	clear_maps()
	_image_size = image_size
	_vertex_spacing = _vertex_spacing
	
	_origins.resize(lod_count)
	_inv_scales.resize(lod_count)
	_height_images.resize(lod_count)
	_control_images.resize(lod_count)
	
	for lod: int in lod_count:
		_inv_scales[lod] = Vector2.ONE * pow(2.0, -lod) / vertex_spacing
		_origins[lod] = Vector2i((origin * _inv_scales[lod]).floor())
		
		_height_images[lod] = Image.create_empty(_image_size.x, _image_size.y, false, Image.FORMAT_RF)
		_control_images[lod] = Image.create_empty(_image_size.x, _image_size.y, false, Image.FORMAT_RF)
		_generate_region(lod, Rect2i(Vector2.ZERO, _image_size))
	
	_height_textures = Texture2DArray.new()
	_height_textures.create_from_images(_height_images)
	_control_textures = Texture2DArray.new()
	_control_textures.create_from_images(_control_images)
	
	maps_created.emit()

func clear_maps():
	_height_images.clear()
	_height_textures = null
	_control_images.clear()
	_control_textures = null
	_origins.clear()
	_inv_scales.clear()

func shift_maps():
	if _height_images.is_empty():
		push_error("Attempted image shift without creating first.")
		return
	
	var dirty: bool = false
	
	for lod: int in _height_images.size():
		var new_origin := Vector2i((origin * _inv_scales[lod]).floor())
		
		if _try_shift_lod(lod, new_origin):
			_height_textures.update_layer(_height_images[lod], lod)
			_control_textures.update_layer(_control_images[lod], lod)
			dirty = true
	
	if dirty:
		maps_redrawn.emit()

# TODO: use previous lod samples now that they get more expensive, 25% cheaper
# TODO: unify logic with shader transformations, could use Vector2 instead
func _generate_region(lod: int, image_rect: Rect2i):
	var image_center := _image_size / 2
	
	for y: int in image_rect.size.y:
		for x: int in image_rect.size.x:
			var image_p := Vector2i(x, y) + image_rect.position
			var centered_p := image_p - image_center
			var local_xz := (_origins[lod] + centered_p) * (1 << lod)
			
			#_control_images[lod].set_pixelv(image_p, Color(get_control_local(local_xz), 0.0, 0.0))
			_height_images[lod].set_pixelv(image_p, Color(get_height_local(local_xz), 0.0, 0.0))
			

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
