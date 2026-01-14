@tool
class_name Clipmap3D extends Node3D

# TODO: rename to Clipmap3D
# TODO: fix vertex spacing origin issue

@export var source: Clipmap3DSource:
	set(value):
		if source == value:
			return
		source = value
		if not is_node_ready():
			return
		_mesh_handler.update_source(source)
		if not Engine.is_editor_hint():
			_collision_handler.update_source(source)

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

@export_group("Mesh", "mesh")

@export var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		if mesh_vertex_spacing == value:
			return
		mesh_vertex_spacing = value
		if not is_node_ready():
			return
		_mesh_handler.update_vertex_spacing(mesh_vertex_spacing)
		update_position(true)
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
		if source:
			source.create_maps(4 * mesh_tile_size + Vector2i.ONE * 8, mesh_lod_count)

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

var _mesh_handler: Clipmap3DMeshHandler
var _collision_handler: Clipmap3DCollisionHandler
var _last_p: Vector3

signal position_changed(new_position: Vector3)

func _init() -> void:
	_mesh_handler = Clipmap3DMeshHandler.new()
	if not Engine.is_editor_hint():
		_collision_handler = Clipmap3DCollisionHandler.new()
	
@onready var node_2d: Node2D = $Node2D
var sprites: Array[Sprite2D]

func _ready():
	_mesh_handler.initialize(self)
	if not Engine.is_editor_hint():
		_collision_handler.initialize(self)
	
	set_physics_process(not Engine.is_editor_hint())
	
	_last_p = Vector3(INF, INF, INF)
	
	update_position(true)
	
	if not source:
		return
	# 6x6 skirt
	source.create_maps(4 * mesh_tile_size + (2 + 6) * Vector2i.ONE, mesh_lod_count)
	
	if not Engine.is_editor_hint():
		var images := source.get_height_images()
		source.refreshed.connect(_update_images)
		
		for lod: int in mesh_lod_count:
			var sprite := Sprite2D.new()
			node_2d.add_child(sprite)
			sprite.texture = ImageTexture.create_from_image(images[lod])
			sprite.centered = false
			sprite.position = Vector2.ONE * 3.0
			sprite.position.x += (sprite.texture.get_width() + 3.0) * lod
			sprites.append(sprite)

func _update_images():
	var images := source.get_height_images()
	
	for lod: int in images.size():
		sprites[lod].texture = ImageTexture.create_from_image(images[lod])
	
func _exit_tree() -> void:
	_mesh_handler.clear()
	if not Engine.is_editor_hint():
		_collision_handler.clear()
	request_ready()

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

func update_position(force: bool = false):
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if force:
		_last_p = Vector3(INF, INF, INF)
	
	if global_position == _last_p:
		return
	
	if global_position.x != _last_p.x or global_position.z != _last_p.z:
		var target_xz := Vector2(global_position.x, global_position.z)
		_mesh_handler.snap(target_xz, force)
		if source:
			source.origin = target_xz / mesh_vertex_spacing
			if source.has_maps():
				source.shift_maps()
	if global_position.y != _last_p.y:
		_mesh_handler.update_y_position(global_position.y)
		if not Engine.is_editor_hint():
			_collision_handler.update_y_position(global_position.y)
	
	_last_p = global_position
	position_changed.emit(global_position)
