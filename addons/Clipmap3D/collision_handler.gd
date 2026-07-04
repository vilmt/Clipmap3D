@tool
class_name Clipmap3DCollisionHandler

# NOTE: if adding holes to control map and mesh, will have to fetch that as well. Skip those triangles.
# TODO: enforce that the physics mesh is much smaller than the buffer.

# TODO: If built without compute handler, or if the data request fails, should just 
# build a flat plane and wait for either the compute handler to be assigned or for a new region to be generated.


var compute_handler: Clipmap3DComputeHandler:
	set(value):
		if compute_handler and compute_handler.region_updated.is_connected(_on_region_updated):
			compute_handler.region_updated.disconnect(_on_region_updated)
		compute_handler = value
		if compute_handler and not compute_handler.region_updated.is_connected(_on_region_updated):
			compute_handler.region_updated.connect(_on_region_updated)
		_schedule_update()

var space: RID:
	set(value):
		space = value
		_body_needs_update = true
		_schedule_update()

var instance_id: int:
	set(value):
		instance_id = value
		_body_needs_update = true
		_schedule_update

var target_transform: Transform3D:
	set(value):
		if target_transform == value:
			return
		target_transform = value

var mesh_radius: Vector2i:
	set(value):
		mesh_radius = value
		_shape_needs_rebuild = true
		_schedule_update()

var collision_layer: int:
	set(value):
		collision_layer = value
		_body_needs_update = true
		_schedule_update()

var collision_mask: int:
	set(value):
		collision_mask = value
		_body_needs_update = true
		_schedule_update()

var physics_material: PhysicsMaterial:
	set(value):
		physics_material = value
		_body_needs_update = true
		_schedule_update()

var collision_lod: int:
	set(value):
		if collision_lod == value:
			return
		collision_lod = value
		# TODO: must fetch the entire lod again
		# If does not exist, just build a flat plane and wait for region updates.
		
		#_meshes_need_rebuild = true
		_schedule_update()

var collision_priority: int:
	set(value):
		collision_priority = value
		_body_needs_update = true
		_schedule_update()

var _faces: PackedVector3Array
var _safe_region: Rect2i
var _latest_data: PackedByteArray

var _built: bool = false
var _body_needs_rebuild: bool = false
var _body_needs_update: bool = false
var _shape_needs_rebuild: bool = false
var _shape_needs_update: bool = false

var _body_rid: RID
var _shape_rid: RID

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
	
	_ensure_shape()
	_ensure_body()
	
	_update_shape()
	_update_body()

#region shape
func _ensure_shape():
	if not _shape_needs_rebuild:
		return
	
	_shape_rid = PhysicsServer3D.concave_polygon_shape_create()
	var mesh_arrays: Array = []
	mesh_arrays.resize(RenderingServer.ARRAY_MAX)
	
	var half_size := Vector3(float(mesh_radius.x), 0.0, float(mesh_radius.y))
	
	var grid := PackedVector3Array()
	for z: int in 2 * mesh_radius.y + 1:
		for x: int in 2 * mesh_radius.x + 1:
			grid.append(Vector3(float(x), 0.0, float(z)) - half_size)
	
	var vertices := PackedVector3Array()
	for z: int in 2 * mesh_radius.y:
		for x: int in 2 * mesh_radius.x:
			var b_l: int = z * (2 * mesh_radius.x + 1) + x
			var b_r: int = b_l + 1
			var t_l: int = (z + 1) * (2 * mesh_radius.x + 1) + x
			var t_r: int = t_l + 1
			
			vertices.append(grid[b_l])
			vertices.append(grid[t_r])
			vertices.append(grid[t_l])
			
			vertices.append(grid[b_l])
			vertices.append(grid[b_r])
			vertices.append(grid[t_r])
	
	_faces = vertices
	print("Shape ensured")
	_shape_needs_rebuild = false
	
func _update_shape():
	if not _shape_needs_update:
		return
	
	#var world_origin := Vector2(target_transform.origin.x, target_transform.origin.z)
	#var snap := 2.0 * Vector2.ONE
	#var scale := float(1 << collision_lod)
	#var vertex_origin := Vector2i((world_origin / scale / snap).floor() * snap)
	#var texel_origin := vertex_origin * compute_handler.get_texels_per_vertex()
	
	#_previous_region = Rect2i(texel_origin - mesh_radius, mesh_radius * 2)
	
	#print("Current region: %s" % _previous_region)
	
	#print(data.decode_float(0))
		
	#var data := source.get_heightmap_data(mesh_radius)
	#var world_origin := source.get_world_origin(0)
	#
	#PhysicsServer3D.shape_set_data(_shape_rid, data)
	#var o := Basis(Vector3.RIGHT * vertex_spacing.x, Vector3.UP, Vector3.BACK * vertex_spacing.y)
	## HACK: where does this offset even come from
	#var p := Vector3(world_origin.x + 1.0, target_position.y, world_origin.y + 1.0)
	#PhysicsServer3D.body_set_shape_transform(_body_rid, 0, Transform3D(o, p))
		
	_shape_needs_update = false

func _clear_shape():
	if _shape_rid.is_valid():
		PhysicsServer3D.free_rid(_shape_rid)
		_shape_rid = RID()
#endregion

#region body
func _ensure_body():
	if not _body_needs_rebuild:
		return
	
	_clear_body()
	
	_body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	
	_body_needs_rebuild = false

func _update_body():
	if not _body_needs_update:
		return
	
	PhysicsServer3D.body_add_shape(_body_rid, _shape_rid)
	PhysicsServer3D.body_set_space(_body_rid, space)
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

	_body_needs_update = false

func _clear_body():
	if _body_rid.is_valid():
		PhysicsServer3D.free_rid(_body_rid)
		_body_rid = RID()
#endregion

func _on_region_updated(lod: int, new_safe_region: Rect2i):
	if lod != collision_lod:
		return
	
	if _safe_region:
		# This is not correct. Would have to find the region getting "cut off"
		if new_safe_region.encloses(_safe_region):
			return
	
	print("Current safe region: %s" % _safe_region)
	print("New safe region: %s " % new_safe_region)
	print("")
	
	var texel := compute_handler.world_to_snapped_texel(target_transform.origin, collision_lod)
	_safe_region = Rect2i(texel - mesh_radius, 2 * mesh_radius)
	
	compute_handler.request_height_data(lod, _on_height_data_provided)

func _on_height_data_provided(data: PackedByteArray):
	_latest_data = data
	_shape_needs_update = true
	_schedule_update()
	print("data provided")
