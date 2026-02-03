extends CharacterBody3D

enum Mode { WALKING, FLYING, TRANSITIONING }

var current_mode = Mode.WALKING

@export_group("Gravity Detection")
@export var gravity_detector: Area3D

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

var current_gravity_vector = Vector3(0, -9.8, 0)
var active_gravity_areas: Array[Area3D] = []

@export_group("Flying Mode")
@export var fly_max_speed: float = 20.0
@export var fly_move_acceleration: float = 8.0
@export var fly_sensitivity: float = 0.002
@export var safety_mode: bool = true

@export_subgroup("Roll Physics")
@export var roll_acceleration: float = 1.5
@export var max_roll_speed: float = 1.5
@export var roll_friction: float = 1.5

@export_subgroup("Thruster Audio")
@export var thruster_fade_speed: float = 1000.0
@export var thruster_max_volume_db: float = 0.0
@export var thruster_min_volume_db: float = -80.0
@export var deceleration_volume: float = 0.7

@export_group("Gravity Transition")
@export var alignment_speed: float = 6.0
@export var alignment_threshold: float = 0.01

@onready var camera = $Camera3D
@onready var sound: AudioStreamPlayer = $Jetpack/AudioStreamPlayer

var _current_roll_velocity: float = 0.0
var _target_basis: Basis
var _stored_look_pitch: float = 0.0
var _is_thrusting: bool = false
var _is_decelerating: bool = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sound.volume_db = thruster_min_volume_db

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if current_mode == Mode.TRANSITIONING:
			return
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
	
	if event.is_action_pressed("ui_accept") and current_mode == Mode.FLYING:
		safety_mode = !safety_mode

func _physics_process(delta):
	match current_mode:
		Mode.WALKING:
			_process_walking(delta)
		Mode.FLYING:
			_process_flying(delta)
		Mode.TRANSITIONING:
			_process_transition(delta)
	
	_update_thruster_sound(delta)

func _on_gravity_area_entered(area: Area3D):
	if "grav" in area or area.get("grav") != null:
		active_gravity_areas.append(area)
		_update_gravity_state()

func _on_gravity_area_exited(area: Area3D):
	if area in active_gravity_areas:
		active_gravity_areas.erase(area)
		_update_gravity_state()

func _update_gravity_state():
	if current_mode == Mode.TRANSITIONING:
		return
	
	if active_gravity_areas.size() > 0:
		var latest_area = active_gravity_areas.back()
		if "grav" in latest_area:
			current_gravity_vector = latest_area.grav
		if current_mode == Mode.FLYING:
			_begin_transition_to_walking()
	else:
		current_gravity_vector = Vector3.ZERO
		if current_mode == Mode.WALKING:
			_switch_to_flying()

func _begin_transition_to_walking():
	current_mode = Mode.TRANSITIONING
	_stored_look_pitch = rotation.x
	_is_thrusting = false
	_is_decelerating = false
	
	var target_up = -current_gravity_vector.normalized()
	var current_forward = -transform.basis.z
	var projected_forward = (current_forward - target_up * current_forward.dot(target_up)).normalized()
	
	if projected_forward.length_squared() < 0.001:
		projected_forward = Vector3.FORWARD
		if abs(target_up.dot(Vector3.FORWARD)) > 0.9:
			projected_forward = Vector3.RIGHT
	
	var target_right = projected_forward.cross(target_up).normalized()
	var corrected_forward = target_up.cross(target_right).normalized()
	
	_target_basis = Basis(target_right, target_up, -corrected_forward)

func _process_transition(delta):
	if active_gravity_areas.size() == 0:
		_switch_to_flying()
		return
	
	var current_quat = transform.basis.get_rotation_quaternion()
	var target_quat = _target_basis.get_rotation_quaternion()
	var new_quat = current_quat.slerp(target_quat, alignment_speed * delta)
	transform.basis = Basis(new_quat)
	
	var angle_diff = current_quat.angle_to(target_quat)
	if angle_diff < alignment_threshold:
		_complete_transition_to_walking()
	
	velocity += current_gravity_vector * delta
	
	if current_gravity_vector != Vector3.ZERO:
		up_direction = -current_gravity_vector.normalized()
	
	move_and_slide()

