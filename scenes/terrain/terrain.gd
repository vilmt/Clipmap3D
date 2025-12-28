@tool
extends Node3D
class_name Terrain

@export_tool_button("Generate", "GridMap") var generate_button = generate_terrain
@export_tool_button("Clear", "GridMap") var clear_button = clear_chunks

# TODO: make export variables less fragile to runtime changes

@export var noise: FastNoiseLite
@export var map_size := Vector2i(512, 512) # BUG: crash after editor change + regenerate
@export var map_offset := Vector2i(256, 256)

@export var texel_snap := Vector2i(4, 4)

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
	generate_terrain()
	if chunk_material:
		chunk_material.set_shader_parameter(&"chunk_origin", chunk_container.global_position)
		# TODO: other offset

func _physics_process(_delta):
	if not player_character or not chunk_material:
		return
	
	var chunk_origin := Vector2(chunk_container.global_position.x, chunk_container.global_position.z)
	var target_position := Vector2(player_character.global_position.x, player_character.global_position.z)
	var new_chunk_origin: Vector2 = target_position.snapped(chunk_size)
	
	if not chunk_origin.is_equal_approx(new_chunk_origin):
		chunk_container.global_position.x = new_chunk_origin.x
		chunk_container.global_position.z = new_chunk_origin.y
		chunk_material.set_shader_parameter(&"chunk_origin", new_chunk_origin)
		
		var subdivision_size := chunk_size / float(1 << max_lod)
		var new_map_origin := Vector2i((new_chunk_origin / subdivision_size).floor())
		var delta := new_map_origin - _map_origin
		#_map_origin = new_map_origin
		
		if delta.x != 0:
			_map_origin.x = new_map_origin.x
			shift_maps_x(delta.x)
		if delta.y != 0:
			_map_origin.y = new_map_origin.y
			shift_maps_y(delta.y)
		
		chunk_material.set_shader_parameter(&"map_origin", _map_origin)
		

func generate_maps():
	if not _height_image:
		_height_image = Image.create_empty(map_size.x, map_size.y, true, Image.FORMAT_RF)
	
	var full_size: Vector2i = map_size + skirt * 2
	var heights := PackedFloat32Array()
	heights.resize(full_size.x * full_size.y)
	
	for s_y: int in full_size.y:
		for s_x: int in full_size.x:
			var s := Vector2i(s_x, s_y)
			var p := s - skirt
			var world_p := _map_origin + p
			var h := noise.get_noise_2dv(world_p) * 0.5 + 0.5
			heights[s_y * full_size.x + s_x] = h
			if not Rect2i(Vector2.ZERO, map_size).has_point(p):
				continue
			_height_image.set_pixelv(p, Color(h, 0.0, 0.0))
	
	_height_image.generate_mipmaps()
	
	if not _normal_image:
		_normal_image = Image.create_empty(map_size.x, map_size.y, true, Image.FORMAT_RGB8)
	
	var texel_world_size: Vector2 = chunk_size / float(1 << max_lod)
	
	for y: int in map_size.y:
		for x: int in map_size.x:
			var p := Vector2i(x, y)
			var s := p + skirt
			
			var l := heights[s.y * full_size.x + (s.x - 1)]
			var r := heights[s.y * full_size.x + (s.x + 1)]
			var d := heights[(s.y - 1) * full_size.x + s.x]
			var u := heights[(s.y + 1) * full_size.x + s.x]
			
			var dx := (r - l) * amplitude / (2.0 * texel_world_size.x)
			var dz := (u - d) * amplitude / (2.0 * texel_world_size.y)
			
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normal = (normal + Vector3.ONE) * 0.5
			
			_normal_image.set_pixelv(p, Color(normal.x, normal.y, normal.z))
	
	_normal_image.generate_mipmaps()
	
	if _height_texture:
		_height_texture.update(_height_image)
	else:
		_height_texture = ImageTexture.create_from_image(_height_image)
		chunk_material.set_shader_parameter(&"height_map", _height_texture)
		
		height_map_sprite.texture = _height_texture
		height_map_sprite.scale = Vector2(128, 128) / _height_texture.get_size()
	
	if _normal_texture:
		_normal_texture.update(_normal_image)
	else:
		_normal_texture = ImageTexture.create_from_image(_normal_image)
		chunk_material.set_shader_parameter(&"normal_map", _normal_texture)
		
		normal_map_sprite.texture = _normal_texture
		normal_map_sprite.scale = Vector2(128, 128) / _height_texture.get_size()
	
