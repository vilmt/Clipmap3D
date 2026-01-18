@tool
@abstract
class_name Clipmap3DSource extends Resource

@export var origin := Vector2.ZERO:
	set(value):
		if origin == value:
			return
		origin = value
		origin_changed.emit(origin)

@export var biomes: Array[Biome]:
	set(value):
		_disconnect_biomes()
		biomes = value
		_connect_biomes()

@warning_ignore_start("unused_signal")
signal parameters_changed
signal origin_changed(new_origin: Vector2)
signal amplitude_changed(new_amplitude: float)
signal texture_arrays_created
signal texture_arrays_changed
signal maps_created
signal maps_redrawn

var _albedo_textures: Texture2DArray
var _normal_textures: Texture2DArray

var _texture_registry: Dictionary[Texture2D, int]

func _connect_biomes():
	for biome in biomes:
		if not biome:
			continue
		biome.textures_changed.connect(_on_biome_textures_changed)
		biome.parameters_changed.connect(_on_biome_parameters_changed)

func _disconnect_biomes():
	for biome in biomes:
		if not biome:
			continue
		biome.textures_changed.disconnect(_on_biome_textures_changed)
		biome.parameters_changed.disconnect(_on_biome_parameters_changed)

func _rebuild_texture_registry():
	_texture_registry.clear()

	var albedo_textures: Array[Texture2D] = []
	var normal_textures: Array[Texture2D] = []

	for biome in biomes:
		var a := biome.get_albedo_textures()
		var n := biome.get_normal_textures()
		
		n.resize(a.size())
		
		for i in a.size():
			var albedo := a[i]
			var normal := n[i]
			if not albedo or not normal or _texture_registry.has(albedo):
				continue
			_texture_registry[albedo] = albedo_textures.size()
			albedo_textures.append(albedo)
			normal_textures.append(normal)
			
		#for texture in biome.get_albedo_textures():
			#if not texture or _texture_registry.has(texture):
				#continue
			#_texture_registry[texture] = albedo_textures.size()
			#albedo_textures.append(texture)
#
		#for texture in biome.get_normal_textures():
			#if not texture or _texture_registry.has(texture):
				#continue
			#_texture_registry[texture] = normal_textures.size()
			#normal_textures.append(texture)

	_build_texture_arrays(albedo_textures, normal_textures)

func _build_texture_arrays(albedo_textures: Array[Texture2D], normal_textures: Array[Texture2D]):
	_albedo_textures = Texture2DArray.new()
	_normal_textures = Texture2DArray.new()
	
	var albedo_images: Array[Image] = []
	for texture in albedo_textures:
		albedo_images.append(texture.get_image())
	var normal_images: Array[Image] = []
	
	for texture in normal_textures:
		normal_images.append(texture.get_image())
		
	_albedo_textures.create_from_images(albedo_images)
	_normal_textures.create_from_images(normal_images)

func _on_biome_textures_changed():
	_rebuild_texture_registry()
	texture_arrays_changed.emit()

func _on_biome_parameters_changed():
	parameters_changed.emit()

class BiomeContribution:
	var biome: Biome
	var weight: float

# TODO: rewrite without class
func _get_top_biomes(xz: Vector2i) -> Array[BiomeContribution]:
	var first_biome: Biome = null
	var second_biome: Biome = null
	
	var first_weight: float = -INF
	var second_weight: float = -INF
	
	for biome in biomes:
		if not biome:
			continue
		var weight := biome.get_weight(xz)
		if weight > first_weight:
			second_biome = first_biome
			second_weight = first_weight
			
			first_biome = biome
			first_weight = weight
		elif weight > second_weight:
			second_biome = biome
			second_weight = weight
	
	var first := BiomeContribution.new()
	first.biome = first_biome
	first.weight = first_weight
	
	var second := BiomeContribution.new()
	second.biome = second_biome
	second.weight = second_weight
	
	return [first, second]

func get_control_local(local_xz: Vector2i):
	var control: int = 0
	var s := resolve_surface(local_xz)
	
	control |= (s.base_id & 0x1F) << 27
	control |= (s.overlay_id & 0x1F) << 22
	control |= (roundi(clampf(s.blend, 0.0, 1.0) * 255.0) & 0xFF) << 14
	
	return control

@abstract
func create_maps(ring_size: Vector2i, lod_count: int, vertex_spacing: Vector2) -> void

@abstract
func shift_maps() -> void

@abstract
func has_maps() -> bool

@abstract
func get_height_maps() -> Texture2DArray

@abstract
func get_control_maps() -> Texture2DArray

func get_albedo_textures() -> Texture2DArray:
	return _albedo_textures

func get_normal_textures() -> Texture2DArray:
	return _normal_textures

@abstract
func get_height_world(world_xz: Vector2) -> float

class EncodedSurface:
	var base_id: int = 0
	var overlay_id: int = 0
	var blend: float = 0.0

func resolve_surface(xz: Vector2) -> EncodedSurface:
	var pair := _get_top_biomes(xz)
	var b_0 := pair[0]
	var b_1 := pair[1]
	
	if not b_0.biome:
		return EncodedSurface.new()
	
	var s_0 := b_0.biome.choose_surface(xz)
	
	if not b_1.biome or b_1.weight <= 10e-6:
		return _encode_surface(s_0)
	
	var s_1 := b_1.biome.choose_surface(xz)
	
	var t := b_1.weight / (b_0.weight + b_1.weight)
	
	return _encode_blended_surfaces(s_0, s_1, t)

func _encode_surface(s: Biome.BiomeSurface) -> EncodedSurface:
	var es := EncodedSurface.new()
	if not _texture_registry.has(s.base) or not _texture_registry.has(s.overlay):
		return es
	es.base_id = _texture_registry[s.base]
	es.overlay_id = _texture_registry[s.overlay]
	es.blend = int(clamp(s.blend * 255.0, 0, 255))
	return es

func _encode_blended_surfaces(a: Biome.BiomeSurface, b: Biome.BiomeSurface, t: float) -> EncodedSurface:
	# Strategy:
	# - base texture comes from dominant biome
	# - overlay from second biome
	# - blend reflects biome mix
	
	var base := a if t < 0.5 else b
	var overlay := b if t < 0.5 else a
	var blend := clampf(t, 0.0, 1.0)
	
	var es := EncodedSurface.new()
	es.base_id = _texture_registry[base.base_texture]
	es.overlay_id = _texture_registry[overlay.overlay_texture]
	es.blend = int(blend * 255.0)
	return es

@abstract
func get_height_amplitude() -> float
