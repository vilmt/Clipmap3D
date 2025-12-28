extends CollisionShape3D
class_name TerrainCollider

@export var physics_body: PhysicsBody3D
@export var size := Vector2i(8, 8)

@onready var snap := Vector3(size.x, 0.0, size.y) / 2.0

var _faces: PackedVector3Array

var _height_image: Image
var _amplitude: float
var _subdivision_size: Vector2

var _map_offset: Vector2i
var _map_origin: Vector2i

var _polygon_shape: ConcavePolygonShape3D

func prepare_shape(height_image: Image, amplitude: float, subdivision_size: Vector2):
	_height_image = height_image
	_amplitude = amplitude
	_subdivision_size = subdivision_size
	
	var plane := PlaneMesh.new()
	plane.size = subdivision_size * Vector2(size)
	plane.subdivide_width = size.x - 1
	plane.subdivide_depth = size.y - 1
	_faces = plane.get_faces()
	
	_polygon_shape = ConcavePolygonShape3D.new()
	shape = _polygon_shape
	
	#update_shape()

func update_offset_and_origin(map_offset, map_origin):
	_map_offset = map_offset
	_map_origin = map_origin

func _physics_process(delta):
	if not physics_body:
		return
	var rounded_body_position := physics_body.global_position.snapped(snap) * Vector3(1.0, 0.0, 1.0)
	if not global_position.is_equal_approx(rounded_body_position):
		global_position = rounded_body_position
		update_shape()

func sample_height(world_position: Vector2) -> float:
	# 1. world → map texel space
	var map_position := world_position / _subdivision_size

	# 2. apply clipmap offsets
	var texel := map_position + Vector2(_map_offset - _map_origin) + Vector2(0.5, 0.5)

	# 3. convert to integer texel index
	var texel_i := Vector2i(floor(texel.x), floor(texel.y))

	# 4. clamp (important for collision!)
	texel_i.x = clampi(texel_i.x, 0, _height_image.get_width()  - 1)
	texel_i.y = clampi(texel_i.y, 0, _height_image.get_height() - 1)

	# 5. fetch height
	return _height_image.get_pixel(texel_i.x, texel_i.y).r * _amplitude
	
func update_shape():
	var xform := global_transform
	for i: int in _faces.size():
		var v_world := xform * _faces[i]
		_faces[i].y = sample_height(Vector2(v_world.x, v_world.z))
		
	_polygon_shape.set_faces(_faces)
