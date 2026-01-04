class_name Terrain3DCollisionHandler

var _height_map: HeightMap
var _vertex_spacing: Vector2
var _space: RID

var _body_rids: Array[RID]
var _shape_rids: Array[RID]
var _body_xzs: PackedVector2Array

var _target_bodies: Array[PhysicsBody3D]

var _template_faces: PackedVector3Array

func _on_height_map_changed():
	pass
	# generate again
	
func initialize(height_map: HeightMap, size: Vector2i, vertex_spacing: Vector2, space: RID):
	if height_map:
		_height_map = height_map
		height_map.changed.connect(_on_height_map_changed)
	
	var template_plane := PlaneMesh.new()
	template_plane.size = vertex_spacing * Vector2(size)
	template_plane.subdivide_width = size.x - 1
	template_plane.subdivide_depth = size.y - 1
	_template_faces = template_plane.get_faces()
	
	_vertex_spacing = vertex_spacing
	
	_space = space

func update():
	for i: int in _target_bodies.size():
		var target_body: PhysicsBody3D = _target_bodies[i]
		if not target_body:
			remove_body(target_body)
			continue
		
		var target_p := target_body.global_position
		var target_xz := Vector2(target_p.x, target_p.z).snapped(_vertex_spacing)
		if _body_xzs[i].is_equal_approx(target_xz):
			continue
			
		_body_xzs[i] = target_xz
		
		PhysicsServer3D.body_set_state(_body_rids[i], PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, Vector3(target_xz.x, 0.0, target_xz.y)))
		
		for j: int in _template_faces.size():
			var v_world := Vector2(_template_faces[j].x, _template_faces[j].z) + target_xz
			_template_faces[j].y = _height_map.sample(v_world, _vertex_spacing)
		
		PhysicsServer3D.shape_set_data(_shape_rids[i], {"faces": _template_faces, "backface_collision": false})
	
func update_height_map(height_map: HeightMap):
	pass

func update_vertex_spacing(vertex_spacing: Vector2):
	pass

func update_mesh_size(mesh_size: Vector2i):
	pass
	
func clear():
	_target_bodies.clear()
	for rid: RID in _body_rids + _shape_rids:
		PhysicsServer3D.free_rid(rid)

func add_bodies(target_bodies: Array[PhysicsBody3D]):
	target_bodies.map(add_body)

func add_body(target_body: PhysicsBody3D):
	if not target_body or not target_body.is_inside_tree():
		push_error("Given target body is invalid.")
		return
	
	_target_bodies.append(target_body)
	
	var target_p := target_body.global_position
	var target_xz := Vector2(target_p.x, target_p.z).snapped(_vertex_spacing)
	_body_xzs.append(target_xz)
	
	# TODO: height map may be null, move this to update shape func anyway
	for i: int in _template_faces.size():
		var v_world := Vector2(_template_faces[i].x, _template_faces[i].z) + target_xz
		_template_faces[i].y = _height_map.sample(v_world, _vertex_spacing)
	
	var body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_space(body_rid, _space)
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, Vector3(target_xz.x, 0.0, target_xz.y)))
	_body_rids.append(body_rid)
	
	var shape_rid = PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape_rid, {"faces": _template_faces, "backface_collision": false})
	PhysicsServer3D.body_add_shape(body_rid, shape_rid)
	PhysicsServer3D.body_set_shape_transform(body_rid, 0, Transform3D.IDENTITY)
	_shape_rids.append(shape_rid)

#func update_shape():
	#var xform := global_transform
	#for i: int in _faces.size():
		#var v_world := xform * _faces[i]
		#_faces[i].y = sample_height(Vector2(v_world.x, v_world.z))
		#
	#_polygon_shape.set_faces(_faces)

func remove_body(body: PhysicsBody3D):
	pass
	
func update_layers(physics_layers: int):
	pass

func update_bodies(physics_bodies: int):
	pass
