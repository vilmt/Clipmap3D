@tool
class_name Clipmap3DCollisionHandler

# TODO: should not query data when not built

# NOTE: if adding holes to control map and mesh, will have to fetch that as well. Skip those triangles.
# TODO: enforce that the physics mesh is much smaller than the buffer.

# TODO: If built without compute handler, or if the data request fails, should just 
# build a flat plane and wait for either the compute handler to be assigned or for a new region to be generated.

var compute_handler: Clipmap3DComputeHandler:
	set(value):
		if compute_handler == value:
			return
		if compute_handler and compute_handler.region_updated.is_connected(_on_region_updated):
			compute_handler.region_updated.disconnect(_on_region_updated)
		compute_handler = value
		if compute_handler and not compute_handler.region_updated.is_connected(_on_region_updated):
			compute_handler.region_updated.connect(_on_region_updated)
		_schedule_update()

var space_rid: RID:
	set(value):
		if space_rid == value:
			return
		space_rid = value
		_body_needs_update = true
		_schedule_update()

var instance_id: int:
	set(value):
		if instance_id == value:
			return
		instance_id = value
		_body_needs_update = true
		_schedule_update()

# TODO: query
var target_transform: Transform3D:
	set(value):
		if target_transform == value:
			return
		target_transform = value

var mesh_radius: Vector2i:
	set(value):
		if mesh_radius == value:
			return
		mesh_radius = value
		_shape_needs_rebuild = true
		_schedule_update()

var collision_layer: int:
	set(value):
		if collision_layer == value:
			return
		collision_layer = value
		_body_needs_update = true
		_schedule_update()

var collision_mask: int:
	set(value):
		if collision_mask == value:
			return
		collision_mask = value
		_body_needs_update = true
		_schedule_update()

var physics_material: PhysicsMaterial:
	set(value):
		if physics_material == value:
			return
		if physics_material and physics_material.changed.is_connected(_on_physics_material_changed):
			physics_material.changed.disconnect(_on_physics_material_changed)
		physics_material = value
		if physics_material and not physics_material.changed.is_connected(_on_physics_material_changed):
			physics_material.changed.connect(_on_physics_material_changed)
		_on_physics_material_changed()

var collision_lod: int:
	set(value):
		if collision_lod == value:
			return
		collision_lod = value
		# TODO: must fetch the entire lod again
		# If does not exist, just build a flat plane and wait for region updates.
		
		_shape_needs_rebuild = true
		_schedule_update()

var collision_priority: int:
	set(value):
		collision_priority = value
		_body_needs_update = true
		_schedule_update()

var debug_visible_collision_shapes: bool:
	set(value):
		if debug_visible_collision_shapes == value:
			return
		debug_visible_collision_shapes = value
		_body_needs_rebuild = true
		_shape_needs_rebuild = true
		_schedule_update()
		
var _grid_to_face_indices: Array[PackedInt32Array]
var _faces: PackedVector3Array
var _safe_region: Rect2i
var _latest_data: PackedByteArray

var _built: bool = false
var _body_needs_rebuild: bool = false
var _body_needs_update: bool = false
var _shape_needs_rebuild: bool = false
var _shape_needs_update: bool = false

var _body_rid: RID
var _debug_body: StaticBody3D
var _shape_rid: RID
var _debug_shape: ConcavePolygonShape3D

func build():
	if _built:
		return
	_built = true
	_body_needs_rebuild = true
	_body_needs_update = true
	_shape_needs_rebuild = true
	_shape_needs_update = true
	
	_schedule_update()

func clear():
	if not _built:
		return
	_built = false
	_body_needs_rebuild = false
	_body_needs_update = false
	_shape_needs_rebuild = false
	_shape_needs_update = false
	
	_clear_shape()
	_clear_body()
	
func _schedule_update():
	_update.call_deferred()

func _update():
	if not _built:
		return
	
	if _shape_needs_rebuild:
		_clear_shape()
		_create_shape()
		_shape_needs_rebuild = false
		_body_needs_rebuild = true
		_shape_needs_update = true
	if _body_needs_rebuild:
		_clear_body()
		_create_body()
		_body_needs_rebuild = false
		_body_needs_update = true
	if _shape_needs_update:
		_update_shape()
		_shape_needs_update = false
	if _body_needs_update:
		_update_body()
		_body_needs_update = false

#region shape
func _create_shape():
	if debug_visible_collision_shapes:
		_debug_shape = ConcavePolygonShape3D.new()
	else:
		_shape_rid = PhysicsServer3D.concave_polygon_shape_create()
	
	var mesh_arrays: Array = []
	mesh_arrays.resize(RenderingServer.ARRAY_MAX)
	
	var scale := float(1 << collision_lod)
	
	#var half_size := Vector3(float(mesh_radius.x), 0.0, float(mesh_radius.y))
	
	var grid_vertex_count: int = (2 * mesh_radius.x + 1) * (2 * mesh_radius.y + 1)
	_grid_to_face_indices.resize(grid_vertex_count)
	for i: int in grid_vertex_count:
		_grid_to_face_indices[i] = PackedInt32Array()
	
	var grid := PackedVector3Array()
	for z: int in range(-mesh_radius.y, mesh_radius.y + 1):
		for x: int in range(-mesh_radius.x, mesh_radius.x + 1):
			grid.append(Vector3(float(x) * scale, 0.0, float(z) * scale))
	
	_faces.clear()
	for z: int in 2 * mesh_radius.y:
		for x: int in 2 * mesh_radius.x:
			var b_l: int = z * (2 * mesh_radius.x + 1) + x
			var b_r: int = b_l + 1
			var t_l: int = (z + 1) * (2 * mesh_radius.x + 1) + x
			var t_r: int = t_l + 1
			
			var face_index := _faces.size()
			
			# Face 1
			_faces.append(grid[b_l])
			_grid_to_face_indices[b_l].append(face_index + 0)
			_faces.append(grid[t_r])
			_grid_to_face_indices[t_r].append(face_index + 1)
			_faces.append(grid[t_l])
			_grid_to_face_indices[t_l].append(face_index + 2)
			
			# Face 2
			_faces.append(grid[b_l])
			_grid_to_face_indices[b_l].append(face_index + 3)
			_faces.append(grid[b_r])
			_grid_to_face_indices[b_r].append(face_index + 4)
			_faces.append(grid[t_r])
			_grid_to_face_indices[t_r].append(face_index + 5)

