@tool
class_name Terrain3D extends Node3D

# TODO: lower resolution images for further terrain (doesnt work cause normals?)

@export var terrain_source: Terrain3DSource:
	set(value):
		if terrain_source == value:
			return
		terrain_source = value
		if not is_node_ready():
			return
		_mesh_handler.update_terrain_source(terrain_source)
		if not Engine.is_editor_hint():
			_collision_handler.update_terrain_source(terrain_source)

@export var follow_target: Node3D:
	set(value):
		if follow_target == value:
			return
		follow_target = value
		if not is_node_ready():
			return
		update_position()

@export var height_amplitude: float = 100.0:
	set(value):
		if height_amplitude == value:
			return
		height_amplitude = value
		if not is_node_ready():
			return
		_mesh_handler.update_height_amplitude(height_amplitude)
		if not Engine.is_editor_hint():
			_collision_handler.update_height_amplitude(height_amplitude)

# TODO: setters
@export var height_origin_snap := Vector2i(4, 4)

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
		
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		if mesh_tile_size == value:
			return
		mesh_tile_size = value
		if not is_node_ready():
			return
		_mesh_handler.update_tile_size(mesh_tile_size)

@export_range(1, 10, 1) var mesh_lod_count: int = 5:
	set(value):
		if mesh_lod_count == value:
			return
		mesh_lod_count = value
		if not is_node_ready():
			return
		_mesh_handler.update_lod_count(mesh_lod_count)

@export_group("Rendering")

# TODO: material should probably not be exposed 
@export var material: ShaderMaterial:
	set(value):
		if material == value:
			return
		material = value
		if not is_node_ready():
			return
		if material:
			_mesh_handler.update_material_rid(material.get_rid())
		else:
			_mesh_handler.update_material_rid(RID())

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

@export_group("Collision", "collision")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var collision_enabled: bool = true

@export var collision_mesh_size := Vector2i(8, 8):
	set(value):
		if collision_mesh_size == value:
			return
		collision_mesh_size = value
		if not is_node_ready():
			return
		if not Engine.is_editor_hint():
			_collision_handler.update_mesh_size(collision_mesh_size)

# TODO: setters
@export var collision_targets: Array[PhysicsBody3D]

@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		if collision_layer == value:
			return
		collision_layer = value
		if not is_node_ready():
			return
		if not Engine.is_editor_hint():
			_collision_handler.update_collision_layer(collision_layer)

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		if collision_mask == value:
			return
		collision_mask = value
		if not is_node_ready():
			return
		if not Engine.is_editor_hint():
			_collision_handler.update_collision_mask(collision_mask)

var _mesh_handler: Terrain3DMeshHandler
var _collision_handler: Terrain3DCollisionHandler
var _last_p: Vector3

signal position_changed(new_position: Vector3)

func _init() -> void:
	_mesh_handler = Terrain3DMeshHandler.new()
	if not Engine.is_editor_hint():
		_collision_handler = Terrain3DCollisionHandler.new()

func _enter_tree() -> void:
	_mesh_handler.initialize(self)
	if not Engine.is_editor_hint():
		_collision_handler.initialize(self)
	
	_last_p = Vector3(INF, INF, INF)
	update_position.call_deferred()

func _ready():
	set_physics_process(not Engine.is_editor_hint())
	
func _exit_tree() -> void:
	_mesh_handler.clear()
	if not Engine.is_editor_hint():
		_collision_handler.clear()

func _process(_delta: float) -> void:
	update_position()

func _physics_process(_delta: float) -> void:
	_collision_handler.update()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			_mesh_handler.update_scenario_rid(RID())
		NOTIFICATION_VISIBILITY_CHANGED:
			_mesh_handler.update_visible(is_visible_in_tree())

func update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if global_position == _last_p:
		return
	if global_position.y != _last_p.y:
		_mesh_handler.update_y_position(global_position.y)
		if not Engine.is_editor_hint():
			_collision_handler.update_y_position(global_position.y)
	if global_position.x != _last_p.x or global_position.z != _last_p.z:
		var target_xz := Vector2(global_position.x, global_position.z)
		_mesh_handler.snap(target_xz)
		if terrain_source:
			# divide by vert spacing?
			terrain_source.origin = Vector2i(target_xz.snapped(height_origin_snap))
			terrain_source.refresh()
	
	_last_p = global_position
	position_changed.emit(global_position)
