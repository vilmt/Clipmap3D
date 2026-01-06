@tool
class_name Terrain3D extends Node3D

# BUG: sometimes when opening scene, terrain is invisible until update
# TODO: allow terrain to move along y axis freely
# TODO: lower resolution images for further terrain (doesnt work cause normals?)

@export var target_node: Node3D:
	set(value):
		if target_node == value:
			return
		target_node = value
		if not is_node_ready():
			return
		_update_target_priority()
		
# TODO: setters
@export var height_map: HeightMap:
	set(value):
		if height_map == value:
			return
		height_map = value
		if not is_node_ready():
			return
		_mesh_handler.update_height_map(height_map)
		if not Engine.is_editor_hint():
			_collision_handler.update_height_map(height_map)
		
@export var height_map_origin_snap := Vector2i(4, 4)

# TODO: collider generation and setters
@export_group("Physics", "physics")
@export var collision_mesh_size := Vector2i(8, 8)
@export var physics_enable_collision: bool = true
@export var physics_target_bodies: Array[PhysicsBody3D]
@export_flags_3d_physics var physics_layer: int = 1
@export_flags_3d_physics var physics_mask: int = 1

@export_group("Mesh", "mesh")
@export var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		if mesh_vertex_spacing == value:
			return
		mesh_vertex_spacing = value
		if not is_node_ready():
			return
		_mesh_handler.update_vertex_spacing(mesh_vertex_spacing)
		if not Engine.is_editor_hint():
			_collision_handler.update_vertex_spacing(mesh_vertex_spacing)
		
@export var mesh_size := Vector2i(32, 32):
	set(value):
		if mesh_size == value:
			return
		mesh_size = value
		if not is_node_ready():
			return
		_mesh_handler.update_size(mesh_size)

@export_range(1, 10, 1) var mesh_lods: int = 5:
	set(value):
		if mesh_lods == value:
			return
		mesh_lods = value
		if not is_node_ready():
			return
		
		_mesh_handler.update_lods(mesh_lods)
@export var shader_material: ShaderMaterial:
	set(value):
		if shader_material == value:
			return
		shader_material = value
		if not is_node_ready():
			return
		if shader_material:
			_mesh_handler.update_material(shader_material.get_rid())

@export_flags_3d_render var render_layer: int = 1:
	set(value):
		if render_layer == value:
			return
		render_layer = value
		if not is_node_ready():
			return
		_mesh_handler.update_render_layer(render_layer)

@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		if cast_shadows == value:
			return
		cast_shadows = value
		if not is_node_ready():
			return
		_mesh_handler.update_cast_shadows(cast_shadows as RenderingServer.ShadowCastingSetting)

var _mesh_handler: Terrain3DMeshHandler
var _collision_handler: Terrain3DCollisionHandler

func _init() -> void:
	_mesh_handler = Terrain3DMeshHandler.new()
	if Engine.is_editor_hint():
		return
	_collision_handler = Terrain3DCollisionHandler.new()

func _ready():
	_mesh_handler.generate(self)
	
	_update_target_priority()
	
	if Engine.is_editor_hint():
		set_physics_process(false)
	else:
		_collision_handler.initialize(height_map, collision_mesh_size, mesh_vertex_spacing, get_world_3d().space)
		_collision_handler.add_bodies(physics_target_bodies)

func get_target_p_2d() -> Vector2:
	var target_p: Vector3 = global_position
	if target_node:
		target_p = target_node.global_position
		target_p.y = 0.0
	
	return Vector2(target_p.x, target_p.z)

func _process(_delta: float) -> void:
	snap_to_target()

func _physics_process(_delta: float) -> void:
	_collision_handler.update()
	
func _exit_tree() -> void:
	_mesh_handler.clear()
	if not Engine.is_editor_hint():
		_collision_handler.clear()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			snap_to_target()
		NOTIFICATION_ENTER_WORLD:
			_mesh_handler.update_scenario(get_world_3d().scenario)
		NOTIFICATION_VISIBILITY_CHANGED:
			_mesh_handler.update_visible(is_visible_in_tree())

func snap_to_target() -> void:
	if not is_inside_tree():
		return
	
	var target_p: Vector3 = global_position
	if target_node:
		target_p = target_node.global_position
		target_p.y = 0.0
		global_position.x = target_p.x
		global_position.z = target_p.z
	
	var target_p_2d := Vector2(target_p.x, target_p.z)
	
	# height map snapping
	if height_map:
		var snap_2d = Vector2(height_map_origin_snap) * mesh_vertex_spacing
		height_map.set_origin(Vector2(target_p_2d.snapped(snap_2d)))
		
	_mesh_handler.snap(target_p_2d)
	
func _update_target_priority():
	var target_node_exists := is_instance_valid(target_node)
	set_process(target_node_exists)
	set_notify_transform(not target_node_exists)
