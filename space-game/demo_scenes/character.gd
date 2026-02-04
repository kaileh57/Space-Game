extends CharacterBody3D

enum MovementMode { GROUNDED, AIRBORNE, ZERO_G, TRANSITIONING }
enum GroundState { IDLE, WALKING, SPRINTING, CROUCHING, SLIDING }
enum AirState { FALLING, JETPACKING }

var movement_mode: MovementMode = MovementMode.GROUNDED
var ground_state: GroundState = GroundState.IDLE
var air_state: AirState = AirState.FALLING

@export_group("Gravity Detection")
@export var gravity_detector: Area3D

@export_group("Ground Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 2.4
@export var walk_sensitivity: float = 0.003

@export_subgroup("Ground Physics")
@export var ground_acceleration: float = 14.0
@export var ground_friction: float = 10.0
@export var jump_velocity: float = 4.5

@export_subgroup("Crouch")
@export var crouch_height_ratio: float = 0.5
@export var crouch_transition_speed: float = 10.0

@export_subgroup("Slide")
@export var slide_initial_speed: float = 10.5
@export var slide_friction: float = 4.0
@export var slide_steer_strength: float = 3.0
@export var slide_jump_speed_boost: float = 1.15
@export var slide_jump_height_boost: float = 1.3

@export_subgroup("Jetpack")
@export var jetpack_lift: float = 14.0
@export var jetpack_air_control: float = 1.5
@export var jetpack_turn_penalty: float = 0.02

@export_group("Air Movement")
@export var air_acceleration: float = 2.0
@export var air_friction: float = 0.5
@export var max_bunny_speed: float = 20.0

@export_group("Zero-G Flight")
@export var fly_max_speed: float = 20.0
@export var fly_acceleration: float = 8.0
@export var fly_sensitivity: float = 0.002
@export var safety_mode: bool = true
@export var safety_decel_rate: float = 5.0

@export_subgroup("Roll")
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

@onready var camera: Camera3D = $Camera3D
@onready var sound: AudioStreamPlayer = $Jetpack/AudioStreamPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var debug_label: Label = $Camera3D/Readout/Label

var current_gravity_vector: Vector3 = Vector3(0, -9.8, 0)
var active_gravity_areas: Array[Area3D] = []

var _slide_direction: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0
var _default_collision_height: float
var _default_collision_position: float
var _default_camera_height: float
var _crouch_collision_height: float
var _crouch_camera_height: float
var _current_height_lerp: float = 1.0

var _current_roll_velocity: float = 0.0
var _target_basis: Basis
var _stored_look_pitch: float = 0.0
var _is_thrusting: bool = false
var _is_decelerating: bool = false

var _has_jumped: bool = false
var _can_jetpack: bool = false
var _jetpack_horizontal_velocity: Vector3 = Vector3.ZERO
var _jetpack_just_activated: bool = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sound.volume_db = thruster_min_volume_db
	
	_default_camera_height = camera.position.y
	_crouch_camera_height = _default_camera_height * crouch_height_ratio
	
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule = collision_shape.shape as CapsuleShape3D
		_default_collision_height = capsule.height
		_default_collision_position = collision_shape.position.y
		_crouch_collision_height = _default_collision_height * crouch_height_ratio

func _input(event: InputEvent):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if movement_mode == MovementMode.TRANSITIONING:
			return
		if movement_mode == MovementMode.ZERO_G:
			rotate_object_local(Vector3.UP, -event.relative.x * fly_sensitivity)
			rotate_object_local(Vector3.RIGHT, -event.relative.y * fly_sensitivity)
		else:
			var yaw_delta = -event.relative.x * walk_sensitivity
			rotate_y(yaw_delta)
			camera.rotate_x(-event.relative.y * walk_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
			
			if movement_mode == MovementMode.AIRBORNE and air_state == AirState.JETPACKING:
				var turn_amount = abs(yaw_delta)
				var speed_loss = turn_amount * jetpack_turn_penalty * _jetpack_horizontal_velocity.length()
				_jetpack_horizontal_velocity = _jetpack_horizontal_velocity.rotated(Vector3.UP, yaw_delta)
				_jetpack_horizontal_velocity = _jetpack_horizontal_velocity * (1.0 - speed_loss)

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if event.is_action_pressed("ui_accept") and movement_mode == MovementMode.ZERO_G:
		safety_mode = !safety_mode

func _physics_process(delta: float):
	match movement_mode:
		MovementMode.GROUNDED, MovementMode.AIRBORNE:
			_process_normal_movement(delta)
		MovementMode.ZERO_G:
			_process_zero_g(delta)
		MovementMode.TRANSITIONING:
			_process_transition(delta)
	
	_update_crouch_height(delta)
	_update_thruster_sound(delta)
	_update_debug_display()

func _on_gravity_area_entered(area: Area3D):
	if "grav" in area or area.get("grav") != null:
		active_gravity_areas.append(area)
		_update_gravity_state()

func _on_gravity_area_exited(area: Area3D):
	if area in active_gravity_areas:
		active_gravity_areas.erase(area)
		_update_gravity_state()

func _update_gravity_state():
	if movement_mode == MovementMode.TRANSITIONING:
		return
	
	if active_gravity_areas.size() > 0:
		var latest_area = active_gravity_areas.back()
		if "grav" in latest_area:
			current_gravity_vector = latest_area.grav
		if movement_mode == MovementMode.ZERO_G:
			_begin_transition_to_gravity()
	else:
		current_gravity_vector = Vector3.ZERO
		if movement_mode != MovementMode.ZERO_G:
			_switch_to_zero_g()

func _begin_transition_to_gravity():
	movement_mode = MovementMode.TRANSITIONING
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

func _process_transition(delta: float):
	if active_gravity_areas.size() == 0:
		_switch_to_zero_g()
		return
	
	var current_quat = transform.basis.get_rotation_quaternion()
	var target_quat = _target_basis.get_rotation_quaternion()
	var new_quat = current_quat.slerp(target_quat, alignment_speed * delta)
	transform.basis = Basis(new_quat)
	
	if current_quat.angle_to(target_quat) < alignment_threshold:
		_complete_transition()
	
	velocity += current_gravity_vector * delta
	
	if current_gravity_vector != Vector3.ZERO:
		up_direction = -current_gravity_vector.normalized()
	
	move_and_slide()

func _complete_transition():
	movement_mode = MovementMode.AIRBORNE
	ground_state = GroundState.IDLE
	air_state = AirState.FALLING
	transform.basis = _target_basis
	
	var forward = -_target_basis.z
	var final_yaw = atan2(forward.x, forward.z)
	rotation = Vector3(0, final_yaw + PI, 0)
	camera.rotation.x = clamp(_stored_look_pitch, deg_to_rad(-90), deg_to_rad(90))
	_current_roll_velocity = 0.0

func _switch_to_zero_g():
	movement_mode = MovementMode.ZERO_G
	ground_state = GroundState.IDLE
	_current_height_lerp = 1.0
	_has_jumped = false
	_can_jetpack = false
	
	var target_yaw = rotation.y
	var target_pitch = camera.rotation.x
	rotation = Vector3(target_pitch, target_yaw, 0.0)
	camera.rotation = Vector3.ZERO

func _process_normal_movement(delta: float):
	if not is_on_floor():
		velocity += current_gravity_vector * delta
		movement_mode = MovementMode.AIRBORNE
	else:
		movement_mode = MovementMode.GROUNDED
		if velocity.y < 0:
			velocity.y = 0
		
		if _has_jumped:
			_on_landed()
	
	if movement_mode == MovementMode.GROUNDED:
		_update_ground_state()
		match ground_state:
			GroundState.SLIDING:
				_process_sliding(delta)
			_:
				_process_walking(delta)
	else:
		_update_air_state(delta)
		_process_airborne(delta)
	
	if current_gravity_vector != Vector3.ZERO:
		up_direction = -current_gravity_vector.normalized()
	else:
		up_direction = Vector3.UP
	
	move_and_slide()

func _on_landed():
	var crouch_held = Input.is_action_pressed("crouch")
	var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
	var landing_speed = horizontal_vel.length()
	
	if crouch_held and landing_speed > crouch_speed:
		ground_state = GroundState.SLIDING
		_slide_direction = horizontal_vel.normalized() if landing_speed > 0.1 else -transform.basis.z
		_slide_speed = landing_speed
	else:
		ground_state = GroundState.IDLE
	
	_has_jumped = false
	_can_jetpack = false
	air_state = AirState.FALLING

func _update_ground_state():
	var crouch_pressed = Input.is_action_pressed("crouch")
	var sprint_pressed = Input.is_action_pressed("shift")
	var input_dir = Input.get_vector("a", "d", "w", "s")
	var has_input = input_dir.length() > 0.1
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	
	match ground_state:
		GroundState.IDLE, GroundState.WALKING, GroundState.SPRINTING:
			if crouch_pressed:
				if (sprint_pressed or horizontal_speed >= slide_initial_speed * 0.8) and horizontal_speed > crouch_speed:
					ground_state = GroundState.SLIDING
					var current_dir = Vector3(velocity.x, 0, velocity.z).normalized()
					_slide_direction = current_dir if current_dir.length() > 0.1 else -transform.basis.z
					_slide_speed = max(horizontal_speed, slide_initial_speed)
				else:
					ground_state = GroundState.CROUCHING
			elif sprint_pressed and has_input:
				ground_state = GroundState.SPRINTING
			elif has_input:
				ground_state = GroundState.WALKING
			else:
				ground_state = GroundState.IDLE
		
		GroundState.CROUCHING:
			if not crouch_pressed and _can_stand_up():
				if has_input:
					ground_state = GroundState.WALKING
				else:
					ground_state = GroundState.IDLE
		
		GroundState.SLIDING:
			if not crouch_pressed and _can_stand_up():
				ground_state = GroundState.WALKING if has_input else GroundState.IDLE
			elif _slide_speed < crouch_speed:
				ground_state = GroundState.CROUCHING

func _update_air_state(delta: float):
	var space_just_pressed = Input.is_action_just_pressed("space")
	var space_held = Input.is_action_pressed("space")
	
	_jetpack_just_activated = false
	
	if space_just_pressed and _has_jumped and _can_jetpack:
		air_state = AirState.JETPACKING
		_jetpack_horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
		_jetpack_just_activated = true
	
	if not space_held and air_state == AirState.JETPACKING:
		air_state = AirState.FALLING
	
	if _has_jumped and not _can_jetpack and not space_held:
		_can_jetpack = true

func _process_walking(delta: float):
	if Input.is_action_just_pressed("space") and is_on_floor():
		if ground_state == GroundState.CROUCHING:
			return
		velocity.y = jump_velocity
		_has_jumped = true
		_can_jetpack = false
	
	var target_speed: float
	match ground_state:
		GroundState.CROUCHING:
			target_speed = crouch_speed
		GroundState.SPRINTING:
			target_speed = sprint_speed
		_:
			target_speed = walk_speed
	
	var input_dir = Input.get_vector("a", "d", "w", "s")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, ground_acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, ground_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0, ground_friction * delta)

func _process_sliding(delta: float):
	if Input.is_action_just_pressed("space") and is_on_floor():
		var boosted_speed = min(_slide_speed * slide_jump_speed_boost, max_bunny_speed)
		velocity = _slide_direction * boosted_speed
		velocity.y = jump_velocity * slide_jump_height_boost
		_has_jumped = true
		_can_jetpack = false
		ground_state = GroundState.IDLE
		return
	
	_slide_speed = move_toward(_slide_speed, 0, slide_friction * delta)
	
	var input_dir = Input.get_vector("a", "d", "w", "s")
	if input_dir.length() > 0.1:
		var steer_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		_slide_direction = (_slide_direction + steer_dir * slide_steer_strength * delta).normalized()
	
	velocity.x = _slide_direction.x * _slide_speed
	velocity.z = _slide_direction.z * _slide_speed

func _process_airborne(delta: float):
	_is_thrusting = false
	
	if air_state == AirState.JETPACKING:
		_is_thrusting = true
		velocity.y += jetpack_lift * delta
		
		if not _jetpack_just_activated:
			velocity.x = _jetpack_horizontal_velocity.x
			velocity.z = _jetpack_horizontal_velocity.z
		
		var input_dir = Input.get_vector("a", "d", "w", "s")
		if input_dir.length() > 0.1:
			var control_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			_jetpack_horizontal_velocity += control_dir * jetpack_air_control * delta
	else:
		var input_dir = Input.get_vector("a", "d", "w", "s")
		if input_dir.length() > 0.1:
			var control_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			velocity.x += control_dir.x * air_acceleration * delta
			velocity.z += control_dir.z * air_acceleration * delta
		else:
			velocity.x = move_toward(velocity.x, 0, air_friction * delta)
			velocity.z = move_toward(velocity.z, 0, air_friction * delta)

func _can_stand_up() -> bool:
	return true

func _update_crouch_height(delta: float):
	if movement_mode == MovementMode.ZERO_G or movement_mode == MovementMode.TRANSITIONING:
		return
	
	var target_lerp: float = 1.0
	if ground_state == GroundState.CROUCHING or ground_state == GroundState.SLIDING:
		target_lerp = 0.0
	
	_current_height_lerp = move_toward(_current_height_lerp, target_lerp, crouch_transition_speed * delta)
	
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule = collision_shape.shape as CapsuleShape3D
		var target_height = lerp(_crouch_collision_height, _default_collision_height, _current_height_lerp)
		capsule.height = target_height
		var height_diff = _default_collision_height - target_height
		collision_shape.position.y = _default_collision_position - height_diff * 0.5
	
	var target_cam_height = lerp(_crouch_camera_height, _default_camera_height, _current_height_lerp)
	camera.position.y = target_cam_height

func _process_zero_g(delta: float):
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
		velocity += thrust * fly_acceleration * delta
		
		if safety_mode and velocity.length() > fly_max_speed:
			var target_vel = velocity.normalized() * fly_max_speed
			velocity = velocity.move_toward(target_vel, safety_decel_rate * delta)
	elif safety_mode:
		if velocity.length() > 0.5:
			_is_decelerating = true
			velocity = velocity.move_toward(Vector3.ZERO, fly_acceleration * 0.5 * delta)
		elif velocity.length() > 0.01:
			velocity = velocity.move_toward(Vector3.ZERO, fly_acceleration * 0.5 * delta)
		else:
			velocity = Vector3.ZERO
	
	move_and_slide()

func _update_thruster_sound(delta: float):
	if movement_mode == MovementMode.TRANSITIONING:
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

func _update_debug_display():
	if not debug_label:
		return
	
	var speed = velocity.length()
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	
	var mode_str: String
	match movement_mode:
		MovementMode.GROUNDED:
			mode_str = "GROUNDED"
		MovementMode.AIRBORNE:
			mode_str = "AIRBORNE"
		MovementMode.ZERO_G:
			mode_str = "ZERO-G"
		MovementMode.TRANSITIONING:
			mode_str = "TRANSITIONING"
	
	var state_str: String
	if movement_mode == MovementMode.GROUNDED:
		match ground_state:
			GroundState.IDLE:
				state_str = "Idle"
			GroundState.WALKING:
				state_str = "Walking"
			GroundState.SPRINTING:
				state_str = "Sprinting"
			GroundState.CROUCHING:
				state_str = "Crouching"
			GroundState.SLIDING:
				state_str = "Sliding"
	elif movement_mode == MovementMode.AIRBORNE:
		match air_state:
			AirState.FALLING:
				state_str = "Falling"
			AirState.JETPACKING:
				state_str = "Jetpacking"
	elif movement_mode == MovementMode.ZERO_G:
		state_str = "Floating"
	else:
		state_str = "Aligning"
	
	var safety_str = "ON" if safety_mode else "OFF"
	var jetpack_str = "READY" if _can_jetpack else "---"
	
	debug_label.text = "FPS: %d\nSpeed: %.1f m/s\nH-Speed: %.1f m/s\nMode: %s\nState: %s\nJetpack: %s\nSafety: %s" % [
		Engine.get_frames_per_second(),
		speed,
		horizontal_speed,
		mode_str,
		state_str,
		jetpack_str,
		safety_str
	]
