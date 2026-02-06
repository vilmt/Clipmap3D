class_name Clipmap3DCollisionHandler

## NOTE: collision is highly WIP. It is often mismatched from the mesh and only supports the player.

var source: Clipmap3DSource:
	set(value):
		_disconnect_source()
		source = value
		_connect_source()

var enabled: bool = true:
	set(value):
		enabled = value
		_apply_state()

var mesh_radius: Vector2i:
	set(value):
		mesh_radius = value
		_update()

var vertex_spacing: Vector2:
	set(value):
		vertex_spacing = value

var collision_layer: int:
	set(value):
		collision_layer = value
		_apply_state()

var collision_mask: int:
	set(value):
		collision_mask = value
		_apply_state()

var space: RID:
	set(value):
		space = value
		_apply_state()

var target_position: Vector3

var _built: bool = false

func _connect_source():
	if not source or source.collision_data_changed.is_connected(_update):
		return
	source.collision_data_changed.connect(_update)
	_apply_state()
	
func _disconnect_source():
	if not source or not source.collision_data_changed.is_connected(_update):
		return
	source.collision_data_changed.disconnect(_update)
	_apply_state()

var _position_y: float #TODO

var _body_rid: RID
var _shape_rid: RID

var _template_faces: PackedVector3Array

func build():
	_built = true
	
	_body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	
	_shape_rid = PhysicsServer3D.heightmap_shape_create()
	PhysicsServer3D.body_add_shape(_body_rid, _shape_rid)
	
	_connect_source()
	_apply_state()

func clear():
	_built = false
	if _body_rid:
		PhysicsServer3D.free_rid(_body_rid)
	_body_rid = RID()
	if _shape_rid:
		PhysicsServer3D.free_rid(_shape_rid)
	_shape_rid = RID()

func _update():
	if not _built or not source:
		return
	var data := source.get_heightmap_data(mesh_radius)
	var world_origin := source.get_world_origin(0)
	
	PhysicsServer3D.shape_set_data(_shape_rid, data)
	var o := Basis(Vector3.RIGHT * vertex_spacing.x, Vector3.UP, Vector3.BACK * vertex_spacing.y)
	# HACK: where does this offset even come from
	var p := Vector3(world_origin.x + 1.0, target_position.y, world_origin.y + 1.0)
	PhysicsServer3D.body_set_shape_transform(_body_rid, 0, Transform3D(o, p))

func _apply_state():
	if not _built:
		return
	PhysicsServer3D.body_set_shape_disabled(_body_rid, 0, not enabled)
	PhysicsServer3D.body_set_space(_body_rid, space)
	PhysicsServer3D.body_set_collision_layer(_body_rid, collision_layer)
	PhysicsServer3D.body_set_collision_mask(_body_rid, collision_mask)
