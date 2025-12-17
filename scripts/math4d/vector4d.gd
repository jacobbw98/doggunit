# Vector4D - 4D Vector Class for Godot
# Ported from HackerPoet's Engine4D (Vector5.cs, adapted for 4D)
# https://github.com/HackerPoet/Engine4D
class_name Vector4D
extends RefCounted

const EPSILON: float = 1e-5

var x: float
var y: float
var z: float
var w: float

# Constructors
func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0, pw: float = 0.0) -> void:
	x = px
	y = py
	z = pz
	w = pw

static func from_vector3(v: Vector3, pw: float = 0.0) -> Vector4D:
	return Vector4D.new(v.x, v.y, v.z, pw)

static func from_vector4(v: Vector4) -> Vector4D:
	return Vector4D.new(v.x, v.y, v.z, v.w)

# Static constants
static func zero() -> Vector4D:
	return Vector4D.new(0, 0, 0, 0)

static func one() -> Vector4D:
	return Vector4D.new(1, 1, 1, 1)

static func unit_x() -> Vector4D:
	return Vector4D.new(1, 0, 0, 0)

static func unit_y() -> Vector4D:
	return Vector4D.new(0, 1, 0, 0)

static func unit_z() -> Vector4D:
	return Vector4D.new(0, 0, 1, 0)

static func unit_w() -> Vector4D:
	return Vector4D.new(0, 0, 0, 1)

# Indexer
func get_component(index: int) -> float:
	match index:
		0: return x
		1: return y
		2: return z
		3: return w
		_: return 0.0

func set_component(index: int, value: float) -> void:
	match index:
		0: x = value
		1: y = value
		2: z = value
		3: w = value

# Basic properties
func magnitude() -> float:
	return sqrt(sqr_magnitude())

func sqr_magnitude() -> float:
	return x * x + y * y + z * z + w * w

func normalized() -> Vector4D:
	var mag := magnitude()
	if mag < EPSILON:
		return Vector4D.zero()
	return Vector4D.new(x / mag, y / mag, z / mag, w / mag)

func normalize() -> void:
	var mag := magnitude()
	if mag < EPSILON:
		x = 0; y = 0; z = 0; w = 0
	else:
		x /= mag; y /= mag; z /= mag; w /= mag

# Arithmetic operations
func add(other: Vector4D) -> Vector4D:
	return Vector4D.new(x + other.x, y + other.y, z + other.z, w + other.w)

func subtract(other: Vector4D) -> Vector4D:
	return Vector4D.new(x - other.x, y - other.y, z - other.z, w - other.w)

func multiply(scalar: float) -> Vector4D:
	return Vector4D.new(x * scalar, y * scalar, z * scalar, w * scalar)

func divide(scalar: float) -> Vector4D:
	if abs(scalar) < EPSILON:
		return Vector4D.zero()
	return Vector4D.new(x / scalar, y / scalar, z / scalar, w / scalar)

func negate() -> Vector4D:
	return Vector4D.new(-x, -y, -z, -w)

# Component-wise operations
func scale(other: Vector4D) -> Vector4D:
	return Vector4D.new(x * other.x, y * other.y, z * other.z, w * other.w)

static func min_components(a: Vector4D, b: Vector4D) -> Vector4D:
	return Vector4D.new(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z), min(a.w, b.w))

static func max_components(a: Vector4D, b: Vector4D) -> Vector4D:
	return Vector4D.new(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z), max(a.w, b.w))

static func sign_components(v: Vector4D) -> Vector4D:
	return Vector4D.new(sign(v.x), sign(v.y), sign(v.z), sign(v.w))

func abs_components() -> Vector4D:
	return Vector4D.new(abs(x), abs(y), abs(z), abs(w))

# Dot product
static func dot(a: Vector4D, b: Vector4D) -> float:
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w

func dot_with(other: Vector4D) -> float:
	return Vector4D.dot(self, other)

# Distance
static func distance(a: Vector4D, b: Vector4D) -> float:
	return a.subtract(b).magnitude()

static func sqr_distance(a: Vector4D, b: Vector4D) -> float:
	return a.subtract(b).sqr_magnitude()

# Interpolation
static func lerp(a: Vector4D, b: Vector4D, t: float) -> Vector4D:
	t = clamp(t, 0.0, 1.0)
	return lerp_unclamped(a, b, t)

static func lerp_unclamped(a: Vector4D, b: Vector4D, t: float) -> Vector4D:
	return a.add(b.subtract(a).multiply(t))

# Projection onto a line (1D subspace)
static func project(p: Vector4D, axis: Vector4D) -> Vector4D:
	var denom := Vector4D.dot(axis, axis)
	if denom < EPSILON:
		return Vector4D.zero()
	return axis.multiply(Vector4D.dot(p, axis) / denom)

# Projection onto a plane (2D subspace) spanned by two vectors
static func project_onto_plane(p: Vector4D, ax1: Vector4D, ax2: Vector4D) -> Vector4D:
	var d11 := Vector4D.dot(ax1, ax1)
	var d12 := Vector4D.dot(ax1, ax2)
	var d22 := Vector4D.dot(ax2, ax2)
	var dp1 := Vector4D.dot(p, ax1)
	var dp2 := Vector4D.dot(p, ax2)
	var d := d11 * d22 - d12 * d12
	if abs(d) < EPSILON:
		return Vector4D.zero()
	var t1 := (d22 * dp1 - d12 * dp2) / d
	var t2 := (d11 * dp2 - d12 * dp1) / d
	return ax1.multiply(t1).add(ax2.multiply(t2))

