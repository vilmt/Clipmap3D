extends CollisionShape3D
class_name TerrainCollider

@export var physics_body: PhysicsBody3D
@export var size := Vector2i(8, 8)

@onready var snap := Vector3(size.x, 0.0, size.y) / 2.0

var _faces: PackedVector3Array

var _height_image: Image
var _amplitude: float
var _subdivision_size: Vector2

var _polygon_shape: ConcavePolygonShape3D

# TODO: use concave polygon again...

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
	
	update_shape()

#func _ready() -> void:
	#if shape:
		#update_shape()
	
func _physics_process(delta):
	if not physics_body:
		return
	var rounded_body_position := physics_body.global_position.snapped(snap) * Vector3(1.0, 0.0, 1.0)
	if not global_position.is_equal_approx(rounded_body_position):
		global_position = rounded_body_position
		update_shape()
	
func update_shape():
	for i: int in _faces.size():
		#var global_vertex: Vector3 = _faces[i] + global_position
		#var texel_position: Vector2 = global_vertex
		_faces[i].y = 300.0 #get_height(global_vertex.x, global_vertex.z)
		#_height_image.get_pixelv()
	_polygon_shape.set_faces(_faces)
	
	
	#var image_size: Vector2i = _height_image.get_size()
	#var half := Vector2i(image_size.x / 2, image_size.y / 2)
	## TODO: replace half with proper offset and take chunk size into account
	## TODO: figure out why its a bit off
	#var bottom: Vector3 = global_position - snap
	#var region := Rect2i(bottom.x + half.x, bottom.z + half.y, size.x, size.y)
	#var sub_image := _height_image.get_region(region)
	#_height_map_shape.update_map_data_from_image(sub_image, 0.0, _amplitude)