func shift_maps_x(delta_x: int):
	var abs_x := absi(delta_x)
	
	assert(abs_x < map_size.x)
	
	var source_rect := Rect2i(Vector2i(maxi(delta_x, 0), 0), Vector2i(map_size.x - abs_x, map_size.y))
	var destination := Vector2i(maxi(-delta_x, 0), 0)
	
	var temp: Image = _height_image.duplicate()
	_height_image.blit_rect(temp, source_rect, destination)
	
	var strip_size := Vector2i(abs_x, map_size.y)
	var full_size := strip_size + skirt * 2
	var heights := PackedFloat32Array()
	heights.resize(full_size.x * full_size.y)
	
	var offset := Vector2i.ZERO
	if delta_x > 0:
		offset.x = map_size.x - delta_x

	for s_y: int in full_size.y:
		for s_x: int in full_size.x:
			var s := Vector2i(s_x, s_y)
			var p := s - skirt + offset
			var world_p := _map_origin + p
			var h := noise.get_noise_2dv(world_p) * 0.5 + 0.5
			heights[s_y * full_size.x + s_x] = h
			if not Rect2i(offset, strip_size).has_point(p):
				continue
			_height_image.set_pixelv(p, Color(h, 0.0, 0.0))
	
	_height_image.generate_mipmaps()
	_height_texture.update(_height_image)
	
	temp = _normal_image.duplicate()
	_normal_image.blit_rect(temp, source_rect, destination)
	
	var texel_world_size: Vector2 = chunk_size / float(1 << max_lod)
	
	for y: int in strip_size.y:
		for x: int in strip_size.x:
			var p := Vector2i(x, y) + offset
			var s := Vector2i(x, y) + skirt
			
			var l := heights[s.y * full_size.x + (s.x - 1)]
			var r := heights[s.y * full_size.x + (s.x + 1)]
			var d := heights[(s.y - 1) * full_size.x + s.x]
			var u := heights[(s.y + 1) * full_size.x + s.x]
			
			var dx := (r - l) * amplitude / (2.0 * texel_world_size.x)
			var dz := (u - d) * amplitude / (2.0 * texel_world_size.y)
			
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normal = (normal + Vector3.ONE) * 0.5
			
			_normal_image.set_pixelv(p, Color(normal.x, normal.y, normal.z))
	
	_normal_image.generate_mipmaps()
	_normal_texture.update(_normal_image)
	
