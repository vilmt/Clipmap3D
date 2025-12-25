@tool
extends Node3D
class_name Terrain

# TODO: write own noise shader since NoiseTexture2D
# has inherent 8 bit limitation

@export_tool_button("Generate", "GridMap") var generate_button = generate_terrain
@export_tool_button("Clear", "GridMap") var clear_button = clear_chunks

@export var noise: FastNoiseLite

@export var amplitude: float = 50.0
@export var render_distance: int = 10
@export var chunk_size := Vector2(32.0, 32.0)
@export_range(0, 10) var max_lod: int = 4
@export var lod_ring_thickness: int = 1
@export var lod_zero_radius: int = 1

@export var player_character: Node3D
@export var physics_bodies: Array[PhysicsBody3D] = []

const CHUNK := preload("res://scenes/terrain_chunk/terrain_chunk.tscn")
const COLLIDER := preload("res://scenes/terrain_collider/terrain_collider.tscn")

@onready var collider_container: StaticBody3D = $ColliderContainer
@onready var chunk_container: Marker3D = $ChunkContainer

@onready var height_map_sprite: Sprite2D = $HeightMapSprite
@onready var normal_map_sprite: Sprite2D = $NormalMapSprite

#@onready var terrain_processor: TerrainProcessor = $TerrainProcessor

var _height_texture: NoiseTexture2D
var _normal_texture: NoiseTexture2D

var _height_image: Image
#var _height_texture: ImageTexture
var _normal_image: Image
#var _normal_texture: ImageTexture

func _ready():
	if Engine.is_editor_hint():
		return
	generate_terrain()

#func _unhandled_key_input(event: InputEvent) -> void:
	#if Engine.is_editor_hint():
		#return
	#if event.is_action_pressed("ui_accept"):

func _physics_process(_delta):
	if not player_character:
		return
	var target_position := player_character.global_position * Vector3(1.0, 0.0, 1.0)
	var snap := Vector3(chunk_size.x, 0.0, chunk_size.y)
	chunk_container.global_position = target_position.snapped(snap)
	RenderingServer.global_shader_parameter_set("terrain_position", chunk_container.global_position)
	# TODO: offset and regenerate terrain image 
	
	# this is for water
	#RenderingServer.global_shader_parameter_set("player_position", player_position)

func generate_terrain():
	if not noise:
		return
	await generate_maps()
	await generate_chunks()
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
	#terrain_processor.set_noise_model(noise_model)
	#terrain_processor.set_amplitude(amplitude)
	_height_texture = NoiseTexture2D.new()
	_normal_texture = NoiseTexture2D.new()
	_height_texture.noise = noise
	_normal_texture.noise = noise
	_normal_texture.as_normal_map = true
	
	await _height_texture.changed
	
	_height_image = _height_texture.get_image()
	_normal_image = _normal_texture.get_image()
	
	#_height_image.generate_mipmaps(true)
	#_normal_image.generate_mipmaps(true)
	
	height_map_sprite.texture = _height_texture
	height_map_sprite.scale = Vector2(48, 48) / _height_texture.get_size()
	normal_map_sprite.texture = _normal_texture
	normal_map_sprite.scale = Vector2(48, 48) / _height_texture.get_size()
	
	RenderingServer.global_shader_parameter_set("height_map", _height_texture)
	RenderingServer.global_shader_parameter_set("height_map_amplitude", amplitude)
	RenderingServer.global_shader_parameter_set("normal_map", _normal_texture)
	
	RenderingServer.global_shader_parameter_set("terrain_max_lod", max_lod)
	RenderingServer.global_shader_parameter_set("terrain_lod_ring_thickness", lod_ring_thickness)
	RenderingServer.global_shader_parameter_set("terrain_lod_zero_radius", lod_zero_radius)
	RenderingServer.global_shader_parameter_set("terrain_chunk_size", chunk_size)

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
	
	for x: int in range(-render_distance, render_distance + 1):
		for z: int in range(-render_distance, render_distance + 1):
			var chunk: TerrainChunk = CHUNK.instantiate()
			
			chunk.position = Vector3(x * chunk_size.x, 0.0, z * chunk_size.y)
			
			var ring := maxi(absi(x), absi(z))
			ring = maxi(0, ring - lod_zero_radius)
			var exponent := maxi(0, max_lod - ring)
			var subdivisions := (1 << exponent) - 1
			
			chunk.prepare_mesh(chunk_size, subdivisions)
			chunk.custom_aabb = chunk_custom_aabb
			
			chunk_container.add_child.call_deferred(chunk)
			
		if Engine.is_editor_hint():
			await get_tree().process_frame
