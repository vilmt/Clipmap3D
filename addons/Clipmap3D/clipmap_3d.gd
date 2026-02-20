@tool
class_name Clipmap3D extends Node3D

## The Node3D which the terrain snaps to on the X and Z axes.
@export var follow_target: Node3D

## The source to use for generation and texturing.
@export var source: Clipmap3DSource:
	set(value):
		if source == value:
			return
		if source:
			source.clear()
		source = value
		if not is_node_ready():
			return
		_mesh_handler.source = source
		if _collision_handler:
			_collision_handler.source = source
		if source:
			# TODO: move to func
			source.size = _mesh_handler.get_vertices()
			source.vertex_spacing = mesh_vertex_spacing
			source.lod_count = mesh_lod_count
			source.collision_enabled = collision_enabled # HACK
			source.build()

@export_group("Mesh", "mesh")

## World spacing between vertices. Power-of-two values are recommended.
@export_custom(PROPERTY_HINT_LINK, "suffix:m") var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		if mesh_vertex_spacing == value:
			return
		mesh_vertex_spacing = value
		if not is_node_ready():
			return
		_mesh_handler.vertex_spacing = mesh_vertex_spacing
		if _collision_handler:
			_collision_handler.vertex_spacing = mesh_vertex_spacing
		if source:
			source.vertex_spacing = mesh_vertex_spacing

## The base tile size used to build the clipmap.
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		value = value.clampi(1, 128)
		if mesh_tile_size == value:
			return
		mesh_tile_size = value
		if not is_node_ready():
			return
		_mesh_handler.tile_size = mesh_tile_size
		if source:
			source.size = _mesh_handler.get_vertices()

# NOTE: arbitrary lower limit of 2 because of https://github.com/godotengine/godot/issues/115103
## The amount of level of detail (LOD) rings that form this mesh.
@export_range(2, Clipmap3DMeshHandler.MAX_LOD_COUNT, 1) var mesh_lod_count: int = 5:
	set(value):
		if mesh_lod_count == value:
			return
		mesh_lod_count = value
		if not is_node_ready():
			return
		_mesh_handler.lod_count = mesh_lod_count
		if source:
			source.lod_count = mesh_lod_count

@export_group("Rendering")

## The ShaderMaterial assigned to all meshes in this clipmap.
@export var material: ShaderMaterial:
	set(value):
		if material == value:
			return
		material = value
		if not is_node_ready():
			return
		if material:
			_mesh_handler.material_rid = material.get_rid()
		else:
			_mesh_handler.material_rid = RID()

@export_flags_3d_render var render_layer: int = 1:
	set(value):
		if render_layer == value:
			return
		render_layer = value
		if not is_node_ready():
			return
		_mesh_handler.render_layer = render_layer

@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		if cast_shadows == value:
			return
		cast_shadows = value
		if not is_node_ready():
			return
		_mesh_handler.cast_shadows = cast_shadows as RenderingServer.ShadowCastingSetting

@export_group("Collision", "collision")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var collision_enabled: bool = true:
	set(value):
		if collision_enabled == value:
			return
		collision_enabled = value
		if not is_node_ready():
			return
		if _collision_handler:
			_collision_handler.enabled = collision_enabled

@export var collision_mesh_radius := Vector2i(4, 4):
	set(value):
		if collision_mesh_radius == value:
			return
		collision_mesh_radius = value
		if not is_node_ready():
			return
		if _collision_handler:
			_collision_handler.mesh_size = collision_mesh_radius

## WIP: must currently only contain the follow target
@export var collision_targets: Array[PhysicsBody3D]

@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		if collision_layer == value:
			return
		collision_layer = value
		if not is_node_ready():
			return
		if _collision_handler:
			_collision_handler.collision_layer = collision_layer

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		if collision_mask == value:
			return
		collision_mask = value
		if not is_node_ready():
			return
		if _collision_handler:
			_collision_handler.collision_mask = collision_mask

@export_group("Debug")

@export var generate_debug_canvas_items: bool = false

var _mesh_handler: Clipmap3DMeshHandler
var _collision_handler: Clipmap3DCollisionHandler
var _last_p := Vector3(INF, INF, INF)

func _enter_tree() -> void:
	request_ready()

func _ready():
	if not _mesh_handler:
		_mesh_handler = Clipmap3DMeshHandler.new()
		_mesh_handler.source = source
		_mesh_handler.vertex_spacing = mesh_vertex_spacing
		_mesh_handler.tile_size = mesh_tile_size
		_mesh_handler.lod_count = mesh_lod_count
		_mesh_handler.cast_shadows = cast_shadows
		_mesh_handler.render_layer = render_layer
		if material:
			_mesh_handler.material_rid = material.get_rid()
		
	_mesh_handler.visible = is_visible_in_tree()
	_mesh_handler.scenario_rid = get_world_3d().scenario
	
	_mesh_handler.build()
	
	if Engine.is_editor_hint():
		set_physics_process(false)
	else:
		if not _collision_handler:
			_collision_handler = Clipmap3DCollisionHandler.new()
			_collision_handler.source = source
			_collision_handler.mesh_radius = collision_mesh_radius
			_collision_handler.enabled = collision_enabled
			_collision_handler.collision_layer = collision_layer
			_collision_handler.collision_mask = collision_mask
			_collision_handler.vertex_spacing = mesh_vertex_spacing
			
		_collision_handler.space = get_world_3d().space
		_collision_handler.build()
			
	_update_position()
	
	if source:
		source.size = _mesh_handler.get_vertices()
		source.vertex_spacing = mesh_vertex_spacing
		source.lod_count = mesh_lod_count
		source.collision_enabled = collision_enabled # HACK
		source.build()
		if generate_debug_canvas_items and not Engine.is_editor_hint():
			var node_2d := Node2D.new()
			add_child(node_2d)
			source.create_debug_canvas_items(node_2d)
	
func _exit_tree() -> void:
	_mesh_handler.clear()
	if _collision_handler:
		_collision_handler.clear()

func _process(_delta: float) -> void:
	_update_position()

func _update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if global_position == _last_p:
		return
	
	_last_p = global_position
	_mesh_handler.target_position = global_position
	if _collision_handler:
		_collision_handler.target_position = global_position
	if source:
		source.world_origin = Vector2(global_position.x, global_position.z)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			if source:
				source.clear()
			_mesh_handler.scenario_rid = RID()
		NOTIFICATION_VISIBILITY_CHANGED:
			_mesh_handler.visible = is_visible_in_tree()
