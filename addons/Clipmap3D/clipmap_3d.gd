@icon("icons/clipmap_3d_icon.svg")
@tool
class_name Clipmap3D extends Node3D

const MAX_TEXTURE_COUNT: int = 32

## The Node3D which the terrain snaps to on the X and Z axes.
@export var follow_target: Node3D

# TODO: turn this category into a resource
@export_group("Compute")

@export var compute_shader: RDShaderFile:
	set(value):
		compute_shader = value
		if _compute_handler:
			_compute_handler.compute_shader = compute_shader

## The random number seed passed to the compute shader.
@export var compute_seed: int = 0:
	set(value):
		compute_seed = value
		if _compute_handler:
			_compute_handler.compute_seed = compute_seed

@export var texels_per_vertex := Vector2i.ONE:
	set(value):
		texels_per_vertex = value.maxi(1)
		if _compute_handler:
			_compute_handler.texels_per_vertex = texels_per_vertex
		_update_material()

@export var max_height: float = 10000.0:
	set(value):
		max_height = value
		if _mesh_handler:
			_mesh_handler.max_height = max_height

#@export var texture_assets: Array[Clipmap3DTextureAsset]:
	#set(value):
		#texture_assets = value


@export_group("Mesh", "mesh")

## World spacing between vertices. Power-of-two values are recommended.
@export_custom(PROPERTY_HINT_LINK, "suffix:m") var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		mesh_vertex_spacing = value
		if _mesh_handler:
			_mesh_handler.vertex_spacing = mesh_vertex_spacing
		if _compute_handler:
			_compute_handler.vertex_spacing = mesh_vertex_spacing
		_update_material()

## The base tile size used to build the clipmap.
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		value = value.clampi(1, 128)
		mesh_tile_size = value
		if _mesh_handler:
			_mesh_handler.tile_size = mesh_tile_size
		if _compute_handler:
			_compute_handler.tile_size = mesh_tile_size
		_update_material()

# NOTE: lower limit of 2 because of https://github.com/godotengine/godot/issues/115103
# NOTE: upper limit of 10 rings is arbitrary
## The amount of level of detail (LOD) rings that form this mesh.
@export_range(2, 10, 1) var mesh_lod_count: int = 5:
	set(value):
		mesh_lod_count = value
		if _mesh_handler:
			_mesh_handler.lod_count = mesh_lod_count
		if _compute_handler:
			_compute_handler.lod_count = mesh_lod_count
		_update_material()

@export_group("Rendering")

## The ShaderMaterial assigned to all meshes in this clipmap.
@export var material: ShaderMaterial:
	set(value):
		material = value
		if _mesh_handler:
			_mesh_handler.material_rid = material.get_rid() if material else RID()
		_update_material()

@export_flags_3d_render var render_layer: int = 1:
	set(value):
		render_layer = value
		if _mesh_handler:
			_mesh_handler.render_layer = render_layer

# NOTE: Manual enum is used since directly exporting looks different than other Godot editor properties of this type
@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		cast_shadows = value
		_mesh_handler.cast_shadows = cast_shadows as RenderingServer.ShadowCastingSetting

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

var _compute_handler: Clipmap3DComputeHandler
var _mesh_handler: Clipmap3DMeshHandler
var _collision_handler: Clipmap3DCollisionHandler

var _last_position := Vector3(INF, INF, INF)

func _enter_tree() -> void:
	request_ready()

func _ready():
	if not _compute_handler:
		_compute_handler = Clipmap3DComputeHandler.new()
	
	_compute_handler.compute_shader = compute_shader
	_compute_handler.compute_seed = compute_seed
	_compute_handler.lod_count = mesh_lod_count
	_compute_handler.texels_per_vertex = texels_per_vertex
	_compute_handler.tile_size = mesh_tile_size
	_compute_handler.vertex_spacing = mesh_vertex_spacing
	
	if not _mesh_handler:
		_mesh_handler = Clipmap3DMeshHandler.new()
	
	_mesh_handler.vertex_spacing = mesh_vertex_spacing
	_mesh_handler.tile_size = mesh_tile_size
	_mesh_handler.lod_count = mesh_lod_count
	_mesh_handler.cast_shadows = cast_shadows
	_mesh_handler.render_layer = render_layer
	_mesh_handler.material_rid = material.get_rid() if material else RID()
	_mesh_handler.visible = is_visible_in_tree()
	_mesh_handler.scenario_rid = get_world_3d().scenario
	_mesh_handler.max_height = max_height
	
	_update_position() # This is already doing the update_state shit. Why not make a method that does all of it?
	
	_compute_handler.compute_finished.connect(_update_material)
	
	_compute_handler.build()
	_mesh_handler.build()
	

func _exit_tree() -> void:
	if _compute_handler:
		_compute_handler.clear()
	if _mesh_handler:
		_mesh_handler.clear()

func _process(_delta: float) -> void:
	_update_position()

func _update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if global_position == _last_position:
		return
	_last_position = global_position
	
	if _compute_handler:
		_compute_handler.world_origin = Vector2(global_position.x, global_position.z)
	if _mesh_handler:
		_mesh_handler.target_position = global_position

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			if _mesh_handler:
				_mesh_handler.scenario_rid = RID()
		NOTIFICATION_VISIBILITY_CHANGED:
			if _mesh_handler:
				_mesh_handler.visible = is_visible_in_tree()

## Material

func _update_material():
	if not material:
		return
	
	material.set_shader_parameter(&"_vertex_spacing", mesh_vertex_spacing)
	material.set_shader_parameter(&"_lod_count", mesh_lod_count)
	material.set_shader_parameter(&"_tile_size", mesh_tile_size)
	material.set_shader_parameter(&"_target_position", _last_position)
	
	material.set_shader_parameter(&"_texels_per_vertex", texels_per_vertex)
	
	if _compute_handler:
		material.set_shader_parameter(&"_height_maps", _compute_handler.get_height_buffer_rid())
		material.set_shader_parameter(&"_gradient_maps", _compute_handler.get_gradient_buffer_rid())
		material.set_shader_parameter(&"_control_maps", _compute_handler.get_control_buffer_rid())
