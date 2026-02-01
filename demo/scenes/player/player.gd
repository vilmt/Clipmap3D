extends CharacterBody3D

@export var sensitivity: float = 3.0

@export var third_person: bool = false: 
	set(value):
		third_person = value
		if not is_node_ready():
			return
		_transition_perspective()

var _transition_tween: Tween

func _transition_perspective(instant: bool = false):
	var time: float = 0.3
	if instant:
		time = 0.0
	
	if _transition_tween:
		_transition_tween.kill()
		_transition_tween = null
		
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_CUBIC)
	_transition_tween.set_ease(Tween.EASE_OUT)

	if third_person:
		#body.visible = true
		_transition_tween.tween_callback(body.set_visible.bind(true))
		_transition_tween.tween_property(spring_arm, "spring_length", _spring_length, time)
	else:
		
		_transition_tween.tween_property(spring_arm, "spring_length", 0.0, time)
		_transition_tween.tween_callback(body.set_visible.bind(false))
		
			

@export_group("Walk", "walk")
@export var walk_max_speed: float = 10
@export var walk_acceleration: float = 12
@export var walk_friction: float = 40

@export_group("Jump", "jump")
@export var jump_speed: float = 10
@export var jump_leniency_time: float = 0.15

@export_group("Air", "air")
@export var air_max_speed: float = 2
@export var air_acceleration: float = 12
@export var air_gravity: float = 25

@export_group("Fly", "fly")
@export var fly_max_speed: float = 200
@export var fly_acceleration: float = 200
@export var fly_friction: float = 200

const MIN_SPEED: float = 0.1

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var _spring_length: float = spring_arm.spring_length
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var body: MeshInstance3D = $MeshInstance3D

var state_machine := CallableStateMachine.new()

var _last_jump_input_ticks: int = -10000000000
var _last_grounded_ticks: int = 0

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("fly"):
		if state_machine.get_current_state() == _fly:
			state_machine.queue_state(_walk)
		else:
			state_machine.queue_state(_fly)
	elif event.is_action_pressed("jump"):
		if state_machine.get_current_state() == _fly:
			return
		_last_jump_input_ticks = Time.get_ticks_msec()
		if _can_jump():
			state_machine.queue_state(_jump)
	elif event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_perspective"):
		third_person = not third_person
	elif event.is_action_pressed("cycle_render_mode"):
		var vp = get_viewport()
		vp.debug_draw = (vp.debug_draw + 1 ) % 6

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.add_excluded_object(get_rid())
	
	state_machine.add_state(_walk)
	state_machine.add_state(_jump)
	state_machine.add_state(_air)
	state_machine.add_state(_fly)
	state_machine.queue_state(_walk)
	
	_transition_perspective(true)

func _physics_process(_delta: float) -> void:
	if is_on_floor():
		_last_grounded_ticks = Time.get_ticks_msec()
	state_machine.update()

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var mouse_event := event as InputEventMouseMotion
		var look_dir: Vector2 = mouse_event.relative * 0.001
		
		rotate_y(-look_dir.x * sensitivity)
		spring_arm.rotate_x(-look_dir.y * sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-90), deg_to_rad(90))

#region walk
func _walk():
	var delta := get_physics_process_delta_time()
	velocity += _get_acceleration(walk_acceleration, walk_max_speed, delta)
	velocity += _get_friction(walk_friction, delta)
	
	move_and_slide()
	
	if _can_jump():
		state_machine.queue_state(_jump)
	if not is_on_floor():
		state_machine.queue_state(_air)
#endregion

#region jump
func _jump():
	velocity.y = maxf(velocity.y, jump_speed)
	
	_last_jump_input_ticks = -1000000000
	_last_grounded_ticks = -100000000
	
	move_and_slide()
	
	state_machine.queue_state(_air)

func _can_jump():
	var input_queued: bool = (Time.get_ticks_msec() - _last_jump_input_ticks) / 1000.0 < jump_leniency_time
	var grounded: bool = (Time.get_ticks_msec() - _last_grounded_ticks) / 1000.0 < jump_leniency_time
	return input_queued and grounded

#endregion

#region air
func _air():
	var delta := get_physics_process_delta_time()
	velocity += _get_acceleration(air_acceleration, air_max_speed, delta)
	velocity.y -= air_gravity * delta
	
	move_and_slide()
	
	if is_on_floor():
		state_machine.queue_state(_walk)
#endregion

#region fly
func _fly():
	var delta := get_physics_process_delta_time()
	var raw_input := Input.get_vector("left", "right", "up", "down")
	var input_vector := global_basis * Vector3(raw_input.x, 0.0, raw_input.y)
	var alternate_y := Input.get_axis("crouch", "jump")
	if absf(alternate_y) > absf(input_vector.y):
		input_vector.y = alternate_y
	input_vector = input_vector.normalized()
	
	if not input_vector:
		velocity = velocity.move_toward(Vector3.ZERO, fly_friction * delta)
	else:
		velocity = velocity.move_toward(input_vector * fly_max_speed, fly_acceleration * delta)
	
	move_and_slide()
#endregion

func _get_acceleration(acceleration: float, max_speed: float, delta: float) -> Vector3:
	var raw_input := Input.get_vector("left", "right", "up", "down")
	var input: Vector3 = global_basis * Vector3(raw_input.x, 0.0, raw_input.y)
	
	var add_speed: float = max_speed - velocity.dot(input)
	
	if add_speed <= 0:
		return Vector3.ZERO
	
	return input * minf(acceleration * delta * max_speed, add_speed)

func _get_friction(friction: float, delta: float) -> Vector3:
	var velocity_xz: Vector3 = velocity * Vector3(1.0, 0.0, 1.0)
	var speed: float = velocity_xz.length()
	
	if speed < MIN_SPEED:
		return -velocity_xz
	
	var new_speed: float = maxf(speed - friction * delta, 0)
	var new_velocity_xz: Vector3 = velocity_xz.normalized() * new_speed
	return new_velocity_xz - velocity_xz
