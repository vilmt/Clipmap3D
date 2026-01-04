extends Node3D

@export var sensitivity: float = 3.0

@export var max_speed: float = 10
@export var acceleration: float = 12
@export var friction: float = 40

@onready var camera: Camera3D = $Camera3D

var velocity := Vector3.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var raw_input := Input.get_vector("left", "right", "up", "down")
	var input_vector := global_basis * Vector3(raw_input.x, 0.0, raw_input.y)
	var alternate_y := Input.get_axis("crouch", "jump")
	if absf(alternate_y) > absf(input_vector.y):
		input_vector.y = alternate_y
	input_vector = input_vector.normalized()
	
	if not input_vector:
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)
	else:
		velocity = velocity.move_toward(input_vector * max_speed, acceleration * delta)
	
	global_position += velocity * delta

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var mouse_event := event as InputEventMouseMotion
		var look_dir: Vector2 = mouse_event.relative * 0.001
		
		rotate_y(-look_dir.x * sensitivity)
		camera.rotate_x(-look_dir.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
