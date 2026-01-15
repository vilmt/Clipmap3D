class_name Clipmap3DCollisionHandler

# TODO: cache values for rebuilding close meshes

var _source: Clipmap3DSource
var _vertex_spacing: Vector2
var _mesh_size: Vector2i
var _position_y: float

var _body_rid: RID
var _shape_rids: Array[RID]
var _shape_xzs: PackedVector2Array

var _targets: Array[PhysicsBody3D]

var _template_faces: PackedVector3Array

func initialize(clipmap: Clipmap3D):
	_source = clipmap.source
	if _source:
		_source.maps_created.connect(update.bind(true))
		_source.maps_redrawn.connect(update.bind(true))
	
	_vertex_spacing = clipmap.mesh_vertex_spacing
	_mesh_size = clipmap.collision_mesh_size
	_position_y = clipmap.global_position.y
	
	_body_rid = PhysicsServer3D.body_create()
	
	PhysicsServer3D.body_set_space(_body_rid, clipmap.get_world_3d().space)
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	PhysicsServer3D.body_set_collision_layer(_body_rid, clipmap.collision_layer)
	PhysicsServer3D.body_set_collision_mask(_body_rid, clipmap.collision_mask)
	
	_generate_template_faces()
	
	clipmap.collision_targets.map(add_target)
	
	clipmap.source_changed.connect(_on_source_changed)
	clipmap.mesh_vertex_spacing_changed.connect(_on_vertex_spacing_changed)
	clipmap.collision_mesh_size_changed.connect(_on_mesh_size_changed)
	clipmap.target_position_changed.connect(_on_target_position_changed)
	clipmap.collision_layer_changed.connect(_on_collision_layer_changed)
	clipmap.collision_mask_changed.connect(_on_collision_layer_changed)
	
func _generate_template_faces():
	var template_plane := PlaneMesh.new()
	template_plane.size = _vertex_spacing * Vector2(_mesh_size)
	template_plane.subdivide_width = _mesh_size.x - 1
	template_plane.subdivide_depth = _mesh_size.y - 1
	_template_faces = template_plane.get_faces()
	
func update(force: bool = false):
	for i: int in _targets.size():
		var target_body: PhysicsBody3D = _targets[i]
		if not target_body:
			remove_target(target_body)
			continue
		
		var target_xz := Vector2(target_body.global_position.x, target_body.global_position.z)
		var scale := _vertex_spacing * 1.0
		var target_xz_snapped := (target_xz / scale).floor() * scale
		if not force and _shape_xzs[i].is_equal_approx(target_xz_snapped):
			continue
			
		_shape_xzs[i] = target_xz_snapped
		
		_build_mesh(i, target_xz_snapped)
	
func _on_source_changed(source: Clipmap3DSource):
	if _source:
		_source.maps_created.disconnect(update)
		_source.maps_redrawn.disconnect(update)
	_source = source
	if _source:
		_source.maps_created.connect(update)
		_source.maps_redrawn.connect(update)

func _on_vertex_spacing_changed(vertex_spacing: Vector2):
	_vertex_spacing = vertex_spacing
	
	_generate_template_faces()
	#update()

func _on_mesh_size_changed(mesh_size: Vector2i):
	_mesh_size = mesh_size
	
	_generate_template_faces()
	#update()

func _on_target_position_changed(target_position: Vector3):
	_position_y = target_position.y
	#update()
	
func _on_collision_layer_changed(physics_layer: int):
	PhysicsServer3D.body_set_collision_layer(_body_rid, physics_layer)
	
func _on_collision_mask_changed(physics_mask: int):
	PhysicsServer3D.body_set_collision_mask(_body_rid, physics_mask)
	
func _build_mesh(shape_index: int, xz: Vector2):
	for i: int in _template_faces.size():
		var v_world := Vector2(_template_faces[i].x, _template_faces[i].z) + xz
		_template_faces[i].y = _source.sample(v_world, _vertex_spacing)
	
	var shape_rid := _shape_rids[shape_index]
	PhysicsServer3D.shape_set_data(shape_rid, {"faces": _template_faces, "backface_collision": false})
	PhysicsServer3D.body_set_shape_transform(_body_rid, shape_index, Transform3D(Basis.IDENTITY, Vector3(xz.x, _position_y, xz.y)))
	
func clear():
	_targets.clear()
	PhysicsServer3D.free_rid(_body_rid)
	for rid: RID in _shape_rids:
		PhysicsServer3D.free_rid(rid)
	_shape_rids.clear()

func add_target(target_body: PhysicsBody3D):
	if not target_body or not target_body.is_inside_tree():
		push_error("Given target body is invalid.")
		return
	
	_targets.append(target_body)
	
	var target_xz := Vector2(target_body.global_position.x, target_body.global_position.z)
	var scale := _vertex_spacing * 1.0
	var target_xz_snapped := (target_xz / scale).floor() * scale
	_shape_xzs.append(target_xz_snapped)
	
	var shape_rid := PhysicsServer3D.concave_polygon_shape_create()
	_shape_rids.append(shape_rid)
	
	PhysicsServer3D.body_add_shape(_body_rid, shape_rid)
	
	# TODO: height map null check
	_build_mesh(_shape_rids.size() - 1, target_xz_snapped)

func remove_target(body: PhysicsBody3D):
	pass
