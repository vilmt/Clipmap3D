@tool
extends Node3D
class_name Terrain

@export_tool_button("Generate", "MeshItem") var generate_button = _generate_terrain
@export_tool_button("Clear", "Remove") var clear_button = _clear_chunks

@export var noise: FastNoiseLite
@export var map_size := Vector2i(512, 512)
@export var map_offset := Vector2i(256, 256)

@export var chunk_rings: int = 10
@export var chunk_size := Vector2(64.0, 64.0)
@export_range(0, 10) var max_lod: int = 4
@export var lods: Array[int] = [0, 1, 2, 3]

@export var amplitude: float = 50.0

@export var player_character: Node3D
@export var physics_bodies: Array[PhysicsBody3D] = []

@export var chunk_material: ShaderMaterial

const CHUNK := preload("res://scenes/terrain/terrain_chunk.tscn")
const COLLIDER := preload("res://scenes/terrain/terrain_collider.tscn")

@onready var collider_container: StaticBody3D = $ColliderContainer
@onready var chunk_container: Marker3D = $ChunkContainer

@onready var height_map_sprite: Sprite2D = $HeightMapSprite
@onready var normal_map_sprite: Sprite2D = $NormalMapSprite

# Duplicate private values to prevent unexpected runtime changes
var _map_size: Vector2i
var _chunk_size: Vector2
var _max_lod: int
var _amplitude: float

var _height_image: Image
var _height_texture: ImageTexture
var _normal_image: Image
var _normal_texture: ImageTexture

var _map_origin := Vector2i.ZERO

const skirt := Vector2i.ONE

func _ready():
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	_generate_terrain()
	#_follow_player()

func _physics_process(_delta):
	if not player_character or not chunk_material:
		return
	
	_follow_player()

func _exit_tree() -> void:
	_clear_chunks()
		
func _generate_maps():
	var size_changed := _map_size != map_size
	
	if not _height_image or size_changed:
		_map_size = map_size
		_height_image = Image.create_empty(_map_size.x, _map_size.y, true, Image.FORMAT_RF)
		_normal_image = Image.create_empty(_map_size.x, _map_size.y, true, Image.FORMAT_RGB8)
	
	_generate_region(Rect2i(Vector2i.ZERO, _map_size), Vector2i.ZERO)
	
	_height_image.generate_mipmaps()
	_normal_image.generate_mipmaps()
	
	if _height_texture and not size_changed:
		_height_texture.update(_height_image)
		_normal_texture.update(_normal_image)
	else:
		_height_texture = ImageTexture.create_from_image(_height_image)
		_normal_texture = ImageTexture.create_from_image(_normal_image)
		chunk_material.set_shader_parameter(&"height_map", _height_texture)
		chunk_material.set_shader_parameter(&"normal_map", _normal_texture)
		
		height_map_sprite.texture = _height_texture
		normal_map_sprite.texture = _normal_texture
		height_map_sprite.scale = Vector2(128, 128) / _height_texture.get_size()
		normal_map_sprite.scale = Vector2(128, 128) / _normal_texture.get_size()
	
func _shift_maps_x(delta_x: int):
	var abs_x := absi(delta_x)
	assert(abs_x < _map_size.x)
	
	var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(_map_size.x - abs_x, _map_size.y))
	var destination := Vector2i(maxi(-delta_x, 0), 0)
	
	_height_image.blit_rect(_height_image.duplicate(), source_rect, destination)
	_normal_image.blit_rect(_normal_image.duplicate(), source_rect, destination)
	
	var image_rect := Rect2i(
		Vector2i(_map_size.x - abs_x if delta_x > 0 else 0, 0),
		Vector2i(abs_x, _map_size.y)
	)
	
	_generate_region(image_rect, image_rect.position)
	
func _shift_maps_y(delta_y: int):
	if delta_y == 0:
		return
	
	var abs_y := absi(delta_y)
	assert(abs_y < _map_size.y)
	
	var source_rect := Rect2i(Vector2i(0, maxi(delta_y, 0)), Vector2i(_map_size.x, _map_size.y - abs_y))
	var destination := Vector2i(0, maxi(-delta_y, 0))
	
	_height_image.blit_rect(_height_image.duplicate(), source_rect, destination)
	_normal_image.blit_rect(_normal_image.duplicate(), source_rect, destination)
	
	var image_rect := Rect2i(
		Vector2i(0, _map_size.y - abs_y if delta_y > 0 else 0),
		Vector2i(_map_size.x, abs_y)
	)
	
	_generate_region(image_rect, image_rect.position)

