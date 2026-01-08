class_name Terrain3DCollisionHandler

var _terrain_source: Terrain3DSource
var _height_amplitude: float
var _vertex_spacing: Vector2
var _mesh_size: Vector2i
var _y_position: float

var _body_rid: RID
var _shape_rids: Array[RID]
var _shape_xzs: PackedVector2Array

var _targets: Array[PhysicsBody3D]

var _template_faces: PackedVector3Array

func initialize(terrain: Terrain3D):
	assert(not _terrain_source) # double initialization not supported yet
	_terrain_source = terrain.terrain_source
	if _terrain_source:
		_terrain_source.changed.connect(update)
	_vertex_spacing = terrain.mesh_vertex_spacing
	_mesh_size = terrain.collision_mesh_size
	_height_amplitude = terrain.height_amplitude
	_y_position = terrain.global_position.y
		
	_body_rid = PhysicsServer3D.body_create()
	
	PhysicsServer3D.body_set_space(_body_rid, terrain.get_world_3d().space)
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	PhysicsServer3D.body_set_collision_layer(_body_rid, terrain.collision_layer)
	PhysicsServer3D.body_set_collision_mask(_body_rid, terrain.collision_mask)
	
	_generate_template_faces()
	
	terrain.collision_targets.map(add_target)
	
func _generate_template_faces():
	var template_plane := PlaneMesh.new()
	template_plane.size = _vertex_spacing * Vector2(_mesh_size)
	template_plane.subdivide_width = _mesh_size.x - 1
	template_plane.subdivide_depth = _mesh_size.y - 1
	_template_faces = template_plane.get_faces()
	
func update():
	for i: int in _targets.size():
		var target_body: PhysicsBody3D = _targets[i]
		if not target_body:
			remove_target(target_body)
			continue
		
		var target_p := target_body.global_position
		var target_xz := Vector2(target_p.x, target_p.z).snapped(_vertex_spacing)
		if _shape_xzs[i].is_equal_approx(target_xz):
			continue
			
		_shape_xzs[i] = target_xz
		
		_build_mesh(i, target_xz)
	
func update_terrain_source(terrain_source: Terrain3DSource):
	if _terrain_source:
		_terrain_source.refreshed.disconnect(update)
	_terrain_source = terrain_source
	if _terrain_source:
		_terrain_source.refreshed.connect(update)

func update_vertex_spacing(vertex_spacing: Vector2):
	_vertex_spacing = vertex_spacing
	
	_generate_template_faces()
	update()

func update_mesh_size(mesh_size: Vector2i):
	_mesh_size = mesh_size
	
	_generate_template_faces()
	update()

func update_height_amplitude(amplitude: float):
	_height_amplitude = amplitude
	
	update()

func update_y_position(y_position: float):
	_y_position = y_position
	update()
	
func update_collision_layer(physics_layer: int):
	PhysicsServer3D.body_set_collision_layer(_body_rid, physics_layer)
	
func update_collision_mask(physics_mask: int):
	PhysicsServer3D.body_set_collision_mask(_body_rid, physics_mask)
	
func _build_mesh(shape_index: int, xz: Vector2):
	for i: int in _template_faces.size():
		var v_world := Vector2(_template_faces[i].x, _template_faces[i].z) + xz
		_template_faces[i].y = _terrain_source.sample(v_world, _height_amplitude, _vertex_spacing) + _y_position
	
	var shape_rid := _shape_rids[shape_index]
	PhysicsServer3D.shape_set_data(shape_rid, {"faces": _template_faces, "backface_collision": false})
	PhysicsServer3D.body_set_shape_transform(_body_rid, shape_index, Transform3D(Basis.IDENTITY, Vector3(xz.x, 0.0, xz.y)))
	
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
	
	var target_p := target_body.global_position
	var target_xz := Vector2(target_p.x, target_p.z).snapped(_vertex_spacing)
	_shape_xzs.append(target_xz)
	
	var shape_rid := PhysicsServer3D.concave_polygon_shape_create()
	_shape_rids.append(shape_rid)
	
	PhysicsServer3D.body_add_shape(_body_rid, shape_rid)
	
	# TODO: height map null check
	_build_mesh(_shape_rids.size() - 1, target_xz)

func remove_target(body: PhysicsBody3D):
	pass
