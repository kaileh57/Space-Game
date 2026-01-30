extends CharacterBody3D

@export_group("Movement")
@export var max_speed: float = 20.0
@export var move_acceleration: float = 8.0 

@export_group("Rotation")
@export var mouse_sensitivity: float = 0.002

@export_subgroup("Roll Physics")
@export var roll_acceleration: float = 1.5  
@export var max_roll_speed: float = 1.5     
@export var roll_friction: float = 1.5     

var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _current_roll_velocity: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
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
		velocity += thrust * move_acceleration * delta
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
		
	move_and_slide()