# Projection onto a 3D subspace spanned by three vectors
static func project_onto_3space(p: Vector4D, ax1: Vector4D, ax2: Vector4D, ax3: Vector4D) -> Vector4D:
	var d11 := Vector4D.dot(ax1, ax1)
	var d12 := Vector4D.dot(ax1, ax2)
	var d13 := Vector4D.dot(ax1, ax3)
	var d22 := Vector4D.dot(ax2, ax2)
	var d23 := Vector4D.dot(ax2, ax3)
	var d33 := Vector4D.dot(ax3, ax3)
	var dp1 := Vector4D.dot(p, ax1)
	var dp2 := Vector4D.dot(p, ax2)
	var dp3 := Vector4D.dot(p, ax3)
	var a11 := d33 * d22 - d23 * d23
	var a12 := d13 * d23 - d33 * d12
	var a13 := d12 * d23 - d13 * d22
	var a22 := d33 * d11 - d13 * d13
	var a23 := d12 * d13 - d11 * d23
	var a33 := d11 * d22 - d12 * d12
	var d := (d11 * a11) + (d12 * a12) + (d13 * a13)
	if abs(d) < EPSILON:
		return Vector4D.zero()
	var t1 := (a11 * dp1 + a12 * dp2 + a13 * dp3) / d
	var t2 := (a12 * dp1 + a22 * dp2 + a23 * dp3) / d
	var t3 := (a13 * dp1 + a23 * dp2 + a33 * dp3) / d
	return ax1.multiply(t1).add(ax2.multiply(t2)).add(ax3.multiply(t3))

# Angle between vectors (in radians)
static func angle(a: Vector4D, b: Vector4D) -> float:
	return acos(cos_angle(a, b))

static func cos_angle(a: Vector4D, b: Vector4D) -> float:
	var denom := sqrt(a.sqr_magnitude() * b.sqr_magnitude())
	if denom < EPSILON:
		return 0.0
	return clamp(Vector4D.dot(a, b) / denom, -1.0, 1.0)

# Rotate towards target (limited by max radians)
static func rotate_towards(from: Vector4D, target: Vector4D, max_radians: float) -> Vector4D:
	var min_cos := cos(max_radians)
	var cos_ang := cos_angle(from, target)
	if cos_ang >= min_cos:
		return target
	var min_sin := sin(max_radians)
	var perp := target.subtract(from.multiply(cos_ang))
	var perp_mag := perp.magnitude()
	if perp_mag <= EPSILON:
		# Vectors are nearly parallel/anti-parallel, pick arbitrary perpendicular
		perp = Vector4D.new(from.y, -from.x, from.w, -from.z)
		perp_mag = perp.magnitude()
	return from.multiply(min_cos).add(perp.multiply(min_sin / perp_mag))

# 4D Cross product equivalent: Generate normal from 3 vectors
# In 4D, the cross product of 3 vectors gives a vector perpendicular to all three
static func make_normal(a: Vector4D, b: Vector4D, c: Vector4D) -> Vector4D:
	# Using the 4D generalization of cross product via determinant expansion
	# Each component uses the 3D cross product of the remaining components
	var yzw_a := Vector3(a.y, a.z, a.w)
	var yzw_b := Vector3(b.y, b.z, b.w)
	var yzw_c := Vector3(c.y, c.z, c.w)
	
	var zwx_a := Vector3(a.z, a.w, a.x)
	var zwx_b := Vector3(b.z, b.w, b.x)
	var zwx_c := Vector3(c.z, c.w, c.x)
	
	var wxy_a := Vector3(a.w, a.x, a.y)
	var wxy_b := Vector3(b.w, b.x, b.y)
	var wxy_c := Vector3(c.w, c.x, c.y)
	
	var xyz_a := Vector3(a.x, a.y, a.z)
	var xyz_b := Vector3(b.x, b.y, b.z)
	var xyz_c := Vector3(c.x, c.y, c.z)
	
	return Vector4D.new(
		-yzw_a.dot(yzw_b.cross(yzw_c)),
		 zwx_a.dot(zwx_b.cross(zwx_c)),
		-wxy_a.dot(wxy_b.cross(wxy_c)),
		 xyz_a.dot(xyz_b.cross(xyz_c))
	)

# Conversion to Godot types
func to_vector3() -> Vector3:
	return Vector3(x, y, z)

func to_vector4() -> Vector4:
	return Vector4(x, y, z, w)

# Skip Y (for 4D -> 3D projections where Y is up)
func skip_y() -> Vector3:
	return Vector3(x, z, w)

static func insert_y(v: Vector3, py: float) -> Vector4D:
	return Vector4D.new(v.x, py, v.y, v.z)

# Utility
func is_zero() -> bool:
	return sqr_magnitude() < EPSILON * EPSILON

func is_normalized() -> bool:
	return abs(sqr_magnitude() - 1.0) < EPSILON

func equals(other: Vector4D, tolerance: float = EPSILON) -> bool:
	return subtract(other).sqr_magnitude() < tolerance * tolerance

func duplicate() -> Vector4D:
	return Vector4D.new(x, y, z, w)

func _to_string() -> String:
	return "(%0.3f, %0.3f, %0.3f, %0.3f)" % [x, y, z, w]