func shift_maps_y(delta_y: int):
	var abs_y := absi(delta_y)
	
	assert(abs_y < map_size.y)
	
	var source_rect := Rect2i(Vector2i(0, maxi(delta_y, 0)), Vector2i(map_size.x, map_size.y - abs_y))
	var destination := Vector2i(0, maxi(-delta_y, 0))
	
	var temp: Image = _height_image.duplicate()
	_height_image.blit_rect(temp, source_rect, destination)
	
	var strip_size := Vector2i(map_size.x, abs_y)
	var full_size := strip_size + skirt * 2
	var heights := PackedFloat32Array()
	heights.resize(full_size.x * full_size.y)
	
	var offset := Vector2i.ZERO
	if delta_y > 0:
		offset.y = map_size.y - delta_y

	for s_y: int in full_size.y:
		for s_x: int in full_size.x:
			var s := Vector2i(s_x, s_y)
			var p := s - skirt + offset
			var world_p := _map_origin + p
			var h := noise.get_noise_2dv(world_p) * 0.5 + 0.5
			heights[s_y * full_size.x + s_x] = h
			if not Rect2i(offset, strip_size).has_point(p):
				continue
			_height_image.set_pixelv(p, Color(h, 0.0, 0.0))
	
	_height_image.generate_mipmaps()
	_height_texture.update(_height_image)
	
	temp = _normal_image.duplicate()
	_normal_image.blit_rect(temp, source_rect, destination)
	
	var texel_world_size: Vector2 = chunk_size / float(1 << max_lod)
	
	for y: int in strip_size.y:
		for x: int in strip_size.x:
			var p := Vector2i(x, y) + offset
			var s := Vector2i(x, y) + skirt
			
			var l := heights[s.y * full_size.x + (s.x - 1)]
			var r := heights[s.y * full_size.x + (s.x + 1)]
			var d := heights[(s.y - 1) * full_size.x + s.x]
			var u := heights[(s.y + 1) * full_size.x + s.x]
			
			var dx := (r - l) * amplitude / (2.0 * texel_world_size.x)
			var dz := (u - d) * amplitude / (2.0 * texel_world_size.y)
			
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normal = (normal + Vector3.ONE) * 0.5
			
			_normal_image.set_pixelv(p, Color(normal.x, normal.y, normal.z))
	
	_normal_image.generate_mipmaps()
	_normal_texture.update(_normal_image)

func _exit_tree() -> void:
	clear_chunks()
	
func generate_terrain():
	if not noise or not chunk_material:
		return
	
	chunk_material.set_shader_parameter(&"amplitude", amplitude)
	chunk_material.set_shader_parameter(&"chunk_size", chunk_size)
	chunk_material.set_shader_parameter(&"map_offset", map_offset)
	var resized: Array[int] = []
	resized.resize(20)
	resized.fill(max_lod)
	for i: int in lods.size():
		resized[i] = lods[i]
	chunk_material.set_shader_parameter(&"lods", resized)
	chunk_material.set_shader_parameter(&"max_lod", max_lod)
	
	generate_maps()
	generate_chunks()
	if Engine.is_editor_hint():
		return
	generate_colliders()
	
func generate_colliders():
	if not physics_bodies.has(player_character):
		physics_bodies.append(player_character)
	var subdivision_size := chunk_size / float(1 << max_lod);
	for physics_body: PhysicsBody3D in physics_bodies:
		var collider: TerrainCollider = COLLIDER.instantiate()
		
		collider.physics_body = physics_body
		collider.prepare_shape(_height_image, amplitude, subdivision_size)
		
		collider_container.add_child.call_deferred(collider)

func generate_chunks():
	if not chunk_container:
		return
	clear_chunks()
	
	var bottom_corner := Vector3(-chunk_size.x, 0.0, -chunk_size.y) / 2.0
	var top_corner := Vector3(chunk_size.x, amplitude, chunk_size.y)
	var chunk_custom_aabb := AABB(bottom_corner, top_corner)
	
	for x: int in range(-chunk_rings, chunk_rings + 1):
		for z: int in range(-chunk_rings, chunk_rings + 1):
			var chunk: TerrainChunk = CHUNK.instantiate()
			
			chunk.position = Vector3(x * chunk_size.x, 0.0, z * chunk_size.y)
			
			var ring := maxi(absi(x), absi(z))
			var lod: int = max_lod
			if ring < lods.size():
				lod = lods[ring]
			var exponent := maxi(0, max_lod - lod)
			var subdivisions := (1 << exponent) - 1
			
			chunk.prepare_mesh(chunk_size, subdivisions)
			chunk.custom_aabb = chunk_custom_aabb
			
			chunk_container.add_child.call_deferred(chunk)
	
	set_physics_process(true)

func clear_chunks():
	if not chunk_container:
		return
	for chunk: Node in chunk_container.get_children():
		chunk_container.remove_child(chunk)
		chunk.queue_free()
	set_physics_process(false)
