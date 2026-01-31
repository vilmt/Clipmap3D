class_name Clipmap3DCollisionHandler

var _source: Clipmap3DSource
var _vertex_spacing: Vector2
var _mesh_size: Vector2i
var _position_y: float

var _body_rid: RID
var _shape_rid: RID

var _static_body: StaticBody3D
var _shape: CollisionShape3D
var _shape_resource: HeightMapShape3D

var _template_faces: PackedVector3Array

func initialize(clipmap: Clipmap3D):
	_source = clipmap.source
	_connect_source()
	
	_static_body = clipmap.get_node("StaticBody3D")
	_shape = clipmap.get_node("StaticBody3D/CollisionShape3D")
	_shape_resource = _shape.shape
	
	_vertex_spacing = clipmap.mesh_vertex_spacing
	_mesh_size = clipmap.collision_mesh_size
	_position_y = clipmap.global_position.y
	
	_body_rid = PhysicsServer3D.body_create()
	
	PhysicsServer3D.body_set_space(_body_rid, clipmap.get_world_3d().space)
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	PhysicsServer3D.body_set_collision_layer(_body_rid, clipmap.collision_layer)
	PhysicsServer3D.body_set_collision_mask(_body_rid, clipmap.collision_mask)
	
	_shape_rid = PhysicsServer3D.heightmap_shape_create()
	PhysicsServer3D.body_add_shape(_body_rid, _shape_rid)
	
	clipmap.source_changed.connect(_on_source_changed)
	clipmap.mesh_vertex_spacing_changed.connect(_on_vertex_spacing_changed)
	clipmap.collision_mesh_size_changed.connect(_on_mesh_size_changed)
	clipmap.target_position_changed.connect(_on_target_position_changed)
	clipmap.collision_layer_changed.connect(_on_collision_layer_changed)
	clipmap.collision_mask_changed.connect(_on_collision_layer_changed)

func update():
	#print("updated")
	var data := _source.get_lod_0_data()
	var origin := _source.get_world_origin()
	var texel_origin := _source.get_lod_0_origin()
	var size := _source.get_lod_0_size()
	var step := _source.texels_per_vertex
	
	var heights := PackedFloat32Array()
	
	# TODO: do this in compute source
	for y: int in range(0, size.y, step.y):
		for x: int in range(0, size.x, step.x):
			var tx = posmod(x + texel_origin.x + ceili(float(size.x) / 2.0) + 1, size.x)
			var ty = posmod(y + texel_origin.y + ceili(float(size.y) / 2.0) + 1, size.y)
			var index = (tx + ty * size.x) * 4
			var h = data.decode_float(index)
			heights.append(h)
	
	var dict := {
		"width": size.x / step.x,
		"depth": size.y / step.y,
		"heights": heights
	}
	
	#_shape_resource.map_width = size.x / step.x
	#_shape_resource.map_depth = size.y / step.y
	#_shape_resource.map_data = heights
	#_shape.global_transform = Transform3D(Basis.IDENTITY, Vector3(origin.x, 0.0, origin.y))
	##
	PhysicsServer3D.shape_set_data(_shape_rid, dict)
	var o := Basis(Vector3(1.0, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, 1.0))
	var p := Vector3(origin.x, 0.0, origin.y)
	PhysicsServer3D.body_set_shape_transform(_body_rid, 0, Transform3D(o, p))
	
func _on_source_changed(source: Clipmap3DSource):
	_disconnect_source()
	_source = source
	_connect_source()

func _connect_source():
	if _source and not _source.lod_0_data_changed.is_connected(update):
		_source.lod_0_data_changed.connect(update)

func _disconnect_source():
	if _source and _source.lod_0_data_changed.is_connected(update):
		_source.lod_0_data_changed.disconnect(update)

func _on_vertex_spacing_changed(vertex_spacing: Vector2):
	_vertex_spacing = vertex_spacing
	

func _on_mesh_size_changed(mesh_size: Vector2i):
	_mesh_size = mesh_size

func _on_target_position_changed(target_position: Vector3):
	_position_y = target_position.y
	#update()
	
func _on_collision_layer_changed(physics_layer: int):
	PhysicsServer3D.body_set_collision_layer(_body_rid, physics_layer)
	
func _on_collision_mask_changed(physics_mask: int):
	PhysicsServer3D.body_set_collision_mask(_body_rid, physics_mask)
	
func clear():
	if _body_rid:
		PhysicsServer3D.free_rid(_body_rid)
	_body_rid = RID()
	if _shape_rid:
		PhysicsServer3D.free_rid(_shape_rid)
	_shape_rid = RID()
