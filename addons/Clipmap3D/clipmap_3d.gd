@icon("icons/clipmap_3d_icon.svg")
@tool
class_name Clipmap3D extends Node3D

## The Node3D which the terrain snaps to on the X and Z axes. If unassigned, camera is used.
@export var follow_target: Node3D

@export var compute_data: Clipmap3DComputeData:
	set(value):
		compute_data = value
		_compute_handler.compute_data = compute_data

@export var texture_assets: Array[Clipmap3DTextureAsset]:
	set(value):
		texture_assets = value
		_texture_handler.texture_assets = texture_assets

@export_group("Mesh", "mesh")

# NOTE: Lower limit of 2 because of https://github.com/godotengine/godot/issues/115103
## The amount of level of detail (LOD) rings that form this mesh.
@export_range(2, 16, 1) var mesh_lod_count: int = 5:
	set(value):
		mesh_lod_count = value
		_mesh_handler.lod_count = mesh_lod_count
		_compute_handler.lod_count = mesh_lod_count
		
## The base tile size used to build the clipmap.
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		mesh_tile_size = value.clampi(1, 128)
		_mesh_handler.tile_size = mesh_tile_size
		_compute_handler.tile_size = mesh_tile_size

@export_group("Rendering")

## The ShaderMaterial assigned to all meshes in this clipmap.
@export var material: ShaderMaterial:
	set(value):
		material = value
		_mesh_handler.material = material
		_compute_handler.material = material
		_texture_handler.material = material

@export_flags_3d_render var render_layer: int = 1:
	set(value):
		render_layer = value
		_mesh_handler.render_layer = render_layer

# NOTE: Manual enum is used since directly exporting looks different than other Godot editor properties of this type
@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		cast_shadows = value
		_mesh_handler.cast_shadows = cast_shadows as RenderingServer.ShadowCastingSetting

@export var aabb_height: float = 10000.0:
	set(value):
		aabb_height = value
		_mesh_handler.aabb_height = aabb_height

@export_group("Collision", "collision")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		if (debug_visible_collision_shapes or not Engine.is_editor_hint()) and collision_enabled:
			_collision_handler.build()
		else:
			_collision_handler.clear()

@export_range(0, 16) var collision_lod: int = 2:
	set(value):
		collision_lod = value
		_collision_handler.collision_lod = collision_lod

@export var collision_mesh_radius := Vector2i(4, 4):
	set(value):
		collision_mesh_radius = value
		_collision_handler.mesh_radius = collision_mesh_radius
	
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		_collision_handler.collision_layer = collision_layer

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		_collision_handler.collision_mask = collision_mask

@export var collision_physics_material: PhysicsMaterial:
	set(value):
		collision_physics_material = value
		_collision_handler.physics_material = collision_physics_material

@export var collision_priority: int:
	set(value):
		collision_priority = value
		_collision_handler.collision_priority = collision_priority

@export_group("Debug", "debug")

@export var debug_visible_collision_shapes: bool:
	set(value):
		debug_visible_collision_shapes = value
		_collision_handler.debug_visible_collision_shapes = debug_visible_collision_shapes
		if (debug_visible_collision_shapes or not Engine.is_editor_hint()) and collision_enabled:
			_collision_handler.build()
		else:
			_collision_handler.clear()
			print("Cleared.")

@export var debug_visible_buffers: bool:
	set(value):
		debug_visible_buffers = value

var _compute_handler := Clipmap3DComputeHandler.new()
var _mesh_handler := Clipmap3DMeshHandler.new()
var _texture_handler := Clipmap3DTextureHandler.new()
var _collision_handler := Clipmap3DCollisionHandler.new()

func _enter_tree() -> void:
	request_ready()

func _ready():
	# TODO: check if setting in ready is even necessary. Godot sets @export variables when adding to tree.
	_compute_handler.compute_data = compute_data
	_compute_handler.lod_count = mesh_lod_count
	_compute_handler.tile_size = mesh_tile_size
	_compute_handler.material = material

	_mesh_handler.tile_size = mesh_tile_size
	_mesh_handler.lod_count = mesh_lod_count
	_mesh_handler.cast_shadows = cast_shadows
	_mesh_handler.render_layer = render_layer
	_mesh_handler.material = material
	_mesh_handler.visible = is_visible_in_tree()
	_mesh_handler.scenario_rid = get_world_3d().scenario
	_mesh_handler.aabb_height = aabb_height
	
	_collision_handler.compute_handler = _compute_handler
	_collision_handler.mesh_radius = collision_mesh_radius
	_collision_handler.collision_layer = collision_layer
	_collision_handler.collision_mask = collision_mask
	_collision_handler.physics_material = collision_physics_material
	_collision_handler.collision_lod = collision_lod
	_collision_handler.space_rid = get_world_3d().space
	_collision_handler.instance_id = get_instance_id()
	_collision_handler.debug_visible_collision_shapes = debug_visible_collision_shapes
	
	_texture_handler.texture_assets = texture_assets
	_texture_handler.material = material
	
	_update_position()
	
	_compute_handler.build()
	_mesh_handler.build()
	_texture_handler.build()
	if (debug_visible_collision_shapes or not Engine.is_editor_hint()) and collision_enabled:
		_collision_handler.build()
	
func _exit_tree() -> void:
	_compute_handler.clear()
	_mesh_handler.clear()
	_texture_handler.clear()
	_collision_handler.clear()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			_mesh_handler.scenario_rid = RID()
			_collision_handler.space_rid = RID()
		NOTIFICATION_VISIBILITY_CHANGED:
			_mesh_handler.visible = is_visible_in_tree()

@warning_ignore("unused_parameter")
func _process(dt: float) -> void:
	_update_position()

func _update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	else:
		var camera: Camera3D
		if Engine.is_editor_hint():
			camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		else:
			camera = get_viewport().get_camera_3d()
		
		if camera:
			global_position.x = camera.global_position.x
			global_position.z = camera.global_position.z
	
	_compute_handler.target_transform = global_transform
	_mesh_handler.target_transform = global_transform
	_collision_handler.target_transform = global_transform
	if material:
		material.set_shader_parameter(&"_target_transform", global_transform)
