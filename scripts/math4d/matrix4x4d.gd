# Matrix4x4D - 4D Transformation Matrix for Godot
# Ported from HackerPoet's Engine4D (Transform4D.cs matrix operations)
# https://github.com/HackerPoet/Engine4D
class_name Matrix4x4D
extends RefCounted

const EPSILON: float = 1e-5

# Column-major storage (like Godot and most graphics APIs)
var column0: Vector4D
var column1: Vector4D
var column2: Vector4D
var column3: Vector4D

func _init(c0: Vector4D = null, c1: Vector4D = null, c2: Vector4D = null, c3: Vector4D = null) -> void:
	column0 = c0 if c0 else Vector4D.new(1, 0, 0, 0)
	column1 = c1 if c1 else Vector4D.new(0, 1, 0, 0)
	column2 = c2 if c2 else Vector4D.new(0, 0, 1, 0)
	column3 = c3 if c3 else Vector4D.new(0, 0, 0, 1)

# Static constructors
static func identity() -> Matrix4x4D:
	return Matrix4x4D.new(
		Vector4D.new(1, 0, 0, 0),
		Vector4D.new(0, 1, 0, 0),
		Vector4D.new(0, 0, 1, 0),
		Vector4D.new(0, 0, 0, 1)
	)

static func zero_matrix() -> Matrix4x4D:
	return Matrix4x4D.new(
		Vector4D.zero(),
		Vector4D.zero(),
		Vector4D.zero(),
		Vector4D.zero()
	)

static func from_godot_basis(b: Basis) -> Matrix4x4D:
	# Embed 3D rotation in 4D (W axis unchanged)
	return Matrix4x4D.new(
		Vector4D.new(b.x.x, b.x.y, b.x.z, 0),
		Vector4D.new(b.y.x, b.y.y, b.y.z, 0),
		Vector4D.new(b.z.x, b.z.y, b.z.z, 0),
		Vector4D.new(0, 0, 0, 1)
	)

static func from_quaternion(q: Quaternion) -> Matrix4x4D:
	return from_godot_basis(Basis(q))

# Indexer
func get_element(row: int, col: int) -> float:
	return get_column(col).get_component(row)

func set_element(row: int, col: int, value: float) -> void:
	get_column(col).set_component(row, value)

func get_column(index: int) -> Vector4D:
	match index:
		0: return column0
		1: return column1
		2: return column2
		3: return column3
		_: return Vector4D.zero()

func set_column(index: int, col: Vector4D) -> void:
	match index:
		0: column0 = col
		1: column1 = col
		2: column2 = col
		3: column3 = col

func get_row(index: int) -> Vector4D:
	return Vector4D.new(
		column0.get_component(index),
		column1.get_component(index),
		column2.get_component(index),
		column3.get_component(index)
	)

func set_row(index: int, row: Vector4D) -> void:
	column0.set_component(index, row.x)
	column1.set_component(index, row.y)
	column2.set_component(index, row.z)
	column3.set_component(index, row.w)

# Matrix operations
func transpose() -> Matrix4x4D:
	return Matrix4x4D.new(
		get_row(0),
		get_row(1),
		get_row(2),
		get_row(3)
	)

func multiply_vector(v: Vector4D) -> Vector4D:
	return column0.multiply(v.x).add(
		column1.multiply(v.y)).add(
		column2.multiply(v.z)).add(
		column3.multiply(v.w))

func multiply_matrix(other: Matrix4x4D) -> Matrix4x4D:
	return Matrix4x4D.new(
		multiply_vector(other.column0),
		multiply_vector(other.column1),
		multiply_vector(other.column2),
		multiply_vector(other.column3)
	)

func add_matrix(other: Matrix4x4D) -> Matrix4x4D:
	return Matrix4x4D.new(
		column0.add(other.column0),
		column1.add(other.column1),
		column2.add(other.column2),
		column3.add(other.column3)
	)

func subtract_matrix(other: Matrix4x4D) -> Matrix4x4D:
	return Matrix4x4D.new(
		column0.subtract(other.column0),
		column1.subtract(other.column1),
		column2.subtract(other.column2),
		column3.subtract(other.column3)
	)

func multiply_scalar(s: float) -> Matrix4x4D:
	return Matrix4x4D.new(
		column0.multiply(s),
		column1.multiply(s),
		column2.multiply(s),
		column3.multiply(s)
	)

