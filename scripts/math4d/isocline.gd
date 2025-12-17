# Isocline - 4D Rotation representation using isoclinic decomposition
# Ported from HackerPoet's Engine4D (Isocline.cs)
# https://github.com/HackerPoet/Engine4D
#
# An Isocline represents a 4D rotation as a pair of quaternions (left and right isoclinic rotations).
# This is the 4D equivalent of quaternions in 3D - essential for smooth rotations.
# Any 4D rotation can be decomposed into a composition of left and right isoclinic rotations.
class_name Isocline
extends RefCounted

var qL: Quaternion  # Left isoclinic rotation
var qR: Quaternion  # Right isoclinic rotation

func _init(left: Quaternion = Quaternion.IDENTITY, right: Quaternion = Quaternion.IDENTITY) -> void:
	qL = left
	qR = right

# Identity isocline (no rotation)
static func identity() -> Isocline:
	return Isocline.new(Quaternion.IDENTITY, Quaternion.IDENTITY)

# Create from 4x4 rotation matrix
static func from_matrix(m: Matrix4x4D) -> Isocline:
	var r0 := m.get_row(0)
	var r1 := m.get_row(1)
	var r2 := m.get_row(2)
	var r3 := m.get_row(3)
	
	var qL_val := Quaternion(
		r3.x - r0.w + r1.z - r2.y,
		r3.y - r0.z - r1.w + r2.x,
		r3.z + r0.y - r1.x - r2.w,
		r3.w + r0.x + r1.y + r2.z
	).normalized()
	
	var vR := left_isocline_matrix(qL_val).multiply_vector(r3)
	var qR_val := Quaternion(vR.x, vR.y, vR.z, vR.w)
	
	return Isocline.new(qL_val, qR_val)

# Create from dual quaternion representation
static func from_dual(r: Quaternion, d: Quaternion) -> Isocline:
	return Isocline.new(r.inverse() * d, r * d)

# Create from Euler angles (embeds 3D rotation in 4D)
static func euler(x_deg: float, y_deg: float, z_deg: float) -> Isocline:
	var q := Quaternion.from_euler(Vector3(deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg)))
	return Isocline.new(q.inverse(), q)

# Create rotation from one 4D vector to another
static func from_to_rotation(from: Vector4D, to: Vector4D) -> Isocline:
	return from_matrix(Matrix4x4D.from_to_rotation(from, to))

# Multiply two isoclines (compose rotations)
func multiply(other: Isocline) -> Isocline:
	return Isocline.new(other.qL * qL, qR * other.qR)

# Multiply by a 3D quaternion (adds 3D rotation)
func multiply_quaternion(q: Quaternion) -> Isocline:
	return Isocline.new(q.inverse() * qL, qR * q)

# Apply rotation to a 4D vector
func multiply_vector(v: Vector4D) -> Vector4D:
	return matrix_L().multiply_vector(matrix_R().multiply_vector(v))

# Inverse rotation
func inverse_isocline() -> Isocline:
	return Isocline.new(qL.inverse(), qR.inverse())

# Spherical interpolation
static func slerp(a: Isocline, b: Isocline, t: float) -> Isocline:
	return Isocline.new(a.qL.slerp(b.qL, t), a.qR.slerp(b.qR, t))

# Left isoclinic matrix from quaternion
static func left_isocline_matrix(q: Quaternion) -> Matrix4x4D:
	return Matrix4x4D.new(
		Vector4D.new(q.w, q.z, -q.y, -q.x),
		Vector4D.new(-q.z, q.w, q.x, -q.y),
		Vector4D.new(q.y, -q.x, q.w, -q.z),
		Vector4D.new(q.x, q.y, q.z, q.w)
	)

# Right isoclinic matrix from quaternion
static func right_isocline_matrix(q: Quaternion) -> Matrix4x4D:
	return Matrix4x4D.new(
		Vector4D.new(q.w, -q.z, q.y, -q.x),
		Vector4D.new(q.z, q.w, -q.x, -q.y),
		Vector4D.new(-q.y, q.x, q.w, -q.z),
		Vector4D.new(q.x, q.y, q.z, q.w)
	)

# Get left isoclinic matrix
func matrix_L() -> Matrix4x4D:
	return left_isocline_matrix(qL)

# Get right isoclinic matrix
func matrix_R() -> Matrix4x4D:
	return right_isocline_matrix(qR)

# Get full rotation matrix
func to_matrix() -> Matrix4x4D:
	return matrix_L().multiply_matrix(matrix_R())

# Duplicate
func duplicate() -> Isocline:
	return Isocline.new(qL, qR)

func _to_string() -> String:
	return "[L:%s | R:%s]" % [qL, qR]
