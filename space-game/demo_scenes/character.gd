extends CharacterBody3D

enum Mode { WALKING, FLYING }
var current_mode = Mode.WALKING

@export_group("Walking Mode")
@export var walk_speed = 5.0
@export var walk_sprint_speed = 9.0
@export var walk_jump_velocity = 4.5
@export var walk_sensitivity = 0.003

@export_subgroup("Walk Physics")
@export var ground_acceleration = 14.0
@export var ground_friction = 10.0
@export var air_acceleration = 2.0
@export var air_friction = 1.0

var gravity = 9.8

@export_group("Flying Mode")
@export var fly_max_speed: float = 20.0
@export var fly_move_acceleration: float = 8.0 
@export var fly_sensitivity: float = 0.002

@export_subgroup("Roll Physics")
@export var roll_acceleration: float = 1.5  
@export var max_roll_speed: float = 1.5       
@export var roll_friction: float = 1.5       

@onready var camera = $Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _current_roll_velocity: float = 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_yaw = rotation.y
	_pitch = rotation.x
	_roll = rotation.z

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):
		_toggle_mode()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if current_mode == Mode.WALKING:
			_handle_walk_look(event)
		else:
			_handle_fly_look(event)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	if current_mode == Mode.WALKING:
		_process_walking(delta)
	else:
		_process_flying(delta)

func _toggle_mode():
	if current_mode == Mode.WALKING:
		current_mode = Mode.FLYING
		
		# Transfer orientation to body
		_yaw = rotation.y
		_pitch = camera.rotation.x 
		_roll = 0.0
		
		rotation = Vector3(_pitch, _yaw, _roll)
		camera.rotation = Vector3.ZERO
		
	else:
		current_mode = Mode.WALKING
		
		# Reset body upright, transfer pitch to camera
		var current_pitch = rotation.x
		var current_yaw = rotation.y
		
		rotation = Vector3(0, current_yaw, 0)
		camera.rotation.x = current_pitch
		_current_roll_velocity = 0.0

func _handle_walk_look(event):
	rotate_y(-event.relative.x * walk_sensitivity)
	camera.rotate_x(-event.relative.y * walk_sensitivity)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _process_walking(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0:
		velocity.y = 0

	if Input.is_action_just_pressed("space") and is_on_floor():
		velocity.y = walk_jump_velocity

	var current_speed = walk_speed
	if Input.is_action_pressed("shift"):
		current_speed = walk_sprint_speed

	var input_dir = Input.get_vector("a", "d", "w", "s")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var accel = ground_acceleration if is_on_floor() else air_acceleration
	var friction = ground_friction if is_on_floor() else air_friction
	
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)

	move_and_slide()

func _handle_fly_look(event):
	_yaw -= event.relative.x * fly_sensitivity
	_pitch -= event.relative.y * fly_sensitivity

func _process_flying(delta):
	var roll_input = Input.get_axis("q", "e")
	
	if roll_input != 0:
		_current_roll_velocity -= roll_input * roll_acceleration * delta
	else:
		_current_roll_velocity = move_toward(_current_roll_velocity, 0, roll_friction * delta)
	
	_current_roll_velocity = clamp(_current_roll_velocity, -max_roll_speed, max_roll_speed)
	_roll += _current_roll_velocity * delta
	
	rotation = Vector3(_pitch, _yaw, _roll)
	
	var input_dir = Input.get_vector("a", "d", "w", "s")
	var vertical_dir = Input.get_axis("shift", "space")
	
	var thrust = Vector3.ZERO
	thrust += transform.basis.z * input_dir.y
	thrust += transform.basis.x * input_dir.x
	thrust += transform.basis.y * vertical_dir
	
	if thrust.length_squared() > 1.0:
		thrust = thrust.normalized()
	if thrust != Vector3.ZERO:
		velocity += thrust * fly_move_acceleration * delta
	if velocity.length() > fly_max_speed:
		velocity = velocity.normalized() * fly_max_speed
		
	move_and_slide()