# Determinant (for 4x4 matrix)
func determinant() -> float:
	# Using cofactor expansion along first row
	var a := get_element(0, 0)
	var b := get_element(0, 1)
	var c := get_element(0, 2)
	var d := get_element(0, 3)
	
	return a * _minor_3x3(0, 0) - b * _minor_3x3(0, 1) + c * _minor_3x3(0, 2) - d * _minor_3x3(0, 3)

func _minor_3x3(skip_row: int, skip_col: int) -> float:
	# Get the 3x3 minor by skipping specified row and column
	var m: Array[float] = []
	for row in range(4):
		if row == skip_row:
			continue
		for col in range(4):
			if col == skip_col:
				continue
			m.append(get_element(row, col))
	# 3x3 determinant
	return m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])

# Inverse using adjugate method
func inverse() -> Matrix4x4D:
	var det := determinant()
	if abs(det) < EPSILON:
		push_warning("Matrix4x4D.inverse(): Matrix is singular")
		return Matrix4x4D.identity()
	
	var adj := adjugate()
	return adj.multiply_scalar(1.0 / det)

func adjugate() -> Matrix4x4D:
	return cofactor().transpose()

func cofactor() -> Matrix4x4D:
	# Each element is the cofactor (signed minor)
	var result := Matrix4x4D.zero_matrix()
	for row in range(4):
		for col in range(4):
			var sign_val := 1.0 if (row + col) % 2 == 0 else -1.0
			result.set_element(row, col, sign_val * _minor_3x3(row, col))
	return result

# Trace (sum of diagonal elements)
func trace() -> float:
	return column0.x + column1.y + column2.z + column3.w

# Frobenius norm
func norm() -> float:
	var sum_sq := 0.0
	for i in range(4):
		sum_sq += get_column(i).sqr_magnitude()
	return sqrt(sum_sq)

# Outer product of two 4D vectors
static func outer(a: Vector4D, b: Vector4D) -> Matrix4x4D:
	return Matrix4x4D.new(
		a.multiply(b.x),
		a.multiply(b.y),
		a.multiply(b.z),
		a.multiply(b.w)
	)

# Scale matrix from 4D vector
static func scale_matrix(s: Vector4D) -> Matrix4x4D:
	return Matrix4x4D.new(
		Vector4D.new(s.x, 0, 0, 0),
		Vector4D.new(0, s.y, 0, 0),
		Vector4D.new(0, 0, s.z, 0),
		Vector4D.new(0, 0, 0, s.w)
	)

# Rotation in a 2D plane within 4D space
# p1 and p2 are axis indices (0=x, 1=y, 2=z, 3=w)
static func plane_rotation(angle_deg: float, p1: int, p2: int) -> Matrix4x4D:
	var cs := cos(deg_to_rad(angle_deg))
	var sn := sin(deg_to_rad(angle_deg))
	
	# Snap to exact values for common angles
	if abs(angle_deg) == 90.0 or angle_deg == 180.0 or angle_deg == 0.0:
		cs = round(cs)
		sn = round(sn)
	
	var result := Matrix4x4D.identity()
	result.set_element(p1, p1, cs)
	result.set_element(p2, p2, cs)
	result.set_element(p1, p2, sn)
	result.set_element(p2, p1, -sn)
	return result

# Rotation matrices for specific planes
static func rotation_xy(angle_deg: float) -> Matrix4x4D:
	return plane_rotation(angle_deg, 0, 1)

static func rotation_xz(angle_deg: float) -> Matrix4x4D:
	return plane_rotation(angle_deg, 0, 2)

static func rotation_xw(angle_deg: float) -> Matrix4x4D:
	return plane_rotation(angle_deg, 0, 3)

static func rotation_yz(angle_deg: float) -> Matrix4x4D:
	return plane_rotation(angle_deg, 1, 2)

static func rotation_yw(angle_deg: float) -> Matrix4x4D:
	return plane_rotation(angle_deg, 1, 3)

static func rotation_zw(angle_deg: float) -> Matrix4x4D:
	return plane_rotation(angle_deg, 2, 3)

# From-to rotation: rotate 'from' vector to 'to' vector
static func from_to_rotation(from: Vector4D, to: Vector4D) -> Matrix4x4D:
	var from_n := from.normalized()
	var to_n := to.normalized()
	var c := from_n.add(to_n)
	var mag_sq := c.sqr_magnitude()
	
	if mag_sq < EPSILON:
		# Vectors are opposite, return scale by -1
		return scale_matrix(Vector4D.new(-1, -1, -1, -1))
	
	var S := Matrix4x4D.identity().add_matrix(
		Matrix4x4D.outer(c.multiply(-2.0 / mag_sq), c)
	)
	return S.add_matrix(Matrix4x4D.outer(to_n.multiply(-2.0), S.multiply_vector(to_n)))

