@tool
class_name Clipmap3D extends Node3D

@export var source: Clipmap3DSource:
	set(value):
		if source == value:
			return
		_disconnect_source()
		source = value
		if not is_node_ready():
			return
		_connect_source()
		source_changed.emit(source)

@export var follow_target: Node3D

@export_group("Mesh", "mesh")

@export var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		if mesh_vertex_spacing == value:
			return
		mesh_vertex_spacing = value
		if not is_node_ready():
			return
		
		_recalculate_source_origin()
		mesh_vertex_spacing_changed.emit(mesh_vertex_spacing)
		
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		if mesh_tile_size == value:
			return
		mesh_tile_size = value
		if not is_node_ready():
			return
		mesh_tile_size_changed.emit(mesh_tile_size)

# NOTE: arbitrary lower limit of 2 because of https://github.com/godotengine/godot/issues/115103
@export_range(2, 10, 1) var mesh_lod_count: int = 5:
	set(value):
		if mesh_lod_count == value:
			return
		mesh_lod_count = value
		if not is_node_ready():
			return
		mesh_lod_count_changed.emit(mesh_lod_count)
		_mark_source_dirty()

@export_group("Rendering")

@export var material: ShaderMaterial:
	set(value):
		if material == value:
			return
		material = value
		if not is_node_ready():
			return
		material_changed.emit(material)
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
		render_layer_changed.emit(render_layer)

@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		if cast_shadows == value:
			return
		cast_shadows = value
		if not is_node_ready():
			return
		cast_shadows_changed.emit(cast_shadows as RenderingServer.ShadowCastingSetting)

@export_group("Collision", "collision")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var collision_enabled: bool = true:
	set(value):
		if collision_enabled == value:
			return
		collision_enabled = value
		if not is_node_ready():
			return
		collision_enabled_changed.emit(collision_enabled)

@export var collision_mesh_size := Vector2i(8, 8):
	set(value):
		if collision_mesh_size == value:
			return
		collision_mesh_size = value
		if not is_node_ready():
			return
		collision_mesh_size_changed.emit(collision_mesh_size)

# TODO: setters
@export var collision_targets: Array[PhysicsBody3D]

@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		if collision_layer == value:
			return
		collision_layer = value
		if not is_node_ready():
			return
		collision_layer_changed.emit(collision_layer)

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		if collision_mask == value:
			return
		collision_mask = value
		if not is_node_ready():
			return
		collision_mask_changed.emit(collision_mask)

var _mesh_handler: Clipmap3DMeshHandler
var _collision_handler: Clipmap3DCollisionHandler
var _last_p := Vector3(INF, INF, INF)

signal source_changed(new_value: Clipmap3DSource)
signal mesh_vertex_spacing_changed(new_value: Vector2)
signal mesh_tile_size_changed(new_value: Vector2i)
signal mesh_lod_count_changed(new_value: int)
signal material_changed(new_value: ShaderMaterial)
signal render_layer_changed(new_value: int)
signal cast_shadows_changed(new_value: RenderingServer.ShadowCastingSetting)
signal collision_enabled_changed(new_value: bool)
signal collision_mesh_size_changed(new_value: Vector2i)
signal collision_layer_changed(new_value: int)
signal collision_mask_changed(new_value: int)

signal target_position_changed(new_value: Vector3)

var _source_dirty: bool = true

func _mark_source_dirty():
	_source_dirty = true
	_rebuild_source.call_deferred()

func _rebuild_source():
	if _source_dirty:
		var target := Vector2(global_position.x, global_position.z)
		var size := 4 * mesh_tile_size + Vector2i.ONE * 8
		source.create_maps(target, size, mesh_lod_count, mesh_vertex_spacing)
	_source_dirty = false

func _enter_tree() -> void:
	request_ready()

func _ready():
	if not _mesh_handler:
		_mesh_handler = Clipmap3DMeshHandler.new()
		_mesh_handler.initialize(self)
	_mesh_handler.update_visible(is_visible_in_tree())
	_mesh_handler.update_scenario_rid(get_world_3d().scenario)
	if material:
		_mesh_handler.update_material_rid(material.get_rid())
	if source:
		_mesh_handler.update_height_amplitude(source.get_height_amplitude())
	_mesh_handler.generate()
	if not _collision_handler and not Engine.is_editor_hint():
		_collision_handler = Clipmap3DCollisionHandler.new()
		_collision_handler.initialize(self)
		
	set_physics_process(not Engine.is_editor_hint())
	
	_update_position()
	
	if source:
		_connect_source()
	
func _exit_tree() -> void:
	_mesh_handler.clear()
	if not Engine.is_editor_hint():
		_collision_handler.clear()

func _physics_process(_delta: float) -> void:
	_update_position()

func _update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if global_position == _last_p:
		return
	
	_last_p = global_position
	_recalculate_source_origin()
	target_position_changed.emit(global_position)

#func _physics_process(_delta: float) -> void:
	#_collision_handler.update()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			_mesh_handler.update_scenario_rid(RID())
		NOTIFICATION_VISIBILITY_CHANGED:
			_mesh_handler.update_visible(is_visible_in_tree())

func _connect_source():
	if not source or source.parameters_changed.is_connected(_mark_source_dirty):
		return
	source.maps_created.connect(_on_source_maps_created)
	source.amplitude_changed.connect(_on_source_amplitude_changed)
	source.parameters_changed.connect(_mark_source_dirty)
	mesh_tile_size_changed.connect(_mark_source_dirty)
	_mark_source_dirty()

func _disconnect_source():
	if not source or not source.parameters_changed.is_connected(_mark_source_dirty):
		return
	source.maps_created.disconnect(_on_source_maps_created)
	source.amplitude_changed.disconnect(_on_source_amplitude_changed)
	source.parameters_changed.disconnect(_mark_source_dirty)
	mesh_tile_size_changed.disconnect(_mark_source_dirty)

func _recalculate_source_origin():
	if not source or not source.has_maps():
		return
	# TODO: remake maps on vert spacing change
	source.shift_maps(Vector2(global_position.x, global_position.z))

func _on_source_amplitude_changed(amplitude: float):
	_mesh_handler.update_height_amplitude(amplitude)
	_mark_source_dirty()

func _on_source_maps_created():
	#pass
	_mesh_handler.update_map_rids(source.get_map_rids())