func _generate_region(image_rect: Rect2i, world_offset: Vector2i):
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
			
			var h := noise.get_noise_2dv(_map_origin + p_world) * 0.5 + 0.5
			heights[s_y * full_size.x + s_x] = h
			
			if image_rect.has_point(p_image):
				_height_image.set_pixelv(p_image, Color(h, 0.0, 0.0))
	
	var texel_world_size: Vector2 = _chunk_size / float(1 << _max_lod)
	
	for y: int in strip_size.y:
		for x: int in strip_size.x:
			var p_image := Vector2i(x, y) + image_rect.position
			var s := Vector2i(x, y) + skirt
			
			var l := heights[s.y * full_size.x + (s.x - 1)]
			var r := heights[s.y * full_size.x + (s.x + 1)]
			var d := heights[(s.y - 1) * full_size.x + s.x]
			var u := heights[(s.y + 1) * full_size.x + s.x]
			
			var dx := (r - l) * _amplitude / (2.0 * texel_world_size.x)
			var dz := (u - d) * _amplitude / (2.0 * texel_world_size.y)
			
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normal = (normal + Vector3.ONE) * 0.5
			
			_normal_image.set_pixelv(p_image, Color(normal.x, normal.y, normal.z))

func _follow_player():
	var chunk_origin := Vector2(chunk_container.global_position.x, chunk_container.global_position.z)
	var target_position := Vector2(player_character.global_position.x, player_character.global_position.z)
	var new_chunk_origin: Vector2 = target_position.snapped(_chunk_size)
	
	if chunk_origin.is_equal_approx(new_chunk_origin):
		return
	
	chunk_container.global_position.x = new_chunk_origin.x
	chunk_container.global_position.z = new_chunk_origin.y
	chunk_material.set_shader_parameter(&"chunk_origin", new_chunk_origin)
	
	var subdivision_size := _chunk_size / float(1 << _max_lod)
	var new_map_origin := Vector2i((new_chunk_origin / subdivision_size).floor())
	var delta := new_map_origin - _map_origin
	
	if delta:
		if delta.x >= _map_size.x or delta.y >= _map_size.y:
			_map_origin = new_map_origin
			_generate_maps()
		else:
			if delta.x != 0:
				_map_origin.x = new_map_origin.x
				_shift_maps_x(delta.x)
			if delta.y != 0:
				_map_origin.y = new_map_origin.y
				_shift_maps_y(delta.y)
	
			_height_image.generate_mipmaps()
			_normal_image.generate_mipmaps()
			_height_texture.update(_height_image)
			_normal_texture.update(_normal_image)
	
	chunk_material.set_shader_parameter(&"map_origin", _map_origin)
	
	if Engine.is_editor_hint():
		return
	for collider: TerrainCollider in collider_container.get_children():
		collider.update_offset_and_origin(map_offset, _map_origin)
	
func _generate_terrain():
	if not noise or not chunk_material:
		return
	
	_chunk_size = chunk_size
	_max_lod = max_lod
	_amplitude = amplitude
	
	chunk_material.set_shader_parameter(&"chunk_origin", Vector2.ZERO)
	chunk_material.set_shader_parameter(&"map_origin", Vector2i.ZERO)
	chunk_material.set_shader_parameter(&"amplitude", _amplitude)
	chunk_material.set_shader_parameter(&"chunk_size", _chunk_size)
	chunk_material.set_shader_parameter(&"map_offset", map_offset)
	var resized: Array[int] = []
	resized.resize(20)
	resized.fill(_max_lod)
	for i: int in lods.size():
		resized[i] = lods[i]
	chunk_material.set_shader_parameter(&"lods", resized)
	chunk_material.set_shader_parameter(&"max_lod", _max_lod)
	
	_generate_maps()
	_generate_chunks()
	
	_follow_player()
	
	if Engine.is_editor_hint():
		return
	_generate_colliders()
	
func _generate_colliders():
	if not physics_bodies.has(player_character):
		physics_bodies.append(player_character)
	var subdivision_size := _chunk_size / float(1 << _max_lod);
	for physics_body: PhysicsBody3D in physics_bodies:
		var collider: TerrainCollider = COLLIDER.instantiate()
		
		collider.physics_body = physics_body
		collider.prepare_shape(_height_image, _amplitude, subdivision_size)
		collider.update_offset_and_origin(map_offset, _map_origin)
		
		collider_container.add_child.call_deferred(collider)

func _generate_chunks():
	if not chunk_container:
		return
	_clear_chunks()
	
	var bottom_corner := Vector3(-_chunk_size.x, 0.0, -_chunk_size.y) / 2.0
	var top_corner := Vector3(_chunk_size.x, _amplitude, _chunk_size.y)
	var chunk_custom_aabb := AABB(bottom_corner, top_corner)
	
	for x: int in range(-chunk_rings, chunk_rings + 1):
		for z: int in range(-chunk_rings, chunk_rings + 1):
			var chunk: TerrainChunk = CHUNK.instantiate()
			
			chunk.position = Vector3(x * _chunk_size.x, 0.0, z * _chunk_size.y)
			
			var ring := maxi(absi(x), absi(z))
			var lod: int = _max_lod
			if ring < lods.size():
				lod = lods[ring]
			var exponent := maxi(0, _max_lod - lod)
			var subdivisions := (1 << exponent) - 1
			
			chunk.prepare_mesh(_chunk_size, subdivisions)
			chunk.custom_aabb = chunk_custom_aabb
			
			chunk_container.add_child.call_deferred(chunk)
	
	set_physics_process(true)

func _clear_chunks():
	if not chunk_container:
		return
	for chunk: Node in chunk_container.get_children():
		chunk_container.remove_child(chunk)
		chunk.queue_free()
	set_physics_process(false)
