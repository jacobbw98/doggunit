# Transform4D - Full 4D Transformation (rotation + translation + scale)
# Ported from HackerPoet's Engine4D (Transform4D.cs)
# https://github.com/HackerPoet/Engine4D
class_name Transform4D
extends RefCounted

var matrix: Matrix4x4D  # Rotation and scale
var translation: Vector4D  # Position

func _init(rot: Matrix4x4D = null, trans: Vector4D = null) -> void:
	matrix = rot if rot else Matrix4x4D.identity()
	translation = trans if trans else Vector4D.zero()

# Static constructors
static func identity_transform() -> Transform4D:
	return Transform4D.new(Matrix4x4D.identity(), Vector4D.zero())

static func from_translation(trans: Vector4D) -> Transform4D:
	return Transform4D.new(Matrix4x4D.identity(), trans)

static func from_matrix(m: Matrix4x4D) -> Transform4D:
	return Transform4D.new(m, Vector4D.zero())

static func from_rotation_translation_scale(rotation: Matrix4x4D, trans: Vector4D, scale: Vector4D) -> Transform4D:
	return Transform4D.new(rotation.multiply_matrix(Matrix4x4D.scale_matrix(scale)), trans)

static func from_isocline(iso: Isocline, trans: Vector4D = null) -> Transform4D:
	return Transform4D.new(iso.to_matrix(), trans if trans else Vector4D.zero())

# Create from Godot 3D Transform
static func from_transform3d(t: Transform3D, w: float = 0.0) -> Transform4D:
	var m := Matrix4x4D.from_godot_basis(t.basis)
	var trans := Vector4D.from_vector3(t.origin, w)
	return Transform4D.new(m, trans)

# Transform a point
func transform_point(point: Vector4D) -> Vector4D:
	return matrix.multiply_vector(point).add(translation)

# Transform a direction (ignores translation)
func transform_direction(dir: Vector4D) -> Vector4D:
	return matrix.multiply_vector(dir)

# Compose two transforms
func multiply(other: Transform4D) -> Transform4D:
	return Transform4D.new(
		matrix.multiply_matrix(other.matrix),
		transform_point(other.translation)
	)

# Inverse transform
func inverse_transform() -> Transform4D:
	var inv_matrix := matrix.inverse()
	return Transform4D.new(inv_matrix, inv_matrix.multiply_vector(translation).negate())

# Get the position (translation)
func get_position() -> Vector4D:
	return translation

func set_position(pos: Vector4D) -> void:
	translation = pos

# Get rotation as isocline
func get_rotation() -> Isocline:
	return Isocline.from_matrix(matrix)

# Get scale (assumes uniform scaling per axis)
func get_scale() -> Vector4D:
	return Vector4D.new(
		matrix.get_column(0).magnitude(),
		matrix.get_column(1).magnitude(),
		matrix.get_column(2).magnitude(),
		matrix.get_column(3).magnitude()
	)

# Get max scale factor
func max_scale() -> float:
	return matrix.max_scale()

# Interpolate between transforms
static func lerp_transform(a: Transform4D, b: Transform4D, t: float) -> Transform4D:
	var trans := Vector4D.lerp(a.translation, b.translation, t)
	var rot := Matrix4x4D.slerp_near(a.matrix, b.matrix, t)
	return Transform4D.new(rot, trans)

# Look at (orient Z axis toward target)
func look_at(target: Vector4D, up: Vector4D = null) -> Transform4D:
	if up == null:
		up = Vector4D.unit_y()
	
	var forward := target.subtract(translation).normalized()
	if forward.is_zero():
		return self
	
	# Gram-Schmidt to build orthonormal basis
	var right := Vector4D.make_normal(up, forward, Vector4D.unit_w())
	if right.is_zero():
		right = Vector4D.unit_x()
	right = right.normalized()
	
	var actual_up := Vector4D.make_normal(forward, right, Vector4D.unit_w()).normalized()
	var w_axis := Vector4D.make_normal(right, actual_up, forward).normalized()
	
	var new_matrix := Matrix4x4D.new(right, actual_up, forward, w_axis)
	return Transform4D.new(new_matrix, translation)

# Convert back to Godot 3D Transform (projecting W to 0)
func to_transform3d() -> Transform3D:
	var basis := Basis(
		Vector3(matrix.get_column(0).x, matrix.get_column(0).y, matrix.get_column(0).z),
		Vector3(matrix.get_column(1).x, matrix.get_column(1).y, matrix.get_column(1).z),
		Vector3(matrix.get_column(2).x, matrix.get_column(2).y, matrix.get_column(2).z)
	)
	return Transform3D(basis, translation.to_vector3())

# Duplicate
func duplicate() -> Transform4D:
	return Transform4D.new(matrix.duplicate(), translation.duplicate())

func _to_string() -> String:
	return "Transform4D(matrix=%s, translation=%s)" % [matrix, translation]
