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

@export_group("Height", "height")
@export var height_map: HeightMap
@export var height_map_origin_snap := Vector2i(4, 4)

@export_group("Mesh", "mesh")
@export var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		if mesh_vertex_spacing == value:
			return
		mesh_vertex_spacing = value
		if not is_node_ready():
			return
		if shader_material:
			shader_material.set_shader_parameter(&"vertex_spacing", mesh_vertex_spacing)
		snap_to_target(true)
		
@export var mesh_size: int = 32:
	set(value):
		if mesh_size == value:
			return
		mesh_size = value
		if not is_node_ready():
			return
		initialize()

@export_range(1, 10, 1) var mesh_lods: int = 5:
	set(value):
		if mesh_lods == value:
			return
		mesh_lods = value
		if not is_node_ready():
			return
		initialize()

@export_group("Collision", "collision")

@export var shader_material: ShaderMaterial:
	set(value):
		if shader_material == value:
			return
		shader_material = value
		if not is_node_ready():
			return
		if shader_material:
			_clipmap.update_material(shader_material.get_rid())

@export_flags_3d_render var render_mask: int = 1:
	set(value):
		if render_mask == value:
			return
		render_mask = value
		if not is_node_ready():
			return
		_clipmap.update_layer_mask(render_mask)

@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		if cast_shadows == value:
			return
		cast_shadows = value
		if not is_node_ready():
			return
		_clipmap.update_cast_shadows(cast_shadows as RenderingServer.ShadowCastingSetting)

var _clipmap := Clipmap.new()

func _ready():
	initialize()
	
	_clipmap.update_layer_mask(render_mask)
	_clipmap.update_cast_shadows(cast_shadows as RenderingServer.ShadowCastingSetting)
	if shader_material:
		_clipmap.update_material(shader_material.get_rid())
		shader_material.set_shader_parameter(&"vertex_spacing", mesh_vertex_spacing)
	
	_update_shader_params()
	height_map.changed.connect(_update_shader_params)

func _process(_delta: float) -> void:
	snap_to_target()

func _exit_tree() -> void:
	_clipmap.clear()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			snap_to_target()
		NOTIFICATION_ENTER_WORLD:
			_clipmap.update_scenario(get_world_3d().scenario)
		NOTIFICATION_VISIBILITY_CHANGED:
			_clipmap.update_visible(is_visible_in_tree())
	
func initialize():
	if not is_inside_tree():
		return
	
	_clipmap.generate(mesh_size, mesh_lods, get_world_3d().scenario)
	var amplitude: float = 0.1
	if height_map:
		amplitude = height_map.amplitude
	_clipmap.update_aabbs(amplitude)
	
	snap_to_target(true)
	_update_target_priority()

func snap_to_target(force: bool = false) -> void:
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
		
	_clipmap.snap_to_target(target_p_2d, mesh_vertex_spacing, force)

func _update_shader_params():
	if not shader_material or not height_map:
		return
	shader_material.set_shader_parameter(&"map_origin", height_map.origin)
	shader_material.set_shader_parameter(&"height_map", height_map.get_texture())
	shader_material.set_shader_parameter(&"amplitude", height_map.amplitude)
	
func _update_target_priority():
	var target_node_exists := is_instance_valid(target_node)
	set_process(target_node_exists)
	set_notify_transform(not target_node_exists)