# Gram-Schmidt orthonormalization
func make_ortho_normal() -> Matrix4x4D:
	var w1 := column0
	var w2 := column1
	var w3 := column2
	var w4 := column3
	
	var v1 := w1
	var v2 := w2.subtract(Vector4D.project(w2, v1))
	var v3 := w3.subtract(Vector4D.project(w3, v1)).subtract(Vector4D.project(w3, v2))
	var v4 := w4.subtract(Vector4D.project(w4, v1)).subtract(Vector4D.project(w4, v2)).subtract(Vector4D.project(w4, v3))
	
	return Matrix4x4D.new(
		v1.normalized(),
		v2.normalized(),
		v3.normalized(),
		v4.normalized()
	)

# Iterative orthonormalization (faster, less accurate)
func ortho_iterate() -> Matrix4x4D:
	var m := duplicate()
	
	# Normalize columns
	for i in range(4):
		var v := m.get_column(i)
		var mag := v.magnitude()
		if mag < EPSILON:
			return m
		m.set_column(i, v.divide(mag))
	
	var mt := m.transpose().multiply_matrix(m)
	var result := Matrix4x4D.zero_matrix()
	
	for i in range(4):
		var sum_v := m.get_column(i)
		for j in range(4):
			if i != j:
				sum_v = sum_v.add(m.get_column(j).multiply(-0.5 * mt.get_element(i, j)))
		result.set_column(i, sum_v)
	
	return result

# Cayley transform for rotation interpolation
static func cayley_transform(m: Matrix4x4D) -> Matrix4x4D:
	var a := Matrix4x4D.identity().add_matrix(m.multiply_scalar(-1.0))
	var b := Matrix4x4D.identity().add_matrix(m).inverse()
	return a.multiply_matrix(b)

# Skew-symmetric matrix magnitude
func skew_symmetric_magnitude() -> float:
	var mag_sq := 0.0
	for i in range(4):
		for j in range(i + 1, 4):
			var val := get_element(i, j)
			mag_sq += val * val
	return sqrt(mag_sq)

# Spherical interpolation between rotation matrices
static func slerp(A: Matrix4x4D, B: Matrix4x4D, t: float) -> Matrix4x4D:
	var C := A.inverse().multiply_matrix(B)
	C = cayley_transform(C)
	var mag := C.skew_symmetric_magnitude()
	if mag < EPSILON:
		return A
	var mul := tan(atan(mag) * t)
	C = cayley_transform(C.multiply_scalar(mul / mag))
	return A.multiply_matrix(C)

# Near-linear slerp (faster, for small angles)
static func slerp_near(A: Matrix4x4D, B: Matrix4x4D, t: float) -> Matrix4x4D:
	var m := A.multiply_scalar(1.0 - t).add_matrix(B.multiply_scalar(t))
	# Iterate orthonormalization 3 times
	m = m.ortho_iterate()
	m = m.ortho_iterate()
	m = m.ortho_iterate()
	return m

# Rotation angles (returns two angles for 4D double rotation)
func rotation_angles() -> Vector2:
	var trace_r: float = trace()
	var tn: float = trace_r
	var tr_sq: float = multiply_matrix(self).trace()
	var delta: float = sqrt(max(2 * (tr_sq - trace_r) - (tn - 4) * (tn + 2), 0.0))
	var y1: float = clamp(0.25 * (tn - delta), -1.0, 1.0)
	var y2: float = clamp(0.25 * (tn + delta), -1.0, 1.0)
	return Vector2(rad_to_deg(acos(y1)), rad_to_deg(acos(y2)))

# Get maximum scale factor
func max_scale() -> float:
	var max_scale_sq := 0.0
	for i in range(4):
		max_scale_sq = max(max_scale_sq, get_column(i).sqr_magnitude())
	return sqrt(max_scale_sq)

# Utility
func duplicate() -> Matrix4x4D:
	return Matrix4x4D.new(
		column0.duplicate(),
		column1.duplicate(),
		column2.duplicate(),
		column3.duplicate()
	)

func _to_string() -> String:
	return "[%s\n %s\n %s\n %s]" % [get_row(0), get_row(1), get_row(2), get_row(3)]
