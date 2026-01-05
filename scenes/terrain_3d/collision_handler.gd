class_name Terrain3DCollisionHandler

var _height_map: HeightMap
var _vertex_spacing: Vector2

var _body_rid: RID
var _shape_rids: Array[RID]
var _shape_xzs: PackedVector2Array

var _target_bodies: Array[PhysicsBody3D]

var _template_faces: PackedVector3Array

func _on_height_map_changed():
	pass
	# generate again
	
func initialize(height_map: HeightMap, size: Vector2i, vertex_spacing: Vector2, space: RID):
	if height_map:
		_height_map = height_map
		height_map.changed.connect(_on_height_map_changed)
	
	_body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_space(_body_rid, space)
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	
	var template_plane := PlaneMesh.new()
	template_plane.size = vertex_spacing * Vector2(size)
	template_plane.subdivide_width = size.x - 1
	template_plane.subdivide_depth = size.y - 1
	_template_faces = template_plane.get_faces()
	
	_vertex_spacing = vertex_spacing

func update():
	for i: int in _target_bodies.size():
		var target_body: PhysicsBody3D = _target_bodies[i]
		if not target_body:
			remove_body(target_body)
			continue
		
		var target_p := target_body.global_position
		var target_xz := Vector2(target_p.x, target_p.z).snapped(_vertex_spacing)
		if _shape_xzs[i].is_equal_approx(target_xz):
			continue
			
		_shape_xzs[i] = target_xz
		
		_build_mesh(i, target_xz)
	
func update_height_map(height_map: HeightMap):
	pass

func update_vertex_spacing(vertex_spacing: Vector2):
	pass

func update_mesh_size(mesh_size: Vector2i):
	pass

func _build_mesh(shape_index: int, xz: Vector2):
	for i: int in _template_faces.size():
		var v_world := Vector2(_template_faces[i].x, _template_faces[i].z) + xz
		_template_faces[i].y = _height_map.sample(v_world, _vertex_spacing)
	
	var shape_rid := _shape_rids[shape_index]
	PhysicsServer3D.shape_set_data(shape_rid, {"faces": _template_faces, "backface_collision": false})
	PhysicsServer3D.body_set_shape_transform(_body_rid, shape_index, Transform3D(Basis.IDENTITY, Vector3(xz.x, 0.0, xz.y)))
	
func clear():
	_target_bodies.clear()
	PhysicsServer3D.free_rid(_body_rid)
	for rid: RID in _shape_rids:
		PhysicsServer3D.free_rid(rid)
	_shape_rids.clear()
	
func add_bodies(target_bodies: Array[PhysicsBody3D]):
	target_bodies.map(add_body)

func add_body(target_body: PhysicsBody3D):
	if not target_body or not target_body.is_inside_tree():
		push_error("Given target body is invalid.")
		return
	
	_target_bodies.append(target_body)
	
	var target_p := target_body.global_position
	var target_xz := Vector2(target_p.x, target_p.z).snapped(_vertex_spacing)
	_shape_xzs.append(target_xz)
	
	var shape_rid := PhysicsServer3D.concave_polygon_shape_create()
	_shape_rids.append(shape_rid)
	
	PhysicsServer3D.body_add_shape(_body_rid, shape_rid)
	
	# TODO: height map null check
	_build_mesh(_shape_rids.size() - 1, target_xz)

func remove_body(body: PhysicsBody3D):
	pass
	
func update_layers(physics_layers: int):
	pass

func update_bodies(physics_bodies: int):
	pass
