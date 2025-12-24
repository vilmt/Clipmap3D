extends CollisionShape3D
class_name TerrainCollider

@export var physics_body: PhysicsBody3D
@export var size := Vector2i(8, 8)

@onready var snap := Vector3(size.x, 0.0, size.y) / 2.0

var _height_image: Image
var _amplitude: float

var _height_map_shape: HeightMapShape3D

func prepare_shape(height_image: Image, amplitude: float):
	_height_image = height_image
	_amplitude = amplitude
	
	_height_map_shape = HeightMapShape3D.new()
	shape = _height_map_shape

func _ready() -> void:
	if shape:
		update_shape()
	
func _physics_process(delta):
	if not physics_body:
		return
	var rounded_body_position := physics_body.global_position.snapped(snap) * Vector3(1.0, 0.0, 1.0)
	if not global_position.is_equal_approx(rounded_body_position):
		global_position = rounded_body_position
		update_shape()
	
func update_shape():
	var image_size: Vector2i = _height_image.get_size()
	var half := Vector2i(image_size.x / 2, image_size.y / 2)
	# TODO: replace half with proper offset and take part size into account
	# TODO: figure out why its a bit off
	var bottom = global_position - snap
	var region = Rect2i(bottom.x + half.x, bottom.z + half.y, size.x, size.y)
	var sub_image = _height_image.get_region(region)
	sub_image.convert(Image.FORMAT_RH)
	_height_map_shape.update_map_data_from_image(sub_image, 0.0, _amplitude)
