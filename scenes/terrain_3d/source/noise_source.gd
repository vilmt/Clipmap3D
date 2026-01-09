@tool
class_name Terrain3DNoiseSource extends Terrain3DSource

@export var noise: Noise

var _images: Array[Image]
var _textures: Texture2DArray
var _origins: Array[Vector2i]

func get_images() -> Array[Image]:
	return _images

func get_textures() -> Texture2DArray:
	return _textures

# this will not need changes, only used for lod 0 (collision)
@warning_ignore_start("integer_division")
func sample(world_position: Vector2, amplitude: float, vertex_spacing: Vector2) -> float:
	if _images.is_empty():
		return 0.0
	var map_position := Vector2i((world_position / vertex_spacing).round())
	var image_size := _images[0].get_size()
	var texel := map_position - origin + image_size / 2;
	if not Rect2i(Vector2i.ZERO, image_size).has_point(texel):
		return 0.0
	return _images[0].get_pixelv(texel).r * amplitude

func create_maps(ring_size: Vector2i, lod_count: int):
	# clipmap ring size: 4 * mesh_tile_size + Vector2i.ONE * 2 + skirt
	clear_maps()
	
	for lod: int in lod_count:
		var cell_size := 1 << lod
		_origins.append(Vector2i(floori(origin.x / cell_size), floori(origin.y / cell_size)))
		_images.append(Image.create_empty(ring_size.x, ring_size.y, false, Image.FORMAT_RF))
		_generate_region(lod, Rect2i(Vector2.ZERO, ring_size), Vector2i.ZERO)
	
	_textures = Texture2DArray.new()
	_textures.create_from_images(_images)
	ResourceSaver.save(_textures, "res://texture_2d_array.res", ResourceSaver.FLAG_COMPRESS)

	refreshed.emit()

func clear_maps():
	_images.clear()
	_textures = null
	_origins.clear()
	
func fill_maps():
	pass
	
	#_generate_region(Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	#
	#_height_image.generate_mipmaps()
	#_height_texture.update(_height_image)

func shift_maps():
	print("shifted")

func _generate_region(lod: int, image_rect: Rect2i, world_offset: Vector2i):
	var image_center := _images[lod].get_size() / 2
			
	for y: int in image_rect.size.y:
		for x: int in image_rect.size.x:
			var p_local := Vector2i(x, y)
			var p_image := p_local + image_rect.position
			
			var p_centered := p_local - image_center
			var p_world := (_origins[lod] + p_centered + world_offset) * (1 << lod)
			
			var h := noise.get_noise_2dv(p_world) * 0.5 + 0.5
			
			_images[lod].set_pixelv(p_image, Color(h, 0.0, 0.0))

func _shift_maps():
	pass
	

# NEW
#func shift_maps():
	#if _images.is_empty():
		#return
#
	#for lod: int in _images.size():
		#var cell_size := 1 << lod
	#
		#var new_origin := Vector2i(floori(origin.x / cell_size), floori(origin.y / cell_size))
	#
		#var delta := new_origin - _origins[lod]
		## POSSIBLE OPTIMIZATION: if delta is zero, delta for higher lods is also zero
		#if delta == Vector2i.ZERO:
			#continue
	#
		#_shift_lod(lod, delta, new_origin)
		##_origins[lod] = new_origin
		#_textures.update_layer(_images[lod], lod)
	#
	## TODO: only emit signal when creating new texture array
	#ResourceSaver.save(_textures, "res://texture_2d_array.res", ResourceSaver.FLAG_COMPRESS)
	#refreshed.emit()
#
#func _shift_lod(lod: int, delta: Vector2i, new_origin: Vector2i):
	#var image := _images[lod]
	#var size := image.get_size()
#
	#if absi(delta.x) >= size.x or absi(delta.y) >= size.y:
		#_origins[lod] = new_origin
		#_generate_region(lod, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
		#return
	##print("SHIFT")
	#_origins[lod].x = new_origin.x
	#if delta.x != 0:
		#_shift_lod_x(lod, delta.x)
	#
	#_origins[lod].y = new_origin.y
	#if delta.y != 0:
		#_shift_lod_y(lod, delta.y)
#
#func _shift_lod_x(lod: int, delta_x: int):
	#var image := _images[lod]
	#var size := image.get_size()
	#var abs_x := absi(delta_x)
	#
	#assert(abs_x < size.x)
	#
	#var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(size.x - abs_x, size.y))
	#var destination := Vector2i(maxi(-delta_x, 0), 0)
	#
	#image.blit_rect(image.duplicate(), source_rect, destination)
	#
	#var fill_rect := Rect2i(
		#Vector2i(size.x - abs_x if delta_x > 0 else 0, 0),
		#Vector2i(abs_x, size.y)
	#)
	#
	#_generate_region(lod, fill_rect, fill_rect.position - size / 2)
	#
#func _shift_lod_y(lod: int, delta_y: int):
	#var image := _images[lod]
	#var size := image.get_size()
	#var abs_y := absi(delta_y)
	#
	#assert(abs_y < size.y)
	#
	#var source_rect := Rect2i(Vector2i(0, maxi(delta_y, 0)), Vector2i(size.x, size.y - abs_y))
	#var destination := Vector2i(0, maxi(-delta_y, 0))
	#
	#image.blit_rect(image.duplicate(), source_rect, destination)
	#
	#var fill_rect := Rect2i(
		#Vector2i(0, size.y - abs_y if delta_y > 0 else 0),
		#Vector2i(size.x, abs_y)
	#)
	#
	#_generate_region(lod, fill_rect, fill_rect.position - size / 2)
#
#func _generate_region(lod: int, image_rect: Rect2i, world_offset: Vector2i):
	#var image_center := _images[lod].get_size() / 2
			#
	#for y: int in image_rect.size.y:
		#for x: int in image_rect.size.x:
			#var p_local := Vector2i(x, y)
			#var p_image := p_local + image_rect.position
			#
			#var p_centered := p_local - image_center
			#var p_world := (_origins[lod] + world_offset + p_centered) * (1 << lod)
			#
			#var h := noise.get_noise_2dv(p_world) * 0.5 + 0.5
			#
			#_images[lod].set_pixelv(p_image, Color(h, 0.0, 0.0))