# TODO: cannot just update shape once. Must keep monitoring player position and work based on that.
func _update_shape():
	var grid_index: int = 0
	var buffer_size := compute_handler.get_buffer_size()
	var texels_per_vertex := compute_handler.get_texels_per_vertex()
	
	for z: int in (2 * mesh_radius.y + 1):
		for x: int in (2 * mesh_radius.x + 1):
			var texel := _safe_region.position + Vector2i(x, z) * texels_per_vertex
			var texel_wrapped := Vector2i(posmod(texel.x, buffer_size.x), posmod(texel.y, buffer_size.y))
			var buffer_index := (texel_wrapped.y * buffer_size.x + texel_wrapped.x) * 4
			var height := _latest_data.decode_float(buffer_index)
			
			for vertex_index: int in _grid_to_face_indices[grid_index]:
				_faces[vertex_index].y = height
			
			grid_index += 1
	
	if debug_visible_collision_shapes:
		_debug_shape.set_faces(_faces)
		_debug_shape.backface_collision = false
	else:
		PhysicsServer3D.shape_set_data(_shape_rid, {"faces": _faces, "backface_collision": false})

func _clear_shape():
	if _debug_shape:
		_debug_shape = null
	if _shape_rid.is_valid():
		PhysicsServer3D.free_rid(_shape_rid)
		_shape_rid = RID()
#endregion

#region body
func _create_body():
	if debug_visible_collision_shapes:
		_debug_body = StaticBody3D.new()
		_debug_body.top_level = true
		var parent: Node = instance_from_id(instance_id)
		if not parent:
			push_error("Could not find parent for debug collision shapes.")
			return
		parent.add_child(_debug_body)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = _debug_shape
		collision_shape.visible = true
		_debug_body.add_child(collision_shape)
		collision_shape.transform = Transform3D.IDENTITY
		collision_shape.owner = _debug_body
		
	else:
		_body_rid = PhysicsServer3D.body_create()
		PhysicsServer3D.body_add_shape(_body_rid, _shape_rid)
		PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)

func _update_body():
	var texels_per_vertex := compute_handler.get_texels_per_vertex()
	var center := _safe_region.position + mesh_radius * texels_per_vertex
	var pos := compute_handler.texel_to_world(center, collision_lod)
	var body_transform := Transform3D(Basis.IDENTITY, pos)
	
	if debug_visible_collision_shapes:
		_debug_body.collision_layer = collision_layer
		_debug_body.collision_mask = collision_mask
		_debug_body.collision_priority = collision_priority
		_debug_body.physics_material_override = physics_material
		_debug_body.transform = body_transform
	else:
		PhysicsServer3D.body_set_space(_body_rid, space_rid)
		PhysicsServer3D.body_set_collision_layer(_body_rid, collision_layer)
		PhysicsServer3D.body_set_collision_mask(_body_rid, collision_mask)
		PhysicsServer3D.body_attach_object_instance_id(_body_rid, instance_id)
		PhysicsServer3D.body_set_collision_priority(_body_rid, collision_priority)
		
		var bounce: float = 0.0
		var friction: float = 1.0
		
		if physics_material:
			bounce = physics_material.bounce
			if physics_material.absorbent:
				bounce = -bounce
			friction = physics_material.friction
			if physics_material.rough:
				friction = -friction
		
		PhysicsServer3D.body_set_param(_body_rid, PhysicsServer3D.BODY_PARAM_BOUNCE, bounce)
		PhysicsServer3D.body_set_param(_body_rid, PhysicsServer3D.BODY_PARAM_FRICTION, friction)
		
		PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, body_transform)

func _clear_body():
	if _debug_body:
		_debug_body.queue_free()
		_debug_body = null
	if _body_rid.is_valid():
		PhysicsServer3D.free_rid(_body_rid)
		_body_rid = RID()
#endregion

func _on_region_updated(lod: int, new_safe_region: Rect2i):
	if lod != collision_lod:
		return
	
	if _safe_region:
		if new_safe_region.encloses(_safe_region):
			return
	
	var center_texel := compute_handler.world_to_texel(target_transform.origin, collision_lod)
	var texels_per_vertex := compute_handler.get_texels_per_vertex()
	# Should this be 2x + 1?
	_safe_region = Rect2i(center_texel - mesh_radius * texels_per_vertex, 2 * mesh_radius * texels_per_vertex)
	
	compute_handler.request_height_data(lod, _on_height_data_received)

func _on_height_data_received(data: PackedByteArray):
	_latest_data = data
	_shape_needs_update = true
	_body_needs_update = true
	_schedule_update()
	print("data provided")

func _on_physics_material_changed():
	_body_needs_update = true
	_schedule_update()
