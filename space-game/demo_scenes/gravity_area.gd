@tool
extends Area3D

# This code by kellen
# This is a tool, which means it runs in editor, to update some properties LIVE

@export var grav: Vector3

@export var target_shape: Shape3D:
	set(value):
		# Disconnect old signal to prevent errors/leaks
		if target_shape and target_shape.changed.is_connected(_update_area):
			target_shape.changed.disconnect(_update_area)
		target_shape = value
		# Listen for changes (like dragging the radius slider)
		if target_shape:
			target_shape.changed.connect(_update_area)
			
		_update_area()

@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

const SHIMMER_MAT = preload("res://materials/mat.tres")

func _ready() -> void:
	_update_area()

func _update_area() -> void:
	if not is_inside_tree(): return
	
	var col = get_node_or_null("CollisionShape3D")
	var msh = get_node_or_null("MeshInstance3D")
	if not col or not msh: return

	if col.shape != target_shape:
		col.shape = target_shape
	
	if target_shape:
		msh.mesh = _create_mesh_from_shape(target_shape)
		
		msh.set_surface_override_material(0, SHIMMER_MAT)
	else:
		msh.mesh = null

# Helper to convert Physics Shapes to Visual Meshes
func _create_mesh_from_shape(shape: Shape3D) -> Mesh:
	if shape is BoxShape3D:
		var m = BoxMesh.new()
		m.size = shape.size
		return m
	elif shape is SphereShape3D:
		var m = SphereMesh.new()
		m.radius = shape.radius
		m.height = shape.radius * 2.0
		return m
	elif shape is CapsuleShape3D:
		var m = CapsuleMesh.new()
		m.radius = shape.radius
		m.height = shape.height
		return m
	elif shape is CylinderShape3D:
		var m = CylinderMesh.new()
		m.top_radius = shape.radius
		m.bottom_radius = shape.radius
		m.height = shape.height
		return m
	
	# Other case
	return shape.get_debug_mesh()