func _complete_transition_to_walking():
	current_mode = Mode.WALKING
	transform.basis = _target_basis
	
	var forward = -_target_basis.z
	var final_yaw = atan2(forward.x, forward.z)
	rotation = Vector3(0, final_yaw + PI, 0)
	camera.rotation.x = clamp(_stored_look_pitch, deg_to_rad(-90), deg_to_rad(90))
	_current_roll_velocity = 0.0

func _switch_to_flying():
	current_mode = Mode.FLYING
	var target_yaw = rotation.y
	var target_pitch = camera.rotation.x
	rotation = Vector3(target_pitch, target_yaw, 0.0)
	camera.rotation = Vector3.ZERO

func _handle_walk_look(event):
	rotate_y(-event.relative.x * walk_sensitivity)
	camera.rotate_x(-event.relative.y * walk_sensitivity)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _handle_fly_look(event):
	rotate_object_local(Vector3.UP, -event.relative.x * fly_sensitivity)
	rotate_object_local(Vector3.RIGHT, -event.relative.y * fly_sensitivity)

func _process_walking(delta):
	if not is_on_floor():
		velocity += current_gravity_vector * delta
	elif velocity.y <= 0:
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
	
	if current_gravity_vector != Vector3.ZERO:
		up_direction = -current_gravity_vector.normalized()
	else:
		up_direction = Vector3.UP
	
	move_and_slide()

func _process_flying(delta):
	_is_thrusting = false
	_is_decelerating = false
	
	var roll_input = Input.get_axis("q", "e")
	if roll_input != 0:
		_current_roll_velocity -= roll_input * roll_acceleration * delta
		_is_thrusting = true
	else:
		_current_roll_velocity = move_toward(_current_roll_velocity, 0, roll_friction * delta)
	
	_current_roll_velocity = clamp(_current_roll_velocity, -max_roll_speed, max_roll_speed)
	rotate_object_local(Vector3.BACK, _current_roll_velocity * delta)
	
	var input_dir = Input.get_vector("a", "d", "w", "s")
	var vertical_dir = Input.get_axis("shift", "space")
	
	var thrust = Vector3.ZERO
	thrust += transform.basis.z * input_dir.y
	thrust += transform.basis.x * input_dir.x
	thrust += transform.basis.y * vertical_dir
	
	if thrust.length_squared() > 1.0:
		thrust = thrust.normalized()
	
	if thrust != Vector3.ZERO:
		_is_thrusting = true
		velocity += thrust * fly_move_acceleration * delta
		if safety_mode and velocity.length() > fly_max_speed:
			velocity = velocity.normalized() * fly_max_speed
	elif safety_mode and velocity.length() > 0.5:
		_is_decelerating = true
		var dampen_rate = fly_move_acceleration * 0.5
		velocity = velocity.move_toward(Vector3.ZERO, dampen_rate * delta)
	elif velocity.length() > 0.01:
		velocity = velocity.move_toward(Vector3.ZERO, fly_move_acceleration * 0.5 * delta)
	else:
		velocity = Vector3.ZERO
	
	move_and_slide()

func _update_thruster_sound(delta):
	if current_mode != Mode.FLYING:
		_is_thrusting = false
		_is_decelerating = false
	
	var target_volume = thruster_min_volume_db
	var should_play = false
	
	if _is_thrusting:
		target_volume = thruster_max_volume_db
		should_play = true
	elif _is_decelerating:
		var max_linear = db_to_linear(thruster_max_volume_db)
		var scaled_linear = max_linear * deceleration_volume
		target_volume = linear_to_db(scaled_linear)
		should_play = true
	
	if should_play:
		if not sound.playing:
			sound.play()
		sound.volume_db = move_toward(sound.volume_db, target_volume, thruster_fade_speed * delta)
	else:
		sound.volume_db = move_toward(sound.volume_db, thruster_min_volume_db, thruster_fade_speed * delta)
		if sound.volume_db <= thruster_min_volume_db + 1.0:
			sound.stop()
