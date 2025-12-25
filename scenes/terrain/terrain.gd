@tool
extends Node3D
class_name Terrain

@export_tool_button("Generate", "GridMap") var generate_button = generate_terrain
@export_tool_button("Clear", "GridMap") var clear_button = clear_chunks

@export var noise: FastNoiseLite
@export var map_size := Vector2i(512, 512)

@export var chunk_rings: int = 10
@export var chunk_size := Vector2(32.0, 32.0)
@export var lods: Array[int]
@export_range(0, 10) var max_lod: int = 4

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

func _ready():
	if Engine.is_editor_hint():
		return
	generate_terrain()

#func _unhandled_key_input(event: InputEvent) -> void:
	#if Engine.is_editor_hint():
		#return
	#if event.is_action_pressed("ui_accept"):

func _physics_process(_delta):
	if not player_character or not chunk_material:
		return
	var target_position := player_character.global_position * Vector3(1.0, 0.0, 1.0)
	var snap := Vector3(chunk_size.x, 0.0, chunk_size.y)
	chunk_container.global_position = target_position.snapped(snap)
	chunk_material.set_shader_parameter("terrain_position", chunk_container.global_position)
	# TODO: offset and regenerate terrain image 
	
	# this is for water
	#RenderingServer.global_shader_parameter_set("player_position", player_position)

func generate_terrain():
	if not noise or not chunk_material:
		return
	generate_maps()
	generate_chunks()
	if Engine.is_editor_hint():
		return
	generate_colliders()

func clear_chunks():
	if not chunk_container:
		return
	for chunk: Node in chunk_container.get_children():
		chunk_container.remove_child(chunk)
		chunk.queue_free()

func generate_maps():
	_height_image = Image.create(map_size.x, map_size.y, true, Image.FORMAT_RF)
	_normal_image = Image.create(map_size.x, map_size.y, true, Image.FORMAT_RGB8)
	
	var heights := PackedFloat32Array()
	heights.resize(map_size.x * map_size.y)
	
	for y: int in map_size.y:
		for x: int in map_size.x:
			var h := absf(noise.get_noise_2d(x, y))
			heights[y * map_size.x + x] = h
			_height_image.set_pixel(x, y, Color(h, 0.0, 0.0))
	
	var inv_amplitude: float = 1.0 / max(amplitude, 0.0001)
	
	for y: int in map_size.y:
		for x: int in map_size.x:
			var left := heights[y * map_size.x + maxi(x - 1, 0)]
			var right := heights[y * map_size.x + mini(x + 1, map_size.x - 1)]
			var down := heights[maxi(y - 1, 0) * map_size.x + x]
			var up := heights[mini(y + 1, map_size.y - 1) * map_size.x + x]
			
			var normal := Vector3(left - right, inv_amplitude, down - up).normalized()
			normal = (normal + Vector3.ONE) * 0.5
			_normal_image.set_pixel(x, y, Color(normal.x, normal.y, normal.z))

	_height_image.generate_mipmaps()
	_normal_image.generate_mipmaps()
	
	_height_texture = ImageTexture.create_from_image(_height_image)
	_normal_texture = ImageTexture.create_from_image(_normal_image)

	height_map_sprite.texture = _height_texture
	height_map_sprite.scale = Vector2(48, 48) / _height_texture.get_size()
	normal_map_sprite.texture = _normal_texture
	normal_map_sprite.scale = Vector2(48, 48) / _height_texture.get_size()
	
	chunk_material.set_shader_parameter("height_map", _height_texture)
	chunk_material.set_shader_parameter("amplitude", amplitude)
	chunk_material.set_shader_parameter("normal_map", _normal_texture)
	
	chunk_material.set_shader_parameter("max_lod", max_lod)
	chunk_material.set_shader_parameter("lods", lods)
	
	chunk_material.set_shader_parameter("chunk_size", chunk_size)

func generate_colliders():
	if not physics_bodies.has(player_character):
		physics_bodies.append(player_character)
	for physics_body: PhysicsBody3D in physics_bodies:
		var collider: TerrainCollider = COLLIDER.instantiate()
		
		collider.physics_body = physics_body
		collider.prepare_shape(_height_image, amplitude)
		
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
			ring = maxi(0, ring - 1)
			var exponent := maxi(0, max_lod - ring)
			var subdivisions := (1 << exponent) - 1
			
			chunk.prepare_mesh(chunk_size, subdivisions)
			chunk.custom_aabb = chunk_custom_aabb
			
			chunk_container.add_child.call_deferred(chunk)
			
		#if Engine.is_editor_hint():
			#await get_tree().process_frame
