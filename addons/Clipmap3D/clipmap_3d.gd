@icon("icons/clipmap_3d_icon.svg")
@tool
class_name Clipmap3D extends Node3D

## The Node3D which the terrain snaps to on the X and Z axes.
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

# TODO: use scale, it does the same thing. Then, can just pass the transform.
## World spacing between vertices. Power-of-two values are recommended.
@export_custom(PROPERTY_HINT_LINK, "suffix:m") var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		mesh_vertex_spacing = value
		_mesh_handler.vertex_spacing = mesh_vertex_spacing
		_compute_handler.vertex_spacing = mesh_vertex_spacing
		_update_material()

## The base tile size used to build the clipmap.
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		mesh_tile_size = value.clampi(1, 128)
		_mesh_handler.tile_size = mesh_tile_size
		_compute_handler.tile_size = mesh_tile_size

# NOTE: lower limit of 2 because of https://github.com/godotengine/godot/issues/115103
# NOTE: upper limit of 10 rings is arbitrary
## The amount of level of detail (LOD) rings that form this mesh.
@export_range(2, 10, 1) var mesh_lod_count: int = 5:
	set(value):
		mesh_lod_count = value
		_mesh_handler.lod_count = mesh_lod_count
		_compute_handler.lod_count = mesh_lod_count

@export_group("Rendering")

## The ShaderMaterial assigned to all meshes in this clipmap.
@export var material: ShaderMaterial:
	set(value):
		material = value
		_mesh_handler.material = material
		_compute_handler.material = material
		_update_material()

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

@export var collision_mesh_radius := Vector2i(4, 4):
	set(value):
		collision_mesh_radius = value
	
## WIP: must currently only contain the follow target
@export var collision_targets: Array[PhysicsBody3D]

@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value

@export_group("Debug")

@export var generate_debug_canvas_items: bool = false

var _compute_handler := Clipmap3DComputeHandler.new()
var _mesh_handler := Clipmap3DMeshHandler.new()
#var _collision_handler: Clipmap3DCollisionHandler
var _texture_handler := Clipmap3DTextureHandler.new()

var _last_position := Vector3(INF, INF, INF)

func _enter_tree() -> void:
	request_ready()

func _ready():
	# TODO: check if setting in ready is even necessary. Godot sets @export variables when adding to tree.
	_compute_handler.compute_data = compute_data
	_compute_handler.lod_count = mesh_lod_count
	_compute_handler.tile_size = mesh_tile_size
	_compute_handler.vertex_spacing = mesh_vertex_spacing
	_compute_handler.material = material

	_mesh_handler.vertex_spacing = mesh_vertex_spacing
	_mesh_handler.tile_size = mesh_tile_size
	_mesh_handler.lod_count = mesh_lod_count
	_mesh_handler.cast_shadows = cast_shadows
	_mesh_handler.render_layer = render_layer
	_mesh_handler.material = material
	_mesh_handler.visible = is_visible_in_tree()
	_mesh_handler.scenario_rid = get_world_3d().scenario
	_mesh_handler.aabb_height = aabb_height
	
	_texture_handler.texture_assets = texture_assets
	_texture_handler.material = material
	
	_update_position()
	
	_compute_handler.build()
	_mesh_handler.build()
	_texture_handler.build()
	
	_update_material()

func _exit_tree() -> void:
	_compute_handler.clear()
	_mesh_handler.clear()
	_texture_handler.clear()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			_mesh_handler.scenario_rid = RID()
		NOTIFICATION_VISIBILITY_CHANGED:
			_mesh_handler.visible = is_visible_in_tree()

func _process(_delta: float) -> void:
	_update_position()

func _update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if global_position == _last_position:
		return
	_last_position = global_position
	
	_compute_handler.world_origin = Vector2(global_position.x, global_position.z)
	_mesh_handler.target_position = global_position

func _update_material():
	
	# TODO: just pass the transform. Get rid of vertex spacing.
	material.set_shader_parameter(&"_vertex_spacing", mesh_vertex_spacing)
	material.set_shader_parameter(&"_target_position", _last_position)
